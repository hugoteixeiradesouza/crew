import Carbon.HIToolbox
import Foundation

// O atalho global que abre o comando universal. `RegisterEventHotKey` do Carbon: não precisa de
// Acessibilidade e não lê o teclado — o macOS só avisa quando a combinação exata é apertada.
// Não depende da barra de menus: vale com qualquer app na frente.

@MainActor
final class AtalhoComando {
    fileprivate static let assinatura: OSType = 0x4372_774B   // "CrwK"

    private var ref: EventHotKeyRef?
    private var tratador: EventHandlerRef?
    private let acao: () -> Void

    init(acao: @escaping () -> Void) { self.acao = acao }

    /// Registra a combinação. false = o macOS recusou (outro app já usa).
    @discardableResult
    func ligar(_ c: Combinacao) -> Bool {
        desligar()
        if tratador == nil {
            // No alvo do despachante (antes do alvo do app), como os atalhos da Captura: um
            // tratador de outro módulo instalado no app não engole os daqui.
            var tipo = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let eu = Unmanaged.passUnretained(self).toOpaque()
            InstallEventHandler(GetEventDispatcherTarget(), atalhoComandoEvento, 1, &tipo, eu, &tratador)
        }
        var novo: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.assinatura, id: 1)
        let st = RegisterEventHotKey(c.tecla, c.modificadores, id, GetEventDispatcherTarget(), 0, &novo)
        ref = st == noErr ? novo : nil
        return ref != nil
    }

    /// Solta a combinação e o tratador: desligado, o Crew não recebe nada do teclado por aqui.
    func desligar() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        if let tratador { RemoveEventHandler(tratador) }
        tratador = nil
    }

    fileprivate func disparou() { acao() }
}

/// Tratador C do Carbon (thread principal). Atalho de outro dono passa adiante sem ser consumido.
private func atalhoComandoEvento(_: EventHandlerCallRef?, _ evento: EventRef?, _ dados: UnsafeMutableRawPointer?) -> OSStatus {
    guard let evento, let dados else { return OSStatus(eventNotHandledErr) }
    var hk = EventHotKeyID()
    let st = GetEventParameter(evento, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                               nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
    guard st == noErr, hk.signature == 0x4372_774B else { return OSStatus(eventNotHandledErr) }
    let ptr = UInt(bitPattern: dados)
    MainActor.assumeIsolated {
        guard let raw = UnsafeMutableRawPointer(bitPattern: ptr) else { return }
        Unmanaged<AtalhoComando>.fromOpaque(raw).takeUnretainedValue().disparou()
    }
    return noErr
}
