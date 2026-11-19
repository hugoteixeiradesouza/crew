import SwiftUI

// MARK: - Brilho / volume

/// Ícone + barra do nível + porcentagem.
struct NivelBarra: View {
    let nivel: NivelService.Nivel
    let compacta: Bool

    private var icone: String {
        switch nivel.tipo {
        case .brilho: return nivel.valor < 0.5 ? "sun.min.fill" : "sun.max.fill"
        case .volume:
            if nivel.mudo || nivel.valor <= 0.001 { return "speaker.slash.fill" }
            return nivel.valor < 0.34 ? "speaker.wave.1.fill" : nivel.valor < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
        }
    }

    private var valor: Double { nivel.mudo ? 0 : nivel.valor }

    var body: some View {
        HStack(spacing: compacta ? 8 : 10) {
            Image(systemName: icone)
                .font(.system(size: compacta ? 10 : 13, weight: .semibold))
                .foregroundColor(Color(hex: "#DADDE2"))
                .frame(width: compacta ? 14 : 20)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.14))
                    Capsule().fill(Color.white)
                        .frame(width: max(compacta ? 4 : 6, g.size.width * valor))
                }
            }
            .frame(height: compacta ? 4 : 6)
            .animation(.spring(response: 0.25, dampingFraction: 0.85), value: valor)
            Text("\(Int((valor * 100).rounded()))")
                .font(.system(size: compacta ? 10 : 12, weight: .semibold).monospacedDigit())
                .foregroundColor(Color(hex: "#8E939C"))
                .frame(width: compacta ? 22 : 28, alignment: .trailing)
        }
    }
}
