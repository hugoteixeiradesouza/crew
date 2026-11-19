import SwiftUI

// MARK: - Prompt (chat)

/// Conversa com as sessões do Claude Code — sem chave de API.
/// Lê o transcript da sessão escolhida e fala com ela pelo Xirp; "+ Nova" abre uma sessão.
struct PromptView: View {
    @ObservedObject var state: AppState
    @State private var text: String = ""
    /// Próxima mensagem prevista pelo modelo local (Tab aceita). nil = nenhuma.
    private var sugestao: String? { SugestoesChat.shared.sugestao(current) }
    @FocusState private var focused: Bool

    /// Id da tarefa da sessão escolhida; nil = nova sessão
    private var selected: String? {
        get { state.chatSelection }
        nonmutating set { state.chatSelection = newValue; state.chatSelectionSet = true }
    }
    @State private var messages: [SessionMessage] = []
    @State private var xirpId: String? = nil
    @State private var xirpChecked = false
    /// Por onde o texto chega à sessão (Xirp, tmux, Terminal, iTerm) — ou por que não chega
    @State private var channel: SessionChannel? = nil
    @State private var projects: [XirpProject] = []
    @State private var project: XirpProject? = nil
    @State private var sending = false
    @State private var notice: String? = nil
    /// Chat colado no fim: só para de seguir quando o Hugo rola para cima
    @State private var seguindoFim = true
    /// Imagem da conversa ampliada por cima do chat (nil = nenhuma)
    @State private var imagemAmpliada: Data? = nil
    /// Sessão recém-criada pelo "+ Nova": quando ela aparecer, a conversa pula para ela.
    @State private var waitingNew: (xirpId: String?, projectPath: String, known: Set<String>)? = nil

    /// Sessões do Claude Code, juntas por projeto (mesma cor = mesmo repo)
    private var sessions: [AgentTask] { Projetos.agrupadas(state.tasks.filter { $0.source == .claudeCode }) }
    private var current: AgentTask? { sessions.first { $0.id == selected } }

    var body: some View {
        ZStack(alignment: .leading) {
            CardBackground(wash: .indigo)

            VStack(alignment: .leading, spacing: 6) {
                sessionPicker

                if let notice {
                    Text(notice)
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#F5A524"))
                        .lineLimit(2)
                }

                if current != nil {
                    conversation
                } else {
                    newSessionHeader
                }

                if !state.anexosChat.isEmpty { anexos }

                HStack(spacing: 8) {
                    TextField(placeholder, text: $text, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .lineLimit(1...6)
                        .focused($focused)
                        // Enter envia; Shift+Enter quebra a linha (mensagens em várias linhas)
                        .onKeyPress(.return, phases: .down) { tecla in
                            if tecla.modifiers.contains(.shift) || tecla.modifiers.contains(.option) {
                                text += "\n"
                                return .handled
                            }
                            send()
                            return .handled
                        }
                        // Tab com o campo vazio aceita a sugestão (como no terminal do Claude Code)
                        .onKeyPress(.tab) {
                            guard text.isEmpty, let s = sugestao else { return .ignored }
                            text = s
                            return .handled
                        }
                        // Delete com o campo vazio tira o último anexo
                        .onKeyPress(.delete) {
                            guard text.isEmpty, !state.anexosChat.isEmpty else { return .ignored }
                            state.anexosChat.removeLast()
                            return .handled
                        }
                        .disabled(!canSend)

                    Button(action: send) {
                        Image(systemName: sending ? "ellipsis" : "arrow.up")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color(hex: "#0B0C0E"))
                    }
                    .buttonStyle(SendButtonStyle())
                    .disabled((text.isEmpty && state.anexosChat.isEmpty) || !canSend || sending)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color.white.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .simultaneousGesture(TapGesture().onEnded { focused = true })
            }
            .padding(.leading, 84)
            .padding(.trailing, 16)
            .padding(.top, 12)
            .padding(.bottom, 14)
            .environment(\.ampliarImagem) { imagemAmpliada = $0 }
            .overlay {
                if let d = imagemAmpliada {
                    ImagemAmpliada(data: d) {
                        withAnimation(.easeOut(duration: 0.15)) { imagemAmpliada = nil }
                    }
                    .padding(.leading, 84).padding(.trailing, 16)
                    .padding(.top, 8).padding(.bottom, 10)
                }
            }
        }
        .onChange(of: selected) { _, _ in imagemAmpliada = nil }
        .padding(.bottom, 10)
        .onAppear {
            // Abre na sessão em foco (a da notificação); sem sessão, em "nova".
            // Sem escolha explícita (aba do chat): abre na sessão em foco
            if !state.chatSelectionSet {
                if let f = state.focusTask, f.source == .claudeCode { selected = f.id }
                else { selected = sessions.first?.id }
            }
            if case .file(_, let url?) = state.promptContext { text = url.path + " " }
            // Volta do upload (ou reabriu o chat): o que estava escrito continua ali
            if text.isEmpty && !state.rascunhoChat.isEmpty { text = state.rascunhoChat }
            focused = true
        }
        .onChange(of: text) { _, t in state.rascunhoChat = t }
        .task(id: selected) { await follow() }
        .onChange(of: sessions.map(\.id)) { _, ids in jumpToNewSession(ids) }
    }

    // MARK: Partes

    /// Arquivos arrastados para a ilha, esperando o envio junto com o texto.
    private var anexos: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(state.anexosChat, id: \.self) { url in
                    HStack(spacing: 5) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                            .resizable().frame(width: 14, height: 14)
                        Text(url.lastPathComponent)
                            .font(.system(size: 11)).lineLimit(1).truncationMode(.middle)
                            .frame(maxWidth: 160, alignment: .leading)
                        // Alvo de clique folgado: o X sozinho era pequeno demais para acertar
                        Button { state.anexosChat.removeAll { $0 == url } } label: {
                            Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                                .frame(width: 18, height: 18)
                                .background(Color.white.opacity(0.10))
                                .clipShape(Circle())
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Tirar anexo (ou Delete com o campo vazio)")
                    }
                    .foregroundColor(Color(hex: "#DADDE2"))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
                }
            }
        }
        .frame(height: 24)
    }

    private var sessionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(sessions.enumerated()), id: \.element.id) { i, t in
                    // Começo de cada projeto: separador + nome do projeto (repo) na cor dele
                    if i == 0 || Projetos.chave(sessions[i - 1]) != Projetos.chave(t) {
                        if i > 0 {
                            Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 14)
                                .padding(.horizontal, 2)
                        }
                        if let nome = Projetos.nome(de: t.sessionCwd) {
                            Text(nome.uppercased())
                                .font(.system(size: 9, weight: .bold)).tracking(0.6)
                                .foregroundColor(Color(hex: t.color).opacity(0.85))
                                .lineLimit(1).fixedSize()
                        }
                    }
                    Group {
                        if state.renomeando == t.id {
                            TituloSessao(state: state, task: t, tamanho: 11)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .frame(width: 170)
                                .background(Color(hex: t.color).opacity(0.22))
                                .clipShape(Capsule())
                        } else {
                            chip(t.displayTitle, color: t.color, on: selected == t.id, badge: t.pillBadge != nil) { selected = t.id }
                                // Dois cliques no nome renomeia (o mesmo do menu "Renomear")
                                .simultaneousGesture(TapGesture(count: 2).onEnded { state.renomeando = t.id })
                                .help("Dois cliques para renomear")
                        }
                    }
                        .opacity(t.ativa ? 1 : 0.5)
                        .contextMenu {
                            if t.ativa {
                                Button("Ocultar sessão") { state.ocultar(t.id) }
                            } else {
                                Button("Mostrar sessão") { state.mostrar(t.id) }
                            }
                            SessaoMenuFim(state: state, task: t)
                        }
                }
                chip("+ Nova", color: "#8E939C", on: selected == nil, badge: false) { selected = nil }
            }
        }
        .frame(height: 22)
    }

    private func chip(_ label: String, color: String, on: Bool, badge: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Circle().fill(Color(hex: color)).frame(width: 6, height: 6)
                Text(label).font(.system(size: 11, weight: on ? .semibold : .regular)).lineLimit(1)
                    .frame(maxWidth: 160)
                if badge { Circle().fill(Color(hex: "#F5A524")).frame(width: 5, height: 5) }
            }
            .foregroundColor(on ? Color(hex: "#F5F6F8") : Color(hex: "#8E939C"))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(on ? Color(hex: color).opacity(0.22) : Color.white.opacity(0.05))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// Medidas da rolagem do chat: dizem se foi o Hugo que rolou ou se o conteúdo mudou.
    private struct RolagemChat: Equatable {
        var offset: CGFloat, conteudo: CGFloat, janela: CGFloat
        var noFim: Bool { offset + janela >= conteudo - 4 }
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    if messages.isEmpty {
                        Text("Sem conversa ainda nesta sessão.")
                            .font(.system(size: 12)).foregroundColor(Color(hex: "#6B7079"))
                    }
                    ForEach(ChatTurn.group(messages)) { turn in
                        ChatTurnView(turn: turn).id(turn.id)
                    }
                    if let t = current, [.working, .thinking].contains(t.state) {
                        HStack { TypingDotsView(); Spacer(minLength: 32) }.id("typing")
                    }
                    // Marca do fim de verdade: rolar até aqui não deixa sobra embaixo
                    Color.clear.frame(height: 1).id("fim")
                }
                .padding(.vertical, 2)
            }
            .defaultScrollAnchor(.bottom)
            .onScrollGeometryChange(for: RolagemChat.self) { g in
                RolagemChat(offset: g.contentOffset.y, conteudo: g.contentSize.height, janela: g.containerSize.height)
            } action: { antes, agora in
                state.chatAtBottom = agora.noFim
                let mesmoTamanho = antes.conteudo == agora.conteudo && antes.janela == agora.janela
                if agora.noFim {
                    seguindoFim = true
                } else if mesmoTamanho && agora.offset < antes.offset - 1 {
                    // Hugo rolou para cima: deixa onde ele está até voltar ao fim
                    seguindoFim = false
                } else if !mesmoTamanho && seguindoFim {
                    // Ilha esticou, mensagem cresceu, imagem carregou: continua no fim
                    proxy.scrollTo("fim", anchor: .bottom)
                }
            }
            .onDisappear { state.chatAtBottom = true }
            .onChange(of: messages) { _, _ in
                if seguindoFim { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("fim", anchor: .bottom) } }
            }
            .onChange(of: selected) { _, _ in
                seguindoFim = true
                DispatchQueue.main.async { proxy.scrollTo("fim", anchor: .bottom) }
            }
            .onAppear {
                seguindoFim = true
                proxy.scrollTo("fim", anchor: .bottom)
                // De novo depois do primeiro layout (markdown e imagens mudam a altura)
                DispatchQueue.main.async { proxy.scrollTo("fim", anchor: .bottom) }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var newSessionHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !Xirp.available {
                Text("Xirp não encontrado — sessão nova só pelo terminal.")
                    .font(.system(size: 12)).foregroundColor(Color(hex: "#9398A1"))
            } else {
                Menu {
                    ForEach(projects) { p in Button(p.name) { project = p } }
                } label: {
                    Text(project.map { "Projeto: \($0.name)" } ?? "Escolha o projeto")
                        .font(.system(size: 12, weight: .semibold))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Text("Abre uma sessão nova do Claude Code no Xirp, na raiz do projeto.")
                    .font(.system(size: 11)).foregroundColor(Color(hex: "#6B7079"))
            }
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
        // Sessão parou de trabalhar com uma resposta nova: o modelo local prevê o próximo pedido
        // (gerado à parte; a tela só mostra quando fica pronto).
        .onAppear { SugestoesChat.shared.pedir(current) }
        .onChange(of: current.flatMap(SugestoesChat.chave)) { _, _ in SugestoesChat.shared.pedir(current) }
    }

    private var placeholder: String {
        if let t = current {
            if case .none(let app)? = channel { return "Essa sessão roda no \(app) — responda lá" }
            if let s = sugestao, text.isEmpty { return "\(s)   ⇥" }
            return "Falar com \(t.displayTitle)…"
        }
        return "O que a sessão nova deve fazer?"
    }

    private var canSend: Bool {
        if current != nil {
            if let channel, case .none = channel { return false }
            return channel != nil
        }
        return Xirp.available && project != nil
    }

    // MARK: Ações

    /// Acompanha a sessão escolhida: relê o transcript enquanto a tela está aberta.
    private func follow() async {
        notice = nil
        messages = []
        xirpId = nil
        xirpChecked = false
        channel = nil
        guard let t = current else {
            if projects.isEmpty { projects = await Xirp.projects() }
            // Padrão: o projeto "dev" (~/dev); troca pelo seletor acima.
            if project == nil {
                let dev = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("dev").path
                project = projects.first { $0.path == dev } ?? projects.first { $0.name == "dev" } ?? projects.first
            }
            return
        }
        let sid = t.sessionId ?? ""
        if CaptureTool.ativo { xirpId = "captura"; channel = .xirp("captura") } else {
        xirpId = await Xirp.sessionId(forClaudeSession: sid)
        xirpChecked = true
        channel = await TerminalBridge.channel(claudePid: t.claudePid, bundleId: t.sessionAppBundleId, xirpId: xirpId)
        }
        var tick = 0
        var lastSize: UInt64 = 0
        while !Task.isCancelled {
            // Não achou no Xirp? Tenta de novo de tempos em tempos (pode ter sido falha passageira).
            tick += 1
            if tick % 6 == 0, case .none? = channel {
                xirpId = await Xirp.sessionId(forClaudeSession: sid)
                let cur = state.tasks.first { $0.id == t.id }
                channel = await TerminalBridge.channel(claudePid: cur?.claudePid, bundleId: cur?.sessionAppBundleId, xirpId: xirpId)
            }
            let path = state.tasks.first { $0.id == t.id }?.transcriptPath
            // Só relê quando o transcript cresceu
            let size = (path.flatMap { try? FileManager.default.attributesOfItem(atPath: $0)[.size] as? UInt64 }) ?? 0
            if size != lastSize {
                lastSize = size
                let m = await Task.detached { TranscriptReader.messages(path: path) }.value
                if m != messages { messages = m }
            }
            try? await Task.sleep(for: .seconds(1.5))
        }
    }

    /// Assim que a sessão criada pelo "+ Nova" mandar o primeiro evento, abre a conversa dela.
    private func jumpToNewSession(_ ids: [String]) {
        guard let w = waitingNew else { return }
        let fresh = sessions.filter { !w.known.contains($0.id) }
        let hit = fresh.first { t in w.xirpId != nil && t.sessionId == w.xirpId }
            ?? fresh.first { ($0.sessionCwd ?? "").hasPrefix(w.projectPath) }
        guard let hit else { return }
        waitingNew = nil
        selected = hit.id
        state.setFocus(hit.id)
    }

    private func send() {
        // Anexos vão "colados" na sessão (imagem vira anexo de verdade no Claude Code)
        let anexos = state.anexosChat
        let msg = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !msg.isEmpty || !anexos.isEmpty, canSend, !sending else { return }
        sending = true
        notice = nil
        Task {
            var err: String?
            if let ch = channel, current != nil {
                err = await TerminalBridge.send(msg, anexos: anexos, via: ch)
            } else if let p = project {
                let known = Set(sessions.map(\.id))
                // Sessão nova nasce de texto: os anexos vão como caminho, que o Claude lê
                let pedido = ([msg] + anexos.map(\.path)).filter { !$0.isEmpty }.joined(separator: " ")
                switch await Xirp.newSession(projectId: p.id, prompt: pedido) {
                case .success(let id):
                    waitingNew = (id, p.path, known)
                    notice = "Abrindo sessão em \(p.name)…"
                case .failure(let e):
                    err = e.message
                }
            }
            if let err { notice = "Não foi: \(err.prefix(120))" } else {
                text = ""
                state.anexosChat.removeAll { anexos.contains($0) }
            }
            state.promptContext = nil
            sending = false
            focused = true
        }
    }
}
