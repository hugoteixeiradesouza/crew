import Foundation

// O que pode sair de um projeto parado.
//
// Nada sai pelo nome: a pasta só vale quando a pasta acima dela é, comprovadamente, um projeto
// do tipo certo (marcador como `package.json`, `Cargo.toml`, `.csproj`). E as proteções vêm antes:
// projeto dentro de Fotos, Música, Library ou de uma sessão do Crew não expõe nada.
// Chamada na varredura, na revalidação antes de confirmar e de novo imediatamente antes de mover.

enum PoliticaArtefatos {
    /// Pastas da home em que projeto nenhum é procurado nem limpo.
    static let raizesProibidas = ["Library", "Pictures", "Music", "Movies", "Public", "Applications"]

    /// A regra que permite tirar `url`, ou o motivo da recusa.
    static func avaliar(_ url: URL, acesso: AcessoVarredura) -> Result<RegraArtefato, Recusa> {
        let u = url.standardizedFileURL
        let c = u.path
        let home = PoliticaSeguranca.home
        guard c.hasPrefix(home + "/") else { return .failure(.foraDaHome) }
        let rel = c.dropFirst(home.count + 1).split(separator: "/").map(String.init)
        guard let topo = rel.first, !raizesProibidas.contains(topo) else { return .failure(.localProtegido) }
        // Worktrees das sessões do Crew: nunca, em nenhum nível.
        if rel.contains(".coucou-sessoes") { return .failure(.sessaoDoCrew) }
        if PoliticaSeguranca.pedeAdministrador(u) { return .failure(.localProtegido) }
        for p in PoliticaSeguranca.nuncaApagarPrefixos(home: home) where c == p || c.hasPrefix(p + "/") {
            return .failure(.localProtegido)
        }
        // Antes de qualquer acesso que siga link: sem Acesso Total, nada em Mesa/Documentos/Downloads.
        guard LocaisProtegidos.podeLer(u, acesso: acesso) else { return .failure(.semPermissao) }
        guard let atrib = try? FileManager.default.attributesOfItem(atPath: c),
              let tipo = atrib[.type] as? FileAttributeType else { return .failure(.sumiu) }
        guard tipo == .typeDirectory else { return .failure(.naoEPasta) }

        guard let candidatas = CatalogoArtefatos.porNomeDePasta[u.lastPathComponent] else { return .failure(.foraDoCatalogo) }
        var recusada = false
        for r in candidatas {
            // Sobe tantos níveis quanto a pasta da regra tem (`ios/Pods` ancora na raiz do projeto).
            var raiz = u
            for _ in 0..<r.pasta.split(separator: "/").count { raiz.deleteLastPathComponent() }
            guard raiz.path.hasPrefix(home + "/"), raiz.path == u.path.dropLastPath(r.pasta) else { continue }
            // Projeto escondido (pasta com ponto entre a home e a raiz) não entra.
            let relRaiz = raiz.path.dropFirst(home.count + 1).split(separator: "/")
            if relRaiz.contains(where: { $0.hasPrefix(".") }) { continue }
            guard r.valeNaRaiz(raiz) else { continue }
            if r.recusa(u) { recusada = true; continue }
            return .success(r)
        }
        return .failure(recusada ? .guardaEstado : .naoEProjeto)
    }

    enum Recusa: Error, Sendable {
        case foraDaHome, localProtegido, sessaoDoCrew, semPermissao, sumiu, naoEPasta, foraDoCatalogo,
             naoEProjeto, guardaEstado

        var motivo: String {
            switch self {
            case .foraDaHome: return "Fora da sua pasta pessoal."
            case .localProtegido: return "Local protegido — nunca sai."
            case .sessaoDoCrew: return "Dentro de uma sessão do Crew."
            case .semPermissao: return "Pede permissão do macOS (sem Acesso Total ao Disco)."
            case .sumiu: return "Não existe mais."
            case .naoEPasta: return "Não é mais uma pasta comum (virou link ou arquivo)."
            case .foraDoCatalogo: return "Não é um artefato conhecido."
            case .naoEProjeto: return "A pasta acima não é mais um projeto do tipo certo."
            case .guardaEstado: return "Guarda estado que não se refaz (ex.: terraform.tfstate)."
            }
        }
    }
}

private extension String {
    /// `"/a/b/ios/Pods".dropLastPath("ios/Pods") == "/a/b"`.
    func dropLastPath(_ rel: String) -> String {
        hasSuffix("/" + rel) ? String(dropLast(rel.count + 1)) : self
    }
}
