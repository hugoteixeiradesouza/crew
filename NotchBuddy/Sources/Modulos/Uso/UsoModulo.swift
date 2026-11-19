import SwiftUI

@MainActor
final class UsoModulo: Modulo {
    static let shared = UsoModulo()

    let id = "uso"
    let nome = "Uso"
    let icone = "chart.bar.xaxis"
    let pilar = Pilar.ia
    var temBloco: Bool { true }
    var blocoPorPadrao: Bool { false }
    func bloco() -> AnyView { AnyView(UsoBloco()) }
    let resumo = "Quanto você gasta com o Claude Code: tokens e custo estimado por dia, projeto, modelo e sessão, lidos dos transcripts deste Mac (sem rede). Só lê quando você abre."
    var temAba: Bool { true }

    func iniciar() { UsoAlerta.aplicar() }
    func parar() { UsoAlerta.aplicar(moduloLigado: false) }

    func aba() -> AnyView { AnyView(UsoAba()) }
    func central() -> AnyView? { AnyView(UsoCentral()) }
    func ajustes() -> AnyView? { AnyView(UsoAjustes()) }
}
