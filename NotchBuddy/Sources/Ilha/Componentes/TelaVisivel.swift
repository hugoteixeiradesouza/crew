import SwiftUI

// Todas as abas da ilha ficam montadas ao mesmo tempo (as de fora com opacidade 0).
// Este sinal diz a cada uma se ela está na tela de verdade: animação contínua
// (TimelineView, timer) só roda com `telaVisivel == true`. Fora da ilha vale true.

private struct TelaVisivelKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var telaVisivel: Bool {
        get { self[TelaVisivelKey.self] }
        set { self[TelaVisivelKey.self] = newValue }
    }
}

/// Taxa de quadros das animações que não pedem fluidez máxima (Homie compacto, brilho do texto).
enum Quadros {
    /// Homie na ilha compacta, brilho do ticker.
    static let leve: Double = 1.0 / 24
    /// Mini-Homies das outras sessões (12 pt).
    static let mini: Double = 1.0 / 12
}
