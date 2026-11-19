import SwiftUI

@MainActor
final class AppsModulo: Modulo {
    static let shared = AppsModulo()

    let id = "apps"
    let nome = "Apps"
    let icone = "app.badge.checkmark"
    let pilar = Pilar.mac
    let superficies: [Superficie] = [.ilha]
    let resumo = "Desinstalar apps com as sobras deles, achar sobras de apps já apagados e avisar na ilha quando um app é apagado. Tudo vai para a Lixeira, com confirmação."
    // O cabeçalho da ilha está cheio: só Central + aviso na ilha fechada.
    var temAba: Bool { false }

    func iniciar() { VigiaApps.aplicar() }
    func parar() { VigiaApps.aplicar(moduloLigado: false) }

    func central() -> AnyView? { AnyView(AppsCentral()) }
    func ajustes() -> AnyView? { AnyView(AppsAjustes()) }
}
