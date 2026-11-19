import Foundation

// Qual modelo de IA cada sessão está usando. O Claude Code grava o id do modelo em cada
// resposta no transcript; aqui se lê só o fim do arquivo, e só quando ele cresceu.

@MainActor
final class ModelosSessoes: ObservableObject {
    static let shared = ModelosSessoes()

    /// Caminho do transcript → nome do modelo para ler ("Fable 5.2").
    @Published private(set) var porCaminho: [String: String] = [:]
    private var tamanhos: [String: UInt64] = [:]

    func nome(de t: AgentTask) -> String? { t.transcriptPath.flatMap { porCaminho[$0] } }

    /// Relê o modelo se o transcript mudou de tamanho desde a última vez.
    func atualizar(_ caminho: String?) async {
        guard let caminho, !CaptureTool.ativo else { return }
        let tamanho = (try? FileManager.default.attributesOfItem(atPath: caminho)[.size] as? UInt64) ?? 0
        guard tamanho > 0, tamanhos[caminho] != tamanho else { return }
        tamanhos[caminho] = tamanho
        let id = await Task.detached(priority: .utility) { Self.ler(caminho) }.value
        guard let id else { return }
        let bonito = Self.bonito(id)
        if porCaminho[caminho] != bonito { porCaminho[caminho] = bonito }
    }

    /// Id do modelo da resposta mais recente (procura do fim para o começo, em pedaços).
    nonisolated static func ler(_ caminho: String) -> String? {
        guard let fh = FileHandle(forReadingAtPath: caminho) else { return nil }
        defer { try? fh.close() }
        let fim = (try? fh.seekToEnd()) ?? 0
        let marca = Data("\"model\":\"".utf8)
        let pedaco: UInt64 = 512_000
        var ate = fim
        // No máximo 4 MB para trás: imagem em base64 pode empurrar a última resposta para longe.
        while ate > 0, fim - ate < 4_096_000 {
            let de = ate > pedaco ? ate - pedaco : 0
            try? fh.seek(toOffset: de)
            guard let dados = try? fh.read(upToCount: Int(ate - de) + 80) else { return nil }
            var busca = dados.startIndex..<dados.endIndex
            while let r = dados.range(of: marca, options: .backwards, in: busca) {
                let resto = dados[r.upperBound...].prefix(80)
                if let aspas = resto.firstIndex(of: UInt8(ascii: "\"")),
                   let id = String(data: resto[..<aspas], encoding: .utf8), id.hasPrefix("claude") {
                    return id
                }
                busca = dados.startIndex..<r.lowerBound
            }
            ate = de
        }
        return nil
    }

    /// "claude-fable-5-2" → "Fable 5.2"; "claude-opus-5-5-20261001[1m]" → "Opus 5.5".
    nonisolated static func bonito(_ id: String) -> String {
        var s = id
        if let c = s.firstIndex(of: "[") { s = String(s[..<c]) }
        var partes = s.split(separator: "-").map(String.init)
        if partes.first == "claude" { partes.removeFirst() }
        // Data no fim (8 dígitos) não é versão.
        if let u = partes.last, u.count == 8, u.allSatisfy(\.isNumber) { partes.removeLast() }
        var out: [String] = []
        var numeros: [String] = []
        func fecharNumeros() {
            if !numeros.isEmpty { out.append(numeros.joined(separator: ".")); numeros = [] }
        }
        for p in partes {
            if p.allSatisfy(\.isNumber) { numeros.append(p) } else { fecharNumeros(); out.append(p.capitalized) }
        }
        fecharNumeros()
        return out.isEmpty ? id : out.joined(separator: " ")
    }
}
