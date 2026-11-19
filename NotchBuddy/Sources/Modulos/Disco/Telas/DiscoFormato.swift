import SwiftUI

enum DiscoFormato {
    static func bytes(_ b: Int64) -> String { ByteCountFormatter.string(fromByteCount: b, countStyle: .file) }

    static func ha(_ d: Date) -> String {
        let s = Int(Date().timeIntervalSince(d))
        if s < 60 { return "agora há pouco" }
        if s < 3600 { return "há \(s / 60) min" }
        return "há \(s / 3600) h"
    }

    static func corLivre(_ v: AmostraVolume) -> Color {
        let f = Double(v.livre) / Double(max(1, v.total))
        return f < 0.05 ? Color(hex: "#F4505E") : f < 0.12 ? Color(hex: "#F5A524") : Color(hex: "#34D399")
    }

    static let corDisco = Color(hex: "#3B9EFF")
}

/// Barra de uso do disco (fração usada).
struct BarraDisco: View {
    let volume: AmostraVolume?
    var trilho: Color = Color.white.opacity(0.10)
    var altura: CGFloat = 6

    var body: some View {
        GeometryReader { g in
            let f = volume.map { Double($0.usado) / Double(max(1, $0.total)) } ?? 0
            ZStack(alignment: .leading) {
                Capsule().fill(trilho)
                Capsule().fill(volume.map(DiscoFormato.corLivre) ?? trilho)
                    .frame(width: max(altura, g.size.width * f))
            }
        }
        .frame(height: altura)
    }
}
