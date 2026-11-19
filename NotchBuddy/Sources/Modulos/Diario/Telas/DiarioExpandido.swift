import SwiftUI

// As Tasks inteiras na ilha expandida (botão do canto da aba; a ilha cresce como no monitor do
// Sistema). Três segmentos:
//   • Pendências — todas as abertas e adiadas (detalhe, editar, prazo, feito/adiar/ignorar) e as
//     resolvidas de hoje com "reabrir";
//   • Hoje — a linha do tempo completa, filtrável; clicar numa entrada mostra o texto inteiro;
//     nota: editar e apagar; qualquer entrada: virar pendência com prazo em um clique;
//   • Resumo — o resumo do dia e "gerar de novo".
// "Anotar…" no topo. Recolher volta à aba normal; fechar a ilha ou trocar de aba recolhe sozinho.

/// Topo comum às duas alturas da aba: segmentos com contagem, "Anotar…" e expandir/recolher.
/// A aba normal e a expandida são a mesma tela em dois tamanhos.
struct TopoTasks: View {
    let expandido: Bool
    private let s = DiarioServico.shared
    @State private var texto = ""
    @FocusState private var anotando: Bool

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                ForEach(DiarioServico.Segmento.allCases) { seg in
                    Button { withAnimation(.easeOut(duration: 0.12)) { s.segmento = seg; s.detalhe = nil } } label: {
                        Text(rotulo(seg))
                            .font(.system(size: 11.5, weight: s.segmento == seg ? .semibold : .regular))
                            .foregroundColor(s.segmento == seg ? Color(hex: "#0B0C0E") : DiarioExpandido.cinza)
                            .padding(.horizontal, 9).frame(height: 22)
                            .background(s.segmento == seg ? Color(hex: "#F5F6F8") : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .contentShape(Rectangle())
                            .fixedSize()
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
            .background(DiarioExpandido.campo)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            // O Homie tem sugestões esperando o Sim/Não do Hugo
            if !s.sugeridas.isEmpty {
                Button { s.perguntar() } label: {
                    Text("\(s.sugeridas.count) a confirmar")
                        .font(.system(size: 11, weight: .semibold)).foregroundColor(Color(hex: "#C4B5FD"))
                        .padding(.horizontal, 8).frame(height: 24)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color(hex: "#A78BFA").opacity(0.16)))
                        .fixedSize()
                }
                .buttonStyle(.plain)
                .help("O Homie acha que isso pode virar task — responder agora")
            }
            HStack(spacing: 6) {
                Image(systemName: "square.and.pencil").font(.system(size: 11, weight: .medium)).foregroundColor(DiarioExpandido.cinza)
                TextField("Anotar…", text: $texto)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(DiarioExpandido.claro)
                    .focused($anotando)
                    .onSubmit(salvarNota)
                if s.triando > 0 { ProgressView().controlSize(.mini).help("Triando com o modelo local…") }
            }
            .padding(.horizontal, 9).frame(height: 26)
            .background(DiarioExpandido.campo)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded {
                // A ilha não vira janela-chave sozinha fora do chat: o campo precisa dela para digitar
                NSApp.windows.first { $0 is IslandPanel }?.makeKey()
                anotando = true
            })

            // Expandir/recolher é só rolar (elástico da ilha), sem botão
        }
    }

    private func rotulo(_ seg: DiarioServico.Segmento) -> String {
        switch seg {
        case .pendencias: return "Pendências \(s.abertas.count)"
        case .hoje: return "Hoje \(s.hoje.entradas.count)"
        case .resumo: return "Resumo"
        }
    }

    private func salvarNota() {
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        s.adicionarNota(t)
        texto = ""
    }
}

struct DiarioExpandido: View {
    private let s = DiarioServico.shared
    @State private var filtro: TipoEntrada?
    @State private var verResolvidas = false

    static let cinza = Color(hex: "#8E939C")
    static let apagado = Color(hex: "#5F646D")
    static let claro = Color(hex: "#F1F2F4")
    static let campo = Color.white.opacity(0.07)

    /// O mesmo cartão da aba normal, crescendo para baixo: Homie e topo no mesmo lugar.
    var body: some View {
        ZStack {
            CardBackground(wash: nil)
            VStack(alignment: .leading, spacing: 8) {
                TopoTasks(expandido: true)
                Group {
                    switch s.segmento {
                    case .pendencias: pendencias
                    case .hoje: hoje
                    case .resumo: resumo
                    }
                }
                .padding(.leading, -8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(.leading, 108).padding(.trailing, 14).padding(.top, DiarioAbaResumo.topo)
        }
        .foregroundColor(Self.claro)
        .onAppear { s.abaVista() }
    }

    // MARK: Pendências

    private var pendencias: some View {
        let abertas = s.abertas
        let resolvidas = s.hoje.pendencias.filter { !$0.aberta }
            .sorted { ($0.resolvidaEm ?? $0.criadaEm) > ($1.resolvidaEm ?? $1.criadaEm) }
        return ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 6) {
                if abertas.isEmpty {
                    vazio("Nenhuma pendência aberta. O que você anotar com prazo, ou prometer, aparece aqui.")
                }
                ForEach(abertas) { p in
                    if s.detalhe == p.id {
                        DetalhePendencia(p: p) { withAnimation(.easeOut(duration: 0.15)) { s.detalhe = nil } }
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.06)))
                    } else {
                        LinhaPendencia(p: p, destaque: p.id == s.destaque) {
                            withAnimation(.easeOut(duration: 0.15)) { s.detalhe = p.id }
                        }
                        .padding(.horizontal, 8)
                    }
                }
                if !resolvidas.isEmpty {
                    Button { withAnimation(.easeOut(duration: 0.15)) { verResolvidas.toggle() } } label: {
                        HStack(spacing: 4) {
                            Image(systemName: verResolvidas ? "chevron.down" : "chevron.right").font(.system(size: 9, weight: .bold))
                            Text("Resolvidas hoje (\(resolvidas.count))").font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(Self.cinza)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4).padding(.horizontal, 8)
                    if verResolvidas {
                        ForEach(resolvidas) { p in linhaResolvida(p) }
                    }
                }
            }
            .padding(.bottom, 6)
        }
        .rolagemDaIlha()
    }

    private func linhaResolvida(_ p: Pendencia) -> some View {
        HStack(spacing: 7) {
            Image(systemName: p.estado == .feita ? "checkmark" : "minus")
                .font(.system(size: 9.5, weight: .bold))
                .foregroundColor(p.estado == .feita ? Color(hex: "#0B0C0E") : Self.cinza)
                .frame(width: 22, height: 22)
                .background(Circle().fill(p.estado == .feita ? Color(hex: "#34D399") : Color.white.opacity(0.08)))
            VStack(alignment: .leading, spacing: 0) {
                Text(p.acao).font(.system(size: 12)).foregroundColor(Self.cinza)
                    .strikethrough(p.estado == .feita).lineLimit(1)
                Text([p.estado == .feita ? "feito" : "ignorado",
                      p.resolvidaEm.map { "às \(FormatoDiario.hora($0))" }, p.motivo]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 10)).foregroundColor(Self.apagado).lineLimit(1)
            }
            Spacer(minLength: 4)
            pilula("Reabrir", "arrow.uturn.backward") { s.reabrir(p.id) }
        }
        .padding(.horizontal, 8)
    }

    // MARK: Hoje (linha do tempo)

    private var hoje: some View {
        let tipos = TipoEntrada.allCases.filter { s.hoje.contagem($0) > 0 }
        let entradas = s.hoje.entradas.filter { filtro == nil || $0.tipo == filtro }.sorted { $0.hora > $1.hora }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                chipFiltro(nil, "Tudo \(s.hoje.entradas.count)")
                ForEach(tipos) { t in chipFiltro(t, "\(t.nome) \(s.hoje.contagem(t))") }
            }
            .padding(.horizontal, 8)
            ScrollViewReader { leitor in
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        if entradas.isEmpty { vazio("Nada aqui ainda.") }
                        ForEach(entradas) { e in
                            LinhaEntradaExpandida(e: e, aberta: s.entradaAberta == e.id) {
                                withAnimation(.easeOut(duration: 0.15)) {
                                    s.entradaAberta = s.entradaAberta == e.id ? nil : e.id
                                }
                            }
                            .id(e.id)
                        }
                    }
                    .padding(.bottom, 6)
                }
        .rolagemDaIlha()
                .onAppear {
                    if let id = s.entradaAberta {
                        DispatchQueue.main.async { leitor.scrollTo(id, anchor: .center) }
                    }
                }
            }
        }
    }

    private func chipFiltro(_ t: TipoEntrada?, _ texto: String) -> some View {
        Button { filtro = t } label: {
            Text(texto)
                .font(.system(size: 10.5, weight: filtro == t ? .semibold : .regular))
                .foregroundColor(filtro == t ? Color(hex: "#0B0C0E") : Color(hex: "#C9CDD3"))
                .padding(.horizontal, 8).frame(height: 20)
                .background(Capsule().fill(filtro == t ? Color(hex: "#F5F6F8") : Color.white.opacity(0.08)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: Resumo

    private var resumo: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(s.hoje.resumo.map { r in
                        "Gerado às \(FormatoDiario.hora(r.geradoEm)) \(r.comIA ? "com o modelo local do Mac" : "sem IA")"
                    } ?? "Ainda sem resumo hoje.")
                    .font(.system(size: 11)).foregroundColor(Self.cinza)
                    Spacer()
                    Button { Task { await s.resumir() } } label: {
                        HStack(spacing: 4) {
                            if s.resumindo { ProgressView().controlSize(.mini) }
                            else { Image(systemName: "arrow.clockwise").font(.system(size: 10, weight: .semibold)) }
                            Text(s.resumindo ? "Resumindo…" : (s.hoje.resumo == nil ? "Resumir o dia" : "Gerar de novo"))
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(Color(hex: "#0B0C0E"))
                        .padding(.horizontal, 10).frame(height: 22)
                        .background(Capsule().fill(Color(hex: "#F5F6F8")))
                    }
                    .buttonStyle(.plain)
                    .disabled(s.resumindo)
                }
                if let r = s.hoje.resumo {
                    bloco("FEITO", "#34D399", r.feito)
                    bloco("ABERTO", "#F5A524", r.aberto)
                    bloco("PROMETIDO", "#60A5FA", r.prometido)
                }
            }
            .padding(.horizontal, 8).padding(.bottom, 6)
        }
        .rolagemDaIlha()
    }

    private func bloco(_ titulo: String, _ cor: String, _ itens: [String]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(titulo).font(.system(size: 9.5, weight: .semibold)).tracking(0.6).foregroundColor(Color(hex: cor))
            if itens.isEmpty { Text("Nada.").font(.system(size: 11.5)).foregroundColor(Self.apagado) }
            ForEach(Array(itens.enumerated()), id: \.offset) { _, t in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Circle().fill(Color(hex: cor).opacity(0.8)).frame(width: 4, height: 4).offset(y: -2)
                    Text(t).font(.system(size: 12)).foregroundColor(Color(hex: "#DADDE2"))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Peças

    private func vazio(_ t: String) -> some View {
        Text(t).font(.system(size: 11.5)).foregroundColor(Self.apagado).padding(.horizontal, 8).padding(.top, 6)
    }

    private func pilula(_ t: String, _ img: String, _ acao: @escaping () -> Void) -> some View {
        DiarioExpandido.pilula(t, img, acao)
    }

    static func pilula(_ t: String, _ img: String, destrutivo: Bool = false, _ acao: @escaping () -> Void) -> some View {
        Button(action: acao) {
            HStack(spacing: 4) {
                Image(systemName: img).font(.system(size: 9.5, weight: .semibold))
                Text(t).font(.system(size: 10.5, weight: .medium))
            }
            .foregroundColor(destrutivo ? Color(hex: "#F4505E") : Color(hex: "#DADDE2"))
            .padding(.horizontal, 8).frame(height: 22)
            .background(Capsule().fill(Color.white.opacity(0.09)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Uma entrada da linha do tempo. Fechada: hora, ícone e uma linha. Aberta: o texto inteiro, de
/// onde veio e as ações (nota: editar/apagar; qualquer uma: virar pendência com prazo).
struct LinhaEntradaExpandida: View {
    let e: EntradaDiario
    let aberta: Bool
    let alternar: () -> Void
    private let s = DiarioServico.shared
    @State private var editando = false
    @State private var rascunho = ""
    @State private var confirmarApagar = false
    @FocusState private var focoEdicao: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 7) {
                Text(FormatoDiario.hora(e.hora)).font(.system(size: 10.5)).foregroundColor(DiarioExpandido.cinza)
                    .monospacedDigit().frame(width: 34, alignment: .leading).padding(.top, 2)
                Image(systemName: e.tipo.icone)
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundColor(Color(hex: "#0B0C0E"))
                    .frame(width: 17, height: 17)
                    .background(Circle().fill(Color(hex: e.cor ?? (e.tipo == .nota ? "#DADDE2" : "#8E939C"))))
                VStack(alignment: .leading, spacing: 2) {
                    if editando {
                        TextField("Nota", text: $rascunho, axis: .vertical)
                            .textFieldStyle(.plain).font(.system(size: 12))
                            .lineLimit(1...5)
                            .focused($focoEdicao)
                            .onSubmit(salvarEdicao)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)))
                    } else {
                        Text(aberta ? e.texto : e.texto.replacingOccurrences(of: "\n", with: " "))
                            .font(.system(size: 12)).foregroundColor(Color(hex: "#DADDE2"))
                            .lineLimit(aberta ? nil : 1).truncationMode(.tail)
                            .fixedSize(horizontal: false, vertical: aberta)
                            .textSelection(.enabled)
                    }
                    if aberta, e.projeto != nil || e.sessao != nil {
                        Text([e.projeto, e.sessao].compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 10)).foregroundColor(DiarioExpandido.cinza)
                    }
                }
                Spacer(minLength: 0)
                if !aberta, s.pendencia(daEntrada: e.id) != nil {
                    Image(systemName: "pin.fill").font(.system(size: 9)).foregroundColor(Color(hex: "#F5A524"))
                        .help("Virou pendência")
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { if !editando { alternar() } }
            if aberta { acoes.padding(.leading, 58) }
        }
        .padding(.horizontal, 8).padding(.vertical, aberta ? 6 : 3)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(aberta ? 0.06 : 0)))
        .onChange(of: aberta) { _, a in if !a { editando = false; confirmarApagar = false } }
    }

    @ViewBuilder private var acoes: some View {
        HStack(spacing: 5) {
            if let p = s.pendencia(daEntrada: e.id) {
                Image(systemName: "pin.fill").font(.system(size: 9.5)).foregroundColor(Color(hex: "#F5A524"))
                Text("Pendência: \(p.acaoCurta)\(p.prazo.map { " · até \(FormatoDiario.quando($0))" } ?? "")")
                    .font(.system(size: 10.5)).foregroundColor(Color(hex: "#C9CDD3")).lineLimit(1)
                DiarioExpandido.pilula("Ver", "arrow.right") {
                    s.detalhe = p.id
                    s.segmento = .pendencias
                }
            } else if !editando {
                Text("Virar pendência:").font(.system(size: 10.5)).foregroundColor(DiarioExpandido.cinza)
                chip("sem prazo") { s.virarPendencia(e, prazo: nil) }
                chip("+1 h") { s.virarPendencia(e, prazo: Date().addingTimeInterval(3600)) }
                if Date() < hojeAs(18) { chip("18h") { s.virarPendencia(e, prazo: hojeAs(18)) } }
                chip("amanhã 9h") { s.virarPendencia(e, prazo: amanhaAs(9)) }
            }
            Spacer(minLength: 4)
            if e.tipo == .nota, Calendar.current.isDateInToday(e.hora) {
                if editando {
                    DiarioExpandido.pilula("Salvar", "checkmark") { salvarEdicao() }
                    DiarioExpandido.pilula("Cancelar", "xmark") { editando = false }
                } else if confirmarApagar {
                    Text("Apagar a nota\(s.pendencia(daEntrada: e.id) != nil ? " e a pendência dela" : "")?")
                        .font(.system(size: 10.5)).foregroundColor(Color(hex: "#F4505E"))
                    DiarioExpandido.pilula("Apagar", "trash", destrutivo: true) {
                        s.apagarEntrada(e.id, dia: s.hoje.dia)
                        s.entradaAberta = nil
                    }
                    DiarioExpandido.pilula("Não", "xmark") { confirmarApagar = false }
                } else {
                    DiarioExpandido.pilula("Editar", "pencil") {
                        rascunho = e.texto
                        editando = true
                        NSApp.windows.first { $0 is IslandPanel }?.makeKey()
                        focoEdicao = true
                    }
                    DiarioExpandido.pilula("Apagar", "trash") { confirmarApagar = true }
                }
            }
        }
    }

    private func salvarEdicao() {
        s.editarNota(e.id, texto: rascunho)
        editando = false
    }

    private func chip(_ t: String, _ acao: @escaping () -> Void) -> some View {
        Button(action: acao) {
            Text(t).font(.system(size: 10)).foregroundColor(Color(hex: "#C9CDD3"))
                .padding(.horizontal, 7).frame(height: 18)
                .background(Capsule().fill(Color.white.opacity(0.08)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func hojeAs(_ h: Int) -> Date {
        Calendar.current.date(bySettingHour: h, minute: 0, second: 0, of: Date()) ?? Date()
    }
    private func amanhaAs(_ h: Int) -> Date {
        let d = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return Calendar.current.date(bySettingHour: h, minute: 0, second: 0, of: d) ?? d
    }
}
