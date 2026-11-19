import Foundation

// Regras puras do campo de endereço: o que guardar no histórico, o que completar em linha e
// em que ordem as sugestões aparecem. Só Foundation — dá para compilar e testar sozinho
// (`testes/navegador/conferir.sh`). Nada aqui toca disco nem rede.

/// Uma página visitada.
struct VisitaNav: Codable, Equatable, Sendable {
    var url: String
    var titulo: String
    /// A última vez.
    var ultima: Date
    /// Quantas vezes.
    var vezes: Int
}

/// Uma aba que já está aberta (para "Ir para a aba").
struct AbaAbertaNav: Equatable, Sendable {
    var id: String
    var url: String
    var titulo: String
    /// O espaço onde ela está.
    var espaco: String
}

/// Uma linha da lista de sugestões.
struct SugestaoNav: Identifiable, Equatable, Sendable {
    enum Tipo: String, Sendable {
        /// O site mais provável (o que o campo completou) ou outro site que casa.
        case site
        /// O que foi digitado, aberto como endereço.
        case endereco
        /// Buscar o que foi digitado.
        case buscar
        /// Uma aba já aberta: vai para ela em vez de abrir outra.
        case aba
        /// Uma página do histórico.
        case pagina
        /// Uma busca sugerida (vem do buscador).
        case busca
    }

    var tipo: Tipo
    var titulo: String
    /// O que vai depois do título, apagado (domínio, endereço).
    var detalhe: String
    /// Para onde vai. Em `buscar` e `busca`, o texto da busca.
    var destino: String
    var aba: String? = nil
    var espaco: String? = nil

    var id: String { tipo.rawValue + "|" + destino + "|" + (aba ?? "") }
    var ehBusca: Bool { tipo == .buscar || tipo == .busca }
}

/// O que o campo completa em linha: o resto do endereço, que fica selecionado.
struct CompletarNav: Equatable, Sendable {
    /// O que entra depois do que foi digitado.
    var resto: String
    /// Para onde o Enter leva.
    var destino: String
    /// O domínio (sem "www.") ou o endereço completado, como aparece no campo.
    var mostrado: String
}

// MARK: - Histórico

enum HistoricoRegras {
    /// Quantas páginas o histórico guarda.
    static let limite = 5000

    /// Só página da web entra (http/https). `about:`, `data:`, `file:`, `blob:` ficam de fora.
    static func guardavel(_ url: String) -> Bool {
        guard let c = URLComponents(string: url), let esquema = c.scheme?.lowercased(),
              esquema == "http" || esquema == "https", let h = c.host, !h.isEmpty else { return false }
        return true
    }

    /// A mesma página com âncoras diferentes (`#secao`) é uma página só.
    static func normalizar(_ url: String) -> String {
        guard var c = URLComponents(string: url) else { return url }
        c.fragment = nil
        return c.string ?? url
    }

    /// Conta a visita. Devolve false se o endereço não é guardável.
    @discardableResult
    static func registrar(_ visitas: inout [VisitaNav], url: String, titulo: String, agora: Date,
                          limite: Int = limite) -> Bool {
        guard guardavel(url) else { return false }
        let u = normalizar(url)
        if let i = visitas.firstIndex(where: { $0.url == u }) {
            visitas[i].vezes += 1
            visitas[i].ultima = agora
            if !titulo.isEmpty { visitas[i].titulo = titulo }
        } else {
            visitas.append(VisitaNav(url: u, titulo: titulo, ultima: agora, vezes: 1))
            podar(&visitas, limite: limite)
        }
        return true
    }

    /// O título chegou depois da visita: guarda sem contar outra.
    @discardableResult
    static func intitular(_ visitas: inout [VisitaNav], url: String, titulo: String) -> Bool {
        let u = normalizar(url)
        guard !titulo.isEmpty, let i = visitas.firstIndex(where: { $0.url == u }), visitas[i].titulo != titulo else { return false }
        visitas[i].titulo = titulo
        return true
    }

    /// Passou do limite: saem as mais antigas.
    static func podar(_ visitas: inout [VisitaNav], limite: Int) {
        guard visitas.count > limite, limite >= 0 else { return }
        visitas.sort { $0.ultima > $1.ultima }
        visitas.removeLast(visitas.count - limite)
    }
}

// MARK: - Sugestões

enum SugestoesEndereco {
    /// Quantas linhas de cada tipo, no máximo.
    static let maxAbas = 2, maxPaginas = 4, maxSites = 2, maxBuscas = 5

    // MARK: Texto

    /// Minúsculas e sem acento: "Previsão" casa com "previsao".
    static func plano(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
    }

    /// Sem "https://", "http://" e "www." na frente.
    static func semPrefixo(_ s: String) -> String {
        var t = s
        for p in ["https://", "http://"] where t.lowercased().hasPrefix(p) { t = String(t.dropFirst(p.count)) }
        if t.lowercased().hasPrefix("www.") { t = String(t.dropFirst(4)) }
        return t
    }

    /// O domínio de um endereço, sem "www." e com a porta quando ela faz parte (localhost:3000).
    static func dominio(_ url: String) -> String? {
        guard let c = URLComponents(string: url), var h = c.host?.lowercased(), !h.isEmpty else { return nil }
        if h.hasPrefix("www.") { h = String(h.dropFirst(4)) }
        if let p = c.port { h += ":\(p)" }
        return h
    }

    /// A raiz do site de um endereço ("https://www.exemplo.com/").
    static func raiz(_ url: String) -> String? {
        guard let c = URLComponents(string: url), let esquema = c.scheme, let h = c.host else { return nil }
        return esquema + "://" + h + (c.port.map { ":\($0)" } ?? "") + "/"
    }

    /// O endereço como se digita: sem esquema, sem "www." e sem a barra do fim.
    static func digitavel(_ url: String) -> String {
        var t = semPrefixo(url)
        if t.hasSuffix("/") { t.removeLast() }
        return t
    }

    /// Parece endereço (tem ponto e não tem espaço, ou é localhost / IP / tem "://").
    static func pareceEndereco(_ texto: String) -> Bool {
        let t = texto.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !t.contains(" ") else { return false }
        if t.contains("://") { return true }
        let hospedeiro = t.split(separator: "/").first.map(String.init) ?? t
        let nome = hospedeiro.split(separator: ":").first.map(String.init) ?? hospedeiro
        if nome == "localhost" || nome.range(of: #"^\d{1,3}(\.\d{1,3}){3}$"#, options: .regularExpression) != nil { return true }
        return nome.contains(".") && !nome.hasSuffix(".") && !nome.hasPrefix(".")
    }

    // MARK: Peso

    /// Quanto uma página pesa: mais visitas e visita mais recente pesam mais. Uma visita de
    /// hoje vale cinco de dois meses atrás; site muito usado não some por uma semana parado.
    static func peso(_ v: VisitaNav, agora: Date) -> Double {
        let dias = max(0, agora.timeIntervalSince(v.ultima) / 86400)
        return Double(min(v.vezes, 200)) * (0.2 + 0.8 * pow(0.5, dias / 14))
    }

    private struct Site {
        var dominio: String
        var peso = 0.0
        /// A raiz, no esquema da visita que mais pesa.
        var raiz: String
        var pesoDaRaiz = 0.0
        /// O título da página inicial, se ela foi visitada.
        var titulo = ""
    }

    private static func sites(_ visitas: [VisitaNav], agora: Date) -> [Site] {
        var mapa: [String: Site] = [:]
        for v in visitas {
            guard let d = dominio(v.url), let r = raiz(v.url) else { continue }
            let p = peso(v, agora: agora)
            var s = mapa[d] ?? Site(dominio: d, raiz: r)
            s.peso += p
            if p > s.pesoDaRaiz { s.pesoDaRaiz = p; s.raiz = r }
            if HistoricoRegras.normalizar(v.url) == r || v.url + "/" == r, !v.titulo.isEmpty { s.titulo = v.titulo }
            mapa[d] = s
        }
        // Peso igual: ordem alfabética, para a resposta não mudar de uma vez para a outra.
        return mapa.values.sorted { $0.peso != $1.peso ? $0.peso > $1.peso : $0.dominio < $1.dominio }
    }

    // MARK: Completar em linha

    /// O que completar no campo: o domínio que mais pesa entre os que começam com o que foi
    /// digitado ("git" → "github.com"; "www.git" e "https://git" também). Com barra no texto
    /// ("github.com/an"), completa a página visitada que começa assim. nil = nada a completar.
    static func completar(_ texto: String, visitas: [VisitaNav], agora: Date) -> CompletarNav? {
        guard !texto.isEmpty, !texto.contains(" ") else { return nil }
        let q = semPrefixo(texto).lowercased()
        guard !q.isEmpty else { return nil }

        if q.contains("/") {
            var melhor: (v: VisitaNav, d: String, p: Double)?
            for v in visitas {
                let d = digitavel(v.url)
                guard d.lowercased().hasPrefix(q), d.count > q.count else { continue }
                let p = peso(v, agora: agora)
                if melhor == nil || p > melhor!.p || (p == melhor!.p && d < melhor!.d) { melhor = (v, d, p) }
            }
            guard let m = melhor else { return nil }
            return CompletarNav(resto: String(m.d.dropFirst(q.count)), destino: m.v.url, mostrado: m.d)
        }

        guard let s = sites(visitas, agora: agora).first(where: { $0.dominio.hasPrefix(q) && $0.dominio.count > q.count }) else { return nil }
        return CompletarNav(resto: String(s.dominio.dropFirst(q.count)), destino: s.raiz, mostrado: s.dominio)
    }

    // MARK: Lista

    /// Todas as palavras digitadas aparecem no título ou no endereço?
    private static func casa(_ termos: [String], titulo: String, url: String) -> Double {
        guard !termos.isEmpty else { return 0 }
        let t = plano(titulo), u = plano(digitavel(url))
        var soma = 0.0
        for termo in termos {
            if u.hasPrefix(termo) { soma += 1 }                                   // começo do endereço
            else if t.hasPrefix(termo) { soma += 0.9 }                            // começo do título
            else if t.contains(" " + termo) || u.contains("/" + termo) || u.contains("." + termo) { soma += 0.75 } // começo de palavra
            else if t.contains(termo) || u.contains(termo) { soma += 0.5 }        // no meio
            else { return 0 }
        }
        return soma / Double(termos.count)
    }

    /// Há algo já visitado (ou aberto) que casa com o texto? Se não há, vale pedir buscas sugeridas.
    static func querBuscas(_ texto: String, visitas: [VisitaNav], abas: [AbaAbertaNav], agora: Date) -> Bool {
        let t = texto.trimmingCharacters(in: .whitespaces)
        guard t.count >= 2, !pareceEndereco(t) else { return false }
        return !montar(texto: t, visitas: visitas, abas: abas, buscas: [], agora: agora)
            .contains { $0.tipo == .site || $0.tipo == .pagina || $0.tipo == .aba }
    }

    /// A lista, na ordem em que aparece. A primeira linha é a que o Enter faz.
    ///  1. o site que o campo completou;
    ///  2. o texto digitado: abrir como endereço (se parece um) e buscar;
    ///  3. abas já abertas que casam ("Ir para a aba");
    ///  4. páginas do histórico;
    ///  5. outros sites que casam;
    ///  6. buscas sugeridas (só chegam quando nada visitado casa).
    static func montar(texto: String, visitas: [VisitaNav], abas: [AbaAbertaNav], buscas: [String],
                       abaAtual: String? = nil, agora: Date) -> [SugestaoNav] {
        let t = texto.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return [] }
        var lista: [SugestaoNav] = []
        var usados = Set<String>()   // endereços que já têm linha
        let termos = plano(semPrefixo(t)).split(separator: " ").map(String.init)
        let todosSites = sites(visitas, agora: agora)

        let c = completar(t, visitas: visitas, agora: agora)
        if let c {
            let site = todosSites.first { $0.raiz == c.destino }
            let titulo = c.destino == site?.raiz ? (site?.titulo ?? "") : (visitas.first { $0.url == c.destino }?.titulo ?? "")
            lista.append(SugestaoNav(tipo: .site, titulo: titulo.isEmpty ? c.mostrado : titulo, detalhe: c.mostrado, destino: c.destino))
            usados.insert(digitavel(c.destino).lowercased())
        }

        if pareceEndereco(t), !usados.contains(digitavel(t).lowercased()) {
            lista.append(SugestaoNav(tipo: .endereco, titulo: t, detalhe: "Abrir endereço", destino: t))
            usados.insert(digitavel(t).lowercased())
        }
        lista.append(SugestaoNav(tipo: .buscar, titulo: t, detalhe: "Buscar", destino: t))

        // Abas abertas (fora a que está na tela).
        var abasQueCasam: [(AbaAbertaNav, Double)] = []
        for a in abas where a.id != abaAtual {
            let pontos = casa(termos, titulo: a.titulo, url: a.url)
            if pontos > 0 { abasQueCasam.append((a, pontos)) }
        }
        abasQueCasam.sort { (x: (AbaAbertaNav, Double), y: (AbaAbertaNav, Double)) -> Bool in
            x.1 != y.1 ? x.1 > y.1 : x.0.titulo < y.0.titulo
        }
        var abasVistas = Set<String>()
        for (a, _) in abasQueCasam where abasVistas.count < maxAbas {
            let chave = digitavel(a.url).lowercased()
            guard abasVistas.insert(chave).inserted else { continue }
            lista.append(SugestaoNav(tipo: .aba, titulo: a.titulo.isEmpty ? (dominio(a.url) ?? a.url) : a.titulo,
                                     detalhe: dominio(a.url) ?? a.url, destino: a.url, aba: a.id, espaco: a.espaco))
            usados.insert(chave)
        }

        // Páginas do histórico: casamento × peso.
        var paginas: [(VisitaNav, Double)] = []
        for v in visitas {
            let pontos = casa(termos, titulo: v.titulo, url: v.url)
            if pontos > 0 { paginas.append((v, pontos * (1 + log2(1 + peso(v, agora: agora))))) }
        }
        paginas.sort { (x: (VisitaNav, Double), y: (VisitaNav, Double)) -> Bool in
            x.1 != y.1 ? x.1 > y.1 : x.0.url < y.0.url
        }
        var n = 0
        for (v, _) in paginas where n < maxPaginas {
            let chave = digitavel(v.url).lowercased()
            guard usados.insert(chave).inserted else { continue }
            lista.append(SugestaoNav(tipo: .pagina, titulo: v.titulo.isEmpty ? digitavel(v.url) : v.titulo,
                                     detalhe: digitavel(v.url), destino: v.url))
            n += 1
        }

        // Outros sites cujo domínio casa (o digitado está no meio do nome, ou perdeu para o completado).
        n = 0
        if termos.count == 1, let termo = termos.first, !termo.contains("/") {
            for s in todosSites where n < maxSites && s.dominio.contains(termo) {
                guard usados.insert(digitavel(s.raiz).lowercased()).inserted else { continue }
                lista.append(SugestaoNav(tipo: .site, titulo: s.titulo.isEmpty ? s.dominio : s.titulo, detalhe: s.dominio, destino: s.raiz))
                n += 1
            }
        }

        // Buscas sugeridas, sem repetir a que já é "buscar o que digitei".
        var vistas: Set<String> = [plano(t)]
        n = 0
        for b in buscas where n < maxBuscas {
            let limpa = b.trimmingCharacters(in: .whitespaces)
            guard !limpa.isEmpty, vistas.insert(plano(limpa)).inserted else { continue }
            lista.append(SugestaoNav(tipo: .busca, titulo: limpa, detalhe: "", destino: limpa))
            n += 1
        }
        return lista
    }
}
