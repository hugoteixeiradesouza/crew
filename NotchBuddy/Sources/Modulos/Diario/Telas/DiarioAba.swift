import SwiftUI

// Aba Tasks na ilha (≈600×98, Homie à esquerda): a mesma tela da expandida em tamanho pequeno —
// segmentos (Pendências · Hoje · Resumo), "Anotar…" e expandir no topo; embaixo, duas linhas do
// segmento escolhido. Rolar para baixo (ou o botão) abre a expandida.
// Nada a assinar: tudo vem do serviço, que só muda por evento.

struct DiarioAba: View {
    @ObservedObject private var ilha = AppState.shared

    var body: some View {
        if ilha.alturaAba != nil {
            DiarioExpandido().transition(.opacity)
        } else {
            DiarioAbaResumo().transition(.opacity)
        }
    }
}

struct DiarioAbaResumo: View {
    /// Distância do topo do cartão até os segmentos — igual na aba normal e na expandida.
    static let topo: CGFloat = 10
    private let s = DiarioServico.shared

    private let cinza = Color(hex: "#8E939C")
    private let apagado = Color(hex: "#5F646D")

    var body: some View {
        ZStack {
            CardBackground(wash: nil)
            Group {
                if let id = s.detalhe, let p = s.pendencias.first(where: { $0.id == id }) {
                    DetalhePendencia(p: p) { withAnimation(.easeOut(duration: 0.15)) { s.detalhe = nil } }
                } else {
                    VStack(alignment: .leading, spacing: 7) {
                        TopoTasks(expandido: false)
                        conteudo.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.leading, 108)
            .padding(.trailing, 14)
            .padding(.top, Self.topo)
        }
        .foregroundColor(DiarioExpandido.claro)
        .onAppear { s.abaVista() }
    }

    // MARK: Duas linhas do segmento escolhido (o resto, rolando para baixo)

    @ViewBuilder private var conteudo: some View {
        switch s.segmento {
        case .pendencias: pendencias
        case .hoje: hoje
        case .resumo: resumo
        }
    }

    private var pendencias: some View {
        let abertas = Array(s.abertas)
        return VStack(alignment: .leading, spacing: 4) {
            if abertas.isEmpty {
                vazio("Nenhuma pendência aberta. O que você anotar com prazo, ou prometer, aparece aqui.")
            }
            ForEach(abertas.prefix(2)) { p in
                LinhaPendencia(p: p, destaque: p.id == s.destaque) {
                    withAnimation(.easeOut(duration: 0.15)) { s.detalhe = p.id }
                }
            }
            mais(abertas.count - 2, .pendencias)
        }
    }

    private var hoje: some View {
        let todas = s.hoje.entradas
        return VStack(alignment: .leading, spacing: 4) {
            if todas.isEmpty {
                vazio("Nada hoje ainda. O que você anotar e o que as sessões entregarem aparece aqui.")
            }
            ForEach(Array(todas.suffix(2).reversed())) { e in linhaEntrada(e) }
            mais(todas.count - 2, .hoje)
        }
    }

    private var resumo: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let r = s.hoje.resumo {
                linhaResumo("FEITO", "#34D399", r.feito)
                linhaResumo("ABERTO", "#F5A524", r.aberto)
            } else {
                Button {
                    s.expandir(.resumo)
                    Task { await s.resumir() }
                } label: {
                    HStack(spacing: 4) {
                        if s.resumindo { ProgressView().controlSize(.mini) }
                        else { Image(systemName: "sparkles").font(.system(size: 10, weight: .semibold)) }
                        Text(s.resumindo ? "Resumindo…" : "Resumir o dia").font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(Color(hex: "#0B0C0E"))
                    .padding(.horizontal, 10).frame(height: 22)
                    .background(Capsule().fill(Color(hex: "#F5F6F8")))
                }
                .buttonStyle(.plain)
                .disabled(s.resumindo)
                .help("Feito, aberto e prometido do dia, com o modelo local do Mac.")
            }
        }
    }

    private func linhaResumo(_ titulo: String, _ cor: String, _ itens: [String]) -> some View {
        HStack(spacing: 6) {
            Text(titulo).font(.system(size: 9, weight: .semibold)).tracking(0.5).foregroundColor(Color(hex: cor))
                .frame(width: 46, alignment: .leading)
            Text(itens.isEmpty ? "Nada." : itens.joined(separator: " · "))
                .font(.system(size: 11.5)).foregroundColor(itens.isEmpty ? apagado : Color(hex: "#DADDE2"))
                .lineLimit(1).truncationMode(.tail)
        }
        .contentShape(Rectangle())
        .onTapGesture { s.expandir(.resumo) }
    }

    /// "+N" discreto: o que não coube; clique (ou rolar para baixo) abre tudo.
    @ViewBuilder private func mais(_ n: Int, _ seg: DiarioServico.Segmento) -> some View {
        if n > 0 {
            Text("+\(n) — role para baixo para ver tudo")
                .font(.system(size: 10)).foregroundColor(apagado)
                .contentShape(Rectangle())
                .onTapGesture { s.expandir(seg) }
        }
    }

    private func vazio(_ t: String) -> some View {
        Text(t).font(.system(size: 11)).foregroundColor(apagado).lineLimit(2)
    }

    private func linhaEntrada(_ e: EntradaDiario) -> some View {
        HStack(spacing: 6) {
            Image(systemName: e.tipo.icone)
                .font(.system(size: 8.5, weight: .bold))
                .foregroundColor(Color(hex: "#0B0C0E"))
                .frame(width: 15, height: 15)
                .background(Circle().fill(Color(hex: e.cor ?? (e.tipo == .nota ? "#DADDE2" : "#8E939C"))))
            Text(FormatoDiario.hora(e.hora)).font(.system(size: 10.5)).foregroundColor(cinza).monospacedDigit()
            Text(e.texto.replacingOccurrences(of: "\n", with: " "))
                .font(.system(size: 11.5)).foregroundColor(Color(hex: "#DADDE2"))
                .lineLimit(1).truncationMode(.tail)
        }
        .contentShape(Rectangle())
        .onTapGesture { s.expandir(.hoje, entrada: e.id) }
        .help("Abrir: texto inteiro, editar, virar pendência")
    }
}

struct LinhaPendencia: View {
    let p: Pendencia
    var destaque = false
    var claro = false   // Central (fundo claro do sistema)
    /// Toque no texto: abre o detalhe (entender, editar, mudar o prazo).
    var aoAbrir: (() -> Void)? = nil
    private let s = DiarioServico.shared

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icone)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(cor))
            VStack(alignment: .leading, spacing: 0) {
                TituloRenomeavel(texto: p.acao, tamanho: claro ? 13 : 12,
                                 cor: claro ? .primary : Color(hex: destaque ? "#FFFFFF" : "#ECEDEF")) { s.editar(p.id, acao: $0) }
                // Embaixo: do que se trata; de onde veio e quando entrou ficam em etiquetas discretas
                HStack(spacing: 5) {
                    Text(legenda)
                        .font(.system(size: claro ? 11 : 10.5))
                        .foregroundColor(claro ? .secondary : Color(hex: vencida ? "#F4818B" : "#9398A1"))
                        .lineLimit(1).truncationMode(.tail)
                        .layoutPriority(1)
                    ForEach(etiquetas, id: \.self) { etiqueta($0) }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { aoAbrir?() }
            .help(aoAbrir == nil ? "\(p.acao)\n\(DiarioServico.deOnde(p)): \"\(p.textoOrigem)\"" : "Abrir: ver de onde veio, editar, mudar o prazo")
            Spacer(minLength: 4)
            botao("checkmark", "Feito") { s.feito(p.id) }
            Menu {
                ForEach(DiarioServico.Adiamento.allCases) { a in
                    Button(a.rawValue) { s.adiar(p.id, a) }
                }
            } label: {
                Image(systemName: "clock.arrow.circlepath").font(.system(size: 10, weight: .semibold))
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
            .foregroundColor(claro ? .primary : Color(hex: "#DADDE2"))
            .frame(width: 22, height: 22)
            .background(Circle().fill(claro ? Color.primary.opacity(0.08) : Color.white.opacity(0.09)))
            .help("Adiar: 30 min, 1 h ou amanhã")
            botao("xmark", "Ignorar") { s.ignorar(p.id) }
        }
        .padding(.vertical, destaque && !claro ? 1 : 0)
    }

    private func botao(_ img: String, _ ajuda: String, _ acao: @escaping () -> Void) -> some View {
        Button(action: acao) {
            Image(systemName: img).font(.system(size: 10, weight: .semibold))
                .foregroundColor(claro ? .primary : Color(hex: "#DADDE2"))
                .frame(width: 22, height: 22)
                .background(Circle().fill(claro ? Color.primary.opacity(0.08) : Color.white.opacity(0.09)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(ajuda)
    }

    private var vencida: Bool { (p.prazo.map { $0 <= Date() } ?? false) && p.estado == .aberta }

    private var cor: Color {
        if vencida || p.urgencia == .agora { return Color(hex: "#F4505E") }
        if p.estado == .adiada { return Color(hex: "#6B7280") }
        if p.origem == .whatsapp, p.urgencia != .hoje { return Color(hex: "#25D366") }
        switch p.urgencia {
        case .hoje: return Color(hex: "#F5A524")
        default: return Color(hex: "#3B82F6")
        }
    }

    private var icone: String {
        switch p.origem {
        case .nota: return "pencil"
        case .pedido: return "text.bubble"
        case .entrega: return "hourglass"
        case .whatsapp: return "message.fill"
        }
    }

    /// O assunto; sem assunto (pendências antigas), o prazo. Vencida/adiada sempre aparecem.
    private var legenda: String {
        if p.estado == .adiada, let a = p.adiadaAte { return "adiada até \(FormatoDiario.quando(a))" + (p.assunto.map { " · \($0)" } ?? "") }
        if vencida, let pz = p.prazo { return "venceu \(FormatoDiario.quando(pz))" + (p.assunto.map { " · \($0)" } ?? "") }
        if let a = p.assunto { return a }
        if let pz = p.prazo { return "até \(FormatoDiario.quando(pz))" }
        return p.urgencia == .semPressa ? "sem pressa" : p.urgencia.nome
    }

    /// Etiquetas secundárias: a origem (com quem / qual sessão) e a hora em que entrou.
    private var etiquetas: [String] {
        var e: [String] = []
        switch p.origem {
        case .whatsapp: e.append(p.pessoa.flatMap { $0.split(separator: " ").first.map(String.init) } ?? p.sessao ?? "WhatsApp")
        case .nota: e.append("nota")
        case .pedido, .entrega: e.append(p.sessao ?? p.projeto ?? "sessão")
        }
        // Prazo que não está no título nem na legenda vira etiqueta também
        if p.assunto != nil, !vencida, p.estado != .adiada, let pz = p.prazo,
           p.acao.range(of: #"\d"#, options: .regularExpression) == nil {
            e.append("até \(FormatoDiario.quando(pz))")
        }
        e.append(FormatoDiario.hora(p.criadaEm))
        return e
    }

    private func etiqueta(_ t: String) -> some View {
        HStack(spacing: 3) {
            if t == etiquetas.first {
                Image(systemName: icone).font(.system(size: 7, weight: .bold))
            }
            Text(t).font(.system(size: 9, weight: .medium)).lineLimit(1)
        }
        .foregroundColor(claro ? .secondary : Color(hex: "#7C818A"))
        .padding(.horizontal, 5).frame(height: 14)
        .background(Capsule().fill(claro ? Color.primary.opacity(0.06) : Color.white.opacity(0.06)))
        .fixedSize()
    }
}

/// Detalhe de uma pendência na aba: de onde veio (o texto inteiro), a ação editável, o prazo
/// (trocar em um clique) e as saídas. "Abrir a sessão" quando veio de uma sessão.
struct DetalhePendencia: View {
    let p: Pendencia
    let voltar: () -> Void
    private let s = DiarioServico.shared
    @State private var acao = ""
    @FocusState private var editando: Bool
    @State private var contando = ""
    @FocusState private var focoContando: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Button(action: voltar) {
                    Image(systemName: "chevron.left").font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color(hex: "#DADDE2")).frame(width: 20, height: 20)
                        .background(Circle().fill(Color.white.opacity(0.09)))
                }
                .buttonStyle(.plain).help("Voltar")
                TextField("O que fazer", text: $acao)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(Color(hex: "#F1F2F4"))
                    .focused($editando)
                    .onSubmit { s.editar(p.id, acao: acao) }
                    .onChange(of: editando) { _, foco in if !foco { s.editar(p.id, acao: acao) } }
                    .simultaneousGesture(TapGesture().onEnded {
                        NSApp.windows.first { $0 is IslandPanel }?.makeKey()
                        editando = true
                    })
                    .help("Clique para editar; Enter salva")
                Spacer(minLength: 4)
                if let sid = p.sessaoId, let t = AppState.shared.tasks.first(where: { $0.sessionId == sid }) {
                    pilula("Abrir sessão", "bubble.left") { AppState.shared.openChat(t.id) }
                }
                circulo("checkmark", "Feito") { s.feito(p.id); voltar() }
                circulo("xmark", "Ignorar") { s.ignorar(p.id); voltar() }
            }
            Text("\(DiarioServico.deOnde(p)): \u{201C}\(p.textoOrigem)\u{201D}")
                .font(.system(size: 10.5)).foregroundColor(Color(hex: "#9398A1"))
                .lineLimit(1).truncationMode(.tail)
                .help(p.textoOrigem)
            atualizacao
            HStack(spacing: 5) {
                Image(systemName: "clock").font(.system(size: 10)).foregroundColor(Color(hex: "#8E939C"))
                Text(p.prazo.map { FormatoDiario.quando($0) } ?? "sem prazo")
                    .font(.system(size: 10.5, weight: .medium)).foregroundColor(Color(hex: "#DADDE2"))
                    .lineLimit(1).fixedSize()
                    .padding(.trailing, 2)
                chip("+1 h") { s.editar(p.id, prazo: .some(Date().addingTimeInterval(3600))) }
                chip("18h") { s.editar(p.id, prazo: .some(hojeAs(18))) }
                chip("amanhã 9h") { s.editar(p.id, prazo: .some(amanhaAs(9))) }
                if p.prazo != nil { chip("tirar prazo") { s.editar(p.id, prazo: .some(nil)) } }
            }
        }
        .onAppear { acao = p.acao }
        .onChange(of: p.id) { _, _ in acao = p.acao }
    }

    /// "O que aconteceu?": conta em uma frase e o Homie atualiza a task (e abre as novas).
    @ViewBuilder private var atualizacao: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles").font(.system(size: 10, weight: .semibold)).foregroundColor(Color(hex: "#A78BFA"))
            if s.atualizando.contains(p.id) {
                ProgressView().controlSize(.mini)
                Text("O Homie está atualizando…").font(.system(size: 11)).foregroundColor(Color(hex: "#9398A1"))
            } else if let r = s.resultadoAtualizacao[p.id] {
                Text(r).font(.system(size: 11, weight: .medium)).foregroundColor(Color(hex: "#C4B5FD"))
                    .lineLimit(1).truncationMode(.tail)
            } else {
                TextField("O que aconteceu? Conte e o Homie atualiza a task", text: $contando)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5))
                    .foregroundColor(Color(hex: "#F1F2F4"))
                    .focused($focoContando)
                    .onSubmit {
                        s.atualizar(p.id, contando: contando)
                        contando = ""
                    }
                    .simultaneousGesture(TapGesture().onEnded {
                        NSApp.windows.first { $0 is IslandPanel }?.makeKey()
                        focoContando = true
                    })
            }
        }
        .padding(.horizontal, 8).frame(height: 22)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color(hex: "#A78BFA").opacity(0.10)))
        .onChange(of: s.resultadoAtualizacao[p.id]) { _, r in
            guard r != nil else { return }
            // Mostra o que mudou e, se a task saiu da lista, volta sozinho
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                s.resultadoAtualizacao[p.id] = nil
                if s.pendencias.first(where: { $0.id == p.id })?.aberta != true { voltar() }
            }
        }
    }

    private func hojeAs(_ h: Int) -> Date {
        Calendar.current.date(bySettingHour: h, minute: 0, second: 0, of: Date()) ?? Date()
    }
    private func amanhaAs(_ h: Int) -> Date {
        let d = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return Calendar.current.date(bySettingHour: h, minute: 0, second: 0, of: d) ?? d
    }

    private func chip(_ t: String, _ acao: @escaping () -> Void) -> some View {
        Button(action: acao) {
            Text(t).font(.system(size: 10)).foregroundColor(Color(hex: "#C9CDD3"))
                .padding(.horizontal, 7).frame(height: 18)
                .background(Capsule().fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }

    private func circulo(_ img: String, _ ajuda: String, _ acao: @escaping () -> Void) -> some View {
        Button(action: acao) {
            Image(systemName: img).font(.system(size: 10, weight: .semibold))
                .foregroundColor(Color(hex: "#DADDE2")).frame(width: 22, height: 22)
                .background(Circle().fill(Color.white.opacity(0.09)))
        }
        .buttonStyle(.plain).help(ajuda)
    }

    private func pilula(_ t: String, _ img: String, _ acao: @escaping () -> Void) -> some View {
        Button(action: acao) {
            HStack(spacing: 4) {
                Image(systemName: img).font(.system(size: 9.5, weight: .semibold))
                Text(t).font(.system(size: 10.5, weight: .medium))
            }
            .foregroundColor(Color(hex: "#DADDE2")).padding(.horizontal, 8).frame(height: 22)
            .background(Capsule().fill(Color.white.opacity(0.09)))
        }
        .buttonStyle(.plain)
    }
}
