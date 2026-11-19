import CryptoKit
import Foundation

// Duplicados nas pastas pessoais, só quando o Hugo pede.
//
// Três etapas, da mais barata para a mais cara, para quase nada ser lido:
// 1. agrupa por tamanho lógico (tamanho único não tem gêmeo, nem é aberto);
// 2. SHA-256 de amostra: tamanho + primeiros 64 KB + últimos 64 KB;
// 3. SHA-256 do arquivo inteiro, só para quem ainda empata.
// Nada é chamado de duplicado sem o hash completo igual. Hard links (mais de um nome para o
// mesmo arquivo) ficam de fora: apagar um nome não libera nada. Clones do APFS não dá para
// detectar barato — um par clonado aparece como duplicado e libera menos do que diz.

struct GrupoDuplicado: Identifiable, Sendable, Hashable {
    let id: String
    /// Caminhos, em ordem.
    let caminhos: [String]
    /// Tamanho de UMA cópia (o menor ocupado entre elas).
    let bytes: Int64
    /// Data de modificação de cada cópia quando o hash foi feito (para conferir antes de mover).
    let datas: [String: Date]
    let sugestao: String
    var recuperavel: Int64 { bytes * Int64(caminhos.count - 1) }
}

enum Duplicados {
    /// Abaixo disto não vale ler (e a busca não termina nunca em pastas cheias de miudeza).
    static let minimoBytes: Int64 = 1_000_000
    static let janela = 64 * 1024
    static let pedaco = 1 << 20
    static let simultaneos = 3

    struct Progresso: Sendable {
        let etapa: String
        let feito: Int
        let total: Int
    }

    private struct Candidato: Sendable {
        let caminho: String
        let logico: Int64
        let ocupado: Int64
        let data: Date
    }

    static func executar(acesso: AcessoVarredura, progresso: @Sendable (Progresso) async -> Void) async -> [GrupoDuplicado] {
        await progresso(Progresso(etapa: "Listando arquivos…", feito: 0, total: 0))
        var porTamanho: [Int64: [Candidato]] = [:]
        VarreduraArquivos.andar(acesso: acesso) { u, v in
            guard let logico = v.fileSize.map(Int64.init), logico >= minimoBytes else { return }
            let c = u.standardizedFileURL.path
            guard PoliticaArquivos.motivoRecusa(u, acesso: acesso) == nil, links(c) == 1 else { return }
            porTamanho[logico, default: []].append(
                Candidato(caminho: c, logico: logico, ocupado: Int64(v.totalFileAllocatedSize ?? Int(logico)),
                          data: v.contentModificationDate ?? .distantPast))
        }
        if Task.isCancelled { return [] }
        // Maiores primeiro: se cancelar no meio, o que já foi feito é o que mais importava.
        let baldes = porTamanho.filter { $0.value.count > 1 }.sorted { $0.key > $1.key }
        let totalAmostra = baldes.reduce(0) { $0 + $1.value.count }

        var feitos = 0
        var empates: [[Candidato]] = []
        for (tamanho, lista) in baldes {
            if Task.isCancelled { return [] }
            await progresso(Progresso(etapa: "Comparando início e fim…", feito: feitos, total: totalAmostra))
            let porAmostra = await hashes(lista) { amostra($0.caminho, tamanho: tamanho) }
            feitos += lista.count
            empates += porAmostra.values.filter { $0.count > 1 }
        }

        let totalCompleto = empates.reduce(0) { $0 + $1.count }
        feitos = 0
        var grupos: [GrupoDuplicado] = []
        for lista in empates {
            if Task.isCancelled { return [] }
            await progresso(Progresso(etapa: "Conferindo o conteúdo inteiro…", feito: feitos, total: totalCompleto))
            let porCompleto = await hashes(lista) { completo($0.caminho) }
            feitos += lista.count
            for (h, membros) in porCompleto where membros.count > 1 {
                let caminhos = membros.map(\.caminho).sorted()
                grupos.append(GrupoDuplicado(id: h, caminhos: caminhos, bytes: membros.map(\.ocupado).min() ?? 0,
                                             datas: Dictionary(uniqueKeysWithValues: membros.map { ($0.caminho, $0.data) }),
                                             sugestao: Guardiao.sugerir(caminhos) ?? caminhos[0]))
            }
        }
        if Task.isCancelled { return [] }
        return grupos.sorted { $0.recuperavel != $1.recuperavel ? $0.recuperavel > $1.recuperavel : $0.id < $1.id }
    }

    /// Hash de cada candidato, `simultaneos` por vez. Quem falha na leitura sai (não dá para provar cópia).
    private static func hashes(_ lista: [Candidato], _ h: @escaping @Sendable (Candidato) -> String?) async -> [String: [Candidato]] {
        var res: [String: [Candidato]] = [:]
        var i = 0
        while i < lista.count {
            if Task.isCancelled { return [:] }
            let lote = Array(lista[i..<min(i + simultaneos, lista.count)])
            i += simultaneos
            await withTaskGroup(of: (Candidato, String?).self) { g in
                for c in lote { g.addTask { (c, h(c)) } }
                for await (c, d) in g { if let d { res[d, default: []].append(c) } }
            }
        }
        return Task.isCancelled ? [:] : res
    }

    static func links(_ caminho: String) -> Int {
        ((try? FileManager.default.attributesOfItem(atPath: caminho))?[.referenceCount] as? NSNumber)?.intValue ?? 1
    }

    /// Tamanho + primeiros 64 KB + últimos 64 KB. Erro de leitura abandona (nunca vira "vazio").
    static func amostra(_ caminho: String, tamanho: Int64) -> String? {
        guard let f = FileHandle(forReadingAtPath: caminho) else { return nil }
        defer { try? f.close() }
        var h = SHA256()
        withUnsafeBytes(of: tamanho.littleEndian) { h.update(bufferPointer: $0) }
        do {
            h.update(data: try f.read(upToCount: janela) ?? Data())
            if tamanho > Int64(janela) {
                try f.seek(toOffset: UInt64(tamanho - Int64(janela)))
                h.update(data: try f.read(upToCount: janela) ?? Data())
            }
        } catch { return nil }
        return hex(h.finalize())
    }

    /// Arquivo inteiro, em pedaços de 1 MB (nunca carrega um vídeo de vários GB na memória).
    static func completo(_ caminho: String) -> String? {
        guard let f = FileHandle(forReadingAtPath: caminho) else { return nil }
        defer { try? f.close() }
        var h = SHA256()
        while true {
            if Task.isCancelled { return nil }
            let d: Data?
            do { d = try f.read(upToCount: pedaco) } catch { return nil }
            guard let d, !d.isEmpty else { break }
            h.update(data: d)
        }
        return hex(h.finalize())
    }

    private static func hex(_ d: SHA256.Digest) -> String { d.map { String(format: "%02x", $0) }.joined() }
}

/// Qual cópia manter. Só sugere: o Hugo vê e pode trocar.
/// Regras, da mais forte para a mais fraca: onde mora (lugar "de verdade" > Downloads/Mesa >
/// cache/build/lixo), o nome (`foo copy`, `foo (1)` é a cópia), menos níveis de pasta, o caminho.
enum Guardiao {
    static func sugerir(_ caminhos: [String]) -> String? {
        caminhos.min { chave($0) < chave($1) }
    }

    static func chave(_ c: String) -> (Int, Int, Int, String) {
        let base = ((c as NSString).lastPathComponent as NSString).deletingPathExtension
        return (lugar(c), nomeDeCopia(base), c.split(separator: "/").count, c)
    }

    static func lugar(_ c: String) -> Int {
        let l = c.lowercased()
        let descartaveis = ["/library/caches/", "/caches/", "/.cache/", "/deriveddata/", "/library/developer/xcode/",
                            "/node_modules/", "/.build/", "/build/", "/target/", "/.trash/", "/tmp/", "/.tmp/"]
        if descartaveis.contains(where: l.contains) { return 2 }
        if l.contains("/downloads/") || l.contains("/desktop/") { return 1 }
        return 0
    }

    static func nomeDeCopia(_ base: String) -> Int {
        let n = base.lowercased()
        let padroes = [#" copy( \d+)?$"#, #" \(\d+\)$"#, #" cópia( \d+)?$"#, #" copia( \d+)?$"#]
        return padroes.contains { n.range(of: $0, options: .regularExpression) != nil } ? 1 : 0
    }
}
