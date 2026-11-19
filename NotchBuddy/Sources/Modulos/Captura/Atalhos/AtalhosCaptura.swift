import AppKit
import Carbon.HIToolbox

// Atalhos globais da Captura. `RegisterEventHotKey` do Carbon: não precisa de Acessibilidade e
// não lê o teclado — o macOS só avisa quando a combinação exata é apertada. Cada atalho tem a
// combinação que o Hugo escolher e pode ser desligado sozinho.

/// Uma combinação de teclas (código da tecla + modificadores no formato do Carbon).
struct Combinacao: Equatable, Sendable {
    var tecla: UInt32
    var modificadores: UInt32
    /// Nome da tecla para mostrar ("4", "A", "F6", "Espaço").
    var nomeTecla: String

    static let base = UInt32(controlKey | optionKey | cmdKey)

    static func padrao(_ modo: ModoCaptura) -> Combinacao {
        switch modo {
        case .area: Combinacao(tecla: UInt32(kVK_ANSI_4), modificadores: base, nomeTecla: "4")
        case .janela: Combinacao(tecla: UInt32(kVK_ANSI_5), modificadores: base, nomeTecla: "5")
        case .tela: Combinacao(tecla: UInt32(kVK_ANSI_3), modificadores: base, nomeTecla: "3")
        case .texto: Combinacao(tecla: UInt32(kVK_ANSI_2), modificadores: base, nomeTecla: "2")
        }
    }

    /// "⌃⌥⌘4" — na ordem em que o macOS escreve.
    var rotulo: String {
        var s = ""
        if modificadores & UInt32(controlKey) != 0 { s += "⌃" }
        if modificadores & UInt32(optionKey) != 0 { s += "⌥" }
        if modificadores & UInt32(shiftKey) != 0 { s += "⇧" }
        if modificadores & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + nomeTecla
    }

    /// Da tecla apertada no gravador. nil = não serve (sem ⌃, ⌥ ou ⌘ ficaria no caminho de digitar).
    @MainActor
    static func de(_ evento: NSEvent) -> Combinacao? {
        let f = evento.modifierFlags
        var m: UInt32 = 0
        if f.contains(.control) { m |= UInt32(controlKey) }
        if f.contains(.option) { m |= UInt32(optionKey) }
        if f.contains(.command) { m |= UInt32(cmdKey) }
        guard m != 0 else { return nil }
        if f.contains(.shift) { m |= UInt32(shiftKey) }
        let codigo = Int(evento.keyCode)
        let especiais: [Int: String] = [
            kVK_Space: "Espaço", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
            kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_LeftArrow: "←", kVK_RightArrow: "→",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        ]
        let nome: String
        if let e = especiais[codigo] {
            nome = e
        } else if let c = evento.charactersIgnoringModifiers?.uppercased(), !c.isEmpty,
                  c.unicodeScalars.allSatisfy({ $0.value > 0x20 && $0.value != 0x7F && !(0xF700...0xF8FF).contains($0.value) }) {
            nome = c
        } else {
            return nil
        }
        return Combinacao(tecla: UInt32(codigo), modificadores: m, nomeTecla: nome)
    }
}

@MainActor
final class AtalhosCaptura {
    private static let assinatura: OSType = 0x4372_7743   // "CrwC"

    private var refs: [EventHotKeyRef] = []
    private var tratador: EventHandlerRef?
    private let acao: (ModoCaptura) -> Void
    /// Atalhos que o macOS recusou (outro app já usa a combinação).
    private(set) var recusados: Set<ModoCaptura> = []

    init(acao: @escaping (ModoCaptura) -> Void) { self.acao = acao }

    /// Registra exatamente estes (os que não vierem ficam desligados).
    func aplicar(_ combinacoes: [ModoCaptura: Combinacao]) {
        desligar()
        guard !combinacoes.isEmpty else { return }
        if tratador == nil {
            // No alvo do despachante (antes do alvo do app): o tratador de atalhos de outro módulo
            // responde "tratado" para tudo e, instalado depois, engoliria os daqui.
            var tipo = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let eu = Unmanaged.passUnretained(self).toOpaque()
            InstallEventHandler(GetEventDispatcherTarget(), atalhosCapturaEvento, 1, &tipo, eu, &tratador)
        }
        for (i, modo) in ModoCaptura.allCases.enumerated() {
            guard let c = combinacoes[modo] else { continue }
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.assinatura, id: UInt32(i + 1))
            if RegisterEventHotKey(c.tecla, c.modificadores, id, GetEventDispatcherTarget(), 0, &ref) == noErr, let ref {
                refs.append(ref)
            } else {
                recusados.insert(modo)
            }
        }
    }

    func desligar() {
        for r in refs { UnregisterEventHotKey(r) }
        refs.removeAll()
        recusados = []
    }

    fileprivate func disparou(_ id: UInt32) {
        let i = Int(id) - 1
        if ModoCaptura.allCases.indices.contains(i) { acao(ModoCaptura.allCases[i]) }
    }

    fileprivate static func assinaturaOK(_ s: OSType) -> Bool { s == assinatura }
}

/// Tratador C do Carbon. Os eventos de atalho chegam na thread principal.
private func atalhosCapturaEvento(_: EventHandlerCallRef?, _ evento: EventRef?, _ dados: UnsafeMutableRawPointer?) -> OSStatus {
    guard let evento, let dados else { return OSStatus(eventNotHandledErr) }
    var hk = EventHotKeyID()
    let st = GetEventParameter(evento, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                               nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
    guard st == noErr else { return st }
    let id = hk.id, assinatura = hk.signature
    // De outro módulo (o Áudio tem os dele): deixa passar para o tratador certo.
    guard assinatura == 0x4372_7743 else { return OSStatus(eventNotHandledErr) }
    let ptr = UInt(bitPattern: dados)
    MainActor.assumeIsolated {
        guard AtalhosCaptura.assinaturaOK(assinatura),
              let raw = UnsafeMutableRawPointer(bitPattern: ptr) else { return }
        Unmanaged<AtalhosCaptura>.fromOpaque(raw).takeUnretainedValue().disparou(id)
    }
    return noErr
}
