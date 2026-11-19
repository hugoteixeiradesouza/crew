import SwiftUI

// MARK: - Agent pills (overview right card)

struct AgentPillsView: View {
    @ObservedObject var state: AppState

    /// Homie sempre presente, esperando para abrir uma sessão nova.
    static let novaSessao = AgentTask(id: "nova_sessao", name: "Nova sessão", color: "#8E939C",
                                      state: .sleeping, steps: [], source: .claudeCode)
    @State private var swapping = false

    /// Juntas por projeto (mesma cor = mesmo repo)
    private var others: [AgentTask] {
        Projetos.agrupadas(state.tasks.filter { $0.id != state.focusId })
    }

    /// Ativas sempre; paradas/ocultas só quando o Hugo abre o "+N paradas".
    private var displayTasks: [AgentTask] {
        state.mostrarParadas ? others : others.filter(\.ativa)
    }

    private var paradas: Int { state.tasks.filter { !$0.ativa && $0.id != state.focusId }.count }

    /// Homie que agrupa as sessões paradas/ocultas; toque mostra ou esconde.
    private var grupoParadas: AgentTask {
        AgentTask(id: "grupo_paradas", name: state.mostrarParadas ? "Esconder paradas" : "+\(paradas) paradas",
                  color: "#5F646D", state: .sleeping, steps: [], source: .claudeCode)
    }

    private var pills: [AgentTask] {
        displayTasks + (paradas > 0 ? [grupoParadas] : []) + [AgentPillsView.novaSessao]
    }

    private let columns = [
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4)
    ]

    /// Sessões em blocos por projeto (repo), na ordem de `displayTasks`.
    private var grupos: [(chave: String, nome: String, cor: String, tarefas: [AgentTask])] {
        var out: [(chave: String, nome: String, cor: String, tarefas: [AgentTask])] = []
        for t in displayTasks {
            let k = Projetos.chave(t)
            if let i = out.firstIndex(where: { $0.chave == k }) { out[i].tarefas.append(t); continue }
            let nome = t.sessionId == nil ? "Integrações" : (Projetos.nome(de: t.sessionCwd) ?? t.name)
            out.append((k, nome, t.color, [t]))
        }
        return out
    }

    /// "2 trabalhando · 1 esperando você" — o que está acontecendo, de relance.
    private var resumo: String {
        let sessoes = state.tasks.filter { $0.source == .claudeCode && $0.sessionId != nil && $0.ativa }
        let trabalhando = sessoes.filter { [.working, .thinking, .searching].contains($0.state) }.count
        let esperando = sessoes.filter { $0.pillBadge == .approval }.count
        var partes: [String] = []
        if trabalhando > 0 { partes.append("\(trabalhando) trabalhando") }
        if esperando > 0 { partes.append("\(esperando) esperando você") }
        if partes.isEmpty { partes.append(sessoes.count == 1 ? "1 sessão" : "\(sessoes.count) sessões") }
        return partes.joined(separator: " · ")
    }

    var body: some View {
        // Mais sessões que cabem: rola em vez de esconder as demais.
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 6) {
                if grupos.isEmpty {
                    Text(resumo).font(.system(size: 10)).foregroundColor(Color(hex: "#8E939C"))
                }
                ForEach(grupos, id: \.chave) { g in
                    VStack(alignment: .leading, spacing: 4) {
                        // Nome do projeto na cor dele: diz de qual repo é cada sessão
                        HStack(spacing: 5) {
                            Circle().fill(Color(hex: g.cor)).frame(width: 5, height: 5)
                            Text(g.nome.uppercased()).font(.system(size: 9, weight: .bold)).tracking(0.6)
                                .foregroundColor(Color(hex: g.cor).opacity(0.85)).lineLimit(1)
                            // Resumo geral na linha do primeiro projeto (economiza uma linha)
                            if g.chave == grupos.first?.chave {
                                Spacer(minLength: 4)
                                Text(resumo).font(.system(size: 10)).foregroundColor(Color(hex: "#8E939C")).lineLimit(1)
                            }
                        }
                        LazyVGrid(columns: columns, spacing: 4) {
                            ForEach(g.tarefas) { task in pill(task) }
                        }
                    }
                }
                LazyVGrid(columns: columns, spacing: 4) {
                    if paradas > 0 { pill(grupoParadas) }
                    pill(AgentPillsView.novaSessao)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 8).padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func pill(_ task: AgentTask) -> some View {
        AgentPill(task: task, state: state, swapping: $swapping) {
            if task.id == "grupo_paradas" {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { state.mostrarParadas.toggle() }
                return
            }
            if task.id == AgentPillsView.novaSessao.id {
                state.openChat(nil)
                SoundEngine.shared.play("blip")
                return
            }
            swapping = true
            state.setFocus(task.id)
            // Sessão com pendência abre direto na pergunta/aprovação dela
            if let sid = task.sessionId, let p = state.pendingApprovals[sid] {
                state.view = p.questions.isEmpty ? .approval : .question
            }
            SoundEngine.shared.play("blip")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { swapping = false }
        }
        .opacity(task.sessionId != nil && !task.ativa ? 0.5 : 1)
        .contextMenu {
            if task.sessionId != nil {
                if task.ativa {
                    Button("Ocultar sessão") { state.ocultar(task.id) }
                } else {
                    Button("Mostrar sessão") { state.mostrar(task.id) }
                }
                SessaoMenuFim(state: state, task: task)
            }
        }
    }
}

struct AgentPill: View {
    let task: AgentTask
    @ObservedObject var state: AppState
    @Binding var swapping: Bool
    let onTap: () -> Void
    @State private var isHovered = false

    // A pílula do Claude Code mostra sempre "Claude Code", qualquer que seja o projeto ativo
    private var displayName: String {
        task.id == "integration_claude" ? "Claude Code" : task.displayTitle
    }

    var body: some View {
        Button(action: { onTap() }) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Capsule()
                        .fill(isHovered
                              ? Color(hex: task.color).opacity(0.18)
                              : Color(hex: "#0E0F11"))
                    Capsule()
                        .stroke(Color(hex: task.color).opacity(isHovered ? 0.55 : 0.14), lineWidth: 1)
                    // Homie à esquerda, nome no espaço que sobra — nome longo corta, não cobre o Homie
                    HStack(spacing: 6) {
                        MiniBotCanvasView(task: task)
                            .frame(width: 22 / 0.6, height: 22 / 0.6)
                            .frame(width: 22, height: 22, alignment: .center)
                        Text(displayName)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(isHovered
                                             ? Color(hex: task.color).lighter(by: 0.3)
                                             : Color(hex: "#9398A1"))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.leading, 8)
                    .padding(.trailing, 10)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .shadow(color: Color(hex: task.color).opacity(isHovered ? 0.35 : 0), radius: 10, x: 0, y: 2)

                // Alert badge (approval / finished / error)
                if let badge = task.pillBadge {
                    PillBadgeView(badge: badge, taskColor: task.color)
                        .offset(x: 3, y: -3)
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.04 : 1.0)
        .brightness(isHovered ? 0.06 : 0)
        .onHover { newHover in
            guard !swapping else { return }
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) { isHovered = newHover }
        }
    }
}

struct PillBadgeView: View {
    let badge: PillBadge
    let taskColor: String

    private var badgeColor: Color {
        switch badge {
        case .approval: return Color(hex: "#F5A524")
        case .finished: return Color(hex: "#22C55E")
        case .error:    return Color(hex: "#F4505E")
        }
    }

    private var icon: String {
        switch badge {
        case .approval: return "exclamationmark"
        case .finished: return "checkmark"
        case .error:    return "xmark"
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(hex: "#0B0C0E"))
                .frame(width: 14, height: 14)
            Circle()
                .fill(badgeColor)
                .frame(width: 12, height: 12)
            Image(systemName: icon)
                .font(.system(size: 6, weight: .bold))
                .foregroundColor(.black)
        }
        .shadow(color: badgeColor.opacity(0.6), radius: 4, x: 0, y: 0)
    }
}

// MARK: - Column agents (right side of non-overview views)

struct ColumnAgentsView: View {
    @ObservedObject var state: AppState

    var others: [AgentTask] {
        state.tasks.filter { $0.id != state.focusId }
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(others.prefix(4).enumerated()), id: \.1.id) { idx, task in
                MiniBotCanvasView(task: task)
                    .frame(width: 16 / 0.6, height: 16 / 0.6)
                    .frame(width: 16, height: 16)
                    .position(x: 0, y: CGFloat(50 + idx * 24))
                    .animation(.spring(response: 0.5, dampingFraction: 0.72).delay(Double(idx) * 0.035), value: idx)
            }
        }
    }
}
