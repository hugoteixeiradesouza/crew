import CryptoKit
import Foundation

// Falas já geradas pela voz humanizada, guardadas em disco para repetir sem gerar de novo.
// Gerar uma frase curta custa segundos de GPU; tocar uma que já existe custa milésimos e nem
// precisa do motor ligado. É o que faz um aviso fixo ("crew precisa da sua aprovação.") sair
// na hora da segunda vez em diante.
//
// Uma fala = um arquivo WAV cujo nome é o resumo (SHA-256) de voz + velocidade + texto. O texto
// não fica escrito em lugar nenhum: só o áudio. A pasta tem teto de tamanho; passou, saem as
// falas usadas há mais tempo. Sem relógio e sem vigia: a limpeza roda quando uma fala entra.

struct CacheDeFala: Sendable {
    let pasta: URL
    /// Teto da pasta em bytes (24 kHz mono 16 bits = 48 kB por segundo: 60 MB ≈ 20 min de fala).
    var teto: Int64 = 60_000_000

    /// Nome do arquivo de uma fala. `voz` identifica o timbre (ver `marca(de:)`), `passos` a
    /// velocidade com que foi gerada (falas de qualidades diferentes não se misturam).
    static func chave(texto: String, voz: String, passos: Int) -> String {
        let entrada = "\(voz)\u{1F}\(passos)\u{1F}\(texto)"
        return SHA256.hash(data: Data(entrada.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// O que identifica uma voz guardada: o id e o áudio de referência (tamanho e data). Voz
    /// apagada e recriada com o mesmo nome não reaproveita as falas da antiga.
    static func marca(id: String, referencia: URL) -> String {
        let a = try? FileManager.default.attributesOfItem(atPath: referencia.path)
        let tamanho = (a?[.size] as? NSNumber)?.int64Value ?? 0
        let data = (a?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "voz:\(id):\(tamanho):\(Int(data))"
    }

    private func arquivo(_ chave: String) -> URL { pasta.appendingPathComponent(chave + ".wav") }

    func tem(_ chave: String) -> Bool { FileManager.default.fileExists(atPath: arquivo(chave).path) }

    /// A fala guardada (nil se não existe ou se o arquivo não é um WAV inteiro). Ler conta como
    /// uso: a data do arquivo anda, e ele fica por último na fila de saída.
    func ler(_ chave: String) -> Data? {
        let u = arquivo(chave)
        guard let d = try? Data(contentsOf: u), d.count > 44, d.prefix(4) == Data("RIFF".utf8) else { return nil }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: u.path)
        return d
    }

    func guardar(_ chave: String, _ wav: Data) {
        guard wav.count > 44, Int64(wav.count) < teto / 4 else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: pasta, withIntermediateDirectories: true)
        guard (try? wav.write(to: arquivo(chave), options: .atomic)) != nil else { return }
        aparar()
    }

    private func arquivos() -> [(url: URL, bytes: Int64, uso: Date)] {
        let chaves: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        let lista = (try? FileManager.default.contentsOfDirectory(at: pasta, includingPropertiesForKeys: chaves,
                                                                  options: [.skipsHiddenFiles])) ?? []
        return lista.compactMap { u in
            guard u.pathExtension == "wav", let v = try? u.resourceValues(forKeys: Set(chaves)) else { return nil }
            return (u, Int64(v.fileSize ?? 0), v.contentModificationDate ?? .distantPast)
        }
    }

    /// Passou do teto: saem as falas usadas há mais tempo, até caber.
    private func aparar() {
        var lista = arquivos()
        var total = lista.reduce(0) { $0 + $1.bytes }
        guard total > teto else { return }
        lista.sort { $0.uso < $1.uso }
        for a in lista where total > teto {
            try? FileManager.default.removeItem(at: a.url)
            total -= a.bytes
        }
    }

    /// Quantas falas há guardadas e quanto ocupam.
    func ocupacao() -> (falas: Int, bytes: Int64) {
        let lista = arquivos()
        return (lista.count, lista.reduce(0) { $0 + $1.bytes })
    }

    func limpar() { try? FileManager.default.removeItem(at: pasta) }
}
