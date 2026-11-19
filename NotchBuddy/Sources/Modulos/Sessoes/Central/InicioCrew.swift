import SwiftUI
import AppKit

// O início do app do Crew: o Homie, uma saudação e o campo grande para pedir uma sessão nova.
// Na linha de baixo do campo, os chips do pedido: em que projeto, com qual modelo e em que
// modo. O motor é o do Crew (tmux + CLI), sem depender de outro app. Enviar abre a sessão; enquanto ela
// não chega pelos hooks, o início mostra "abrindo" (e, no motor do Crew, a tela do terminal:
// é ali que o Claude Code pergunta se confia na pasta).

struct InicioCrew: View {
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var projetos = ProjetosCrew.shared
    @EnvironmentObject private var nav: NavegacaoCrew

    @State private var texto = ""
    @State private var anexos: [URL] = []
    @ObservedObject private var config = ConfigProjetos.shared
    // Escolha feita agora no campo; sem ela vale o padrão do projeto (painel do projeto).
    @State private var modeloEscolhido: String?
    @State private var modoEscolhido: String?
    @State private var mexeuModelo = false
    @State private var mexeuModo = false
    @State private var enviando = false
    @State private var erro: String?
    /// Muda a cada pedido enviado: o campo é refeito do zero (nada do pedido anterior sobra nele).
    @State private var geracao = 0
    @State private var olhar = OlharHomie()
    @State private var centroHomie: CGPoint = .zero
    // Uma leitura só por tela: são conferências no disco.
    @State private var temCrew = MotorCrew.disponivel

    private static let modelos = OpcoesSessao.modelos
    private static let modos = OpcoesSessao.modos

    private var padroes: ConfigProjeto { config.de(projeto?.caminho) }
    private var modelo: String? { mexeuModelo ? modeloEscolhido : padroes.modelo }
    private var modo: String? { mexeuModo ? modoEscolhido : padroes.modo }

    // MARK: Escolhas

    /// O projeto do pedido: o escolhido agora, o último usado, o da sessão em foco, o primeiro.
    private var projeto: ProjetoCrew? {
        let l = projetos.lista
        if let c = nav.projetoInicio, let p = l.first(where: { $0.caminho == c }) { return p }
        if let u = projetos.ultimo, let p = l.first(where: { $0.caminho == u }) { return p }
        if let r = Projetos.raiz(de: state.focusTask?.sessionCwd), let p = l.first(where: { $0.caminho == r }) { return p }
        return l.first
    }


    /// O que impede de abrir uma sessão agora (nil = nada).
    private var impedimento: String? {
        if projetos.lista.isEmpty { return "Adicione a pasta de um projeto para abrir a primeira sessão." }
        if !temCrew { return MotorCrew.motivoIndisponivel ?? "Motor do Crew indisponível." }
        return nil
    }

    private var saudacao: String {
        let h = Calendar.current.component(.hour, from: Date())
        let s = h < 5 ? "Boa madrugada" : h < 12 ? "Bom dia" : h < 18 ? "Boa tarde" : "Boa noite"
        return "\(s), \(Usuario.nome)."
    }

    // MARK: Tela

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            if let a = nav.abrindo {
                abrindo(a)
            } else {
                heroi
                campo
                    .padding(.top, 26)
                rodapeDoCampo
                atalhos
                    .padding(.top, 20)
            }
            Spacer(minLength: 24)
            // Um pouco acima do meio: o olho descansa melhor ali.
            Spacer().frame(height: 36)
        }
        .frame(maxWidth: 720)
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .coordinateSpace(name: "inicio")
        .contentShape(Rectangle())
        .onContinuousHover(coordinateSpace: .named("inicio")) { fase in
            switch fase {
            case .active(let p):
                olhar.x = tanh((p.x - centroHomie.x) / 260)
                olhar.y = -tanh((p.y - centroHomie.y) / 220)
            case .ended:
                olhar.x = 0; olhar.y = 0
            }
        }
    }

    private var heroi: some View {
        VStack(spacing: 6) {
            HomieVivo(estado: enviando ? .thinking : erro != nil ? .error : .idle, tamanho: 190, olhar: olhar)
                .frame(width: 190, height: 150)
                // Uma luz fraca atrás dele: tira o Homie do preto chapado.
                .background {
                    Circle()
                        .fill(RadialGradient(colors: [Color.white.opacity(0.07), .clear],
                                             center: .center, startRadius: 0, endRadius: 190))
                        .frame(width: 380, height: 380)
                        .allowsHitTesting(false)
                }
                .onGeometryChange(for: CGPoint.self) { g in
                    let f = g.frame(in: .named("inicio"))
                    return CGPoint(x: f.midX, y: f.midY)
                } action: { centroHomie = $0 }
            Text(saudacao)
                .font(Tema.titulo(30, .bold))
                .foregroundStyle(Tema.texto)
            Text("Diga o que precisa e eu abro a sessão.")
                .font(.system(size: 15))
                .foregroundStyle(Tema.texto2)
        }
    }

    private var campo: some View {
        CompositorCrew(texto: $texto, anexos: $anexos,
                       placeholder: projeto.map { "O que o Claude Code faz em \($0.nome)?" } ?? "O que o Claude Code deve fazer?",
                       habilitado: impedimento == nil && !enviando, enviando: enviando, grande: true,
                       foco: nav.focoInicio, aoEnviar: abrir) {
            chipProjeto
            chipModelo
            chipModo
        }
        .modifier(GuardaRascunho(chave: "inicio", texto: $texto, anexos: $anexos, ignorar: nav.pedidoEnviado))
        .id(geracao)
        // Trocou de projeto: voltam a valer os padrões dele.
        .onChange(of: projeto?.caminho) { _, _ in mexeuModelo = false; mexeuModo = false }
        // "Nova sessão" de novo: se o que está no campo é o pedido que já virou sessão, sai.
        .onChange(of: nav.focoInicio) { _, _ in limparSeJaEnviado() }
        .onAppear { limparSeJaEnviado() }
    }

    private func limparSeJaEnviado() {
        guard let enviado = nav.pedidoEnviado, !texto.isEmpty || !anexos.isEmpty else { return }
        if texto.trimmingCharacters(in: .whitespacesAndNewlines) == enviado { limpar() }
        // Conferido uma vez: se o Hugo escrever o mesmo texto de propósito depois, ele fica.
        nav.pedidoEnviado = nil
    }

    private func limpar() {
        MarcasImagem.esquecer(anexos)
        texto = ""
        anexos = []
        geracao += 1
    }

    // MARK: Chips

    private var chipProjeto: some View {
        MenuChip(icone: projeto == nil ? "folder" : nil, ponto: projeto.map { Color(hex: $0.cor) },
                 texto: projeto?.nome ?? "Escolher projeto", forte: projeto != nil,
                 ajuda: projeto?.caminhoCurto ?? "Em que pasta a sessão abre") {
            var itens = projetos.lista.map { p in
                ItemMenu.acao(p.nome, ponto: Color(hex: p.cor), marcado: p.caminho == projeto?.caminho) {
                    nav.projetoInicio = p.caminho
                }
            }
            if !itens.isEmpty { itens.append(.divisor) }
            itens.append(.acao("Adicionar pasta…", icone: "plus") {
                Task { if let p = await projetos.adicionarPerguntando() { nav.projetoInicio = p.caminho } }
            })
            return itens
        }
    }

    private var chipModelo: some View {
        let atual = Self.modelos.first { $0.valor == modelo }
        return MenuChip(icone: "cpu", texto: modelo == nil ? "Modelo" : atual?.nome ?? "Modelo", forte: modelo != nil,
                        ajuda: "Modelo da sessão (padrão: o do Claude Code)") {
            Self.modelos.map { m in
                ItemMenu.acao(m.nome, marcado: m.valor == modelo) { modeloEscolhido = m.valor; mexeuModelo = true }
            }
        }
    }

    private var chipModo: some View {
        let atual = Self.modos.first { $0.valor == modo }
        return MenuChip(icone: "shield.lefthalf.filled", texto: modo == nil ? "Modo" : atual?.nome ?? "Modo", forte: modo != nil,
                        ajuda: "Modo de permissão da sessão") {
            Self.modos.map { m in
                ItemMenu.acao(m.nome, detalhe: m.detalhe, marcado: m.valor == modo) { modoEscolhido = m.valor; mexeuModo = true }
            }
        }
    }

    // MARK: Abaixo do campo

    private var rodapeDoCampo: some View {
        Group {
            if let erro {
                aviso(erro, cor: Tema.vermelho, icone: "exclamationmark.triangle.fill")
            } else if let impedimento {
                aviso(impedimento, cor: Tema.ambar, icone: "exclamationmark.circle.fill")
            } else {
                Text("Enter envia  ·  ⇧Enter quebra a linha")
                    .font(.system(size: 11))
                    .foregroundStyle(Tema.texto3)
            }
        }
        .padding(.top, 10)
    }

    private func aviso(_ texto: String, cor: Color, icone: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icone).font(.system(size: 11))
            Text(texto).font(.system(size: 12)).lineLimit(2)
        }
        .foregroundStyle(cor.opacity(0.9))
        .multilineTextAlignment(.center)
    }

    /// Atalhos discretos: as sessões que pedem resposta e os projetos mais recentes.
    @ViewBuilder
    private var atalhos: some View {
        let pendentes = Array(SessoesCrew.pendentes(state).prefix(3))
        let recentes = projetosRecentes
        if !pendentes.isEmpty || !recentes.isEmpty {
            FluxoCrew(espaco: 8) {
                ForEach(pendentes) { t in
                    BotaoChip(icone: "hand.raised.fill", texto: t.displayTitle, cor: Tema.ambar) { nav.abrir(t.id) }
                        .help("Pede sua resposta")
                }
                ForEach(recentes) { p in
                    BotaoChip(ponto: Color(hex: p.cor), texto: p.nome) {
                        nav.projetoInicio = p.caminho
                        nav.focoInicio += 1
                    }
                    .help("Nova sessão em \(p.caminhoCurto)")
                }
            }
        }
    }

    /// Projetos com sessão mais recente primeiro (sem o já escolhido), no máximo quatro.
    private var projetosRecentes: [ProjetoCrew] {
        let atual = projeto?.caminho
        var ultima: [String: Date] = [:]
        for t in SessoesCrew.todas(state) {
            guard let r = Projetos.raiz(de: t.sessionCwd) else { continue }
            ultima[r] = max(ultima[r] ?? .distantPast, t.lastEvent)
        }
        return Array(projetos.lista.enumerated()
            .filter { $0.element.caminho != atual }
            .sorted {
                let a = ultima[$0.element.caminho] ?? .distantPast, b = ultima[$1.element.caminho] ?? .distantPast
                return a != b ? a > b : $0.offset < $1.offset
            }
            .map(\.element)
            .prefix(4))
    }

    // MARK: Abrindo

    private func abrindo(_ a: SessaoAbrindo) -> some View {
        VStack(spacing: 16) {
            HStack(spacing: 14) {
                HomieVivo(estado: .working, tamanho: 84, olhar: olhar)
                    .frame(width: 84, height: 66)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Abrindo a sessão em \(a.projeto)…")
                        .font(Tema.titulo(20))
                        .foregroundStyle(Tema.texto)
                    Text("A conversa aparece quando o Claude Code começar. Se ele perguntar algo antes, responda aqui.")
                        .font(.system(size: 13))
                        .foregroundStyle(Tema.texto2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            if a.doCrew, let sid = a.sessionId {
                TerminalSessao(sessionId: sid)
                    .frame(height: 320)
            }
            HStack(spacing: 8) {
                if a.doCrew, let sid = a.sessionId {
                    BotaoPilula(titulo: "Abrir no Terminal", icone: "macwindow", altura: 30) {
                        Task { await MotorCrew.abrirNoTerminal(sid) }
                    }
                    BotaoPilula(titulo: "Encerrar", icone: "stop.fill", estilo: .perigo, altura: 30) {
                        nav.abrindo = nil
                        Task { _ = await MotorCrew.encerrar(sid) }
                    }
                    .help("Fecha o Claude Code dessa sessão")
                }
                Spacer()
                BotaoPilula(titulo: "Voltar ao início", estilo: .discreto, altura: 30) { nav.abrindo = nil }
                    .help("A sessão continua abrindo e aparece na lista quando começar")
            }
        }
    }

    // MARK: Abrir

    private func abrir() {
        let pedido = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let p = projeto, temCrew, !enviando, !CaptureTool.ativo,
              !pedido.isEmpty || !anexos.isEmpty else { return }
        // Sessão nova ainda não tem onde colar arquivo: os caminhos vão no texto do pedido.
        let completo = MarcasImagem.textoComCaminhos(pedido, anexos: anexos)
        let c = padroes
        let opcoes = MotorCrew.Opcoes(modelo: modelo, modo: modo, esforco: c.esforco, instrucao: c.instrucao)
        let conhecidas = Set(state.tasks.map(\.id))
        enviando = true
        erro = nil
        Task {
            // Projeto com isolamento: o comando dele cria a pasta própria da sessão antes.
            var pasta = p.caminho
            if c.isolamentoPronto {
                switch await IsolamentoProjeto.preparar(raiz: p.caminho, config: c, pedido: pedido) {
                case .success(let propria): pasta = propria
                case .failure(let f): erro = f.mensagem
                }
            }
            if erro == nil {
                switch await MotorCrew.nova(pasta: pasta, pedido: completo, opcoes: opcoes) {
                case .success(let sid): abriu(sid, em: p, conhecidas: conhecidas, doCrew: true)
                case .failure(let f): erro = "Não foi: \(f.mensagem.prefix(200))"
                }
            }
            enviando = false
            // Não abriu: o pedido continua no campo, pronto para tentar de novo.
            if erro != nil { nav.focoInicio += 1 }
        }
    }

    private func abriu(_ sessionId: String?, em p: ProjetoCrew, conhecidas: Set<String>, doCrew: Bool) {
        projetos.ultimo = p.caminho
        nav.pedidoEnviado = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        // O campo solta o cursor antes de esvaziar: ao sair da tela com o cursor dentro, o
        // editor de texto devolvia o que tinha escrito e o pedido voltava como rascunho.
        NSApp.keyWindow?.makeFirstResponder(nil)
        limpar()
        Task { @MainActor in
            if nav.abrindo != nil || nav.selecao != .inicio { texto = ""; anexos = [] }
        }
        nav.abrindo = SessaoAbrindo(sessionId: sessionId, caminho: p.caminho, projeto: p.nome,
                                    conhecidas: conhecidas, doCrew: doCrew)
        nav.procurarNova(state.tasks)
    }
}
