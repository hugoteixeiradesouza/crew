import SwiftUI

// A grade do app do Crew: até 16 sessões (4 × 4) na mesma tela. As colunas são automáticas ou
// as que o Hugo escolher (menu de grade no cabeçalho de qualquer painel); as linhas saem do
// número de sessões. A ordem é a do Hugo: arrastar o cabeçalho de um painel para cima de outro
// muda o lugar dele (também pelo menu e por ⌃⌘← ⌃⌘→).

/// Reparte a área em linhas de `colunas` painéis; a última linha, se tiver menos, estica.
/// Cada painel tem um peso dentro da linha e cada linha tem um peso: é o que o Hugo muda
/// arrastando as divisórias (peso 1 = parte igual).
struct GradeLayout: Layout {
    var colunas: Int
    var ids: [String]
    var pesoPainel: [String: CGFloat]
    var pesoLinha: [Int: CGFloat]

    static func quadros(_ ids: [String], colunas: Int, em tamanho: CGSize,
                        pesoPainel: [String: CGFloat], pesoLinha: [Int: CGFloat]) -> [CGRect] {
        let n = ids.count
        guard n > 0, colunas > 0 else { return [] }
        let linhas = Int((Double(n) / Double(colunas)).rounded(.up))
        let somaLinhas = (0..<linhas).reduce(CGFloat(0)) { $0 + (pesoLinha[$1] ?? 1) }
        var out: [CGRect] = []
        var y: CGFloat = 0
        for l in 0..<linhas {
            let altura = tamanho.height * (pesoLinha[l] ?? 1) / somaLinhas
            let daLinha = Array(ids[(l * colunas)..<min(n, (l + 1) * colunas)])
            let soma = daLinha.reduce(CGFloat(0)) { $0 + (pesoPainel[$1] ?? 1) }
            var x: CGFloat = 0
            for id in daLinha {
                let largura = tamanho.width * (pesoPainel[id] ?? 1) / soma
                out.append(CGRect(x: x, y: y, width: largura, height: altura))
                x += largura
            }
            y += altura
        }
        return out
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let quadros = Self.quadros(ids, colunas: colunas, em: bounds.size, pesoPainel: pesoPainel, pesoLinha: pesoLinha)
        for (v, q) in zip(subviews, quadros) {
            v.place(at: CGPoint(x: bounds.minX + q.minX, y: bounds.minY + q.minY),
                    proposal: ProposedViewSize(width: q.width, height: q.height))
        }
    }
}

struct GradeSessoes: View {
    /// Sessões da grade que ainda existem, na ordem do Hugo.
    let paineis: [String]
    /// O painel em foco.
    let foco: String
    /// Recuo do título do primeiro painel (barra lateral recolhida: os botões da janela ficam por cima).
    var recuoDoPrimeiro: CGFloat = 0
    @EnvironmentObject private var nav: NavegacaoCrew

    /// Uma divisória que o Hugo arrasta: entre dois painéis da mesma linha, ou entre duas linhas.
    private struct Divisoria: Identifiable {
        let id: String
        let faixa: CGRect
        let entreLinhas: Bool
        /// Entre painéis: os dois ids. Entre linhas: os índices das duas linhas.
        var a = "", b = ""
        var linhaA = 0
        /// Tamanho atual de cada lado (largura ou altura).
        let tamanhoA: CGFloat, tamanhoB: CGFloat
    }

    /// Como estavam os dois lados quando o arraste começou.
    @State private var inicio: (id: String, pesoA: CGFloat, pesoB: CGFloat, tamA: CGFloat, tamB: CGFloat)?

    private static let larguraMinima: CGFloat = 230
    private static let alturaMinima: CGFloat = 170

    var body: some View {
        GeometryReader { geo in
            let colunas = NavegacaoCrew.colunas(para: paineis.count, escolha: nav.colunasGrade)
            let quadros = GradeLayout.quadros(paineis, colunas: colunas, em: geo.size,
                                              pesoPainel: nav.pesoPainel, pesoLinha: nav.pesoLinha)
            // Onde cada painel está: é com isso que o arraste sabe em cima de quem está.
            let _ = (nav.quadrosGrade = Array(zip(paineis, quadros)).map { (id: $0.0, quadro: $0.1) })
            ZStack(alignment: .topLeading) {
                GradeLayout(colunas: colunas, ids: paineis, pesoPainel: nav.pesoPainel, pesoLinha: nav.pesoLinha) {
                    ForEach(paineis, id: \.self) { p in
                        ConversaCrew(taskId: p, compacto: true, emFoco: p == foco, atencao: nav.atencao.contains(p)) {
                            nav.fecharPainel(p)
                        }
                        .environment(\.recuoTitulo, p == paineis.first ? recuoDoPrimeiro : 0)
                        // Clicar em qualquer ponto do painel põe o foco nele (o texto da conversa
                        // fica com o clique dele e avisa por aqui).
                        .environment(\.aoTocarTexto) { focar(p) }
                        .simultaneousGesture(TapGesture().onEnded { focar(p) })
                        .opacity(nav.arrastando == p ? 0.4 : 1)
                        .overlay { Rectangle().strokeBorder(Tema.borda, lineWidth: 0.5).allowsHitTesting(false) }
                        .overlay {
                            // O lugar para onde o painel arrastado vai.
                            if nav.alvoArraste == p, nav.arrastando != nil, nav.arrastando != p {
                                Rectangle().fill(Tema.azul.opacity(0.12))
                                    .overlay(Rectangle().strokeBorder(Tema.azul, lineWidth: 2))
                                    .allowsHitTesting(false)
                            }
                        }
                    }
                }
                ForEach(divisorias(quadros, colunas: colunas)) { d in alca(d) }
            }
            .coordinateSpace(name: "grade")
            .overlay(alignment: .bottomTrailing) {
                if let a = nav.abrindo, a.naGrade {
                    HStack(spacing: 7) {
                        ProgressView().controlSize(.small).scaleEffect(0.7)
                        Text("Abrindo sessão em \(a.projeto)…").font(.system(size: 12, weight: .medium)).foregroundStyle(Tema.texto)
                    }
                    .padding(.horizontal, 14).frame(height: 32)
                    .background(Pilula().fill(Tema.elevado))
                    .overlay(Pilula().strokeBorder(Tema.bordaForte))
                    .shadow(color: .black.opacity(0.4), radius: 12, y: 5)
                    .padding(14)
                }
            }
        }
    }

    private func focar(_ p: String) {
        if nav.selecao != .sessao(p) { nav.selecao = .sessao(p) }
    }

    /// As divisórias da grade: uma entre cada par de vizinhos na linha e uma entre cada par de linhas.
    private func divisorias(_ quadros: [CGRect], colunas: Int) -> [Divisoria] {
        var out: [Divisoria] = []
        let n = paineis.count
        guard n > 1, quadros.count == n else { return [] }
        let linhas = Int((Double(n) / Double(colunas)).rounded(.up))
        for i in 0..<n where (i + 1) % colunas != 0 && i + 1 < n {
            let q = quadros[i]
            out.append(Divisoria(id: "c" + paineis[i], faixa: CGRect(x: q.maxX - 4, y: q.minY, width: 8, height: q.height),
                                 entreLinhas: false, a: paineis[i], b: paineis[i + 1],
                                 tamanhoA: q.width, tamanhoB: quadros[i + 1].width))
        }
        for l in 0..<(linhas - 1) {
            let cima = quadros[l * colunas], baixo = quadros[(l + 1) * colunas]
            out.append(Divisoria(id: "l\(l)", faixa: CGRect(x: 0, y: cima.maxY - 4, width: quadros.map(\.maxX).max() ?? 0, height: 8),
                                 entreLinhas: true, linhaA: l, tamanhoA: cima.height, tamanhoB: baixo.height))
        }
        return out
    }

    /// A faixa invisível em cima da divisória: arrastar tira de um lado e dá ao outro.
    private func alca(_ d: Divisoria) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .frame(width: d.faixa.width, height: d.faixa.height)
            .onHover { dentro in
                if dentro { (d.entreLinhas ? NSCursor.resizeUpDown : NSCursor.resizeLeftRight).push() } else { NSCursor.pop() }
            }
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named("grade"))
                .onChanged { g in
                    if inicio?.id != d.id {
                        let pa = d.entreLinhas ? nav.pesoLinha[d.linhaA] ?? 1 : nav.pesoPainel[d.a] ?? 1
                        let pb = d.entreLinhas ? nav.pesoLinha[d.linhaA + 1] ?? 1 : nav.pesoPainel[d.b] ?? 1
                        inicio = (d.id, pa, pb, d.tamanhoA, d.tamanhoB)
                    }
                    guard let i = inicio else { return }
                    let total = i.tamA + i.tamB
                    let minimo = d.entreLinhas ? Self.alturaMinima : Self.larguraMinima
                    guard total > minimo * 2 else { return }
                    let delta = d.entreLinhas ? g.translation.height : g.translation.width
                    let novoA = min(max(i.tamA + delta, minimo), total - minimo)
                    let pesos = i.pesoA + i.pesoB
                    let pa = pesos * novoA / total
                    if d.entreLinhas {
                        nav.pesoLinha[d.linhaA] = pa
                        nav.pesoLinha[d.linhaA + 1] = pesos - pa
                    } else {
                        nav.pesoPainel[d.a] = pa
                        nav.pesoPainel[d.b] = pesos - pa
                    }
                }
                .onEnded { _ in inicio = nil })
            .offset(x: d.faixa.minX, y: d.faixa.minY)
            .help("Arraste para mudar o tamanho")
    }
}
