import AVFoundation
import ScreenCaptureKit

// Quem grava de verdade: um `SCStream` do ScreenCaptureKit com um `SCRecordingOutput` (macOS 15),
// que escreve o arquivo sozinho — vídeo, som do sistema e microfone. Um gravador por gravação;
// parado, não existe nada (nem stream, nem fila, nem timer). Fica fora do MainActor: o que volta
// para a tela são valores simples.

/// O que gravar e como. Só valores: atravessa para fora da main sem risco.
struct PlanoGravacao: Sendable {
    enum Origem: Sendable {
        /// A tela inteira.
        case tela(CGDirectDisplayID)
        /// Um pedaço da tela: retângulo em pontos, com a origem no canto de cima à esquerda dela.
        case area(CGDirectDisplayID, CGRect)
        /// O que o Hugo escolheu no seletor do macOS (uma janela).
        case filtro(UncheckedSendable<SCContentFilter>)
    }

    var origem: Origem
    /// Janelas do próprio Crew que não entram na gravação (a ilha, prévias, a moldura da área).
    var foraDaGravacao: [CGWindowID]
    var destino: URL
    var somDoSistema: Bool
    var microfone: Bool
    /// Qual microfone (`uniqueID` do aparelho); nil = o padrão do macOS.
    var microfoneId: String?
    var cursor: Bool
    var quadros: Int
    var leve: Bool
}

enum ErroGravacao: LocalizedError {
    case semTela

    var errorDescription: String? {
        switch self {
        case .semTela: "O macOS não entregou nenhuma tela para gravar (com a tela dormindo ou bloqueada ele não entrega)."
        }
    }
}

final class GravadorTela: NSObject, SCStreamDelegate, SCRecordingOutputDelegate, @unchecked Sendable {
    /// A gravação parou sem o Crew pedir (botão do macOS, janela fechada, erro). Com o motivo,
    /// quando é erro.
    private let aoPararSozinha: @Sendable (String?) -> Void

    private let trava = NSLock()
    private var stream: SCStream?
    private var saida: SCRecordingOutput?
    private var pediuParar = false
    private var arquivoFechado = false
    private var erroDoArquivo: String?
    private var inicio: TimeInterval?
    private var quadroDaJanela: CGRect?

    /// O instante (relógio de `ProcessInfo.systemUptime`) em que o arquivo começou a ser escrito:
    /// é o zero do vídeo, usado para dar tempo ao rastro do mouse. nil até o macOS avisar.
    var inicioDoVideo: TimeInterval? { trava.withLock { inicio } }

    /// Na gravação de janela: onde a janela estava ao começar (pontos, origem no canto de cima à
    /// esquerda da tela principal). nil nos outros alvos.
    var janelaAoComecar: CGRect? { trava.withLock { quadroDaJanela } }

    init(aoPararSozinha: @escaping @Sendable (String?) -> Void) {
        self.aoPararSozinha = aoPararSozinha
    }

    func comecar(_ plano: PlanoGravacao) async throws {
        let filtro: SCContentFilter
        switch plano.origem {
        case .filtro(let f):
            filtro = f.valor
            var quadro = filtro.contentRect
            if #available(macOS 15.2, *), let janela = filtro.includedWindows.first { quadro = janela.frame }
            trava.withLock { quadroDaJanela = quadro }
        case .tela(let id), .area(let id, _):
            let conteudo = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let tela = conteudo.displays.first(where: { $0.displayID == id }) ?? conteudo.displays.first else {
                throw ErroGravacao.semTela
            }
            let fora = Set(plano.foraDaGravacao)
            filtro = SCContentFilter(display: tela, excludingWindows: conteudo.windows.filter { fora.contains($0.windowID) })
        }

        let c = SCStreamConfiguration()
        var pontos = filtro.contentRect.size
        if case .area(_, let r) = plano.origem {
            c.sourceRect = r
            pontos = r.size
        }
        let d = PoliticaGravacao.dimensoes(pontos: pontos, escala: CGFloat(filtro.pointPixelScale), leve: plano.leve)
        c.width = d.largura
        c.height = d.altura
        c.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(1, plano.quadros)))
        c.showsCursor = plano.cursor
        c.queueDepth = 6
        c.capturesAudio = plano.somDoSistema
        // Os sons do próprio Crew (o Homie, os avisos) ficam fora da gravação.
        c.excludesCurrentProcessAudio = true
        c.captureMicrophone = plano.microfone
        if plano.microfone, let id = plano.microfoneId { c.microphoneCaptureDeviceID = id }

        let rc = SCRecordingOutputConfiguration()
        rc.outputURL = plano.destino
        rc.outputFileType = .mp4
        rc.videoCodecType = .h264

        let saida = SCRecordingOutput(configuration: rc, delegate: self)
        let stream = SCStream(filter: filtro, configuration: c, delegate: self)
        try stream.addRecordingOutput(saida)
        trava.withLock {
            self.stream = stream
            self.saida = saida
        }
        do {
            try await stream.startCapture()
        } catch {
            trava.withLock {
                self.pediuParar = true
                self.stream = nil
                self.saida = nil
            }
            throw error
        }
    }

    /// Para e espera o arquivo fechar (no máximo 6 s). Devolve o erro do arquivo, se houve.
    func parar() async -> String? {
        let stream = trava.withLock { () -> UncheckedSendable<SCStream?> in
            pediuParar = true
            return UncheckedSendable(self.stream)
        }.valor
        if let stream {
            try? await stream.stopCapture()
        }
        await esperarArquivo(limite: 6)
        return trava.withLock {
            self.stream = nil
            self.saida = nil
            return erroDoArquivo
        }
    }

    /// Depois de a gravação parar sozinha: dá tempo de o arquivo fechar.
    func esperarArquivo(limite: TimeInterval) async {
        let ate = Date().addingTimeInterval(limite)
        while !trava.withLock({ arquivoFechado }), Date() < ate {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    // MARK: SCRecordingOutputDelegate

    func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        let agora = ProcessInfo.processInfo.systemUptime
        trava.withLock { if inicio == nil { inicio = agora } }
    }

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        trava.withLock { arquivoFechado = true }
    }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        trava.withLock {
            erroDoArquivo = error.localizedDescription
            arquivoFechado = true
        }
    }

    // MARK: SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        let pedido = trava.withLock { pediuParar }
        guard !pedido else { return }
        // Parar pelo botão do macOS (barra de menus) não é erro.
        let parouPeloMac = (error as NSError).domain == SCStreamErrorDomain
            && (error as NSError).code == SCStreamError.Code.userStopped.rawValue
        aoPararSozinha(parouPeloMac ? nil : error.localizedDescription)
    }
}
