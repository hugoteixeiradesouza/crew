import Foundation

// O histórico do navegador do Crew: as páginas visitadas (endereço, título, quando, quantas
// vezes), guardadas num arquivo deste Mac (`navegador-historico.json`, só o Hugo lê). É dele que
// saem o completar do campo de endereço e as sugestões. Nada disso sai do Mac. Tem teto
// (`HistoricoRegras.limite` páginas; saem as mais antigas), dá para pausar e para limpar.

@MainActor
final class HistoricoNav {
    static let shared = HistoricoNav()

    /// "Guardar histórico" (ligado por padrão). Desligado, nada novo é gravado.
    static let chaveLigado = "modulo.navegador.historico"
    static var ligado: Bool {
        get { UserDefaults.standard.object(forKey: chaveLigado) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: chaveLigado) }
    }

    private(set) var visitas: [VisitaNav] = []
    private var gravacao: DispatchWorkItem?
    private static var arquivo: URL { HookServer.supportDir.appendingPathComponent("navegador-historico.json") }

    private init() {
        guard !CaptureTool.ativo, let data = try? Data(contentsOf: Self.arquivo) else { return }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        visitas = (try? d.decode([VisitaNav].self, from: data)) ?? []
    }

    /// Histórico de exemplo para as capturas (nada vai para o disco).
    func exemploParaCaptura() {
        let agora = Date()
        func v(_ url: String, _ titulo: String, _ vezes: Int, _ horas: Double) -> VisitaNav {
            VisitaNav(url: url, titulo: titulo, ultima: agora.addingTimeInterval(-horas * 3600), vezes: vezes)
        }
        visitas = [
            v("https://github.com/", "GitHub", 40, 2),
            v("https://github.com/anthropics/claude-code", "anthropics/claude-code: Claude Code", 12, 20),
            v("https://github.com/apple/swift/pulls", "Pull requests · apple/swift", 4, 70),
            v("https://gitlab.com/", "GitLab", 2, 90),
            v("https://git-scm.com/docs/git-rebase", "Git - git-rebase Documentation", 3, 200),
            v("https://developer.apple.com/documentation/webkit", "WebKit | Apple Developer", 6, 30),
        ]
    }

    /// A página carregou: conta a visita.
    func visitou(_ url: String, titulo: String) {
        guard Self.ligado, !CaptureTool.ativo else { return }
        if HistoricoRegras.registrar(&visitas, url: url, titulo: titulo, agora: Date()) { gravar() }
    }

    /// O título chegou (ou mudou) depois: guarda sem contar outra visita.
    func intitulou(_ url: String, titulo: String) {
        guard Self.ligado, !CaptureTool.ativo else { return }
        if HistoricoRegras.intitular(&visitas, url: url, titulo: titulo) { gravar() }
    }

    /// Junta visitas vindas de outro navegador (importação). Página que já existe fica com a
    /// maior contagem e a visita mais recente. Devolve quantas páginas eram novas.
    @discardableResult
    func importar(_ outras: [VisitaNav]) -> Int {
        var porUrl: [String: Int] = [:]
        for (i, v) in visitas.enumerated() { porUrl[v.url] = i }
        var novas = 0
        for o in outras where HistoricoRegras.guardavel(o.url) {
            let url = HistoricoRegras.normalizar(o.url)
            if let i = porUrl[url] {
                visitas[i].vezes = max(visitas[i].vezes, o.vezes)
                visitas[i].ultima = max(visitas[i].ultima, o.ultima)
                if visitas[i].titulo.isEmpty { visitas[i].titulo = o.titulo }
            } else {
                porUrl[url] = visitas.count
                visitas.append(VisitaNav(url: url, titulo: o.titulo, ultima: o.ultima, vezes: max(o.vezes, 1)))
                novas += 1
            }
        }
        HistoricoRegras.podar(&visitas, limite: HistoricoRegras.limite)
        gravar()
        return novas
    }

    /// Apaga tudo, da memória e do disco.
    func limpar() {
        visitas = []
        gravacao?.cancel()
        try? FileManager.default.removeItem(at: Self.arquivo)
    }

    private func gravar() {
        gravacao?.cancel()
        let w = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                let e = JSONEncoder()
                e.dateEncodingStrategy = .secondsSince1970
                guard let data = try? e.encode(self.visitas) else { return }
                try? data.write(to: Self.arquivo, options: .atomic)
                // Só o Hugo lê.
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.arquivo.path)
            }
        }
        gravacao = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: w)
    }
}

/// Buscas sugeridas enquanto se digita. É a única coisa do campo de endereço que sai do Mac:
/// o texto digitado vai para o serviço de sugestões do Google — o mesmo buscador que o
/// navegador do Crew já usa quando o texto não é endereço. Só é chamado quando nada já
/// visitado casa com o texto e ele não parece endereço. Sem cookies (não vai ligado à conta
/// do Google em que o Hugo esteja no navegador). Dá para desligar no "…" da barra.
enum BuscasSugeridas {
    static let chaveLigado = "modulo.navegador.sugerirBuscas"
    static var ligado: Bool {
        get { UserDefaults.standard.object(forKey: chaveLigado) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: chaveLigado) }
    }

    private static let sessao: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.httpCookieStorage = nil
        c.httpShouldSetCookies = false
        c.urlCache = nil
        c.timeoutIntervalForRequest = 3
        return URLSession(configuration: c)
    }()

    static func buscar(_ texto: String) async -> [String] {
        var c = URLComponents(string: "https://suggestqueries.google.com/complete/search")
        c?.queryItems = [URLQueryItem(name: "client", value: "firefox"), URLQueryItem(name: "hl", value: "pt-BR"),
                         URLQueryItem(name: "ie", value: "utf-8"), URLQueryItem(name: "oe", value: "utf-8"),
                         URLQueryItem(name: "q", value: texto)]
        guard let url = c?.url, let (data, _) = try? await sessao.data(from: url) else { return [] }
        return ler(data)
    }

    /// A resposta é `["o que digitei", ["sugestão 1", "sugestão 2", …], …]`.
    static func ler(_ data: Data) -> [String] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [Any], json.count > 1,
              let lista = json[1] as? [String] else { return [] }
        return lista
    }
}
