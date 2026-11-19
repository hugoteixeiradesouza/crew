import SwiftUI

@MainActor
final class ModelosModulo: Modulo {
    static let shared = ModelosModulo()

    let id = "modelos"
    let nome = "Modelos"
    let icone = "cpu"
    let pilar = Pilar.ia
    let resumo = "Modelos locais de IA (Ollama e LM Studio): quanto ocupam, quanto cada um libera e qual está carregado agora."
    var temAba: Bool { true }
    /// Liga sozinho só se este Mac tem Ollama ou LM Studio (pasta de modelos ou o binário).
    var ligadoPorPadrao: Bool { PoliticaModelos.haAlgoInstalado() }

    func parar() {
        ModelosServico.shared.soltar("aba")
        ModelosServico.shared.soltar("central")
    }

    func aba() -> AnyView { AnyView(ModelosAba()) }
    func central() -> AnyView? { AnyView(ModelosCentral()) }
}
