import SwiftUI

// MARK: - Overview

struct OverviewView: View {
    @ObservedObject var state: AppState
    @State private var showingN8nDetail = false

    var agent: AgentTask? { state.focusTask }

    var body: some View {
        HStack(spacing: 10) {
            // Left card: title row + ticker below + ↗ button overlay
            ZStack(alignment: .topLeading) {
                CardBackground(wash: nil)

                // Title row + ticker stacked (or integration card)
                if let agent = agent {
                    if agent.isIntegration {
                        IntegrationCardView(task: agent, showingDetail: $showingN8nDetail)
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            // Título da sessão
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color(hex: agent.color))
                                    .frame(width: 7, height: 7)
                                TituloSessao(state: state, task: agent, tamanho: 13)
                            }
                            .padding(.top, 6)
                            .padding(.leading, 108)
                            .padding(.trailing, 36)

                            // Projeto · estado, e à direita o selo da fila (outras sessões)
                            HStack(spacing: 6) {
                                Text(agent.title != nil ? "\(agent.name) · \(agent.stateLabel)" : agent.stateLabel)
                                    .font(.system(size: 11))
                                    .foregroundColor(Color(hex: "#8E939C"))
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                SeloFila(state: state)
                            }
                            .padding(.top, 2)
                            .padding(.leading, 121)
                            .padding(.trailing, 10)

                            if [.working, .thinking, .searching].contains(agent.state), !agent.steps.isEmpty {
                                TickerView(task: agent)
                                    .frame(height: 44)
                                    .padding(.top, 4)
                                    .padding(.leading, 108)
                                    .padding(.trailing, 12)
                            } else if let brief = agent.brief {
                                // Descrição curta: primeira frase da entrega
                                Text(brief)
                                    .font(.system(size: 12))
                                    .foregroundColor(Color(hex: "#C5C8CD"))
                                    .lineLimit(2)
                                    .truncationMode(.tail)
                                    .frame(maxWidth: .infinity, alignment: .topLeading)
                                    .padding(.top, 8)
                                    .padding(.leading, 121)
                                    .padding(.trailing, 12)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.top, 4)
                        .contextMenu {
                            if agent.sessionId != nil {
                                Button("Ocultar sessão") { state.ocultar(agent.id) }
                                SessaoMenuFim(state: state, task: agent)
                            }
                        }
                        // Tocar na sessão abre a conversa dela
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if agent.source == .claudeCode { state.openChat(agent.id) }
                        }
                    }
                }

                // ↗ jump button — last in ZStack so it renders on top; hidden while any detail is open
                if !showingN8nDetail {
                    Button(action: { openAgentTarget(agent) }) {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(Color(hex: "#5F646D"))
                            .frame(width: 16, height: 16)
                            .background(Color.white.opacity(0.07))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                    .padding(.trailing, 10)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .frame(width: 322)

            // Cartão da direita: o Mac agora (blocos dos módulos). A home junta os dois lados do
            // Crew: sessões à esquerda, Mac à direita.
            CardBackground(wash: nil) {
                PainelMac()
            }
        }
        .onChange(of: state.focusId) { _, _ in showingN8nDetail = false }
    }

    private func openAgentTarget(_ task: AgentTask?) {
        guard let task else { return }
        switch task.id {
        case "integration_claude":
            // Leva ao app de onde a sessão roda (Xirp, terminal…); sem pista, VS Code como antes.
            if let appId = task.sessionAppBundleId,
               let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == appId }) {
                app.activate(options: .activateIgnoringOtherApps)
                return
            }
            let vscodeBundleId = "com.microsoft.VSCode"
            if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == vscodeBundleId }) {
                app.activate(options: .activateIgnoringOtherApps)
            } else {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Visual Studio Code.app"))
            }
        case "integration_resend":
            NSWorkspace.shared.open(URL(string: "https://resend.com/emails")!)
        case "integration_vercel":
            NSWorkspace.shared.open(URL(string: "https://vercel.com/dashboard")!)
        case "integration_github":
            NSWorkspace.shared.open(URL(string: "https://github.com")!)
        case "integration_n8n":
            if let urlStr = KeychainStore.shared.get("n8n-url"), let url = URL(string: urlStr) {
                NSWorkspace.shared.open(url)
            }
        case "integration_stripe":
            NSWorkspace.shared.open(URL(string: "https://dashboard.stripe.com/payments")!)
        case "integration_notion":
            NSWorkspace.shared.open(URL(string: "https://notion.so")!)
        case "integration_calcom":
            NSWorkspace.shared.open(URL(string: "https://app.cal.com/bookings")!)
        default:
            // Non-integration real tasks
            if task.source == .n8n {
                if let urlStr = KeychainStore.shared.get("n8n-url"), let url = URL(string: urlStr) {
                    NSWorkspace.shared.open(url)
                }
            } else {
                abrirSessao(task)
            }
        }
    }
}

// MARK: - Empty

struct EmptyStateView: View {
    @ObservedObject var state: AppState

    var body: some View {
        ZStack {
            CardBackground(wash: nil)
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Nenhuma sessão do Claude Code aberta.")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Elas aparecem aqui assim que começarem.")
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "#9398A1"))
                }
                Spacer()
                PrimaryButton("Nova sessão") {
                    state.openChat(nil)
                }
            }
            .padding(.leading, 118)
            .padding(.trailing, 18)
        }
    }
}
