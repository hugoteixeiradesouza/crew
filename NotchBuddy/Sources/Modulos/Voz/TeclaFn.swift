import AppKit
import CoreGraphics

// Segurar a tecla Fn (Globo) para falar, de qualquer app. O Carbon não registra modificador
// sozinho, então o Fn vem de um tap de teclado só-escuta: o Crew vê a tecla e nunca a consome
// nem altera. Só existe com o ajuste "Segurar Fn" ligado; desligado, não há tap.
//
//   Fn desce sozinho        → começa a ouvir
//   Fn sobe                 → para e entrega o texto
//   outra tecla com Fn      → cancela (Fn+seta, Fn+F5… são atalhos do macOS, não ditado)
//   toque mais curto que `toqueMinimo` → cancela (esbarrão)
//
// Precisa de Acessibilidade (a mesma permissão das teclas de brilho e volume). O tap só olha
// `flagsChanged` e `keyDown`, e do `keyDown` só usa o fato de ter acontecido: nenhuma tecla é
// lida, guardada ou registrada.

@MainActor
final class TeclaFn {
    static let toqueMinimo: TimeInterval = 0.18

    private var tap: CFMachPort?
    private var fonte: CFRunLoopSource?
    private var seguro = false
    private var desceuEm = Date.distantPast
    private let apertou: () -> Void
    private let soltou: () -> Void
    private let cancelou: () -> Void
    /// O macOS não deixou criar o tap (falta Acessibilidade).
    private(set) var semPermissao = false

    init(apertou: @escaping () -> Void, soltou: @escaping () -> Void, cancelou: @escaping () -> Void) {
        self.apertou = apertou
        self.soltou = soltou
        self.cancelou = cancelou
    }

    var ligado: Bool { tap != nil }

    func ligar() {
        guard tap == nil else { return }
        let mascara = CGEventMask(1 << CGEventType.flagsChanged.rawValue) | CGEventMask(1 << CGEventType.keyDown.rawValue)
        let eu = Unmanaged.passUnretained(self).toOpaque()
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                        eventsOfInterest: mascara, callback: teclaFnEvento, userInfo: eu) else {
            semPermissao = true
            return
        }
        semPermissao = false
        tap = t
        let f = CFMachPortCreateRunLoopSource(nil, t, 0)
        fonte = f
        CFRunLoopAddSource(CFRunLoopGetMain(), f, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
    }

    func desligar() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let fonte { CFRunLoopRemoveSource(CFRunLoopGetMain(), fonte, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil
        fonte = nil
        semPermissao = false
        if seguro { seguro = false; cancelou() }
    }

    fileprivate func evento(_ tipo: CGEventType, fn: Bool, outrosModificadores: Bool) {
        switch tipo {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // O macOS desliga o tap quando acha que ele demorou: religa.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .flagsChanged:
            if fn && !seguro {
                // Fn junto de ⌘ ⌥ ⌃ ⇧ é atalho de outra coisa
                guard !outrosModificadores else { return }
                seguro = true
                desceuEm = Date()
                apertou()
            } else if !fn && seguro {
                seguro = false
                if Date().timeIntervalSince(desceuEm) < Self.toqueMinimo { cancelou() } else { soltou() }
            } else if fn && seguro && outrosModificadores {
                seguro = false
                cancelou()
            }
        case .keyDown:
            if seguro {
                seguro = false
                cancelou()
            }
        default:
            break
        }
    }
}

/// Callback C do tap (roda na thread principal: a fonte está no run loop principal).
private func teclaFnEvento(_: CGEventTapProxy, _ tipo: CGEventType, _ evento: CGEvent,
                           _ dados: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if let dados {
        let flags = evento.flags
        let fn = flags.contains(.maskSecondaryFn)
        let outros = !flags.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift]).isEmpty
        let ptr = UInt(bitPattern: dados)
        MainActor.assumeIsolated {
            guard let raw = UnsafeMutableRawPointer(bitPattern: ptr) else { return }
            Unmanaged<TeclaFn>.fromOpaque(raw).takeUnretainedValue().evento(tipo, fn: fn, outrosModificadores: outros)
        }
    }
    return Unmanaged.passUnretained(evento)
}

/// O que o macOS faz sozinho quando a tecla Fn/Globo é apertada (Ajustes do Sistema › Teclado).
/// Com qualquer coisa diferente de "Não fazer nada", o macOS executa a ação dele junto com o
/// ditado do Crew (abre emoji, troca o teclado ou liga o ditado dele).
enum AcaoDoGlobo {
    /// true = "Não fazer nada". nil = não deu para ler.
    static var livre: Bool? {
        guard let v = UserDefaults(suiteName: "com.apple.HIToolbox")?.object(forKey: "AppleFnUsageType") as? Int else { return nil }
        return v == 0
    }

    static func abrirAjustesDoTeclado() {
        if let u = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(u)
        }
    }
}
