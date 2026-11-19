import Foundation

// MARK: - Approval info (pending PermissionRequest from Claude Code)

struct ApprovalInfo: @unchecked Sendable {
    var sessionId: String
    var tool: String
    var command: String
    /// Pergunta com opções (AskUserQuestion) — quando presente, a aprovação vira escolha.
    var questions: [QuestionInfo] = []
    /// Plano a aprovar (ExitPlanMode).
    var plan: String? = nil
    /// Para que serve o comando, nas palavras do Claude.
    var purpose: String? = nil
    /// tool_input original, devolvido com as respostas preenchidas.
    var toolInput: [String: Any] = [:]
}

struct QuestionInfo: @unchecked Sendable {
    var question: String
    var header: String
    var options: [String]
    var multiSelect: Bool
}

// MARK: - Pill badge (shown on pill edge when non-focused task has an alert)

enum PillBadge { case approval, finished, error }

// MARK: - Agent Task

struct AgentTask: Identifiable, Equatable {
    var id: String
    var name: String
    var color: String          // hex
    var state: BotState
    var stepIndex: Int = 0
    var steps: [String]
    var source: AgentSource
    var isIntegration: Bool = false  // true for persistent integration pills
    var emote: BotEmote? = nil
    var miniEye: EyeShape? = nil
    var pillBadge: PillBadge? = nil  // alert badge shown on pill when not focused
    var sessionCwd: String?  = nil  // last known working directory (Claude Code sessions)
    var sessionAppBundleId: String? = nil  // app de onde a sessão roda (Xirp, Terminal, VS Code…)
    // Sessões do Claude Code: uma tarefa por sessão
    var sessionId: String? = nil
    var transcriptPath: String? = nil
    var title: String? = nil               // título da sessão (o que o Claude Code dá ou o /rename)
    var lastPrompt: String? = nil          // último pedido do Hugo
    var delivery: String? = nil            // última resposta do Claude (entrega)
    var claudePid: pid_t? = nil            // processo do Claude Code, para saber quando a sessão fechou
    var lastEvent: Date = .now
    var oculta = false                     // Hugo ocultou; volta no próximo pedido dele
    var parada = false                     // sem evento há 15 min e sem pendência

    static func == (a: AgentTask, b: AgentTask) -> Bool {
        a.id == b.id && a.name == b.name && a.color == b.color && a.state == b.state
            && a.stepIndex == b.stepIndex && a.steps == b.steps && a.emote == b.emote
            && a.miniEye == b.miniEye && a.pillBadge == b.pillBadge && a.lastPrompt == b.lastPrompt
            && a.delivery == b.delivery && a.sessionCwd == b.sessionCwd && a.title == b.title
            && a.oculta == b.oculta && a.parada == b.parada
    }
}

extension AgentTask {
    /// Aparece na grade: nem ocultada nem parada.
    var ativa: Bool { !oculta && !parada }

    /// Nome para bater o olho: título da sessão; sem título, o projeto.
    var displayTitle: String { title ?? name }

    /// Estado em uma palavra ou duas.
    var stateLabel: String {
        switch state {
        case .working:   return "trabalhando"
        case .thinking:  return "pensando"
        case .searching: return "pesquisando"
        case .approval:  return "esperando sua permissão"
        case .question:  return "esperando sua resposta"
        case .error:     return "erro"
        case .finished:  return "entregou"
        case .ratelimit: return "limite de uso"
        default:         return "esperando você"
        }
    }

    /// Descrição curta: primeira frase da entrega (ou do pedido), sem markdown.
    var brief: String? {
        guard let raw = delivery ?? lastPrompt else { return nil }
        var t = raw.replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "#", with: "")
        t = t.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? ""
        // Primeira frase; se ela for curta demais ("Confirmado:"), junta a seguinte.
        var cut = t.startIndex
        while let end = t.range(of: #"[.!?](\s|$)"#, options: .regularExpression, range: cut..<t.endIndex) {
            cut = t.index(after: end.lowerBound)
            if t.distance(from: t.startIndex, to: cut) >= 40 { break }
        }
        if cut > t.startIndex { t = String(t[..<cut]) }
        return t.count > 110 ? String(t.prefix(107)) + "…" : t
    }
}

enum AgentSource: Equatable {
    case claudeCode
    case n8n
}
