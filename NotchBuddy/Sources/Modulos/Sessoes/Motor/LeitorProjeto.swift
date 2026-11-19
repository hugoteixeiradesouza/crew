import Foundation

// O que o painel do projeto lê do disco, sempre fora da main e só com o painel na tela:
// o estado do git, o tamanho da pasta, o CLAUDE.md, os servidores MCP, as permissões e as
// memórias do Claude Code. Só leitura — a única gravação é `salvarClaudeMd`, no clique do Hugo.

struct GitDoProjeto: Sendable, Equatable {
    var ehRepositorio = false
    var branch: String?
    /// Arquivos com mudança não commitada (inclui os novos).
    var mudancas = 0
    var aFrente = 0
    var atras = 0
    var remoto: String?
    /// Página do repositório no navegador, quando o remoto é de um serviço conhecido.
    var pagina: URL?
    var ultimoCommit: String?
    var quandoCommit: Date?
}

struct ServidorDoProjeto: Sendable, Identifiable, Hashable {
    enum Origem: String, Sendable {
        case projeto = "do projeto (.mcp.json)"
        case local = "só seu, neste projeto"
        case usuario = "seu, em todos os projetos"
    }
    let nome: String
    let origem: Origem
    /// Comando ou endereço, resumido.
    let alvo: String
    let negado: Bool
    var id: String { origem.rawValue + ":" + nome }
}

struct ClaudeDoProjeto: Sendable, Equatable {
    var servidores: [ServidorDoProjeto] = []
    var permitidas: [String] = []
    var negadas: [String] = []
    var perguntar: [String] = []
    /// Arquivos de onde as permissões vieram (caminho curto).
    var arquivos: [String] = []
}

struct MemoriaDoProjeto: Sendable, Identifiable, Hashable {
    let caminho: String
    let nome: String
    let descricao: String
    let tipo: String
    var id: String { caminho }
}

enum LeitorProjeto {
    private static let git = "/usr/bin/git"

    // MARK: Git

    static func git(_ raiz: String) async -> GitDoProjeto {
        var g = GitDoProjeto()
        let estado = await Processo.rodar(git, ["-C", raiz, "--no-optional-locks", "status", "--porcelain=v1", "-b"], tempoMax: 15)
        guard estado.ok else { return g }
        g.ehRepositorio = true
        let linhas = estado.saida.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        if let cab = linhas.first, cab.hasPrefix("## ") {
            let resto = String(cab.dropFirst(3))
            let nome = resto.components(separatedBy: "...").first ?? resto
            g.branch = nome.hasPrefix("HEAD (no branch)") ? nil : nome.components(separatedBy: " ").first
            g.aFrente = numero(depoisDe: "ahead ", em: resto)
            g.atras = numero(depoisDe: "behind ", em: resto)
        }
        g.mudancas = linhas.filter { !$0.hasPrefix("## ") }.count

        let remoto = await Processo.rodar(git, ["-C", raiz, "remote", "get-url", "origin"], tempoMax: 10)
        if remoto.ok {
            let u = remoto.saida.trimmingCharacters(in: .whitespacesAndNewlines)
            if !u.isEmpty { g.remoto = u; g.pagina = pagina(doRemoto: u) }
        }
        let ultimo = await Processo.rodar(git, ["-C", raiz, "log", "-1", "--format=%ct%x1f%s"], tempoMax: 10)
        if ultimo.ok {
            let p = ultimo.saida.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\u{1f}")
            if p.count == 2, let s = Double(p[0]) {
                g.quandoCommit = Date(timeIntervalSince1970: s)
                g.ultimoCommit = p[1]
            }
        }
        return g
    }

    private static func numero(depoisDe marca: String, em texto: String) -> Int {
        guard let r = texto.range(of: marca) else { return 0 }
        return Int(texto[r.upperBound...].prefix { $0.isNumber }) ?? 0
    }

    /// `git@github.com:dono/repo.git` e `https://github.com/dono/repo.git` → a página do repositório.
    static func pagina(doRemoto remoto: String) -> URL? {
        var u = remoto
        if u.hasSuffix(".git") { u = String(u.dropLast(4)) }
        if u.hasPrefix("git@"), let dois = u.firstIndex(of: ":") {
            let host = u[u.index(u.startIndex, offsetBy: 4)..<dois]
            u = "https://\(host)/\(u[u.index(after: dois)...])"
        } else if u.hasPrefix("ssh://git@") {
            u = "https://" + u.dropFirst("ssh://git@".count)
        }
        guard u.hasPrefix("https://"), var c = URLComponents(string: u) else { return nil }
        c.user = nil; c.password = nil
        return c.url
    }

    // MARK: Disco

    /// Tamanho da pasta inteira em bytes (`du`); nil se demorou demais ou falhou.
    static func tamanho(_ raiz: String) async -> Int64? {
        let r = await Processo.rodar("/usr/bin/du", ["-sk", raiz], tempoMax: 40)
        guard let kb = r.saida.split(whereSeparator: { $0 == "\t" || $0 == " " }).first.flatMap({ Int64($0) }) else { return nil }
        return kb * 1024
    }

    static func worktrees(_ raiz: String) async -> [WorktreesAtivas.Worktree] {
        await Task.detached(priority: .utility) {
            let home = FileManager.default.homeDirectoryForCurrentUser
            return WorktreesAtivas.worktrees(em: raiz + "/.git", vivo: .agora(home: home))
        }.value
    }

    // MARK: CLAUDE.md

    /// O CLAUDE.md do projeto: o da raiz ou o de `.claude/`. Se nenhum existe, o da raiz (a criar).
    static func caminhoClaudeMd(_ raiz: String) -> String {
        let candidatos = [raiz + "/CLAUDE.md", raiz + "/.claude/CLAUDE.md"]
        return candidatos.first { FileManager.default.fileExists(atPath: $0) } ?? candidatos[0]
    }

    static func lerClaudeMd(_ raiz: String) async -> String? {
        await Task.detached(priority: .utility) {
            try? String(contentsOfFile: caminhoClaudeMd(raiz), encoding: .utf8)
        }.value
    }

    /// Grava o CLAUDE.md, guardando antes uma cópia do que havia. Devolve o erro, ou nil.
    static func salvarClaudeMd(_ raiz: String, texto: String) async -> String? {
        await Task.detached(priority: .utility) { () -> String? in
            let destino = caminhoClaudeMd(raiz)
            let fm = FileManager.default
            if fm.fileExists(atPath: destino) {
                let pasta = HookServer.supportDir.appendingPathComponent("claude-md-anteriores", isDirectory: true)
                try? fm.createDirectory(at: pasta, withIntermediateDirectories: true)
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd-HHmmss"
                let nome = (raiz as NSString).lastPathComponent + "-" + f.string(from: Date()) + ".md"
                do { try fm.copyItem(atPath: destino, toPath: pasta.appendingPathComponent(nome).path) }
                catch { return "Não deu para guardar a cópia anterior: \(error.localizedDescription)" }
            }
            do { try texto.write(toFile: destino, atomically: true, encoding: .utf8) }
            catch { return error.localizedDescription }
            return nil
        }.value
    }

    /// Quantas linhas saem e quantas entram entre os dois textos.
    static func diferenca(de antigo: String, para novo: String) -> (saem: Int, entram: Int) {
        let a = antigo.components(separatedBy: "\n"), b = novo.components(separatedBy: "\n")
        let d = b.difference(from: a)
        return (d.removals.count, d.insertions.count)
    }

    // MARK: MCP e permissões

    static func claude(_ raiz: String) async -> ClaudeDoProjeto {
        await Task.detached(priority: .utility) { lerClaude(raiz) }.value
    }

    private static func json(_ caminho: String) -> [String: Any]? {
        guard let d = FileManager.default.contents(atPath: caminho) else { return nil }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
    }

    private static func alvo(_ s: Any?) -> String {
        guard let s = s as? [String: Any] else { return "" }
        if let u = s["url"] as? String { return u }
        let args = (s["args"] as? [String])?.joined(separator: " ") ?? ""
        return ((s["command"] as? String ?? "") + " " + args).trimmingCharacters(in: .whitespaces)
    }

    private static func lerClaude(_ raiz: String) -> ClaudeDoProjeto {
        var c = ClaudeDoProjeto()
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var desligados: Set<String> = []

        for arq in [raiz + "/.claude/settings.json", raiz + "/.claude/settings.local.json"] {
            guard let s = json(arq) else { continue }
            c.arquivos.append(String(arq.dropFirst(raiz.count + 1)))
            if let p = s["permissions"] as? [String: Any] {
                c.permitidas += p["allow"] as? [String] ?? []
                c.negadas += p["deny"] as? [String] ?? []
                c.perguntar += p["ask"] as? [String] ?? []
            }
            desligados.formUnion(s["disabledMcpjsonServers"] as? [String] ?? [])
        }

        let geral = json(home + "/.claude.json")
        let doProjeto = (geral?["projects"] as? [String: Any])?[raiz] as? [String: Any]
        desligados.formUnion(doProjeto?["disabledMcpjsonServers"] as? [String] ?? [])
        desligados.formUnion(doProjeto?["disabledMcpServers"] as? [String] ?? [])

        func negado(_ nome: String) -> Bool {
            desligados.contains(nome) || c.negadas.contains { $0 == "mcp__\(nome)" || $0 == "mcp__\(nome)__*" }
        }
        func juntar(_ servidores: Any?, _ origem: ServidorDoProjeto.Origem) {
            guard let d = servidores as? [String: Any] else { return }
            for nome in d.keys.sorted() {
                c.servidores.append(ServidorDoProjeto(nome: nome, origem: origem, alvo: alvo(d[nome]), negado: negado(nome)))
            }
        }
        juntar(json(raiz + "/.mcp.json")?["mcpServers"], .projeto)
        juntar(doProjeto?["mcpServers"], .local)
        juntar(geral?["mcpServers"], .usuario)
        return c
    }

    // MARK: Memórias

    /// A pasta onde o Claude Code guarda o que é deste projeto (`~/.claude/projects/<pasta>`).
    static func pastaDoClaude(_ raiz: String) -> String {
        let nome = String(raiz.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" })
        return FileManager.default.homeDirectoryForCurrentUser.path + "/.claude/projects/" + nome
    }

    static func memorias(_ raiz: String) async -> [MemoriaDoProjeto] {
        await Task.detached(priority: .utility) {
            let pasta = pastaDoClaude(raiz) + "/memory"
            let nomes = (try? FileManager.default.contentsOfDirectory(atPath: pasta)) ?? []
            return nomes.filter { $0.hasSuffix(".md") && $0 != "MEMORY.md" }.sorted().map { arq in
                let caminho = pasta + "/" + arq
                let texto = (try? String(contentsOfFile: caminho, encoding: .utf8)) ?? ""
                func campo(_ chave: String) -> String {
                    for l in texto.components(separatedBy: "\n").prefix(12) {
                        let t = l.trimmingCharacters(in: .whitespaces)
                        if t.hasPrefix(chave + ":") { return String(t.dropFirst(chave.count + 1)).trimmingCharacters(in: .whitespaces) }
                    }
                    return ""
                }
                let nome = campo("name")
                return MemoriaDoProjeto(caminho: caminho, nome: nome.isEmpty ? String(arq.dropLast(3)) : nome,
                                        descricao: campo("description"), tipo: campo("type"))
            }
        }.value
    }
}
