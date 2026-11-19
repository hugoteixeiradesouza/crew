import SwiftUI
import AppKit

// Uma sessão do Claude Code no app do Crew: cabeçalho enxuto (título, projeto, branch, de
// onde roda, ações), a conversa no centro e, embaixo, o que ela espera do Hugo (aprovação ou
// pergunta) logo acima do campo para falar com ela. Fala pelo mesmo caminho do chat da ilha
// (Xirp, tmux, Terminal, iTerm — TerminalBridge). Sessões do motor do Crew ganham o
// "Terminal": a tela ao vivo, para o que os hooks não contam.

struct ConversaCrew: View {
    @Environment(\.recuoTitulo) private var recuoTitulo
    let taskId: String
    /// Um dos painéis da tela dividida: cabeçalho e margens enxutos.
    var compacto = false
    /// O painel em que o Hugo está (só na tela dividida).
    var emFoco = false
    /// Entregou e o Hugo ainda não olhou (painel da grade fora de foco).
    var atencao = false
    /// Fecha este painel (só na tela dividida).
    var aoFechar: (() -> Void)? = nil
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var modelos = ModelosSessoes.shared
    @EnvironmentObject private var nav: NavegacaoCrew
    @Environment(\.telaVisivel) private var visivel

    @State private var mensagens: [SessionMessage] = []
    /// Já leu o transcript ao menos uma vez (sem isso, "sem conversa" pisca ao abrir).
    @State private var leu = false
    /// Tempo e tokens do turno em andamento.
    @State private var andamento = AndamentoTurno()
    /// Quantas falas recentes estão carregadas (cresce quando o Hugo sobe a conversa).
    @State private var limite = 30
    @State private var temMais = false
    @State private var carregandoMais = false
    @State private var abertaEm = Date()
    /// A conversa está rolada até o fim (ou perto dele).
    @State private var noFim = true
    @State private var canal: SessionChannel?
    /// A sessão roda no motor do Crew (tmux `crew-<id>`).
    @State private var doCrew = false
    /// Terminal à mostra: nil = automático (aparece enquanto não há conversa).
    @State private var terminalEscolhido: Bool?
    /// O shell do Hugo na pasta da sessão está aberto ao lado (botão "Terminal").
    @State private var shellAberto = false
    @State private var texto = ""
    @State private var anexos: [URL] = []
    @State private var enviando = false
    @State private var aviso: String?
    @State private var renomeando = false
    @State private var novoNome = ""
    @State private var foco = 0
    @FocusState private var nomeFocado: Bool
    /// O menu que um comando ("/model") abriu no terminal da sessão, mostrado aqui no chat.
    @State private var menuComando: MenuDoTerminal?
    @State private var vigiaComando: Task<Void, Never>?
    /// Quanto da largura fica com o terminal quando ele abre ao lado da conversa.
    @AppStorage("modulo.sessoes.fracaoTerminal") private var fracaoTerminal = 0.5

    /// O que cada sessão já tinha na tela: voltar a ela (trocar de sessão, entrar e sair da
    /// grade) mostra a conversa na hora, sem tela vazia enquanto relê.
    private static var guardadas: [String: (leitura: LeituraConversa, limite: Int)] = [:]

    init(taskId: String, compacto: Bool = false, emFoco: Bool = false, atencao: Bool = false,
         aoFechar: (() -> Void)? = nil) {
        self.taskId = taskId
        self.compacto = compacto
        self.emFoco = emFoco
        self.atencao = atencao
        self.aoFechar = aoFechar
        if let g = Self.guardadas[taskId] {
            _mensagens = State(initialValue: g.leitura.mensagens)
            _temMais = State(initialValue: g.leitura.temMais)
            _andamento = State(initialValue: g.leitura.andamento)
            _limite = State(initialValue: g.limite)
            _leu = State(initialValue: true)
        }
    }

    private var task: AgentTask? { state.tasks.first { $0.id == taskId } }
    private var pendencia: ApprovalInfo? { task?.sessionId.flatMap { state.pendingApprovals[$0] } }
    /// O navegador está aberto ao lado desta conversa (só na tela cheia).
    private var mostraNavegador: Bool { !compacto && nav.navegadorCom.contains(taskId) }
    private var mostraArquivos: Bool { !compacto && nav.arquivosCom.contains(taskId) }
    /// Os arquivos estão no lugar da conversa (visualização principal).
    private var arquivosNoLugar: Bool { mostraArquivos && nav.arquivosPrincipal.contains(taskId) }

    private func arquivos(_ pasta: String) -> some View {
        ArquivosProjeto(raiz: pasta, mencionar: { caminho in
            texto += (texto.isEmpty || texto.hasSuffix(" ") ? "" : " ") + "@" + caminho + " "
            // Mencionou: volta para a conversa, com o campo pronto.
            nav.arquivosPrincipal.remove(taskId)
            foco += 1
        }, principal: arquivosNoLugar, alternarPrincipal: {
            if nav.arquivosPrincipal.contains(taskId) { nav.arquivosPrincipal.remove(taskId) } else { nav.arquivosPrincipal.insert(taskId) }
        }, aoFechar: {
            nav.arquivosCom.remove(taskId)
            nav.arquivosPrincipal.remove(taskId)
        })
    }
    private var mostraTerminal: Bool {
        // Sem conversa ainda, o terminal aparece sozinho — menos no painel da grade, onde ele
        // tomaria o lugar do chat (sessão em branco na grade é para escrever).
        doCrew && (terminalEscolhido ?? (!compacto && leu && mensagens.isEmpty))
    }

    var body: some View {
        if let task {
            VStack(spacing: 0) {
                cabecalho(task).padding(.leading, recuoTitulo)
                Fio()
                Group {
                    if mostraTerminal, compacto, let sid = task.sessionId {
                        // Painel da grade: estreito demais para dois — o terminal toma o lugar da conversa.
                        TerminalSessao(sessionId: sid)
                            .padding(.horizontal, margem).padding(.top, 14).padding(.bottom, 6)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .safeAreaInset(edge: .bottom, spacing: 0) { doca(task) }
                    } else {
                        // Tela cheia: o terminal abre ao lado da conversa, que continua onde estava.
                        GeometryReader { geo in
                            HStack(spacing: 0) {
                                if arquivosNoLugar, let pasta = task.sessionCwd {
                                    // Arquivos como visualização principal: tomam o lugar da conversa.
                                    arquivos(pasta)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                } else {
                                    conversa(task)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                                if mostraNavegador {
                                    divisorDoTerminal(largura: geo.size.width)
                                    NavegadorView(projeto: nil,
                                                  sessao: SessaoDoNavegador(id: task.id, nome: task.displayTitle,
                                                                            cor: Projetos.cor(de: task.sessionCwd))) { nav.navegadorCom.remove(taskId) }
                                        .environment(\.recuoTitulo, 0)
                                        .frame(width: larguraTerminal(em: geo.size.width))
                                } else if mostraArquivos, !arquivosNoLugar, let pasta = task.sessionCwd {
                                    divisorDoTerminal(largura: geo.size.width)
                                    arquivos(pasta)
                                        .frame(width: larguraTerminal(em: geo.size.width))
                                } else if shellAberto, let sid = task.sessionId, let pasta = task.sessionCwd {
                                    divisorDoTerminal(largura: geo.size.width)
                                    TerminalSessao(sessionId: sid, pasta: pasta)
                                        .padding(.leading, 4).padding(.trailing, 12).padding(.vertical, 12)
                                        .frame(width: larguraTerminal(em: geo.size.width))
                                } else if mostraTerminal, let sid = task.sessionId {
                                    divisorDoTerminal(largura: geo.size.width)
                                    TerminalSessao(sessionId: sid)
                                        .padding(.leading, 4).padding(.trailing, 12).padding(.vertical, 12)
                                        .frame(width: larguraTerminal(em: geo.size.width))
                                }
                            }
                            .coordinateSpace(name: "dividida")
                        }
                    }
                }
            }
            // Tela dividida: um fio de cor marca o painel em que o Hugo está.
            .overlay(alignment: .top) {
                if compacto { Rectangle().fill(emFoco ? Tema.azul : atencao ? Tema.verde : .clear).frame(height: 2) }
            }
            .task(id: "\(taskId)|\(visivel)") { await acompanhar() }
            .task(id: task.lastEvent) { await modelos.atualizar(task.transcriptPath) }
            // Entrou em foco na grade (⌘← ⌘→ ou clique): o cursor vai para o campo dela.
            .onChange(of: emFoco) { _, f in if f { foco += 1 } }
        }
    }

    // MARK: Terminal ao lado

    private func larguraTerminal(em total: CGFloat) -> CGFloat {
        max(300, min(total - 340, total * fracaoTerminal))
    }

    /// O fio entre a conversa e o terminal: arrastar muda a divisão.
    private func divisorDoTerminal(largura total: CGFloat) -> some View {
        Rectangle().fill(Tema.borda).frame(width: 1)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
            .onHover { dentro in
                if dentro { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named("dividida")).onChanged { g in
                guard total > 0 else { return }
                fracaoTerminal = min(max(1 - Double(g.location.x / total), 0.25), 0.75)
            })
            .help("Arraste para mudar a divisão")
    }

    // MARK: Cabeçalho

    private func cabecalho(_ t: AgentTask) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                if renomeando {
                    TextField("", text: $novoNome, prompt: Text("Nome da sessão").foregroundStyle(Tema.texto3))
                        .textFieldStyle(.plain)
                        .font(Tema.titulo(15))
                        .foregroundStyle(Tema.texto)
                        .focused($nomeFocado)
                        .onSubmit { state.renomear(t.id, para: novoNome); renomeando = false }
                        .onExitCommand { renomeando = false }
                        .onChange(of: nomeFocado) { _, f in if !f { renomeando = false } }
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.07)))
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Tema.bordaForte))
                        .frame(maxWidth: 380)
                        .padding(.leading, -8)
                } else {
                    Text(t.displayTitle)
                        .font(Tema.titulo(15))
                        .foregroundStyle(Tema.texto)
                        .lineLimit(1)
                        .onTapGesture(count: 2) { comecarRenomear(t) }
                        .help("Dois cliques para renomear")
                }
                HStack(spacing: 6) {
                    Circle().fill(Color(hex: Projetos.cor(de: t.sessionCwd) ?? t.color)).frame(width: 6, height: 6)
                    Text(Projetos.nome(de: t.sessionCwd) ?? t.name)
                    if let b = Projetos.branch(de: t.sessionCwd) {
                        Text("·").foregroundStyle(Tema.texto3)
                        Image(systemName: "arrow.triangle.branch").font(.system(size: 9))
                        Text(b).truncationMode(.middle)
                    }
                    Text("·").foregroundStyle(Tema.texto3)
                    Text(origem)
                    if let m = modelos.nome(de: t) {
                        Text("·").foregroundStyle(Tema.texto3)
                        Text(m)
                    }
                }
                .font(.system(size: 11.5))
                .foregroundStyle(Tema.texto2)
                .lineLimit(1)
                .help(t.sessionCwd?.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~") ?? "")
            }
            Spacer(minLength: 12)
            if compacto {
                Circle().fill(CorDoEstado.de(t.state, esperando: pendencia != nil)).frame(width: 8, height: 8)
                    .help(SessoesCrew.rotulo(t, esperando: pendencia != nil))
            } else {
                PilulaEstado(texto: SessoesCrew.rotulo(t, esperando: pendencia != nil),
                             cor: CorDoEstado.de(t.state, esperando: pendencia != nil))
            }
            if t.sessionCwd != nil, !compacto {
                // "Terminal": um shell novo na pasta da sessão, para os comandos do Hugo.
                AlternadorTerminal(ligado: shellAberto && !mostraNavegador && !mostraArquivos) {
                    if mostraNavegador || mostraArquivos {
                        nav.navegadorCom.remove(taskId); nav.arquivosCom.remove(taskId); shellAberto = true
                    } else { shellAberto.toggle() }
                }
            }
            HStack(spacing: 2) {
                if !compacto {
                    if t.sessionCwd != nil {
                        BotaoIcone(icone: "folder", ajuda: mostraArquivos ? "Fechar os arquivos" : "Arquivos do projeto, ao lado",
                                   ativo: mostraArquivos) {
                            if mostraArquivos { nav.arquivosCom.remove(taskId) }
                            else { nav.navegadorCom.remove(taskId); nav.arquivosCom.insert(taskId) }
                        }
                    }
                    BotaoIcone(icone: "globe", ajuda: mostraNavegador ? "Recolher o navegador (⌘J)" : "Abrir o navegador ao lado (⌘J)",
                               ativo: mostraNavegador) {
                        if mostraNavegador { nav.navegadorCom.remove(taskId) } else { nav.abrirNavegador(taskId) }
                    }
                    // Sessão de fora do Crew (Xirp, Terminal, iTerm): atalho para ir até onde ela roda.
                    if !doCrew {
                        BotaoIcone(icone: "arrow.up.forward.app", ajuda: "Ir para onde a sessão roda (\(origem))") {
                            abrirSessao(t)
                        }
                    }
                    if podeEncerrar {
                        BotaoIcone(icone: "stop.circle", ajuda: "Encerrar a sessão (a conversa fica salva)",
                                   corHover: Tema.vermelho) { nav.pedirEncerrar = t.id }
                    }
                }
                menuDividir(t)
                BotaoIconeMenu(icone: "ellipsis", ajuda: "Mais ações") {
                    var itens: [ItemMenu] = [.acao("Renomear", icone: "pencil") { comecarRenomear(t) }]
                    if doCrew {
                        itens.append(.acao("Abrir a sessão no app Terminal", icone: "macwindow", detalhe: "fora do Crew, ligada à mesma sessão") {
                            abrirSessao(t)
                        })
                    }
                    if doCrew, !compacto {
                        itens.append(.acao(mostraTerminal && !shellAberto ? "Fechar o terminal da sessão" : "Ver o terminal da sessão",
                                           icone: "terminal", detalhe: "o Claude Code rodando") {
                            let abrir = !(mostraTerminal && !shellAberto)
                            shellAberto = false
                            nav.navegadorCom.remove(taskId); nav.arquivosCom.remove(taskId)
                            terminalEscolhido = abrir
                        })
                    }
                    if compacto {
                        if doCrew {
                            itens.append(.acao(mostraTerminal ? "Voltar para a conversa" : "Ver o terminal", icone: "terminal") {
                                terminalEscolhido = !mostraTerminal
                            })
                        }
                        if podeEncerrar {
                            itens.append(.acao("Encerrar a sessão…", icone: "stop.circle", destrutivo: true) { nav.pedirEncerrar = t.id })
                        }
                    }
                    return itens + [.divisor] + MenuSessao.itens(t)
                }
                if let aoFechar {
                    BotaoIcone(icone: "xmark", ajuda: "Tirar da grade (a sessão continua)", acao: aoFechar)
                }
            }
        }
        .padding(.leading, margem).padding(.trailing, compacto ? 8 : 14)
        .frame(height: 60)
        .contentShape(Rectangle())
        // Na grade, arrastar o cabeçalho leva o painel para o lugar de outro.
        .simultaneousGesture(compacto ? arrasteDoPainel : nil)
    }

    private var arrasteDoPainel: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .named("grade"))
            .onChanged { nav.arrastar(taskId, em: $0.location) }
            .onEnded { _ in nav.soltar() }
    }

    /// Margem lateral: larga na tela cheia, enxuta no painel da tela dividida.
    private var margem: CGFloat { compacto ? 14 : 24 }

    /// "Grade": põe esta sessão na grade (⌘G) ou escolhe outra para abrir ao lado.
    @ViewBuilder
    private func menuDividir(_ t: AgentTask) -> some View {
        BotaoIconeMenu(icone: "rectangle.split.2x1", ajuda: "Grade: várias sessões na mesma tela, até 4 × 4 (⌘G)") {
            let naGrade = nav.emGrade && nav.paineis.contains(t.id)
            var itens: [ItemMenu] = [
                .acao(naGrade ? "Sair da grade" : nav.paineis.contains(t.id) ? "Voltar para a grade" : "Pôr esta sessão na grade",
                      icone: naGrade ? "rectangle" : "rectangle.split.2x1", detalhe: "⌘G") {
                    nav.selecao = .sessao(t.id)
                    nav.alternarGrade()
                },
            ]
            if naGrade {
                // A configuração da grade: quantas colunas (as linhas saem do número de sessões; até 4 × 4).
                itens += [.divisor, .titulo("Colunas da grade")]
                itens += [0, 1, 2, 3, 4].map { n in
                    .acao(n == 0 ? "Automático" : n == 1 ? "1 coluna" : "\(n) colunas", marcado: nav.colunasGrade == n) {
                        nav.colunasGrade = n
                    }
                }
                if !nav.pesoPainel.isEmpty || !nav.pesoLinha.isEmpty {
                    itens.append(.acao("Igualar os tamanhos", icone: "rectangle.grid.2x2") { nav.igualarGrade() })
                }
                if nav.paineis.count > 1 {
                    itens += [.divisor, .titulo("Lugar na grade (ou arraste o cabeçalho)"),
                              .acao("Mover para antes", icone: "arrow.left", detalhe: "⌃⌘←",
                                    desabilitado: nav.paineis.first == t.id) { nav.moverPainel(t.id, passo: -1) },
                              .acao("Mover para depois", icone: "arrow.right", detalhe: "⌃⌘→",
                                    desabilitado: nav.paineis.last == t.id) { nav.moverPainel(t.id, passo: 1) }]
                }
            }
            let outras = SessoesCrew.todas(state).filter { $0.id != t.id && !nav.paineis.contains($0.id) }
                .sorted { $0.lastEvent > $1.lastEvent }
            if !outras.isEmpty, nav.paineis.count < NavegacaoCrew.maxPaineis {
                itens += [.divisor, .titulo("Pôr na grade")]
                itens += outras.map { o in
                    .acao(o.displayTitle, ponto: Color(hex: Projetos.cor(de: o.sessionCwd) ?? o.color),
                          detalhe: Projetos.nome(de: o.sessionCwd) ?? o.name) {
                        nav.selecao = .sessao(t.id)
                        nav.abrirAoLado(o.id)
                    }
                }
            }
            return itens
        }
    }

    private var podeEncerrar: Bool {
        if doCrew { return true }
        if case .xirp? = canal { return true }
        return false
    }

    private func comecarRenomear(_ t: AgentTask) {
        novoNome = t.displayTitle
        renomeando = true
        nomeFocado = true
    }

    private var origem: String {
        if doCrew { return "Crew" }
        switch canal {
        case .xirp?: return "Xirp"
        case .tmux?: return "tmux"
        case .terminal?: return "Terminal"
        case .iterm?: return "iTerm"
        case .none(let app)?: return app
        case nil: return "…"
        }
    }

    // MARK: Conversa

    private func conversa(_ t: AgentTask) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 26) {
                    if mensagens.isEmpty {
                        VStack(spacing: 8) {
                            if leu {
                                Text("Sem conversa para mostrar ainda.")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Tema.texto3)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                    }
                    if temMais {
                        // Chegou no topo do que está carregado: busca as falas anteriores.
                        Button { carregarMais(proxy) } label: {
                            HStack(spacing: 7) {
                                if carregandoMais { ProgressView().controlSize(.small).scaleEffect(0.7) }
                                Text(carregandoMais ? "Carregando…" : "Carregar mensagens anteriores")
                                    .font(.system(size: 11.5))
                            }
                            .foregroundStyle(Tema.texto3)
                            .frame(maxWidth: .infinity)
                            .frame(height: 26)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id("mais-\(limite)")
                        // Só busca sozinho quando o Hugo subiu de verdade até aqui.
                        .onAppear { if !noFim, Date().timeIntervalSince(abertaEm) > 0.8 { carregarMais(proxy) } }
                    }
                    let turnos = TurnoConversa.agrupar(mensagens)
                    let trabalhando = [.working, .thinking, .searching].contains(t.state)
                    ForEach(turnos) { turno in
                        // O último turno, com a sessão trabalhando, mostra os passos abertos.
                        TurnoCrew(turno: turno, vivo: trabalhando && turno.id == turnos.last?.id)
                    }
                    if trabalhando {
                        // O plano do Claude (a lista de tarefas que ele marca enquanto trabalha).
                        let tarefas = ListaDeTarefas.montar(mensagens)
                        if !tarefas.isEmpty {
                            CartaoTarefas(tarefas: tarefas)
                                .transition(.opacity)
                        }
                        // O passo que roda agora vem do transcript (a ferramenta ainda sem
                        // resultado); sem isso, vale o que o hook contou.
                        let rodando = turnos.last?.passoRodando
                        IndicadorTrabalho(estado: t.state,
                                          passo: rodando?.frase ?? t.steps.last ?? t.stateLabel,
                                          andamento: andamento, desdePasso: rodando?.quando)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    Color.clear.frame(height: 1).id("fim")
                }
                .padding(.horizontal, compacto ? 4 : 12).padding(.top, 26).padding(.bottom, 14)
                .frame(maxWidth: Tema.larguraConversa)
                .padding(.horizontal, margem)
                .frame(maxWidth: .infinity)
            }
            // Arquivo citado sem o caminho inteiro é procurado na pasta da sessão.
            .environment(\.pastaDaSessao, t.sessionCwd)
            // Abre no fim da conversa; conversa curta começa em cima.
            .defaultScrollAnchor(.bottom)
            .defaultScrollAnchor(.top, for: .alignment)
            .safeAreaInset(edge: .bottom, spacing: 0) { doca(t) }
            .onScrollGeometryChange(for: Bool.self) { g in
                g.contentOffset.y + g.containerSize.height >= g.contentSize.height - 120
            } action: { _, v in noFim = v }
            // No fim da conversa, a rolagem já acompanha sozinha o que chega (âncora embaixo),
            // sem pulo. Lendo mais acima, nada se mexe. Só a fala do próprio Hugo leva ao fim.
            .onChange(of: mensagens.last?.id) { _, _ in
                if mensagens.last?.fromUser == true, !noFim { proxy.scrollTo("fim", anchor: .bottom) }
            }
            .onChange(of: pendencia?.sessionId) { _, _ in
                DispatchQueue.main.async { proxy.scrollTo("fim", anchor: .bottom) }
            }
        }
    }

    /// Carrega mais 40 falas antigas e mantém na tela a que estava no topo.
    private func carregarMais(_ proxy: ScrollViewProxy) {
        guard leu, temMais, !carregandoMais else { return }
        carregandoMais = true
        let topo = TurnoConversa.agrupar(mensagens).first?.id
        limite += 40
        Task {
            await reler(animar: false)
            if let topo { proxy.scrollTo(topo, anchor: .top) }
            carregandoMais = false
        }
    }

    /// Relê o fim do transcript (só o pedaço que cobre as falas carregadas).
    private func reler(animar: Bool) async {
        let caminho = task?.transcriptPath
        let n = limite
        let l = await Task.detached(priority: .userInitiated) { TranscriptReader.ler(path: caminho, limit: n) }.value
        if l.mensagens != mensagens {
            // Sem animação: fala entrando com a tela deslizando fazia a conversa pular.
            mensagens = l.mensagens
        }
        if Self.guardadas.count > 12, Self.guardadas[taskId] == nil { Self.guardadas.removeAll() }
        Self.guardadas[taskId] = (l, n)
        if l.temMais != temMais { temMais = l.temMais }
        if l.andamento != andamento { andamento = l.andamento }
        leu = true
    }

    // MARK: Doca: pendência + campo

    /// O que fica preso embaixo: a aprovação/pergunta (a ação principal do app) e o campo.
    private func doca(_ t: AgentTask) -> some View {
        VStack(spacing: 10) {
            if let p = pendencia {
                CartaoPendencia(approval: p)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if pendencia == nil, menuComando == nil, [.approval, .question].contains(t.state) {
                // A pergunta/permissão voltou para o terminal: a sessão está parada esperando lá.
                CartaoNoTerminal(pergunta: t.state == .question,
                                 verTerminal: compacto || !doCrew ? nil : {
                                     nav.navegadorCom.remove(taskId); nav.arquivosCom.remove(taskId)
                                     shellAberto = false; terminalEscolhido = true
                                 })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if let m = menuComando, pendencia == nil, let sid = t.sessionId {
                CartaoComando(menu: m,
                              escolher: { i in escolherNoMenu(sid, m, i) },
                              cancelar: { Task { _ = await MotorCrew.tecla(sid, "Escape") } },
                              verTerminal: compacto ? nil : {
                                  nav.navegadorCom.remove(taskId); nav.arquivosCom.remove(taskId)
                                  shellAberto = false; terminalEscolhido = true
                              })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            CompositorCrew(texto: $texto, anexos: $anexos, placeholder: placeholder(t),
                           habilitado: podeEnviar, enviando: enviando, foco: foco,
                           comandos: MenuDoTerminal.comandos, aoEnviar: enviar)
                .modifier(GuardaRascunho(chave: taskId, texto: $texto, anexos: $anexos))
            if let aviso {
                Text(aviso)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Tema.ambar)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
            }
        }
        .frame(maxWidth: Tema.larguraConversa)
        .padding(.horizontal, margem).padding(.top, 10).padding(.bottom, compacto ? 12 : 18)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(stops: [.init(color: Tema.fundo.opacity(0), location: 0),
                                   .init(color: Tema.fundo.opacity(0.94), location: 0.22),
                                   .init(color: Tema.fundo, location: 1)],
                           startPoint: .top, endPoint: .bottom)
        )
        .animation(.snappy(duration: 0.25), value: pendencia?.sessionId)
        .animation(.snappy(duration: 0.2), value: menuComando)
        .onDisappear { vigiaComando?.cancel() }
    }

    /// Mandou um comando ("/…") numa sessão do motor do Crew: olha a tela do terminal dela e,
    /// se o comando abriu um menu, mostra as opções aqui. Só enquanto o menu está aberto.
    private func vigiarComando(_ sid: String) {
        vigiaComando?.cancel()
        vigiaComando = Task {
            var semMenu = 0
            // Espera o menu aparecer por até ~4 s; depois acompanha até ele fechar (no máximo 5 min).
            for _ in 0..<600 {
                try? await Task.sleep(for: .milliseconds(450))
                if Task.isCancelled { return }
                let lido = await MotorCrew.tela(sid).flatMap(MenuDoTerminal.ler)
                if lido != menuComando { menuComando = lido }
                semMenu = lido == nil ? semMenu + 1 : 0
                if semMenu >= 9 { break }
            }
            menuComando = nil
        }
    }

    /// Clique numa opção: leva o ponteiro do terminal até ela e confirma.
    private func escolherNoMenu(_ sid: String, _ m: MenuDoTerminal, _ i: Int) {
        Task {
            let passos = i - m.marcada
            for _ in 0..<abs(passos) { _ = await MotorCrew.tecla(sid, passos > 0 ? "Down" : "Up") }
            _ = await MotorCrew.tecla(sid, "Enter")
        }
    }

    private var podeEnviar: Bool {
        guard let canal else { return false }
        if case .none = canal { return false }
        return !enviando
    }

    private func placeholder(_ t: AgentTask) -> String {
        if case .none(let app)? = canal { return "Essa sessão roda no \(app), que não aceita texto de fora — responda lá" }
        if canal == nil { return "Procurando por onde falar com a sessão…" }
        return compacto ? "Falar com a sessão…" : "Falar com \(t.displayTitle)…"
    }

    private func enviar() {
        let msg = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let canal, podeEnviar, !msg.isEmpty || !anexos.isEmpty else { return }
        let indo = anexos
        // Cada [Image #N] do texto vira a imagem naquele ponto; os outros anexos vão antes.
        let pecas = MarcasImagem.pecas(msg, anexos: indo)
        enviando = true
        aviso = nil
        Task {
            let erro = await TerminalBridge.send(pecas: pecas, via: canal)
            enviando = false
            if let erro {
                aviso = "Não foi: \(erro.prefix(160))"
            } else {
                texto = ""
                anexos.removeAll { indo.contains($0) }
                if let t = task { state.mostrar(t.id) }
                if msg.hasPrefix("/"), doCrew, let sid = task?.sessionId { vigiarComando(sid) }
            }
            foco += 1
        }
    }

    // MARK: Acompanhar

    /// Enquanto a sessão está na tela (e a janela à vista): acha por onde falar com ela e
    /// relê o transcript quando ele cresce.
    private func acompanhar() async {
        guard let t = task else { return }
        let sid = t.sessionId ?? ""
        if CaptureTool.ativo {
            // Capturas: sem consultar o Xirp nem o terminal; só a conversa de exemplo.
            doCrew = nav.cena?.terminal == true
            canal = doCrew ? .tmux(pane: "captura") : .xirp("captura")
            mensagens = TranscriptReader.ler(path: t.transcriptPath, limit: 200).mensagens
            leu = true
            return
        }
        guard visivel else { return }
        // A conversa aparece já; achar por onde falar (consulta ao Xirp) corre em paralelo.
        if canal == nil { Task { await acharCanal(sid) } }
        var volta = 0
        var tamanho: UInt64 = 0
        var primeira = true
        while !Task.isCancelled {
            volta += 1
            // Não achou por onde falar? Tenta de novo de tempos em tempos.
            if volta % 8 == 0, case .none? = canal { await acharCanal(sid) }
            let caminho = task?.transcriptPath
            let novo = (caminho.flatMap { try? FileManager.default.attributesOfItem(atPath: $0)[.size] as? UInt64 }) ?? 0
            if novo != tamanho || primeira {
                tamanho = novo
                primeira = false
                await reler(animar: true)
            }
            try? await Task.sleep(for: .seconds(0.8))
        }
    }

    /// Motor do Crew primeiro (um `tmux has-session`); só então pergunta ao Xirp.
    private func acharCanal(_ sid: String) async {
        let cur = task
        doCrew = await MotorCrew.ehDoCrew(sid)
        if doCrew {
            // O tmux dela tem nome certo: fala direto com ele, sem procurar pelo tty.
            canal = .tmux(pane: "=" + MotorCrew.nomeTmux(sid) + ":")
            return
        }
        let xid = await Xirp.sessionId(forClaudeSession: sid)
        canal = await TerminalBridge.channel(claudePid: cur?.claudePid, bundleId: cur?.sessionAppBundleId, xirpId: xid)
    }
}

/// "Terminal": liga e desliga a tela ao vivo da sessão (motor do Crew).
private struct AlternadorTerminal: View {
    let ligado: Bool
    let acao: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: acao) {
            HStack(spacing: 5) {
                Image(systemName: "terminal").font(.system(size: 10.5, weight: .semibold))
                Text("Terminal").font(.system(size: 11.5, weight: .medium))
            }
            .foregroundStyle(ligado ? Tema.sobreDestaque : hover ? Tema.texto : Tema.texto2)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(Pilula().fill(ligado ? Tema.destaque : Color.white.opacity(hover ? 0.1 : 0.05)))
            .overlay(Pilula().strokeBorder(ligado ? .clear : Tema.borda))
            .contentShape(Pilula())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(ligado ? "Fechar o terminal (o que estiver rodando continua)" : "Abrir um terminal seu na pasta da sessão")
    }
}

// MARK: - Trabalhando

/// O Claude está trabalhando: o Homie, o passo atual com um brilho correndo pelo texto, e o
/// tempo e os tokens do turno andando ao vivo (como a linha de estado do terminal).
struct IndicadorTrabalho: View {
    let estado: BotState
    let passo: String
    let andamento: AndamentoTurno
    /// Desde quando roda o passo atual (a ferramenta ainda sem resultado no transcript).
    var desdePasso: Date? = nil
    @Environment(\.telaVisivel) private var visivel

    var body: some View {
        HStack(spacing: 9) {
            HomieVivo(estado: estado, tamanho: 30, quadro: 1.0 / 30)
                .frame(width: 22, height: 22)
            TextoBrilhando(texto: passo.hasSuffix("…") ? passo : passo + "…", vivo: visivel)
                .layoutPriority(1)
            if let inicio = andamento.inicio {
                TimelineView(.periodic(from: .now, by: 1)) { tl in
                    Text(Self.noPasso(desde: desdePasso, agora: tl.date)
                         + Self.resumo(desde: inicio, agora: tl.date, tokens: andamento.tokens))
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(Tema.texto3)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        }
        .padding(.leading, 6).padding(.trailing, 14)
        .frame(height: 36)
        .background(Pilula().fill(Color.white.opacity(0.04)))
        .overlay(Pilula().strokeBorder(Tema.borda))
    }

    /// "passo 12s · total " — quanto o passo atual já leva, quando passa de uns segundos.
    static func noPasso(desde inicio: Date?, agora: Date) -> String {
        guard let inicio else { return "" }
        let s = Int(agora.timeIntervalSince(inicio))
        return s >= 3 ? "passo \(LeitorPassos.duracao(Double(s))) · total " : ""
    }

    /// "1m 8s · ↓ 8.3k tokens"
    static func resumo(desde inicio: Date, agora: Date, tokens: Int) -> String {
        let s = max(0, Int(agora.timeIntervalSince(inicio)))
        let tempo = s < 60 ? "\(s)s" : s < 3600 ? "\(s / 60)m \(s % 60)s" : "\(s / 3600)h \(s % 3600 / 60)m"
        guard tokens > 0 else { return tempo }
        let t = tokens < 1000 ? "\(tokens)" : String(format: "%.1fk", Double(tokens) / 1000)
        return "\(tempo) · ↓ \(t) tokens"
    }
}

/// Texto com uma faixa de luz passando da esquerda para a direita.
struct TextoBrilhando: View {
    let texto: String
    var vivo = true

    private var base: Text { Text(texto).font(.system(size: 12.5, weight: .medium)) }

    var body: some View {
        base.foregroundStyle(Tema.texto2)
            .lineLimit(1)
            .overlay {
                if vivo {
                    TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in
                        let f = tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.7) / 1.7
                        let x = f * 1.8 - 0.4
                        LinearGradient(colors: [.clear, .white, .clear],
                                       startPoint: UnitPoint(x: x - 0.22, y: 0.5), endPoint: UnitPoint(x: x + 0.22, y: 0.5))
                    }
                    .mask(base.lineLimit(1))
                    .allowsHitTesting(false)
                }
            }
    }
}

// MARK: - Turno da conversa

/// Um turno com a cara do app: o pedido do Hugo em balão à direita, as falas do caminho
/// recolhidas e a resposta em texto corrido, largo e confortável de ler.
struct TurnoCrew: View {
    let turno: TurnoConversa
    /// O turno está em andamento: os passos aparecem abertos.
    var vivo = false
    @Environment(\.ampliarImagem) private var ampliar

    static func copiar(_ texto: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(texto, forType: .string)
    }

    /// O texto do Hugo com cada [Image #N] clicável: abre a imagem daquela marca (a ordem das
    /// marcas no texto é a ordem das imagens da mensagem).
    static func comMarcas(_ m: SessionMessage) -> AttributedString {
        var out = AttributedString()
        var ordem: [String] = []
        var resto = Substring(m.text)
        while let r = resto.range(of: #"\[Image #\d+\]"#, options: .regularExpression) {
            out += comLinks(String(resto[..<r.lowerBound]))
            let marca = String(resto[r])
            if !ordem.contains(marca) { ordem.append(marca) }
            var pedaco = AttributedString(marca)
            if let k = ordem.firstIndex(of: marca), k < m.images.count {
                pedaco.link = URL(string: "crew-imagem:\(k)")
                pedaco.foregroundColor = Tema.azul
            }
            out += pedaco
            resto = resto[r.upperBound...]
        }
        out += comLinks(String(resto))
        return out
    }

    /// Um trecho do pedido com os endereços (https://…) em azul, sublinhados e clicáveis.
    private static func comLinks(_ s: String) -> AttributedString {
        let achados = TextoRico.enderecos(em: s)
        guard !achados.isEmpty else { return AttributedString(s) }
        let ns = s as NSString
        var out = AttributedString()
        var pos = 0
        for (faixa, url) in achados where faixa.location >= pos {
            out += AttributedString(ns.substring(with: NSRange(location: pos, length: faixa.location - pos)))
            var link = AttributedString(ns.substring(with: faixa))
            link.link = url
            link.foregroundColor = Tema.azul
            link.underlineStyle = .single
            out += link
            pos = faixa.location + faixa.length
        }
        out += AttributedString(ns.substring(from: pos))
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if turno.resumo {
                // O Claude Code resumiu a conversa aqui para caber no contexto dele.
                HStack(spacing: 10) {
                    Fio()
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 9.5, weight: .semibold))
                        Text("Conversa resumida pelo Claude Code").font(.system(size: 11.5))
                    }
                    .foregroundStyle(Tema.texto3)
                    .fixedSize()
                    Fio()
                }
                .help("A conversa ficou longa e o Claude Code resumiu o que veio antes para continuar. Nada se perdeu no transcript.")
            }
            if let u = turno.user {
                VStack(alignment: .trailing, spacing: 5) {
                    imagens(u, direita: true)
                    if !u.text.isEmpty {
                        Text(Self.comMarcas(u))
                            .environment(\.openURL, OpenURLAction { url in
                                guard url.scheme == "crew-imagem", let k = Int(url.absoluteString.dropFirst("crew-imagem:".count)),
                                      k < u.images.count else {
                                    // Link de verdade só abre com ⌘ clique, no navegador do Crew.
                                    // Caminho de arquivo abre por cima da janela do Crew (pasta, no Finder).
                                    if NSEvent.modifierFlags.contains(.command) {
                                        if url.isFileURL { VisorCrew.abrir(url) }
                                        else { NotificationCenter.default.post(name: .abrirNoNavegador, object: url) }
                                    }
                                    return .handled
                                }
                                if let ampliar { withAnimation(.easeOut(duration: 0.18)) { ampliar(u.images[k]) } }
                                else { AttachedImage.abrirNoPreview(u.images[k]) }
                                return .handled
                            })
                            .font(.system(size: 14))
                            .foregroundStyle(Tema.texto)
                            .lineSpacing(3)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 15).padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white.opacity(0.085)))
                            .opacity(u.naFila ? 0.55 : 1)
                    }
                    if u.naFila {
                        // Mandada com o Claude ocupado: ele lê quando terminar o passo atual.
                        HStack(spacing: 4) {
                            Image(systemName: "clock").font(.system(size: 9.5, weight: .semibold))
                            Text("Na fila — o Claude lê em seguida").font(.system(size: 11))
                        }
                        .foregroundStyle(Tema.texto3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.leading, 90)
                .menuContexto { [.acao("Copiar mensagem", icone: "doc.on.doc") { Self.copiar(u.text) }] }
            }
            if !turno.caminho.isEmpty {
                // O que o Claude fez até a resposta: recolhido numa linha; um clique abre.
                CaminhoTurno(turno: turno, vivo: vivo)
            }
            if let a = turno.answer {
                VStack(alignment: .leading, spacing: 8) {
                    imagens(a, direita: false)
                    if !a.text.isEmpty {
                        // Um campo de texto só: seleciona de qualquer ponto a qualquer ponto da resposta.
                        TextoConversa(texto: a.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        // Resposta terminada: copiar inteira, num clique.
                        if !vivo { CopiarResposta(texto: a.text) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func imagens(_ m: SessionMessage, direita: Bool) -> some View {
        if !m.images.isEmpty {
            HStack(spacing: 6) {
                if direita { Spacer(minLength: 0) }
                ForEach(Array(m.images.enumerated()), id: \.offset) { _, data in AttachedImage(data: data) }
                if !direita { Spacer(minLength: 0) }
            }
        }
    }
}

// MARK: - Comando

/// A sessão espera o Hugo no terminal: a pergunta (ou o pedido de permissão) ficou sem resposta
/// aqui e voltou para o Claude Code. Enquanto ele não responder lá, nada anda.
struct CartaoNoTerminal: View {
    let pergunta: Bool
    /// Abre o terminal ao lado (nil no painel da grade e em sessão que não é do motor do Crew).
    let verTerminal: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: pergunta ? "questionmark" : "lock.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Tema.sobreDestaque)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Tema.ambar))
            VStack(alignment: .leading, spacing: 2) {
                Text(pergunta ? "Esperando a sua resposta no terminal" : "Esperando a sua permissão no terminal")
                    .font(Tema.titulo(14))
                    .foregroundStyle(Tema.texto)
                Text("A sessão está parada até você responder lá.")
                    .font(.system(size: 12.5)).foregroundStyle(Tema.texto2)
            }
            Spacer(minLength: 8)
            if let verTerminal {
                BotaoPilula(titulo: "Responder no terminal", icone: "terminal", estilo: .primario, altura: 30, acao: verTerminal)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Tema.elevado)
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Tema.ambar.opacity(0.06)))
        )
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Tema.ambar.opacity(0.45), lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
    }
}

/// As opções que um comando abriu no terminal da sessão ("/model"), para escolher no chat.
struct CartaoComando: View {
    let menu: MenuDoTerminal
    let escolher: (Int) -> Void
    let cancelar: () -> Void
    /// Abre o terminal ao lado (nil no painel da grade).
    let verTerminal: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: "command")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Tema.sobreDestaque)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Tema.azul))
                Text(menu.soNoTerminal ? "O comando espera uma resposta no terminal"
                     : menu.titulo.isEmpty ? "Escolha uma opção" : menu.titulo)
                    .font(Tema.titulo(14))
                    .foregroundStyle(Tema.texto)
                    .lineLimit(2)
                Spacer()
            }
            if menu.soNoTerminal {
                Text("Essa tela do Claude Code não é uma lista de opções; responda no terminal da sessão.")
                    .font(.system(size: 12.5)).foregroundStyle(Tema.texto2)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(menu.opcoes.enumerated()), id: \.element.id) { i, o in
                        LinhaOpcaoComando(opcao: o, marcada: i == menu.marcada) { escolher(i) }
                    }
                }
            }
            HStack(spacing: 8) {
                if let verTerminal {
                    BotaoPilula(titulo: "Ver no terminal", icone: "terminal", estilo: .discreto, altura: 30, acao: verTerminal)
                }
                Spacer()
                BotaoPilula(titulo: "Cancelar", altura: 30, acao: cancelar)
                    .help("Fecha o menu no Claude Code (Esc)")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Tema.elevado)
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Tema.azul.opacity(0.06)))
        )
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Tema.azul.opacity(0.45), lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
    }
}

private struct LinhaOpcaoComando: View {
    let opcao: MenuDoTerminal.Opcao
    let marcada: Bool
    let acao: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: acao) {
            HStack(spacing: 10) {
                Text("\(opcao.numero)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Tema.texto3)
                    .frame(width: 16)
                Text(opcao.titulo)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Tema.texto)
                if let d = opcao.detalhe {
                    Text(d).font(.system(size: 12)).foregroundStyle(Tema.texto3).lineLimit(1)
                }
                Spacer(minLength: 0)
                if marcada {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Tema.azul)
                }
            }
            .padding(.horizontal, 12).frame(minHeight: 34)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.white.opacity(marcada ? 0.11 : hover ? 0.09 : 0.05)))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(marcada ? Tema.azul.opacity(0.45) : Tema.borda))
            .contentShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: - Pendência

/// Aprovação ou pergunta que a sessão espera do Hugo — a ação principal do app. Presa logo
/// acima do campo, com os mesmos botões da ilha. Nada aqui tem atalho de teclado: aprovar é
/// sempre um clique.
struct CartaoPendencia: View {
    let approval: ApprovalInfo
    @State private var indice = 0
    @State private var respostas: [String: String] = [:]
    @State private var marcadas: Set<String> = []

    private var ehPergunta: Bool { !approval.questions.isEmpty }
    private var cor: Color { ehPergunta ? Tema.azul : Tema.ambar }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if ehPergunta { pergunta } else { permissao }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Tema.elevado)
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(cor.opacity(0.07)))
        )
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(cor.opacity(0.5), lineWidth: 1))
        .shadow(color: cor.opacity(0.12), radius: 24, y: 6)
        .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
        .onChange(of: approval.sessionId) { _, _ in indice = 0; respostas = [:]; marcadas = [] }
    }

    private func titulo(_ icone: String, _ texto: String, etiqueta: String? = nil) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icone)
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(Tema.sobreDestaque)
                .frame(width: 24, height: 24)
                .background(Circle().fill(cor))
            Text(texto)
                .font(Tema.titulo(14))
                .foregroundStyle(Tema.texto)
            if let etiqueta {
                Text(etiqueta)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(cor)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Pilula().fill(cor.opacity(0.14)))
            }
            Spacer()
        }
    }

    private var noTerminal: some View {
        BotaoPilula(titulo: "Responder no terminal", estilo: .discreto, altura: 30) {
            HookServer.shared.sendApprovalDecision("ask", sessionId: approval.sessionId)
        }
        .help("Deixar o pedido para responder na própria sessão")
    }

    private var permissao: some View {
        VStack(alignment: .leading, spacing: 12) {
            if approval.plan != nil {
                titulo("list.bullet.clipboard.fill", "Quer aprovar o plano")
            } else {
                titulo("hand.raised.fill", "Pede permissão", etiqueta: approval.tool)
            }
            if let p = approval.purpose, approval.plan == nil {
                Text(p)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Tema.texto)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Group {
                if let plano = approval.plan {
                    ScrollView {
                        TextoConversa(texto: plano, tamanho: 12.5, entrelinha: 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 240)
                } else {
                    Text(approval.command)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color(hex: "#DDE0E5"))
                        .textSelection(.enabled)
                        .lineLimit(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.35)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Tema.borda))
            // Coluna estreita (sessão dividida ao lado): os botões não cabem numa fileira e
            // ficavam cortados; aí as decisões ocupam a linha e o "no terminal" desce.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    noTerminal
                    Spacer()
                    decisoes
                }
                VStack(alignment: .trailing, spacing: 8) {
                    HStack(spacing: 8) { decisoes }
                    noTerminal
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    @ViewBuilder
    private var decisoes: some View {
        BotaoPilula(titulo: "Negar", altura: 34) {
            HookServer.shared.sendApprovalDecision("deny", sessionId: approval.sessionId)
        }
        .fixedSize()
        if approval.plan == nil {
            BotaoPilula(titulo: "Sempre", altura: 34) {
                HookServer.shared.sendApprovalDecision("always", sessionId: approval.sessionId)
            }
            .fixedSize()
            .help("Permitir e não perguntar de novo para este tipo de comando")
        }
        BotaoPilula(titulo: approval.plan != nil ? "Aprovar plano" : "Permitir", icone: "checkmark",
                    estilo: .ambar, altura: 34) {
            HookServer.shared.sendApprovalDecision("allow", sessionId: approval.sessionId)
        }
        .fixedSize()
    }

    @ViewBuilder
    private var pergunta: some View {
        if indice < approval.questions.count {
            let q = approval.questions[indice]
            VStack(alignment: .leading, spacing: 12) {
                titulo("questionmark",
                       approval.questions.count > 1 ? "Pergunta \(indice + 1) de \(approval.questions.count)" : "Pergunta",
                       etiqueta: q.header.isEmpty ? nil : q.header)
                Text(q.question)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Tema.texto)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(q.options, id: \.self) { o in
                        OpcaoPergunta(texto: o, multipla: q.multiSelect, marcada: marcadas.contains(o)) {
                            if q.multiSelect {
                                if marcadas.contains(o) { marcadas.remove(o) } else { marcadas.insert(o) }
                            } else {
                                responder(q, o)
                            }
                        }
                    }
                }
                HStack(spacing: 8) {
                    noTerminal
                    Spacer()
                    if q.multiSelect {
                        BotaoPilula(titulo: "Enviar", icone: "arrow.up", estilo: .azul, altura: 34) {
                            responder(q, marcadas.sorted().joined(separator: ", "))
                        }
                        .disabled(marcadas.isEmpty)
                    }
                }
            }
        }
    }

    private func responder(_ q: QuestionInfo, _ valor: String) {
        respostas[q.question] = valor
        marcadas = []
        if indice + 1 < approval.questions.count {
            indice += 1
        } else {
            HookServer.shared.sendAnswers(respostas, sessionId: approval.sessionId)
            indice = 0; respostas = [:]
        }
    }
}

/// Uma opção de pergunta, na largura toda (texto longo cabe inteiro).
private struct OpcaoPergunta: View {
    let texto: String
    let multipla: Bool
    let marcada: Bool
    let acao: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: acao) {
            HStack(spacing: 9) {
                if multipla {
                    Image(systemName: marcada ? "checkmark.square.fill" : "square")
                        .font(.system(size: 13))
                        .foregroundStyle(marcada ? Tema.azul : Tema.texto3)
                }
                Text(texto)
                    .font(.system(size: 13))
                    .foregroundStyle(Tema.texto)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if !multipla {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Tema.texto3)
                        .opacity(hover ? 1 : 0)
                }
            }
            .padding(.horizontal, 13).padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(marcada ? 0.12 : hover ? 0.1 : 0.055)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(marcada ? Tema.azul.opacity(0.5) : Tema.borda))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
