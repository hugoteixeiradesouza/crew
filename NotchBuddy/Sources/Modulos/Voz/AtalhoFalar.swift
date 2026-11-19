import Carbon.HIToolbox
import Foundation

// Atalho global de "segurar para falar" (desligado por padrão). `RegisterEventHotKey` do Carbon:
// não precisa de Acessibilidade e não lê o teclado — o macOS só avisa quando a combinação exata
// é apertada e quando é solta.

@MainActor
final class AtalhoFalar {
    /// Combinações oferecidas (todas com Espaço).
    enum Combinacao: String, CaseIterable, Identifiable, Sendable {
        case controleOpcao, controleOpcaoComando, opcaoComando
        var id: String { rawValue }

        var modificadores: UInt32 {
            switch self {
            case .controleOpcao: UInt32(controlKey | optionKey)
            case .controleOpcaoComando: UInt32(controlKey | optionKey | cmdKey)
            case .opcaoComando: UInt32(optionKey | cmdKey)
            }
        }
        var rotulo: String {
            switch self {
            case .controleOpcao: "⌃⌥ Espaço"
            case .controleOpcaoComando: "⌃⌥⌘ Espaço"
            case .opcaoComando: "⌥⌘ Espaço"
            }
        }
    }

    private static let assinatura: OSType = 0x4372_7756   // "CrwV"
    private static let idTecla: UInt32 = 1

    private var ref: EventHotKeyRef?
    private var tratador: EventHandlerRef?
    private let apertou: () -> Void
    private let soltou: () -> Void
    /// O macOS recusou a combinação (outro app já usa).
    private(set) var recusado = false

    init(apertou: @escaping () -> Void, soltou: @escaping () -> Void) {
        self.apertou = apertou
        self.soltou = soltou
    }

    var ligado: Bool { ref != nil }

    func ligar(_ combinacao: Combinacao) {
        desligar()
        if tratador == nil {
            var tipos = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                         EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
            let eu = Unmanaged.passUnretained(self).toOpaque()
            InstallEventHandler(GetApplicationEventTarget(), atalhoFalarEvento, tipos.count, &tipos, eu, &tratador)
        }
        var novo: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.assinatura, id: Self.idTecla)
        let st = RegisterEventHotKey(UInt32(kVK_Space), combinacao.modificadores, id, GetApplicationEventTarget(), 0, &novo)
        ref = st == noErr ? novo : nil
        recusado = ref == nil
    }

    /// Solta a combinação e o tratador: desligado, o Crew não recebe nada do teclado por aqui.
    func desligar() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        recusado = false
        if let tratador { RemoveEventHandler(tratador) }
        tratador = nil
    }

    fileprivate func evento(apertado: Bool) {
        if apertado { apertou() } else { soltou() }
    }

    fileprivate static func ehMeu(_ hk: EventHotKeyID) -> Bool { hk.signature == assinatura && hk.id == idTecla }
}

/// Tratador C do Carbon (thread principal). Atalho de outro dono (ex.: os do volume por app)
/// passa adiante sem ser consumido.
private func atalhoFalarEvento(_: EventHandlerCallRef?, _ evento: EventRef?, _ dados: UnsafeMutableRawPointer?) -> OSStatus {
    guard let evento, let dados else { return OSStatus(eventNotHandledErr) }
    var hk = EventHotKeyID()
    let st = GetEventParameter(evento, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                               nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
    guard st == noErr else { return OSStatus(eventNotHandledErr) }
    let apertado = GetEventKind(evento) == UInt32(kEventHotKeyPressed)
    let ptr = UInt(bitPattern: dados)
    let chave = hk
    return MainActor.assumeIsolated {
        guard AtalhoFalar.ehMeu(chave), let raw = UnsafeMutableRawPointer(bitPattern: ptr) else {
            return OSStatus(eventNotHandledErr)
        }
        Unmanaged<AtalhoFalar>.fromOpaque(raw).takeUnretainedValue().evento(apertado: apertado)
        return noErr
    }
}
