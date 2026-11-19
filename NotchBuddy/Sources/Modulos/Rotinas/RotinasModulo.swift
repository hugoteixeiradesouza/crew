import SwiftUI

// Rotinas: pedidos guardados que abrem sessões do Claude Code num projeto, pela agenda ou à mão.
// Ver docs/ARQUITETURA.md (Rotinas).

@MainActor
final class RotinasModulo: Modulo {
    static let shared = RotinasModulo()

    let id = RotinasServico.idModulo
    let nome = "Rotinas"
    let icone = "clock.arrow.2.circlepath"
    let pilar = Pilar.ia
    let superficies: [Superficie] = [.ilha, .claude]
    let resumo = "Pedidos guardados que abrem uma sessão do Claude Code num projeto, na hora marcada ou quando você manda. Só roda sozinha a rotina que você ligou."

    func iniciar() { RotinasServico.shared.iniciar() }
    func parar() { RotinasServico.shared.parar() }

    func central() -> AnyView? { AnyView(RotinasCentral()) }

    /// `crew://rotinas/rodar?id=<uuid>` ou `?nome=<nome>`. Endereço pode vir de um agente, então
    /// não roda: publica o pedido na ilha e o Hugo decide na página (botão "Rodar agora").
    func executar(_ acao: String, _ parametros: [String: String]) -> Bool {
        switch acao {
        case "rodar":
            return RotinasServico.shared.pedirDeFora(id: parametros["id"], nome: parametros["nome"])
        default:
            return false
        }
    }
}
