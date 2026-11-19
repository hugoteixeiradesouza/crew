import SwiftUI

// Fila de atenção (cartão da direita na visão geral): as outras sessões, de todos os projetos,
// na ordem do que precisa do Hugo — esperando você, entregou, trabalhando, à espera do próximo
// pedido. Uma linha por sessão, com a cor do projeto, o título e o estado em palavras.
// Paradas viram um contador no título; "nova sessão" é o "+". Semente do gerenciador de
// sessões: a gestão completa vai para a Central; aqui é só a triagem.

struct FilaAtencao: View {
    @ObservedObject var state: AppState

    private var sessoes: [AgentTask] {
        state.tasks.filter { $0.source == .claudeCode && $0.sessionId != nil && $0.id != state.focusId }
    }
    private var paradas: [AgentTask] { sessoes.filter { !$0.ativa } }

    /// Ativas na ordem de urgência; com "paradas" aberto, elas entram no fim.
    private var fila: [AgentTask] {
        let ativas = sessoes.filter(\.ativa).sorted { a, b in
            let pa = prioridade(a), pb = prioridade(b)
            return pa != pb ? pa < pb : a.lastEvent > b.lastEvent
        }
        return ativas + (state.mostrarParadas ? paradas.sorted { $0.lastEvent > $1.lastEvent } : [])
    }

    private func prioridade(_ t: AgentTask) -> Int { Self.prioridade(t, state) }

    /// 0 esperando você · 1 erro · 2 entregou · 3 trabalhando · 4 à espera do próximo pedido.
    static func prioridade(_ t: AgentTask, _ state: AppState) -> Int {
        if let sid = t.sessionId, state.pendingApprovals[sid] != nil { return 0 }
        if t.pillBadge == .approval || t.state == .approval || t.state == .question { return 0 }
        if t.pillBadge == .error || t.state == .error { return 1 }
        if t.pillBadge == .finished || t.state == .finished { return 2 }
        if [.working, .thinking, .searching].contains(t.state) { return 3 }
        return 4
    }

    private var resumo: String {
        let ativas = sessoes.filter(\.ativa)
        let esperando = ativas.filter { prioridade($0) == 0 }.count
        let trabalhando = ativas.filter { prioridade($0) == 3 }.count
        var p: [String] = []
        if esperando > 0 { p.append("\(esperando) esperando") }
        if trabalhando > 0 { p.append("\(trabalhando) trabalhando") }
        if p.isEmpty { p.append(ativas.isEmpty ? "nenhuma outra sessão" : "\(ativas.count) à espera") }
        return p.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("FILA").font(.system(size: 9, weight: .bold)).tracking(0.7)
                    .foregroundColor(Color(hex: "#7C818A"))
                Text(resumo).font(.system(size: 10)).foregroundColor(Color(hex: "#8E939C")).lineLimit(1)
                Spacer(minLength: 4)
                if !paradas.isEmpty {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { state.mostrarParadas.toggle() }
                    } label: {
                        Text(state.mostrarParadas ? "esconder paradas" : "\(paradas.count) paradas")
                            .font(.system(size: 10)).foregroundColor(Color(hex: "#8E939C"))
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    state.openChat(nil)
                    SoundEngine.shared.play("blip")
                } label: {
                    Image(systemName: "plus").font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color(hex: "#B0B5BE"))
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .help("Nova sessão")
            }
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 2) {
                    ForEach(fila) { t in LinhaFila(task: t, state: state, mostrarBranch: branchDistingue(t)) }
                    if fila.isEmpty {
                        Text("Só a sessão em foco por agora.")
                            .font(.system(size: 11)).foregroundColor(Color(hex: "#5F646D"))
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 8).padding(.bottom, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Branch só aparece quando distingue: outra sessão do mesmo projeto na fila está em outra branch.
    private func branchDistingue(_ t: AgentTask) -> Bool {
        let k = Projetos.chave(t)
        let irmas = fila.filter { Projetos.chave($0) == k }
        return irmas.count > 1 && Set(irmas.map { Projetos.branch(de: $0.sessionCwd) }).count > 1
    }
}

/// Uma linha da fila: sinal do estado, projeto (cor), título e o estado em palavras.
struct LinhaFila: View {
    let task: AgentTask
    @ObservedObject var state: AppState
    let mostrarBranch: Bool
    @State private var sobre = false

    private var pendencia: ApprovalInfo? { task.sessionId.flatMap { state.pendingApprovals[$0] } }

    private var sinal: (icone: String, cor: String) {
        if pendencia != nil || task.state == .approval || task.pillBadge == .approval {
            return (pendencia?.questions.isEmpty == false || task.state == .question
                    ? "questionmark.circle.fill" : "hand.raised.fill", "#F5A524")
        }
        if task.state == .question { return ("questionmark.circle.fill", "#F5A524") }
        if task.pillBadge == .error || task.state == .error { return ("exclamationmark.triangle.fill", "#F4505E") }
        if task.pillBadge == .finished || task.state == .finished { return ("checkmark.circle.fill", "#34D399") }
        if [.working, .thinking, .searching].contains(task.state) { return ("ellipsis.circle.fill", "#3B9EFF") }
        if task.state == .ratelimit { return ("hourglass.circle.fill", "#F59E0B") }
        return ("moon.circle.fill", "#5F646D")
    }

    private var estado: String {
        let ha = Self.tempo(desde: task.lastEvent)
        if let p = pendencia {
            if !p.questions.isEmpty { return "tem uma pergunta · \(ha)" }
            if p.plan != nil { return "quer aprovar o plano · \(ha)" }
            return "quer rodar \(p.tool) · \(ha)"
        }
        if !task.ativa { return "parada · \(ha)" }
        switch task.state {
        case .approval: return "pede permissão · \(ha)"
        case .question: return "tem uma pergunta · \(ha)"
        case .error: return "parou com erro · \(ha)"
        case .finished: return "entregou · \(ha)"
        case .ratelimit: return "limite de uso"
        case .working, .thinking, .searching:
            let passo = task.steps.indices.contains(task.stepIndex) ? task.steps[task.stepIndex] : task.stateLabel
            return passo
        default:
            return task.pillBadge == .finished ? "entregou · \(ha)" : "esperando você · \(ha)"
        }
    }

    private var projeto: String {
        let nome = Projetos.nome(de: task.sessionCwd) ?? task.name
        guard mostrarBranch, let b = Projetos.branch(de: task.sessionCwd) else { return nome }
        return "\(nome) · \(b)"
    }

    var body: some View {
        Button(action: abrir) {
            HStack(spacing: 6) {
                Image(systemName: sinal.icone).font(.system(size: 11)).foregroundColor(Color(hex: sinal.cor))
                    .frame(width: 13)
                // O estado é a informação principal: aparece inteiro; quem encurta é o título
                Text(projeto).font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color(hex: task.color).opacity(0.9)).lineLimit(1)
                    .frame(maxWidth: 90, alignment: .leading).fixedSize(horizontal: true, vertical: false)
                Text(task.displayTitle).font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(Color(hex: "#E8E9EC")).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 4)
                Text(estado).font(.system(size: 10.5)).foregroundColor(Color(hex: "#9398A1"))
                    .lineLimit(1).truncationMode(.middle)
                    .layoutPriority(1)
            }
            .padding(.horizontal, 6).frame(height: 20)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(sobre ? 0.07 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(task.ativa ? 1 : 0.55)
        .onHover { sobre = $0 }
        .help([task.displayTitle, Projetos.branch(de: task.sessionCwd).map { "branch \($0)" }, task.brief]
                .compactMap { $0 }.joined(separator: "\n"))
        .contextMenu {
            if task.ativa {
                Button("Ocultar sessão") { state.ocultar(task.id) }
            } else {
                Button("Mostrar sessão") { state.mostrar(task.id) }
            }
            SessaoMenuFim(state: state, task: task)
        }
    }

    /// Mesmo que a pílula fazia: foco na sessão; com pendência, abre direto nela.
    private func abrir() {
        state.setFocus(task.id)
        if let p = pendencia { state.view = p.questions.isEmpty ? .approval : .question }
        SoundEngine.shared.play("blip")
    }

    static func tempo(desde d: Date) -> String {
        let s = Int(Date().timeIntervalSince(d))
        if s < 60 { return "agora" }
        if s < 3600 { return "\(s / 60) min" }
        if s < 86400 { return "\(s / 3600) h" }
        return "\(s / 86400) d"
    }
}

/// Selo da fila no cartão da sessão em foco: quantas outras sessões precisam de você (laranja)
/// ou estão trabalhando (azul). Clique leva à próxima mais urgente.
struct SeloFila: View {
    @ObservedObject var state: AppState
    @State private var sobre = false

    private var outras: [AgentTask] {
        state.tasks.filter { $0.source == .claudeCode && $0.sessionId != nil && $0.id != state.focusId && $0.ativa }
    }

    /// Resumo calculado uma vez: ordem por urgência e as contagens.
    private struct Resumo {
        var ordem: [AgentTask] = []
        var esperando = 0, entregou = 0, trabalhando = 0
        var numero: Int { esperando > 0 ? esperando : entregou > 0 ? entregou : trabalhando }
        var cor: String { esperando > 0 ? "#F5A524" : entregou > 0 ? "#34D399" : "#3B9EFF" }
        var texto: String {
            esperando > 0 ? "\(esperando) esperando você" : entregou > 0 ? "\(entregou) entregou" : "\(trabalhando) trabalhando"
        }
    }

    private var resumo: Resumo {
        var r = Resumo()
        let st = state
        r.ordem = outras.sorted { a, b in
            let pa = FilaAtencao.prioridade(a, st), pb = FilaAtencao.prioridade(b, st)
            return pa != pb ? pa < pb : a.lastEvent > b.lastEvent
        }
        for t in r.ordem {
            switch FilaAtencao.prioridade(t, st) {
            case 0, 1: r.esperando += 1
            case 2: r.entregou += 1
            case 3: r.trabalhando += 1
            default: break
            }
        }
        return r
    }

    private func ir(_ t: AgentTask) {
        state.setFocus(t.id)
        if let sid = t.sessionId, let p = state.pendingApprovals[sid] {
            state.view = p.questions.isEmpty ? .approval : .question
        }
        SoundEngine.shared.play("blip")
    }

    var body: some View {
        let r = resumo
        if let prox = r.ordem.first, r.numero > 0 {
            let lista: String = r.ordem.prefix(5).map { "• " + $0.displayTitle }.joined(separator: "\n")
            let dica: String = r.texto + " — ir para: " + prox.displayTitle + "\n" + lista
            Button { ir(prox) } label: {
                HStack(spacing: 4) {
                    Circle().fill(Color(hex: r.cor)).frame(width: 6, height: 6)
                    Text("\(r.numero)").font(.system(size: 10, weight: .semibold)).foregroundColor(Color(hex: "#C9CDD3"))
                    Image(systemName: "chevron.right").font(.system(size: 7, weight: .bold)).foregroundColor(Color(hex: "#7C818A"))
                }
                .padding(.horizontal, 7).frame(height: 18)
                .background(Capsule().fill(Color.white.opacity(sobre ? 0.12 : 0.07)))
            }
            .buttonStyle(.plain)
            .onHover { sobre = $0 }
            .help(dica)
        }
    }
}
