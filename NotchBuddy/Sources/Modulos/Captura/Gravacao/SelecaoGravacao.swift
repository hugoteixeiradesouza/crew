import AppKit
import ScreenCaptureKit
import SwiftUI

// O que aparece na tela antes e durante uma gravação: a seleção de área (arrastar um retângulo),
// o seletor de janela do macOS, a moldura em volta da área gravada e a contagem regressiva.
// Tudo existe só enquanto está na tela; as janelas daqui ficam fora da gravação.

/// Painel sem borda que aceita o teclado sem ativar o Crew (o app em uso continua na frente).
private final class PainelGravacao: NSPanel {
    var aceitaTeclado = false
    override var canBecomeKey: Bool { aceitaTeclado }
    override var canBecomeMain: Bool { false }
}

@MainActor
private func painelSolto(_ quadro: NSRect, nivel: NSWindow.Level) -> PainelGravacao {
    let p = PainelGravacao(contentRect: quadro, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    p.isFloatingPanel = true
    p.level = nivel
    p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    p.backgroundColor = .clear
    p.isOpaque = false
    p.hasShadow = false
    p.hidesOnDeactivate = false
    p.isReleasedWhenClosed = false
    // Marca de "fora da gravação": o serviço tira da gravação toda janela do Crew com ela.
    p.sharingType = .none
    return p
}

// MARK: - Área

/// Seleção de área própria do Crew: escurece a tela onde o mouse está e o Hugo arrasta o
/// retângulo. Esc ou um clique sem arrastar cancela.
@MainActor
final class SeletorArea {
    static let shared = SeletorArea()

    private var painel: PainelGravacao?
    private var aoFim: ((NSScreen, CGRect)?) -> Void = { _ in }

    /// Devolve a tela e o retângulo em coordenadas globais do AppKit; nil = cancelou.
    func escolher(_ fim: @escaping ((NSScreen, CGRect)?) -> Void) {
        cancelar()
        let mouse = NSEvent.mouseLocation
        guard let tela = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else {
            fim(nil)
            return
        }
        aoFim = fim
        let p = painelSolto(tela.frame, nivel: .screenSaver)
        p.aceitaTeclado = true
        let vista = VistaSelecao(frame: NSRect(origin: .zero, size: tela.frame.size))
        vista.aoFim = { [weak self] r in
            guard let self else { return }
            let fim = self.aoFim
            self.fechar()
            // Da vista (origem embaixo à esquerda da tela) para as coordenadas globais.
            fim(r.map { (tela, $0.offsetBy(dx: tela.frame.minX, dy: tela.frame.minY)) })
        }
        p.contentView = vista
        p.makeKeyAndOrderFront(nil)
        p.makeFirstResponder(vista)
        painel = p
    }

    /// Fecha sem responder (quem chamou já sabe que cancelou).
    func cancelar() { fechar() }

    private func fechar() {
        aoFim = { _ in }
        painel?.orderOut(nil)
        painel?.contentView = nil
        painel = nil
    }
}

private final class VistaSelecao: NSView {
    var aoFim: ((CGRect?) -> Void)?
    private var inicio: CGPoint?
    private var atual: CGRect?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    override func mouseDown(with event: NSEvent) {
        inicio = convert(event.locationInWindow, from: nil)
        atual = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let inicio else { return }
        let p = convert(event.locationInWindow, from: nil)
        atual = CGRect(x: min(inicio.x, p.x), y: min(inicio.y, p.y), width: abs(inicio.x - p.x), height: abs(inicio.y - p.y))
            .intersection(bounds)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let inicio else { return }
        let r = PoliticaGravacao.retangulo(de: inicio, ate: convert(event.locationInWindow, from: nil), dentro: bounds)
        self.inicio = nil
        aoFim?(r)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { aoFim?(nil) } else { NSSound.beep() }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.32).setFill()
        bounds.fill()
        if let r = atual, r.width > 0, r.height > 0 {
            NSColor.clear.setFill()
            r.fill(using: .copy)
            NSColor.white.setStroke()
            let borda = NSBezierPath(rect: r.insetBy(dx: -0.5, dy: -0.5))
            borda.lineWidth = 1
            borda.stroke()
            rotulo("\(Int(r.width)) × \(Int(r.height))", perto: CGPoint(x: r.midX, y: r.minY - 22))
        } else {
            rotulo("Arraste sobre o que quer gravar — Esc cancela", perto: CGPoint(x: bounds.midX, y: bounds.midY))
        }
    }

    private func rotulo(_ texto: String, perto p: CGPoint) {
        let atributos: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .medium),
                                                        .foregroundColor: NSColor.white]
        let t = NSAttributedString(string: texto, attributes: atributos)
        let tam = t.size()
        var caixa = CGRect(x: p.x - tam.width / 2 - 10, y: p.y - tam.height / 2 - 5, width: tam.width + 20, height: tam.height + 10)
        caixa.origin.x = min(max(caixa.minX, 8), bounds.maxX - caixa.width - 8)
        caixa.origin.y = min(max(caixa.minY, 8), bounds.maxY - caixa.height - 8)
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: caixa, xRadius: 7, yRadius: 7).fill()
        t.draw(at: CGPoint(x: caixa.minX + 10, y: caixa.minY + 5))
    }
}

// MARK: - Janela

/// Seletor de janela do macOS (`SCContentSharingPicker`): o próprio sistema mostra as janelas e
/// devolve o filtro pronto. O Crew não lista nem lê janela nenhuma.
@MainActor
final class SeletorJanela: NSObject, SCContentSharingPickerObserver {
    static let shared = SeletorJanela()

    private var aoFim: ((SCContentFilter?, String?) -> Void)?

    /// Devolve o filtro da janela escolhida; (nil, nil) = cancelou; (nil, motivo) = não abriu.
    func escolher(_ fim: @escaping (SCContentFilter?, String?) -> Void) {
        cancelar()
        aoFim = fim
        let seletor = SCContentSharingPicker.shared
        var c = SCContentSharingPickerConfiguration()
        c.allowedPickerModes = [.singleWindow]
        seletor.defaultConfiguration = c
        seletor.add(self)
        seletor.isActive = true
        seletor.present(using: .window)
    }

    /// Fecha sem responder.
    func cancelar() {
        guard aoFim != nil else { return }
        aoFim = nil
        soltar()
    }

    private func soltar() {
        let seletor = SCContentSharingPicker.shared
        seletor.remove(self)
        seletor.isActive = false
    }

    private func responder(_ filtro: SCContentFilter?, _ motivo: String?) {
        guard let fim = aoFim else { return }
        aoFim = nil
        soltar()
        fim(filtro, motivo)
    }

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        Task { @MainActor in self.responder(nil, nil) }
    }

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        let caixa = UncheckedSendable(filter)
        Task { @MainActor in self.responder(caixa.valor, nil) }
    }

    nonisolated func contentSharingPickerStartDidFailWithError(_ error: any Error) {
        let motivo = error.localizedDescription
        Task { @MainActor in self.responder(nil, motivo) }
    }
}

// MARK: - Moldura e contagem

/// Durante a gravação de uma área: um traço fino em volta do que está sendo gravado. Não recebe
/// clique e não entra na gravação.
@MainActor
final class MolduraArea {
    static let shared = MolduraArea()
    private var painel: PainelGravacao?

    func mostrar(_ area: CGRect) {
        fechar()
        let folga: CGFloat = 4
        let p = painelSolto(area.insetBy(dx: -folga, dy: -folga), nivel: .statusBar)
        p.ignoresMouseEvents = true
        p.contentView = NSHostingView(rootView:
            Rectangle().strokeBorder(Color(hex: "#F4505E"), style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                .padding(1))
        p.orderFrontRegardless()
        painel = p
    }

    func fechar() {
        painel?.orderOut(nil)
        painel?.contentView = nil
        painel = nil
    }
}

/// 3 · 2 · 1 no meio da tela que vai ser gravada. Some antes de a gravação começar.
@MainActor
final class PainelContagem {
    static let shared = PainelContagem()
    private var painel: PainelGravacao?

    func mostrar(_ n: Int, no centro: CGPoint) {
        let lado: CGFloat = 148
        if painel == nil {
            let p = painelSolto(NSRect(x: centro.x - lado / 2, y: centro.y - lado / 2, width: lado, height: lado), nivel: .screenSaver)
            p.ignoresMouseEvents = true
            p.orderFrontRegardless()
            painel = p
        }
        painel?.contentView = NSHostingView(rootView:
            VStack(spacing: 2) {
                Text("gravando em").font(.system(size: 11, weight: .medium)).opacity(0.7)
                Text("\(n)").font(.system(size: 76, weight: .semibold, design: .rounded)).monospacedDigit()
            }
            .foregroundColor(.white)
            .frame(width: lado, height: lado)
            .background(Color.black.opacity(0.78))
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous)))
    }

    func fechar() {
        painel?.orderOut(nil)
        painel?.contentView = nil
        painel = nil
    }
}
