import Foundation

// Lapidar o ditado: o que o Hugo falou vira o que ele escreveria — sem perder nem inventar palavra.
//
// A regra que sustenta tudo: **as palavras do texto final são sempre as da fala**. O modelo local
// do Mac só empresta pontuação, maiúsculas e quebras de linha; o resultado dele é alinhado palavra
// a palavra com a fala e o que ele trocou, acrescentou ou respondeu é jogado fora. Palavra só some
// por regra escrita aqui (muleta, palavra repetida, correção no meio da fala, "primeiro/segundo"
// de lista). Sem modelo, com erro ou com resposta que não bate com a fala, sai o texto com o que o
// código faz sozinho (dicionário, muletas, correções com número/horário, maiúscula inicial).
//
// Não depende de nada do app: a bateria de falas roda este arquivo num script de linha de comando.
// Quem chama o modelo é `IAdoMac.pontuarDitado`. Medição de 2026-11-13 em `docs/ARQUITETURA.md`.

struct PalavraDitada: Sendable, Equatable {
    var quebras = 0          // linhas novas antes da palavra (0, 1 ou 2)
    var item = false         // a palavra começa um item de lista
    var abre = ""            // pontuação que abre (aspas, parêntese)
    var palavra: String
    var fecha = ""           // pontuação que fecha (vírgula, ponto, interrogação)
    var fixa = false         // veio do dicionário: grafia não muda
    var chave: String        // minúscula, sem acento e sem símbolo: é o que se compara
    var sobra = false        // o modelo tirou esta palavra e ela foi reposta
    var ordinal = false      // item de lista numerada ("primeiro, segundo…")

    init(_ palavra: String, abre: String = "", fecha: String = "", quebras: Int = 0, item: Bool = false, fixa: Bool = false) {
        self.palavra = palavra
        self.abre = abre
        self.fecha = fecha
        self.quebras = quebras
        self.item = item
        self.fixa = fixa
        self.chave = LapidarDitado.dobrar(palavra)
    }
}

enum LapidarDitado {

    struct Resultado: Sendable {
        var texto: String
        /// O modelo foi usado e a resposta dele passou nas travas.
        var comModelo: Bool
        /// Por que o modelo ficou de fora (nil quando entrou).
        var motivo: String?
    }

    /// Acima disto (uns dois minutos de fala) o modelo demora demais depois de soltar a tecla:
    /// a fala segue só com o que o código faz. Medido: 160 palavras levam cerca de 5 s.
    static let limitePalavrasModelo = 220

    /// `modelo` recebe a fala já preparada e devolve a mesma fala pontuada (nil = não deu).
    static func lapidar(_ fala: String, formatar: Bool, dicionario: String,
                        modelo: (@Sendable (String, Bool) async -> String?)?) async -> Resultado {
        let base = preparar(fala, dicionario: dicionario)
        guard !base.isEmpty else { return Resultado(texto: fala, comModelo: false, motivo: "fala vazia") }
        guard let modelo else {
            return Resultado(texto: montar(acabar(base, formatar: false, pontoFinal: false)), comModelo: false, motivo: "sem modelo")
        }
        guard base.count <= limitePalavrasModelo else {
            return Resultado(texto: montar(acabar(base, formatar: false, pontoFinal: false)), comModelo: false, motivo: "fala longa (\(base.count) palavras)")
        }
        guard let resposta = await modelo(montar(base), formatar) else {
            return Resultado(texto: montar(acabar(base, formatar: false, pontoFinal: false)), comModelo: false, motivo: "modelo não respondeu")
        }
        guard let fundido = fundir(base: base, modelo: separar(resposta)) else {
            return Resultado(texto: montar(acabar(base, formatar: false, pontoFinal: false)), comModelo: false, motivo: "resposta não bate com a fala")
        }
        return Resultado(texto: montar(acabar(fundido, formatar: formatar, pontoFinal: true)), comModelo: true, motivo: nil)
    }

    /// Tudo o que não precisa de modelo: dicionário, muletas, repetições e correções seguras.
    static func preparar(_ fala: String, dicionario: String) -> [PalavraDitada] {
        var p = separar(fala.replacingOccurrences(of: "\n", with: " "))
        p = aplicarDicionario(p, lerDicionario(dicionario))
        p = tirarMuletas(p)
        p = aplicarCorrecoes(p)
        return p
    }

    // MARK: - Palavras

    static func dobrar(_ s: String) -> String {
        let f = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR")).lowercased()
        let a = String(String.UnicodeScalarView(f.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }))
        return a.isEmpty ? f : a
    }

    private static let abrem = Set("(\"'“‘«[¿¡*_")
    private static let fecham = Set(".,;:!?…)\"'”’»]*_")
    private static let fortes = Set(".?!…")

    private static func ehMarcaDeItem(_ s: String) -> Bool {
        if ["-", "–", "—", "•", "*", "·"].contains(s) { return true }
        guard let fim = s.last, fim == "." || fim == ")" else { return false }
        let n = s.dropLast()
        return !n.isEmpty && n.count <= 2 && n.allSatisfy(\.isNumber)
    }

    /// Texto → palavras, guardando a pontuação em volta, as quebras de linha e as marcas de lista.
    static func separar(_ texto: String) -> [PalavraDitada] {
        var saida: [PalavraDitada] = []
        var quebras = 0
        var item = false
        for (n, linha) in texto.components(separatedBy: "\n").enumerated() {
            if n > 0 { quebras += 1 }
            var inicio = true
            for pedaco in linha.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\r" || $0 == "\u{a0}" }) {
                let p = String(pedaco)
                if inicio, ehMarcaDeItem(p) { item = true; inicio = false; continue }
                inicio = false
                var c = Array(p)
                var abre = ""
                while let primeiro = c.first, abrem.contains(primeiro) { abre.append(primeiro); c.removeFirst() }
                var fecha = ""
                while let ultimo = c.last, fecham.contains(ultimo) { fecha.insert(ultimo, at: fecha.startIndex); c.removeLast() }
                let miolo = String(c)
                if miolo.isEmpty || ["-", "–", "—"].contains(miolo) {
                    // pontuação solta: cola na palavra anterior
                    if quebras == 0, let u = saida.indices.last, !fecha.isEmpty || !abre.isEmpty {
                        saida[u].fecha += abre.filter { fecham.contains($0) } + fecha
                    }
                    continue
                }
                saida.append(PalavraDitada(miolo, abre: abre.filter { $0 != "*" && $0 != "_" },
                                           fecha: fecha.filter { $0 != "*" && $0 != "_" },
                                           quebras: saida.isEmpty ? 0 : min(quebras, 2), item: item))
                quebras = 0
                item = false
            }
        }
        return saida
    }

    /// Palavras → texto. Lista numerada quando a fala trazia "primeiro, segundo…".
    static func montar(_ p: [PalavraDitada]) -> String {
        var s = ""
        var numero = 0
        for (i, t) in p.enumerated() {
            if i > 0 { s += t.quebras > 0 ? String(repeating: "\n", count: t.quebras) : " " }
            if t.item {
                numero += 1
                s += t.ordinal ? "\(numero). " : "- "
            } else if t.quebras > 0 {
                numero = 0
            }
            s += t.abre + t.palavra + t.fecha
        }
        return s
    }

    // MARK: - Dicionário (como eu falo → como se escreve)

    struct Dicionario: Sendable {
        /// chaves das palavras faladas, separadas por espaço → palavras escritas
        var porPalavras: [String: [String]] = [:]
        /// a forma falada sem espaço nenhum → palavras escritas ("cloudcode" → Claude Code)
        var juntas: [String: [String]] = [:]
        var maiorTermo = 1
        var vazio: Bool { porPalavras.isEmpty }
    }

    /// Uma entrada por linha (ou separadas por ";"): `cru, crú → Crew` (aceita →, ->, => e =).
    /// Entrada sem seta é só a grafia ("Itapeva, GitHub"): vale para quando a palavra veio certa
    /// mas sem maiúscula.
    static func lerDicionario(_ bruto: String) -> Dicionario {
        var d = Dicionario()
        func registrar(_ falado: String, _ escrito: String) {
            let palavras = falado.split(whereSeparator: { $0 == " " || $0 == "-" }).map { dobrar(String($0)) }.filter { !$0.isEmpty }
            let escritas = escrito.split(separator: " ").map(String.init)
            guard !palavras.isEmpty, !escritas.isEmpty else { return }
            d.porPalavras[palavras.joined(separator: " ")] = escritas
            d.juntas[palavras.joined()] = escritas
            d.maiorTermo = max(d.maiorTermo, palavras.count)
        }
        for linha in bruto.split(whereSeparator: { $0.isNewline || $0 == ";" }) {
            let l = String(linha)
            if let seta = ["→", "=>", "->", "="].compactMap({ l.range(of: $0) }).min(by: { $0.lowerBound < $1.lowerBound }) {
                let escrito = l[seta.upperBound...].trimmingCharacters(in: .whitespaces)
                guard !escrito.isEmpty else { continue }
                for falado in l[..<seta.lowerBound].split(separator: ",") {
                    registrar(falado.trimmingCharacters(in: .whitespaces), escrito)
                }
                registrar(escrito, escrito)
            } else {
                for termo in l.split(separator: ",") {
                    let t = termo.trimmingCharacters(in: .whitespaces)
                    registrar(t, t)
                }
            }
        }
        return d
    }

    static func aplicarDicionario(_ p: [PalavraDitada], _ d: Dicionario) -> [PalavraDitada] {
        guard !d.vazio else { return p }
        var saida: [PalavraDitada] = []
        var i = 0
        while i < p.count {
            var achou = false
            var n = min(d.maiorTermo, p.count - i)
            while n >= 1 {
                let trecho = p[i..<(i + n)]
                // um termo não atravessa pontuação nem quebra de linha
                let inteiro = trecho.dropLast().allSatisfy { $0.fecha.isEmpty } && trecho.dropFirst().allSatisfy { $0.quebras == 0 && $0.abre.isEmpty }
                let escritas = inteiro ? (d.porPalavras[trecho.map(\.chave).joined(separator: " ")] ?? (n == 1 ? d.juntas[trecho[i].chave] : nil)) : nil
                if let escritas, !(n == 1 && ehAdjetivoAqui(p, i, escritas)) {
                    for (k, e) in escritas.enumerated() {
                        var t = PalavraDitada(e, fixa: true)
                        if k == 0 { t.abre = p[i].abre; t.quebras = p[i].quebras; t.item = p[i].item }
                        if k == escritas.count - 1 { t.fecha = p[i + n - 1].fecha }
                        saida.append(t)
                    }
                    i += n
                    achou = true
                    break
                }
                n -= 1
            }
            if !achou { saida.append(p[i]); i += 1 }
        }
        return saida
    }

    private static let antesDeAdjetivo: Set<String> = ["ta", "tava", "esta", "estava", "estao", "tavam", "e", "era", "sao", "ficou", "fica",
                                                       "ficam", "meio", "muito", "bem", "mais", "tao", "ainda", "quase", "super", "totalmente"]

    /// "cru → Crew" não vale em "o peixe tava cru": nome próprio não vem logo depois de
    /// "tava", "é", "muito"… Aí a palavra é a comum e fica como foi falada.
    private static func ehAdjetivoAqui(_ p: [PalavraDitada], _ i: Int, _ escritas: [String]) -> Bool {
        guard i > 0, escritas.count == 1, let c = escritas[0].first, c.isUppercase,
              p[i].chave != dobrar(escritas[0]), p[i - 1].fecha.isEmpty else { return false }
        return antesDeAdjetivo.contains(p[i - 1].chave)
    }

    // MARK: - Muletas e repetições

    private static let sons: Set<String> = ["hã", "hãã", "hãn", "ãh", "ã", "ãã", "ããã", "ãããã", "ãn", "ãhn", "ahn", "ahm", "ham",
                                            "hum", "humm", "hmm", "hm", "uhm", "éé", "ééé", "éééé", "eh", "ehh", "hãm"]
    private static let antesDeTipo: Set<String> = ["o", "a", "os", "as", "um", "uma", "que", "esse", "essa", "este", "esta", "aquele",
                                                   "aquela", "do", "da", "de", "dos", "das", "no", "na", "qual", "outro", "mesmo", "cada",
                                                   "algum", "nenhum", "todo", "qualquer", "meu", "seu", "nosso", "desse", "deste", "daquele",
                                                   "nesse", "neste", "pro", "pra", "ao", "com", "por", "sem", "quanto"]
    private static let depoisDoEInicial: Set<String> = ["entao", "assim", "bom", "cara", "olha", "tipo", "mano", "seguinte"]
    private static let enfase: Set<String> = ["muito", "bem", "nao", "sim", "ja", "mais", "quase", "tao", "nunca", "super", "pouco",
                                              "vai", "ta", "calma", "pera", "bla", "ha", "rs", "k", "kk", "ui", "ai", "oi", "tchau", "la"]

    static func tirarMuletas(_ entrada: [PalavraDitada]) -> [PalavraDitada] {
        var p = entrada
        func tirar(_ i: Int) {
            let t = p[i]
            // pontuação forte ("né?") passa para a palavra de antes; quebra de linha, para a de depois
            if i > 0, t.fecha.contains(where: { fortes.contains($0) }), !p[i - 1].fecha.contains(where: { fortes.contains($0) }) {
                p[i - 1].fecha = t.fecha
            }
            if i + 1 < p.count, t.quebras > 0 || t.item {
                p[i + 1].quebras = max(p[i + 1].quebras, t.quebras)
                p[i + 1].item = p[i + 1].item || t.item
            }
            p.remove(at: i)
        }
        var i = 0
        while i < p.count {
            let t = p[i]
            guard !t.fixa else { i += 1; continue }
            let minuscula = t.palavra.lowercased()
            if sons.contains(minuscula) || t.chave == "ne" && minuscula != "ne" || minuscula == "né" {
                tirar(i)
                continue
            }
            if t.chave == "tipo" {
                let antes = i > 0 ? p[i - 1].chave : ""
                let depois = i + 1 < p.count ? p[i + 1].chave : ""
                if depois == "assim" {
                    tirar(i + 1); tirar(i)
                    continue
                }
                let antesFechado = i > 0 && !p[i - 1].fecha.isEmpty
                if depois != "de", antesFechado || !antesDeTipo.contains(antes) {
                    tirar(i)
                    continue
                }
            }
            // palavra repetida por engano ("eu eu quero")
            if i + 1 < p.count, p[i + 1].chave == t.chave, t.fecha.isEmpty, !p[i + 1].fixa,
               !enfase.contains(t.chave), !ehNumero(t.chave) {
                tirar(i)
                continue
            }
            i += 1
        }
        // "é então…", "é assim…": o "é" de quem está pensando
        if p.count > 2, p[0].palavra.lowercased() == "é", depoisDoEInicial.contains(p[1].chave) {
            p.remove(at: 0)
        }
        if let primeiro = p.indices.first { p[primeiro].quebras = 0 }
        return p
    }

    // MARK: - Correção no meio da fala

    private static let numeros: Set<String> = [
        "dois", "duas", "tres", "quatro", "cinco", "seis", "sete", "oito", "nove", "dez", "onze", "doze", "treze", "catorze",
        "quatorze", "quinze", "dezesseis", "dezessete", "dezoito", "dezenove", "vinte", "trinta", "quarenta", "cinquenta",
        "sessenta", "setenta", "oitenta", "noventa", "cem", "cento", "duzentos", "trezentos", "quatrocentos", "quinhentos",
        "seiscentos", "setecentos", "oitocentos", "novecentos", "mil", "meia", "meio", "meiodia", "meianoite",
        "segunda", "terca", "quarta", "quinta", "sexta", "sabado", "domingo", "hoje", "amanha", "ontem",
        "janeiro", "fevereiro", "marco", "abril", "maio", "junho", "julho", "agosto", "setembro", "outubro", "novembro", "dezembro",
    ]
    static func ehNumero(_ chave: String) -> Bool { chave.contains(where: \.isNumber) || numeros.contains(chave) }

    /// Marcador de correção começando em `i`: quantas palavras ocupa e se é explícito
    /// ("aliás", "quer dizer", "não, pera") ou só um "não", que também é palavra comum.
    private static func marcador(_ p: [PalavraDitada], _ i: Int) -> (tamanho: Int, explicito: Bool)? {
        let a = p[i].chave
        let b = i + 1 < p.count ? p[i + 1].chave : ""
        switch a {
        case "nao": return ["pera", "perai", "espera", "calma", "minto"].contains(b) ? (2, true) : (1, false)
        case "quer": return b == "dizer" ? (2, true) : nil
        case "ou": return b == "melhor" ? (2, true) : nil
        case "alias", "minto", "perdao", "corrigindo": return (1, true)
        default: return nil
        }
    }

    private static let naoRepete: Set<String> = ["que", "e", "se", "mas", "nao", "ou", "ai", "dai"]

    /// Correções que o código resolve sozinho, sem modelo:
    /// - marcador explícito com a palavra de apoio repetida: "pra produção, quer dizer, pra homologação";
    /// - "não" entre dois números/horários/dias: "pras três, não, pras quatro", "sexta não sábado".
    /// "Não" sem número fica como está: "é pra mim, não é pra você" não é correção.
    static func aplicarCorrecoes(_ entrada: [PalavraDitada]) -> [PalavraDitada] {
        var p = entrada
        // Fala que já veio pontuada: correção com "não" tem vírgula depois ("três, não, quatro");
        // sem a vírgula é contraste ("é às três, não às quatro") e fica.
        let pontuada = p.dropLast().contains { !$0.fecha.isEmpty }
        var i = 1
        while i < p.count {
            guard let m = marcador(p, i), i + m.tamanho < p.count else { i += 1; continue }
            let depois = i + m.tamanho
            if !m.explicito, pontuada, !p[depois - 1].fecha.contains(",") { i += 1; continue }
            var inicio: Int?
            let apoio = p[depois].chave
            if !naoRepete.contains(apoio) || p[depois].palavra.lowercased() == "é", i >= 2 {
                // a palavra de apoio repetida, até 4 palavras antes do marcador, sem ponto no meio
                var j = i - 2
                while j >= max(0, i - 5) {
                    if p[j].chave == apoio, !p[j..<(i - 1)].contains(where: { $0.fecha.contains(where: { fortes.contains($0) }) }) {
                        let trocado = p[(j + 1)..<i]
                        let novo = p[(depois + 1)..<min(p.count, depois + 4)]
                        if m.explicito || (trocado.contains { ehNumero($0.chave) } && novo.contains { ehNumero($0.chave) }) {
                            inicio = j
                        }
                        break
                    }
                    j -= 1
                }
            }
            if inicio == nil, ehNumero(p[i - 1].chave), ehNumero(apoio), p[i - 1].fecha.allSatisfy({ !fortes.contains($0) }) {
                inicio = i - 1
            }
            if let inicio {
                let cabeca = p[inicio]
                p.removeSubrange(inicio..<depois)
                p[inicio].abre = cabeca.abre
                p[inicio].quebras = cabeca.quebras
                p[inicio].item = cabeca.item
                i = inicio + 1
            } else {
                i += 1
            }
        }
        return p
    }

    // MARK: - Juntar a fala com a resposta do modelo

    private static let muletasDoModelo: Set<String> = ["tipo", "assim", "ne", "entao", "bom", "ah", "e"]
    private static let ordinais = ["primeiro", "segundo", "terceiro", "quarto", "quinto", "sexto", "setimo", "oitavo"]
    private static let ligaItem: Set<String> = ["e", "depois", "por", "ultimo", "fim", "primeiro", "primeira", "segundo", "segunda",
                                                "terceiro", "terceira", "quarto", "quinto", "sexto", "setimo", "oitavo", "o", "a"]

    /// Alinha a resposta do modelo com a fala. As palavras são as da fala; do modelo vêm a
    /// pontuação, as maiúsculas e as quebras. nil = a resposta não é a mesma fala (o modelo
    /// respondeu, resumiu ou reescreveu): não serve.
    static func fundir(base: [PalavraDitada], modelo: [PalavraDitada]) -> [PalavraDitada]? {
        let n = base.count, m = modelo.count
        guard n > 0, m > 0 else { return nil }
        // maior subsequência comum, por chave
        var t = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                t[i][j] = base[i].chave == modelo[j].chave ? t[i + 1][j + 1] + 1 : max(t[i + 1][j], t[i][j + 1])
            }
        }
        // Resposta bem maior que a fala é conversa, não transcrição.
        guard m <= n + max(3, n / 3) else { return nil }
        // O modelo às vezes devolve tudo em maiúsculas: aí a caixa dele não vale.
        let gritando = modelo.filter { $0.palavra.count > 1 && $0.palavra == $0.palavra.uppercased() && $0.palavra != $0.palavra.lowercased() }.count * 2 > m

        var saida: [PalavraDitada] = []
        var sobrasBase: [PalavraDitada] = []
        var sobrasModelo: [PalavraDitada] = []
        var trocadas = 0
        func fecharSobras() {
            defer { sobrasBase = []; sobrasModelo = [] }
            guard !sobrasBase.isEmpty else { return }   // o modelo acrescentou palavras: fora
            if sobrasModelo.isEmpty {
                // o modelo tirou palavras da fala: só vale se for muleta, repetição ou correção explícita
                if podeSumir(sobrasBase, antes: saida) { return }
                // o mesmo corte, visto uma palavra antes ("pras [três não pras] quatro" = "[pras três não] pras quatro")
                var giro = 1
                while giro < sobrasBase.count, giro <= saida.count {
                    let cauda = sobrasBase.suffix(giro).map(\.chave)
                    if Array(saida.suffix(giro).map(\.chave)) == cauda {
                        let girado = Array(saida.suffix(giro)) + sobrasBase.dropLast(giro)
                        if podeSumir(girado, antes: Array(saida.dropLast(giro))) {
                            let reposto = Array(sobrasBase.suffix(giro))
                            let marcas = Array(saida.suffix(giro))
                            saida.removeLast(giro)
                            for (k, var r) in reposto.enumerated() {
                                r.abre = marcas[k].abre; r.quebras = marcas[k].quebras; r.item = marcas[k].item
                                saida.append(r)
                            }
                            return
                        }
                    }
                    giro += 1
                }
                saida += sobrasBase.map { var s = $0; s.sobra = true; return s }
                return
            }
            // número que o modelo passou para algarismo ("quarenta e duas" → 42): fica por extenso, sem contar como desvio
            let soNumeros = sobrasBase.allSatisfy { ehNumero($0.chave) || $0.chave == "e" } && sobrasModelo.allSatisfy { ehNumero($0.chave) }
            // palavras que o modelo só juntou ("package json" → "package.json"): ficam separadas, como na fala
            let soJuntou = sobrasBase.map(\.chave).joined() == sobrasModelo.map(\.chave).joined()
            if !soNumeros, !soJuntou { trocadas += sobrasBase.count }
            // o modelo trocou palavras: ficam as da fala; dele, só a pontuação em volta
            var manter = sobrasBase
            if manter.count == sobrasModelo.count {
                for k in manter.indices { copiarMarcas(de: sobrasModelo[k], para: &manter[k]) }
            } else {
                manter[0].abre = sobrasModelo[0].abre
                manter[0].quebras = sobrasModelo[0].quebras
                manter[0].item = sobrasModelo[0].item
                manter[manter.count - 1].fecha = sobrasModelo[sobrasModelo.count - 1].fecha
            }
            saida += manter
        }
        var i = 0, j = 0
        while i < n, j < m {
            if base[i].chave == modelo[j].chave, t[i][j] == t[i + 1][j + 1] + 1 {
                fecharSobras()
                var p = base[i]
                copiarMarcas(de: modelo[j], para: &p)
                if !p.fixa, !gritando {
                    let dele = modelo[j].palavra
                    if dele.lowercased() == p.palavra.lowercased(), dele.count <= 4 || dele.dropFirst() == p.palavra.dropFirst() {
                        p.palavra = dele                         // só muda maiúscula/minúscula (sigla curta ou a inicial)
                    } else if let c = dele.first, c.isUppercase {
                        p.palavra = p.palavra.prefix(1).uppercased() + p.palavra.dropFirst()
                    }
                }
                saida.append(p)
                i += 1; j += 1
            } else if t[i + 1][j] >= t[i][j + 1] {
                sobrasBase.append(base[i]); i += 1
            } else {
                sobrasModelo.append(modelo[j]); j += 1
            }
        }
        sobrasBase += base[i...]
        sobrasModelo += modelo[j...]
        fecharSobras()

        // Trava: palavra da fala que o modelo trocou ou tirou sem motivo é desvio. Poucos desvios,
        // a pontuação dele ainda serve (as palavras são sempre as da fala); muitos, ele reescreveu
        // ou respondeu, e a resposta inteira é descartada.
        let desvios = trocadas + saida.filter { $0.sobra && !ligaItem.contains($0.chave) }.count
        guard desvios <= (n <= 3 ? 0 : max(1, n * 15 / 100)) else { return nil }

        // Palavra que o modelo tirou e nós repusemos ("primeiro", "e") logo antes de uma linha
        // nova: a linha passa a começar nela, para a limpeza de itens enxergar.
        var k = saida.count - 1
        while k > 0 {
            if (saida[k].quebras > 0 || saida[k].item), saida[k - 1].sobra, ligaItem.contains(saida[k - 1].chave), saida[k - 1].quebras == 0 {
                saida[k - 1].quebras = saida[k].quebras
                saida[k - 1].item = saida[k].item
                saida[k - 1].fecha = ""
                saida[k].quebras = 0
                saida[k].item = false
            }
            k -= 1
        }
        return saida
    }

    private static func copiarMarcas(de m: PalavraDitada, para p: inout PalavraDitada) {
        p.abre = m.abre
        p.fecha = m.fecha
        p.quebras = m.quebras
        p.item = m.item
    }

    /// Palavras da fala que o modelo deixou de fora podem mesmo sumir?
    private static func podeSumir(_ trecho: [PalavraDitada], antes: [PalavraDitada]) -> Bool {
        guard !trecho.isEmpty, trecho.count <= 6, !trecho.contains(where: \.fixa) else { return false }
        if trecho.allSatisfy({ ["tipo", "assim", "ne"].contains($0.chave) }) { return true }
        // correção com marcador explícito no fim do trecho: "sexta, aliás, [sábado]"
        // Só uma palavra trocada ("vinte caixas ou melhor trinta" perderia "caixas": fica tudo).
        if trecho.count >= 2, let mk = marcador(trecho, 1), mk.explicito, 1 + mk.tamanho == trecho.count { return true }
        return false
    }

    // MARK: - Acabamento

    private static let abrePergunta: Set<String> = ["qual", "quais", "quanto", "quantos", "quanta", "quantas", "cade"]
    private static let abrePerguntaDupla: Set<String> = ["sera que", "por que", "como faz", "como que", "que horas", "como eu", "tem como"]

    /// Só os começos que quase nunca são afirmação ("quando…", "quem…", "onde…" ficam de fora).
    private static func comecaPergunta(_ c: [String]) -> Bool {
        guard let a = c.first else { return false }
        if abrePergunta.contains(a) { return true }
        guard c.count >= 2 else { return false }
        if a == "como", c[1] == "eu" { return c.count >= 3 && ["faco", "posso", "consigo", "vou"].contains(c[2]) }
        return abrePerguntaDupla.contains(a + " " + c[1])
    }

    /// Lista só com dois itens ou mais, sem "primeiro/segundo/e" na frente do item, introdução
    /// com dois-pontos, maiúsculas de começo de frase e ponto final.
    static func acabar(_ entrada: [PalavraDitada], formatar: Bool, pontoFinal: Bool) -> [PalavraDitada] {
        var p = entrada
        guard !p.isEmpty else { return p }
        p[0].quebras = 0
        if !formatar {
            for i in p.indices where p[i].quebras > 0 || p[i].item {
                if i > 0, p[i - 1].fecha.isEmpty { p[i - 1].fecha = p[i].item ? "," : "." }
                p[i].quebras = 0
                p[i].item = false
            }
        } else {
            // blocos de itens em linhas seguidas
            var i = 0
            while i < p.count {
                guard p[i].item else { i += 1; continue }
                var inicios = [i]
                var j = i + 1
                while j < p.count {
                    if p[j].quebras > 0 {
                        if p[j].item, p[j].quebras == 1 { inicios.append(j) } else { break }
                    }
                    j += 1
                }
                var fim = j
                // Não é lista: item sozinho, ou "item" que é um parágrafo (frase inteira com ponto
                // no meio, ou comprido demais). Volta tudo para a frase.
                let corpo = p[i..<fim]
                let comPontoNoMeio = corpo.indices.contains { q in
                    p[q].fecha.contains(where: { fortes.contains($0) }) && q + 1 < fim && p[q + 1].quebras == 0
                }
                guard inicios.count >= 2, !comPontoNoMeio, corpo.count <= inicios.count * 16 else {
                    for q in inicios {
                        if q > 0, q != i, p[q - 1].fecha.isEmpty { p[q - 1].fecha = "." }
                        p[q].item = false
                        p[q].quebras = 0
                    }
                    i = fim
                    continue
                }
                // limpar cada item, do último para o primeiro (assim os índices de antes não mudam)
                var ordinaisTirados = 0
                var semMarca: Set<Int> = []
                var ultimoComE: Int?
                let fechaDoFim = p[fim - 1].fecha
                for n in inicios.indices.reversed() {
                    let a = inicios[n]
                    let b = n + 1 < inicios.count ? inicios[n + 1] : fim
                    if p[a].chave != "e", !ordinais.contains(p[a].chave), p[a].chave != "por" { semMarca.insert(n) }
                    p[b - 1].fecha = p[b - 1].fecha.filter { !",;.".contains($0) }
                    // "e", "primeiro", "e por último" na frente do item
                    var c = a
                    if c < b - 1, p[c].chave == "e" {
                        c += 1
                        if n >= 1, n < inicios.count - 1 { ultimoComE = min(ultimoComE ?? n, n) }
                    }
                    if c < b - 1, n < ordinais.count, p[c].chave == ordinais[n] || p[c].chave == ordinais[n].dropLast() + "a" {
                        c += 1
                        ordinaisTirados += 1
                    } else if c + 2 < b, n == inicios.count - 1, p[c].chave == "por", ["ultimo", "fim"].contains(p[c + 1].chave) {
                        c += 2
                        ordinaisTirados += 1
                    }
                    if c > a {
                        let cabeca = p[a]
                        p.removeSubrange(a..<c)
                        p[a].quebras = cabeca.quebras
                        p[a].item = true
                        fim -= c - a
                    }
                }
                // "primeiro… segundo… terceiro… quando terminar me avisa": o último pedaço, sem
                // ordinal, não é item — é a frase que vem depois da lista.
                // Igual em "farinha, ovo e sal, mistura tudo": o item com "e" na frente fecha a lista.
                let comecos = (i..<fim).filter { p[$0].item }
                var itensDeVerdade = comecos.count
                if inicios.count >= 3, ordinaisTirados == inicios.count - 1, semMarca == [inicios.count - 1] {
                    itensDeVerdade = comecos.count - 1
                } else if ordinaisTirados == 0, let e = ultimoComE {
                    itensDeVerdade = e + 1
                }
                if itensDeVerdade < comecos.count {
                    p[fim - 1].fecha = fechaDoFim
                    for q in comecos[itensDeVerdade...] {
                        p[q].item = false
                        if q != comecos[itensDeVerdade] {
                            p[q].quebras = 0
                            if p[q - 1].fecha.isEmpty { p[q - 1].fecha = "." }
                        }
                    }
                    fim = comecos[itensDeVerdade]
                }
                if ordinaisTirados >= 2 { for q in i..<fim where p[q].item { p[q].ordinal = true } }
                // introdução termina em dois-pontos
                if i > 0 {
                    p[i].quebras = 1
                    p[i - 1].fecha = p[i - 1].fecha.filter { !",;.:".contains($0) } + ":"
                }
                // o que vem depois da lista é parágrafo novo
                if fim < p.count { p[fim].quebras = 2; p[fim].item = false }
                i = fim
            }
            for q in p.indices where p[q].quebras > 2 { p[q].quebras = 2 }
        }
        // maiúsculas: começo do texto, depois de ponto e em começo de linha
        var comeco = true
        for q in p.indices {
            if p[q].quebras > 0 { comeco = true }
            if comeco, !p[q].fixa, let c = p[q].palavra.first, c.isLowercase {
                p[q].palavra = p[q].palavra.prefix(1).uppercased() + p[q].palavra.dropFirst()
            }
            comeco = p[q].fecha.contains(where: { fortes.contains($0) })
        }
        if pontoFinal, let u = p.indices.last, p[u].fecha.isEmpty || p[u].fecha == "," {
            let emItem = p[...u].last(where: { $0.quebras > 0 || $0.item })?.item ?? p[0].item
            p[u].fecha = emItem ? "" : "."
        }
        if pontoFinal {
            // Frase que começa como pergunta e o modelo fechou com ponto: vira "?".
            var a = 0
            for q in p.indices {
                if q > a, p[q].quebras > 0 { a = q }
                guard p[q].fecha.contains(where: { fortes.contains($0) }) else { continue }
                if p[q].fecha == ".", !p[a].item, comecaPergunta(p[a...q].prefix(3).map(\.chave)) { p[q].fecha = "?" }
                a = q + 1
            }
        }
        return p
    }
}

