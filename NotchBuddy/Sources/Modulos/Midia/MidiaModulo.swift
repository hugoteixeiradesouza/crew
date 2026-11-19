import SwiftUI

// O que está tocando no Spotify e no Música: aba fixa no cabeçalho e capa no canto da ilha fechada.

@MainActor
final class MidiaModulo: Modulo {
    static let shared = MidiaModulo()

    let id = "midia"
    let nome = "Música"
    let icone = "music.note"
    let pilar = Pilar.mac
    let superficies: [Superficie] = [.ilha]
    var temBloco: Bool { true }
    var blocoPorPadrao: Bool { true }
    func bloco() -> AnyView { AnyView(MidiaBloco()) }
    let resumo = "O que toca no Spotify e no Música: capa, progresso e controles na ilha; tocando, a ilha não some."
    var podeDesligar: Bool { false }
}
