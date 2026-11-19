import Foundation

// Worktrees que o git ainda lista, por repositório — a visão geral das sessões paralelas.
// Só leitura e sem rodar `git`: lê `<repo>/.git/worktrees/<id>/{gitdir,HEAD,locked}` em disco.

enum WorktreesAtivas {

    struct Worktree: Sendable, Identifiable, Hashable {
        let caminho: String
        /// `nil` = HEAD destacado (aparece o commit curto em `commit`).
        let branch: String?
        let commit: String?
        /// Última atividade do git nela (index, HEAD, reflog) ou da pasta.
        let ultimaMudanca: Date?
        let emUso: Bool
        let travada: Bool
        /// A pasta sumiu mas o git ainda lista (`git worktree prune` limparia).
        let pastaSumiu: Bool
        /// Do scripts/sessao.sh do Crew.
        let sessaoCrew: Bool
        var id: String { caminho }
        var nome: String { (caminho as NSString).lastPathComponent }
    }

    struct Repositorio: Sendable, Identifiable, Hashable {
        let caminho: String
        let worktrees: [Worktree]
        var id: String { caminho }
        var nome: String { (caminho as NSString).lastPathComponent }
    }

    /// Repositórios dos projetos do Claude Code que têm pelo menos uma worktree ligada.
    static func ler(projetos: [URL], home: URL, vivo: PoliticaWorktrees.Vivo) -> [Repositorio] {
        var comuns: [String] = []
        var vistos: Set<String> = []
        for p in projetos {
            guard let c = diretorioComum(acimaDe: p, home: home) else { continue }
            if vistos.insert(c).inserted { comuns.append(c) }
        }
        return comuns.compactMap { comum in
            let lista = worktrees(em: comum, vivo: vivo)
            guard !lista.isEmpty else { return nil }
            let raiz = comum.hasSuffix("/.git") ? String(comum.dropLast(5)) : comum
            return Repositorio(caminho: raiz, worktrees: lista)
        }
        .sorted { $0.nome.localizedCaseInsensitiveCompare($1.nome) == .orderedAscending }
    }

    /// O `.git` comum do repositório que contém a pasta (subindo até a home, sem passar dela).
    static func diretorioComum(acimaDe pasta: URL, home: URL) -> String? {
        let h = home.standardizedFileURL.path
        var atual = pasta.standardizedFileURL
        while atual.path.hasPrefix(h + "/") {
            let dotGit = atual.appendingPathComponent(".git", isDirectory: false)
            switch PoliticaWorktrees.tipo(dotGit.path, seguindoLinks: false) {
            case .diretorio:
                return dotGit.path
            case .arquivo:
                // A própria pasta é uma worktree: o comum vem do `commondir` da pasta admin.
                guard let admin = PoliticaWorktrees.diretorioGit(doRepositorio: atual),
                      let rel = try? String(contentsOf: admin.appendingPathComponent("commondir"), encoding: .utf8)
                else { return nil }
                let r = rel.trimmingCharacters(in: .whitespacesAndNewlines)
                let c = r.hasPrefix("/") ? r : admin.path + "/" + r
                let padrao = (c as NSString).standardizingPath
                return PoliticaWorktrees.tipo(padrao, seguindoLinks: true) == .diretorio ? padrao : nil
            case .ausente:
                atual.deleteLastPathComponent()
            case .outro, .ilegivel:
                return nil
            }
        }
        return nil
    }

    static func worktrees(em comum: String, vivo: PoliticaWorktrees.Vivo) -> [Worktree] {
        let pasta = URL(fileURLWithPath: comum, isDirectory: true).appendingPathComponent("worktrees", isDirectory: true)
        guard let ids = try? FileManager.default.contentsOfDirectory(atPath: pasta.path) else { return [] }
        let fm = FileManager.default
        var lista: [Worktree] = []
        for id in ids.sorted() where !id.hasPrefix(".") {
            let admin = pasta.appendingPathComponent(id, isDirectory: true)
            guard let bruto = try? String(contentsOf: admin.appendingPathComponent("gitdir"), encoding: .utf8) else { continue }
            let g = bruto.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !g.isEmpty else { continue }
            let dotGit = ((g.hasPrefix("/") ? g : admin.path + "/" + g) as NSString).standardizingPath
            let caminho = (dotGit as NSString).deletingLastPathComponent
            // Disco desconectado: não dá para saber, não aparece.
            if PoliticaWorktrees.estaEmVolumeDesmontado(caminho) { continue }

            var branch: String?, commit: String?
            if let head = try? String(contentsOf: admin.appendingPathComponent("HEAD"), encoding: .utf8) {
                let t = head.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.hasPrefix("ref:") {
                    let ref = t.dropFirst(4).trimmingCharacters(in: .whitespaces)
                    branch = ref.hasPrefix("refs/heads/") ? String(ref.dropFirst("refs/heads/".count)) : ref
                } else {
                    commit = String(t.prefix(7))
                }
            }

            let datas = [admin.appendingPathComponent("index").path,
                         admin.appendingPathComponent("HEAD").path,
                         admin.appendingPathComponent("logs/HEAD").path,
                         caminho]
                .compactMap { (try? fm.attributesOfItem(atPath: $0))?[.modificationDate] as? Date }
            let existe = fm.fileExists(atPath: caminho)
            lista.append(Worktree(
                caminho: caminho, branch: branch, commit: commit, ultimaMudanca: datas.max(),
                emUso: existe && (vivo.cwds.map { _ in vivo.temProcessoDentro(caminho) } ?? false),
                travada: fm.fileExists(atPath: admin.appendingPathComponent("locked").path),
                pastaSumiu: !existe,
                sessaoCrew: caminho.contains(PoliticaWorktrees.pastaSessoesCrew)))
        }
        return lista.sorted { ($0.ultimaMudanca ?? .distantPast) > ($1.ultimaMudanca ?? .distantPast) }
    }
}
