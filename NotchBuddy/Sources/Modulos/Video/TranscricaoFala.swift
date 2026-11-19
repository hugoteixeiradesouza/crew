import AVFoundation
import Speech

// Legendas pela fala: transcreve o som de uma gravação NESTE Mac (nada sai dele) e devolve as
// frases com o tempo de cada palavra — é o `legendas.json` que o componente de legenda do
// projeto de vídeo lê. Usa o `SpeechAnalyzer` + `SpeechTranscriber` do macOS 26; em macOS
// anterior não há legenda (o reconhecedor antigo corta as frases no meio, medido aqui).
// Só existe enquanto transcreve: nenhum modelo fica carregado depois.

enum TranscricaoFala {
    struct Palavra: Codable, Sendable, Equatable {
        /// Segundo da gravação em que a palavra começa e termina.
        let t: Double
        let fim: Double
        let texto: String
    }

    struct Frase: Codable, Sendable, Equatable {
        let inicio: Double
        let fim: Double
        let texto: String
        let palavras: [Palavra]
    }

    struct Legendas: Codable, Sendable, Equatable {
        let idioma: String
        let frases: [Frase]

        static let vazias = Legendas(idioma: "", frases: [])

        func json() -> Data {
            let c = JSONEncoder()
            c.outputFormatting = [.prettyPrinted, .sortedKeys]
            return (try? c.encode(self)) ?? Data("{\"idioma\":\"\",\"frases\":[]}".utf8)
        }
    }

    enum Estado: Equatable, Sendable {
        /// O modelo do idioma está neste Mac: dá para transcrever.
        case pronto
        /// O Mac suporta o idioma, mas o modelo ainda não foi baixado.
        case faltaModelo
        /// Não dá neste Mac (macOS antigo ou idioma sem suporte): o motivo.
        case semSuporte(String)
    }

    struct Falha: Error, Sendable { let texto: String }

    /// Dá para transcrever neste idioma agora? Não baixa nada e não pede permissão.
    static func estado(idioma: String) async -> Estado {
        guard #available(macOS 26, *) else { return .semSuporte("As legendas pela fala pedem o macOS 26 ou mais novo.") }
        guard SpeechTranscriber.isAvailable else { return .semSuporte("Este Mac não tem o transcritor de fala da Apple.") }
        guard let local = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: idioma)) else {
            return .semSuporte("O transcritor da Apple não tem o idioma \(idioma).")
        }
        let instalados = await SpeechTranscriber.installedLocales.map { $0.identifier(.bcp47) }
        return instalados.contains(local.identifier(.bcp47)) ? .pronto : .faltaModelo
    }

    /// Baixa o modelo do idioma (da Apple, pelo sistema). Só por clique do Hugo.
    static func baixarModelo(idioma: String, andamento: @escaping @Sendable (Double) -> Void) async throws {
        guard #available(macOS 26, *) else { throw Falha(texto: "As legendas pela fala pedem o macOS 26 ou mais novo.") }
        guard let local = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: idioma)) else {
            throw Falha(texto: "O transcritor da Apple não tem o idioma \(idioma).")
        }
        let modulo = SpeechTranscriber(locale: local, transcriptionOptions: [], reportingOptions: [], attributeOptions: [.audioTimeRange])
        guard let pedido = try await AssetInventory.assetInstallationRequest(supporting: [modulo]) else { return }
        let progresso = pedido.progress
        let vigia = progresso.observe(\.fractionCompleted) { p, _ in andamento(p.fractionCompleted) }
        defer { vigia.invalidate() }
        try await pedido.downloadAndInstall()
    }

    /// Transcreve o som de `arquivo` (áudio ou vídeo: MP4, MOV, M4A, WAV…). Vídeo sem som ou
    /// sem fala devolve zero frases. `prazo` em segundos: passou disso, desiste com erro.
    static func transcrever(_ arquivo: URL, idioma: String, prazo: TimeInterval = 300) async throws -> Legendas {
        guard #available(macOS 26, *) else { throw Falha(texto: "As legendas pela fala pedem o macOS 26 ou mais novo.") }
        switch await estado(idioma: idioma) {
        case .pronto: break
        case .faltaModelo: throw Falha(texto: "Falta baixar o modelo de fala de \(idioma).")
        case .semSuporte(let motivo): throw Falha(texto: motivo)
        }
        return try await withThrowingTaskGroup(of: Legendas.self) { grupo in
            grupo.addTask { try await rodar(arquivo, idioma: idioma) }
            grupo.addTask {
                try await Task.sleep(for: .seconds(prazo))
                throw Falha(texto: "A transcrição demorou demais e foi cancelada.")
            }
            defer { grupo.cancelAll() }
            return try await grupo.next() ?? .vazias
        }
    }

    @available(macOS 26, *)
    private static func rodar(_ arquivo: URL, idioma: String) async throws -> Legendas {
        guard let local = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: idioma)) else {
            throw Falha(texto: "O transcritor da Apple não tem o idioma \(idioma).")
        }
        let som: AVAudioFile
        do { som = try AVAudioFile(forReading: arquivo) } catch {
            // Sem trilha de som (ou formato que o Core Audio não abre): não há o que legendar.
            return Legendas(idioma: local.identifier(.bcp47), frases: [])
        }
        let modulo = SpeechTranscriber(locale: local, transcriptionOptions: [], reportingOptions: [], attributeOptions: [.audioTimeRange])
        let analisador = SpeechAnalyzer(modules: [modulo])
        async let coleta = frases(de: modulo)
        do {
            if let fim = try await analisador.analyzeSequence(from: som) {
                try await analisador.finalizeAndFinish(through: fim)
            } else {
                await analisador.cancelAndFinishNow()
            }
        } catch {
            await analisador.cancelAndFinishNow()
            _ = try? await coleta
            throw Falha(texto: "A transcrição falhou: \(error.localizedDescription)")
        }
        return Legendas(idioma: local.identifier(.bcp47), frases: try await coleta)
    }

    @available(macOS 26, *)
    private static func frases(de modulo: SpeechTranscriber) async throws -> [Frase] {
        var saida: [Frase] = []
        for try await r in modulo.results {
            var palavras: [Palavra] = []
            for trecho in r.text.runs {
                guard let faixa = trecho.audioTimeRange else { continue }
                let texto = String(r.text[trecho.range].characters).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !texto.isEmpty else { continue }
                palavras.append(Palavra(t: arredondar(faixa.start.seconds), fim: arredondar(faixa.end.seconds), texto: texto))
            }
            let texto = String(r.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !texto.isEmpty else { continue }
            saida.append(Frase(inicio: arredondar(palavras.first?.t ?? r.range.start.seconds),
                               fim: arredondar(palavras.last?.fim ?? r.range.end.seconds), texto: texto, palavras: palavras))
        }
        return saida.sorted { $0.inicio < $1.inicio }
    }

    private static func arredondar(_ v: Double) -> Double { (v * 1000).rounded() / 1000 }
}
