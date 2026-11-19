import SwiftUI
import AppKit

// Rotinas: guarda, agenda e roda.
//
// Custo parado: zero. UM DispatchSourceTimer de relógio de parede armado para a próxima rotina
// ligada (como os avisos do Diário), refeito ao acordar e quando o relógio/fuso muda. Sem rotina
// ligada, pausado ou sem a confirmação do Hugo: nenhum timer.
//
// Segurança: a agenda só roda rotina que o Hugo ligou na chave, depois de confirmar uma vez que o
// Crew vai abrir sessões sozinho. Nunca há fila: o que venceu com o Mac dormindo ou o Crew fechado
// vira no máximo UMA recuperação (se a rotina pedir) e a próxima é contada a partir de agora.

@MainActor
@Observable
final class RotinasServico {
    static let shared = RotinasServico()
    static let idModulo = "rotinas"

    private(set) var rotinas: [Rotina] = []
    /// Rotinas abrindo sessão agora.
    private(set) var rodando: Set<UUID> = []
    /// `rotinas.json` existe mas não deu para ler: caminho da cópia guardada. Enquanto isto não
    /// for nil, nada é gravado (o arquivo do Hugo fica como está).
    private(set) var arquivoIlegivel: String?
    /// Pedido de fora (crew://) para rodar esta rotina: espera o clique do Hugo na página.
    var pedidoDeFora: UUID?

    /// "Pausar todas": nenhuma rotina roda pela agenda enquanto ligado.
    var pausadas: Bool = Ajustes.bool(RotinasServico.idModulo, "pausadas", padrao: false) {
        didSet {
            guard pausadas != oldValue else { return }
            Ajustes.definir(Self.idModulo, "pausadas", pausadas)
            // Voltando da pausa: o que venceu enquanto pausado não roda; conta a partir de agora
            if !pausadas { reprogramar(soVencidas: true) }
            armar()
        }
    }

    /// O Hugo já confirmou (uma vez) que rotinas ligadas abrem sessões sozinhas.
    private(set) var consentiu: Bool = Ajustes.bool(RotinasServico.idModulo, "consentiu", padrao: false)

    @ObservationIgnored private var ativo = false
    @ObservationIgnored private var timer: DispatchSourceTimer?
    @ObservationIgnored private var observadores: [(NotificationCenter, NSObjectProtocol)] = []
    @ObservationIgnored private let fila = DispatchQueue(label: "crew.rotinas.gravar", qos: .utility)
    @ObservationIgnored private let log = Log.de("rotinas")

    static var arquivo: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchBuddy/rotinas.json")
    }

    // MARK: Ciclo

    func iniciar() {
        guard !ativo, !CaptureTool.ativo else { return }
        ativo = true
        carregar()
        let ws = NSWorkspace.shared.notificationCenter
        observar(ws, NSWorkspace.didWakeNotification) { $0.conferir() }
        // Relógio acertado: a hora marcada pode ter chegado (ou ficado mais longe)
        observar(.default, .NSSystemClockDidChange) { $0.conferir() }
        // Fuso novo: "todo dia às 09:00" passa a valer na hora local nova
        observar(.default, .NSSystemTimeZoneDidChange) { $0.reprogramar(soVencidas: false, soCalendario: true); $0.armar() }
        conferir()
        log.info("rotinas: \(self.rotinas.count) guardada(s), \(self.rotinas.filter(\.ligada).count) ligada(s)")
    }

    func parar() {
        ativo = false
        timer?.cancel()
        timer = nil
        for (centro, o) in observadores { centro.removeObserver(o) }
        observadores = []
        Arbitro.shared.retirar("rotinas.aviso")
        Arbitro.shared.retirar("rotinas.pedido")
    }

    private func observar(_ centro: NotificationCenter, _ nome: Notification.Name, _ acao: @escaping @MainActor (RotinasServico) -> Void) {
        let o = centro.addObserver(forName: nome, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if let self { acao(self) } }
        }
        observadores.append((centro, o))
    }

    // MARK: Consulta

    func rotina(_ id: UUID) -> Rotina? { rotinas.first { $0.id == id } }

    /// As rotinas de um Homie, na ordem em que foram criadas.
    func doHomie(_ id: UUID) -> [Rotina] { rotinas.filter { $0.homie == id } }

    /// O Homie saiu da equipe: as rotinas dele saem junto.
    func apagarDoHomie(_ id: UUID) {
        guard rotinas.contains(where: { $0.homie == id }) else { return }
        rotinas.removeAll { $0.homie == id }
        gravar()
        armar()
    }

    /// A agenda está valendo agora? (módulo ligado, confirmado, sem pausa)
    var agendaValendo: Bool { ativo && consentiu && !pausadas }

    // MARK: Edição (sempre clique do Hugo)

    /// Cria ou atualiza. Agenda nova = próxima recontada a partir de agora.
    func salvar(_ nova: Rotina) {
        var r = nova
        r.nome = r.nome.trimmingCharacters(in: .whitespacesAndNewlines)
        r.agenda.dias = Array(Set(r.agenda.dias)).sorted()
        if r.agenda.tipo == .manual || !r.agenda.valida { r.ligada = false }
        if let i = rotinas.firstIndex(where: { $0.id == r.id }) {
            if rotinas[i].agenda != r.agenda || rotinas[i].ligada != r.ligada {
                r.proximaExecucao = r.ligada ? r.agenda.proxima(depois: Date(), ancora: Date()) : nil
            }
            rotinas[i] = r
        } else {
            r.proximaExecucao = r.ligada ? r.agenda.proxima(depois: Date(), ancora: Date()) : nil
            rotinas.append(r)
        }
        gravar()
        armar()
    }

    func apagar(_ id: UUID) {
        rotinas.removeAll { $0.id == id }
        if pedidoDeFora == id { dispensarPedido() }
        gravar()
        armar()
    }

    /// O Hugo confirmou o aviso da primeira vez.
    func confirmarConsentimento() {
        consentiu = true
        Ajustes.definir(Self.idModulo, "consentiu", true)
    }

    /// Liga/desliga a agenda de uma rotina. Ligar exige a confirmação já dada.
    func ligar(_ id: UUID, _ ligada: Bool) {
        guard !ligada || consentiu else { return }
        mudar(id) { r in
            guard r.agenda.tipo != .manual, r.agenda.valida || !ligada else { return }
            r.ligada = ligada
            r.proximaExecucao = ligada ? r.agenda.proxima(depois: Date(), ancora: Date()) : nil
            // "Uma vez" que já passou não tem o que ligar
            if ligada && r.proximaExecucao == nil { r.ligada = false }
        }
        gravar()
        armar()
    }

    /// O arquivo ilegível fica guardado na cópia; o Hugo decide recomeçar com a lista vazia.
    func comecarDoZero() {
        guard arquivoIlegivel != nil else { return }
        arquivoIlegivel = nil
        rotinas = []
        gravar()
        armar()
    }

    private func mudar(_ id: UUID, _ f: (inout Rotina) -> Void) {
        guard let i = rotinas.firstIndex(where: { $0.id == id }) else { return }
        f(&rotinas[i])
    }

    // MARK: Agenda (um timer só)

    /// Reconta a próxima a partir de agora, sem rodar nada.
    private func reprogramar(soVencidas: Bool, soCalendario: Bool = false) {
        let agora = Date()
        var mudou = false
        for i in rotinas.indices where rotinas[i].ligada {
            let r = rotinas[i]
            if soVencidas, let p = r.proximaExecucao, p > agora { continue }
            if soCalendario, r.agenda.tipo == .intervalo || r.agenda.tipo == .umaVez { continue }
            let nova = r.agenda.proxima(depois: agora, ancora: r.proximaExecucao ?? agora)
            if nova != r.proximaExecucao { rotinas[i].proximaExecucao = nova; mudou = true }
            if nova == nil { rotinas[i].ligada = false; mudou = true }
        }
        if mudou { gravar() }
    }

    /// Roda o que chegou a hora, decide o que fazer com o que passou da hora e arma a próxima.
    private func conferir() {
        guard agendaValendo else { armar(); return }
        let agora = Date()
        var mudou = false
        for i in rotinas.indices where rotinas[i].ligada {
            let r = rotinas[i]
            guard let marcada = r.proximaExecucao else {
                // Ligada sem próxima (arquivo editado à mão, por exemplo): conta a partir de agora
                rotinas[i].proximaExecucao = r.agenda.proxima(depois: agora, ancora: agora)
                if rotinas[i].proximaExecucao == nil { rotinas[i].ligada = false }
                mudou = true
                continue
            }
            guard marcada <= agora else { continue }
            // A próxima sai de AGORA: dez horas marcadas perdidas viram uma decisão só
            rotinas[i].proximaExecucao = r.agenda.proxima(depois: agora, ancora: marcada)
            if rotinas[i].proximaExecucao == nil { rotinas[i].ligada = false }   // "uma vez" cumpriu
            mudou = true
            switch PoliticaRotinas.vencida(agendada: marcada, agora: agora, recuperar: r.recuperarPerdida) {
            case .naHora:
                Task { await self.executar(r.id, .agenda) }
            case .recuperar:
                Task { await self.executar(r.id, .recuperada) }
            case .perdida:
                registrar(r.id, .agenda, sessao: nil,
                          motivo: "passou da hora (\(FormatoRotina.quando(marcada))) com o Mac dormindo ou o Crew fechado")
            }
        }
        if mudou { gravar() }
        armar()
    }

    private func armar() {
        timer?.cancel()
        timer = nil
        guard agendaValendo else { return }
        guard let alvo = rotinas.filter(\.ligada).compactMap(\.proximaExecucao).min() else { return }
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(wallDeadline: .now() + max(0.5, alvo.timeIntervalSinceNow), leeway: .seconds(2))
        t.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.conferir() } }
        t.resume()
        timer = t
    }

    // MARK: Execução

    /// Botão "Rodar agora": o clique do Hugo.
    func rodarAgora(_ id: UUID) {
        if pedidoDeFora == id { dispensarPedido() }
        Task { await executar(id, .manual) }
    }

    private func executar(_ id: UUID, _ origem: ExecucaoRotina.Origem) async {
        // Modo de capturas nunca abre sessão
        guard !CaptureTool.ativo, let r = rotina(id), !rodando.contains(id) else { return }
        rodando.insert(id)
        defer { rodando.remove(id) }

        if let m = MotorCrew.motivoIndisponivel {
            registrar(id, origem, sessao: nil, motivo: "o motor de sessões não está disponível: \(m)")
            return
        }
        var pasta = r.pasta, pedido = r.pedido
        var opcoes = MotorCrew.Opcoes(modelo: r.modelo, modo: r.modo, nome: r.nome)
        // Rotina de Homie: quem diz a pasta, o pedido e os limites da sessão é o Homie.
        if r.homie != nil {
            guard let plano = HomiesServico.shared.planoDaRotina(r) else {
                registrar(id, origem, sessao: nil, motivo: "o Homie desta rotina não está mais na equipe")
                return
            }
            (pasta, pedido, opcoes) = plano
        }
        var ehPasta: ObjCBool = false
        guard FileManager.default.fileExists(atPath: pasta, isDirectory: &ehPasta), ehPasta.boolValue else {
            registrar(id, origem, sessao: nil, motivo: "a pasta não existe (\(pasta))")
            return
        }
        // Pela agenda, uma rotina não empilha sessões: espera a anterior fechar. No clique do Hugo
        // ("Rodar agora") a decisão é dele.
        if origem != .manual, let anterior = r.historico.first(where: { $0.sessao != nil })?.sessao,
           await MotorCrew.ehDoCrew(anterior) {
            registrar(id, origem, sessao: nil, motivo: "a sessão da execução anterior ainda está aberta")
            return
        }
        switch await MotorCrew.nova(pasta: pasta, pedido: pedido, opcoes: opcoes) {
        case .success(let sid):
            registrar(id, origem, sessao: sid, motivo: nil)
            if r.homie != nil { HomiesServico.shared.rotinaAbriu(r, sessao: sid) }
        case .failure(let f):
            registrar(id, origem, sessao: nil, motivo: f.mensagem)
        }
    }

    /// Anota a tentativa no histórico, grava e avisa na ilha fechada.
    private func registrar(_ id: UUID, _ origem: ExecucaoRotina.Origem, sessao: String?, motivo: String?) {
        guard let r = rotina(id) else { return }
        let agora = Date()
        mudar(id) { r in
            r.historico.insert(ExecucaoRotina(quando: agora, origem: origem, sessao: sessao, ok: sessao != nil, motivo: motivo), at: 0)
            if r.historico.count > PoliticaRotinas.maxHistorico { r.historico.removeLast(r.historico.count - PoliticaRotinas.maxHistorico) }
            if sessao != nil { r.ultimaExecucao = agora }
        }
        gravar()
        if sessao != nil {
            log.info("rotina \(r.nome, privacy: .public) abriu a sessão \(sessao ?? "", privacy: .public) (\(origem.rawValue, privacy: .public))")
            avisar("Rotina \(r.nome) abriu uma sessão", ok: true)
        } else {
            log.error("rotina \(r.nome, privacy: .public) não rodou (\(origem.rawValue, privacy: .public)): \(motivo ?? "", privacy: .public)")
            avisar("Rotina \(r.nome) não rodou: \(motivo ?? "motivo desconhecido")", ok: false)
        }
    }

    private func avisar(_ texto: String, ok: Bool) {
        let curto = texto.count > 110 ? String(texto.prefix(109)) + "…" : texto
        Arbitro.shared.publicar(Sinal(id: "rotinas.aviso", lugar: .barra, prioridade: .alerta, duracao: ok ? 6 : 9,
                                      conteudo: AnyView(AvisoBarra(icone: ok ? "clock.badge.checkmark" : "clock.badge.exclamationmark",
                                                                   texto: curto, cor: ok ? FormatoRotinaUI.corOk : FormatoRotinaUI.corFalha))))
    }

    // MARK: Pedido de fora (crew://)

    /// `crew://rotinas/rodar?id=` ou `?nome=`: NÃO roda. Vira um pedido na ilha; o Hugo clica, cai
    /// na página com a rotina em destaque e decide no botão "Rodar agora". false = rotina não achada.
    func pedirDeFora(id: String?, nome: String?) -> Bool {
        let alvo: Rotina?
        if let id, let u = UUID(uuidString: id) {
            alvo = rotina(u)
        } else if let nome, !nome.isEmpty {
            alvo = rotinas.first { $0.nome.compare(nome, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
        } else {
            alvo = nil
        }
        guard let r = alvo else { return false }
        pedidoDeFora = r.id
        log.info("pedido de fora para rodar a rotina \(r.nome, privacy: .public): esperando o clique")
        Arbitro.shared.publicar(Sinal(id: "rotinas.pedido", lugar: .barra, prioridade: .alerta, duracao: 120,
                                      clicavel: true, conteudo: AnyView(AvisoPedidoRotina(nome: r.nome))))
        return true
    }

    func dispensarPedido() {
        pedidoDeFora = nil
        Arbitro.shared.retirar("rotinas.pedido")
    }

    // MARK: Arquivo

    private static let codificador: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private func carregar() {
        let url = Self.arquivo
        guard FileManager.default.fileExists(atPath: url.path) else { rotinas = []; return }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        do {
            rotinas = try dec.decode(ArquivoRotinas.self, from: Data(contentsOf: url)).rotinas
            arquivoIlegivel = nil
        } catch {
            // Existe mas não deu para ler: nunca gravar por cima. Guarda uma cópia e avisa na página.
            let copia = url.deletingPathExtension().appendingPathExtension("ilegivel-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: url, to: copia)
            arquivoIlegivel = copia.path
            rotinas = []
            log.error("rotinas.json ilegível, nada será gravado: \(String(describing: error), privacy: .public)")
        }
    }

    /// Gravação atômica, fora da main, em ordem (fila serial).
    private func gravar() {
        guard arquivoIlegivel == nil, !Gravar.desligado, !CaptureTool.ativo else { return }
        guard let data = try? Self.codificador.encode(ArquivoRotinas(rotinas: rotinas)) else { return }
        let url = Self.arquivo
        fila.async {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            do { try data.write(to: url, options: .atomic) } catch {
                Log.de("rotinas").error("não gravou rotinas.json: \(String(describing: error), privacy: .public)")
            }
        }
    }

    // MARK: Capturas

    /// Dados de exemplo para o modo de capturas (nada é gravado nem executado).
    func exemploParaCaptura() {
        let agora = Date()
        let cal = Calendar.current
        let casa = FileManager.default.homeDirectoryForCurrentUser.path
        func ex(_ horasAtras: Double, _ origem: ExecucaoRotina.Origem, ok: Bool, _ motivo: String? = nil) -> ExecucaoRotina {
            ExecucaoRotina(quando: agora.addingTimeInterval(-horasAtras * 3600), origem: origem,
                           sessao: ok ? UUID().uuidString.lowercased() : nil, ok: ok, motivo: motivo)
        }
        var a = Rotina(nome: "Revisão da manhã", pasta: casa + "/dev/crew",
                       pedido: "Leia os commits de ontem no estavel e me diga o que ficou sem teste.",
                       modelo: "opus", modo: "plan", agenda: AgendaRotina(tipo: .semanal, hora: 9, minuto: 0), ligada: true)
        a.historico = [ex(26, .agenda, ok: true), ex(50, .agenda, ok: true),
                       ex(74, .agenda, ok: false, "a sessão da execução anterior ainda está aberta")]
        var b = Rotina(nome: "Dependências desatualizadas", pasta: casa + "/dev/painel",
                       pedido: "Liste as dependências com versão nova e o risco de cada atualização. Não altere nada.",
                       agenda: AgendaRotina(tipo: .diaria, hora: 18, minuto: 0), ligada: true, recuperarPerdida: true)
        b.historico = [ex(17, .recuperada, ok: true)]
        var c = Rotina(nome: "Conferir fila de erros", pasta: casa + "/dev/api",
                       pedido: "Olhe os erros novos do log e agrupe por causa.", modelo: "haiku",
                       agenda: AgendaRotina(tipo: .intervalo, intervaloMin: 120), ligada: true)
        c.historico = [ex(1.5, .agenda, ok: false, "a pasta não existe (\(casa)/dev/api)")]
        let d = Rotina(nome: "Notas da versão", pasta: casa + "/dev/crew",
                       pedido: "Escreva as notas da versão a partir dos commits desde a última tag.", modo: "acceptEdits")
        let e = Rotina(nome: "Migração do banco", pasta: casa + "/dev/painel",
                       pedido: "Rode o plano de migração em modo de leitura e me mostre o que mudaria.", modelo: "sonnet",
                       agenda: AgendaRotina(tipo: .umaVez, data: cal.date(byAdding: .day, value: 3, to: agora)))
        rotinas = [a, b, c, d, e].map { r in
            var r = r
            r.ultimaExecucao = r.historico.first { $0.ok }?.quando
            r.proximaExecucao = r.ligada ? r.agenda.proxima(depois: agora, ancora: agora) : nil
            return r
        }
        consentiu = true
        pedidoDeFora = d.id
    }
}

/// O pedido de fora na barra da ilha fechada: clique abre a página das Rotinas, onde o Hugo decide.
struct AvisoPedidoRotina: View {
    let nome: String

    var body: some View {
        AvisoBarra(icone: "clock.badge.questionmark", texto: "Pedido para rodar a rotina \(nome) — clique para decidir",
                   cor: FormatoRotinaUI.corPedido)
            .contentShape(Rectangle())
            .onTapGesture {
                Arbitro.shared.retirar("rotinas.pedido")
                Central.abrir(modulo: RotinasServico.idModulo)
            }
            .help("Uma automação (crew://) pediu para rodar esta rotina. Nada roda sem o seu clique.")
    }
}

enum FormatoRotinaUI {
    static let corOk = Color(hex: "#34D399")
    static let corFalha = Color(hex: "#F59E0B")
    static let corPedido = Color(hex: "#A78BFA")
}
