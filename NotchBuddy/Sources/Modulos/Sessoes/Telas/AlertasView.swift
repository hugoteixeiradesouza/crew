import SwiftUI

// MARK: - Approval

struct ApprovalView: View {
    @ObservedObject var state: AppState

    var approval: ApprovalInfo? { state.pendingApproval }

    var body: some View {
        ZStack {
            CardBackground(wash: .amber)
            VStack(alignment: .leading, spacing: 5) {
                AgentWho(task: state.focusTask, label: approval?.plan != nil ? "quer aprovar o plano" : "pede permissão")
                if let purpose = approval?.purpose, approval?.plan == nil {
                    Text(purpose)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                }
                if let plan = approval?.plan {
                    ScrollView {
                        Text(plan)
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "#E8E9EC"))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 64)
                } else {
                    CodeBlock(text: approval?.command ?? approval?.tool ?? "…")
                        .lineLimit(approval?.purpose == nil ? 2 : 1)
                        .truncationMode(.middle)
                }
                HStack(spacing: 8) {
                    SecondaryButton("Negar") {
                        HookServer.shared.sendApprovalDecision("deny")
                    }
                    PrimaryButton(approval?.plan != nil ? "Aprovar plano" : "Permitir") {
                        HookServer.shared.sendApprovalDecision("allow")
                    }
                    if approval?.plan == nil {
                        SecondaryButton("Sempre") {
                            HookServer.shared.sendApprovalDecision("always")
                        }
                    }
                    PendingCounter(state: state)
                }
            }
            .padding(.leading, 116)
            .padding(.trailing, 16)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// "+2 esperando" quando outras sessões também aguardam resposta.
struct PendingCounter: View {
    @ObservedObject var state: AppState

    var body: some View {
        let others = state.pendingApprovals.count - (state.pendingApproval == nil ? 0 : 1)
        if others > 0 {
            Text("+\(others) esperando")
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "#F5A524"))
        }
    }
}

// MARK: - Question

struct QuestionView: View {
    @ObservedObject var state: AppState
    @State private var index = 0
    @State private var answers: [String: String] = [:]
    @State private var picked: Set<String> = []

    private var approval: ApprovalInfo? { state.pendingApproval }

    var body: some View {
        ZStack {
            CardBackground(wash: .cyan)
            VStack(alignment: .leading, spacing: 5) {
                if let approval, index < approval.questions.count {
                    let q = approval.questions[index]
                    AgentWho(task: state.focusTask,
                             label: approval.questions.count > 1 ? "pergunta \(index + 1)/\(approval.questions.count)" : "pergunta")
                    Text(q.question)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(q.options, id: \.self) { opt in
                                if q.multiSelect {
                                    SecondaryButton((picked.contains(opt) ? "✓ " : "") + opt) {
                                        if picked.contains(opt) { picked.remove(opt) } else { picked.insert(opt) }
                                    }
                                } else {
                                    SecondaryButton(opt) { answer(q, opt, approval) }
                                }
                            }
                        }
                    }
                    HStack(spacing: 8) {
                        if q.multiSelect {
                            PrimaryButton("Enviar") { answer(q, picked.sorted().joined(separator: ", "), approval) }
                                .disabled(picked.isEmpty)
                        }
                        SecondaryButton("Responder no terminal") {
                            HookServer.shared.sendApprovalDecision("ask", sessionId: approval.sessionId)
                            if let t = state.focusTask { abrirSessao(t) }
                        }
                        PendingCounter(state: state)
                    }
                } else {
                    // Pergunta vinda de notificação: só dá para responder na sessão.
                    AgentWho(task: state.focusTask, label: "pergunta")
                    Text(state.focusTask?.steps.last ?? "O Claude está esperando sua resposta.")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(3)
                    HStack(spacing: 8) {
                        PrimaryButton("Abrir sessão") { state.openChat(state.focusId) }
                    }
                }
            }
            .padding(.leading, 116)
            .padding(.trailing, 16)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: approval?.sessionId) { _, _ in index = 0; answers = [:]; picked = [] }
    }

    private func answer(_ q: QuestionInfo, _ value: String, _ approval: ApprovalInfo) {
        answers[q.question] = value
        picked = []
        if index + 1 < approval.questions.count {
            index += 1
        } else {
            HookServer.shared.sendAnswers(answers, sessionId: approval.sessionId)
            index = 0; answers = [:]
        }
    }
}

// MARK: - Error

struct ErrorView: View {
    @ObservedObject var state: AppState

    var body: some View {
        ZStack {
            CardBackground(wash: .red)
            VStack(alignment: .leading, spacing: 5) {
                AgentWho(task: state.focusTask, label: "parou com erro")
                Text(state.focusTask?.delivery ?? "A sessão parou.")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "#FF8D97"))
                    .lineLimit(3)
                HStack(spacing: 8) {
                    PrimaryButton("Abrir sessão") { state.openChat(state.focusId) }
                    SecondaryButton("OK") {
                        NotificationCenter.default.post(name: .islandCollapse, object: nil)
                    }
                }
            }
            .padding(.leading, 116)
            .padding(.trailing, 16)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Finished

struct FinishedView: View {
    @ObservedObject var state: AppState

    var body: some View {
        ZStack {
            CardBackground(wash: .green)
            VStack(alignment: .leading, spacing: 5) {
                AgentWho(task: state.focusTask, label: "entregou")
                ScrollView {
                    Text(state.focusTask?.delivery ?? state.focusTask?.steps.last ?? "Terminou.")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "#E8E9EC"))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 74)
                HStack(spacing: 8) {
                    PrimaryButton("Abrir sessão") { state.openChat(state.focusId) }
                    SecondaryButton("OK") {
                        NotificationCenter.default.post(name: .islandCollapse, object: nil)
                    }
                }
            }
            .padding(.leading, 116)
            .padding(.trailing, 16)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Leva até o app de onde a sessão roda (Xirp, Terminal, VS Code…).
@MainActor
func abrirSessao(_ task: AgentTask) {
    // Sessão do motor do Crew: não tem app dono — abre um terminal ligado ao tmux dela.
    if task.sessionAppBundleId == nil || task.sessionAppBundleId == Bundle.main.bundleIdentifier,
       let sid = task.sessionId {
        Task {
            if await MotorCrew.ehDoCrew(sid) { await MotorCrew.abrirNoTerminal(sid) }
            else { abrirAppDaSessao(task) }
        }
        return
    }
    abrirAppDaSessao(task)
}

@MainActor
private func abrirAppDaSessao(_ task: AgentTask) {
    if let appId = task.sessionAppBundleId,
       let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == appId }) {
        app.activate(options: .activateIgnoringOtherApps)
        return
    }
    let terminals = ["com.apple.Terminal", "com.googlecode.iterm2", "net.kovidgoyal.kitty", "com.mitchellh.ghostty"]
    if let hit = terminals.compactMap({ id in
        NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == id }
    }).first {
        hit.activate(options: .activateIgnoringOtherApps)
    }
}

// MARK: - Confused

struct ConfusedView: View {
    var body: some View {
        ZStack {
            CardBackground(wash: .pink)
            VStack(alignment: .leading, spacing: 5) {
                Text("Opa, muito tapa de uma vez.").font(.system(size: 15, weight: .semibold))
                Text("Só um instante — volto em três segundos.")
                    .font(.system(size: 13)).foregroundColor(Color(hex: "#9398A1"))
            }
            .padding(.leading, 128)
            .padding(.trailing, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
