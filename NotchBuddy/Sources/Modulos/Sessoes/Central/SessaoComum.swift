import SwiftUI
import AppKit

// O que as telas do app do Crew compartilham sobre uma sessão: quais são, se esperam o Hugo,
// a cor do estado, o "há quanto tempo" e o menu de ações.

@MainActor
enum SessoesCrew {
    /// Só sessões do Claude Code (as pílulas de integração ficam de fora).
    static func todas(_ state: AppState) -> [AgentTask] {
        state.tasks.filter { $0.sessionId != nil && !$0.isIntegration }
    }

    /// A sessão tem aprovação ou pergunta esperando o Hugo.
    static func esperando(_ t: AgentTask, _ state: AppState) -> Bool {
        t.sessionId.map { state.pendingApprovals[$0] != nil } ?? false
    }

    /// As que pedem resposta, da mais recente para a mais antiga.
    static func pendentes(_ state: AppState) -> [AgentTask] {
        todas(state).filter { esperando($0, state) }.sorted { $0.lastEvent > $1.lastEvent }
    }

    /// "agora", "5 min", "2 h", "3 d".
    static func haQuanto(_ d: Date) -> String {
        let s = Int(Date().timeIntervalSince(d))
        if s < 60 { return "agora" }
        if s < 3600 { return "\(s / 60) min" }
        if s < 86_400 { return "\(s / 3600) h" }
        return "\(s / 86_400) d"
    }

    /// O estado em palavras, já contando a pendência.
    static func rotulo(_ t: AgentTask, esperando: Bool) -> String {
        esperando ? "pede sua resposta" : t.stateLabel
    }
}

enum CorDoEstado {
    static func de(_ s: BotState, esperando: Bool) -> Color {
        if esperando { return Tema.ambar }
        switch s {
        case .working, .thinking, .searching: return Tema.azul
        case .approval, .question: return Tema.ambar
        case .error, .ratelimit: return Tema.vermelho
        case .finished: return Tema.verde
        default: return Tema.cinza
        }
    }
}

/// Ações de uma sessão (menu de contexto da lista e botão "…" do cabeçalho).
@MainActor
enum MenuSessao {
    /// Enxuto de propósito: o que o Hugo usa. (Transcript, id e comando de retomar saíram em
    /// 2026-11-12; a conversa encerrada tem os dois últimos no Histórico.)
    static func itens(_ task: AgentTask) -> [ItemMenu] {
        let state = AppState.shared
        var out: [ItemMenu] = [.acao("Abrir navegador", icone: "globe") {
            NotificationCenter.default.post(name: .navegadorDaSessao, object: task.id)
        }]
        if let cwd = task.sessionCwd {
            out.append(.acao("Arquivos do projeto", icone: "folder") {
                NotificationCenter.default.post(name: .arquivosDaSessao, object: task.id)
            })
            out.append(.acao("Mostrar a pasta no Finder", icone: "arrow.up.forward.square") {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: cwd)
            })
        }
        out.append(.divisor)
        if task.oculta || task.parada {
            out.append(.acao("Mostrar na ilha", icone: "eye") { state.mostrar(task.id) })
        } else {
            out.append(.acao("Ocultar da ilha", icone: "eye.slash") { state.ocultar(task.id) })
        }
        out.append(.acao("Tirar do Crew", icone: "xmark.circle", destrutivo: true) { state.dispensar(task.id) })
        return out
    }

    static func aspas(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}
