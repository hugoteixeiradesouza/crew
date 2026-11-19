import SwiftUI

struct MarkdownText: View {
    let text: String
    var lineSpacing: CGFloat = 1

    enum Block {
        case paragraph(String)
        case heading(String)
        case item(marker: String, text: String, indent: Int)
        case code(String)
        case table([[String]])
        case rule
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8 + lineSpacing) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let s):
                    inline(s)
                case .heading(let s):
                    inline(s).fontWeight(.semibold).foregroundColor(Color(hex: "#E8E9EC"))
                case .item(let marker, let s, let indent):
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(marker).foregroundColor(Color(hex: "#6B7079"))
                        inline(s)
                    }
                    .padding(.leading, CGFloat(indent) * 12)
                case .code(let s):
                    Text(s)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Color(hex: "#D5D8DD"))
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                case .table(let rows):
                    table(rows)
                case .rule:
                    Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1)
                }
            }
        }
        .lineSpacing(lineSpacing)
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
    }

    private func inline(_ s: String) -> Text {
        let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        var a = (try? AttributedString(markdown: s, options: opts)) ?? AttributedString(s)
        // Negrito salta um pouco mais: branco
        for run in a.runs where run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true {
            a[run.range].foregroundColor = Color(hex: "#F5F6F8")
        }
        return Text(a)
    }

    /// Tabela com colunas proporcionais ao conteúdo; o texto quebra dentro da célula.
    private func table(_ rows: [[String]]) -> some View {
        let cols = rows.map(\.count).max() ?? 0
        let grid = rows.map { $0 + Array(repeating: "", count: cols - $0.count) }
        // Peso da coluna: maior célula (em caracteres), limitado para nenhuma sumir nem dominar
        let weights = (0..<cols).map { c in
            CGFloat(min(max(grid.map { $0[c].count }.max() ?? 0, 6), 40))
        }
        // Largura mínima: a maior palavra da coluna, para nunca cortar palavra no meio
        let font = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
        let minWidths = (0..<cols).map { c in
            grid.flatMap { $0[c].replacingOccurrences(of: "[*_`]", with: "", options: .regularExpression)
                .split(separator: " ") }
                .map { ceil((String($0) as NSString).size(withAttributes: [.font: font]).width) + 1 }
                .max() ?? 0
        }
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(grid.enumerated()), id: \.offset) { r, row in
                if r > 0 { Rectangle().fill(Color.white.opacity(r == 1 ? 0.14 : 0.07)).frame(height: 1) }
                TableRowLayout(weights: weights, minWidths: minWidths, spacing: 10) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        let t = inline(cell).fixedSize(horizontal: false, vertical: true)
                        if r == 0 { t.fontWeight(.semibold).foregroundColor(Color(hex: "#E8E9EC")) } else { t }
                    }
                }
                .padding(.vertical, 5)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 2)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private static func cells(_ line: String) -> [String] {
        var l = Substring(line)
        if l.hasPrefix("|") { l = l.dropFirst() }
        if l.hasSuffix("|") && !l.hasSuffix("\\|") { l = l.dropLast() }
        // "\|" é barra literal dentro da célula
        return l.replacingOccurrences(of: "\\|", with: "\u{0}")
            .components(separatedBy: "|")
            .map { $0.replacingOccurrences(of: "\u{0}", with: "|").trimmingCharacters(in: .whitespaces) }
    }

    private var blocks: [Block] { Self.blocos(text) }

    /// O texto em blocos (parágrafo, título, item, código, tabela, fio). Também usado pelo
    /// texto selecionável do app do Crew (`TextoConversa`).
    static func blocos(_ text: String) -> [Block] {
        var out: [Block] = []
        var para: [String] = []
        var code: [String]? = nil
        func flush() { if !para.isEmpty { out.append(.paragraph(para.joined(separator: "\n"))); para = [] } }

        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if let c = code { out.append(.code(c.joined(separator: "\n"))); code = nil }
                else { flush(); code = [] }
                continue
            }
            if code != nil { code!.append(raw); continue }
            if line.isEmpty { flush(); continue }
            if line.hasPrefix("|") {
                // Tabela: linhas seguidas viram um bloco só; a linha de separação (|---|) é descartada
                flush()
                if line.replacingOccurrences(of: "[|:\\- ]", with: "", options: .regularExpression).isEmpty { continue }
                if case .table(let prev)? = out.last { out[out.count - 1] = .table(prev + [Self.cells(line)]) }
                else { out.append(.table([Self.cells(line)])) }
                continue
            }
            if line.hasPrefix("#") {
                flush()
                out.append(.heading(String(line.drop { $0 == "#" }).trimmingCharacters(in: .whitespaces)))
                continue
            }
            if line == "---" || line == "***" { flush(); out.append(.rule); continue }
            let indent = (raw.prefix { $0 == " " }.count) / 2
            if let r = line.range(of: #"^[-*+] "#, options: .regularExpression) {
                flush(); out.append(.item(marker: "•", text: String(line[r.upperBound...]), indent: indent)); continue
            }
            if let r = line.range(of: #"^\d+[.)] "#, options: .regularExpression) {
                flush()
                out.append(.item(marker: String(line[..<r.upperBound]).trimmingCharacters(in: .whitespaces),
                                 text: String(line[r.upperBound...]), indent: indent))
                continue
            }
            para.append(line)
        }
        if let c = code { out.append(.code(c.joined(separator: "\n"))) }
        flush()
        return out
    }
}

/// Uma linha de tabela: cada célula recebe a fatia da largura dada pelo peso da coluna,
/// e a altura da linha é a da célula mais alta. Mesmos pesos em todas as linhas = colunas alinhadas.
struct TableRowLayout: Layout {
    let weights: [CGFloat]
    let minWidths: [CGFloat]
    let spacing: CGFloat

    /// Reparte pelos pesos; coluna que ficaria abaixo do mínimo fica com o mínimo e o resto
    /// é repartido de novo entre as demais.
    private func widths(_ total: CGFloat, _ n: Int) -> [CGFloat] {
        let w = (0..<n).map { $0 < weights.count ? weights[$0] : 1 }
        let mins = (0..<n).map { $0 < minWidths.count ? minWidths[$0] : 0 }
        let free = max(total - spacing * CGFloat(max(n - 1, 0)), 0)
        var fixed = Set<Int>()
        while true {
            let rest = free - fixed.reduce(0) { $0 + mins[$1] }
            let sum = max((0..<n).filter { !fixed.contains($0) }.reduce(0) { $0 + w[$1] }, 1)
            let out = (0..<n).map { fixed.contains($0) ? mins[$0] : max(rest, 0) * w[$0] / sum }
            let novas = (0..<n).filter { !fixed.contains($0) && out[$0] < mins[$0] }
            if novas.isEmpty || fixed.count + novas.count == n { return out }
            fixed.formUnion(novas)
        }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let total = proposal.width ?? 320
        let h = zip(subviews, widths(total, subviews.count))
            .map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }.max() ?? 0
        return CGSize(width: total, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (v, w) in zip(subviews, widths(bounds.width, subviews.count)) {
            v.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(width: w, height: nil))
            x += w + spacing
        }
    }
}

struct TypingDotsView: View {
    @State private var phase = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color(hex: "#6B7079"))
                    .frame(width: 5, height: 5)
                    .scaleEffect(phase ? 1.2 : 0.6)
                    .animation(
                        .easeInOut(duration: 0.45).repeatForever().delay(Double(i) * 0.14),
                        value: phase
                    )
            }
        }
        .padding(.horizontal, 2).padding(.vertical, 4)
        .onAppear { phase = true }
    }
}
