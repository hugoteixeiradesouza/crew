@preconcurrency import AVFoundation
import Speech

// O microfone e o reconhecedor de UM ditado. Vive só enquanto o ditado dura: `VozServico` cria
// ao começar e solta ao terminar — parado, não existe motor de áudio, tap nem timer.
//
// Fica fora do MainActor de propósito: o tap do microfone roda na thread de áudio e a resposta
// do reconhecedor pode chegar em outra fila. Nada daqui toca em estado da tela; tudo volta para
// a main como `Evento` (valores simples), na ordem em que aconteceu.

final class CapturaVoz: @unchecked Sendable {
    enum Evento: Sendable {
        case parcial(String)
        case final(String)
        /// 0…1, para o medidor.
        case nivel(Float)
        /// Motivo legível + código do erro do reconhecedor (0 = não veio dele).
        case erro(String, codigo: Int)
    }

    enum Falha: Error {
        case semMicrofone
        case motor(String)
    }

    private let motor = AVAudioEngine()
    private var pedido: SFSpeechAudioBufferRecognitionRequest?
    private var tarefa: SFSpeechRecognitionTask?
    private var tapLigado = false

    /// Liga o microfone e começa a reconhecer. Chamado na main, com as permissões já dadas.
    /// `noMac` = exigir reconhecimento no aparelho (o áudio não sai do Mac).
    func iniciar(reconhecedor: SFSpeechRecognizer, noMac: Bool,
                 evento: @escaping @Sendable (Evento) -> Void) throws {
        let pedido = SFSpeechAudioBufferRecognitionRequest()
        pedido.shouldReportPartialResults = true
        pedido.requiresOnDeviceRecognition = noMac
        pedido.addsPunctuation = true
        self.pedido = pedido

        let entrada = motor.inputNode
        let formato = entrada.outputFormat(forBus: 0)
        guard formato.sampleRate > 0, formato.channelCount > 0 else { throw Falha.semMicrofone }

        // Thread de áudio: entrega o buffer ao reconhecedor e mede o nível. Sem lock nem estado.
        let caixa = UncheckedSendable(pedido)
        entrada.installTap(onBus: 0, bufferSize: 2048, format: formato) { buffer, _ in
            caixa.valor.append(buffer)
            evento(.nivel(CapturaVoz.nivel(buffer)))
        }
        tapLigado = true

        motor.prepare()
        do { try motor.start() } catch {
            soltarMotor()
            throw Falha.motor(error.localizedDescription)
        }

        tarefa = reconhecedor.recognitionTask(with: pedido) { resultado, erro in
            if let resultado {
                let texto = resultado.bestTranscription.formattedString
                evento(resultado.isFinal ? .final(texto) : .parcial(texto))
            } else if let erro {
                evento(.erro(erro.localizedDescription, codigo: (erro as NSError).code))
            }
        }
    }

    /// Para de ouvir e deixa o reconhecedor fechar o texto (o `.final` chega logo depois).
    func encerrar() {
        soltarMotor()
        pedido?.endAudio()
    }

    /// Larga tudo sem esperar texto final.
    func cancelar() {
        soltarMotor()
        pedido?.endAudio()
        tarefa?.cancel()
        tarefa = nil
        pedido = nil
    }

    private func soltarMotor() {
        if tapLigado {
            motor.inputNode.removeTap(onBus: 0)
            tapLigado = false
        }
        if motor.isRunning { motor.stop() }
        motor.reset()
    }

    /// Volume do buffer em 0…1 (RMS em dB, de −50 dB a −10 dB).
    private static func nivel(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let canais = buffer.floatChannelData, buffer.frameLength > 0 else { return 0 }
        let n = Int(buffer.frameLength)
        let amostras = canais[0]
        var soma: Float = 0
        for i in 0..<n { soma += amostras[i] * amostras[i] }
        let rms = (soma / Float(n)).squareRoot()
        let db = 20 * log10(max(rms, 0.000_01))
        return min(1, max(0, (db + 50) / 40))
    }
}

/// Permissões do ditado: Microfone e Reconhecimento de Fala. Ler o estado nunca mostra pedido.
enum PermissaoVoz: Equatable, Sendable {
    case concedida, negada, naoPerguntada

    static func microfone() -> PermissaoVoz {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .concedida
        case .notDetermined: .naoPerguntada
        default: .negada
        }
    }

    static func fala() -> PermissaoVoz {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: .concedida
        case .notDetermined: .naoPerguntada
        default: .negada
        }
    }

    /// Mostra o pedido do macOS para o microfone. Fora do MainActor: a resposta chega em outra fila.
    nonisolated static func pedirMicrofone() async -> Bool {
        await withCheckedContinuation { c in
            AVCaptureDevice.requestAccess(for: .audio) { ok in c.resume(returning: ok) }
        }
    }

    /// Mostra o pedido do macOS para o reconhecimento de fala.
    nonisolated static func pedirFala() async -> Bool {
        await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { estado in c.resume(returning: estado == .authorized) }
        }
    }

    static let urlMicrofone = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
    static let urlFala = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")!
}
