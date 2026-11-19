import Foundation

// Tamanho de pastas com `du -sk`, em lotes e com limite de processos ao mesmo tempo.
// Aqui o `du` roda pelo `Processo.rodar` do núcleo (fora da main, drena a saída, mata se travar).

enum Tamanhos {
    static let caminhosPorLote = 64
    /// `du` é limitado pelo disco, não pela CPU: poucos ao mesmo tempo bastam.
    static let lotesSimultaneos = 4
    /// Um lote que anda numa árvore funda pode levar minutos; isto só impede travar para sempre.
    static let tempoMaxLote: TimeInterval = 300

    /// Bytes por caminho (`standardizedFileURL.path`). Caminho sem leitura fica de fora
    /// (diferente de 0, que é "li e está vazio").
    static func medir(_ urls: [URL]) async -> [String: Int64] {
        guard !urls.isEmpty else { return [:] }
        var lotes: [[String]] = []
        let caminhos = urls.map { $0.standardizedFileURL.path }
        var i = 0
        while i < caminhos.count {
            lotes.append(Array(caminhos[i..<min(i + caminhosPorLote, caminhos.count)]))
            i += caminhosPorLote
        }
        var res: [String: Int64] = [:]
        await withTaskGroup(of: [String: Int64].self) { g in
            var it = lotes.makeIterator()
            var rodando = 0
            func proximo() {
                guard let lote = it.next() else { return }
                rodando += 1
                g.addTask { await medirLote(lote) }
            }
            for _ in 0..<min(lotesSimultaneos, lotes.count) { proximo() }
            while rodando > 0, let parcial = await g.next() {
                rodando -= 1
                res.merge(parcial) { $1 }
                if Task.isCancelled { g.cancelAll(); break }
                proximo()
            }
        }
        return res
    }

    private static func medirLote(_ lote: [String]) async -> [String: Int64] {
        if Task.isCancelled { return [:] }
        // `du` escreve uma linha por pasta negada e sai com erro; a saída parcial vale.
        let r = await Processo.rodar("/usr/bin/du", ["-sk"] + lote, tempoMax: tempoMaxLote)
        var res: [String: Int64] = [:]
        for linha in r.saida.split(separator: "\n") {
            guard let tab = linha.firstIndex(of: "\t"), let kb = Int64(linha[..<tab]) else { continue }
            res[String(linha[linha.index(after: tab)...])] = kb * 1024
        }
        return res
    }
}
