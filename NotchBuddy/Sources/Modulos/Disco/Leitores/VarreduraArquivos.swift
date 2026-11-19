import Foundation

// Arquivos grandes nas pastas pessoais.
// Só lê metadados (tamanho e datas); nunca abre um arquivo. Roda fora da main.

struct ArquivoGrande: Identifiable, Sendable, Hashable {
    var id: String { caminho }
    let caminho: String
    /// Espaço ocupado no disco (o que a Lixeira devolve quando esvaziada).
    let bytes: Int64
    /// O maior entre o último acesso e a última modificação.
    let ultimoUso: Date
    var nome: String { (caminho as NSString).lastPathComponent }
    var pasta: String { ((caminho as NSString).deletingLastPathComponent as NSString).abbreviatingWithTildeInPath }
}

enum VarreduraArquivos {
    static let chaves: Set<URLResourceKey> = [
        .isRegularFileKey, .isDirectoryKey, .isPackageKey, .isSymbolicLinkKey,
        .totalFileAllocatedSizeKey, .fileSizeKey, .contentAccessDateKey, .contentModificationDateKey,
    ]

    /// Anda nas raízes e entrega cada arquivo comum (`visitar`), pulando o que a política exclui.
    /// Devolve quantos arquivos foram vistos.
    @discardableResult
    static func andar(acesso: AcessoVarredura, visitar: (URL, URLResourceValues) -> Void) -> Int {
        var vistos = 0
        for raiz in PoliticaArquivos.raizes(acesso: acesso) {
            if Task.isCancelled { break }
            guard existeSemSeguir(raiz),
                  let e = FileManager.default.enumerator(at: raiz, includingPropertiesForKeys: Array(chaves),
                                                         options: [.skipsHiddenFiles, .skipsPackageDescendants],
                                                         errorHandler: { _, _ in true }) else { continue }
            var parar = false
            while !parar {
                autoreleasepool {
                    for _ in 0..<256 {
                        guard let u = e.nextObject() as? URL, !Task.isCancelled else { parar = true; return }
                        guard let v = try? u.resourceValues(forKeys: chaves) else { continue }
                        if v.isSymbolicLink == true { continue }
                        if v.isDirectory == true || v.isPackage == true {
                            if PoliticaArquivos.pastaExcluida(u) || !LocaisProtegidos.podeLer(u, acesso: acesso) {
                                e.skipDescendants()
                            }
                            continue
                        }
                        guard v.isRegularFile == true else { continue }
                        vistos += 1
                        visitar(u, v)
                    }
                }
            }
        }
        return vistos
    }

    /// Arquivos com pelo menos `minimo` bytes e sem uso há `diasParado` dias (0 = qualquer).
    static func executar(minimo: Int64, diasParado: Int, acesso: AcessoVarredura) -> (arquivos: [ArquivoGrande], vistos: Int) {
        let agora = Date()
        var achados: [ArquivoGrande] = []
        let vistos = andar(acesso: acesso) { u, v in
            let bytes = Int64(v.totalFileAllocatedSize ?? v.fileSize ?? 0)
            guard bytes >= minimo else { return }
            let uso = max(v.contentAccessDate ?? .distantPast, v.contentModificationDate ?? .distantPast)
            if diasParado > 0, agora.timeIntervalSince(uso) < Double(diasParado) * 86_400 { return }
            // A política inteira só para os poucos que passaram do tamanho e da idade.
            guard PoliticaArquivos.motivoRecusa(u, acesso: acesso) == nil else { return }
            achados.append(ArquivoGrande(caminho: u.standardizedFileURL.path, bytes: bytes, ultimoUso: uso))
        }
        return (achados.sorted { $0.bytes > $1.bytes }, vistos)
    }
}
