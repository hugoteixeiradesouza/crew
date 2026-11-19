import Foundation

// Projetos parados: acha raízes de projeto, propõe os artefatos reconstruíveis e esconde todo
// projeto em uso, com atividade recente ou com mudança não commitada.
// Roda fora da main (Task.detached no serviço).

struct ArtefatoProjeto: Identifiable, Sendable, Hashable {
    var id: String { caminho }
    let caminho: String
    let tipo: String
    let pastaRelativa: String
    let nivel: NivelArtefato
    let reinstalacao: EstadoReinstalacao
    let comando: String
    var bytes: Int64
    /// Marcado por padrão: seguro e com como voltar igual.
    var marcadoPorPadrao: Bool { nivel == .seguro && reinstalacao != .semLockfile }
}

struct ProjetoParado: Identifiable, Sendable, Hashable {
    var id: String { raiz }
    let raiz: String
    let nome: String
    let ecossistemas: [String]
    let ultimoSinal: Date?
    let repositorio: String?
    var artefatos: [ArtefatoProjeto]
    var bytes: Int64 { artefatos.reduce(0) { $0 + $1.bytes } }
}

/// Por que projetos com artefatos ficaram de fora (contagem, para a Central dizer).
struct EscondidosProjetos: Sendable, Equatable {
    var emUso = 0
    var recentes = 0
    var comMudancas = 0
    var semConferir = 0
    var total: Int { emUso + recentes + comMudancas + semConferir }
}

enum VarreduraProjetos {
    static let profundidadeMax = 4
    /// Pasta com mais entradas que isto não é aberta (é depósito, não projeto).
    static let maxEntradasPorPasta = 2000
    static let minimoBytes: Int64 = 1_000_000

    /// Raízes onde os projetos costumam morar. Mesa/Documentos/Downloads só
    /// com Acesso Total ao Disco.
    static let nomesRaiz = [
        "dev", "Dev", "Developer", "developer", "Development", "development", "Projects", "projects",
        "Projetos", "projetos", "Code", "code", "Work", "work", "src", "Src", "repos", "Repos",
        "GitHub", "github", "GitLab", "gitlab", "Sites", "sites", "workspace", "Workspace",
        "coding", "Coding", "apps", "Apps",
    ]
    static let nomesRaizComAcessoTotal = ["Documents", "Desktop", "Downloads"]

    /// Não desce nestas (além das ocultas e dos próprios artefatos).
    static let naoDescer: Set<String> = ["DerivedData", "android", "ios", "Library"]

    struct Resultado: Sendable {
        let projetos: [ProjetoParado]
        let escondidos: EscondidosProjetos
        let pastasLidas: Int
    }

    static func executar(meses: Int, acesso: AcessoVarredura, etapa: @Sendable (String) async -> Void) async -> Resultado {
        let fm = FileManager.default
        let home = URL(fileURLWithPath: PoliticaSeguranca.home, isDirectory: true)
        var raizesProjeto: [URL] = []
        var vistos = Set<String>()
        var lidas = 0

        func ehProjeto(_ dir: URL) -> Bool { CatalogoArtefatos.regras.contains { $0.valeNaRaiz(dir) } }

        func andar(_ dir: URL, prof: Int) {
            if Task.isCancelled { return }
            lidas += 1
            if ehProjeto(dir), vistos.insert(dir.path).inserted { raizesProjeto.append(dir) }
            guard prof < profundidadeMax else { return }
            guard let filhos = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                                                           options: [.skipsPackageDescendants]),
                  filhos.count <= maxEntradasPorPasta else { return }
            for f in filhos {
                let n = f.lastPathComponent
                if n.hasPrefix(".") || naoDescer.contains(n) || CatalogoArtefatos.nomesDeArtefato.contains(n) { continue }
                // Decidido pelo caminho antes de ler a entrada (não abre Mesa/Documentos sem acesso).
                guard LocaisProtegidos.podeLer(f, acesso: acesso) else { continue }
                // Nunca por um link: as duas chaves descrevem a entrada, não o destino.
                let v = try? f.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard v?.isSymbolicLink != true, v?.isDirectory == true else { continue }
                andar(f, prof: prof + 1)
            }
        }

        await etapa("Procurando projetos…")
        var raizes = nomesRaiz
        if acesso == .total { raizes += nomesRaizComAcessoTotal }
        var raizesVistas = Set<String>()
        for n in raizes {
            let r = home.appendingPathComponent(n, isDirectory: true)
            guard LocaisProtegidos.podeLer(r, acesso: acesso),
                  let a = try? fm.attributesOfItem(atPath: r.path), (a[.type] as? FileAttributeType) == .typeDirectory else { continue }
            // `dev` e `Dev` são a mesma pasta no APFS sem maiúsculas: anda uma vez só.
            let real = r.resolvingSymlinksInPath().path.lowercased()
            guard raizesVistas.insert(real).inserted else { continue }
            andar(r, prof: 0)
        }
        // Filhos diretos da home (ex.: ~/n8n-local): só a própria pasta, sem descer.
        let raizesLower = Set(raizes.map { $0.lowercased() })
        for f in (try? fm.contentsOfDirectory(at: home, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                                              options: [.skipsHiddenFiles])) ?? [] {
            let n = f.lastPathComponent
            if raizesLower.contains(n.lowercased()) || PoliticaArtefatos.raizesProibidas.contains(n) { continue }
            guard LocaisProtegidos.podeLer(f, acesso: acesso) else { continue }
            let v = try? f.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard v?.isSymbolicLink != true, v?.isDirectory == true else { continue }
            lidas += 1
            if ehProjeto(f), vistos.insert(f.path).inserted { raizesProjeto.append(f) }
        }
        if Task.isCancelled { return Resultado(projetos: [], escondidos: .init(), pastasLidas: lidas) }

        await etapa("Conferindo \(raizesProjeto.count) projetos…")
        let cwds = AtividadeProjeto.pastasDeTrabalho()
        let corte = Calendar.current.date(byAdding: .month, value: -meses, to: Date()) ?? Date()
        var escondidos = EscondidosProjetos()
        var candidatos: [ProjetoParado] = []
        var situacaoRepo: [String: Git.Situacao] = [:]

        for raiz in raizesProjeto {
            if Task.isCancelled { break }
            var artefatos = coletar(raiz: raiz, acesso: acesso)
            guard !artefatos.isEmpty else { continue }
            // Sem a lista de processos não dá para saber quem está em uso: ninguém aparece.
            guard let cwds else { escondidos.semConferir += 1; continue }
            if AtividadeProjeto.emUso(raiz: raiz, cwds: cwds, acesso: acesso) != nil { escondidos.emUso += 1; continue }
            if AtividadeProjeto.temAtividade(desde: corte, raiz: raiz, artefatos: artefatos.map { URL(fileURLWithPath: $0.caminho) },
                                             acesso: acesso) {
                escondidos.recentes += 1
                continue
            }
            let repo = AtividadeProjeto.raizDoRepositorio(raiz)
            if let repo {
                let s: Git.Situacao
                if let ja = situacaoRepo[repo.path] { s = ja } else {
                    s = await Git.situacao(repo: repo)
                    situacaoRepo[repo.path] = s
                }
                switch s {
                case .limpo: break
                case .comMudancas: escondidos.comMudancas += 1; continue
                case .desconhecido: escondidos.semConferir += 1; continue
                }
                // Pasta com arquivo versionado não é artefato.
                guard let vers = await Git.versionadas(raiz: raiz, pastas: artefatos.map(\.pastaRelativa)) else {
                    escondidos.semConferir += 1
                    continue
                }
                artefatos.removeAll { vers.contains($0.pastaRelativa) }
                if artefatos.isEmpty { continue }
            }
            let ecos = Array(Set(artefatos.compactMap { a in CatalogoArtefatos.regras.first { $0.tipo == a.tipo }?.ecossistema })).sorted()
            candidatos.append(ProjetoParado(raiz: raiz.path, nome: raiz.lastPathComponent, ecossistemas: ecos,
                                            ultimoSinal: AtividadeProjeto.ultimoSinal(raiz: raiz, acesso: acesso),
                                            repositorio: repo?.path, artefatos: artefatos))
        }
        if Task.isCancelled { return Resultado(projetos: [], escondidos: escondidos, pastasLidas: lidas) }

        await etapa("Medindo…")
        let tamanhos = await Tamanhos.medir(candidatos.flatMap { $0.artefatos.map { URL(fileURLWithPath: $0.caminho) } })
        var projetos: [ProjetoParado] = []
        for var p in candidatos {
            for i in p.artefatos.indices { p.artefatos[i].bytes = tamanhos[p.artefatos[i].caminho] ?? 0 }
            p.artefatos = p.artefatos.filter { $0.bytes > 0 }.sorted { $0.bytes > $1.bytes }
            if p.bytes >= minimoBytes { projetos.append(p) }
        }
        return Resultado(projetos: projetos.sorted { $0.bytes > $1.bytes }, escondidos: escondidos, pastasLidas: lidas)
    }

    /// Artefatos de uma raiz que passam pela política (sem medir). Artefato dentro de outro
    /// (`node_modules/.vite`) fica de fora: o de fora já leva tudo.
    static func coletar(raiz: URL, acesso: AcessoVarredura) -> [ArtefatoProjeto] {
        var achados: [String: ArtefatoProjeto] = [:]
        for r in CatalogoArtefatos.regras {
            let u = raiz.appendingPathComponent(r.pasta, isDirectory: true).standardizedFileURL
            guard achados[u.path] == nil, existeSemSeguir(u) else { continue }
            guard case .success(let regra) = PoliticaArtefatos.avaliar(u, acesso: acesso), regra == r else { continue }
            achados[u.path] = ArtefatoProjeto(caminho: u.path, tipo: r.tipo, pastaRelativa: r.pasta, nivel: r.nivel,
                                              reinstalacao: CatalogoArtefatos.estadoReinstalacao(r, artefato: u),
                                              comando: CatalogoArtefatos.comoReinstalar(r, raiz: raiz), bytes: 0)
        }
        let caminhos = Array(achados.keys)
        return achados.values.filter { a in !caminhos.contains { a.caminho.hasPrefix($0 + "/") } }
            .sorted { $0.caminho < $1.caminho }
    }

    /// Antes de confirmar: cada artefato de novo pela política, o projeto de novo por uso, lock e
    /// mudança não commitada. Devolve o que ainda vale e o que saiu (com o motivo).
    static func revalidar(_ projetos: [ProjetoParado], acesso: AcessoVarredura) async -> ([ProjetoParado], [Retirado]) {
        var validos: [ProjetoParado] = []
        var retirados: [Retirado] = []
        let cwds = AtividadeProjeto.pastasDeTrabalho()
        for var p in projetos {
            let raiz = URL(fileURLWithPath: p.raiz)
            guard let cwds else { retirados.append(Retirado(nome: p.nome, motivo: "Não deu para ler a lista de processos.")); continue }
            if let m = AtividadeProjeto.emUso(raiz: raiz, cwds: cwds, acesso: acesso) {
                retirados.append(Retirado(nome: p.nome, motivo: m)); continue
            }
            if let repo = p.repositorio {
                switch await Git.situacao(repo: URL(fileURLWithPath: repo)) {
                case .limpo: break
                case .comMudancas(let n):
                    retirados.append(Retirado(nome: p.nome, motivo: "\(n) mudança(s) não commitada(s) no repositório.")); continue
                case .desconhecido:
                    retirados.append(Retirado(nome: p.nome, motivo: "Não deu para conferir o git.")); continue
                }
            }
            p.artefatos = p.artefatos.filter { a in
                if case .failure(let r) = PoliticaArtefatos.avaliar(URL(fileURLWithPath: a.caminho), acesso: acesso) {
                    retirados.append(Retirado(nome: "\(p.nome)/\(a.pastaRelativa)", motivo: r.motivo))
                    return false
                }
                return true
            }
            if !p.artefatos.isEmpty { validos.append(p) }
        }
        return (validos, retirados)
    }

    /// Checagem síncrona imediatamente antes de mover cada pasta.
    static func aindaPodeSair(_ a: ArtefatoProjeto, projeto: ProjetoParado, cwds: Set<String>?, acesso: AcessoVarredura) -> String? {
        guard let cwds else { return "Não deu para ler a lista de processos." }
        if let m = AtividadeProjeto.emUso(raiz: URL(fileURLWithPath: projeto.raiz), cwds: cwds, acesso: acesso) { return m }
        if case .failure(let r) = PoliticaArtefatos.avaliar(URL(fileURLWithPath: a.caminho), acesso: acesso) { return r.motivo }
        return nil
    }
}
