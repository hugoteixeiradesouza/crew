import SwiftUI

@MainActor
final class DiscoModulo: Modulo {
    static let shared = DiscoModulo()

    let id = "disco"
    let nome = "Disco"
    let icone = "internaldrive"
    let pilar = Pilar.mac
    var temBloco: Bool { true }
    // Na home, o lugar dele foi para o Diário (o que está em aberto); dá para trazer de volta na Central
    var blocoPorPadrao: Bool { false }
    func bloco() -> AnyView { AnyView(DiscoBloco()) }
    let resumo = "Espaço livre e limpeza segura: caches (Xcode, npm, brew, apps…), projetos parados, simuladores, arquivos grandes e duplicados. Sempre com confirmação e para a Lixeira (simuladores: definitivo). Só procura quando você pede."
    var temAba: Bool { true }

    func parar() {
        DiscoServico.shared.parar()
        ProjetosServico.shared.parar()
        SimuladoresServico.shared.parar()
        ArquivosServico.shared.parar()
    }
    func aba() -> AnyView { AnyView(DiscoAba()) }
    func central() -> AnyView? { AnyView(DiscoCentral()) }
}
