import Foundation

/// Projeto de cada sessão (a pasta/repo de onde ela roda) e a cor dele.
/// Sessões do mesmo projeto ficam juntas e com a mesma cor.
@MainActor
enum Projetos {
    /// Cores dos projetos — cada projeto novo pega a primeira livre e guarda para sempre.
    static let cores = ["#FF7A59", "#38BDF8", "#A78BFA", "#34D399",
                        "#F472B6", "#FBBF24", "#2DD4BF", "#60A5FA",
                        "#FB923C", "#C084FC", "#4ADE80", "#F87171"]

    private static var cacheRaiz: [String: String] = [:]
    private static var coresDados: [String: String] =
        (UserDefaults.standard.dictionary(forKey: "coresProjetos") as? [String: String]) ?? [:]

    /// Raiz do projeto: o repositório git que contém a pasta (worktree conta como o repo
    /// principal, ex.: `.coucou-sessoes/x` é o Crew). Fora de git, a própria pasta.
    static func raiz(de cwd: String?) -> String? {
        guard let cwd, !cwd.isEmpty else { return nil }
        if let r = cacheRaiz[cwd] { return r }
        let fm = FileManager.default
        var dir = URL(fileURLWithPath: cwd).standardizedFileURL
        var achada = cwd
        while dir.path != "/" {
            let git = dir.appendingPathComponent(".git")
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: git.path, isDirectory: &isDir) {
                if isDir.boolValue {
                    achada = dir.path
                } else if let txt = try? String(contentsOf: git, encoding: .utf8),
                          let r = txt.range(of: "gitdir:") {
                    // Worktree: "gitdir: /repo/.git/worktrees/<nome>" → /repo
                    let gitdir = txt[r.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                    if let w = gitdir.range(of: "/.git/worktrees/") {
                        achada = String(gitdir[..<w.lowerBound])
                    } else {
                        achada = dir.path
                    }
                } else {
                    achada = dir.path
                }
                break
            }
            dir.deleteLastPathComponent()
        }
        cacheRaiz[cwd] = achada
        return achada
    }

    /// Branch da pasta da sessão, lida direto do .git (sem rodar git). Cache curto: troca de
    /// branch aparece em até 30 s.
    static func branch(de cwd: String?) -> String? {
        guard let cwd, !cwd.isEmpty else { return nil }
        if let c = cacheBranch[cwd], Date().timeIntervalSince(c.quando) < 30 { return c.branch }
        var b: String?
        var dir = URL(fileURLWithPath: cwd).standardizedFileURL
        let fm = FileManager.default
        while dir.path != "/" {
            let git = dir.appendingPathComponent(".git")
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: git.path, isDirectory: &isDir) {
                var head = git.appendingPathComponent("HEAD")
                if !isDir.boolValue, let txt = try? String(contentsOf: git, encoding: .utf8),
                   let r = txt.range(of: "gitdir:") {
                    let gd = txt[r.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                    head = URL(fileURLWithPath: gd, relativeTo: dir).appendingPathComponent("HEAD")
                }
                if let h = try? String(contentsOf: head, encoding: .utf8) {
                    let t = h.trimmingCharacters(in: .whitespacesAndNewlines)
                    b = t.hasPrefix("ref: refs/heads/") ? String(t.dropFirst("ref: refs/heads/".count)) : String(t.prefix(7))
                }
                break
            }
            dir.deleteLastPathComponent()
        }
        cacheBranch[cwd] = (b, Date())
        return b
    }
    nonisolated(unsafe) private static var cacheBranch: [String: (branch: String?, quando: Date)] = [:]

    /// Nome curto do projeto (pasta do repo).
    static func nome(de cwd: String?) -> String? {
        raiz(de: cwd).map { ConfigProjetos.shared.de($0).nome ?? URL(fileURLWithPath: $0).lastPathComponent }
    }

    /// Cor fixa do projeto; projeto novo pega a primeira cor que nenhum outro usa.
    static func cor(de cwd: String?) -> String? {
        guard let r = raiz(de: cwd) else { return nil }
        if let c = coresDados[r] { return c }
        let usadas = Set(coresDados.values)
        let c = cores.first { !usadas.contains($0) } ?? cores[coresDados.count % cores.count]
        coresDados[r] = c
        Gravar.padrao.set(coresDados, forKey: "coresProjetos")
        return c
    }

    /// O Hugo escolheu outra cor para o projeto (painel do projeto).
    static func definirCor(_ raiz: String, _ hex: String) {
        coresDados[raiz] = hex
        Gravar.padrao.set(coresDados, forKey: "coresProjetos")
    }

    /// Junta as sessões do mesmo projeto, na ordem em que cada projeto aparece pela primeira
    /// vez; dentro do projeto, mantém a ordem original. Integrações ficam onde estão.
    static func agrupadas(_ tasks: [AgentTask]) -> [AgentTask] {
        var ordem: [String: Int] = [:]
        for t in tasks { let k = chave(t); if ordem[k] == nil { ordem[k] = ordem.count } }
        return tasks.enumerated()
            .sorted { (ordem[chave($0.element)]!, $0.offset) < (ordem[chave($1.element)]!, $1.offset) }
            .map(\.element)
    }

    static func chave(_ t: AgentTask) -> String {
        raiz(de: t.sessionCwd) ?? "sem-projeto:" + t.id
    }
}
