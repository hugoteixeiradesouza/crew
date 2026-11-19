import Foundation

// Programa externo de vida longa (instalação, renderização, servidor local de um motor): roda
// fora da main, entrega a saída linha a linha enquanto acontece e pode ser parado a qualquer
// hora. Para comando curto com resposta inteira, use `Processo.rodar`.
//
// Parar manda TERM ao grupo do processo e, se ele insistir, KILL: um motor não deixa filho órfão.

final class ProcessoVivo: @unchecked Sendable {
    private let processo = Process()
    private let trava = NSLock()
    private var resto = Data()
    private var parado = false

    /// Foi parado por `parar()` (e não porque terminou sozinho).
    var foiParado: Bool { trava.lock(); defer { trava.unlock() }; return parado }
    var rodando: Bool { processo.isRunning }
    /// Identificador do processo (0 se não chegou a abrir).
    var pid: Int32 { processo.processIdentifier }

    /// `linha` e `fim` chegam na fila principal. `fim` recebe o código de saída.
    @discardableResult
    init?(_ executavel: String, _ argumentos: [String], pasta: URL, ambiente: [String: String],
          linha: @escaping @MainActor (String) -> Void, fim: @escaping @MainActor (Int32) -> Void) {
        processo.executableURL = URL(fileURLWithPath: executavel)
        processo.arguments = argumentos
        processo.currentDirectoryURL = pasta
        processo.environment = ambiente
        let cano = Pipe()
        processo.standardOutput = cano
        processo.standardError = cano
        processo.standardInput = FileHandle.nullDevice
        cano.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            guard !d.isEmpty, let self else { return }
            for l in self.fatiar(d) { Task { @MainActor in linha(l) } }
        }
        processo.terminationHandler = { [weak self] p in
            cano.fileHandleForReading.readabilityHandler = nil
            let ultimas = self?.fatiar(cano.fileHandleForReading.readDataToEndOfFile(), fechar: true) ?? []
            let codigo = p.terminationStatus
            Task { @MainActor in
                for l in ultimas { linha(l) }
                fim(codigo)
            }
        }
        do { try processo.run() } catch { return nil }
    }

    /// Junta os pedaços e devolve as linhas completas (quebra em \n e em \r: barras de progresso
    /// reescrevem a mesma linha com \r).
    private func fatiar(_ d: Data, fechar: Bool = false) -> [String] {
        trava.lock(); defer { trava.unlock() }
        resto.append(d)
        var linhas: [String] = []
        while let i = resto.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
            let pedaco = resto[resto.startIndex..<i]
            resto.removeSubrange(resto.startIndex...i)
            if !pedaco.isEmpty { linhas.append(String(decoding: pedaco, as: UTF8.self)) }
        }
        if fechar, !resto.isEmpty {
            linhas.append(String(decoding: resto, as: UTF8.self))
            resto.removeAll()
        }
        return linhas
    }

    func parar() {
        trava.lock(); parado = true; trava.unlock()
        guard processo.isRunning else { return }
        let pid = processo.processIdentifier
        // Os filhos (navegador sem janela, ffmpeg) herdam o grupo: o sinal vai para todos.
        Self.sinalizarArvore(pid, SIGTERM)
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [processo] in
            if processo.isRunning { Self.sinalizarArvore(pid, SIGKILL) }
        }
    }

    /// Sinal para o processo e para os descendentes dele (via `pgrep -P`, em profundidade).
    private static func sinalizarArvore(_ pid: Int32, _ sinal: Int32) {
        for filho in filhos(de: pid) { sinalizarArvore(filho, sinal) }
        kill(pid, sinal)
    }

    private static func filhos(de pid: Int32) -> [Int32] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        p.arguments = ["-P", String(pid)]
        let cano = Pipe()
        p.standardOutput = cano
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return [] }
        let dados = cano.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: dados, as: UTF8.self).split(whereSeparator: \.isNewline).compactMap { Int32($0) }
    }
}
