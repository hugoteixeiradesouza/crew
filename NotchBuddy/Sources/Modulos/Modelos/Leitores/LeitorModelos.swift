import Foundation

// Acha os modelos de IA baixados neste Mac e os mostra como modelos, não como arquivos.
//
// Lista também os modelos que não liberam nada sozinhos (pesos compartilhados),
// soma o total em disco sem contar duas vezes o que é compartilhado, usa a data de
// modificação (não a de acesso) e mantém o servidor no nome quando não é o registro padrão
// do Ollama (`hf.co/…`), porque é esse o nome que o `ollama rm` entende.
//
// O Ollama guarda blobs endereçados por conteúdo (`blobs/sha256-4c27e0…`): listar os arquivos
// mostraria nomes hexadecimais e deixaria quebrar um modelo sem o Ollama perceber (o manifesto
// continuaria dizendo que ele está instalado). E os blobs são compartilhados entre modelos:
// o que um modelo libera de verdade são só os blobs que nenhum outro manifesto usa.

struct ModeloLocal: Identifiable, Sendable, Hashable {
    /// Caminho do manifesto (Ollama) ou da pasta do modelo (LM Studio).
    let id: String
    let nome: String
    let origem: PoliticaModelos.Origem
    /// Tudo o que o modelo usa, inclusive o que divide com outros.
    let tamanho: Int64
    /// O que sai do disco se só ele for removido.
    let recuperavel: Int64
    let modificado: Date
    /// O que vai para a Lixeira ao remover pelos arquivos: manifesto + blobs exclusivos
    /// (Ollama) ou a pasta do modelo (LM Studio).
    let arquivos: [URL]
}

struct VarreduraModelos: Sendable {
    var modelos: [ModeloLocal] = []
    /// Ocupação real (blobs compartilhados contados uma vez só).
    var totalDisco: Int64 = 0
    /// Pastas que existem neste Mac.
    var pastas: [URL] = []
    var binarioOllama: String?
    var quando = Date()
}

enum LeitorModelos {
    static func varrer(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                       ambiente: [String: String] = ProcessInfo.processInfo.environment) -> VarreduraModelos {
        let fm = FileManager.default
        var v = VarreduraModelos()
        let o = ollama(raiz: PoliticaModelos.raizOllama(home: home, ambiente: ambiente))
        let l = lmStudio(raizes: PoliticaModelos.raizesLMStudio(home: home))
        v.modelos = (o.modelos + l.modelos).sorted { $0.tamanho > $1.tamanho }
        v.totalDisco = o.total + l.total
        v.pastas = PoliticaModelos.raizes(home: home, ambiente: ambiente).filter { fm.fileExists(atPath: $0.path) }
        v.binarioOllama = PoliticaModelos.binarioOllama()
        return v
    }

    // MARK: Ollama

    private struct Manifesto: Decodable {
        struct Camada: Decodable { let digest: String }
        let config: Camada?
        let layers: [Camada]
        /// Tudo o que o modelo precisa, config incluída (é tão parte do modelo quanto os pesos).
        var digests: [String] { layers.map(\.digest) + (config.map { [$0.digest] } ?? []) }
    }

    private struct InfoBlob { let bytes: Int64; let modificado: Date }

    static func ollama(raiz: URL) -> (modelos: [ModeloLocal], total: Int64) {
        let fm = FileManager.default
        let raizManifestos = raiz.appendingPathComponent("manifests", isDirectory: true)
        let raizBlobs = raiz.appendingPathComponent("blobs", isDirectory: true)
        guard fm.fileExists(atPath: raizManifestos.path),
              let it = fm.enumerator(at: raizManifestos, includingPropertiesForKeys: [.isRegularFileKey],
                                     options: [.skipsPackageDescendants])
        else { return ([], 0) }

        // Primeiro todos os manifestos: um blob só é recuperável se exatamente um modelo o usa,
        // e isso não dá para saber olhando um modelo por vez.
        var lidos: [(url: URL, digests: [String])] = []
        var usos: [String: Int] = [:]
        while let prox = it.nextObject() {
            guard let url = prox as? URL,
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true,
                  url.lastPathComponent != ".DS_Store",
                  let dados = try? Data(contentsOf: url),
                  let m = try? JSONDecoder().decode(Manifesto.self, from: dados)
            else { continue }
            let digests = Array(Set(m.digests))
            lidos.append((url, digests))
            for d in digests { usos[d, default: 0] += 1 }
        }

        var blobs: [String: InfoBlob] = [:]
        for d in usos.keys {
            let url = raizBlobs.appendingPathComponent(d.replacingOccurrences(of: ":", with: "-"))
            guard let r = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey,
                                                            .contentModificationDateKey]) else { continue }
            blobs[d] = InfoBlob(bytes: Int64(r.totalFileAllocatedSize ?? r.fileSize ?? 0),
                                modificado: r.contentModificationDate ?? .distantPast)
        }
        let total = blobs.values.reduce(0) { $0 + $1.bytes }

        let modelos = lidos.map { m -> ModeloLocal in
            var tamanho: Int64 = 0, recuperavel: Int64 = 0
            var modificado = (try? m.url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            // O manifesto é minúsculo mas precisa sair junto, senão o Ollama segue listando um
            // modelo sem pesos.
            var arquivos = [m.url]
            for d in m.digests {
                guard let b = blobs[d] else { continue }
                tamanho += b.bytes
                modificado = max(modificado, b.modificado)
                guard usos[d] == 1 else { continue }
                recuperavel += b.bytes
                arquivos.append(raizBlobs.appendingPathComponent(d.replacingOccurrences(of: ":", with: "-")))
            }
            return ModeloLocal(id: m.url.path, nome: nomeOllama(manifesto: m.url, raiz: raizManifestos),
                               origem: .ollama, tamanho: tamanho, recuperavel: recuperavel,
                               modificado: modificado, arquivos: arquivos)
        }
        return (modelos, total)
    }

    /// `manifests/registry.ollama.ai/library/gemma3/latest` → `gemma3:latest`, o nome que se
    /// digitou no `ollama pull`. De outro servidor, o servidor fica: `hf.co/autor/repo:tag`.
    static func nomeOllama(manifesto: URL, raiz: URL) -> String {
        let partes = Array(manifesto.standardizedFileURL.pathComponents
            .dropFirst(raiz.standardizedFileURL.pathComponents.count))
        guard partes.count >= 2, let tag = partes.last else { return manifesto.lastPathComponent }
        var nome = Array(partes.dropLast())
        if nome.first == "registry.ollama.ai" {
            nome.removeFirst()
            if nome.first == "library" { nome.removeFirst() }
        }
        guard !nome.isEmpty else { return "\(partes[0]):\(tag)" }
        return "\(nome.joined(separator: "/")):\(tag)"
    }

    // MARK: LM Studio

    /// O LM Studio guarda `<autor>/<repo>/<pesos>.gguf`: a pasta do repo é a unidade (pesos,
    /// config e partes de um modelo dividido).
    static func lmStudio(raizes: [URL]) -> (modelos: [ModeloLocal], total: Int64) {
        let fm = FileManager.default
        var modelos: [ModeloLocal] = []
        func pastas(_ u: URL) -> [URL] {
            ((try? fm.contentsOfDirectory(at: u, includingPropertiesForKeys: [.isDirectoryKey],
                                          options: [.skipsHiddenFiles])) ?? [])
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
        }
        for raiz in raizes where fm.fileExists(atPath: raiz.path) {
            for autor in pastas(raiz) {
                for repo in pastas(autor) {
                    let m = medir(repo)
                    guard m.bytes > 0 else { continue }
                    modelos.append(ModeloLocal(id: repo.path, nome: "\(autor.lastPathComponent)/\(repo.lastPathComponent)",
                                               origem: .lmStudio, tamanho: m.bytes, recuperavel: m.bytes,
                                               modificado: m.modificado, arquivos: [repo]))
                }
            }
        }
        return (modelos, modelos.reduce(0) { $0 + $1.tamanho })
    }

    private static func medir(_ url: URL) -> (bytes: Int64, modificado: Date) {
        let chaves: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey, .contentModificationDateKey]
        guard let it = FileManager.default.enumerator(at: url, includingPropertiesForKeys: chaves,
                                                      options: [.skipsPackageDescendants]) else { return (0, .distantPast) }
        var bytes: Int64 = 0, modificado = Date.distantPast
        while let prox = it.nextObject() {
            guard let u = prox as? URL, let r = try? u.resourceValues(forKeys: Set(chaves)), r.isRegularFile == true
            else { continue }
            bytes += Int64(r.totalFileAllocatedSize ?? r.fileSize ?? 0)
            modificado = max(modificado, r.contentModificationDate ?? .distantPast)
        }
        return (bytes, modificado)
    }
}
