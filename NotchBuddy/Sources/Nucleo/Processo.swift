import Foundation

// Roda um programa externo sem travar o Crew: fora da main, drena saída e erro enquanto o
// programa roda (pipe cheio trava o filho), e mata se passar do tempo (TERM, depois KILL).

enum Processo {
    struct Resultado: Sendable {
        let codigo: Int32
        let saida: String
        let erro: String
        let estourouTempo: Bool
        var ok: Bool { codigo == 0 && !estourouTempo }
    }

    static func rodar(_ executavel: String, _ argumentos: [String],
                      tempoMax: TimeInterval = 30) async -> Resultado {
        await withCheckedContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: executavel)
            p.arguments = argumentos
            let out = Pipe(), err = Pipe()
            p.standardOutput = out
            p.standardError = err
            let coletor = Coletor()
            out.fileHandleForReading.readabilityHandler = { coletor.saida($0.availableData) }
            err.fileHandleForReading.readabilityHandler = { coletor.erro($0.availableData) }
            p.terminationHandler = { proc in
                out.fileHandleForReading.readabilityHandler = nil
                err.fileHandleForReading.readabilityHandler = nil
                coletor.saida(out.fileHandleForReading.readDataToEndOfFile())
                coletor.erro(err.fileHandleForReading.readDataToEndOfFile())
                cont.resume(returning: coletor.resultado(codigo: proc.terminationStatus))
            }
            do { try p.run() } catch {
                cont.resume(returning: Resultado(codigo: -1, saida: "", erro: error.localizedDescription,
                                                 estourouTempo: false))
                return
            }
            let pid = p.processIdentifier
            DispatchQueue.global().asyncAfter(deadline: .now() + tempoMax) {
                guard p.isRunning, p.processIdentifier == pid else { return }
                coletor.marcarEstouro()
                p.terminate()
                DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                    if p.isRunning { kill(pid, SIGKILL) }
                }
            }
        }
    }

    private final class Coletor: @unchecked Sendable {
        private let trava = NSLock()
        private var dadosSaida = Data(), dadosErro = Data(), estouro = false
        func saida(_ d: Data) { trava.lock(); dadosSaida.append(d); trava.unlock() }
        func erro(_ d: Data) { trava.lock(); dadosErro.append(d); trava.unlock() }
        func marcarEstouro() { trava.lock(); estouro = true; trava.unlock() }
        func resultado(codigo: Int32) -> Resultado {
            trava.lock(); defer { trava.unlock() }
            return Resultado(codigo: codigo, saida: String(decoding: dadosSaida, as: UTF8.self),
                             erro: String(decoding: dadosErro, as: UTF8.self), estourouTempo: estouro)
        }
    }
}
