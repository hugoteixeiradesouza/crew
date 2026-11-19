import Foundation

// O servidor de fala do motor (tts-server do omnivoice.cpp): liga no primeiro pedido (ou quando
// alguém pede para aquecer), guarda o modelo na memória (~1,05 GB) enquanto há uso e desliga
// sozinho depois de um tempo parado — ou antes, se o macOS avisar que a memória apertou.
// Só escuta em 127.0.0.1, numa porta livre escolhida na hora. Sem relógio: o desligamento é um
// disparo único, remarcado a cada uso; parado, o processo fica em 0 % de CPU esperando conexão.
//
// Medido neste Mac (M2, 16 GB): ligar leva de 7 a 10 s (quase tudo é o Metal compilando os
// programas de GPU do motor, a cada ligada) e registrar uma voz, 1 s. Por isso vale manter
// ligado entre uma fala e outra.

@MainActor
final class ServidorOmniVoice {
    struct Falha: Error { let texto: String }

    /// Tempo parado até o servidor ser desligado (o Hugo escolhe na tela).
    var ociosoMax: TimeInterval = 1200 { didSet { if ligado, emCurso == 0 { agendarDesligamento() } } }

    private(set) var ligado = false
    /// Avisa a tela quando liga ou desliga.
    var mudou: (@MainActor () -> Void)?

    private var processo: ProcessoVivo?
    private var porta = 0
    private var esperando: [CheckedContinuation<Void, Error>] = []
    private var registradas: Set<String> = []
    private var emCurso = 0
    private var desligamento: DispatchWorkItem?
    private var pressao: DispatchSourceMemoryPressure?
    private var ultimasLinhas: [String] = []

    private var base: String { "http://127.0.0.1:\(porta)" }

    // MARK: Ligar / desligar

    /// Garante o servidor de pé e pronto para receber pedidos.
    func ligar() async throws {
        if ligado { return }
        guard MotorOmniVoice.instalado else { throw Falha(texto: "O motor de voz humanizada não está instalado.") }
        if processo == nil {
            MotorOmniVoice.limparSobra()
            guard let p = Self.portaLivre() else { throw Falha(texto: "Não achei uma porta livre para o motor de voz.") }
            porta = p
            ultimasLinhas = []
            processo = ProcessoVivo(MotorOmniVoice.servidor.path,
                                    ["--model", MotorOmniVoice.modelo.path, "--codec", MotorOmniVoice.codec.path,
                                     "--host", "127.0.0.1", "--port", String(p), "--lang", "Portuguese"],
                                    pasta: MotorOmniVoice.pasta, ambiente: MotorOmniVoice.ambiente,
                                    linha: { [weak self] l in self?.recebeu(l, porta: p) },
                                    fim: { [weak self] _ in self?.terminou(porta: p) })
            guard processo != nil else { throw Falha(texto: "Não consegui abrir o motor de voz.") }
        }
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in esperando.append(c) }
    }

    private func recebeu(_ linha: String, porta p: Int) {
        guard p == porta, processo != nil else { return }
        if linha.hasPrefix("[Server]") || linha.contains("FATAL") || linha.lowercased().contains("error") {
            ultimasLinhas.append(linha)
            if ultimasLinhas.count > 8 { ultimasLinhas.removeFirst() }
        }
        guard !ligado, linha.contains("[Server] listening") else { return }
        // A linha sai um instante antes de a porta abrir: confirma com o /health
        Task { [weak self] in
            for _ in 0..<50 {
                guard let self, self.porta == p, self.processo != nil else { return }
                if await self.responde() { self.ficouPronto(); return }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            self?.desligar()
        }
    }

    private func responde() async -> Bool {
        guard let url = URL(string: base + "/health") else { return false }
        var r = URLRequest(url: url)
        r.timeoutInterval = 2
        guard let (_, resp) = try? await URLSession.shared.data(for: r) else { return false }
        return (resp as? HTTPURLResponse)?.statusCode == 200
    }

    private func ficouPronto() {
        ligado = true
        try? String(processo?.pid ?? 0).write(to: MotorOmniVoice.arquivoPid, atomically: true, encoding: .utf8)
        let fila = esperando
        esperando = []
        for c in fila { c.resume() }
        agendarDesligamento()
        vigiarMemoria()
        mudou?()
    }

    private func terminou(porta p: Int) {
        guard p == porta else { return }
        let detalhe = ultimasLinhas.suffix(3).joined(separator: "\n")
        soltar(Falha(texto: "O motor de voz parou." + (detalhe.isEmpty ? "" : "\n" + detalhe)))
    }

    /// Desliga agora e libera a memória do modelo.
    func desligar() {
        processo?.parar()
        soltar(Falha(texto: "O motor de voz foi desligado."))
    }

    private func soltar(_ falha: Falha) {
        desligamento?.cancel()
        desligamento = nil
        pressao?.cancel()
        pressao = nil
        processo = nil
        porta = 0
        registradas = []
        try? FileManager.default.removeItem(at: MotorOmniVoice.arquivoPid)
        let fila = esperando
        esperando = []
        for c in fila { c.resume(throwing: falha) }
        if ligado { ligado = false; mudou?() }
    }

    private func agendarDesligamento() {
        desligamento?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.emCurso == 0 else { return }
                self.desligar()
            }
        }
        desligamento = item
        DispatchQueue.main.asyncAfter(deadline: .now() + ociosoMax, execute: item)
    }

    /// Com o servidor ligado e parado, a memória do modelo é a primeira coisa a devolver quando
    /// o Mac aperta. O aviso vem do sistema (evento, sem consulta periódica).
    private func vigiarMemoria() {
        pressao?.cancel()
        let fonte = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        fonte.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.ligado, self.emCurso == 0 else { return }
                self.desligar()
            }
        }
        fonte.resume()
        pressao = fonte
    }

    // MARK: Aquecer

    /// Deixa o servidor de pé e a voz já registrada, sem falar nada: a próxima fala não paga a
    /// ligada (7 a 10 s) nem o registro da voz (1 s).
    func aquecer(_ voz: VozHumanizada?) async throws {
        try await ligar()
        emCurso += 1
        desligamento?.cancel()
        defer { emCurso -= 1; if ligado { agendarDesligamento() } }
        if let voz { try await registrar(voz) }
    }

    // MARK: Falar

    /// Gera a fala e devolve o WAV (24 kHz mono). Com `voz`, usa a identidade guardada; sem ela,
    /// desenha uma voz pelas `instrucoes` (ex.: "female, young adult, moderate pitch").
    /// `passos`: quantas voltas o motor dá para gerar (menos = mais rápido); só o servidor
    /// compilado com o ajuste do Crew obedece, o original ignora o campo e usa 32.
    func sintetizar(_ texto: String, voz: VozHumanizada?, instrucoes: String?, semente: Int?,
                    passos: Int? = nil) async throws -> Data {
        try await ligar()
        emCurso += 1
        desligamento?.cancel()
        defer { emCurso -= 1; if ligado { agendarDesligamento() } }
        var corpo: [String: Any] = ["input": texto, "response_format": "wav", "language": "Portuguese"]
        if let voz {
            try await registrar(voz)
            corpo["voice"] = voz.id
        } else if let instrucoes, !instrucoes.isEmpty {
            corpo["instructions"] = instrucoes
        }
        if let semente { corpo["seed"] = semente }
        if let passos { corpo["num_step"] = passos }
        let dados = try await enviar("/v1/audio/speech", corpo, tempoMax: 600)
        guard dados.count > 44, dados.prefix(4) == Data("RIFF".utf8) else {
            throw Falha(texto: "O motor de voz não devolveu áudio.")
        }
        return dados
    }

    /// As vozes moram na memória do servidor: cada uma é enviada uma vez por ligada.
    private func registrar(_ voz: VozHumanizada) async throws {
        guard !registradas.contains(voz.id) else { return }
        guard let wav = try? Data(contentsOf: voz.referencia) else {
            throw Falha(texto: "A voz \(voz.nome) está sem o áudio de referência.")
        }
        _ = try await enviar("/v1/audio/voices", ["name": voz.id, "ref_text": voz.textoDaReferencia,
                                                  "wav_b64": wav.base64EncodedString()], tempoMax: 120)
        registradas.insert(voz.id)
    }

    /// A voz mudou no disco (ou foi apagada): na próxima fala ela é enviada de novo.
    func esquecer(_ id: String) { registradas.remove(id) }

    private func enviar(_ caminho: String, _ corpo: [String: Any], tempoMax: TimeInterval) async throws -> Data {
        guard ligado, let url = URL(string: base + caminho) else { throw Falha(texto: "O motor de voz não está ligado.") }
        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        r.timeoutInterval = tempoMax
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONSerialization.data(withJSONObject: corpo)
        do {
            let (dados, resp) = try await URLSession.shared.data(for: r)
            let codigo = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard codigo == 200 else {
                let dito = String(decoding: dados.prefix(300), as: UTF8.self)
                throw Falha(texto: "O motor de voz recusou o pedido (\(codigo)). \(dito)")
            }
            return dados
        } catch let f as Falha {
            throw f
        } catch is CancellationError {
            throw CancellationError()
        } catch let e as URLError where e.code == .cancelled {
            throw CancellationError()
        } catch {
            throw Falha(texto: "O motor de voz não respondeu: \(error.localizedDescription)")
        }
    }

    private static func portaLivre() -> Int? {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var end = sockaddr_in()
        end.sin_family = sa_family_t(AF_INET)
        end.sin_addr.s_addr = inet_addr("127.0.0.1")
        end.sin_port = 0
        var tamanho = socklen_t(MemoryLayout<sockaddr_in>.size)
        let ok = withUnsafeMutablePointer(to: &end) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { s in
                bind(fd, s, tamanho) == 0 && getsockname(fd, s, &tamanho) == 0
            }
        }
        return ok ? Int(UInt16(bigEndian: end.sin_port)) : nil
    }
}
