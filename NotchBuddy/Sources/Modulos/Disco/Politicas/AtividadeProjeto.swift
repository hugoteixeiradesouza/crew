import Darwin
import Foundation

// Se os artefatos de um projeto podem aparecer. As duas perguntas olham o PROJETO, nunca só a
// pasta do artefato:
// 1. Em uso agora: algum processo trabalha dentro dele, ou o git tem lock. Esconde sempre.
// 2. Usado há pouco: a idade conta do sinal de uso mais novo em qualquer lugar do projeto
//    (`.git/index`, `HEAD`, `logs/HEAD`, `FETCH_HEAD`, arquivos do projeto). O `node_modules`
//    sozinho só diz quando o `npm install` rodou, não se alguém ainda mexe no projeto.
// A terceira pergunta (mudança não commitada) precisa do `git` e fica em `VarreduraProjetos`.

enum AtividadeProjeto {
    /// Máximo de entradas lidas na caminhada por projeto. Passou disso, conta como "nada recente
    /// achado" e o projeto é julgado pelas datas do git e dos artefatos.
    static let limiteEntradas = 20_000

    /// Arquivos que o git reescreve em commit, checkout, fetch e atualização do índice.
    static let arquivosDeAtividadeGit = ["index", "HEAD", "logs/HEAD", "FETCH_HEAD", "ORIG_HEAD"]
    static let locksGit = ["index.lock", "HEAD.lock"]

    /// cwd de todo processo do usuário que dá para inspecionar (menos `/`), via `proc_pidinfo`.
    /// Nil quando a lista de processos não pôde ser lida — aí ninguém aparece.
    static func pastasDeTrabalho() -> Set<String>? {
        let n = proc_listallpids(nil, 0)
        guard n > 0 else { return nil }
        var lista = [pid_t](repeating: 0, count: Int(n) + 64)
        let lidos = proc_listallpids(&lista, Int32(MemoryLayout<pid_t>.size * lista.count))
        guard lidos > 0 else { return nil }
        var dirs: Set<String> = []
        for pid in lista.prefix(Int(lidos)) where pid > 0 {
            var info = proc_vnodepathinfo()
            let tam = MemoryLayout<proc_vnodepathinfo>.stride
            guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, Int32(tam)) == Int32(tam) else { continue }
            let c = withUnsafePointer(to: &info.pvi_cdir.vip_path) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
            }
            guard !c.isEmpty, c != "/" else { continue }
            dirs.insert((c as NSString).standardizingPath)
        }
        return dirs
    }

    /// Algum processo com cwd dentro do projeto, ou lock do git.
    static func emUso(raiz: URL, cwds: Set<String>, acesso: AcessoVarredura) -> String? {
        let grafias = grafiasDe(raiz, acesso: acesso)
        if cwds.contains(where: { d in grafias.contains { d == $0 || d.hasPrefix($0 + "/") } }) {
            return "Tem um programa trabalhando dentro do projeto agora."
        }
        if let g = diretorioGit(doProjeto: raiz, acesso: acesso),
           locksGit.contains(where: { existeSemSeguir(g.appendingPathComponent($0)) }) {
            return "O git está mexendo no repositório (lock)."
        }
        return nil
    }

    /// Algo no projeto mudou depois de `corte`? Sinais baratos primeiro, depois uma caminhada
    /// limitada que para no primeiro item recente.
    static func temAtividade(desde corte: Date, raiz: URL, artefatos: [URL], acesso: AcessoVarredura) -> Bool {
        func recente(_ u: URL) -> Bool { (dataSemSeguir(u) ?? .distantPast) > corte }
        if artefatos.contains(where: recente) { return true }
        if let g = diretorioGit(doProjeto: raiz, acesso: acesso),
           arquivosDeAtividadeGit.contains(where: { recente(g.appendingPathComponent($0)) }) { return true }
        if recente(raiz) { return true }
        guard raiz.path != PoliticaSeguranca.home else { return false }

        let chaves: [URLResourceKey] = [.contentModificationDateKey, .isDirectoryKey, .isSymbolicLinkKey]
        guard let e = FileManager.default.enumerator(at: raiz, includingPropertiesForKeys: chaves, options: [],
                                                     errorHandler: { _, _ in true }) else { return false }
        var lidas = 0
        for case let u as URL in e {
            lidas += 1
            if lidas > limiteEntradas || Task.isCancelled { return false }
            guard let v = try? u.resourceValues(forKeys: Set(chaves)), v.isSymbolicLink != true else { continue }
            if let d = v.contentModificationDate, d > corte { return true }
            guard v.isDirectory == true else { continue }
            // Árvores de dependência/build mudam no install/build e são o que está sendo oferecido.
            if u.lastPathComponent == ".git" || CatalogoArtefatos.nomesDeArtefato.contains(u.lastPathComponent)
                || !LocaisProtegidos.podeLer(u, acesso: acesso) {
                e.skipDescendants()
            }
        }
        return false
    }

    /// Sinal de uso mais novo entre os baratos (git, raiz) — só para mostrar "parado há…".
    static func ultimoSinal(raiz: URL, acesso: AcessoVarredura) -> Date? {
        var datas = [dataSemSeguir(raiz)]
        if let g = diretorioGit(doProjeto: raiz, acesso: acesso) {
            datas += arquivosDeAtividadeGit.map { dataSemSeguir(g.appendingPathComponent($0)) }
        }
        return datas.compactMap { $0 }.max()
    }

    /// Raiz do repositório que contém o projeto (pode estar acima, num monorepo). Para abaixo da
    /// home: um repositório de dotfiles em `~` faria todo projeto parecer ocupado.
    static func raizDoRepositorio(_ projeto: URL) -> URL? {
        let home = PoliticaSeguranca.home
        var c = projeto.standardizedFileURL
        while c.path.hasPrefix(home + "/") {
            if existeSemSeguir(c.appendingPathComponent(".git")) { return c }
            c.deleteLastPathComponent()
        }
        return nil
    }

    /// Onde o git guarda os dados do repositório: `<repo>/.git`, ou, numa worktree ligada, a
    /// pasta que o arquivo `.git` aponta. Nil se não der para ler sem pedir permissão.
    static func diretorioGit(doProjeto projeto: URL, acesso: AcessoVarredura) -> URL? {
        guard let repo = raizDoRepositorio(projeto) else { return nil }
        let dotGit = repo.appendingPathComponent(".git")
        guard LocaisProtegidos.podeLer(dotGit, acesso: acesso),
              let atrib = try? FileManager.default.attributesOfItem(atPath: dotGit.path),
              let tipo = atrib[.type] as? FileAttributeType else { return nil }
        if tipo == .typeDirectory { return dotGit }
        guard tipo == .typeRegular, let texto = try? String(contentsOf: dotGit, encoding: .utf8) else { return nil }
        for linha in texto.split(whereSeparator: \.isNewline) {
            let l = linha.trimmingCharacters(in: .whitespaces)
            guard l.lowercased().hasPrefix("gitdir:") else { continue }
            let p = l.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
            let url = p.hasPrefix("/") ? URL(fileURLWithPath: p) : repo.appendingPathComponent(p)
            return LocaisProtegidos.podeLer(url, acesso: acesso) ? url : nil
        }
        return nil
    }

    /// `lstat`: um link não é seguido.
    static func dataSemSeguir(_ u: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: u.path))?[.modificationDate] as? Date
    }

    /// A raiz como achada e o caminho real (o cwd dos processos vem com os links resolvidos).
    private static func grafiasDe(_ raiz: URL, acesso: AcessoVarredura) -> [String] {
        var g = [raiz.path]
        let real = acesso == .limitado ? LocaisProtegidos.caminhoReal(de: raiz.path) : raiz.resolvingSymlinksInPath().path
        if let real, real != raiz.path { g.append(real) }
        return g
    }
}
