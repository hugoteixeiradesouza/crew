import Foundation

// O markdown de uma resposta do Claude, em blocos — para o app do Crew desenhar cada entregável
// do jeito dele (tabela com colunas medidas, código com linguagem, título com nível, checklist,
// citação). Regra pura, só Foundation; conferida por `testes/entregaveis/conferir.sh`.
// A ilha continua com o leitor simples do `MarkdownText`.

enum BlocoResposta: Hashable {
    enum Marca: Hashable {
        case ponto
        case numero(String)
        case feito
        case aFazer
    }

    case paragrafo(String)
    case titulo(nivel: Int, texto: String)
    case item(marca: Marca, texto: String, recuo: Int)
    case codigo(linguagem: String, texto: String)
    case tabela(TabelaResposta)
    case citacao(String)
    case fio
}

/// Uma tabela da resposta: o markdown cru de cada célula, o alinhamento pedido na linha de
/// traços (`:---`, `---:`, `:---:`) e todas as linhas com o mesmo número de colunas.
struct TabelaResposta: Hashable {
    enum Alinhamento: Hashable { case esquerda, centro, direita }

    var cabecalho: [String]
    var linhas: [[String]]
    var alinhamento: [Alinhamento?]

    var colunas: Int { cabecalho.count }
}

enum BlocosResposta {
    static func ler(_ texto: String) -> [BlocoResposta] {
        var out: [BlocoResposta] = []
        var paragrafo: [String] = []
        var codigo: (linguagem: String, recuo: Int, linhas: [String])?
        /// Houve linha em branco desde o último bloco (continuação de item não atravessa).
        var branco = false

        func fecha() {
            if !paragrafo.isEmpty { out.append(.paragrafo(paragrafo.joined(separator: "\n"))); paragrafo = [] }
        }

        let brutas = texto.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var i = 0
        while i < brutas.count {
            let bruta = brutas[i]
            let linha = bruta.trimmingCharacters(in: .whitespaces)
            i += 1

            // Bloco de código: ``` ou ~~~, com a linguagem depois da cerca.
            if linha.hasPrefix("```") || linha.hasPrefix("~~~") {
                if let c = codigo {
                    out.append(.codigo(linguagem: c.linguagem, texto: c.linhas.joined(separator: "\n")))
                    codigo = nil
                } else {
                    fecha()
                    let resto = linha.drop { $0 == "`" || $0 == "~" }.trimmingCharacters(in: .whitespaces)
                    let linguagem = resto.split(whereSeparator: { $0 == " " || $0 == "{" || $0 == "," }).first.map(String.init) ?? ""
                    codigo = (linguagem.lowercased(), recuo(bruta), [])
                }
                branco = false
                continue
            }
            if codigo != nil {
                // Cerca recuada (dentro de lista): o recuo dela sai de cada linha.
                var l = Substring(bruta)
                var tirar = codigo!.recuo
                while tirar > 0, l.first == " " { l = l.dropFirst(); tirar -= 1 }
                codigo!.linhas.append(String(l))
                continue
            }
            if linha.isEmpty { fecha(); branco = true; continue }

            // Tabela: linhas seguidas que começam com "|", ou "a | b" seguida da linha de traços.
            let semBarra = !linha.hasPrefix("|") && linha.contains("|") && i < brutas.count && ehSeparador(brutas[i]) && brutas[i].contains("|")
            if linha.hasPrefix("|") || semBarra {
                fecha()
                var linhasTabela = [linha]
                while i < brutas.count {
                    let proxima = brutas[i].trimmingCharacters(in: .whitespaces)
                    guard !proxima.isEmpty, proxima.hasPrefix("|") || (semBarra && proxima.contains("|")) else { break }
                    linhasTabela.append(proxima)
                    i += 1
                }
                if let t = tabela(linhasTabela) { out.append(.tabela(t)) }
                branco = false
                continue
            }

            if let r = linha.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
                fecha()
                var t = String(linha[r.upperBound...])
                if let fim = t.range(of: #"\s+#+$"#, options: .regularExpression) { t = String(t[..<fim.lowerBound]) }
                out.append(.titulo(nivel: linha.prefix { $0 == "#" }.count, texto: t))
                branco = false
                continue
            }
            if linha.range(of: #"^(-{3,}|\*{3,}|_{3,})$"#, options: .regularExpression) != nil {
                fecha(); out.append(.fio); branco = false
                continue
            }
            if linha.hasPrefix(">") {
                fecha()
                var t = linha.dropFirst()
                if t.first == " " { t = t.dropFirst() }
                if !branco, case .citacao(let antes)? = out.last { out[out.count - 1] = .citacao(antes + "\n" + t) }
                else { out.append(.citacao(String(t))) }
                branco = false
                continue
            }

            let nivel = min(recuo(bruta) / 2, 6)
            if let r = linha.range(of: #"^[-*+•] +"#, options: .regularExpression) {
                fecha()
                var t = String(linha[r.upperBound...])
                var marca = BlocoResposta.Marca.ponto
                if let caixa = t.range(of: #"^\[[ xX]\] +"#, options: .regularExpression) {
                    marca = t.hasPrefix("[ ]") ? .aFazer : .feito
                    t = String(t[caixa.upperBound...])
                }
                out.append(.item(marca: marca, texto: t, recuo: nivel))
                branco = false
                continue
            }
            if let r = linha.range(of: #"^\d{1,4}[.)] +"#, options: .regularExpression) {
                fecha()
                out.append(.item(marca: .numero(String(linha[..<r.upperBound]).trimmingCharacters(in: .whitespaces)),
                                 texto: String(linha[r.upperBound...]), recuo: nivel))
                branco = false
                continue
            }
            // Linha recuada logo depois de um item: é a continuação dele, não parágrafo novo.
            if !branco, paragrafo.isEmpty, recuo(bruta) >= 2, case .item(let marca, let t, let n)? = out.last {
                out[out.count - 1] = .item(marca: marca, texto: t + "\n" + linha, recuo: n)
                continue
            }
            paragrafo.append(linha)
            branco = false
        }
        if let c = codigo { out.append(.codigo(linguagem: c.linguagem, texto: c.linhas.joined(separator: "\n"))) }
        fecha()
        return out
    }

    private static func recuo(_ bruta: String) -> Int {
        var n = 0
        for c in bruta {
            if c == " " { n += 1 } else if c == "\t" { n += 4 } else { break }
        }
        return n
    }

    /// A linha de traços de uma tabela: só "|", ":", "-" e espaço, com pelo menos um traço.
    static func ehSeparador(_ linha: String) -> Bool {
        let l = linha.trimmingCharacters(in: .whitespaces)
        return l.contains("-") && l.allSatisfy { "|:- ".contains($0) }
    }

    static func celulas(_ linha: String) -> [String] {
        var l = Substring(linha.trimmingCharacters(in: .whitespaces))
        if l.hasPrefix("|") { l = l.dropFirst() }
        if l.hasSuffix("|") && !l.hasSuffix("\\|") { l = l.dropLast() }
        // "\|" é barra de verdade dentro da célula; barra dentro de `código` também não separa.
        var out: [String] = []
        var atual = ""
        var emCodigo = false
        var anterior: Character = " "
        for c in l {
            if c == "`" { emCodigo.toggle() }
            if c == "|" && anterior == "\\" { atual.removeLast(); atual.append("|") }
            else if c == "|" && !emCodigo { out.append(atual); atual = "" }
            else { atual.append(c) }
            anterior = c
        }
        out.append(atual)
        return out.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    static func tabela(_ linhas: [String]) -> TabelaResposta? {
        guard let primeira = linhas.first else { return nil }
        var cabecalho = celulas(primeira)
        var alinhamento: [TabelaResposta.Alinhamento?] = []
        var corpo: [[String]] = []
        for (n, l) in linhas.dropFirst().enumerated() {
            if ehSeparador(l) {
                // Só a primeira linha de traços (logo depois do cabeçalho) diz o alinhamento.
                if n == 0 {
                    alinhamento = celulas(l).map { c in
                        let esquerda = c.hasPrefix(":"), direita = c.hasSuffix(":")
                        return esquerda && direita ? .centro : direita ? .direita : esquerda ? .esquerda : nil
                    }
                }
                continue
            }
            corpo.append(celulas(l))
        }
        let colunas = max(cabecalho.count, corpo.map(\.count).max() ?? 0)
        guard colunas > 0 else { return nil }
        func completa(_ l: [String]) -> [String] { l + Array(repeating: "", count: colunas - l.count) }
        cabecalho = completa(cabecalho)
        return TabelaResposta(cabecalho: cabecalho, linhas: corpo.map(completa),
                              alinhamento: (0..<colunas).map { $0 < alinhamento.count ? alinhamento[$0] : nil })
    }
}
