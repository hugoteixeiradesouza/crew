import AppKit
import Carbon.HIToolbox

// Atalho global da gravação de tela: o mesmo mecanismo dos atalhos de captura
// (`RegisterEventHotKey` do Carbon — não precisa de Acessibilidade e não lê o teclado), com
// assinatura própria para não se misturar com os de captura. Um atalho só: começa e para.

extension Combinacao {
    /// ⌃⌥⌘6 — na sequência dos de captura (2 texto, 3 tela, 4 área, 5 janela).
    static let padraoGravar = Combinacao(tecla: UInt32(kVK_ANSI_6), modificadores: base, nomeTecla: "6")
}

@MainActor
final class AtalhoGravar {
    fileprivate static let assinatura: OSType = 0x4372_7747   // "CrwG"

    private var ref: EventHotKeyRef?
    private var tratador: EventHandlerRef?
    private let acao: () -> Void
    /// O macOS recusou (outro app já usa a combinação).
    private(set) var recusado = false

    init(acao: @escaping () -> Void) { self.acao = acao }

    /// Registra a combinação (nil = desligado).
    func aplicar(_ c: Combinacao?) {
        desligar()
        guard let c else { return }
        if tratador == nil {
            // No alvo do despachante, como os de captura (ver `AtalhosCaptura`).
            var tipo = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let eu = Unmanaged.passUnretained(self).toOpaque()
            InstallEventHandler(GetEventDispatcherTarget(), atalhoGravarEvento, 1, &tipo, eu, &tratador)
        }
        var novo: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.assinatura, id: 1)
        if RegisterEventHotKey(c.tecla, c.modificadores, id, GetEventDispatcherTarget(), 0, &novo) == noErr, let novo {
            ref = novo
        } else {
            recusado = true
        }
    }

    func desligar() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        recusado = false
    }

    fileprivate func disparou() { acao() }
}

/// Tratador C do Carbon. Os eventos de atalho chegam na thread principal.
private func atalhoGravarEvento(_: EventHandlerCallRef?, _ evento: EventRef?, _ dados: UnsafeMutableRawPointer?) -> OSStatus {
    guard let evento, let dados else { return OSStatus(eventNotHandledErr) }
    var hk = EventHotKeyID()
    let st = GetEventParameter(evento, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                               nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
    guard st == noErr else { return st }
    // De outro atalho do Crew (captura, áudio, voz): deixa passar para o tratador certo.
    guard hk.signature == 0x4372_7747 else { return OSStatus(eventNotHandledErr) }
    let ptr = UInt(bitPattern: dados)
    MainActor.assumeIsolated {
        guard let raw = UnsafeMutableRawPointer(bitPattern: ptr) else { return }
        Unmanaged<AtalhoGravar>.fromOpaque(raw).takeUnretainedValue().disparou()
    }
    return noErr
}
