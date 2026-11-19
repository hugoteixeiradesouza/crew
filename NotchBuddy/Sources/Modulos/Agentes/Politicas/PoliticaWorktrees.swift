import Darwin
import Foundation

// Worktrees de agentes de IA: quais são órfãs (podem ir para a Lixeira) e quais estão ativas.
//
// Regras:
// - órfã = o repositório não lista mais a pasta. Verificado em disco, sem rodar `git`;
// - a idade nunca é critério;
// - qualquer dúvida (volume desmontado, arquivo ilegível, `.git` que é link) = "desconhecido" = não aparece;
// - processo com cwd dentro, pasta aberta no Cursor ou lock do git = fica de fora;
// - acréscimo do Crew: `.coucou-sessoes/` (worktrees do scripts/sessao.sh) nunca é órfã.

enum PoliticaWorktrees {

    // MARK: - Onde procurar

    /// Pastas (relativas à home) onde cada ferramenta guarda worktrees, dois níveis:
    /// `<raiz>/<repo>/<nome>`, ou `<raiz>/<id>/<repo>` no Codex.
    static let raizesNaHome: [(caminho: String, ferramenta: String)] = [
        (".cursor/worktrees", "Cursor"),
        (".codex/worktrees", "Codex"),
        ("conductor/workspaces", "Conductor"),
        (".t3/worktrees", "T3 Code"),
    ]

    /// O Claude Code põe dentro do projeto: `<projeto>/.claude/worktrees/<nome>`.
    static let raizNoProjeto = ".claude/worktrees"

    /// Worktrees do scripts/sessao.sh do Crew: nunca são órfãs, nunca vão para a Lixeira.
    static let pastaSessoesCrew = "/.coucou-sessoes/"

    struct Candidata: Sendable, Hashable {
        let caminho: String
        let ferramenta: String
    }

    static func candidatas(home: URL, projetosClaude: [URL]) -> [Candidata] {
        var lista: [Candidata] = []
        for raiz in raizesNaHome {
            for folha in folhasDoisNiveis(em: home.appendingPathComponent(raiz.caminho, isDirectory: true)) {
                lista.append(Candidata(caminho: folha.path, ferramenta: raiz.ferramenta))
            }
        }
        for p in projetosClaude {
            for f in filhosComGit(em: p.appendingPathComponent(raizNoProjeto, isDirectory: true)) {
                lista.append(Candidata(caminho: f.path, ferramenta: "Claude Code"))
            }
        }
        var vistos: Set<String> = []
        return lista.filter { vistos.insert($0.caminho).inserted }
    }

    /// Pastas de projeto em que o Claude Code já rodou, de `~/.claude.json` (`projects` e
    /// `githubRepoPaths`). Só o que está dentro da home.
    static func projetosClaude(home: URL) -> [URL] {
        let arquivo = home.appendingPathComponent(".claude.json", isDirectory: false)
        guard let data = try? Data(contentsOf: arquivo),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        var caminhos: [String] = []
        if let projetos = json["projects"] as? [String: Any] { caminhos += projetos.keys }
        if let repos = json["githubRepoPaths"] as? [String: Any] {
            for case let lista as [String] in repos.values { caminhos += lista }
        }
        let h = home.standardizedFileURL.path
        var vistos: Set<String> = []
        return caminhos
            .map { ($0 as NSString).standardizingPath }
            .filter { $0.hasPrefix(h + "/") && vistos.insert($0).inserted }
            .sorted()
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    // MARK: - Registro no git (sem rodar git)

    enum Registro: Equatable, Sendable {
        /// O repositório ainda lista esta pasta.
        case registrada
        /// O repositório sumiu ou não lista mais a pasta.
        case orfa(Motivo)
        /// Não é worktree ligada, ou não deu para provar.
        case desconhecido
    }

    enum Motivo: String, Sendable {
        case repositorioSumiu = "O repositório dono não existe mais."
        case removidaDoGit = "O repositório não a lista mais (git worktree remove/prune)."
        case outraCopia = "O registro do git aponta para outra pasta: esta é uma cópia solta."
        case repositorioMudou = "O repositório mudou de pasta e o git perdeu esta worktree (ainda guarda o caminho antigo, que não existe; git worktree repair a reataria)."
    }

    /// Uma worktree ligada tem `.git` arquivo com `gitdir: <repo>/.git/worktrees/<id>`. A pasta admin
    /// tem um `gitdir` que aponta de volta para o `.git` da worktree. Registrada enquanto os dois
    /// lados concordam (comparados por inode, para `/var` × `/private/var` não enganar).
    static func registro(de worktree: URL) -> Registro {
        let dotGit = worktree.appendingPathComponent(".git", isDirectory: false)
        // `lstat`: `.git` diretório é clone com história própria; link nunca é seguido.
        guard tipo(dotGit.path, seguindoLinks: false) == .arquivo,
              let admin = diretorioGit(doRepositorio: worktree) else { return .desconhecido }

        switch tipo(admin.path, seguindoLinks: true) {
        case .ausente:
            // Repositório num disco desconectado tem a mesma cara: fica desconhecido.
            if estaEmVolumeDesmontado(admin.path) { return .desconhecido }
            return .orfa(repositorioDono(doAdmin: admin).map { tipo($0, seguindoLinks: true) == .ausente } == true
                         ? .repositorioSumiu : .removidaDoGit)
        case .diretorio:
            break
        case .arquivo, .outro, .ilegivel:
            return .desconhecido
        }

        let volta = admin.appendingPathComponent("gitdir", isDirectory: false)
        guard let texto = try? String(contentsOf: volta, encoding: .utf8) else { return .desconhecido }
        let gravado = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !gravado.isEmpty else { return .desconhecido }
        // Relativo desde o Git 2.48 (`worktree.useRelativePaths`), em relação à pasta admin.
        let caminhoGravado = gravado.hasPrefix("/") ? gravado : admin.path + "/" + gravado

        guard let nosso = identidade(dotGit.path) else { return .desconhecido }
        switch tipo(caminhoGravado, seguindoLinks: true) {
        case .ausente, .ilegivel:
            // O registro aponta para um caminho que não existe: a pasta foi movida à mão e
            // `git worktree repair` a recuperaria. Na dúvida, não é órfã.
            return .desconhecido
        case .arquivo, .diretorio, .outro:
            guard let deles = identidade(caminhoGravado) else { return .desconhecido }
            return deles == nosso ? .registrada : .orfa(.outraCopia)
        }
    }

    /// Onde o git lê os metadados: `<repo>/.git`, ou o `gitdir:` do arquivo `.git` de uma worktree.
    static func diretorioGit(doRepositorio repo: URL) -> URL? {
        let dotGit = repo.appendingPathComponent(".git", isDirectory: false)
        var ehDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dotGit.path, isDirectory: &ehDir) else { return nil }
        if ehDir.boolValue { return repo.appendingPathComponent(".git", isDirectory: true) }
        guard let texto = try? String(contentsOf: dotGit, encoding: .utf8) else { return nil }
        for linha in texto.split(whereSeparator: \.isNewline) {
            let l = linha.trimmingCharacters(in: .whitespaces)
            guard l.lowercased().hasPrefix("gitdir:") else { continue }
            let p = l.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
            guard !p.isEmpty else { return nil }
            return URL(fileURLWithPath: p.hasPrefix("/") ? p : repo.path + "/" + p, isDirectory: true)
        }
        return nil
    }

    /// `<repo>/.git/worktrees/<id>` → `<repo>` (só lendo o texto do caminho).
    static func repositorioDono(doAdmin admin: URL) -> String? {
        let p = admin.standardizedFileURL.path
        guard let r = p.range(of: "/.git/worktrees/", options: .backwards) else { return nil }
        return String(p[..<r.lowerBound])
    }

    // MARK: - Em uso agora

    struct Vivo: Sendable {
        /// cwd de todo processo do usuário. Nil = não deu para ler a lista de processos; aí nada
        /// é listado como órfão (não dá para separar em uso de largada).
        var cwds: Set<String>?
        /// Pastas abertas em janelas do Cursor.
        var abertasNoCursor: Set<String>

        static func agora(home: URL) -> Vivo {
            Vivo(cwds: DiretoriosDeProcessos.todosSeLegivel(),
                 abertasNoCursor: pastasAbertasNoCursor(
                    home.appendingPathComponent("Library/Application Support/Cursor", isDirectory: true)))
        }

        func temProcessoDentro(_ caminho: String) -> Bool {
            let reais = grafias(caminho)
            return cwds?.contains { c in reais.contains { c == $0 || c.hasPrefix($0 + "/") } } ?? true
        }

        func abertaNoCursor(_ caminho: String) -> Bool {
            let reais = grafias(caminho)
            return abertasNoCursor.contains { c in reais.contains { c == $0 || c.hasPrefix($0 + "/") } }
        }

        /// O caminho como achado e o real (cwd de processo vem com links resolvidos).
        private func grafias(_ caminho: String) -> [String] {
            let real = URL(fileURLWithPath: caminho).resolvingSymlinksInPath().path
            return real == caminho ? [caminho] : [caminho, real]
        }
    }

    /// Lock do git (`index.lock`, `HEAD.lock`) ou worktree travada (`git worktree lock`).
    static func temLock(_ worktree: URL) -> Bool {
        guard let gd = diretorioGit(doRepositorio: worktree) else { return false }
        return ["index.lock", "HEAD.lock", "locked"].contains {
            FileManager.default.fileExists(atPath: gd.appendingPathComponent($0).path)
        }
    }

    // MARK: - Varredura

    struct Orfa: Sendable, Identifiable, Hashable {
        let caminho: String
        let ferramenta: String
        /// Repositório dono (ou a pasta do projeto, para as do Claude Code).
        let projeto: String
        let motivo: Motivo
        var id: String { caminho }
        var nome: String { (caminho as NSString).lastPathComponent }
    }

    /// Órfãs e ociosas, de todas as ferramentas, em ordem estável.
    static func orfas(home: URL, projetosClaude: [URL], vivo: Vivo) -> [Orfa] {
        guard vivo.cwds != nil else { return [] }
        return candidatas(home: home, projetosClaude: projetosClaude).compactMap { c in
            guard !c.caminho.contains(pastaSessoesCrew) else { return nil }
            let url = URL(fileURLWithPath: c.caminho, isDirectory: true)
            guard case .orfa(let motivo) = registro(de: url),
                  !vivo.temProcessoDentro(c.caminho), !vivo.abertaNoCursor(c.caminho), !temLock(url) else { return nil }
            let projeto = projetoDe(c, worktree: url)
            return Orfa(caminho: c.caminho, ferramenta: c.ferramenta, projeto: projeto,
                        motivo: motivo == .repositorioSumiu && repositorioMudou(url, projeto: projeto, home: home)
                            ? .repositorioMudou : motivo)
        }
    }

    /// O `.git` da worktree aponta para um repositório que não existe mais, mas o projeto onde ela
    /// está tem um registro com o mesmo id cujo caminho também sumiu: o repositório foi movido.
    private static func repositorioMudou(_ worktree: URL, projeto: String, home: URL) -> Bool {
        guard let admin = diretorioGit(doRepositorio: worktree),
              let comum = WorktreesAtivas.diretorioComum(acimaDe: URL(fileURLWithPath: projeto, isDirectory: true), home: home)
        else { return false }
        let gitdir = URL(fileURLWithPath: comum).appendingPathComponent("worktrees")
            .appendingPathComponent(admin.lastPathComponent).appendingPathComponent("gitdir")
        guard let t = try? String(contentsOf: gitdir, encoding: .utf8) else { return false }
        let g = t.trimmingCharacters(in: .whitespacesAndNewlines)
        return !g.isEmpty && tipo(g.hasPrefix("/") ? g : gitdir.deletingLastPathComponent().path + "/" + g,
                                  seguindoLinks: true) == .ausente
    }

    private static func projetoDe(_ c: Candidata, worktree: URL) -> String {
        if let r = c.caminho.range(of: "/" + raizNoProjeto + "/", options: .backwards) {
            return String(c.caminho[..<r.lowerBound])
        }
        if let admin = diretorioGit(doRepositorio: worktree), let dono = repositorioDono(doAdmin: admin) {
            return dono
        }
        return (worktree.deletingLastPathComponent().path as NSString).lastPathComponent
    }

    // MARK: - Portão antes da Lixeira

    /// Última conferência antes de mover: formato do caminho, nada de link no caminho, fora do
    /// `.coucou-sessoes/`, e o repositório continua sem listar a pasta (mesmo que tenha voltado a
    /// listar depois da varredura).
    static func podeIrParaLixeira(_ caminho: String, home: URL) -> Bool {
        let path = URL(fileURLWithPath: caminho).standardizedFileURL.path
        let h = home.standardizedFileURL.path
        guard path.hasPrefix(h + "/"), !path.contains(pastaSessoesCrew) else { return false }
        guard formatoNaRaizDaHome(path, home: h) || formatoNoProjeto(path, home: h) else { return false }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        if case .orfa = registro(de: url) { return true }
        return false
    }

    /// Folha (1 ou 2 níveis) debaixo de uma das raízes das ferramentas.
    static func formatoNaRaizDaHome(_ path: String, home: String) -> Bool {
        for raiz in raizesNaHome.map({ "\(home)/\($0.caminho)" }) where path.hasPrefix(raiz + "/") {
            let partes = path.dropFirst(raiz.count + 1).split(separator: "/", omittingEmptySubsequences: false)
            guard (1...2).contains(partes.count), partes.allSatisfy({ !$0.isEmpty && !$0.hasPrefix(".") }) else {
                return false
            }
            let url = URL(fileURLWithPath: path, isDirectory: true)
            return !temLinkNoCaminho(url, home: home) && ficaDentro(raiz: raiz, url: url, home: home)
                && FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path)
        }
        return false
    }

    /// `<projeto>/.claude/worktrees/<nome>` com `.git` arquivo (worktree ligada).
    static func formatoNoProjeto(_ path: String, home: String) -> Bool {
        guard let r = path.range(of: "/" + raizNoProjeto + "/", options: .backwards) else { return false }
        let nome = path[r.upperBound...]
        guard !nome.isEmpty, !nome.contains("/"), !nome.hasPrefix(".") else { return false }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        guard !temLinkNoCaminho(url, home: home) else { return false }
        var info = stat()
        guard lstat(url.appendingPathComponent(".git").path, &info) == 0 else { return false }
        return info.st_mode & S_IFMT == S_IFREG
    }

    // MARK: - Pastas

    /// `<raiz>/<a>/<b>` com `.git`; `<raiz>/<a>` quando ele tem e nenhum filho tem. A raiz e as
    /// pastas de agrupamento nunca são folhas: uma worktree viva ao lado de uma órfã não vai junto.
    static func folhasDoisNiveis(em raiz: URL) -> [URL] {
        var folhas: [URL] = []
        for grupo in subpastas(de: raiz) {
            let filhos = filhosComGit(em: grupo)
            if !filhos.isEmpty { folhas += filhos }
            else if temGit(grupo) { folhas.append(grupo) }
        }
        return folhas
    }

    static func filhosComGit(em pasta: URL) -> [URL] { subpastas(de: pasta).filter(temGit) }

    private static func temGit(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path)
    }

    /// Nomes com ponto pulados à mão: `.skipsHiddenFiles` também derruba o que tem a marca de oculto,
    /// e a `.claude` do Claude Code inteira tem.
    private static func subpastas(de url: URL) -> [URL] {
        guard let itens = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return [] }
        return itens.compactMap { e in
            guard !e.lastPathComponent.hasPrefix(".") else { return nil }
            let v = try? e.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard v?.isDirectory == true, v?.isSymbolicLink != true else { return nil }
            return URL(fileURLWithPath: url.path, isDirectory: true).appendingPathComponent(e.lastPathComponent, isDirectory: true)
        }
        .sorted { $0.path < $1.path }
    }

    static func temLinkNoCaminho(_ url: URL, home: String) -> Bool {
        let path = url.standardizedFileURL.path
        guard path == home || path.hasPrefix(home + "/") else { return true }
        var atual = URL(fileURLWithPath: home, isDirectory: true)
        for parte in path.dropFirst(home.count).split(separator: "/") {
            atual.appendPathComponent(String(parte))
            if (try? atual.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true { return true }
        }
        return false
    }

    private static func ficaDentro(raiz: String, url: URL, home: String) -> Bool {
        let r = URL(fileURLWithPath: raiz, isDirectory: true)
        guard !temLinkNoCaminho(r, home: home) else { return false }
        let raizReal = r.resolvingSymlinksInPath().standardizedFileURL.path
        guard raizReal == raiz else { return false }
        return url.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(raizReal + "/")
    }

    // MARK: - Cursor

    /// Pastas abertas nas janelas do Cursor (`storage.json` dele).
    static func pastasAbertasNoCursor(_ suporte: URL) -> Set<String> {
        let arquivo = suporte.appendingPathComponent("User/globalStorage/storage.json", isDirectory: false)
        guard let data = try? Data(contentsOf: arquivo),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        var pastas: Set<String> = []
        func uri(_ bruto: Any?) {
            guard let s = bruto as? String, let u = URL(string: s), u.scheme == "file" else { return }
            pastas.insert((u.path as NSString).standardizingPath)
        }
        if let backup = json["backupWorkspaces"] as? [String: Any],
           let lista = backup["folders"] as? [[String: Any]] {
            for item in lista { uri(item["folderUri"]) }
        }
        if let estado = json["windowsState"] as? [String: Any],
           let abertas = estado["openedWindows"] as? [[String: Any]] {
            for j in abertas {
                uri(j["folderUri"] ?? j["workspaceIdentifier"])
                if let f = j["folder"] as? String { pastas.insert((f as NSString).standardizingPath) }
            }
        }
        return pastas
    }

    // MARK: - stat

    enum Tipo { case ausente, arquivo, diretorio, outro, ilegivel }

    static func tipo(_ path: String, seguindoLinks: Bool) -> Tipo {
        var info = stat()
        let r = seguindoLinks ? stat(path, &info) : lstat(path, &info)
        guard r == 0 else { return errno == ENOENT || errno == ENOTDIR ? .ausente : .ilegivel }
        switch info.st_mode & S_IFMT {
        case S_IFREG: return .arquivo
        case S_IFDIR: return .diretorio
        default: return .outro
        }
    }

    private struct Identidade: Equatable { let dev: dev_t; let ino: ino_t }

    private static func identidade(_ path: String) -> Identidade? {
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        return Identidade(dev: info.st_dev, ino: info.st_ino)
    }

    /// `/Volumes/<nome>/…` cujo volume não está montado agora.
    static func estaEmVolumeDesmontado(_ path: String) -> Bool {
        let partes = path.split(separator: "/", omittingEmptySubsequences: true)
        guard partes.count >= 2, partes[0] == "Volumes" else { return false }
        var info = stat()
        return stat("/Volumes/\(partes[1])", &info) != 0
    }
}
