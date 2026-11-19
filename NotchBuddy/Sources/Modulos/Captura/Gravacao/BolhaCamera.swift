import AppKit
import AVFoundation

// A bolha da câmera: uma janela redonda, sem borda, sempre na frente e arrastável, com a imagem
// da câmera (espelhada, como num espelho). Ela entra na gravação por estar na tela — o Crew não
// mistura vídeo nenhum. Só existe enquanto está na tela: fechada, a câmera é solta (a luz verde
// apaga) e não sobra sessão, fila nem timer.

@MainActor
final class BolhaCamera {
    static let shared = BolhaCamera()

    private var painel: NSPanel?
    private var camera: CameraDaBolha?
    private var observador: NSObjectProtocol?

    var naTela: Bool { painel != nil }

    static var permissao: AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .video) }

    /// Mostra a bolha na tela dada (ou onde ela ficou da última vez). false = sem câmera ou sem
    /// permissão; nunca dispara o pedido do macOS (isso é só pelo botão da página).
    @discardableResult
    func mostrar(lado: CGFloat, em tela: NSScreen?, camera id: String? = nil) -> Bool {
        if painel != nil { return true }
        guard Self.permissao == .authorized, let camera = CameraDaBolha(id: id) else { return false }

        let quadro = NSRect(origin: origem(lado: lado, tela: tela), size: NSSize(width: lado, height: lado))
        let p = PainelBolha(contentRect: quadro, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.isMovableByWindowBackground = true

        let vista = VistaBolha(frame: NSRect(origin: .zero, size: quadro.size))
        vista.wantsLayer = true
        let previa = AVCaptureVideoPreviewLayer(session: camera.sessao)
        previa.videoGravity = .resizeAspectFill
        previa.frame = vista.bounds
        previa.cornerRadius = lado / 2
        previa.masksToBounds = true
        previa.borderWidth = 3
        previa.borderColor = NSColor.white.withAlphaComponent(0.85).cgColor
        previa.backgroundColor = NSColor.black.cgColor
        if let ligacao = previa.connection, ligacao.isVideoMirroringSupported {
            ligacao.automaticallyAdjustsVideoMirroring = false
            ligacao.isVideoMirrored = true
        }
        vista.layer?.addSublayer(previa)
        vista.toolTip = "Arraste para mudar de lugar"
        p.contentView = vista
        p.orderFrontRegardless()

        observador = NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: p, queue: .main) { _ in
            MainActor.assumeIsolated { BolhaCamera.shared.guardarLugar() }
        }
        self.painel = p
        self.camera = camera
        camera.ligar()
        return true
    }

    func fechar() {
        if let observador { NotificationCenter.default.removeObserver(observador) }
        observador = nil
        camera?.desligar()
        camera = nil
        painel?.orderOut(nil)
        painel?.contentView = nil
        painel = nil
    }

    // MARK: Lugar

    private func guardarLugar() {
        guard let o = painel?.frame.origin else { return }
        Ajustes.definir(CapturaServico.modulo, "gravacao.bolha.x", Double(o.x))
        Ajustes.definir(CapturaServico.modulo, "gravacao.bolha.y", Double(o.y))
    }

    /// Onde ficou da última vez, se ainda cabe em alguma tela; senão, o canto de baixo à esquerda.
    private func origem(lado: CGFloat, tela: NSScreen?) -> NSPoint {
        let m = CapturaServico.modulo
        let x = Ajustes.double(m, "gravacao.bolha.x", padrao: .nan), y = Ajustes.double(m, "gravacao.bolha.y", padrao: .nan)
        if !x.isNaN, !y.isNaN {
            let r = NSRect(x: x, y: y, width: lado, height: lado)
            if NSScreen.screens.contains(where: { $0.visibleFrame.contains(r) }) { return r.origin }
        }
        let area = (tela ?? NSScreen.main)?.visibleFrame ?? .zero
        return NSPoint(x: area.minX + 28, y: area.minY + 28)
    }
}

private final class PainelBolha: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class VistaBolha: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// A sessão da câmera. Ligar e desligar demoram: vão numa fila própria, fora da main.
private final class CameraDaBolha: @unchecked Sendable {
    let sessao = AVCaptureSession()
    private let fila = DispatchQueue(label: "crew.captura.camera", qos: .userInitiated)

    /// `id` = `uniqueID` da câmera escolhida; nil (ou câmera desconectada) = a padrão do macOS.
    init?(id: String?) {
        guard let aparelho = id.flatMap({ AVCaptureDevice(uniqueID: $0) }) ?? AVCaptureDevice.default(for: .video),
              let entrada = try? AVCaptureDeviceInput(device: aparelho),
              sessao.canAddInput(entrada) else { return nil }
        sessao.sessionPreset = .high
        sessao.addInput(entrada)
    }

    func ligar() {
        fila.async { [self] in
            if !sessao.isRunning { sessao.startRunning() }
        }
    }

    func desligar() {
        fila.async { [self] in
            if sessao.isRunning { sessao.stopRunning() }
        }
    }
}
