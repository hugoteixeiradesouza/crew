import Foundation

// `git` só pelo `Processo.rodar` (fora da main, com tempo máximo). Sempre com
// `--no-optional-locks`: o `status` normal reescreve o índice e pegaria o `index.lock`
// de um repositório que outra sessão pode estar usando.

enum Git {
    /// Um `git` que roda sem disparar o instalador das ferramentas de linha de comando:
    /// o do Homebrew, ou o `/usr/bin/git` só se houver Xcode/CLT instalado.
    static func executavel() -> String? {
        let fm = FileManager.default
        for c in ["/opt/homebrew/bin/git", "/usr/local/bin/git"] where fm.isExecutableFile(atPath: c) { return c }
        let temFerramentas = Xcode.pastaDeveloper() != nil
            || fm.fileExists(atPath: "/Library/Developer/CommandLineTools/usr/bin/git")
        return temFerramentas ? "/usr/bin/git" : nil
    }

    enum Situacao: Sendable, Equatable {
        case limpo
        case comMudancas(Int)
        /// Não deu para conferir (sem git, erro, tempo) — tratado como "não mostrar".
        case desconhecido
    }

    static func situacao(repo: URL) async -> Situacao {
        guard let git = executavel() else { return .desconhecido }
        let r = await Processo.rodar(git, ["--no-optional-locks", "-C", repo.path, "status", "--porcelain",
                                           "--untracked-files=normal"], tempoMax: 20)
        guard r.ok else { return .desconhecido }
        let n = r.saida.split(separator: "\n").count
        return n == 0 ? .limpo : .comMudancas(n)
    }

    /// Das `pastas` (relativas a `raiz`), quais têm algum arquivo versionado. Pasta versionada
    /// não é artefato: tirar deixaria o repositório com mudança.
    static func versionadas(raiz: URL, pastas: [String]) async -> Set<String>? {
        guard !pastas.isEmpty else { return [] }
        guard let git = executavel() else { return nil }
        let r = await Processo.rodar(git, ["--no-optional-locks", "-C", raiz.path, "ls-files", "-z", "--"] + pastas, tempoMax: 20)
        guard r.ok else { return nil }
        var achadas: Set<String> = []
        for linha in r.saida.split(separator: "\0") {
            let l = String(linha)
            for p in pastas where l == p || l.hasPrefix(p + "/") { achadas.insert(p) }
            if achadas.count == pastas.count { break }
        }
        return achadas
    }
}

/// Onde está o Xcode (para simuladores e para saber se o `/usr/bin/git` não vai pedir instalação).
enum Xcode {
    /// `…/Xcode.app/Contents/Developer` escolhido no `xcode-select`, ou o primeiro Xcode em
    /// /Applications. Lido do disco: nada roda (o `xcrun` sem Xcode abre o instalador do macOS).
    static func pastaDeveloper() -> String? {
        let fm = FileManager.default
        if let d = try? fm.destinationOfSymbolicLink(atPath: "/var/db/xcode_select_link"),
           d.contains(".app/"), fm.fileExists(atPath: d + "/usr/bin/simctl") {
            return d
        }
        let apps = (try? fm.contentsOfDirectory(atPath: "/Applications")) ?? []
        for a in apps.sorted() where a.hasPrefix("Xcode") && a.hasSuffix(".app") {
            let d = "/Applications/\(a)/Contents/Developer"
            if fm.fileExists(atPath: d + "/usr/bin/simctl") { return d }
        }
        return nil
    }

    /// `xcrun simctl` quando o Xcode é o escolhido; senão o `simctl` do Xcode achado, direto.
    static func simctl() -> (String, [String])? {
        guard let d = pastaDeveloper() else { return nil }
        if let sel = try? FileManager.default.destinationOfSymbolicLink(atPath: "/var/db/xcode_select_link"), sel == d {
            return ("/usr/bin/xcrun", ["simctl"])
        }
        return (d + "/usr/bin/simctl", [])
    }
}
