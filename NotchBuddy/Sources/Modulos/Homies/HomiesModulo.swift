import SwiftUI

// Homies: quem faz, separado da sessão. Cada Homie tem nome, função, instrução e uma pasta
// própria (guia, MCPs, skills, notas); a sessão é uma conversa com ele.
// Ver docs/ARQUITETURA.md (Homies).

@MainActor
final class HomiesModulo: Modulo {
    static let shared = HomiesModulo()

    let id = HomiesServico.idModulo
    let nome = "Homies"
    let icone = "person.2.fill"
    let pilar = Pilar.ia
    let superficies: [Superficie] = [.app]
    let telaCheia = true
    let resumo = "A sua equipe: cada Homie tem uma função, uma instrução e uma pasta só dele, com os MCPs, as skills e as notas. Você conversa com ele pelo Claude Code. Nenhum abre sessão sozinho."

    func iniciar() { HomiesServico.shared.iniciar() }

    func central() -> AnyView? { AnyView(HomiesCentral()) }
}
