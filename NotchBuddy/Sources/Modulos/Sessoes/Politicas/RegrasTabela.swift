import Foundation

// As regras de uma tabela na conversa, sem tela: o que é coluna de número (alinha à direita e
// ordena por valor), como repartir a largura (coluna curta fica do tamanho dela, a longa leva o
// resto, e quando não cabe rola para o lado em vez de espremer), o que é célula de lista
// ("a · b · c" vira um item por linha), ordenar, filtrar e exportar (texto tabulado para colar
// em planilha, CSV, Markdown e HTML). Só Foundation; conferida por `testes/entregaveis/conferir.sh`.

enum RegrasTabela {

    // MARK: Texto da célula

    /// A célula sem as marcas do markdown: é o que se copia e o que vai para a planilha.
    static func limpo(_ celula: String) -> String {
        // Quase toda célula é texto puro: só passa pelas regras quem tem marca.
        guard celula.contains(where: { "*_~`[<".contains($0) }) else { return celula.trimmingCharacters(in: .whitespaces) }
        var s = celula.replacingOccurrences(of: #"<br\s*/?>"#, with: " ", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"\[([^\]]+)\]\(([^)\s]+)\)"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(\*\*|__)(.+?)\1"#, with: "$2", options: .regularExpression)
        s = s.replacingOccurrences(of: #"~~(.+?)~~"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"`([^`]+)`"#, with: "$1", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespaces)
    }

    // MARK: Números

    private static let vazios: Set<String> = ["", "-", "—", "–", "n/d", "n/a", "nd", "na", "…", "..."]
    private static let numero = try? NSRegularExpression(
        pattern: #"^[+\-−–]?\s?(R\$|US\$|\$|€|£)?\s?[+\-−–]?\d[\d.,]*\s?(%|‰|[A-Za-zµ°º²³]{1,5}(/[A-Za-z]{1,4})?)?$"#)

    static func ehVazio(_ s: String) -> Bool { vazios.contains(s.trimmingCharacters(in: .whitespaces).lowercased()) }

    /// "12", "1.234,56", "R$ 71,78", "-7,5%", "12 kg", "3 un".
    static func ehNumero(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard let numero, !t.isEmpty else { return false }
        return numero.firstMatch(in: t, range: NSRange(location: 0, length: (t as NSString).length)) != nil
    }

    /// O valor de um número escrito à brasileira ("1.234,56") ou com ponto decimal ("0.25", "12.5").
    static func valor(_ s: String) -> Double? {
        guard ehNumero(s) else { return nil }
        let negativo = s.contains { "-−–".contains($0) }
        var d = String(s.filter { $0.isNumber || $0 == "." || $0 == "," })
        while let u = d.last, u == "." || u == "," { d.removeLast() }
        let virgulas = d.filter { $0 == "," }.count, pontos = d.filter { $0 == "." }.count
        if virgulas > 0 && pontos > 0 {
            // Os dois: o que aparece por último é o decimal.
            let decimal: Character = d.lastIndex(of: ",")! > d.lastIndex(of: ".")! ? "," : "."
            d = String(d.filter { $0 != (decimal == "," ? "." : ",") }).replacingOccurrences(of: ",", with: ".")
        } else if virgulas == 1 {
            d = d.replacingOccurrences(of: ",", with: ".")
        } else if virgulas > 1 {
            d = d.replacingOccurrences(of: ",", with: "")
        } else if pontos > 1 {
            d = d.replacingOccurrences(of: ".", with: "")
        } else if pontos == 1 {
            // Um ponto só: "1.234" é milhar; "0.125", "12.5" e "1234.567" são decimais.
            let partes = d.split(separator: ".", omittingEmptySubsequences: false)
            if partes.count == 2, partes[1].count == 3, (1...3).contains(partes[0].count), partes[0] != "0" {
                d = d.replacingOccurrences(of: ".", with: "")
            }
        }
        guard let v = Double(d) else { return nil }
        return negativo ? -v : v
    }

    /// Coluna de número: tem pelo menos um valor e quase tudo o que não é vazio é número.
    static func colunaNumerica(_ celulas: [String]) -> Bool {
        let cheias = celulas.map(limpo).filter { !ehVazio($0) }
        guard !cheias.isEmpty else { return false }
        let numeros = cheias.filter(ehNumero).count
        return Double(numeros) >= Double(cheias.count) * 0.8
    }

    // MARK: Célula de lista

    private static let separadores = ["<br>", " · ", " • ", ";", " | "]

    private static func partir(_ celula: String, por separador: String) -> [String] {
        let s = separador == "<br>"
            ? celula.replacingOccurrences(of: #"<br\s*/?>"#, with: "<br>", options: [.regularExpression, .caseInsensitive])
            : celula
        return s.components(separatedBy: separador).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// O separador que faz desta coluna uma coluna de lista — alguma célula com três itens ou
    /// mais, ou metade das células com dois. Sem isso, o texto fica corrido.
    static func separadorDeLista(_ celulas: [String]) -> String? {
        let cheias = celulas.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !cheias.isEmpty else { return nil }
        for sep in separadores {
            let contagens = cheias.map { partir($0, por: sep).count }
            let comDois = contagens.filter { $0 >= 2 }.count
            if contagens.contains(where: { $0 >= 3 }) || (comDois >= 2 && comDois * 2 >= cheias.count) { return sep }
        }
        return nil
    }

    static func itens(_ celula: String, separador: String) -> [String] { partir(celula, por: separador) }

    // MARK: Larguras

    struct Larguras: Equatable {
        var colunas: [Double]
        /// Não coube nem no mínimo: a tabela fica mais larga que o espaço e rola para o lado.
        var rola: Bool
        var total: Double { colunas.reduce(0, +) }
    }

    /// Reparte a largura. `naturais`: cada coluna numa linha só (com as margens da célula);
    /// `minimas`: o menor tamanho em que ela ainda se lê bem. Cabendo tudo, cada uma fica com o
    /// natural (a tabela não estica à toa). Não cabendo, as colunas curtas ficam com o natural e
    /// as longas dividem o que sobra, na proporção do conteúdo. Se nem os mínimos cabem, cada
    /// coluna fica num tamanho confortável (até `teto`) e a tabela rola para o lado.
    static func larguras(naturais: [Double], minimas: [Double], disponivel: Double, teto: Double = 300) -> Larguras {
        let n = naturais.count
        guard n > 0 else { return Larguras(colunas: [], rola: false) }
        let mins = (0..<n).map { min(naturais[$0], $0 < minimas.count ? minimas[$0] : naturais[$0]) }
        if naturais.reduce(0, +) <= disponivel { return Larguras(colunas: naturais, rola: false) }
        if mins.reduce(0, +) > disponivel {
            return Larguras(colunas: (0..<n).map { min(naturais[$0], max(mins[$0], teto)) }, rola: true)
        }
        var out = [Double](repeating: 0, count: n)
        var livres = Set(0..<n)
        var resto = disponivel
        // Colunas curtas: quem cabe na cota igual fica com o natural e devolve a sobra.
        while !livres.isEmpty {
            let cota = resto / Double(livres.count)
            let curtas = livres.filter { naturais[$0] <= cota }
            if curtas.isEmpty { break }
            for c in curtas { out[c] = naturais[c]; resto -= naturais[c]; livres.remove(c) }
        }
        // Colunas longas: o resto, na proporção do conteúdo, sem descer do mínimo de nenhuma.
        while !livres.isEmpty {
            let soma = livres.reduce(0) { $0 + naturais[$1] }
            let apertadas = livres.filter { resto * naturais[$0] / soma < mins[$0] }
            if apertadas.isEmpty {
                for c in livres { out[c] = resto * naturais[c] / soma }
                break
            }
            for c in apertadas { out[c] = mins[c]; resto -= mins[c]; livres.remove(c) }
        }
        // As curtas levaram tanto que uma longa ficou no mínimo e a conta passou: quem está acima
        // do mínimo devolve o excesso, na proporção da folga.
        let passou = out.reduce(0, +) - disponivel
        let folga = (0..<n).reduce(0) { $0 + (out[$1] - mins[$1]) }
        if passou > 0, folga > 0 {
            for c in 0..<n { out[c] -= passou * (out[c] - mins[c]) / folga }
        }
        return Larguras(colunas: out, rola: false)
    }

    // MARK: Ordenar e filtrar

    /// A ordem das linhas (índices) por uma coluna. Número por valor; texto sem ligar para
    /// maiúscula nem acento. Vazio vai sempre para o fim. Empate mantém a ordem original.
    static func ordenar(_ linhas: [[String]], coluna: Int, crescente: Bool, numerica: Bool) -> [Int] {
        let chaves: [(texto: String, valor: Double?, vazio: Bool)] = linhas.map { l in
            let t = coluna < l.count ? limpo(l[coluna]) : ""
            return (t, numerica ? valor(t) : nil, ehVazio(t))
        }
        return linhas.indices.sorted { a, b in
            let x = chaves[a], y = chaves[b]
            if x.vazio != y.vazio { return y.vazio }
            if numerica {
                switch (x.valor, y.valor) {
                case let (p?, q?) where p != q: return crescente ? p < q : p > q
                case (_?, nil): return true
                case (nil, _?): return false
                default: break
                }
            }
            let c = x.texto.compare(y.texto, options: [.caseInsensitive, .diacriticInsensitive, .numeric],
                                    locale: Locale(identifier: "pt_BR"))
            if c == .orderedSame { return a < b }
            return crescente ? c == .orderedAscending : c == .orderedDescending
        }
    }

    private static func dobrar(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "pt_BR"))
    }

    /// As linhas (índices) em que todas as palavras do filtro aparecem, em qualquer coluna.
    static func filtrar(_ linhas: [[String]], texto: String) -> [Int] {
        let termos = dobrar(texto).split(separator: " ").map(String.init)
        guard !termos.isEmpty else { return Array(linhas.indices) }
        return linhas.indices.filter { i in
            let linha = dobrar(linhas[i].map(limpo).joined(separator: "\t"))
            return termos.allSatisfy { linha.contains($0) }
        }
    }

    // MARK: Exportar

    private static func umaLinha(_ s: String) -> String {
        limpo(s).replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ")
    }

    /// Texto tabulado: cola em planilha (Numbers, Excel, Planilhas) já separado em células.
    static func tsv(cabecalho: [String], linhas: [[String]]) -> String {
        ([cabecalho] + linhas).map { $0.map(umaLinha).joined(separator: "\t") }.joined(separator: "\n")
    }

    /// CSV. O padrão é ponto e vírgula, que é o que o Excel em português abre direto em colunas
    /// (e deixa a vírgula decimal em paz).
    static func csv(cabecalho: [String], linhas: [[String]], separador: String = ";") -> String {
        func campo(_ s: String) -> String {
            let t = limpo(s)
            guard t.contains(separador) || t.contains("\"") || t.contains("\n") || t.hasPrefix(" ") || t.hasSuffix(" ") else { return t }
            return "\"" + t.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return ([cabecalho] + linhas).map { $0.map(campo).joined(separator: separador) }.joined(separator: "\r\n") + "\r\n"
    }

    /// Markdown de novo, com as marcas originais das células e o alinhamento de cada coluna.
    static func markdown(cabecalho: [String], linhas: [[String]], direita: [Bool] = []) -> String {
        func linha(_ l: [String]) -> String {
            "| " + l.map { $0.replacingOccurrences(of: "|", with: "\\|") }.joined(separator: " | ") + " |"
        }
        let tracos = "|" + cabecalho.indices.map { $0 < direita.count && direita[$0] ? "---:" : "---" }.joined(separator: "|") + "|"
        return ([linha(cabecalho), tracos] + linhas.map(linha)).joined(separator: "\n")
    }

    /// Tabela em HTML: é o que e-mail, Notas e editores de texto colam como tabela de verdade.
    static func html(cabecalho: [String], linhas: [[String]], direita: [Bool] = []) -> String {
        func texto(_ s: String) -> String {
            limpo(s).replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
        }
        func linha(_ l: [String], _ marca: String) -> String {
            "<tr>" + l.enumerated().map { c, s in
                "<\(marca)\(c < direita.count && direita[c] ? " align=\"right\"" : "")>\(texto(s))</\(marca)>"
            }.joined() + "</tr>"
        }
        return "<meta charset=\"utf-8\"><table>" + linha(cabecalho, "th") + linhas.map { linha($0, "td") }.joined() + "</table>"
    }
}
