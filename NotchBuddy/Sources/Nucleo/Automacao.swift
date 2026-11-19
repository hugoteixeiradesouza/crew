import Foundation

// Endereços crew:// — o Crew controlável de fora (Atalhos do macOS, scripts, o próprio Claude Code
// com `open crew://…`). Ver docs/ARQUITETURA.md §1 (superfície Automação).
//
//   crew://ilha                    abre a ilha (visão geral)
//   crew://ilha/<modulo>           abre a ilha na aba do módulo (ex.: crew://ilha/sistema)
//   crew://central                 abre a Central
//   crew://central/<modulo>        abre a Central na página do módulo
//   crew://<modulo>/<acao>?k=v     ação do próprio módulo (Modulo.executar)
//
// Regra: nada destrutivo por endereço. Ação que apaga/move/desinstala só com clique na tela.

@MainActor
enum Automacao {
    private static let log = Log.de("automacao")

    static func abrir(_ url: URL) {
        guard url.scheme == "crew" else { return }
        let alvo = url.host() ?? ""
        let partes = url.pathComponents.filter { $0 != "/" }
        var params: [String: String] = [:]
        for q in URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [] { params[q.name] = q.value ?? "" }
        log.info("crew:// \(url.absoluteString, privacy: .public)")

        switch alvo {
        case "ilha":
            NotificationCenter.default.post(name: .abrirIlha, object: partes.first)
        case "central":
            Central.abrir(modulo: partes.first)
        default:
            guard let m = Registro.shared.modulo(alvo), Registro.shared.estaLigado(alvo) else {
                log.error("crew://: módulo desconhecido ou desligado: \(alvo, privacy: .public)")
                return
            }
            if !m.executar(partes.first ?? "", params) {
                log.error("crew://: ação não entendida: \(url.absoluteString, privacy: .public)")
            }
        }
    }
}

extension Notification.Name {
    /// Abre a ilha. `object`: id do módulo (String) para abrir na aba dele; nil = visão geral.
    static let abrirIlha = Notification.Name("crew.abrirIlha")
}

/// Caixa para passar um valor não-Sendable (ex.: [String: Any] de JSON) entre threads quando quem
/// envia não toca mais nele.
struct UncheckedSendable<T>: @unchecked Sendable {
    let valor: T
    init(_ v: T) { valor = v }
}
