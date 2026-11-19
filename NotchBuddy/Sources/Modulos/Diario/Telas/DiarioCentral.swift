import SwiftUI

// Página do Diário na Central: seletor de dia, pendências (abertas e resolvidas), o resumo
// (Feito · Aberto · Prometido), a linha do tempo com filtro por tipo, tempo por app e commits.

struct DiarioCentral: View {
    private let s = DiarioServico.shared
    @State private var diaEscolhido: String = FormatoDiario.dia(Date())
    @State private var filtro: TipoEntrada?
    @State private var outroDia: DiaDiario?

    private var eHoje: Bool { diaEscolhido == s.hoje.dia }
    private var d: DiaDiario { eHoje ? s.hoje : (outroDia ?? DiaDiario(dia: diaEscolhido)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            cabecalho
            if eHoje { pendenciasAbertas }
            resumo
            linhaDoTempo
            tempoPorApp
            commits
        }
        .onChange(of: diaEscolhido) { _, novo in
            outroDia = novo == s.hoje.dia ? nil : s.dia(novo)
        }
    }

    // MARK: Cabeçalho

    private var cabecalho: some View {
        let dias = s.diasComArquivo()
        let i = dias.firstIndex(of: diaEscolhido)
        return HStack(spacing: 8) {
            Button { if let i, i + 1 < dias.count { diaEscolhido = dias[i + 1] } } label: { Image(systemName: "chevron.left") }
                .disabled(i == nil || i! + 1 >= dias.count)
                .help("Dia anterior")
            SeletorCrew(selecao: $diaEscolhido,
                        opcoes: dias.map { (valor: $0, titulo: FormatoDiario.diaLongo($0)) },
                        largura: 220)
            Button { if let i, i > 0 { diaEscolhido = dias[i - 1] } } label: { Image(systemName: "chevron.right") }
                .disabled(i == nil || i! == 0)
                .help("Dia seguinte")
            Spacer()
            if eHoje {
                Button {
                    Task { await s.resumir() }
                } label: {
                    Label(s.resumindo ? "Resumindo…" : "Resumir o dia", systemImage: "text.book.closed")
                }
                .disabled(s.resumindo)
            }
        }
    }

    // MARK: Pendências

    private var pendenciasAbertas: some View {
        let abertas = s.abertas
        let resolvidas = s.hoje.pendencias.filter { !$0.aberta }.sorted { ($0.resolvidaEm ?? $0.criadaEm) > ($1.resolvidaEm ?? $1.criadaEm) }
        return Secao("Pendências", "Triadas na hora pelo modelo local a partir das suas notas, dos seus pedidos e das entregas que esperam por você. Com prazo, o Homie avisa \(s.avisoAntes) min antes e na hora; \"agora\" avisa na hora; sem prazo, ficam só aqui e no resumo.") {
            if abertas.isEmpty {
                Text("Nenhuma pendência aberta.").font(.system(size: 12)).foregroundColor(.secondary)
            }
            ForEach(abertas) { p in LinhaPendencia(p: p, claro: true) }
            if !resolvidas.isEmpty {
                DisclosureGroup("Resolvidas hoje (\(resolvidas.count))") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(resolvidas) { p in linhaResolvida(p) }
                    }
                    .padding(.top, 4)
                }
                .font(.system(size: 12))
            }
        }
    }

    private func linhaResolvida(_ p: Pendencia) -> some View {
        HStack(spacing: 8) {
            Image(systemName: p.estado == .feita ? "checkmark.circle.fill" : "minus.circle")
                .foregroundColor(p.estado == .feita ? .green : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(p.acao).font(.system(size: 12)).strikethrough(p.estado == .feita)
                Text([p.estado == .feita ? "feito" : "ignorado",
                      p.resolvidaEm.map { "às \(FormatoDiario.hora($0))" }, p.motivo, DiarioServico.deOnde(p)]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 10.5)).foregroundColor(.secondary)
            }
            Spacer()
            Button("Reabrir") { s.reabrir(p.id) }.controlSize(.small)
        }
    }

    // MARK: Resumo

    private var resumo: some View {
        Secao("Resumo do dia", d.resumo.map { r in
            "Gerado às \(FormatoDiario.hora(r.geradoEm)) \(r.comIA ? "com o modelo local do Mac (sem rede)" : "sem IA (modelo local indisponível)")."
        } ?? (eHoje ? "Sai sozinho às \(String(format: "%02d:%02d", s.horaResumo / 60, s.horaResumo % 60)) (ajuste abaixo) ou no botão." : "Esse dia não teve resumo.")) {
            if let r = d.resumo {
                bloco("Feito", "checkmark.circle", .green, r.feito)
                bloco("Aberto", "circle.dashed", .orange, r.aberto)
                bloco("Prometido", "hand.raised", .blue, r.prometido)
            } else {
                Text(s.resumindo ? "Resumindo…" : "Ainda sem resumo.").font(.system(size: 12)).foregroundColor(.secondary)
            }
        }
    }

    private func bloco(_ titulo: String, _ icone: String, _ cor: Color, _ itens: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(titulo, systemImage: icone).font(.system(size: 12, weight: .semibold)).foregroundColor(cor)
            if itens.isEmpty {
                Text("Nada.").font(.system(size: 12)).foregroundColor(.secondary)
            }
            ForEach(Array(itens.enumerated()), id: \.offset) { _, t in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("•").foregroundColor(.secondary)
                    Text(t).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
            }
        }
    }

    // MARK: Linha do tempo

    private var linhaDoTempo: some View {
        let entradas = d.entradas.filter { filtro == nil || $0.tipo == filtro }.sorted { $0.hora > $1.hora }
        return Secao("Linha do tempo", "Pedidos e entregas das sessões do Claude Code e as suas notas. Notas podem ser apagadas (clique com o botão direito).") {
            Picker("", selection: $filtro) {
                Text("Tudo (\(d.entradas.count))").tag(TipoEntrada?.none)
                ForEach(TipoEntrada.allCases) { t in Text("\(t.nome) (\(d.contagem(t)))").tag(TipoEntrada?.some(t)) }
            }
            .pickerStyle(.segmented).labelsHidden()
            if entradas.isEmpty {
                Text("Nada aqui.").font(.system(size: 12)).foregroundColor(.secondary)
            }
            ForEach(entradas) { e in
                HStack(alignment: .top, spacing: 8) {
                    Text(FormatoDiario.hora(e.hora)).font(.system(size: 11)).foregroundColor(.secondary).monospacedDigit()
                        .frame(width: 38, alignment: .leading)
                    Image(systemName: e.tipo.icone)
                        .font(.system(size: 9, weight: .bold)).foregroundColor(.white)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color(hex: e.cor ?? (e.tipo == .nota ? "#6B7280" : "#8E939C"))))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(e.texto).font(.system(size: 12)).lineLimit(3).textSelection(.enabled)
                        if e.projeto != nil || e.sessao != nil {
                            Text([e.projeto, e.sessao].compactMap { $0 }.joined(separator: " · "))
                                .font(.system(size: 10.5)).foregroundColor(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .menuContexto {
                    // Só nota tem menu; lista vazia não abre nada
                    guard e.tipo == .nota else { return [] }
                    return [.acao("Apagar nota", icone: "trash", destrutivo: true) {
                        s.apagarEntrada(e.id, dia: d.dia)
                        if !eHoje { outroDia = s.dia(diaEscolhido) }
                    }]
                }
            }
        }
    }

    // MARK: Apps

    private var tempoPorApp: some View {
        let lista: [(String, String, Double)] = eHoje
            ? s.appsHoje.map { ($0.bundle, $0.nome, $0.segundos) }
            : d.apps.map { ($0.key, $0.value.nome, $0.value.segundos) }.sorted { $0.2 > $1.2 }
        let maior = max(lista.first?.2 ?? 1, 1)
        let total = lista.reduce(0) { $0 + $1.2 }
        return Secao("Tempo por app", lista.isEmpty ? nil : "Total em foco: \(FormatoDiario.duracao(total)). Pausa com a tela apagada ou bloqueada; o Crew não conta.") {
            if lista.isEmpty {
                Text(s.fonteLigada(.apps) ? "Nada medido ainda." : "Fonte desligada.").font(.system(size: 12)).foregroundColor(.secondary)
            }
            ForEach(lista.prefix(12), id: \.0) { b, nome, seg in
                HStack(spacing: 8) {
                    Text(nome).font(.system(size: 12)).lineLimit(1).frame(width: 170, alignment: .leading)
                    GeometryReader { g in
                        RoundedRectangle(cornerRadius: 3).fill(Color.accentColor.opacity(0.75))
                            .frame(width: max(2, g.size.width * seg / maior))
                    }
                    .frame(height: 10)
                    Text(FormatoDiario.duracao(seg)).font(.system(size: 11)).foregroundColor(.secondary).monospacedDigit()
                        .frame(width: 70, alignment: .trailing)
                }
                .help(b)
            }
        }
    }

    // MARK: Commits

    private var commits: some View {
        Secao("Commits do dia", "Seus commits (user.email de cada repositório) nos projetos que apareceram no dia. Lidos na hora do resumo, do git local.") {
            if eHoje {
                HStack {
                    Button { Task { await s.lerCommits() } } label: {
                        Label(s.lendoCommits ? "Lendo…" : "Ler agora", systemImage: "arrow.clockwise")
                    }
                    .disabled(s.lendoCommits || !s.fonteLigada(.commits))
                    if let l = d.commitsLidosEm {
                        Text("Lidos às \(FormatoDiario.hora(l))").font(.system(size: 11)).foregroundColor(.secondary)
                    }
                }
            }
            let lista = d.commits ?? []
            if lista.isEmpty {
                Text(d.commits == nil ? "Ainda não lidos." : "Nenhum commit seu.").font(.system(size: 12)).foregroundColor(.secondary)
            }
            ForEach(lista) { c in
                HStack(spacing: 8) {
                    Text(FormatoDiario.hora(c.hora)).font(.system(size: 11)).foregroundColor(.secondary).monospacedDigit()
                        .frame(width: 38, alignment: .leading)
                    Text(c.projeto).font(.system(size: 11, weight: .medium)).foregroundColor(.secondary).frame(width: 90, alignment: .leading)
                        .lineLimit(1)
                    Text(c.titulo).font(.system(size: 12)).lineLimit(1).textSelection(.enabled)
                    Spacer(minLength: 0)
                    Text(String(c.hash.prefix(7))).font(.system(size: 10.5, design: .monospaced)).foregroundColor(.secondary)
                }
            }
        }
    }
}

/// Ajustes do Diário: hora do resumo, aviso antes do prazo e cada fonte (desligar apaga).
struct DiarioAjustes: View {
    private let s = DiarioServico.shared
    @State private var confirmar: FonteDiario?
    @State private var versao = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            let _ = versao
            Toggle("Resumo do dia sozinho", isOn: Binding(get: { s.resumoAutomatico }, set: { s.resumoAutomatico = $0; versao += 1 }))
            HStack {
                Text("Hora do resumo")
                Spacer()
                SeletorCrew(selecao: Binding(get: { s.horaResumo }, set: { s.horaResumo = $0; versao += 1 }),
                            opcoes: Array(stride(from: 15 * 60, through: 22 * 60, by: 30)).map { m in
                                (valor: m, titulo: String(format: "%02d:%02d", m / 60, m % 60))
                            },
                            largura: 100)
            }
            .disabled(!s.resumoAutomatico)
            HStack {
                Text("Primeiro aviso antes do prazo")
                Spacer()
                SeletorCrew(selecao: Binding(get: { s.avisoAntes }, set: { s.avisoAntes = $0; versao += 1 }),
                            opcoes: [5, 10, 15, 30, 60].map { (valor: $0, titulo: "\($0) min") },
                            largura: 100)
            }
            Text(IAdoMac.disponivel ? "Triagem e resumo com o modelo local da Apple (Apple Intelligence): roda neste Mac, sem rede."
                                    : "Modelo local indisponível (Apple Intelligence desligada?): triagem e resumo saem por regras simples.")
                .font(.system(size: 11)).foregroundColor(.secondary)
            Divider()
            Text("Fontes").font(.system(size: 12, weight: .semibold))
            ForEach(FonteDiario.allCases) { f in
                VStack(alignment: .leading, spacing: 2) {
                    Toggle(f.nome, isOn: Binding(get: { s.fonteLigada(f) }, set: { novo in
                        if novo { s.definirFonte(f, true); versao += 1 } else { confirmar = f }
                    }))
                    Text(f.detalhe).font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Text("Tudo fica em ~/Library/Application Support/NotchBuddy/diario/, um arquivo por dia. Nada sai do Mac.")
                .font(.system(size: 11)).foregroundColor(.secondary)
        }
        .alert("Desligar \"\(confirmar?.nome ?? "")\"?", isPresented: Binding(get: { confirmar != nil }, set: { if !$0 { confirmar = nil } })) {
            Button("Desligar e apagar", role: .destructive) {
                if let f = confirmar { s.definirFonte(f, false); versao += 1 }
                confirmar = nil
            }
            Button("Cancelar", role: .cancel) { confirmar = nil }
        } message: {
            Text("As Tasks param de registrar essa fonte e apaga o que já guardou dela em todos os dias (inclusive pendências e resumos que vieram dela). Não dá para desfazer.")
        }
    }
}
