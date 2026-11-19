import SwiftUI

@MainActor
final class AudioModulo: Modulo {
    static let shared = AudioModulo()

    let id = "audio"
    let nome = "Áudio"
    let icone = "hifispeaker.2"
    let pilar = Pilar.mac
    let superficies: [Superficie] = [.ilha, .atalho]
    var temBloco: Bool { true }
    var blocoPorPadrao: Bool { true }
    func bloco() -> AnyView { AnyView(AudioBloco()) }
    let resumo = "Volume e mudo de cada app (até 400%), saída e microfone em um clique, e a trava do microfone: quando o macOS troca a entrada sozinho (AirPods conectando), o Crew devolve. Por evento; o volume por app só processa o som dos apps que você ajustou."
    var temAba: Bool { true }

    func iniciar() { AudioServico.shared.iniciar() }
    func parar() { AudioServico.shared.parar() }

    func aba() -> AnyView { AnyView(AudioAba()) }
    func central() -> AnyView? { AnyView(AudioCentral()) }
    func ajustes() -> AnyView? { AnyView(AudioAjustes()) }
}
