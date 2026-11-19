import Foundation
import Observation

/// Sugestões do próximo pedido, por sessão e resposta. Geradas fora do ciclo de vida da tela
/// do chat (antes a tela se redesenhava e cancelava o pedido ao modelo em ~0,1 s).
@Observable @MainActor
final class SugestoesChat {
    static let shared = SugestoesChat()
    private(set) var porChave: [String: String] = [:]
    @ObservationIgnored private var pedindo: Set<String> = []

    /// Chave estável: sessão + resposta. Só gera uma vez por resposta.
    static func chave(_ t: AgentTask) -> String? {
        guard let r = t.delivery, !r.isEmpty, ![.working, .thinking, .searching].contains(t.state) else { return nil }
        return "\(t.id)|\(r.count)|\(r.suffix(40))"
    }

    func sugestao(_ t: AgentTask?) -> String? {
        guard let t, let k = Self.chave(t) else { return nil }
        return porChave[k]
    }

    func pedir(_ t: AgentTask?) {
        guard let t, let k = Self.chave(t), porChave[k] == nil, !pedindo.contains(k),
              Ajustes.bool("sessoes", "sugestao", padrao: true), IAdoMac.disponivel,
              let resposta = t.delivery else { return }
        pedindo.insert(k)
        let pedido = t.lastPrompt
        Task {
            let s = await IAdoMac.proximoPedido(pedido: pedido, resposta: resposta)
            pedindo.remove(k)
            if let s { porChave[k] = s }
            if porChave.count > 40 { porChave.removeAll() }
        }
    }
}
