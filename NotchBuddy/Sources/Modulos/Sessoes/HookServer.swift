import Foundation
import Darwin
import AppKit
import Combine

/// De onde veio um evento: o nb-hook (peer) e o Claude Code acima dele.
struct ProcessOrigin: Sendable {
    let peer: pid_t
    let claudePid: pid_t?
    let chain: String
}

// MARK: - HookServer
// Listens on a Unix domain socket for events from nb-hook (Claude Code hooks).
// Thread-safe: socket I/O on background threads, state updates dispatched to main queue.

final class HookServer: @unchecked Sendable {
    static let shared = HookServer()

    // Support directory paths
    static var supportDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchBuddy")
    }
    static var socketPath: String {
        return supportDir.appendingPathComponent("nb.sock").path
    }
    // hookScriptPath is only used by the non-App Store build.
    // App Store build derives the command from the panel-selected claudeURL in buildHooksData(claudeURL:).
    static var hookScriptPath: String { supportDir.appendingPathComponent("nb-hook").path }

    // No approval blocking state — notch is notification-only, user answers in VS Code

    private var serverFD: Int32 = -1
    // nb-hook esperando decisão, por sessão (session_id → fd aberto). Só tocado na main.
    private var pendingFDs: [String: Int32] = [:]
    private var pidLogged: Set<String> = []
    /// Sem evento por este tempo (e sem pendência) → sessão parada.
    static let paradaApos: TimeInterval = 15 * 60
    private var saveSubscription: AnyCancellable?

    private init() {}

    // MARK: - Start

    func start() {
        // Ensure support directory exists before socket server tries to bind
        try? FileManager.default.createDirectory(at: Self.supportDir, withIntermediateDirectories: true)
        installHookScript()
        Thread.detachNewThread { self.serverThread() }
        // Sessões sobrevivem a reiniciar o app (cada instalação reinicia)
        Task { @MainActor in
            self.restoreSessions()
            self.saveSubscription = AppState.shared.$tasks
                .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
                .sink { tasks in Self.saveSessions(tasks) }
        }
        // Sessões cujo processo do Claude Code morreu somem do notch.
        Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { _ in
            Task { @MainActor in HookServer.shared.pruneDeadSessions() }
        }
    }

    // MARK: - Socket server (background thread)

    private func serverThread() {
        let path = Self.socketPath
        // sun_path on macOS is 104 bytes including the NUL terminator → max 103 usable bytes
        let maxSunPathBytes = MemoryLayout<sockaddr_un>.size - MemoryLayout<sa_family_t>.size - 1
        guard path.utf8.count <= maxSunPathBytes else {
            NSLog("HookServer: socket path too long (\(path.utf8.count) bytes, max \(maxSunPathBytes)): \(path)")
            return
        }
        try? FileManager.default.removeItem(atPath: path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        serverFD = fd

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let cpath = Array(path.utf8CString)
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            for (i, c) in cpath.enumerated() where i < raw.count { raw[i] = UInt8(bitPattern: c) }
        }

        let bindRC = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bindRC == 0 else { close(fd); return }
        guard Darwin.listen(fd, 10) == 0 else { close(fd); return }

        while true {
            let clientFD = Darwin.accept(fd, nil, nil)
            guard clientFD >= 0 else { break }
            Thread.detachNewThread { self.handleClient(fd: clientFD) }
        }
    }

    // MARK: - Client handler (background thread)

    private func handleClient(fd: Int32) {
        // Quem está do outro lado, já — antes de ler: o nb-hook pode sair logo depois de enviar.
        var peerPid: pid_t = 0
        var peerLen = socklen_t(MemoryLayout<pid_t>.size)
        getsockopt(fd, SOL_LOCAL, LOCAL_PEERPID, &peerPid, &peerLen)
        let claudePid = Self.claudeAncestorPid(of: peerPid)
        let chain = claudePid == nil ? Self.processChain(peerPid) : ""
        // Read newline-delimited JSON
        var raw = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        outer: while true {
            let n = recv(fd, &buf, buf.count, 0)
            if n <= 0 { break }
            for i in 0..<n {
                if buf[i] == UInt8(ascii: "\n") { break outer }
                raw.append(buf[i])
            }
        }

        guard !raw.isEmpty,
              let payload = try? JSONSerialization.jsonObject(with: raw) as? [String: Any] else {
            sendLine(fd: fd, text: #"{"ok":true}"#)
            close(fd)
            return
        }

        // Servidor MCP do Crew (Modulos/Automacao): pergunta e resposta numa linha
        if let pedido = payload["crew_mcp"] as? [String: Any] {
            let consulta = UncheckedSendable(pedido)
            Task { @MainActor in
                let r = await ConsultasMCP.responder(consulta.valor)
                let dados = (try? JSONSerialization.data(withJSONObject: r)) ?? Data("{}".utf8)
                self.sendLine(fd: fd, text: String(decoding: dados, as: UTF8.self))
                close(fd)
            }
            return
        }

        let eventName = payload["hook_event_name"] as? String ?? ""
        let origin = ProcessOrigin(peer: peerPid, claudePid: claudePid, chain: chain)

        if eventName == "PermissionRequest" {
            // Hold fd open — Claude Code waits for our decision (up to 120s)
            Task { @MainActor in self.processPermissionRequest(fd: fd, payload: payload, origin: origin) }
        } else {
            Task { @MainActor in self.processEvent(name: eventName, payload: payload, origin: origin) }
            sendLine(fd: fd, text: #"{"ok":true}"#)
            close(fd)
        }
    }


    // MARK: - Event → AppState
    // Nossa versão: cada sessão do Claude Code é uma tarefa própria ("sessao_<session_id>"),
    // com cor, Homie, aprovações e entregas separadas. Alertas só trocam o foco se o Hugo
    // não estiver olhando outra coisa; senão viram selo na pílula.

    @MainActor
    private func processEvent(name: String, payload: [String: Any], origin: ProcessOrigin) {
        let state = AppState.shared
        guard let sessionId = payload["session_id"] as? String, !sessionId.isEmpty else { return }

        // Dispensada pelo Hugo: ignora até ele mandar um pedido novo nela
        if state.dispensadas.contains(sessionId) {
            guard name == "UserPromptSubmit" else { return }
            state.readmitir(sessionId)
        }

        if name == "SessionEnd" {
            removeSession(sessionId)
            nbLog("SessionEnd (\(sessionId.prefix(8)))")
            return
        }

        let id = upsertSession(sessionId: sessionId, payload: payload, origin: origin)
        // Título: a cada pedido/entrega, e enquanto ainda não tiver (sessão recriada no meio)
        if ["SessionStart", "UserPromptSubmit", "Stop"].contains(name)
            || state.tasks.first(where: { $0.id == id })?.title == nil {
            refreshTitle(id)
        }

        switch name {

        case "SessionStart":
            nbLog("SessionStart \(sessionId.prefix(8))")
            if state.isPresent && !sessaoNaFrente(id) { expandIfNeeded(to: .overview, taskId: id) }
            somDaSessao("work", id)

        case "UserPromptSubmit":
            setField(id) { $0.oculta = false }   // pedido novo traz a sessão de volta
            state.updateTask(id: id, state: .thinking)
            if let prompt = payload["prompt"] as? String, !prompt.isEmpty {
                setField(id) { $0.lastPrompt = prompt; $0.delivery = nil; $0.steps = [] }
                appendStep(id: id, step: String(prompt.prefix(60)))
            }
            if state.isPresent && !sessaoNaFrente(id) { expandIfNeeded(to: .overview, taskId: id) }

        case "PreToolUse":
            state.updateTask(id: id, state: .working)
            let tool = payload["tool_name"] as? String ?? "Tool"
            let input = payload["tool_input"] as? [String: Any] ?? [:]
            let step = stepLabel(tool: tool, input: input)
            appendStep(id: id, step: step)

        case "PostToolUse":
            // Uma pergunta/aprovação respondida no terminal: limpa a pendência daqui.
            if state.pendingApprovals[sessionId] != nil { resolvePending(sessionId: sessionId, json: nil) }
            state.updateTask(id: id, state: .working)

        case "PostToolUseFailure":
            if state.pendingApprovals[sessionId] != nil { resolvePending(sessionId: sessionId, json: nil) }
            state.updateTask(id: id, state: .working)
            appendStep(id: id, step: "falhou")

        case "Notification":
            let message = payload["message"] as? String ?? ""
            let type = payload["notification_type"] as? String ?? ""
            let lower = message.lowercased()
            if lower.contains("rate limit") || lower.contains("usage limit") {
                state.updateTask(id: id, state: .ratelimit)
                somDaSessao("rate", id)
            } else if type == "idle_prompt" {
                // Claude parado esperando o Hugo: não é alerta, a entrega já foi mostrada.
                break
            } else if type == "elicitation_dialog" || message.hasSuffix("?") {
                state.updateTask(id: id, state: .question)
                appendStep(id: id, step: message)
                alert(id: id, view: .question, badge: .approval)
            }

        case "Stop":
            state.updateTask(id: id, state: .finished)
            let text = (payload["last_assistant_message"] as? String)
                ?? Self.lastAssistantText(transcriptPath: payload["transcript_path"] as? String)
            if let text, !text.isEmpty {
                setField(id) { $0.delivery = text }
            }
            somDaSessao("finish", id)
            alert(id: id, view: .finished, badge: .finished)
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.2) {
                // Volta ao repouso, mas a entrega e o selo ficam até o Hugo olhar.
                if state.tasks.first(where: { $0.id == id })?.state == .finished {
                    state.updateTask(id: id, state: .idle)
                }
            }

        case "StopFailure":
            state.updateTask(id: id, state: .error)
            let err = (payload["error"] as? String) ?? (payload["message"] as? String)
            if let err, !err.isEmpty { setField(id) { $0.delivery = err } }
            somDaSessao("error", id)
            alert(id: id, view: .error, badge: .error)

        case "SubagentStart":
            appendStep(id: id, step: "+ subagente")

        case "SubagentStop":
            appendStep(id: id, step: "subagente terminou")

        default:
            break
        }
    }

    // MARK: - Sessões

    /// O que se guarda de cada sessão para sobreviver a reiniciar o app.
    private struct SessionSnapshot: Codable {
        var sessionId: String, name: String, color: String
        var title: String?, cwd: String?, transcriptPath: String?, bundleId: String?
        var lastPrompt: String?, delivery: String?, claudePid: Int32?, lastEvent: Date
        var oculta: Bool?
    }

    private static var sessionsFile: URL { supportDir.appendingPathComponent("sessoes.json") }

    private static func saveSessions(_ tasks: [AgentTask]) {
        let snaps = tasks.compactMap { t -> SessionSnapshot? in
            guard t.source == .claudeCode, let sid = t.sessionId else { return nil }
            return SessionSnapshot(sessionId: sid, name: t.name, color: t.color, title: t.title,
                                   cwd: t.sessionCwd, transcriptPath: t.transcriptPath, bundleId: t.sessionAppBundleId,
                                   lastPrompt: t.lastPrompt, delivery: t.delivery, claudePid: t.claudePid, lastEvent: t.lastEvent,
                                   oculta: t.oculta)
        }
        if let data = try? JSONEncoder().encode(snaps) { try? data.write(to: sessionsFile, options: .atomic) }
    }

    /// Traz de volta as sessões que ainda estão vivas (processo do Claude Code existe).
    @MainActor
    private func restoreSessions() {
        guard let data = try? Data(contentsOf: Self.sessionsFile),
              let snaps = try? JSONDecoder().decode([SessionSnapshot].self, from: data) else { return }
        let state = AppState.shared
        for s in snaps {
            let alive: Bool
            if let pid = s.claudePid { alive = kill(pid, 0) == 0 || errno != ESRCH }
            else { alive = Date().timeIntervalSince(s.lastEvent) < 12 * 3600 }
            guard alive, !state.dispensadas.contains(s.sessionId),
                  !state.tasks.contains(where: { $0.sessionId == s.sessionId }) else { continue }
            // Cor do projeto (sessões salvas antes do agrupamento tinham cor por sessão)
            let cor = Projetos.cor(de: s.cwd) ?? s.color
            var t = AgentTask(id: Self.taskId(s.sessionId), name: s.name, color: cor, state: .idle, steps: [], source: .claudeCode)
            t.sessionId = s.sessionId
            t.title = s.title
            t.sessionCwd = s.cwd
            t.transcriptPath = s.transcriptPath
            t.sessionAppBundleId = s.bundleId
            t.lastPrompt = s.lastPrompt
            t.delivery = s.delivery
            t.claudePid = s.claudePid
            t.lastEvent = s.lastEvent
            t.oculta = s.oculta ?? false
            t.parada = Date().timeIntervalSince(s.lastEvent) > Self.paradaApos
            state.addTask(t)
            refreshTitle(t.id)
        }
        nbLog("Restauradas \(state.tasks.count) sessões")
    }

    static func taskId(_ sessionId: String) -> String { "sessao_" + sessionId }

    /// Cores das sessões — cada sessão aberta pega a primeira livre.
    static let sessionColors = ["#FF7A59", "#38BDF8", "#A78BFA", "#34D399",
                                "#F472B6", "#FBBF24", "#2DD4BF", "#60A5FA"]

    /// Cria a tarefa da sessão na primeira vez que ela fala com a gente e atualiza o resto.
    @MainActor
    @discardableResult
    private func upsertSession(sessionId: String, payload: [String: Any], origin: ProcessOrigin) -> String {
        let state = AppState.shared
        let id = Self.taskId(sessionId)
        let cwd = payload["cwd"] as? String ?? ""

        if !state.tasks.contains(where: { $0.id == id }) {
            // Nome e cor vêm do projeto (repo), não da pasta: worktree conta como o repo
            let raw = Projetos.nome(de: cwd) ?? ""
            var name = aliasProjectName(raw.isEmpty ? "Sessão" : raw)
            // Duas sessões no mesmo projeto: numera a segunda em diante.
            let same = state.tasks.filter { $0.source == .claudeCode && ($0.name == name || $0.name.hasPrefix(name + " ·")) }.count
            if same > 0 { name += " ·\(same + 1)" }
            let used = Set(state.tasks.map(\.color))
            let color = Projetos.cor(de: cwd)
                ?? Self.sessionColors.first { !used.contains($0) }
                ?? Self.sessionColors[state.tasks.count % Self.sessionColors.count]
            var task = AgentTask(id: id, name: name, color: color, state: .idle, steps: [], source: .claudeCode)
            task.sessionId = sessionId
            if !cwd.isEmpty { task.sessionCwd = cwd }
            state.addTask(task)
            if state.mode == .expanded && state.view == .empty { state.view = .overview }
        }

        let bundleId = Self.sessionAppBundleId(payload)
        let transcript = payload["transcript_path"] as? String
        let claudePid = origin.claudePid
        if claudePid == nil, !pidLogged.contains(sessionId) {
            // Diagnóstico: sem o processo, a sessão não some quando fecha
            pidLogged.insert(sessionId)
            nbLog("Sem processo do Claude para \(sessionId.prefix(8)): peer=\(origin.peer) cadeia=\(origin.chain)")
        }
        setField(id) { t in
            if !cwd.isEmpty { t.sessionCwd = cwd }
            if let bundleId { t.sessionAppBundleId = bundleId }
            if let transcript, !transcript.isEmpty { t.transcriptPath = transcript }
            if let claudePid { t.claudePid = claudePid }
            t.lastEvent = .now
            t.parada = false
        }
        return id
    }

    @MainActor
    private func removeSession(_ sessionId: String) {
        let state = AppState.shared
        if state.pendingApprovals[sessionId] != nil { resolvePending(sessionId: sessionId, json: nil) }
        state.removeTask(id: Self.taskId(sessionId))
        if state.mode == .expanded && state.tasks.isEmpty { state.view = .empty }
    }

    /// Sessão fechada sem SessionEnd (terminal morto, Ctrl+C duplo): some quando o processo some.
    private var pruneTick = 0

    @MainActor
    func pruneDeadSessions() {
        let state = AppState.shared
        // Renomear no Xirp não gera evento de hook: a cada ~40s confere o nome das sessões de lá
        pruneTick += 1
        if pruneTick % 2 == 0 {
            // Só as sessões ativas: parada ou oculta não está sendo renomeada (e cada consulta
            // abre um processo do xirp).
            for t in state.tasks where t.source == .claudeCode && t.sessionAppBundleId == "com.spotify.xirp"
                && !t.parada && !t.oculta {
                refreshTitle(t.id)
            }
        }
        for task in state.tasks where task.source == .claudeCode {
            guard let sid = task.sessionId else { continue }
            // Parada: sem evento há 15 min e nada esperando resposta
            let parada = Date().timeIntervalSince(task.lastEvent) > Self.paradaApos
                && state.pendingApprovals[sid] == nil
                && ![.approval, .question].contains(task.state)   // esperando o Hugo no terminal
            if parada != task.parada { setField(task.id) { $0.parada = parada } }
            if let pid = task.claudePid {
                if kill(pid, 0) != 0 && errno == ESRCH { removeSession(sid) }
            } else if Date().timeIntervalSince(task.lastEvent) > 12 * 3600 && state.pendingApprovals[sid] == nil {
                removeSession(sid)
            }
        }
    }

    /// Volta ao título automático depois de apagar o nome dado no Crew.
    @MainActor
    func recarregarTitulo(_ id: String) {
        setField(id) { $0.title = nil }
        refreshTitle(id)
    }

    /// Relê o título no transcript (fora da main) — ele aparece depois do primeiro pedido.
    /// Título: nome dado no Crew > nome dado no Xirp > /rename > título automático.
    @MainActor
    private func refreshTitle(_ id: String) {
        guard let task = AppState.shared.tasks.first(where: { $0.id == id }) else { return }
        let path = task.transcriptPath
        let sid = task.sessionId
        let noXirp = task.sessionAppBundleId == "com.spotify.xirp"
        Task {
            var t = await Task.detached { TranscriptReader.title(path: path) }.value
            if noXirp, let sid, let nome = await Xirp.customName(forClaudeSession: sid) { t = nome }
            // Nome dado no Crew vale acima de tudo
            if let sid, let nome = AppState.shared.nomesDados[sid] { t = nome }
            if let t, AppState.shared.tasks.first(where: { $0.id == id })?.title != t {
                self.setField(id) { $0.title = t }
            }
        }
    }

    @MainActor
    private func setField(_ id: String, _ change: (inout AgentTask) -> Void) {
        let state = AppState.shared
        guard let idx = state.tasks.firstIndex(where: { $0.id == id }) else { return }
        change(&state.tasks[idx])
    }

    /// Mostra um alerta da sessão: abre direto se o Hugo não está olhando outra pendência,
    /// senão só marca a pílula.
    @MainActor
    private func alert(id: String, view: IslandView, badge: PillBadge) {
        let state = AppState.shared
        // App do Crew na frente: o Hugo já está olhando as sessões. Nada de abrir a ilha —
        // fica o som (já tocou) e a sessão se destaca na lista do app. Vale também para
        // permissão e pergunta: o cartão de resposta aparece na própria conversa e a sessão
        // sobe para "Pedem sua resposta".
        if JanelaCrew.shared.naFrente, [.finished, .error, .approval, .question].contains(view) {
            setPillBadge(id: id, badge: badge)
            NotificationCenter.default.post(name: .sessaoPedeAtencao, object: id)
            return
        }
        // Aprovação e pergunta pedem SEMPRE, em qualquer tela (chat, música, outra sessão):
        // guarda onde o Hugo estava e volta para lá depois de responder.
        if view == .approval || view == .question {
            if state.mode == .expanded && ![.approval, .question].contains(state.view) && state.vistaAntesDoAlerta == nil {
                state.vistaAntesDoAlerta = (state.view, state.chatSelection)
            }
            state.focusId = id
            expandIfNeeded(to: view, taskId: id)
            return
        }
        // Chat aberto nesta sessão: a resposta já aparece na conversa — nada de aviso por cima.
        if view == .finished, state.mode == .expanded, state.view == .prompt, state.chatSelection == id {
            return
        }
        let busyElsewhere = state.mode == .expanded && state.focusId != id
            && [.approval, .question, .finished, .error, .prompt, .result, .searching, .mail, .upload].contains(state.view)
        // Sessão ocultada não abre a ilha sozinha (aprovação já a desoculta antes);
        // app da sessão na frente (Xirp na tela principal): o Hugo já está vendo lá.
        let oculta = state.tasks.first { $0.id == id }?.oculta == true
        if busyElsewhere || oculta {
            setPillBadge(id: id, badge: badge)
            return
        }
        // Aprovação e pergunta sempre abrem a ilha (o Hugo responde por ela);
        // entrega/erro com o Xirp na frente ficam no aviso discreto.
        if sessaoNaFrente(id) && view != .approval && view != .question {
            // Xirp na frente: aviso discreto — a sessão vira o Homie da ilha compacta,
            // na cor do estado, com uma expressão rápida e o som. Sem abrir.
            setPillBadge(id: id, badge: badge)
            if state.mode != .expanded {
                state.focusId = id
                if state.mode == .hidden { NotificationCenter.default.post(name: .hookReveal, object: nil) }
                let emote: BotEmote = badge == .error ? .annoyed : (badge == .finished ? .proud : .surprised)
                NotificationCenter.default.post(name: .triggerEmote, object: emote, userInfo: ["silent": true])
            }
            return
        }
        state.focusId = id
        expandIfNeeded(to: view, taskId: id)
    }

    // MARK: - App da sessão na frente

    /// O app onde a sessão roda (ex.: Xirp) está em uso, com janela na tela do notch.
    /// Aí a ilha não avisa: só marca a pílula.
    @MainActor
    private func sessaoNaFrente(_ id: String) -> Bool {
        guard let bid = AppState.shared.tasks.first(where: { $0.id == id })?.sessionAppBundleId,
              let front = NSWorkspace.shared.frontmostApplication,
              front.bundleIdentifier == bid else { return false }
        guard let screen = IslandWindowController.notchScreen() ?? NSScreen.main else { return true }
        let primaryH = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        for w in windows {
            guard (w[kCGWindowOwnerPID as String] as? pid_t) == front.processIdentifier,
                  (w[kCGWindowLayer as String] as? Int) == 0,
                  let dict = w[kCGWindowBounds as String] as? NSDictionary,
                  let b = CGRect(dictionaryRepresentation: dict as CFDictionary) else { continue }
            // CoreGraphics conta y do topo da tela principal; AppKit, da base
            let r = CGRect(x: b.minX, y: primaryH - b.maxY, width: b.width, height: b.height)
            if r.intersects(screen.frame) { return true }
        }
        return false
    }

    /// Som do evento. Toca mesmo com o app da sessão na frente: é o aviso discreto.
    @MainActor
    private func somDaSessao(_ name: String, _ id: String) {
        // Projeto silenciado pelo Hugo (painel do projeto): a sessão avisa na ilha, sem som.
        let cwd = AppState.shared.tasks.first { $0.id == id }?.sessionCwd
        if ConfigProjetos.shared.daPasta(cwd).semSom { return }
        SoundEngine.shared.play(name)
    }

    // MARK: - Transcript (reserva quando o Stop não traz a última mensagem)

    /// Lê o fim do transcript e devolve o texto da última resposta do assistente.
    /// O formato do JSONL é interno do Claude Code; se não reconhecer, devolve nil.
    nonisolated static func lastAssistantText(transcriptPath: String?) -> String? {
        guard let path = transcriptPath, let fh = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? fh.close() }
        let size = (try? fh.seekToEnd()) ?? 0
        let start = size > 512_000 ? size - 512_000 : 0
        try? fh.seek(toOffset: start)
        guard let data = try? fh.readToEnd(), let text = String(data: data, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n").reversed() {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  obj["type"] as? String == "assistant",
                  let msg = obj["message"] as? [String: Any],
                  let content = msg["content"] as? [[String: Any]] else { continue }
            let texts = content.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
            if !texts.isEmpty { return texts.joined(separator: "\n") }
        }
        return nil
    }

    // MARK: - Processo do Claude Code

    /// Sobe a árvore de processos a partir do nb-hook até achar o executável do Claude Code.
    nonisolated static func claudeAncestorPid(of start: pid_t) -> pid_t? {
        var pid = start
        for _ in 0..<12 {
            guard pid > 1 else { return nil }
            var buf = [CChar](repeating: 0, count: 4096)
            if proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 {
                let name = URL(fileURLWithPath: String(cString: buf)).lastPathComponent.lowercased()
                if name == "claude" || name == "claude.exe" { return pid }
            }
            var info = kinfo_proc()
            var size = MemoryLayout<kinfo_proc>.stride
            var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
            guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
            pid = info.kp_eproc.e_ppid
        }
        return nil
    }

    /// Cadeia de processos a partir de um pid, para o log de diagnóstico.
    nonisolated static func processChain(_ start: pid_t) -> String {
        var out: [String] = []
        var pid = start
        for _ in 0..<8 {
            guard pid > 0 else { break }
            var buf = [CChar](repeating: 0, count: 4096)
            let name = proc_pidpath(pid, &buf, UInt32(buf.count)) > 0
                ? URL(fileURLWithPath: String(cString: buf)).lastPathComponent : "?"
            out.append("\(pid):\(name)")
            var info = kinfo_proc()
            var size = MemoryLayout<kinfo_proc>.stride
            var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
            guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0, pid > 1 else { break }
            pid = info.kp_eproc.e_ppid
        }
        return out.joined(separator: " < ")
    }

    // MARK: - Helpers

    /// Descobre de qual app a sessão roda, para o "abrir sessão" levar até ela.
    /// `__CFBundleIdentifier` vem do app que abriu o shell (Xirp, VS Code…);
    /// num terminal puro, cai no TERM_PROGRAM.
    static func sessionAppBundleId(_ payload: [String: Any]) -> String? {
        let bundleId = payload["bundle_id"] as? String ?? ""
        if !bundleId.isEmpty { return bundleId }
        let terminals: [String: String] = [
            "apple_terminal": "com.apple.Terminal",
            "iterm.app": "com.googlecode.iterm2",
            "ghostty": "com.mitchellh.ghostty",
            "wezterm": "com.github.wez.wezterm",
            "vscode": "com.microsoft.VSCode",
        ]
        let term = (payload["term_program"] as? String ?? "").lowercased()
        return terminals[term]
    }

    @MainActor
    private func expandIfNeeded(to view: IslandView, taskId: String? = nil) {
        let state = AppState.shared
        let isAlert: Bool
        switch view {
        case .approval, .question, .finished, .error, .confused: isAlert = true
        default: isAlert = false
        }
        if state.mode == .expanded {
            // Only force-switch view for alerts — leave user on their current view otherwise
            if isAlert { state.view = view }
        } else if isAlert {
            // Alerts always force-expand
            NotificationCenter.default.post(name: .hookExpand, object: view)
        } else if state.mode == .hidden {
            // Non-alert work events: reveal compact only, never force-expand
            NotificationCenter.default.post(name: .hookReveal, object: nil)
        }
        // Already compact and non-alert: Homie state update is enough, no expand
    }

    // MARK: - Permission request (blocking — Claude Code waits for decision)
    // Uma pendência por sessão: várias sessões podem esperar ao mesmo tempo.

    @MainActor
    private func processPermissionRequest(fd: Int32, payload: [String: Any], origin: ProcessOrigin) {
        let state = AppState.shared
        guard let sessionId = payload["session_id"] as? String, !sessionId.isEmpty else {
            sendLine(fd: fd, text: #"{"permissionDecision":"ask"}"#); close(fd); return
        }
        state.readmitir(sessionId)   // aprovação/pergunta sempre aparece
        let id = upsertSession(sessionId: sessionId, payload: payload, origin: origin)

        let tool = payload["tool_name"] as? String ?? "Tool"
        let input = payload["tool_input"] as? [String: Any] ?? [:]
        var info = ApprovalInfo(sessionId: sessionId, tool: tool, command: stepLabel(tool: tool, input: input), toolInput: input)
        info.purpose = input["description"] as? String
        if let cmd = input["command"] as? String { info.command = cmd }
        if tool == "AskUserQuestion", let qs = input["questions"] as? [[String: Any]] {
            info.questions = qs.map { q in
                QuestionInfo(question: q["question"] as? String ?? "",
                             header: q["header"] as? String ?? "",
                             options: (q["options"] as? [[String: Any]] ?? []).compactMap { $0["label"] as? String },
                             multiSelect: q["multiSelect"] as? Bool ?? false)
            }
        }
        if tool == "ExitPlanMode" { info.plan = input["plan"] as? String }
        nbLog("PermissionRequest \(sessionId.prefix(8)) \(tool)")

        // Pedido novo da mesma sessão substitui o anterior (o antigo volta para o terminal).
        if let old = pendingFDs[sessionId] {
            Task.detached { [weak self] in
                self?.sendLine(fd: old, text: #"{"permissionDecision":"ask"}"#)
                close(old)
            }
        }
        pendingFDs[sessionId] = fd
        state.pendingApprovals[sessionId] = info
        setField(id) { $0.oculta = false; $0.parada = false }

        let isQuestion = !info.questions.isEmpty
        state.updateTask(id: id, state: isQuestion ? .question : .approval)
        // Com o app do Crew na frente a ilha não abre (ver `alert`), então não há o que prender.
        if !JanelaCrew.shared.naFrente { state.isPinned = true }
        somDaSessao("approval", id)
        alert(id: id, view: isQuestion ? .question : .approval, badge: .approval)

        let captured = fd
        DispatchQueue.main.asyncAfter(deadline: .now() + 115) { [weak self] in
            guard let self, self.pendingFDs[sessionId] == captured else { return }
            // Sem resposta: devolve ao terminal em vez de negar.
            self.resolvePending(sessionId: sessionId, json: #"{"permissionDecision":"ask"}"#)
        }
    }

    /// Botões da aprovação. Sem sessionId, vale a pendência da sessão em foco.
    @MainActor
    func sendApprovalDecision(_ decision: String, sessionId: String? = nil) {
        guard let sid = sessionId ?? AppState.shared.pendingApproval?.sessionId else { return }
        let json: String
        switch decision {
        case "allow":  json = #"{"permissionDecision":"allow"}"#
        case "always": json = #"{"permissionDecision":"always"}"#
        case "ask":    json = #"{"permissionDecision":"ask"}"#
        default:       json = #"{"permissionDecision":"deny"}"#
        }
        resolvePending(sessionId: sid, json: json)
    }

    /// Responde uma pergunta (AskUserQuestion): permite a ferramenta já com as respostas.
    /// `answers` é pergunta → rótulo(s) escolhido(s).
    @MainActor
    func sendAnswers(_ answers: [String: String], sessionId: String) {
        guard let info = AppState.shared.pendingApprovals[sessionId] else { return }
        var input = info.toolInput
        input["answers"] = answers
        let body: [String: Any] = ["permissionDecision": "allow", "updatedInput": input]
        guard let data = try? JSONSerialization.data(withJSONObject: body),
              let json = String(data: data, encoding: .utf8) else { return }
        resolvePending(sessionId: sessionId, json: json)
    }

    /// Fecha a pendência da sessão. `json` nil = só limpa (já respondida no terminal ou sessão fechada).
    @MainActor
    private func resolvePending(sessionId: String, json: String?) {
        let state = AppState.shared
        if let fd = pendingFDs.removeValue(forKey: sessionId) {
            let line = json ?? #"{"permissionDecision":"ask"}"#
            Task.detached { [weak self] in
                self?.sendLine(fd: fd, text: line)
                close(fd)
            }
        }
        state.pendingApprovals[sessionId] = nil
        let id = Self.taskId(sessionId)
        // Devolvida ao terminal (sem resposta a tempo, ou "Responder no terminal"): a sessão
        // continua esperando o Hugo, só que lá. Não é "trabalhando"; o estado de pergunta ou
        // de permissão fica até o Claude Code andar de novo (PostToolUse, pedido novo, Stop).
        let devolvida = json?.contains(#""permissionDecision":"ask""#) ?? false
        if json != nil && !devolvida { state.updateTask(id: id, state: .working) }
        if !devolvida { clearPillBadge(id: id) }

        // Ainda tem sessão esperando? Vai direto para a próxima.
        if let next = state.pendingApprovals.values.first {
            let nextId = Self.taskId(next.sessionId)
            state.focusId = nextId
            clearPillBadge(id: nextId)
            if state.mode == .expanded { state.view = next.questions.isEmpty ? .approval : .question }
            return
        }
        state.isPinned = false
        let antes = state.vistaAntesDoAlerta
        state.vistaAntesDoAlerta = nil
        if state.mode == .expanded && [.approval, .question].contains(state.view) {
            if let antes {
                // Volta para onde o Hugo estava (no chat, na mesma sessão e com o rascunho)
                if antes.view == .prompt { state.openChat(antes.chat) } else { state.view = antes.view }
            } else {
                state.view = state.tasks.isEmpty ? .empty : .overview
            }
        }
    }

    // MARK: - Badge helpers

    @MainActor
    private func setPillBadge(id: String, badge: PillBadge) {
        let state = AppState.shared
        guard let idx = state.tasks.firstIndex(where: { $0.id == id }) else { return }
        state.tasks[idx].pillBadge = badge
    }

    @MainActor
    private func clearPillBadge(id: String) {
        let state = AppState.shared
        guard let idx = state.tasks.firstIndex(where: { $0.id == id }) else { return }
        state.tasks[idx].pillBadge = nil
    }

    @MainActor
    private func appendStep(id: String, step: String) {
        let state = AppState.shared
        guard let idx = state.tasks.firstIndex(where: { $0.id == id }) else { return }
        state.tasks[idx].steps.append(step)
        if state.tasks[idx].steps.count > 20 { state.tasks[idx].steps.removeFirst() }
        state.tasks[idx].stepIndex = state.tasks[idx].steps.count - 1
    }

    // MARK: - Project name alias mapping

    private func aliasProjectName(_ name: String) -> String {
        let aliases: [String: String] = [
            "notch-buddy":  "Crew",
            "notchbuddy":   "Crew",
            "notch_buddy":  "Crew",
        ]
        return aliases[name.lowercased()] ?? name
    }

    // MARK: - Rótulo do passo

    /// Passo em português de gente: usa a descrição que o próprio Claude escreve para
    /// o comando (a mesma que aparece no Xirp); sem ela, um texto por ferramenta.
    private func stepLabel(tool: String, input: [String: Any]) -> String {
        func file(_ k: String) -> String? {
            (input[k] as? String).map { URL(fileURLWithPath: $0).lastPathComponent }
        }
        func short(_ s: String, _ n: Int = 50) -> String {
            let one = s.replacingOccurrences(of: "\n", with: " ")
            return one.count > n ? String(one.prefix(n - 1)) + "…" : one
        }
        if let d = input["description"] as? String, !d.isEmpty { return short(d, 60) }

        switch tool {
        case "Bash":            return "Rodando um comando"
        case "Read":            return file("file_path").map { "Lendo \($0)" } ?? "Lendo um arquivo"
        case "Write":           return file("file_path").map { "Criando \($0)" } ?? "Criando um arquivo"
        case "Edit", "MultiEdit": return file("file_path").map { "Editando \($0)" } ?? "Editando um arquivo"
        case "NotebookEdit":    return file("notebook_path").map { "Editando \($0)" } ?? "Editando um notebook"
        case "Grep":            return (input["pattern"] as? String).map { "Procurando “\(short($0, 30))” no código" } ?? "Procurando no código"
        case "Glob", "LS":      return "Procurando arquivos"
        case "WebSearch":       return (input["query"] as? String).map { "Pesquisando: \(short($0, 40))" } ?? "Pesquisando na web"
        case "WebFetch":        return (input["url"] as? String).flatMap { URL(string: $0)?.host }.map { "Abrindo \($0)" } ?? "Abrindo uma página"
        case "TodoWrite":       return "Atualizando a lista de tarefas"
        case "Task", "Agent":   return "Chamando um ajudante"
        case "AskUserQuestion": return "Fazendo uma pergunta"
        case "ExitPlanMode":    return "Plano pronto para aprovar"
        case "Skill":           return (input["skill"] as? String).map { "Usando a skill \($0)" } ?? "Usando uma skill"
        default:
            // mcp__servidor__ferramenta → "Usando servidor"
            if tool.hasPrefix("mcp__") {
                let parts = tool.split(separator: "_", omittingEmptySubsequences: true)
                if parts.count >= 2 { return "Usando \(parts[1])" }
            }
            return "Usando \(tool)"
        }
    }

    // MARK: - Logging

    private func nbLog(_ message: String) {
        let logsDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/NotchBuddy")
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        let logFile = logsDir.appendingPathComponent("nb.log")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let line = "\(formatter.string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: logFile.path) {
            if let handle = try? FileHandle(forWritingTo: logFile) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            }
        } else {
            try? data.write(to: logFile)
        }
    }

    private func sendLine(fd: Int32, text: String) {
        let bytes = Array((text + "\n").utf8)
        bytes.withUnsafeBytes { buffer in
            var sent = 0
            while sent < buffer.count {
                let n = Darwin.send(fd, buffer.baseAddress! + sent, buffer.count - sent, 0)
                if n <= 0 { break }
                sent += n
            }
        }
    }

    // MARK: - nb-hook script installation

    func installHookScript() {
        let dir = Self.supportDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // nb-hook: shell wrapper (always exits 0, calls nb-hook.py via python3)
        let wrapperURL = URL(fileURLWithPath: Self.hookScriptPath)
        try? nbHookShellWrapper.write(to: wrapperURL, atomically: true, encoding: .utf8)
        _ = try? FileManager.default.setAttributes([.posixPermissions: 0o755 as NSNumber], ofItemAtPath: wrapperURL.path)
        // nb-hook.py: Python relay
        let pyURL = wrapperURL.deletingLastPathComponent().appendingPathComponent("nb-hook.py")
        try? nbHookPythonGitHub.write(to: pyURL, atomically: true, encoding: .utf8)
        _ = try? FileManager.default.setAttributes([.posixPermissions: 0o755 as NSNumber], ofItemAtPath: pyURL.path)
    }

    // MARK: - Outdated hook detection

    /// Returns true if settings.json has a Crew PermissionRequest hook with timeout < 120s.
    static func hooksNeedUpdate() -> Bool {
        let settingsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
        guard let data = try? Data(contentsOf: settingsURL),
              let settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = settings["hooks"] as? [String: Any],
              let permReqHooks = hooks["PermissionRequest"] as? [[String: Any]] else {
            return false
        }
        for matcher in permReqHooks {
            if let hookList = matcher["hooks"] as? [[String: Any]] {
                for hook in hookList {
                    if let cmd = hook["command"] as? String,
                       (cmd.contains("NotchBuddy") || cmd.contains("coucou")),
                       let timeout = hook["timeout"] as? Int,
                       timeout < 120 {
                        return true
                    }
                }
            }
        }
        return false
    }

    // MARK: - Claude Code settings.json hook installer

    private var _pendingHooksData: Data?

    /// Returns preview JSON without writing — call writeClaudeHooks() to confirm.
    func previewClaudeHooks() throws -> String {
        let data = try buildHooksData()
        _pendingHooksData = data
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Writes the hooks to disk (call after user confirms preview).
    func writeClaudeHooks() throws {
        guard let data = _pendingHooksData else { return }
        let settingsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
        // Backup first
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmm"
        let stamp = formatter.string(from: Date())
        let backupURL = settingsURL.deletingLastPathComponent()
            .appendingPathComponent("settings.json.bak-\(stamp)")
        try? FileManager.default.copyItem(at: settingsURL, to: backupURL)
        try? FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(),
                                                  withIntermediateDirectories: true)
        try data.write(to: settingsURL, options: .atomic)
        _pendingHooksData = nil
    }

    private func buildHooksData() throws -> Data {
        let settingsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
        var settings: [String: Any] = [:]
        if let data = try? Data(contentsOf: settingsURL),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settings = parsed
        }
        let hookPath = Self.hookScriptPath
        let quotedCmd = "\"\(hookPath.replacingOccurrences(of: "\"", with: "\\\""))\""
        let events: [(String, Int)] = [
            ("SessionStart", 10), ("SessionEnd", 10),
            ("UserPromptSubmit", 10),
            ("PreToolUse", 10), ("PostToolUse", 10), ("PostToolUseFailure", 10),
            ("PermissionRequest", 120),
            ("Notification", 10),
            ("Stop", 10), ("StopFailure", 10),
            ("SubagentStart", 10), ("SubagentStop", 10),
        ]
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for (event, timeout) in events {
            var existing = hooks[event] as? [[String: Any]] ?? []
            existing.removeAll { ($0["hooks"] as? [[String: Any]])?.contains { ($0["command"] as? String)?.contains("NotchBuddy") == true || ($0["command"] as? String)?.contains("coucou") == true } ?? false }
            existing.append(["hooks": [["type": "command", "command": quotedCmd, "timeout": timeout]]])
            hooks[event] = existing
        }
        settings["hooks"] = hooks
        return try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
    }

    func uninstallClaudeHooks() throws {
        let settingsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
        guard let data = try? Data(contentsOf: settingsURL),
              var settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var hooks = settings["hooks"] as? [String: Any] else { return }

        for key in hooks.keys {
            if var matchers = hooks[key] as? [[String: Any]] {
                matchers.removeAll { matcher in
                    (matcher["hooks"] as? [[String: Any]])?.contains {
                        ($0["command"] as? String)?.contains("NotchBuddy") == true ||
                        ($0["command"] as? String)?.contains("coucou") == true
                    } ?? false
                }
                if matchers.isEmpty { hooks.removeValue(forKey: key) }
                else { hooks[key] = matchers }
            }
        }
        settings["hooks"] = hooks
        let newData = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try newData.write(to: settingsURL, options: .atomic)
    }

    // MARK: - App Store: hooks via security-scoped bookmark

}

// MARK: - Notification names for hook server → controller communication

extension Notification.Name {
    static let hookExpand = Notification.Name("notchBuddy.hookExpand")
}

// MARK: - nb-hook shell wrapper (same for both GitHub and App Store)
// Invoked by Claude Code via /bin/sh or directly via shebang.
// Always exits 0 — never blocks Claude Code.
// Checks xcode-select before running python3 to avoid triggering the
// "install developer tools" dialog on machines without Xcode CLI tools.

private let nbHookShellWrapper = """
#!/bin/sh
# Crew hook relay — always exits 0, never blocks Claude Code
HOOK_DIR="$(dirname "$0")"
if xcode-select -p >/dev/null 2>&1; then
    out=$(/usr/bin/python3 "$HOOK_DIR/nb-hook.py" 2>/dev/null)
    rc=$?
    if [ "$rc" -eq 0 ] && [ -n "$out" ]; then
        printf '%s\\n' "$out"
    fi
fi
exit 0
"""

// MARK: - nb-hook Python relay (GitHub / non-sandboxed version)

private let nbHookPythonGitHub = """
#!/usr/bin/env python3
# nb-hook.py — Crew hook relay for Claude Code (GitHub version)
# Reads JSON from stdin, forwards to Crew via Unix socket, translates response.
import sys, json, os, socket

def main():
    try:
        raw = sys.stdin.buffer.read()
        if not raw:
            return
        payload = json.loads(raw)
    except Exception:
        return

    # Enrich with terminal context
    env = os.environ
    payload.setdefault('term_program', env.get('TERM_PROGRAM', ''))
    payload.setdefault('iterm_session_id', env.get('ITERM_SESSION_ID', ''))
    payload.setdefault('term_session_id', env.get('TERM_SESSION_ID', ''))
    payload.setdefault('bundle_id', env.get('__CFBundleIdentifier', ''))
    if 'cwd' not in payload or not payload['cwd']:
        payload['cwd'] = os.getcwd()

    event = payload.get('hook_event_name', '')
    socket_path = os.path.expanduser(
        '~/Library/Application Support/NotchBuddy/nb.sock'
    )

    if event == 'PermissionRequest':
        # Block and wait for Crew's decision (Claude Code allows up to 120s)
        try:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.settimeout(118)
            s.connect(socket_path)
            s.sendall((json.dumps(payload) + '\\n').encode())
            chunks = []
            while True:
                chunk = s.recv(4096)
                if not chunk:
                    break
                chunks.append(chunk)
                if b'\\n' in chunk:
                    break
            s.close()
            response = b''.join(chunks).decode().strip()
            if response:
                try:
                    resp_obj = json.loads(response)
                    decision = resp_obj.get('permissionDecision', '')
                except Exception:
                    decision = ''
                if decision == 'allow':
                    allow = {'behavior': 'allow'}
                    # Pergunta respondida no notch: a ferramenta roda já com as respostas.
                    if isinstance(resp_obj.get('updatedInput'), dict):
                        allow['updatedInput'] = resp_obj['updatedInput']
                    out = {'hookSpecificOutput': {'hookEventName': 'PermissionRequest', 'decision': allow}}
                    sys.stdout.write(json.dumps(out) + '\\n')
                    sys.stdout.flush()
                    sys.exit(0)
                elif decision == 'always':
                    # Let Claude Code persist the rule via updatedPermissions
                    suggestions = payload.get('permission_suggestions', [])
                    out = {'hookSpecificOutput': {'hookEventName': 'PermissionRequest', 'decision': {'behavior': 'allow', 'updatedPermissions': suggestions}}}
                    sys.stdout.write(json.dumps(out) + '\\n')
                    sys.stdout.flush()
                    sys.exit(0)
                elif decision == 'deny':
                    out = {'hookSpecificOutput': {'hookEventName': 'PermissionRequest', 'decision': {'behavior': 'deny', 'message': 'Denied from Crew'}}}
                    sys.stdout.write(json.dumps(out) + '\\n')
                    sys.stdout.flush()
                    sys.exit(0)
                # 'ask' or unknown: fall through → no output → Claude Code re-asks
        except Exception:
            pass
        # App unreachable, timed out, or no explicit decision — print nothing
        # Claude Code will handle the absence of output (re-ask or default behaviour)
        sys.exit(0)

    # All other events: fire-and-forget (0.3s timeout, never blocks)
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(0.3)
        s.connect(socket_path)
        s.sendall((json.dumps(payload) + '\\n').encode())
        # Espera o ok do app (até 0.3s): enquanto a conexão vive, o app identifica a sessão
        try:
            s.recv(64)
        except Exception:
            pass
        s.close()
    except Exception:
        pass  # Always exit cleanly — never block Claude Code

main()
sys.exit(0)
"""

// MARK: - nb-hook Python relay (App Store — socket in sandboxed container)

private let nbHookPythonAppStore = """
#!/usr/bin/env python3
# nb-hook.py — Crew (App Store) hook relay for Claude Code
# Socket lives inside the sandboxed container; script runs outside the sandbox.
import sys, json, os, socket

def main():
    try:
        raw = sys.stdin.buffer.read()
        if not raw:
            return
        payload = json.loads(raw)
    except Exception:
        return

    env = os.environ
    payload.setdefault('term_program', env.get('TERM_PROGRAM', ''))
    payload.setdefault('iterm_session_id', env.get('ITERM_SESSION_ID', ''))
    payload.setdefault('term_session_id', env.get('TERM_SESSION_ID', ''))
    payload.setdefault('bundle_id', env.get('__CFBundleIdentifier', ''))
    if 'cwd' not in payload or not payload['cwd']:
        payload['cwd'] = os.getcwd()

    event = payload.get('hook_event_name', '')
    socket_path = os.path.expanduser(
        '~/Library/Containers/fr.louisraille.Coucou/Data/nb.sock'
    )

    if event == 'PermissionRequest':
        # Block and wait for Crew's decision (Claude Code allows up to 120s)
        try:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.settimeout(118)
            s.connect(socket_path)
            s.sendall((json.dumps(payload) + '\\n').encode())
            chunks = []
            while True:
                chunk = s.recv(4096)
                if not chunk:
                    break
                chunks.append(chunk)
                if b'\\n' in chunk:
                    break
            s.close()
            response = b''.join(chunks).decode().strip()
            if response:
                try:
                    resp_obj = json.loads(response)
                    decision = resp_obj.get('permissionDecision', '')
                except Exception:
                    decision = ''
                if decision == 'allow':
                    allow = {'behavior': 'allow'}
                    # Pergunta respondida no notch: a ferramenta roda já com as respostas.
                    if isinstance(resp_obj.get('updatedInput'), dict):
                        allow['updatedInput'] = resp_obj['updatedInput']
                    out = {'hookSpecificOutput': {'hookEventName': 'PermissionRequest', 'decision': allow}}
                    sys.stdout.write(json.dumps(out) + '\\n')
                    sys.stdout.flush()
                    sys.exit(0)
                elif decision == 'always':
                    # Let Claude Code persist the rule via updatedPermissions
                    suggestions = payload.get('permission_suggestions', [])
                    out = {'hookSpecificOutput': {'hookEventName': 'PermissionRequest', 'decision': {'behavior': 'allow', 'updatedPermissions': suggestions}}}
                    sys.stdout.write(json.dumps(out) + '\\n')
                    sys.stdout.flush()
                    sys.exit(0)
                elif decision == 'deny':
                    out = {'hookSpecificOutput': {'hookEventName': 'PermissionRequest', 'decision': {'behavior': 'deny', 'message': 'Denied from Crew'}}}
                    sys.stdout.write(json.dumps(out) + '\\n')
                    sys.stdout.flush()
                    sys.exit(0)
                # 'ask' or unknown: fall through → no output → Claude Code re-asks
        except Exception:
            pass
        # App unreachable, timed out, or no explicit decision — print nothing
        sys.exit(0)

    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(0.3)
        s.connect(socket_path)
        s.sendall((json.dumps(payload) + '\\n').encode())
        # Espera o ok do app (até 0.3s): enquanto a conexão vive, o app identifica a sessão
        try:
            s.recv(64)
        except Exception:
            pass
        s.close()
    except Exception:
        pass  # Always exit cleanly — never block Claude Code

main()
sys.exit(0)
"""
