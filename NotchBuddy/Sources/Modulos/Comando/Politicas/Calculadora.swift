import Foundation

// A calculadora do comando universal: regra pura, sem UI nem rede.
//   contas        12*3 · (4+5)/2 · 2^10 · 3 x 4 · raiz(144) · 1.234,56 + 10
//   porcentagem   10% de 200 · 200 + 10% · 200 - 15%
//   unidades      10 km em milhas · 72 f em c · 500 mb em gb · 2 h em min
// Devolve nil quando o texto não é conta (um número sozinho também não é): assim "safari" ou
// "2024" não viram resultado de calculadora. Moeda fica de fora de propósito: pede rede.

enum Calculadora {
    struct Resultado: Equatable {
        /// O valor da conta (para conversão, já na unidade pedida).
        let valor: Double
        /// Como aparece em destaque: "1.234,5" ou "6,214 mi".
        let texto: String
        /// O que foi entendido: "12 × 3" ou "10 km em mi".
        let detalhe: String
        /// O que vai para a área de transferência: sem separador de milhar, com vírgula decimal.
        let copia: String
    }

    static func calcular(_ entrada: String) -> Resultado? {
        var t = entrada.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t.count <= 200 else { return nil }
        // "quanto é 2+2?", "= 2+2", "2+2 ="
        let baixo = t.lowercased()
        for prefixo in ["quanto é ", "quanto e ", "quanto da ", "quanto dá ", "calcula ", "calcular ", "calc "]
        where baixo.hasPrefix(prefixo) {
            t = String(t.dropFirst(prefixo.count))
            break
        }
        t = t.trimmingCharacters(in: CharacterSet(charactersIn: "=? ").union(.whitespaces))
        guard !t.isEmpty, t.contains(where: \.isNumber) || t.lowercased().contains("pi") || t.contains("π") else { return nil }

        if let u = converter(t) { return u }
        var leitor = Leitor(t)
        guard let v = leitor.expressao(), leitor.acabou, leitor.operacoes > 0, v.valor.isFinite else { return nil }
        let texto = formatar(v.valor)
        return Resultado(valor: v.valor, texto: texto, detalhe: bonito(t), copia: formatar(v.valor, milhar: false))
    }

    // MARK: Números

    /// Formato brasileiro, fixo (não depende do idioma do Mac): 1.234,56. Até 8 casas, sem zeros
    /// sobrando; muito grande ou muito pequeno vai em notação científica. `algarismos`: quantos
    /// algarismos significativos mostrar (conversão de unidade usa menos: 6,21371 mi).
    static func formatar(_ v: Double, milhar: Bool = true, algarismos: Int = 10) -> String {
        guard v.isFinite else { return "—" }
        if v == 0 { return "0" }
        let modulo = abs(v)
        if modulo >= 1e15 || modulo < 1e-7 {
            let s = String(format: "%.6g", v)
            return s.replacingOccurrences(of: ".", with: ",")
        }
        // 10 algarismos significativos bastam e escondem o ruído do ponto flutuante (0,1 + 0,2).
        let inteiros = max(1, Int(floor(log10(modulo))) + 1)
        let casas = max(0, min(8, algarismos - inteiros))
        var s = String(format: "%.\(casas)f", v)
        if s.contains(".") {
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
        }
        if s == "-0" { s = "0" }
        let negativo = s.hasPrefix("-")
        if negativo { s.removeFirst() }
        let partes = s.split(separator: ".", omittingEmptySubsequences: false)
        var inteiro = String(partes[0])
        if milhar, inteiro.count > 3 {
            var agrupado = ""
            for (i, c) in inteiro.reversed().enumerated() {
                if i > 0, i % 3 == 0 { agrupado.append(".") }
                agrupado.append(c)
            }
            inteiro = String(agrupado.reversed())
        }
        let fim = partes.count > 1 ? "," + partes[1] : ""
        return (negativo ? "-" : "") + inteiro + fim
    }

    /// "1.234,56" → 1234.56 · "3,5" → 3.5 · "3.5" → 3.5 · "1.234.567" → 1234567.
    /// Com vírgula, ponto é milhar. Só pontos: mais de um = milhar; um só = decimal.
    static func numero(_ s: String) -> Double? {
        guard !s.isEmpty else { return nil }
        var t = s
        if t.contains(",") {
            guard t.filter({ $0 == "," }).count == 1 else { return nil }
            t = t.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        } else if t.filter({ $0 == "." }).count > 1 {
            let grupos = t.split(separator: ".", omittingEmptySubsequences: false)
            guard grupos.dropFirst().allSatisfy({ $0.count == 3 }), !grupos[0].isEmpty, grupos[0].count <= 3 else { return nil }
            t = t.replacingOccurrences(of: ".", with: "")
        }
        return Double(t)
    }

    /// A conta como o Hugo digitou, com os sinais de quem escreve à mão.
    private static func bonito(_ t: String) -> String {
        var s = t.replacingOccurrences(of: "**", with: "^").replacingOccurrences(of: "*", with: " × ")
            .replacingOccurrences(of: "/", with: " ÷ ")
        while s.contains("  ") { s = s.replacingOccurrences(of: "  ", with: " ") }
        return s.trimmingCharacters(in: .whitespaces)
    }

    // MARK: Expressões

    private struct Valor {
        var valor: Double
        /// Veio de "10%": somado ou subtraído de outro número, vale "10 % dele".
        var porcento = false
    }

    private struct Leitor {
        private let c: [Character]
        private var i = 0
        /// Quantas operações de verdade a expressão teve (um número sozinho = 0).
        private(set) var operacoes = 0

        init(_ texto: String) { c = Array(texto.lowercased()) }

        var acabou: Bool { mutating get { espacos(); return i >= c.count } }

        private mutating func espacos() { while i < c.count, c[i].isWhitespace { i += 1 } }
        private mutating func olhar() -> Character? { espacos(); return i < c.count ? c[i] : nil }

        private mutating func come(_ s: String) -> Bool {
            espacos()
            let alvo = Array(s)
            guard i + alvo.count <= c.count, Array(c[i..<i + alvo.count]) == alvo else { return false }
            i += alvo.count
            return true
        }

        /// Come uma palavra inteira ("de", "x"): o que vem depois não pode ser letra.
        private mutating func comePalavra(_ s: String) -> Bool {
            let antes = i
            guard come(s) else { return false }
            if i < c.count, c[i].isLetter { i = antes; return false }
            return true
        }

        mutating func expressao() -> Valor? {
            guard var a = termo() else { return nil }
            while let op = olhar(), op == "+" || op == "-" || op == "−" {
                i += 1
                guard let b = termo() else { return nil }
                operacoes += 1
                let sinal: Double = op == "+" ? 1 : -1
                if b.porcento, !a.porcento {
                    a = Valor(valor: a.valor * (1 + sinal * b.valor))
                } else {
                    a = Valor(valor: a.valor + sinal * b.valor)
                }
            }
            return a
        }

        private mutating func termo() -> Valor? {
            guard var a = potencia() else { return nil }
            while true {
                espacos()
                if come("**") { i -= 2; break }   // potência é com quem chamou
                if come("*") || come("×") || come("·") || comePalavra("x") || comePalavra("vezes") {
                    guard let b = potencia() else { return nil }
                    operacoes += 1
                    a = Valor(valor: a.valor * b.valor)
                } else if come("/") || come("÷") || come(":") || comePalavra("dividido por") {
                    guard let b = potencia(), b.valor != 0 else { return nil }
                    operacoes += 1
                    a = Valor(valor: a.valor / b.valor)
                } else if a.porcento, comePalavra("de") || comePalavra("of") {
                    guard let b = potencia() else { return nil }
                    operacoes += 1
                    a = Valor(valor: a.valor * b.valor)
                } else if let p = olhar(), p == "(" {
                    // 2(3+4)
                    guard let b = potencia() else { return nil }
                    operacoes += 1
                    a = Valor(valor: a.valor * b.valor)
                } else {
                    break
                }
            }
            return a
        }

        private mutating func potencia() -> Valor? {
            guard let base = unario() else { return nil }
            if come("^") || come("**") {
                guard let e = potencia() else { return nil }
                operacoes += 1
                return Valor(valor: pow(base.valor, e.valor))
            }
            return base
        }

        private mutating func unario() -> Valor? {
            if come("-") || come("−") {
                guard let v = unario() else { return nil }
                return Valor(valor: -v.valor, porcento: v.porcento)
            }
            if come("+") { return unario() }
            guard var v = primario() else { return nil }
            if come("%") {
                v = Valor(valor: v.valor / 100, porcento: true)
            } else if come("!") {
                guard v.valor >= 0, v.valor <= 170, v.valor == v.valor.rounded() else { return nil }
                operacoes += 1
                v = Valor(valor: (1...max(1, Int(v.valor))).reduce(1.0) { $0 * Double($1) })
            }
            return v
        }

        private mutating func primario() -> Valor? {
            guard let p = olhar() else { return nil }
            if p == "(" {
                i += 1
                guard let v = expressao(), come(")") else { return nil }
                return Valor(valor: v.valor)
            }
            if p.isNumber || p == "," || p == "." {
                let inicio = i
                while i < c.count, c[i].isNumber || c[i] == "." || c[i] == "," { i += 1 }
                // "1e6"
                if i < c.count, c[i] == "e", i + 1 < c.count, c[i + 1].isNumber || ((c[i + 1] == "-" || c[i + 1] == "+") && i + 2 < c.count && c[i + 2].isNumber) {
                    let mantissa = String(c[inicio..<i])
                    i += 1
                    let inicioExp = i
                    if c[i] == "-" || c[i] == "+" { i += 1 }
                    while i < c.count, c[i].isNumber { i += 1 }
                    guard let m = Calculadora.numero(mantissa), let e = Double(String(c[inicioExp..<i])) else { return nil }
                    operacoes += 1
                    return Valor(valor: m * pow(10, e))
                }
                guard let n = Calculadora.numero(String(c[inicio..<i])) else { return nil }
                return Valor(valor: n)
            }
            if p == "π" { i += 1; operacoes += 1; return Valor(valor: .pi) }
            if p == "√" {
                i += 1
                guard let v = unario(), v.valor >= 0 else { return nil }
                operacoes += 1
                return Valor(valor: v.valor.squareRoot())
            }
            // Palavra: constante ou função.
            let inicio = i
            while i < c.count, c[i].isLetter { i += 1 }
            let nome = String(c[inicio..<i])
            switch nome {
            case "pi": operacoes += 1; return Valor(valor: .pi)
            case "e": operacoes += 1; return Valor(valor: M_E)
            default: break
            }
            guard let f = Self.funcoes[nome], come("(") else { return nil }
            guard let v = expressao(), come(")"), let r = f(v.valor), r.isFinite else { return nil }
            operacoes += 1
            return Valor(valor: r)
        }

        private static let funcoes: [String: @Sendable (Double) -> Double?] = [
            "raiz": { $0 >= 0 ? $0.squareRoot() : nil }, "sqrt": { $0 >= 0 ? $0.squareRoot() : nil },
            "abs": { abs($0) },
            "sen": { sin($0) }, "sin": { sin($0) }, "cos": { cos($0) }, "tan": { tan($0) }, "tg": { tan($0) },
            "ln": { $0 > 0 ? log($0) : nil }, "log": { $0 > 0 ? log10($0) : nil },
            "arred": { $0.rounded() }, "round": { $0.rounded() },
            "piso": { $0.rounded(.down) }, "floor": { $0.rounded(.down) },
            "teto": { $0.rounded(.up) }, "ceil": { $0.rounded(.up) },
        ]
    }

    // MARK: Unidades

    private enum Grandeza { case comprimento, massa, temperatura, volume, area, velocidade, tempo, dados }

    private struct Unidade {
        let simbolo: String
        let grandeza: Grandeza
        /// Quanto vale uma unidade destas na unidade de base da grandeza.
        let fator: Double
        let nomes: [String]
    }

    private static let unidades: [Unidade] = [
        // comprimento (base: metro)
        Unidade(simbolo: "mm", grandeza: .comprimento, fator: 0.001, nomes: ["mm", "milimetro", "milimetros"]),
        Unidade(simbolo: "cm", grandeza: .comprimento, fator: 0.01, nomes: ["cm", "centimetro", "centimetros"]),
        Unidade(simbolo: "m", grandeza: .comprimento, fator: 1, nomes: ["m", "metro", "metros"]),
        Unidade(simbolo: "km", grandeza: .comprimento, fator: 1000, nomes: ["km", "quilometro", "quilometros", "kilometro", "kilometros"]),
        Unidade(simbolo: "pol", grandeza: .comprimento, fator: 0.0254, nomes: ["pol", "in", "polegada", "polegadas", "inch", "inches", "\""]),
        Unidade(simbolo: "pés", grandeza: .comprimento, fator: 0.3048, nomes: ["ft", "pe", "pes", "foot", "feet"]),
        Unidade(simbolo: "jardas", grandeza: .comprimento, fator: 0.9144, nomes: ["yd", "jarda", "jardas", "yard", "yards"]),
        Unidade(simbolo: "mi", grandeza: .comprimento, fator: 1609.344, nomes: ["mi", "milha", "milhas", "mile", "miles"]),
        // massa (base: quilo)
        Unidade(simbolo: "mg", grandeza: .massa, fator: 1e-6, nomes: ["mg", "miligrama", "miligramas"]),
        Unidade(simbolo: "g", grandeza: .massa, fator: 0.001, nomes: ["g", "grama", "gramas"]),
        Unidade(simbolo: "kg", grandeza: .massa, fator: 1, nomes: ["kg", "quilo", "quilos", "kilo", "kilos", "quilograma", "quilogramas"]),
        Unidade(simbolo: "t", grandeza: .massa, fator: 1000, nomes: ["t", "tonelada", "toneladas"]),
        Unidade(simbolo: "oz", grandeza: .massa, fator: 0.028349523125, nomes: ["oz", "onca", "oncas", "ounce", "ounces"]),
        Unidade(simbolo: "lb", grandeza: .massa, fator: 0.45359237, nomes: ["lb", "lbs", "libra", "libras", "pound", "pounds"]),
        // temperatura (tratada à parte)
        Unidade(simbolo: "°C", grandeza: .temperatura, fator: 1, nomes: ["c", "°c", "celsius", "graus celsius", "graus"]),
        Unidade(simbolo: "°F", grandeza: .temperatura, fator: 1, nomes: ["f", "°f", "fahrenheit", "graus fahrenheit"]),
        Unidade(simbolo: "K", grandeza: .temperatura, fator: 1, nomes: ["k", "kelvin"]),
        // volume (base: litro)
        Unidade(simbolo: "ml", grandeza: .volume, fator: 0.001, nomes: ["ml", "mililitro", "mililitros"]),
        Unidade(simbolo: "l", grandeza: .volume, fator: 1, nomes: ["l", "litro", "litros"]),
        Unidade(simbolo: "m³", grandeza: .volume, fator: 1000, nomes: ["m3", "m³", "metro cubico", "metros cubicos"]),
        Unidade(simbolo: "gal", grandeza: .volume, fator: 3.785411784, nomes: ["gal", "galao", "galoes", "gallon", "gallons"]),
        Unidade(simbolo: "xícaras", grandeza: .volume, fator: 0.24, nomes: ["xicara", "xicaras", "cup", "cups"]),
        Unidade(simbolo: "fl oz", grandeza: .volume, fator: 0.0295735295625, nomes: ["fl oz", "floz"]),
        // área (base: metro quadrado)
        Unidade(simbolo: "cm²", grandeza: .area, fator: 0.0001, nomes: ["cm2", "cm²"]),
        Unidade(simbolo: "m²", grandeza: .area, fator: 1, nomes: ["m2", "m²", "metro quadrado", "metros quadrados"]),
        Unidade(simbolo: "km²", grandeza: .area, fator: 1e6, nomes: ["km2", "km²"]),
        Unidade(simbolo: "ha", grandeza: .area, fator: 10000, nomes: ["ha", "hectare", "hectares"]),
        Unidade(simbolo: "alqueires paulistas", grandeza: .area, fator: 24200, nomes: ["alqueire", "alqueires"]),
        Unidade(simbolo: "acres", grandeza: .area, fator: 4046.8564224, nomes: ["acre", "acres"]),
        Unidade(simbolo: "ft²", grandeza: .area, fator: 0.09290304, nomes: ["ft2", "ft²", "pes quadrados"]),
        // velocidade (base: m/s)
        Unidade(simbolo: "m/s", grandeza: .velocidade, fator: 1, nomes: ["m/s"]),
        Unidade(simbolo: "km/h", grandeza: .velocidade, fator: 1 / 3.6, nomes: ["km/h", "kmh", "kph"]),
        Unidade(simbolo: "mph", grandeza: .velocidade, fator: 0.44704, nomes: ["mph", "milhas por hora"]),
        Unidade(simbolo: "nós", grandeza: .velocidade, fator: 0.514444444444, nomes: ["no", "nos", "knot", "knots"]),
        // tempo (base: segundo)
        Unidade(simbolo: "ms", grandeza: .tempo, fator: 0.001, nomes: ["ms", "milissegundo", "milissegundos"]),
        Unidade(simbolo: "s", grandeza: .tempo, fator: 1, nomes: ["s", "seg", "segundo", "segundos"]),
        Unidade(simbolo: "min", grandeza: .tempo, fator: 60, nomes: ["min", "minuto", "minutos"]),
        Unidade(simbolo: "h", grandeza: .tempo, fator: 3600, nomes: ["h", "hora", "horas"]),
        Unidade(simbolo: "dias", grandeza: .tempo, fator: 86400, nomes: ["d", "dia", "dias"]),
        Unidade(simbolo: "semanas", grandeza: .tempo, fator: 604800, nomes: ["semana", "semanas"]),
        Unidade(simbolo: "anos", grandeza: .tempo, fator: 31_557_600, nomes: ["ano", "anos"]),
        // dados (base: byte; decimais como o Finder, e os binários com "i")
        Unidade(simbolo: "B", grandeza: .dados, fator: 1, nomes: ["b", "byte", "bytes"]),
        Unidade(simbolo: "KB", grandeza: .dados, fator: 1e3, nomes: ["kb"]),
        Unidade(simbolo: "MB", grandeza: .dados, fator: 1e6, nomes: ["mb", "mega", "megas"]),
        Unidade(simbolo: "GB", grandeza: .dados, fator: 1e9, nomes: ["gb", "giga", "gigas"]),
        Unidade(simbolo: "TB", grandeza: .dados, fator: 1e12, nomes: ["tb", "tera", "teras"]),
        Unidade(simbolo: "KiB", grandeza: .dados, fator: 1024, nomes: ["kib"]),
        Unidade(simbolo: "MiB", grandeza: .dados, fator: 1_048_576, nomes: ["mib"]),
        Unidade(simbolo: "GiB", grandeza: .dados, fator: 1_073_741_824, nomes: ["gib"]),
    ]

    private static func semAcento(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR")).lowercased()
    }

    private static func unidade(_ nome: String) -> Unidade? {
        let n = semAcento(nome.trimmingCharacters(in: .whitespaces))
        return unidades.first { $0.nomes.contains(n) || semAcento($0.simbolo) == n }
    }

    /// "10 km em milhas": número (ou conta) + unidade, a palavra de ligação e a unidade pedida.
    private static func converter(_ t: String) -> Resultado? {
        let baixo = t.lowercased()
        for ligacao in [" em ", " para ", " pra ", " to ", " in ", " -> ", " → ", "->"] {
            guard let corte = baixo.range(of: ligacao, options: .backwards) else { continue }
            let esquerda = String(baixo[..<corte.lowerBound]).trimmingCharacters(in: .whitespaces)
            let direita = String(baixo[corte.upperBound...])
            guard let destino = unidade(direita) else { continue }
            // A unidade de origem é o fim da parte esquerda; o que sobra antes é a conta.
            let dobrada = semAcento(esquerda)
            let candidatas = unidades.filter { $0.grandeza == destino.grandeza }
                .flatMap { u in (u.nomes + [semAcento(u.simbolo)]).map { (nome: $0, unidade: u) } }
                .sorted { $0.nome.count > $1.nome.count }
            for cand in candidatas where dobrada.hasSuffix(cand.nome) {
                let resto = String(dobrada.dropLast(cand.nome.count))
                // "10km" e "10 km" valem; "10 okm" não (a unidade não pode ser fim de outra palavra).
                guard let ultimo = resto.last, !ultimo.isLetter else { continue }
                var leitor = Leitor(resto)
                guard let v = leitor.expressao(), leitor.acabou, v.valor.isFinite else { continue }
                let convertido: Double
                if destino.grandeza == .temperatura {
                    convertido = deKelvin(emKelvin(v.valor, cand.unidade.simbolo), destino.simbolo)
                } else {
                    convertido = v.valor * cand.unidade.fator / destino.fator
                }
                guard convertido.isFinite else { return nil }
                let numero = formatar(convertido, algarismos: 6)
                return Resultado(valor: convertido, texto: "\(numero) \(destino.simbolo)",
                                 detalhe: "\(formatar(v.valor)) \(cand.unidade.simbolo) em \(destino.simbolo)",
                                 copia: formatar(convertido, milhar: false, algarismos: 6))
            }
        }
        return nil
    }

    private static func emKelvin(_ v: Double, _ simbolo: String) -> Double {
        switch simbolo {
        case "°C": v + 273.15
        case "°F": (v - 32) * 5 / 9 + 273.15
        default: v
        }
    }

    private static func deKelvin(_ k: Double, _ simbolo: String) -> Double {
        switch simbolo {
        case "°C": k - 273.15
        case "°F": (k - 273.15) * 9 / 5 + 32
        default: k
        }
    }
}
