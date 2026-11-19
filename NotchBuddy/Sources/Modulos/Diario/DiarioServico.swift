import SwiftUI
import Combine
import Observation

// O Diário do Hugo: o que ele pediu e recebeu das sessões, o que anotou, onde passou o tempo e —
// o coração — as pendências DELE, triadas na hora pelo modelo local e cobradas na hora certa.
//
// Tudo por evento, nada de polling (0 % de CPU parado):
//   • sessões: assinatura de `AppState.$tasks` (Combine), por diferença de pedido/entrega;
//   • app em foco: notificações do NSWorkspace (FocoApps);
//   • avisos: UM DispatchSourceTimer (relógio de parede) para a próxima pendência a vencer,
//     reagendado quando a lista muda e ao acordar o Mac;
//   • resumo do dia: UM DispatchSourceTimer para a hora do resumo.
// Gravação com folga (3 s) num JSON por dia; no modo de capturas não grava nada.

@Observable @MainActor
final class DiarioServico {
    static let shared = DiarioServico()
    static let idModulo = "diario"

    private(set) var hoje: DiaDiario
    /// Dias anteriores com pendência ainda aberta (carregados para avisar e mostrar).
    private(set) var diasAbertos: [String: DiaDiario] = [:]
    private(set) var resumindo = false
    private(set) var triando = 0
    private(set) var lendoCommits = false
    /// Pendência que o último aviso apontou: vem primeiro na aba.
    var destaque: UUID?
    /// Pendência aberta no detalhe da aba (nil = lista). Mora aqui para o aviso da barra abrir direto nela.
    var detalhe: UUID?

    @ObservationIgnored private let log = Log.de("diario")
    @ObservationIgnored private var assinaturaSessoes: AnyCancellable?
    @ObservationIgnored private var vistos: [String: (prompt: String?, entrega: String?)] = [:]
    @ObservationIgnored private var primeiraLeitura = true
    @ObservationIgnored private var iniciadoEm = Date()
    @ObservationIgnored private lazy var foco = FocoApps { [weak self] b, n, s, i in self?.somarApp(b, n, s, i) }
    @ObservationIgnored private var timerAviso: DispatchSourceTimer?
    @ObservationIgnored private var timerResumo: DispatchSourceTimer?
    @ObservationIgnored private var gravacao: DispatchWorkItem?
    @ObservationIgnored private var sujos: Set<String> = []
    @ObservationIgnored private var filaTriagem: Task<Void, Never>?
    @ObservationIgnored private var observadores: [NSObjectProtocol] = []
    @ObservationIgnored private var ligado = false
    @ObservationIgnored private let filaDisco = DispatchQueue(label: "crew.diario.disco", qos: .utility)

    private init() {
        hoje = DiaDiario(dia: FormatoDiario.dia(Date()))
    }

    // MARK: Ajustes

    func fonteLigada(_ f: FonteDiario) -> Bool { Ajustes.bool(Self.idModulo, "fonte.\(f.rawValue)", padrao: true) }

    var resumoAutomatico: Bool {
        get { Ajustes.bool(Self.idModulo, "resumoAuto", padrao: true) }
        set { Ajustes.definir(Self.idModulo, "resumoAuto", newValue); agendarResumo() }
    }

    /// Hora do resumo, em minutos desde a meia-noite (padrão 18:00).
    var horaResumo: Int {
        get { Int(Ajustes.double(Self.idModulo, "horaResumo", padrao: 18 * 60)) }
        set { Ajustes.definir(Self.idModulo, "horaResumo", Double(newValue)); agendarResumo() }
    }

    /// Minutos antes do prazo para o primeiro aviso.
    var avisoAntes: Int {
        get { Int(Ajustes.double(Self.idModulo, "avisoAntes", padrao: 15)) }
        set { Ajustes.definir(Self.idModulo, "avisoAntes", Double(newValue)); reagendarAvisos() }
    }

    // MARK: Ciclo

    func iniciar() {
        guard !ligado, !CaptureTool.ativo else { return }
        ligado = true
        carregar()
        primeiraLeitura = true
        iniciadoEm = Date()
        assinaturaSessoes = AppState.shared.$tasks
            .receive(on: DispatchQueue.main)
            .sink { [weak self] t in MainActor.assumeIsolated { self?.tarefasMudaram(t) } }
        if fonteLigada(.apps) { foco.ligar() }
        if fonteLigada(.whatsapp) { FonteWhatsApp.shared.ligar() }
        let ws = NSWorkspace.shared.notificationCenter
        observadores.append(ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                // O que venceu com o Mac dormindo avisa agora; o resumo das 18h, se perdido, sai agora
                self?.reagendarAvisos()
                self?.agendarResumo()
            }
        })
        observadores.append(NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                                                   object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.encerrar() }
        })
        reagendarAvisos()
        agendarResumo()
        log.info("diário ligado: \(self.hoje.entradas.count) entrada(s) hoje, \(self.abertas.count) pendência(s) aberta(s)")
        // Sugestões que ficaram sem resposta: o Homie pergunta de novo daqui a pouco
        if !sugeridas.isEmpty { tentarPerguntarDepois() }
    }

    func parar() {
        guard ligado else { return }
        encerrar()
        ligado = false
        FonteWhatsApp.shared.desligar()
        assinaturaSessoes = nil
        for o in observadores {
            NotificationCenter.default.removeObserver(o)
            NSWorkspace.shared.notificationCenter.removeObserver(o)
        }
        observadores.removeAll()
        timerAviso?.cancel(); timerAviso = nil
        timerResumo?.cancel(); timerResumo = nil
        Arbitro.shared.retirar("diario.aviso")
        Arbitro.shared.retirar("diario.resumo")
    }

    /// Ao sair do app: entrega o trecho do app em foco e grava já.
    private func encerrar() {
        foco.desligar()
        gravarAgora()
    }

    // MARK: Sessões (pedido e entrega por diferença)

    private func tarefasMudaram(_ tarefas: [AgentTask]) {
        let ligadaSessoes = fonteLigada(.sessoes)
        for t in tarefas where t.source == .claudeCode {
            guard let sid = t.sessionId else { continue }
            let antes = vistos[sid]
            vistos[sid] = (t.lastPrompt, t.delivery)
            guard !primeiraLeitura, ligadaSessoes else { continue }
            // Sessão que aparece agora com o último evento de antes do Crew abrir = restaurada do
            // sessoes.json: o pedido/entrega dela já aconteceu (e já foi registrado, se era de hoje)
            if antes == nil && t.lastEvent < iniciadoEm { continue }
            if let p = t.lastPrompt, p != antes?.prompt { registrarPedido(t, p) }
            if let d = t.delivery, d != antes?.entrega { registrarEntrega(t, d) }
        }
        primeiraLeitura = false
    }

    private func registrarPedido(_ t: AgentTask, _ prompt: String) {
        let texto = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        // Comandos (/clear, /compact) e mensagens de sistema não são pedidos
        guard !texto.isEmpty, !texto.hasPrefix("/"), !texto.hasPrefix("<") else { return }
        let e = entrada(.pedido, String(texto.prefix(600)), t)
        adicionar(e)
        // Ele respondeu à sessão: o que ela esperava dele está resolvido
        fecharEsperando(sessaoId: t.sessionId, motivo: "você respondeu à sessão às \(FormatoDiario.hora(e.hora))")
        // Pedido a um agente quase sempre é instrução para o agente. Só vai à triagem quando o
        // Hugo fala de algo que ELE vai fazer ("depois eu ligo pro Rafa", "vou mandar a proposta").
        if Self.falaDeSi(texto) {
            let antes = hoje.entradas.filter { $0.sessaoId == t.sessionId && $0.id != e.id && ($0.tipo == .pedido || $0.tipo == .entrega) }
            let falas = antes.suffix(4).map { ContextoTriagem.Fala(quem: $0.tipo == .pedido ? "\(Usuario.nome)" : "Agente", hora: $0.hora, texto: $0.texto) }
            triar(e, texto: texto, origem: .pedido,
                  contexto: contexto(falas, abertas: abertas.filter { $0.sessaoId == t.sessionId }, origem: .pedido))
        }
    }

    private func registrarEntrega(_ t: AgentTask, _ entrega: String) {
        guard var brief = t.brief, !brief.isEmpty else { return }
        if t.state == .error { brief = "Erro: " + brief }
        let e = entrada(.entrega, brief, t)
        adicionar(e)
        // A sessão falou de novo: a espera anterior dela é substituída pela triagem desta entrega
        fecharEsperando(sessaoId: t.sessionId, motivo: "a sessão respondeu de novo às \(FormatoDiario.hora(e.hora))")
        // Entrega de sessão não vira pendência (decisão do Hugo, 2026-10-05): decidir/aprovar/dar o
        // OK já tem o aviso da sessão. Pendência é o que ele vai parar para fazer no mundo real.
    }

    static func falaDeSi(_ texto: String) -> Bool {
        let t = texto.lowercased()
        let verbos = "ligar|mandar|enviar|falar|passar|pagar|comprar|marcar|responder|levar|buscar|conversar|avisar|cobrar|agendar|ir|visitar|entregar"
        let padrao = #"\b(depois eu|amanhã eu|(eu )?vou|preciso|tenho (que|de)) ("# + verbos + #")\b"#
        return t.range(of: padrao, options: .regularExpression) != nil
    }

    private func entrada(_ tipo: TipoEntrada, _ texto: String, _ t: AgentTask) -> EntradaDiario {
        EntradaDiario(hora: Date(), tipo: tipo, texto: texto, projeto: Projetos.nome(de: t.sessionCwd),
                      raiz: Projetos.raiz(de: t.sessionCwd), cor: Projetos.cor(de: t.sessionCwd),
                      sessao: t.title, sessaoId: t.sessionId)
    }

    // MARK: Notas

    func adicionarNota(_ texto: String) {
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, fonteLigada(.notas) else { return }
        let e = EntradaDiario(hora: Date(), tipo: .nota, texto: String(t.prefix(1000)))
        adicionar(e)
        triar(e, texto: t, origem: .nota, contexto: contexto(abertas: abertas, origem: .nota))
    }

    /// Conversa do WhatsApp que mexeu (o Hugo prometeu algo, ou alguém respondeu numa conversa
    /// que tem pendência aberta): vai à triagem INTEIRA — a janela recente, os dois lados — com as
    /// pendências abertas dela, para valer o combinado atual (horário remarcado muda a pendência,
    /// não cria outra). Nada da conversa é guardado: só a pendência, com o assunto.
    /// `fim` roda quando a triagem terminou (a fonte só marca como lido depois disso).
    func conversaWhatsApp(_ msgs: [MensagemWA], fim: (@MainActor () -> Void)? = nil) {
        guard ligado, fonteLigada(.whatsapp), let ultima = msgs.last else { fim?(); return }
        let nome = ultima.conversa
        // Sem sugestão do WhatsApp: só vale triar conversa que já tem task aberta (o combinado
        // remarcado ainda atualiza a task); o resto nem passa pelo modelo
        if !Self.sugerirDoWhatsApp,
           !pendencias.contains(where: { $0.aberta && $0.origem == .whatsapp && $0.sessao == nome }) { fim?(); return }
        let contato = nome.map { ultima.grupo ? "o grupo \($0)" : $0 } ?? "um contato"
        let falas = msgs.map { m in
            ContextoTriagem.Fala(quem: m.deMim ? "\(Usuario.nome)" : (ultima.grupo ? "Alguém do grupo" : (nome ?? "Contato")), hora: m.data, texto: m.texto)
        }
        // A última mensagem do Hugo é a "origem" que a pendência mostra no detalhe
        // A origem que o detalhe mostra: a mensagem mais nova, de quem for ("Diego: dá um pulo aqui")
        let autor = ultima.deMim ? "Você" : (ultima.grupo ? "Alguém do grupo" : (nome.map { n in
            n.filter(\.isNumber).count >= 7 ? "Contato" : (n.split(separator: " ").first.map(String.init) ?? n) } ?? "Contato"))
        let e = EntradaDiario(hora: ultima.data, tipo: .whatsapp, texto: "\(autor): \(ultima.texto.prefix(280))", sessao: nome)
        let daConversa = pendencias.filter { ($0.aberta || $0.estado == .sugerida) && $0.origem == .whatsapp && $0.sessao == nome }
        triar(e, texto: "Conversa com \(contato). Mensagem mais nova: \(ultima.deMim ? "\(Usuario.nome)" : contato): \(ultima.texto.prefix(500))",
              origem: .whatsapp, contexto: contexto(falas, abertas: daConversa), fim: fim)
    }

    // MARK: "Vira task?" — o Homie pergunta

    /// Desligado por ora (atrapalhava mais que ajudava): o WhatsApp não sugere task nova e as
    /// sugestões dele que já estavam na fila ficam guardadas, sem perguntar. `true` volta tudo.
    static let sugerirDoWhatsApp = false

    /// As que esperam resposta, a mais antiga primeiro.
    var sugeridas: [Pendencia] {
        pendencias.filter { $0.estado == .sugerida && (Self.sugerirDoWhatsApp || $0.origem != .whatsapp) }
            .sorted { $0.criadaEm < $1.criadaEm }
    }
    var perguntando: Pendencia? { sugeridas.first }

    /// Abre o card de pergunta na ilha (como a pergunta de uma sessão). Se o Hugo está no meio
    /// de outra coisa (chat, aprovação), espera e tenta de novo.
    func perguntar() {
        guard let _ = perguntando, !CaptureTool.ativo else { return }
        let st = AppState.shared
        if st.mode == .expanded, [.approval, .question, .prompt, .mail, .upload, .sugestao].contains(st.view) {
            if st.view != .sugestao { tentarPerguntarDepois() }
            return
        }
        if !st.pendingApprovals.isEmpty { tentarPerguntarDepois(); return }
        if st.mode == .expanded, st.vistaAntesDoAlerta == nil { st.vistaAntesDoAlerta = (st.view, st.chatSelection) }
        st.isPinned = true
        if st.mode == .expanded { st.view = .sugestao } else { NotificationCenter.default.post(name: .hookExpand, object: IslandView.sugestao) }
    }

    private var perguntaAgendada: DispatchWorkItem?
    private func tentarPerguntarDepois() {
        perguntaAgendada?.cancel()
        let item = DispatchWorkItem { MainActor.assumeIsolated { DiarioServico.shared.perguntar() } }
        perguntaAgendada = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: item)
    }

    /// "Sim": vira task com o prazo escolhido (nil = sem prazo; .none = o sugerido).
    func confirmar(_ id: UUID, prazo: Date?? = .none) {
        guard let p = pendencias.first(where: { $0.id == id }) else { return }
        Aprendizado.shared.registrar(p, virou: true)
        mudar(id) { q in
            q.estado = .aberta
            if let novo = prazo { q.prazo = novo }
            q.urgencia = Self.urgencia(prazo: q.prazo, sugerida: q.urgencia, tipo: .tarefa, agora: Date())
            q.avisos = []
        }
        gravarDepois()
        reagendarAvisos()
        proximaPergunta()
    }

    /// "Não é task": sai e ensina.
    func recusar(_ id: UUID) {
        guard let p = pendencias.first(where: { $0.id == id }) else { return }
        Aprendizado.shared.registrar(p, virou: false)
        mudar(id) { $0.estado = .ignorada; $0.resolvidaEm = Date(); $0.motivo = "você disse que não é task" }
        gravarDepois()
        proximaPergunta()
    }

    /// Altura do "Vira task?" aberto (rolar para baixo ou "Entender").
    static let alturaPergunta: CGFloat = 400

    /// Abre o detalhe da sugestão: por que, o que você escreveu, a conversa do momento.
    func detalharPergunta() {
        let st = AppState.shared
        guard st.mode == .expanded, st.view == .sugestao else { return }
        st.alturaAba = min(Self.alturaPergunta, st.alturaAbaMaxima)
    }

    func recolherPergunta() { AppState.shared.alturaAba = nil }

    /// O Hugo corrigiu o título antes de responder.
    func renomearSugestao(_ id: UUID, _ titulo: String) {
        let t = titulo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        mudar(id) { if $0.acao != t { $0.acao = t; $0.curta = nil } }
        gravarDepois()
    }

    /// "Depois": fecha o card; ela fica em "a confirmar" na aba.
    func perguntarDepois() { soltarPergunta() }

    private func proximaPergunta() {
        if perguntando != nil, AppState.shared.view == .sugestao { return }   // o card mostra a próxima
        soltarPergunta()
    }

    private func soltarPergunta() {
        let st = AppState.shared
        st.alturaAba = nil
        st.isPinned = false
        let antes = st.vistaAntesDoAlerta
        st.vistaAntesDoAlerta = nil
        guard st.mode == .expanded, st.view == .sugestao else { return }
        if let antes {
            if antes.view == .prompt { st.openChat(antes.chat) } else { st.view = antes.view }
        } else {
            NotificationCenter.default.post(name: .islandCollapse, object: nil)
        }
    }

    /// Nomes das conversas do WhatsApp com pendência aberta (a fonte relê essas quando o outro responde).
    var conversasComPendencia: Set<String> {
        Set(abertas.filter { $0.origem == .whatsapp }.compactMap(\.sessao))
    }

    /// Contexto padrão de toda triagem: a conversa, as pendências dela e o critério aprendido.
    private func contexto(_ falas: [ContextoTriagem.Fala] = [], abertas: [Pendencia], origem: TipoEntrada = .whatsapp) -> ContextoTriagem {
        let ex = Aprendizado.shared.exemplos(origem)
        return ContextoTriagem(conversa: falas, abertas: abertas.prefix(8).map { .init(id: $0.id, acao: $0.acao, prazo: $0.prazo) },
                               naoEram: ex.nao, eram: ex.sim)
    }

    /// Só notas (o resto é registro do que aconteceu).
    func apagarEntrada(_ id: UUID, dia: String) {
        if dia == hoje.dia {
            hoje.entradas.removeAll { $0.id == id && $0.tipo == .nota }
            hoje.pendencias.removeAll { $0.entradaId == id }
            sujos.insert(hoje.dia)
            gravarDepois()
            reagendarAvisos()
        } else {
            alterarArquivo(dia) { d in
                d.entradas.removeAll { $0.id == id && $0.tipo == .nota }
                d.pendencias.removeAll { $0.entradaId == id }
            }
            diasAbertos[dia]?.pendencias.removeAll { $0.entradaId == id }
        }
    }

    private func adicionar(_ e: EntradaDiario) {
        garantirHoje()
        hoje.entradas.append(e)
        sujos.insert(hoje.dia)
        gravarDepois()
    }

    // MARK: Triagem (modelo local) → pendências

    private func triar(_ e: EntradaDiario, texto: String, origem: OrigemTriagem, contexto: ContextoTriagem = .vazio,
                       fim: (@MainActor () -> Void)? = nil) {
        let anterior = filaTriagem
        triando += 1
        filaTriagem = Task { [weak self] in
            await anterior?.value
            let itens = await TriagemIA.triar(texto, origem: origem, hora: e.hora, contexto: contexto, usarIA: IAdoMac.disponivel)
            guard let self else { return }
            self.triando -= 1
            defer { fim?() }
            for r in itens {
                if origem == .whatsapp {
                    // Mensagem do WhatsApp: nada de texto no log
                    self.log.info("triagem [whatsapp] \(r.tipo.rawValue, privacy: .public) · IA \(r.comIA)")
                } else {
                    self.log.info("triagem [\(origem.rawValue, privacy: .public)] \(r.tipo.rawValue, privacy: .public): \(r.acao, privacy: .public) · prazo \(r.trechoPrazo ?? "-", privacy: .public) · \(r.urgencia.rawValue, privacy: .public) · IA \(r.comIA)")
                }
                if let k = r.atualiza, k <= contexto.abertas.count, r.ehPendencia {
                    self.atualizarPendencia(contexto.abertas[k - 1].id, e, r)
                } else {
                    self.criarPendencia(e, r)
                }
            }
        }
    }

    /// A conversa mudou um combinado que já é pendência (novo horário, título melhor): muda a
    /// mesma pendência em vez de criar outra. O Hugo vê o novo horário; os avisos recomeçam.
    private func atualizarPendencia(_ id: UUID, _ e: EntradaDiario, _ r: Triagem) {
        guard let atual = pendencias.first(where: { $0.id == id }), atual.aberta || atual.estado == .sugerida else { criarPendencia(e, r); return }
        // A hora do título manda quando o trecho do prazo não veio ("Reunião com Pedro às 14h")
        let prazo = r.trechoPrazo.flatMap { Prazos.resolver($0, desde: e.hora) }
            ?? Prazos.resolver(r.acao, desde: e.hora) ?? atual.prazo
        let mudouPrazo = prazo != atual.prazo
        mudar(id) { p in
            if !r.acao.isEmpty { p.acao = r.acao; p.curta = r.curta.isEmpty ? TriagemIA.curtaValida("", acao: r.acao) : r.curta }
            if let a = r.assunto { p.assunto = a }
            if let q = r.porque { p.porque = q }
            if p.pessoa == nil { p.pessoa = r.pessoa }
            p.prazo = prazo
            p.urgencia = Self.urgencia(prazo: prazo, sugerida: r.urgencia, tipo: r.tipo, agora: e.hora)
            if mudouPrazo { p.avisos = [] }
        }
        log.info("pendência atualizada pela conversa\(mudouPrazo ? " (prazo novo)" : "", privacy: .public)")
        gravarDepois()
        reagendarAvisos()
    }

    private func criarPendencia(_ e: EntradaDiario, _ r: Triagem) {
        var r = r
        // Nota com prazo que dá para calcular é lembrete, mesmo que o modelo ache que é registro
        if !r.ehPendencia, e.tipo == .nota, Prazos.resolver(e.texto, desde: e.hora) != nil {
            r.tipo = .tarefa
            if r.acao.isEmpty { r.acao = TriagemIA.curto(e.texto, 80) }
        }
        guard r.ehPendencia, ligado || CaptureTool.ativo else { return }
        guard fonteLigada(e.tipo.fonte) else { return }
        garantirHoje()
        // A entrada pode ter sido apagada enquanto o modelo pensava
        guard e.tipo == .whatsapp || hoje.entradas.contains(where: { $0.id == e.id }) else { return }
        let acao = r.acao.isEmpty ? TriagemIA.curto(e.texto, 80) : r.acao
        // Já existe a mesma pendência aberta: não duplica
        let n = Prazos.normalizar(acao)
        if pendencias.contains(where: { ($0.aberta || $0.estado == .sugerida) && Prazos.normalizar($0.acao) == n }) { return }
        // O que o Hugo já resolveu (feito ou ignorado) não volta ao reler a mesma conversa
        if e.tipo == .whatsapp, pendencias.contains(where: { !$0.aberta && $0.sessao == e.sessao && Prazos.normalizar($0.acao) == n }) { return }

        var prazo = r.trechoPrazo.flatMap { Prazos.resolver($0, desde: e.hora) }
        if prazo == nil, r.tipo == .compromisso { prazo = Prazos.resolver(acao, desde: e.hora) }
        if prazo == nil, e.tipo == .nota { prazo = Prazos.resolver(e.texto, desde: e.hora) }
        // WhatsApp lido depois (ex.: as últimas 24 h ao ligar): promessa cujo prazo já passou não
        // vira cobrança de algo que já aconteceu
        if e.tipo == .whatsapp, let pz = prazo, pz < Date() { return }
        let urg = Self.urgencia(prazo: prazo, sugerida: r.urgencia, tipo: r.tipo, agora: e.hora)

        var p = Pendencia(criadaEm: e.hora, dia: hoje.dia, origem: e.tipo, entradaId: e.id,
                          textoOrigem: TriagemIA.curto(e.texto, 140), acao: acao,
                          curta: r.curta.isEmpty ? TriagemIA.curtaValida("", acao: acao) : r.curta, pessoa: r.pessoa,
                          assunto: r.assunto, porque: r.porque, prazo: prazo, urgencia: urg, sessaoId: e.sessaoId, sessao: e.sessao,
                          projeto: e.projeto, comIA: r.comIA)
        // Veio sozinho (WhatsApp, sessão): o Homie pergunta antes. O que o Hugo já recusou várias
        // vezes, parecido, nem pergunta. Nota é ele mesmo escrevendo: vira task direto.
        if e.tipo != .nota {
            if e.tipo == .whatsapp, !Self.sugerirDoWhatsApp { return }
            if Aprendizado.shared.recusadoAntes(acao, assunto: r.assunto, origem: e.tipo) {
                log.info("sugestão descartada: parecida com o que já foi recusado")
                return
            }
            p.estado = .sugerida
            hoje.pendencias.append(p)
            sujos.insert(hoje.dia)
            gravarDepois()
            perguntar()
            return
        }
        // Para agora: avisa já (e não repete o "faltam 15 min")
        let avisarJa = urg == .agora
        if avisarJa { p.avisos.append("agora") }
        hoje.pendencias.append(p)
        sujos.insert(hoje.dia)
        gravarDepois()
        if avisarJa { avisar(p, .agora) }
        reagendarAvisos()
    }

    /// Prazo manda: em até 1 h → agora; hoje → hoje; depois → sem pressa. Sem prazo, vale a do
    /// modelo — sessão esperando é "hoje" (nunca grita sozinha).
    static func urgencia(prazo: Date?, sugerida: Urgencia, tipo: Triagem.Tipo, agora: Date) -> Urgencia {
        if let p = prazo {
            if p.timeIntervalSince(agora) <= 3600 { return .agora }
            return Calendar.current.isDate(p, inSameDayAs: agora) ? .hoje : .semPressa
        }
        if tipo == .esperando { return .hoje }
        return sugerida
    }

    private func fecharEsperando(sessaoId: String?, motivo: String) {
        guard let sid = sessaoId else { return }
        for p in abertas where p.sessaoId == sid && p.origem == .entrega {
            mudar(p.id) { $0.estado = .feita; $0.resolvidaEm = Date(); $0.motivo = motivo }
        }
    }

    // MARK: Pendências — leitura e as 3 saídas

    /// Todas as conhecidas: as de hoje (qualquer estado) e as abertas de dias anteriores.
    var pendencias: [Pendencia] {
        hoje.pendencias + diasAbertos.values.flatMap { $0.pendencias.filter { $0.aberta || $0.estado == .sugerida } }
    }

    /// Abertas, a mais urgente primeiro: a do aviso, depois as que vencem antes, depois "agora/hoje".
    var abertas: [Pendencia] {
        pendencias.filter(\.aberta).sorted { a, b in
            if a.id == destaque { return true }
            if b.id == destaque { return false }
            switch (a.vence, b.vence) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default:
                let o: [Urgencia] = [.agora, .hoje, .semPressa]
                let ia = o.firstIndex(of: a.urgencia) ?? 2, ib = o.firstIndex(of: b.urgencia) ?? 2
                return ia != ib ? ia < ib : a.criadaEm > b.criadaEm
            }
        }
    }

    func feito(_ id: UUID) {
        if let p = pendencias.first(where: { $0.id == id }), p.manual != true { Aprendizado.shared.registrar(p, virou: true) }
        mudar(id) { $0.estado = .feita; $0.resolvidaEm = Date(); $0.motivo = nil }
        resolvida(id)
    }

    func ignorar(_ id: UUID) {
        if let p = pendencias.first(where: { $0.id == id }), p.manual != true { Aprendizado.shared.registrar(p, virou: false) }
        mudar(id) { $0.estado = .ignorada; $0.resolvidaEm = Date(); $0.motivo = nil }
        resolvida(id)
    }

    /// O Hugo corrigiu a pendência no detalhe: texto e/ou prazo. Prazo novo reagenda os avisos.
    func editar(_ id: UUID, acao: String? = nil, prazo: Date?? = nil) {
        mudar(id) { p in
            if let a = acao?.trimmingCharacters(in: .whitespacesAndNewlines), !a.isEmpty, a != p.acao {
                p.acao = a
                p.curta = nil
            }
            if let novo = prazo {
                p.prazo = novo
                p.avisos = []
                if p.estado == .adiada { p.estado = .aberta; p.adiadaAte = nil }
            }
        }
        reagendarAvisos()
    }

    // MARK: Ilha expandida (o Diário inteiro)

    enum Segmento: String, CaseIterable, Identifiable {
        case pendencias = "Pendências", hoje = "Hoje", resumo = "Resumo"
        var id: String { rawValue }
    }
    /// Segmento da ilha expandida e a entrada aberta nele (a aba normal abre direto numa entrada).
    var segmento: Segmento = .pendencias
    var entradaAberta: UUID?
    static let alturaExpandida: CGFloat = 450

    func expandir(_ seg: Segmento? = nil, entrada: UUID? = nil) {
        if let seg { segmento = seg }
        entradaAberta = entrada
        DiarioModulo.shared.pedirAlturaAba(Self.alturaExpandida)
    }

    func recolher() {
        entradaAberta = nil
        DiarioModulo.shared.pedirAlturaAba(nil)
    }

    /// O Hugo corrigiu uma nota de hoje. A pendência que veio dela continua como estava.
    func editarNota(_ id: UUID, texto: String) {
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let i = hoje.entradas.firstIndex(where: { $0.id == id && $0.tipo == .nota }),
              hoje.entradas[i].texto != t else { return }
        hoje.entradas[i].texto = String(t.prefix(1000))
        sujos.insert(hoje.dia)
        gravarDepois()
    }

    /// Pendência aberta que nasceu desta entrada (se houver).
    func pendencia(daEntrada id: UUID) -> Pendencia? {
        pendencias.first { $0.entradaId == id && $0.aberta }
    }

    /// Qualquer entrada vira pendência num clique, com ou sem prazo (o Hugo decide; sem modelo).
    func virarPendencia(_ e: EntradaDiario, prazo: Date?) {
        garantirHoje()
        guard pendencia(daEntrada: e.id) == nil else { return }
        let acao = TriagemIA.curto(e.texto, 80)
        let agora = Date()
        let p = Pendencia(criadaEm: e.hora, dia: hoje.dia, origem: e.tipo, entradaId: e.id,
                          textoOrigem: TriagemIA.curto(e.texto, 140), acao: acao,
                          curta: TriagemIA.curtaValida("", acao: acao), pessoa: nil, prazo: prazo,
                          urgencia: Self.urgencia(prazo: prazo, sugerida: .semPressa, tipo: .tarefa, agora: agora),
                          sessaoId: e.sessaoId, sessao: e.sessao, projeto: e.projeto, comIA: false, manual: true)
        hoje.pendencias.append(p)
        sujos.insert(hoje.dia)
        gravarDepois()
        reagendarAvisos()
    }

    /// Atualizações em andamento (id da task) — o detalhe mostra "pensando…".
    var atualizando: Set<UUID> = []
    /// O que a última atualização fez, para o detalhe mostrar ("Feita · nova: Fazer o relatório").
    var resultadoAtualizacao: [UUID: String] = [:]

    /// "O que aconteceu?": a frase do Hugo fica no dia (como nota ligada à task) e o modelo local
    /// traduz em mudanças — feita/continua/ignorada, título e prazo novos, tasks novas. As novas são
    /// dele mesmo, então nascem abertas (sem "Vira task?").
    func atualizar(_ id: UUID, contando texto: String) {
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let p = pendencias.first(where: { $0.id == id }) else { return }
        garantirHoje()
        let e = EntradaDiario(hora: Date(), tipo: .nota, texto: "Sobre \u{201C}\(p.acao)\u{201D}: \(t)")
        adicionar(e)
        atualizando.insert(id)
        Task { [weak self] in
            let r = await InterpretarAtualizacao.interpretar(t, tarefa: p.acao, assunto: p.assunto, hora: e.hora)
            guard let self else { return }
            self.atualizando.remove(id)
            var feito: [String] = []
            switch r.estado {
            case .feita:
                self.mudar(id) { $0.estado = .feita; $0.resolvidaEm = Date(); $0.motivo = "você contou: \(TriagemIA.curto(t, 120))" }
                Aprendizado.shared.registrar(p, virou: true)
                feito.append("Feita")
            case .ignorada:
                self.mudar(id) { $0.estado = .ignorada; $0.resolvidaEm = Date(); $0.motivo = "você contou: \(TriagemIA.curto(t, 120))" }
                feito.append("Não precisa mais")
            case .continua:
                let prazo = r.trechoPrazo.flatMap { Prazos.resolver($0, desde: e.hora) }
                self.mudar(id) { q in
                    if let n = r.novoTitulo { q.acao = n; q.curta = nil }
                    if let pz = prazo { q.prazo = pz; q.avisos = []; q.estado = .aberta; q.adiadaAte = nil }
                }
                if r.novoTitulo != nil { feito.append("Título novo") }
                if let pz = prazo { feito.append("prazo \(FormatoDiario.quando(pz))") }
                if feito.isEmpty { feito.append("Anotado") }
            }
            for n in r.novas {
                let pz = n.trechoPrazo.flatMap { Prazos.resolver($0, desde: e.hora) }
                let nova = Pendencia(criadaEm: e.hora, dia: self.hoje.dia, origem: .nota, entradaId: e.id,
                                     textoOrigem: TriagemIA.curto(t, 140), acao: n.titulo,
                                     curta: TriagemIA.curtaValida("", acao: n.titulo), pessoa: p.pessoa,
                                     assunto: p.assunto, prazo: pz,
                                     urgencia: Self.urgencia(prazo: pz, sugerida: .semPressa, tipo: .tarefa, agora: e.hora),
                                     comIA: r.comIA, manual: true)
                self.hoje.pendencias.append(nova)
                feito.append("nova: \(n.titulo)")
            }
            self.resultadoAtualizacao[id] = feito.joined(separator: " · ")
            self.sujos.insert(self.hoje.dia)
            self.gravarDepois()
            self.reagendarAvisos()
            self.log.info("atualização contada: \(r.estado.rawValue, privacy: .public), \(r.novas.count) nova(s) · IA \(r.comIA)")
        }
    }

    func reabrir(_ id: UUID) {
        mudar(id) { $0.estado = .aberta; $0.resolvidaEm = nil; $0.motivo = nil; $0.adiadaAte = nil }
        reagendarAvisos()
    }

    enum Adiamento: String, CaseIterable, Identifiable {
        case meiaHora = "30 min", umaHora = "1 h", amanha = "Amanhã"
        var id: String { rawValue }
        func data(_ agora: Date = Date()) -> Date {
            switch self {
            case .meiaHora: return agora.addingTimeInterval(30 * 60)
            case .umaHora: return agora.addingTimeInterval(3600)
            case .amanha:
                let cal = Calendar.current
                let d = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: agora)) ?? agora
                return cal.date(bySettingHour: 9, minute: 0, second: 0, of: d) ?? d
            }
        }
    }

    func adiar(_ id: UUID, _ a: Adiamento) {
        let ate = a.data()
        mudar(id) { $0.estado = .adiada; $0.adiadaAte = ate }
        resolvida(id)
    }

    private func resolvida(_ id: UUID) {
        if destaque == id {
            destaque = nil
            Arbitro.shared.retirar("diario.aviso")
        }
        reagendarAvisos()
    }

    /// Muda uma pendência onde ela mora (hoje ou um dia anterior) e marca o dia para gravar.
    private func mudar(_ id: UUID, _ f: (inout Pendencia) -> Void) {
        if let i = hoje.pendencias.firstIndex(where: { $0.id == id }) {
            f(&hoje.pendencias[i])
            sujos.insert(hoje.dia)
        } else {
            for (dia, var d) in diasAbertos {
                guard let i = d.pendencias.firstIndex(where: { $0.id == id }) else { continue }
                f(&d.pendencias[i])
                diasAbertos[dia] = d
                sujos.insert(dia)
                break
            }
        }
        gravarDepois()
    }

    // MARK: Avisos na hora certa (um timer só)

    enum TipoAviso { case antes, prazo, agora, volta }

    private func reagendarAvisos() {
        timerAviso?.cancel()
        timerAviso = nil
        guard ligado || CaptureTool.ativo else { return }
        let agora = Date()
        // 1. O que já venceu (inclusive com o Mac dormindo): marca e avisa só o mais recente
        var vencidos: [(Date, Pendencia, TipoAviso)] = []
        for p in abertas {
            for (quando, chave, tipo) in eventos(p) where quando <= agora {
                mudar(p.id) { $0.avisos.append(chave) }
                if tipo == .volta { mudar(p.id) { $0.estado = .aberta } }
                vencidos.append((quando, p, tipo))
            }
        }
        if let ultimo = vencidos.max(by: { $0.0 < $1.0 }) {
            // "faltam 15 min" que venceu há muito (Mac dormindo) não faz sentido: vira o do prazo
            avisar(pendencias.first { $0.id == ultimo.1.id } ?? ultimo.1, ultimo.2)
        }
        // 2. O próximo
        let proximo = abertas.flatMap { p in eventos(p).map { $0.0 } }.filter { $0 > agora }.min()
        guard let alvo = proximo else { return }
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(wallDeadline: .now() + max(0.5, alvo.timeIntervalSinceNow), leeway: .seconds(2))
        t.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.reagendarAvisos() } }
        t.resume()
        timerAviso = t
    }

    /// Os avisos que ainda faltam dar para uma pendência: (quando, chave, tipo).
    private func eventos(_ p: Pendencia) -> [(Date, String, TipoAviso)] {
        if p.estado == .adiada, let a = p.adiadaAte {
            let k = "volta-\(Int(a.timeIntervalSince1970))"
            return p.avisos.contains(k) ? [] : [(a, k, .volta)]
        }
        guard p.estado == .aberta, let prazo = p.prazo else { return [] }
        var r: [(Date, String, TipoAviso)] = []
        let antes = prazo.addingTimeInterval(-Double(avisoAntes) * 60)
        let jaPrazo = p.avisos.contains("prazo")
        if !jaPrazo, !p.avisos.contains("antes"), !p.avisos.contains("agora"), antes > p.criadaEm, antes < prazo,
           Date() < prazo {
            r.append((antes, "antes", .antes))
        }
        if !jaPrazo { r.append((prazo, "prazo", .prazo)) }
        return r
    }

    private func avisar(_ p: Pendencia, _ tipo: TipoAviso) {
        destaque = p.id
        let h = p.prazo.map { FormatoDiario.hora($0) } ?? ""
        let (quando, cor): (String, String) = {
            switch tipo {
            case .antes: return ("\(h) · em \(avisoAntes) min", "#F5A524")
            case .prazo: return ("agora · \(h)", "#F4505E")
            case .agora: return ("pra já", "#F4505E")
            case .volta: return ("voltou", "#F5A524")
            }
        }()
        let aviso = AvisoDiario(acao: p.acaoCurta, quando: quando, origem: Self.deOnde(p), cor: Color(hex: cor))
        Arbitro.shared.publicar(Sinal(id: "diario.aviso", lugar: .barra, prioridade: .alerta,
                                      duracao: tipo == .antes ? 90 : 900, clicavel: true, conteudo: AnyView(aviso)))
        NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.surprised)
        log.info("aviso \(String(describing: tipo), privacy: .public): \(p.acao, privacy: .public)")
    }

    /// De onde veio, com a hora ("você anotou às 11:40").
    static func deOnde(_ p: Pendencia) -> String {
        let h = FormatoDiario.quando(p.criadaEm)
        switch p.origem {
        case .nota: return "você anotou \(Calendar.current.isDateInToday(p.criadaEm) ? "às " : "")\(h)"
        case .pedido: return "você disse \(p.sessao.map { "na sessão \($0) " } ?? "")\(Calendar.current.isDateInToday(p.criadaEm) ? "às " : "")\(h)"
        case .entrega: return "\(p.sessao ?? p.projeto ?? "a sessão") espera você desde \(h)"
        case .whatsapp: return "você disse \(p.sessao.map { "a \($0) " } ?? "")no WhatsApp \(Calendar.current.isDateInToday(p.criadaEm) ? "às " : "")\(h)"
        }
    }

    /// A aba abriu: o aviso cumpriu o papel.
    func abaVista() {
        Arbitro.shared.retirar("diario.aviso")
    }

    // MARK: App em foco

    private func somarApp(_ bundle: String, _ nome: String, _ s: Double, _ inicio: Date) {
        guard fonteLigada(.apps) else { return }
        let dia = FormatoDiario.dia(inicio)
        if dia == hoje.dia {
            hoje.apps[bundle, default: TempoApp(nome: nome, segundos: 0)].segundos += s
            sujos.insert(dia)
            gravarDepois()
        } else if dia < hoje.dia {
            alterarArquivo(dia) { $0.apps[bundle, default: TempoApp(nome: nome, segundos: 0)].segundos += s }
        } else {
            garantirHoje()
            somarApp(bundle, nome, s, inicio)
        }
    }

    /// Tempo por app de hoje, com o trecho em curso (sem gravar).
    var appsHoje: [(bundle: String, nome: String, segundos: Double)] {
        var a = hoje.apps
        if let t = foco.trechoAtual, ligado { a[t.bundle, default: TempoApp(nome: t.nome, segundos: 0)].segundos += t.segundos }
        return a.map { ($0.key, $0.value.nome, $0.value.segundos) }.sorted { $0.segundos > $1.segundos }
    }

    // MARK: Resumo do dia

    private func agendarResumo() {
        timerResumo?.cancel()
        timerResumo = nil
        guard ligado, resumoAutomatico else { return }
        let cal = Calendar.current
        let agora = Date()
        let h = horaResumo
        guard var alvo = cal.date(bySettingHour: h / 60, minute: h % 60, second: 0, of: agora) else { return }
        // Já passou: se hoje ainda não teve resumo depois da hora (Mac dormindo às 18h), faz agora
        if alvo <= agora {
            if precisaResumoAutomatico(alvo) { Task { await resumir(automatico: true) } }
            alvo = cal.date(byAdding: .day, value: 1, to: alvo) ?? alvo
        }
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(wallDeadline: .now() + max(1, alvo.timeIntervalSinceNow), leeway: .seconds(30))
        t.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.precisaResumoAutomatico(alvo) { Task { await self.resumir(automatico: true) } }
                self.agendarResumo()
            }
        }
        t.resume()
        timerResumo = t
    }

    private func precisaResumoAutomatico(_ hora: Date) -> Bool {
        garantirHoje()
        guard Calendar.current.isDateInToday(hora), !hoje.entradas.isEmpty || !hoje.apps.isEmpty else { return false }
        if let r = hoje.resumo, r.geradoEm >= hora { return false }
        return true
    }

    func resumir(automatico: Bool = false) async {
        guard !resumindo else { return }
        resumindo = true
        defer { resumindo = false }
        garantirHoje()
        if ligado { foco.consolidar() }
        if fonteLigada(.commits) { await lerCommits() }
        let dia = hoje
        let feitoIA = await TriagemIA.feito(Self.compactar(dia))
        let feito = feitoIA ?? Self.feitoSemIA(dia)
        let r = ResumoDiario(geradoEm: Date(), feito: feito, aberto: aberto(dia), prometido: prometido(dia),
                             comIA: feitoIA != nil)
        hoje.resumo = r
        sujos.insert(hoje.dia)
        gravarDepois()
        log.info("resumo do dia (\(r.comIA ? "modelo local" : "sem IA", privacy: .public)): \(r.feito.count) feito, \(r.aberto.count) aberto, \(r.prometido.count) prometido")
        if automatico {
            Arbitro.shared.publicar(Sinal(id: "diario.resumo", lugar: .barra, prioridade: .alerta, duracao: 600,
                                          clicavel: true, conteudo: AnyView(AvisoResumoPronto())))
            NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.proud)
        }
    }

    func lerCommits() async {
        guard !lendoCommits else { return }
        lendoCommits = true
        defer { lendoCommits = false }
        var raizes: [String: String] = [:]
        for e in hoje.entradas { if let r = e.raiz { raizes[r] = e.projeto ?? URL(fileURLWithPath: r).lastPathComponent } }
        let c = await CommitsDoDia.ler(raizes: raizes, dia: Date())
        hoje.commits = c
        hoje.commitsLidosEm = Date()
        sujos.insert(hoje.dia)
        gravarDepois()
    }

    /// Entrada do modelo: entregas e commits agrupados por projeto, cortados para caber na
    /// janela pequena (~4k tokens): no máximo 8 itens por projeto e ~3500 caracteres.
    static func compactar(_ d: DiaDiario) -> String {
        var porProjeto: [String: [String]] = [:]
        var ordem: [String] = []
        func pôr(_ p: String, _ s: String) {
            if porProjeto[p] == nil { ordem.append(p) }
            porProjeto[p, default: []].append(s)
        }
        for e in d.entradas where e.tipo == .entrega { pôr(e.projeto ?? "Sem projeto", "entregou: " + TriagemIA.curto(e.texto, 120)) }
        for c in d.commits ?? [] { pôr(c.projeto, "commit: " + TriagemIA.curto(c.titulo, 90)) }
        var texto = ""
        for p in ordem {
            let itens = porProjeto[p] ?? []
            var bloco = "Projeto \(p):\n" + itens.prefix(8).map { "- " + $0 }.joined(separator: "\n")
            if itens.count > 8 { bloco += "\n- (+\(itens.count - 8) itens parecidos)" }
            if texto.count + bloco.count > 3500 { break }
            texto += bloco + "\n"
        }
        return texto.isEmpty ? "Nada foi entregue hoje." : texto
    }

    static func feitoSemIA(_ d: DiaDiario) -> [String] {
        var r: [String] = []
        var projetos: [String] = []
        for e in d.entradas where e.tipo == .entrega { let p = e.projeto ?? "Sem projeto"; if !projetos.contains(p) { projetos.append(p) } }
        for c in d.commits ?? [] where !projetos.contains(c.projeto) { projetos.append(c.projeto) }
        for p in projetos.prefix(5) {
            let ent = d.entradas.filter { $0.tipo == .entrega && ($0.projeto ?? "Sem projeto") == p }
            let com = (d.commits ?? []).filter { $0.projeto == p }
            var partes: [String] = []
            if !ent.isEmpty { partes.append("\(ent.count) entrega\(ent.count == 1 ? "" : "s")") }
            if !com.isEmpty { partes.append("\(com.count) commit\(com.count == 1 ? "" : "s")") }
            let exemplo = com.last?.titulo ?? ent.last?.texto ?? ""
            r.append("\(p): \(partes.joined(separator: ", ")) — \(TriagemIA.curto(exemplo, 70))")
        }
        return r
    }

    /// O que ficou aberto: sessões esperando o Hugo e pedidos sem entrega depois.
    private func aberto(_ d: DiaDiario) -> [String] {
        var r = abertas.filter { $0.origem == .entrega }.map {
            "\($0.sessao ?? $0.projeto ?? "Sessão"): \($0.acao) (espera desde \(FormatoDiario.hora($0.criadaEm)))"
        }
        var ultimo: [String: EntradaDiario] = [:]
        for e in d.entradas where e.sessaoId != nil { ultimo[e.sessaoId!] = e }
        for e in ultimo.values.sorted(by: { $0.hora < $1.hora }) where e.tipo == .pedido {
            r.append("\(e.sessao ?? e.projeto ?? "Sessão"): sem entrega para \"\(TriagemIA.curto(e.texto, 60))\"")
        }
        return r
    }

    /// O que o Hugo disse que ia fazer: pendências das notas e dos pedidos (abertas primeiro).
    private func prometido(_ d: DiaDiario) -> [String] {
        let minhas = pendencias.filter { $0.origem != .entrega && ($0.aberta || $0.dia == d.dia) }
        return minhas.sorted { ($0.aberta ? 0 : 1, $0.criadaEm) < ($1.aberta ? 0 : 1, $1.criadaEm) }.map { p in
            var s = p.acao
            if let pz = p.prazo { s += " (até \(FormatoDiario.quando(pz)))" }
            switch p.estado {
            case .feita: s += " — feito"
            case .ignorada: s += " — ignorado"
            case .adiada: s += " — adiado"
            case .aberta, .sugerida: break
            }
            return s
        }
    }

    // MARK: Disco

    static var pasta: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchBuddy/diario", isDirectory: true)
    }

    static func arquivo(_ dia: String) -> URL { pasta.appendingPathComponent("\(dia).json") }

    nonisolated static func ler(_ url: URL) -> DiaDiario? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        do { return try dec.decode(DiaDiario.self, from: data) } catch {
            Log.de("diario").error("arquivo do dia ilegível \(url.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Lê o dia para alterar. Arquivo que EXISTE mas não deu para ler nunca é sobrescrito: guarda
    /// uma cópia à parte e devolve nil (quem chamou não grava). Antes, falha de leitura virava um
    /// dia vazio gravado por cima — foi assim que o dia 05/10 perdeu as entradas e pendências.
    nonisolated static func lerParaAlterar(_ url: URL, dia: String) -> DiaDiario? {
        guard FileManager.default.fileExists(atPath: url.path) else { return DiaDiario(dia: dia) }
        if let d = ler(url) { return d }
        let copia = url.deletingPathExtension().appendingPathExtension("ilegivel-\(Int(Date().timeIntervalSince1970)).json")
        try? FileManager.default.copyItem(at: url, to: copia)
        return nil
    }

    private static let codificador: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    /// Dias com arquivo, do mais novo ao mais velho.
    func diasComArquivo() -> [String] {
        let nomes = (try? FileManager.default.contentsOfDirectory(atPath: Self.pasta.path)) ?? []
        var dias = nomes.filter { $0.hasSuffix(".json") }.map { String($0.dropLast(5)) }
        if !dias.contains(hoje.dia) { dias.append(hoje.dia) }
        return dias.sorted(by: >)
    }

    /// Um dia para a Central (hoje vem da memória).
    func dia(_ dia: String) -> DiaDiario {
        if dia == hoje.dia { return hoje }
        return Self.ler(Self.arquivo(dia)) ?? DiaDiario(dia: dia)
    }

    private func carregar() {
        let d = FormatoDiario.dia(Date())
        hoje = Self.lerParaAlterar(Self.arquivo(d), dia: d) ?? DiaDiario(dia: d)
        diasAbertos = [:]
        // Pendências abertas dos últimos 30 dias continuam valendo
        let cal = Calendar.current
        for i in 1...30 {
            guard let data = cal.date(byAdding: .day, value: -i, to: Date()) else { continue }
            let k = FormatoDiario.dia(data)
            if let dia = Self.ler(Self.arquivo(k)), dia.pendencias.contains(where: \.aberta) { diasAbertos[k] = dia }
        }
        tirarDecisoesDeSessao()
        tirarAppsDoSistema()
    }

    /// Tela de bloqueio e protetor de tela não são uso (o loginwindow chegou a "8 h" num dia):
    /// tira o que já foi gravado deles hoje.
    private func tirarAppsDoSistema() {
        let antes = hoje.apps.count
        for b in FocoApps.ignorados { hoje.apps[b] = nil }
        if hoje.apps.count != antes {
            sujos.insert(hoje.dia)
            gravarDepois()
            log.info("tempo da tela de bloqueio tirado do dia")
        }
    }

    /// Uma vez: pendências abertas que vieram de entrega de sessão (decisões) saem da lista —
    /// ficam marcadas, não apagadas, para dar para desfazer.
    private func tirarDecisoesDeSessao() {
        let agora = Date()
        for i in hoje.pendencias.indices where hoje.pendencias[i].origem == .whatsapp && hoje.pendencias[i].aberta
            && (hoje.pendencias[i].prazo.map { $0 < hoje.pendencias[i].criadaEm.addingTimeInterval(60) || $0 < agora.addingTimeInterval(-6 * 3600) } ?? false) {
            hoje.pendencias[i].estado = .ignorada
            hoje.pendencias[i].resolvidaEm = agora
            hoje.pendencias[i].motivo = "o prazo já tinha passado quando o WhatsApp foi lido"
            sujos.insert(hoje.dia)
        }
        func limpar(_ d: inout DiaDiario) -> Bool {
            var mudou = false
            for i in d.pendencias.indices where d.pendencias[i].aberta && d.pendencias[i].manual != true
                && (d.pendencias[i].origem == .entrega
                    || (d.pendencias[i].origem == .pedido && !Self.falaDeSi(d.pendencias[i].textoOrigem))) {
                d.pendencias[i].estado = .ignorada
                d.pendencias[i].resolvidaEm = Date()
                d.pendencias[i].motivo = "não é tarefa de \(Usuario.nome) (decisão ou instrução a uma sessão)"
                mudou = true
            }
            return mudou
        }
        if limpar(&hoje) { sujos.insert(hoje.dia) }
        for (k, var d) in diasAbertos where limpar(&d) { diasAbertos[k] = d; sujos.insert(k) }
        if !sujos.isEmpty { gravarDepois() }
    }

    /// Virou o dia: grava o anterior e começa o novo (o de ontem fica se tiver pendência aberta).
    private func garantirHoje() {
        let d = FormatoDiario.dia(Date())
        guard d != hoje.dia else { return }
        gravarAgora()
        if hoje.pendencias.contains(where: \.aberta) { diasAbertos[hoje.dia] = hoje }
        hoje = Self.lerParaAlterar(Self.arquivo(d), dia: d) ?? DiaDiario(dia: d)
    }

    private func gravarDepois() {
        gravacao?.cancel()
        let item = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.gravarAgora() } }
        gravacao = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: item)
    }

    private func gravarAgora() {
        gravacao?.cancel()
        gravacao = nil
        guard !Gravar.desligado, !CaptureTool.ativo, !sujos.isEmpty else { sujos.removeAll(); return }
        var lote: [(URL, Data)] = []
        for dia in sujos {
            let d = dia == hoje.dia ? hoje : diasAbertos[dia]
            guard let d, let data = try? Self.codificador.encode(d) else { continue }
            lote.append((Self.arquivo(dia), data))
        }
        sujos.removeAll()
        // Pendência de dia antigo que fechou: sai da lista de dias abertos (o arquivo guarda)
        for (k, d) in diasAbertos where !d.pendencias.contains(where: \.aberta) { diasAbertos[k] = nil }
        let pasta = Self.pasta
        let caixa = UncheckedSendable(lote)
        filaDisco.async {
            try? FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
            for (url, data) in caixa.valor { try? data.write(to: url, options: .atomic) }
        }
    }

    /// Mexe direto no arquivo de um dia que não está na memória (fora da main).
    private func alterarArquivo(_ dia: String, _ f: @escaping @Sendable (inout DiaDiario) -> Void) {
        guard !Gravar.desligado, !CaptureTool.ativo else { return }
        let url = Self.arquivo(dia)
        filaDisco.async {
            guard var d = Self.lerParaAlterar(url, dia: dia) else { return }   // ilegível: não grava por cima
            f(&d)
            let e = JSONEncoder()
            e.dateEncodingStrategy = .iso8601
            e.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? e.encode(d) { try? data.write(to: url, options: .atomic) }
        }
    }

    // MARK: Fontes — desligar apaga o que foi guardado

    func definirFonte(_ f: FonteDiario, _ ligada: Bool) {
        Ajustes.definir(Self.idModulo, "fonte.\(f.rawValue)", ligada)
        if f == .apps, ligado { ligada ? foco.ligar() : foco.desligar() }
        if f == .whatsapp, ligado { ligada ? FonteWhatsApp.shared.ligar() : FonteWhatsApp.shared.desligar() }
        if f == .whatsapp, !ligada { FonteWhatsApp.shared.esquecer() }
        if !ligada { apagarFonte(f) }
    }

    private func apagarFonte(_ f: FonteDiario) {
        let limpar: @Sendable (inout DiaDiario) -> Void = { d in
            switch f {
            case .sessoes:
                d.entradas.removeAll { $0.tipo == .pedido || $0.tipo == .entrega }
                d.pendencias.removeAll { $0.origem == .pedido || $0.origem == .entrega }
                d.resumo = nil
            case .notas:
                d.entradas.removeAll { $0.tipo == .nota }
                d.pendencias.removeAll { $0.origem == .nota }
                d.resumo = nil
            case .apps:
                d.apps = [:]
            case .whatsapp:
                d.entradas.removeAll { $0.tipo == .whatsapp }
                d.pendencias.removeAll { $0.origem == .whatsapp }
            case .commits:
                d.commits = nil
                d.commitsLidosEm = nil
                d.resumo = nil
            }
        }
        limpar(&hoje)
        for k in Array(diasAbertos.keys) { limpar(&diasAbertos[k]!) }
        destaque = nil
        Arbitro.shared.retirar("diario.aviso")
        reagendarAvisos()
        guard !Gravar.desligado, !CaptureTool.ativo else { return }
        sujos.insert(hoje.dia)
        gravarAgora()
        for dia in diasComArquivo() where dia != hoje.dia { alterarArquivo(dia, limpar) }
        log.info("fonte \(f.rawValue, privacy: .public) desligada: guardado apagado")
    }

    // MARK: Capturas

    /// Modo de capturas: lê o dia de hoje de verdade (só leitura).
    func carregarParaCaptura() {
        carregar()
    }

    /// Modo de capturas: um dia de exemplo (nada é gravado).
    func exemploParaCaptura() {
        let cal = Calendar.current
        func h(_ hh: Int, _ mm: Int) -> Date { cal.date(bySettingHour: hh, minute: mm, second: 0, of: Date()) ?? Date() }
        var d = DiaDiario(dia: FormatoDiario.dia(Date()))
        func e(_ t: TipoEntrada, _ hh: Int, _ mm: Int, _ texto: String, _ proj: String? = nil, _ cor: String? = nil, _ s: String? = nil) -> EntradaDiario {
            EntradaDiario(hora: h(hh, mm), tipo: t, texto: texto, projeto: proj, cor: cor, sessao: s, sessaoId: s)
        }
        d.entradas = [
            e(.pedido, 9, 12, "revisa o fechamento de caixa da loja do centro e confere os totais", "loja", "#38BDF8", "Fechamento"),
            e(.entrega, 9, 41, "Os totais batem; ajustei o arredondamento do PIX.", "loja", "#38BDF8", "Fechamento"),
            e(.nota, 10, 5, "mandar a planilha pro Rafa até meio-dia"),
            e(.pedido, 10, 30, "faz o módulo de diário no Crew", "crew", "#FF7A59", "Diário"),
            e(.nota, 11, 40, "ligar pro contador amanhã cedo"),
            e(.entrega, 14, 2, "PR aberto. Falta você aprovar o merge para eu fazer o deploy.", "crew", "#FF7A59", "Diário"),
            e(.nota, 14, 20, "revisar PR do KDS quando der"),
        ]
        d.apps = ["com.microsoft.VSCode": TempoApp(nome: "Visual Studio Code", segundos: 9_480),
                  "com.google.Chrome": TempoApp(nome: "Google Chrome", segundos: 5_100),
                  "com.xirp.app": TempoApp(nome: "Xirp", segundos: 3_600),
                  "com.apple.mail": TempoApp(nome: "Mail", segundos: 1_260),
                  "net.whatsapp.WhatsApp": TempoApp(nome: "WhatsApp", segundos: 900)]
        func p(_ hh: Int, _ mm: Int, _ o: TipoEntrada, _ txt: String, _ acao: String, _ pessoa: String?, _ prazo: Date?, _ u: Urgencia, _ s: String? = nil) -> Pendencia {
            Pendencia(criadaEm: h(hh, mm), dia: d.dia, origem: o, textoOrigem: txt, acao: acao, pessoa: pessoa,
                      prazo: prazo, urgencia: u, sessaoId: s, sessao: s, projeto: s == nil ? nil : "crew", comIA: true)
        }
        let amanha9 = cal.date(byAdding: .day, value: 1, to: h(9, 0))
        var feita = p(10, 5, .nota, "mandar a planilha pro Rafa até meio-dia", "mandar a planilha pro Rafa", "Rafa", h(12, 0), .hoje)
        feita.estado = .feita; feita.resolvidaEm = h(11, 52)
        d.pendencias = [
            feita,
            p(11, 40, .nota, "ligar pro contador amanhã cedo", "ligar pro contador", "contador", amanha9, .semPressa),
            p(14, 2, .entrega, "PR aberto. Falta você aprovar o merge para eu fazer o deploy.", "aprovar o merge do PR", nil, nil, .hoje, "Diário"),
            p(14, 20, .nota, "revisar PR do KDS quando der", "revisar PR do KDS", nil, nil, .semPressa),
        ]
        d.commits = [CommitDiario(hash: "a1b2c3d4e5", hora: h(10, 58), titulo: "feat(diario): triagem em tempo real com o modelo local", projeto: "crew"),
                     CommitDiario(hash: "f6e7d8c9b0", hora: h(9, 44), titulo: "fix(caixa): arredondamento do PIX no fechamento", projeto: "loja")]
        d.resumo = ResumoDiario(geradoEm: h(18, 0),
                                feito: ["loja: fechamento da loja do centro conferido, arredondamento do PIX corrigido",
                                        "crew: módulo Diário com triagem e avisos na hora certa"],
                                aberto: ["Diário: aprovar o merge do PR (espera desde 14:02)"],
                                prometido: ["ligar pro contador (até amanhã 09:00)", "revisar PR do KDS",
                                            "mandar a planilha pro Rafa (até 12:00) — feito"],
                                comIA: true)
        hoje = d
        diasAbertos = [:]
        destaque = d.pendencias[2].id
    }
}
