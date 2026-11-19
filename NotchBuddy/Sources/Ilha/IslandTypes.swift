import Foundation

// MARK: - Island Mode

enum IslandMode: String, CaseIterable {
    case hidden, compact, expanded
}

// MARK: - Island View

enum IslandView: String, CaseIterable {
    /// Telas que podem pedir mais altura (`AppState.alturaAba`): abas de módulo e o "Vira task?".
    var cresce: Bool { self == .modulo || self == .sugestao }

    case overview, empty, approval, question, error, finished
    case confused, upload, uploading, choose, mail, prompt
    case searching, result, note, settings, greeting
    case media
    /// O Homie pergunta se uma sugestão vira task (módulo Tasks).
    case sugestao
    /// Aba de um módulo do registro (qual: `AppState.moduloAberto`).
    case modulo
    /// Grade com todos os módulos que têm aba (botão de grade no cabeçalho).
    case modulos
}

// MARK: - Bot State

enum BotState: String, CaseIterable {
    case idle, working, thinking, searching
    case approval, question, error, finished
    case ratelimit, sleeping, dizzy
}

// MARK: - Bot Emote

enum BotEmote: String, CaseIterable {
    case love, surprised, proud, wink, yawn, happy, annoyed
}

// MARK: - View dimensions (from VIEWS in prototype)

struct ViewLayout {
    let height: CGFloat
    let botX: CGFloat
    let botY: CGFloat?         // nil = auto-centered
    let botDiameter: CGFloat
    let agentMode: AgentLayoutMode
}

enum AgentLayoutMode {
    case none, grid, pills, column
}

// MARK: - Constants (from NW, NH, EW in prototype)

enum IslandConst {
    static let notchWidth: CGFloat  = 184
    static let notchHeight: CGFloat = 32
    static let expandedWidth: CGFloat = 640
    static let earRadius: CGFloat   = 14
    static let roundedCorner: CGFloat = 14    // hidden/peek/compact
    static let expandedCorner: CGFloat = 22

    /// Layout de uma tela; tela sem entrada usa o da visão geral (antes derrubava o app).
    static func layout(_ v: IslandView) -> ViewLayout { viewLayouts[v] ?? viewLayouts[.overview]! }

    static let viewLayouts: [IslandView: ViewLayout] = [
        // Home is the reference: height 150
        .overview:  ViewLayout(height: 160, botX: 68,  botY: nil, botDiameter: 58, agentMode: .pills),
        // All non-chat views match home height (150) — law
        .empty:     ViewLayout(height: 160, botX: 70,  botY: nil, botDiameter: 62, agentMode: .none),
        .approval:  ViewLayout(height: 160, botX: 62,  botY: nil, botDiameter: 56, agentMode: .column),
        .question:  ViewLayout(height: 160, botX: 62,  botY: nil, botDiameter: 56, agentMode: .column),
        .sugestao:  ViewLayout(height: 160, botX: 62,  botY: nil, botDiameter: 56, agentMode: .none),
        .error:     ViewLayout(height: 160, botX: 62,  botY: nil, botDiameter: 58, agentMode: .column),
        .finished:  ViewLayout(height: 160, botX: 62,  botY: nil, botDiameter: 58, agentMode: .column),
        .confused:  ViewLayout(height: 160, botX: 76,  botY: nil, botDiameter: 66, agentMode: .column),
        .upload:    ViewLayout(height: 176, botX: 140, botY: 104, botDiameter: 62, agentMode: .column),
        .uploading: ViewLayout(height: 176, botX: 46,  botY: 118, botDiameter: 20, agentMode: .none),
        .choose:    ViewLayout(height: 176, botX: 60,  botY: 101, botDiameter: 52, agentMode: .column),
        .mail:      ViewLayout(height: 240, botX: 56,  botY: nil, botDiameter: 46, agentMode: .column),
        .prompt:    ViewLayout(height: 160, botX: 52,  botY: nil, botDiameter: 44, agentMode: .column),
        .searching: ViewLayout(height: 160, botX: 52,  botY: nil, botDiameter: 44, agentMode: .column),
        .result:    ViewLayout(height: 160, botX: 52,  botY: nil, botDiameter: 44, agentMode: .column),
        .note:      ViewLayout(height: 160, botX: 60,  botY: nil, botDiameter: 50, agentMode: .column),
        .media:     ViewLayout(height: 160, botX: 62,  botY: nil, botDiameter: 56, agentMode: .none),
        .settings:  ViewLayout(height: 160, botX: 54,  botY: nil, botDiameter: 46, agentMode: .none),
        // Abas dos módulos: mesma altura de todas (lei), Homie à esquerda
        .modulo:    ViewLayout(height: 160, botX: 58,  botY: nil, botDiameter: 50, agentMode: .none),
        .modulos:   ViewLayout(height: 160, botX: 58,  botY: nil, botDiameter: 50, agentMode: .none),
        // Greeting: bot drawn by GreetingCanvasView; no BotPlacement needed
        .greeting:  ViewLayout(height: 150, botX: 320, botY: 90,  botDiameter: 0,  agentMode: .none),
    ]

    // Project colors — keyed by lowercase display name or slug
    static let projectColors: [String: String] = [
        "korus":             "#FF5A4E",
        "sbe hub":           "#2EC4A0",
        "morning ai brief":  "#F29B38",
        "publication ig":    "#7C5CFF",
        "ig post":           "#7C5CFF",
        "notch buddy":       "#EC4899",
        "notch-buddy":       "#EC4899",
        "notchbuddy":        "#EC4899",
    ]

    static let fallbackColors = ["#22C55E", "#EAB308", "#60A5FA", "#E879F9"]

    // Available integration pills (matches AgentTask.integrationAgents)
    struct IntegrationMeta {
        let id: String
        let name: String
        let color: String
    }
    static let allIntegrations: [IntegrationMeta] = [
        .init(id: "integration_resend",  name: "Resend",  color: "#22C55E"),
        .init(id: "integration_n8n",     name: "n8n",     color: "#F29B38"),
        .init(id: "integration_vercel",  name: "Vercel",  color: "#7C5CFF"),
        .init(id: "integration_github",  name: "GitHub",  color: "#F4505E"),
        .init(id: "integration_notion",  name: "Notion",  color: "#8C8C8C"),
        .init(id: "integration_calcom",  name: "Cal.com", color: "#C9956A"),
        .init(id: "integration_stripe",  name: "Stripe",  color: "#0570DE"),
    ]

    /// Returns the fixed project color for a display name, or a stable fallback.
    static func colorForProject(_ name: String) -> String {
        let key = name.lowercased().trimmingCharacters(in: .whitespaces)
        if let c = projectColors[key] { return c }
        // partial match (e.g. "korus-api" → "korus")
        for (k, c) in projectColors where key.hasPrefix(k) || key.contains(k) { return c }
        return fallbackColors[abs(name.hashValue) % fallbackColors.count]
    }

    // State card wash colors (radial gradient from bottom)
    static let washColors: [IslandView: String] = [
        .approval:  "rgba(245,165,36,0.42)",
        .question:  "rgba(34,211,238,0.38)",
        .sugestao:  "rgba(167,139,250,0.36)",
        .error:     "rgba(244,80,94,0.55)",
        .finished:  "rgba(52,211,153,0.5)",
        .confused:  "rgba(244,114,182,0.55)",
        .searching: "rgba(99,102,241,0.5)",
        .result:    "rgba(52,211,153,0.22)",
        .prompt:    "rgba(99,102,241,0.22)",
    ]
}
