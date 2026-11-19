import Foundation
import SwiftUI
import Combine

// Integration pills — desligadas por ora: o Crew mostra só as sessões do Claude Code.
extension AgentTask {
    /// Liga de novo as pílulas de integração (Resend, n8n, Vercel…) e os pollers.
    static let integracoesLigadas = false

    /// All available integration pills. Claude is always active; others are opt-in (max 4).
    static let integrationAgents: [AgentTask] = [
        AgentTask(id: "integration_claude",  name: "Claude Code", color: "#F5F6F8", state: .idle, steps: [], source: .claudeCode, isIntegration: true),
        AgentTask(id: "integration_resend",  name: "Resend",    color: "#22C55E", state: .idle, steps: [], source: .n8n, isIntegration: true),
        AgentTask(id: "integration_n8n",     name: "n8n",       color: "#F29B38", state: .idle, steps: [], source: .n8n, isIntegration: true),
        AgentTask(id: "integration_vercel",  name: "Vercel",    color: "#7C5CFF", state: .idle, steps: [], source: .n8n, isIntegration: true),
        AgentTask(id: "integration_github",  name: "GitHub",    color: "#F4505E", state: .idle, steps: [], source: .n8n, isIntegration: true),
        AgentTask(id: "integration_notion",  name: "Notion",    color: "#8C8C8C", state: .idle, steps: [], source: .n8n, isIntegration: true),
        AgentTask(id: "integration_calcom",  name: "Cal.com",   color: "#C9956A", state: .idle, steps: [], source: .n8n, isIntegration: true),
        AgentTask(id: "integration_stripe",  name: "Stripe",    color: "#0570DE", state: .idle, steps: [], source: .n8n, isIntegration: true),
    ]

    /// IDs that can be toggled (VS Code is always on and excluded from this list)
    static let toggleableIntegrationIds: [String] = [
        "integration_resend", "integration_n8n", "integration_vercel", "integration_github",
        "integration_notion", "integration_calcom", "integration_stripe",
    ]

}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    // Island state
    // Fechar a ilha, trocar de tela ou de módulo devolve a ilha à altura padrão
    @Published var mode: IslandMode = .hidden { didSet { if mode != .expanded { alturaAba = nil } } }
    @Published var view: IslandView = .overview { didSet { if view != oldValue || !view.cresce { alturaAba = nil } } }
    /// Qual módulo a aba `.modulo` mostra (id do Registro).
    @Published var moduloAberto: String? = nil { didSet { if moduloAberto != oldValue { alturaAba = nil } } }
    /// Altura que a aba do módulo aberto pediu (nil = a padrão, 160). Só vale com a aba na
    /// frente; volta a nil sozinha ao fechar a ilha ou trocar de aba. Ver `Modulo.pedirAlturaAba`.
    @Published var alturaAba: CGFloat? = nil
    /// Altura da ilha seguindo o dedo durante o elástico de uma tela que cresce (nil = parada).
    @Published var puxaoAba: CGFloat? = nil
    /// A lista da tela aberta chegou ao fim (ou não rola): rolar para cima recolhe. Ver `.rolagemDaIlha()`.
    var abaNoFim = true
    /// O máximo que uma aba pode pedir: cabe na tela, como o chat esticado.
    var alturaAbaMaxima: CGFloat { chatMaxHeight }

    // Tasks
    @Published var tasks: [AgentTask] = []
    @Published var focusId: String? = nil

    // Bot state override
    @Published var stateOverride: BotState? = nil

    // Real notch dimensions (set by IslandWindowController on launch)
    var notchWidth:  CGFloat = IslandConst.notchWidth
    var notchHeight: CGFloat = IslandConst.notchHeight

    // Last app active before NotchBuddy (for window context capture)
    var lastExternalApp: NSRunningApplication? = nil

    // Bot drag-attach state (hides original bot while ghost follows cursor)
    @Published var isDraggingBot: Bool = false

    // Mouse tracking
    var mousePosition: CGPoint = .zero
    var lastMouseMove: Date = .now
    var lastActivity: Date = .now
    var isPresent: Bool = true

    // Pinned (alerts that stay open, never auto-close)
    var isPinned: Bool = false

    // Upload progress (0-1) — set to 1.0 only at completion; animation is time-based
    @Published var uploadProgress: Double = 0

    // Upload animation timing (non-published — TimelineViews read these directly)
    var uploadStartTime: Date?
    var uploadDuration: Double = 2.4

    // File drag-over state (mailbox morph glow + mouth spring)
    @Published var fileDragOver: Bool = false

    // Sound enabled — persisted
    @Published var soundEnabled: Bool = true {
        didSet { Gravar.padrao.set(soundEnabled, forKey: "soundEnabled") }
    }

    // Sound volume (0–0.2) — persisted, synced to SoundEngine
    @Published var soundVolume: Double = 0.12 {
        didSet {
            Gravar.padrao.set(soundVolume, forKey: "soundVolume")
            SoundEngine.shared.volume = Float(soundVolume)
        }
    }

    // Context for prompt (window attach / file)
    @Published var promptContext: PromptContext? = nil

    // Dropped file (set during upload flow)
    @Published var droppedFile: DroppedFile? = nil

    /// Tela em que o Hugo estava quando chegou uma aprovação/pergunta (volta para ela depois).
    var vistaAntesDoAlerta: (view: IslandView, chat: String?)? = nil

    /// Arrasto começou com o chat aberto: o arquivo vai para a conversa, não para o "escolher".
    var arrastoParaChat = false
    /// Sessão do chat a que o arrasto volta (nil = "+ Nova").
    var arrastoSessao: String? = nil
    /// Anexos esperando o próximo envio no chat (caminhos de arquivo).
    @Published var anexosChat: [URL] = []
    /// Texto que o Hugo estava escrevendo no chat — sobrevive à animação de upload.
    var rascunhoChat = ""

    /// Volta à conversa de onde o arrasto saiu.
    func voltarAoChatDoArrasto() {
        arrastoParaChat = false
        openChat(arrastoSessao)
    }

    // Short note message (shown in NoteView)
    @Published var noteMessage: String? = nil

    // Auto-close delay — persisted
    @Published var autoCloseInterval: TimeInterval = 15 {
        didSet { Gravar.padrao.set(autoCloseInterval, forKey: "autoCloseInterval") }
    }

    // Absence interval — persisted
    var absenceInterval: TimeInterval = 3 * 60 {
        didSet { Gravar.padrao.set(absenceInterval, forKey: "absenceInterval") }
    }

    // Greeting threshold — how long hidden before greeting on reappear (default 2 min)
    var greetThresholdSeconds: TimeInterval = 120 {
        didSet { Gravar.padrao.set(greetThresholdSeconds, forKey: "greetThreshold") }
    }

    // Hotkey to show island (e.g. ⌘⇧N)
    // MARK: Personagem — nome e aparência escolhidos pelo Hugo

    @Published var nomePersonagem: String = "Homie" {
        didSet { Gravar.padrao.set(nomePersonagem, forKey: "nomePersonagem") }
    }
    /// Nome para usar em texto: o escolhido, ou "Homie" se ficou vazio.
    var nomeDoPersonagem: String {
        let n = nomePersonagem.trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? "Homie" : n
    }
    /// Cor principal do corpo em hex; vazio = branco padrão.
    @Published var corPersonagem: String = "" { didSet { salvarAparencia() } }
    @Published var bonePersonagem: Bool = true { didSet { salvarAparencia() } }
    @Published var corBone: String = "#2B2E33" { didSet { salvarAparencia() } }
    @Published var abaParaFrente: Bool = false { didSet { salvarAparencia() } }
    /// true = AirPods Pro; false = AirPods Max
    @Published var fonesIntra: Bool = true { didSet { salvarAparencia() } }
    @Published var fonesPrata: Bool = false { didSet { salvarAparencia() } }
    @Published var sobrancelhas: Bool = false { didSet { salvarAparencia() } }
    @Published var contornoPersonagem: Bool = false { didSet { salvarAparencia() } }

    private var carregandoAparencia = false

    private func salvarAparencia() {
        aplicarAparencia()
        guard !carregandoAparencia else { return }
        let ud = UserDefaults.standard
        ud.set(corPersonagem, forKey: "corPersonagem")
        ud.set(bonePersonagem, forKey: "bonePersonagem")
        ud.set(corBone, forKey: "corBone")
        ud.set(abaParaFrente, forKey: "abaParaFrente")
        ud.set(fonesIntra, forKey: "fonesIntra")
        ud.set(fonesPrata, forKey: "fonesPrata")
        ud.set(sobrancelhas, forKey: "sobrancelhas")
        ud.set(contornoPersonagem, forKey: "contornoPersonagem")
    }

    /// Passa a aparência para o desenho (BotStyle), que é lido a cada quadro.
    func aplicarAparencia() {
        BotStyle.corBase = Self.rgb(corPersonagem)
        BotStyle.cap = bonePersonagem
        BotStyle.capRGB = Self.rgb(corBone) ?? (0.17, 0.18, 0.20)
        BotStyle.brimForward = abaParaFrente
        BotStyle.earbuds = fonesIntra
        BotStyle.phonesSilver = fonesPrata
        BotStyle.brows = sobrancelhas
        BotStyle.outline = contornoPersonagem
    }

    static func rgb(_ hex: String) -> (Double, Double, Double)? {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard h.count == 6, let v = UInt64(h, radix: 16) else { return nil }
        return (Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
    }

    // Módulos: cada recurso liga e desliga nos Ajustes
    @Published var moduloBrilho: Bool = true { didSet { Gravar.padrao.set(moduloBrilho, forKey: "moduloBrilho") } }
    @Published var moduloVolume: Bool = true { didSet { Gravar.padrao.set(moduloVolume, forKey: "moduloVolume") } }
    @Published var moduloAvisoProprio: Bool = true {
        didSet {
            Gravar.padrao.set(moduloAvisoProprio, forKey: "moduloAvisoProprio")
            NivelService.shared.atualizarTeclas()
        }
    }
    @Published var moduloOptionDuplo: Bool = true { didSet { Gravar.padrao.set(moduloOptionDuplo, forKey: "moduloOptionDuplo") } }
    @Published var moduloAnexosChat: Bool = true { didSet { Gravar.padrao.set(moduloAnexosChat, forKey: "moduloAnexosChat") } }

    @Published var hotkeyEnabled: Bool = false {
        didSet { Gravar.padrao.set(hotkeyEnabled, forKey: "hotkeyEnabled") }
    }
    var hotkeyFlags: UInt = NSEvent.ModifierFlags([.command, .shift]).rawValue {
        didSet { Gravar.padrao.set(Int(hotkeyFlags), forKey: "hotkeyFlags") }
    }
    var hotkeyCode: UInt16 = 45 {  // 'n'
        didSet { Gravar.padrao.set(Int(hotkeyCode), forKey: "hotkeyCode") }
    }

    // Vercel project filter — empty = watch all projects
    @Published var vercelProjectFilter: Set<String> = [] {
        didSet {
            if let data = try? JSONEncoder().encode(Array(vercelProjectFilter)) {
                Gravar.padrao.set(data, forKey: "vercelProjectFilter")
            }
        }
    }

    // n8n workflow filter — empty = watch all workflows
    @Published var n8nWorkflowFilter: Set<String> = [] {
        didSet {
            if let data = try? JSONEncoder().encode(Array(n8nWorkflowFilter)) {
                Gravar.padrao.set(data, forKey: "n8nWorkflowFilter")
            }
        }
    }

    // Active integration pills (VS Code excluded — always on). Max 4.
    @Published var activeIntegrations: Set<String> = ["integration_resend", "integration_n8n", "integration_vercel", "integration_github"] {
        didSet {
            if let data = try? JSONEncoder().encode(Array(activeIntegrations)) {
                Gravar.padrao.set(data, forKey: "activeIntegrations")
            }
        }
    }

    // Pending API result
    @Published var searchResult: SearchResult? = nil

    // Vercel deployments (populated by VercelPoller)
    @Published var vercelDeployments: [VercelDeployment] = []

    // Resend emails (populated by ResendPoller)
    @Published var resendEmails: [ResendEmail] = []
    @Published var resendTotal: Int? = nil

    // GitHub stats (populated by GithubPoller)
    @Published var githubStats: GitHubStats? = nil

    // Stripe (populated by StripePoller)
    @Published var stripePayments: [StripePayment] = []
    @Published var stripeBalance: Int = 0           // raw balance in cents
    @Published var stripeDisplayBalance: Int = 0    // animated balance target
    @Published var stripeCurrency: String = "eur"
    @Published var stripeLoaded: Bool = false       // true after first successful poll
    @Published var stripeError: String? = nil      // last API error (nil = ok)

    // Cal.com (populated by CalcomPoller)
    @Published var calcomBookings: [CalcomBooking] = []
    @Published var calcomLoaded: Bool = false
    @Published var calcomError: String? = nil

    // Notion (populated by NotionPoller)
    @Published var notionPages: [NotionPage] = []
    @Published var notionLoaded: Bool = false
    @Published var notionError: String? = nil

    // Chat conversation history
    @Published var chatHistory: [ChatMessage] = []

    // Altura do chat: começa compacta e estica ao rolar para cima, até o limite da tela.
    static let chatMinHeight: CGFloat = 240
    @Published var chatHeight: CGFloat = AppState.chatMinHeight
    /// Chat no ponto de trava de cima (esticado) ou de baixo (compacto).
    var chatExpanded = false
    /// Próxima mudança de chatHeight anima com mola (soltou a trava) em vez de seguir o dedo.
    var chatAnimate = false

    /// Conversa rolada até o fim — só então rolar para baixo recolhe a ilha.
    var chatAtBottom: Bool = true
    /// Sessão aberta no chat (id da tarefa; nil = criar sessão nova). Fica no estado do app,
    /// não na tela: o SwiftUI pode montar a tela do chat mais de uma vez ao abrir.
    @Published var chatSelection: String? = nil
    /// false = ainda não escolhida nesta abertura do chat (aí vale a sessão em foco).
    var chatSelectionSet = false

    /// Abre o chat numa sessão (ou em "nova", com nil).
    func openChat(_ taskId: String?) {
        chatSelection = taskId
        chatSelectionSet = true
        view = .prompt
    }
    /// Pin do cabeçalho: ilha fica aberta até soltar o pin.
    @Published var fixado: Bool = false
    var chatMaxHeight: CGFloat {
        let h = NSScreen.main?.visibleFrame.height ?? 800
        return max(Self.chatMinHeight, min(720, h * 0.8))
    }

    // Aprovações/perguntas pendentes, uma por sessão do Claude Code (chave: session_id)
    @Published var pendingApprovals: [String: ApprovalInfo] = [:]

    /// Pendência da sessão em foco; se ela não tiver, a mais antiga de qualquer sessão.
    var pendingApproval: ApprovalInfo? {
        if let sid = focusTask?.sessionId, let a = pendingApprovals[sid] { return a }
        return nil
    }

    // MARK: - Init (loads persisted settings)

    private init() {
        let ud = UserDefaults.standard

        carregandoAparencia = true
        if let v = ud.string(forKey: "nomePersonagem") { nomePersonagem = v }
        if let v = ud.string(forKey: "corPersonagem") { corPersonagem = v }
        if let v = ud.object(forKey: "bonePersonagem") as? Bool { bonePersonagem = v }
        if let v = ud.string(forKey: "corBone") { corBone = v }
        if let v = ud.object(forKey: "abaParaFrente") as? Bool { abaParaFrente = v }
        if let v = ud.object(forKey: "fonesIntra") as? Bool { fonesIntra = v }
        if let v = ud.object(forKey: "fonesPrata") as? Bool { fonesPrata = v }
        if let v = ud.object(forKey: "sobrancelhas") as? Bool { sobrancelhas = v }
        if let v = ud.object(forKey: "contornoPersonagem") as? Bool { contornoPersonagem = v }
        carregandoAparencia = false
        aplicarAparencia()

        if let v = ud.object(forKey: "soundEnabled") as? Bool   { soundEnabled = v }
        if let v = ud.object(forKey: "soundVolume")  as? Double { soundVolume  = v }
        // Migrate old 60s default → 15s
        if let v = ud.object(forKey: "autoCloseInterval") as? Double {
            autoCloseInterval = (v == 60) ? 15 : v
        }
        if let v = ud.object(forKey: "absenceInterval")   as? Double { absenceInterval   = v }
        if let v = ud.object(forKey: "greetThreshold")    as? Double { greetThresholdSeconds = v }
        if let v = ud.object(forKey: "hotkeyEnabled") as? Bool  { hotkeyEnabled = v }
        if let v = ud.object(forKey: "moduloBrilho") as? Bool      { moduloBrilho = v }
        if let v = ud.object(forKey: "moduloVolume") as? Bool      { moduloVolume = v }
        if let v = ud.object(forKey: "moduloOptionDuplo") as? Bool { moduloOptionDuplo = v }
        if let v = ud.object(forKey: "moduloAvisoProprio") as? Bool { moduloAvisoProprio = v }
        if let v = ud.object(forKey: "moduloAnexosChat") as? Bool  { moduloAnexosChat = v }
        if let v = ud.object(forKey: "hotkeyFlags")   as? Int   { hotkeyFlags = UInt(v) }
        if let v = ud.object(forKey: "hotkeyCode")    as? Int   { hotkeyCode = UInt16(v) }
        if let d = ud.data(forKey: "vercelProjectFilter"),
           let a = try? JSONDecoder().decode([String].self, from: d) { vercelProjectFilter = Set(a) }
        if let d = ud.data(forKey: "n8nWorkflowFilter"),
           let a = try? JSONDecoder().decode([String].self, from: d) { n8nWorkflowFilter = Set(a) }
        if let d = ud.data(forKey: "activeIntegrations"),
           let a = try? JSONDecoder().decode([String].self, from: d) { activeIntegrations = Set(a) }

        // Sync SoundEngine volume on launch
        SoundEngine.shared.volume = Float(soundVolume)

        // Always load integration pills
        loadIntegrationTasks()
    }

    // MARK: - Computed

    var focusTask: AgentTask? {
        tasks.first { $0.id == focusId } ?? tasks.first { $0.ativa } ?? tasks.first
    }

    /// Grade mostra também as paradas/ocultas (tocou no "+N paradas").
    @Published var mostrarParadas = false

    /// Oculta a sessão até o próximo pedido do Hugo nela.
    func ocultar(_ id: String) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[i].oculta = true
        if focusId == id { focusId = tasks.first { $0.ativa }?.id ?? focusId }
    }

    /// Sessões tiradas da ilha pelo Hugo (session_id). Só voltam com um pedido novo dele
    /// ou com aprovação/pergunta. Persistido: vale depois de reiniciar o app.
    private(set) var dispensadas: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "sessoesDispensadas") ?? [])

    func dispensar(_ id: String) {
        guard let t = tasks.first(where: { $0.id == id }), let sid = t.sessionId else { return }
        dispensadas.insert(sid)
        Gravar.padrao.set(Array(dispensadas), forKey: "sessoesDispensadas")
        removeTask(id: id)
    }

    func readmitir(_ sessionId: String) {
        guard dispensadas.remove(sessionId) != nil else { return }
        Gravar.padrao.set(Array(dispensadas), forKey: "sessoesDispensadas")
    }

    /// Nomes dados pelo Hugo no Crew (session_id → nome). Valem acima de qualquer outro título
    /// e sobrevivem a reiniciar o app.
    private(set) var nomesDados: [String: String] =
        (UserDefaults.standard.dictionary(forKey: "nomesSessoes") as? [String: String]) ?? [:]

    /// Sessão cujo título está sendo editado agora (id da tarefa).
    @Published var renomeando: String? = nil

    /// Abre a edição do título no lugar onde ele aparece.
    func comecarRenomear(_ id: String) {
        if view == .overview { focusId = id }
        renomeando = id
        NSApp.windows.first { $0 is IslandPanel }?.makeKey()
    }

    /// Renomeia a sessão; nome vazio volta ao título automático. No Xirp, renomeia lá também.
    func renomear(_ id: String, para nome: String) {
        renomeando = nil
        guard let i = tasks.firstIndex(where: { $0.id == id }), let sid = tasks[i].sessionId else { return }
        let nome = nome.trimmingCharacters(in: .whitespacesAndNewlines)
        if nome.isEmpty {
            nomesDados[sid] = nil
        } else {
            nomesDados[sid] = nome
            tasks[i].title = nome
        }
        Gravar.padrao.set(nomesDados, forKey: "nomesSessoes")
        if nome.isEmpty { HookServer.shared.recarregarTitulo(id) }
        guard !nome.isEmpty, Xirp.available else { return }
        Task {
            guard let xid = await Xirp.sessionId(forClaudeSession: sid) else { return }
            _ = await Xirp.rename(xirpId: xid, name: nome)
        }
    }

    /// Encerra a sessão (motor do Crew ou Xirp); o SessionEnd (ou a morte do processo) a tira da ilha.
    func encerrar(_ id: String) {
        guard let sid = tasks.first(where: { $0.id == id })?.sessionId else { return }
        Task {
            if await MotorCrew.ehDoCrew(sid) { _ = await MotorCrew.encerrar(sid); return }
            guard let xid = await Xirp.sessionId(forClaudeSession: sid) else { return }
            _ = await Xirp.stop(xirpId: xid)
        }
    }

    func mostrar(_ id: String) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[i].oculta = false
        tasks[i].parada = false
        tasks[i].lastEvent = .now
    }

    var effectiveState: BotState {
        stateOverride ?? focusTask?.state ?? .idle
    }

    // MARK: - Task management

    func addTask(_ task: AgentTask) {
        guard !tasks.contains(where: { $0.id == task.id }) else { return }
        tasks.append(task)
        if focusId == nil { focusId = task.id }
        syncMode()
        syncView()
    }

    func removeTask(id: String) {
        // Sessão que sai da lista (encerrada, fechada, tirada) fica no Histórico do Crew.
        if let t = tasks.first(where: { $0.id == id }) {
            HistoricoCrew.shared.guardar(t)
            // O shell que o Hugo abriu nessa sessão (botão Terminal) fecha junto.
            if let sid = t.sessionId, !CaptureTool.ativo { TerminalSessao.encerrarShell(sid) }
        }
        tasks.removeAll { $0.id == id }
        if focusId == id { focusId = tasks.first?.id }
        syncMode()
        syncView()
    }

    func updateTask(id: String, state: BotState) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[idx].state = state
    }

    func setFocus(_ id: String) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        focusId = id
        tasks[idx].pillBadge = nil  // clear badge when user brings task to focus
    }

    /// Regra: com música tocando a ilha nunca sai da tela (no mínimo compacta, com a capa).
    var musicaTocando: Bool { MediaService.shared.nowPlaying?.isPlaying == true }

    func syncMode() {
        // If no tasks and not expanded/peek, go hidden — a não ser que esteja tocando música
        let temAlgo = !tasks.isEmpty || musicaTocando
        if !temAlgo && mode == .compact {
            mode = .hidden
        } else if temAlgo && mode == .hidden && isPresent {
            mode = .compact
        }
    }

    func syncView() {
        guard mode == .expanded else { return }
        if view == .empty && !tasks.isEmpty { view = .overview }
        else if view == .overview && tasks.isEmpty { view = .empty }
    }

    /// Load integration pills respecting activeIntegrations. VS Code always loads. Safe to call multiple times.
    func loadIntegrationTasks() {
        guard AgentTask.integracoesLigadas else { return }
        for task in AgentTask.integrationAgents {
            // O Claude Code não é mais uma pílula fixa: cada sessão vira a sua.
            let shouldLoad = task.id != "integration_claude" && activeIntegrations.contains(task.id)
            let loaded = tasks.contains(where: { $0.id == task.id })
            if shouldLoad && !loaded { tasks.append(task) }
            if !shouldLoad && loaded { tasks.removeAll { $0.id == task.id } }
        }
        if focusId == nil { focusId = tasks.first?.id }
        syncMode()
    }

    /// Toggle an integration pill on/off. VS Code cannot be toggled. Max 4 active at once.
    func toggleIntegration(_ id: String) {
        guard id != "integration_claude" else { return }
        if activeIntegrations.contains(id) {
            activeIntegrations.remove(id)
            tasks.removeAll { $0.id == id }
            if focusId == id { focusId = tasks.first?.id }
        } else {
            guard activeIntegrations.count < 4 else { return }
            activeIntegrations.insert(id)
            if let task = AgentTask.integrationAgents.first(where: { $0.id == id }),
               !tasks.contains(where: { $0.id == id }) {
                tasks.append(task)
            }
        }
        syncMode()
    }

}

// MARK: - Supporting types

enum PromptContext {
    case window(appName: String, title: String, url: String?)
    case file(name: String, fileURL: URL?)
}

struct DroppedFile {
    var url: URL
    var name: String
}

struct SearchResult {
    var title: String
    var items: [ResultItem]
    var note: String?
}

struct ResultItem {
    var label: String
    var detail: String
    var url: String?
}
