import SwiftUI

@MainActor
final class AgentesModulo: Modulo {
    static let shared = AgentesModulo()

    let id = "agentes"
    let nome = "Agentes"
    let icone = "arrow.triangle.branch"
    let pilar = Pilar.ia
    let resumo = "Worktrees dos agentes de IA (Claude Code, Cursor, Codex…): as órfãs, que o git já largou, e as ativas por projeto. Só varre quando você abre ou pede."
    // Sem aba na ilha (decisão do Hugo, 2026-10-05): as sessões já aparecem na ilha e as órfãs
    // são raras — é faxina eventual, mora na Central.
    var temAba: Bool { false }

    func aba() -> AnyView { AnyView(AgentesAba()) }
    func central() -> AnyView? { AnyView(AgentesCentral()) }
}
