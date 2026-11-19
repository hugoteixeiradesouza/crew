import Carbon.HIToolbox
import Foundation

// Atalhos globais do volume do "app tocando agora" (desligados por padrão): ⌃⌥⌘↑ sobe,
// ⌃⌥⌘↓ desce, ⌃⌥⌘M muda/desmuda. `RegisterEventHotKey` do Carbon: não precisa de Acessibilidade,
// não lê o teclado — o macOS só avisa quando a combinação exata é apertada.

@MainActor
final class AtalhosVolume {
    enum Acao: UInt32, CaseIterable, Sendable {
        case subir = 1, descer = 2, mudo = 3

        var tecla: UInt32 {
            switch self {
            case .subir: UInt32(kVK_UpArrow)
            case .descer: UInt32(kVK_DownArrow)
            case .mudo: UInt32(kVK_ANSI_M)
            }
        }
        var rotulo: String {
            switch self {
            case .subir: "⌃⌥⌘↑  volume do app +10"
            case .descer: "⌃⌥⌘↓  volume do app −10"
            case .mudo: "⌃⌥⌘M  mudo do app"
            }
        }
    }

    static let modificadores = UInt32(controlKey | optionKey | cmdKey)
    private static let assinatura: OSType = 0x4372_7741   // "CrwA"

    private var refs: [EventHotKeyRef] = []
    private var tratador: EventHandlerRef?
    private let acao: (Acao) -> Void
    /// Ações que o macOS recusou (outro app já usa a combinação).
    private(set) var recusadas: [Acao] = []

    init(acao: @escaping (Acao) -> Void) { self.acao = acao }

    var ligados: Bool { !refs.isEmpty }

    func ligar() {
        guard refs.isEmpty else { return }
        if tratador == nil {
            var tipo = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let eu = Unmanaged.passUnretained(self).toOpaque()
            InstallEventHandler(GetApplicationEventTarget(), atalhosVolumeEvento, 1, &tipo, eu, &tratador)
        }
        recusadas = []
        for a in Acao.allCases {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.assinatura, id: a.rawValue)
            if RegisterEventHotKey(a.tecla, Self.modificadores, id, GetApplicationEventTarget(), 0, &ref) == noErr, let ref {
                refs.append(ref)
            } else {
                recusadas.append(a)
            }
        }
    }

    func desligar() {
        for r in refs { UnregisterEventHotKey(r) }
        refs.removeAll()
    }

    fileprivate func disparou(_ id: UInt32) {
        if let a = Acao(rawValue: id) { acao(a) }
    }

    fileprivate static func assinaturaOK(_ s: OSType) -> Bool { s == assinatura }
}

/// Tratador C do Carbon. Os eventos de atalho chegam na thread principal. Atalho de outro dono
/// (ex.: o segurar-para-falar da Voz) passa adiante sem ser consumido.
private func atalhosVolumeEvento(_: EventHandlerCallRef?, _ evento: EventRef?, _ dados: UnsafeMutableRawPointer?) -> OSStatus {
    guard let evento, let dados else { return OSStatus(eventNotHandledErr) }
    var hk = EventHotKeyID()
    let st = GetEventParameter(evento, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                               nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
    guard st == noErr else { return st }
    let id = hk.id, assinatura = hk.signature
    let ptr = UInt(bitPattern: dados)
    return MainActor.assumeIsolated {
        guard AtalhosVolume.assinaturaOK(assinatura),
              let raw = UnsafeMutableRawPointer(bitPattern: ptr) else { return OSStatus(eventNotHandledErr) }
        Unmanaged<AtalhosVolume>.fromOpaque(raw).takeUnretainedValue().disparou(id)
        return noErr
    }
}
