import SwiftUI

@MainActor
final class ComandoModulo: Modulo {
    static let shared = ComandoModulo()

    let id = ComandoServico.modulo
    let nome = "Plug"
    let icone = "command"
    let pilar = Pilar.mac
    let superficies: [Superficie] = [.atalho, .claude]
    let resumo = "Um campo que acha e faz, por atalho, com qualquer app na frente: abre apps, arquivos e ajustes, faz contas, traduz, pesquisa no navegador do Crew, leva às sessões e dispara as ferramentas do Crew. O que não casa com nada pode virar pedido ao Claude Code. Tudo neste Mac; fechado, não roda nada."

    func iniciar() { ComandoServico.shared.iniciar() }
    func parar() { ComandoServico.shared.parar() }

    func central() -> AnyView? { AnyView(ComandoCentral()) }
    func ajustes() -> AnyView? { AnyView(ComandoAjustes()) }

    /// `crew://comando/abrir[?texto=…]` abre o painel (já com o texto) · `crew://comando/fechar`.
    func executar(_ acao: String, _ parametros: [String: String]) -> Bool {
        switch acao {
        case "abrir":
            ComandoServico.shared.abrir(texto: parametros["texto"] ?? "")
            return true
        case "fechar":
            ComandoServico.shared.fechar()
            return true
        default:
            return false
        }
    }
}
