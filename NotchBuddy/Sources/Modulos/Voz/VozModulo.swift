import SwiftUI

@MainActor
final class VozModulo: Modulo {
    static let shared = VozModulo()

    let id = VozServico.modulo
    let nome = "Voz"
    let icone = "mic"
    let pilar = Pilar.criar
    let superficies: [Superficie] = [.ilha, .app, .atalho, .claude]
    let resumo = "Ditar em vez de digitar e ouvir em vez de ler: ditado em qualquer campo do Crew, segurar um atalho para falar de qualquer app e leitura das respostas em voz alta. A fala vira texto neste Mac; nada é gravado e o microfone só abre enquanto você dita."

    func iniciar() { VozServico.shared.iniciar(); FalaServico.shared.iniciar() }
    func parar() { VozServico.shared.desligar(); FalaServico.shared.desligar() }

    func central() -> AnyView? { AnyView(VozCentral()) }
    func ajustes() -> AnyView? { AnyView(VozAjustes()) }

    /// crew://voz/ditar · crew://voz/parar · crew://voz/falar?texto=…[&voz=<nome de uma voz humanizada>]
    /// `ditar` segue o caminho do segurar-para-falar: mostra na ilha e copia; nunca pede
    /// permissão do macOS por endereço (isso é com clique, na página da Voz).
    func executar(_ acao: String, _ parametros: [String: String]) -> Bool {
        switch acao {
        case "ditar":
            VozGlobal.alternar()
            return true
        case "parar":
            VozServico.shared.pararTudo()
            return true
        case "falar":
            guard let texto = parametros["texto"], !texto.isEmpty else { return false }
            FalaServico.shared.falar(texto, voz: parametros["voz"])
            return true
        default:
            return false
        }
    }
}
