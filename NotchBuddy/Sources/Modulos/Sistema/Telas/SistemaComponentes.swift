import SwiftUI

/// Anel de 0…1 com o valor no meio.
struct AnelSistema: View {
    let fracao: Double
    let texto: String
    let cor: Color
    var espessura: CGFloat = 5
    var fonte: CGFloat = 12
    var trilho: Color = Color.white.opacity(0.10)

    var body: some View {
        ZStack {
            Circle().stroke(trilho, lineWidth: espessura)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, fracao)))
                .stroke(cor, style: StrokeStyle(lineWidth: espessura, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.35), value: fracao)
            Text(texto)
                .font(.system(size: fonte, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .padding(.horizontal, espessura + 2)
        }
    }
}

/// Linha de histórico (0…1) com área preenchida.
struct GraficoHistorico: View {
    let pontos: [Double]
    let total: Int
    let cor: Color

    var body: some View {
        Canvas { ctx, size in
            guard pontos.count > 1 else { return }
            let passo = size.width / CGFloat(max(1, total - 1))
            let inicio = size.width - passo * CGFloat(pontos.count - 1)
            var linha = Path()
            for (i, v) in pontos.enumerated() {
                let p = CGPoint(x: inicio + passo * CGFloat(i), y: size.height * (1 - CGFloat(min(1, max(0, v)))))
                i == 0 ? linha.move(to: p) : linha.addLine(to: p)
            }
            var area = linha
            area.addLine(to: CGPoint(x: size.width, y: size.height))
            area.addLine(to: CGPoint(x: inicio, y: size.height))
            area.closeSubpath()
            ctx.fill(area, with: .linearGradient(Gradient(colors: [cor.opacity(0.45), cor.opacity(0.05)]),
                                                 startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            ctx.stroke(linha, with: .color(cor), lineWidth: 1.5)
        }
    }
}

enum FormatoSistema {
    static func pct(_ f: Double) -> String { "\(Int((f * 100).rounded()))%" }
    static func bytes(_ b: UInt64) -> String { ByteCountFormatter.string(fromByteCount: Int64(b), countStyle: .memory) }
    static func disco(_ b: Int64) -> String { ByteCountFormatter.string(fromByteCount: b, countStyle: .file) }
    static func taxa(_ bps: Double) -> String {
        bps < 1 ? "0 KB/s" : ByteCountFormatter.string(fromByteCount: Int64(bps), countStyle: .file) + "/s"
    }
    static func temp(_ t: Double?) -> String { t.map { "\(Int($0.rounded()))°" } ?? "—" }
    static func duracao(_ s: TimeInterval) -> String {
        let d = Int(s) / 86400, h = Int(s) % 86400 / 3600, m = Int(s) % 3600 / 60
        if d > 0 { return "\(d) d \(h) h" }
        return h > 0 ? "\(h) h \(m) min" : "\(m) min"
    }
    static func corTemp(_ t: Double?) -> Color {
        guard let t else { return Color(hex: "#8E939C") }
        return t >= 85 ? Color(hex: "#F4505E") : t >= 70 ? Color(hex: "#F5A524") : Color(hex: "#34D399")
    }
    static func corPressao(_ p: Int) -> Color {
        p >= 4 ? Color(hex: "#F4505E") : p >= 2 ? Color(hex: "#F5A524") : Color(hex: "#A78BFA")
    }
    static let corCPU = Color(hex: "#3B9EFF")
    static let corGPU = Color(hex: "#2EC4A0")
}
