import Foundation

// "Gravação de Áudio do Sistema" (TCC `kTCCServiceAudioCapture`): o macOS exige para criar um
// process tap. Não há API pública para saber o estado nem para pedir sem criar um tap — e criar
// o tap antes de ter a permissão seria perigoso: com o pedido na tela (ou negado) o tap entrega
// silêncio e o app ficaria mudo. Por isso o estado e o pedido usam a SPI `TCCAccessPreflight` /
// `TCCAccessRequest` do TCC.framework (privado, via dlopen). Se ela sumir numa versão do macOS,
// o estado vira "desconhecido" e o Crew cria o tap direto (o macOS pede na hora).

enum PermissaoCaptura: Equatable, Sendable {
    case concedida, negada, naoPerguntada, desconhecida

    private typealias Preflight = @convention(c) (CFString, CFDictionary?) -> Int
    private typealias Pedido = @convention(c) (CFString, CFDictionary?, @escaping @convention(block) (Bool) -> Void) -> Void

    private nonisolated(unsafe) static let tcc: UnsafeMutableRawPointer? =
        dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW)
    private static var servico: CFString { "kTCCServiceAudioCapture" as CFString }

    static func atual() -> PermissaoCaptura {
        guard let tcc, let s = dlsym(tcc, "TCCAccessPreflight") else { return .desconhecida }
        switch unsafeBitCast(s, to: Preflight.self)(servico, nil) {
        case 0: return .concedida
        case 1: return .negada
        default: return .naoPerguntada
        }
    }

    /// Mostra o pedido do macOS. `pronto` volta na main com o estado novo.
    static func pedir(_ pronto: @escaping @Sendable @MainActor (PermissaoCaptura) -> Void) {
        guard let tcc, let s = dlsym(tcc, "TCCAccessRequest") else {
            DispatchQueue.main.async { pronto(.desconhecida) }
            return
        }
        unsafeBitCast(s, to: Pedido.self)(servico, nil) { ok in
            DispatchQueue.main.async { pronto(ok ? .concedida : .negada) }
        }
    }

    /// Ajustes do Sistema › Privacidade › Gravação de Tela e Áudio do Sistema.
    static let urlAjustes = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")!
}
