import Foundation

// Como um texto é cortado antes de ir para a voz humanizada. O motor gera um pedaço inteiro
// antes de devolver qualquer som (não há fala "saindo aos poucos" dentro de um pedaço), então o
// tempo até o primeiro som é o tempo de gerar o primeiro pedaço: ele tem de ser curto. Os
// seguintes são gerados enquanto o anterior toca. Cada pedaço já vem do motor com ~0,1 s de
// silêncio em cada ponta e começa e termina em zero: emendados, não estalam.

enum PedacosDeFala {
    /// Corta o texto em pedaços: a primeira frase sozinha (começa a falar mais cedo) e o resto
    /// em blocos de até ~220 caracteres, sempre em fim de frase. Primeira frase comprida abre
    /// na primeira vírgula: o tempo até o primeiro som cresce com o tamanho do primeiro pedaço
    /// (cada segundo de fala custa cerca de 1,4 s de geração, fora os ~4,5 s fixos da voz).
    static func cortar(_ texto: String) -> [String] {
        var saida = pedacosPorFrase(texto)
        if let primeira = saida.first, let corte = corteDaPrimeira(primeira) {
            saida[0] = String(primeira[..<corte]).trimmingCharacters(in: .whitespaces)
            saida.insert(String(primeira[corte...]).trimmingCharacters(in: .whitespaces), at: 1)
        }
        return saida
    }

    /// Onde abrir uma primeira frase comprida (mais de 90 caracteres): logo depois da primeira
    /// vírgula, ponto e vírgula ou dois-pontos que deixe um começo de 24 a 80 caracteres e um
    /// resto que não seja só uma palavra.
    private static func corteDaPrimeira(_ frase: String) -> String.Index? {
        guard frase.count > 90 else { return nil }
        var n = 0
        var i = frase.startIndex
        while i < frase.endIndex {
            n += 1
            let depois = frase.index(after: i)
            if n > 80 { return nil }
            if n >= 24, ",;:".contains(frase[i]), depois < frase.endIndex, frase[depois] == " ",
               frase.count - n >= 16 {
                return depois
            }
            i = depois
        }
        return nil
    }

    private static func pedacosPorFrase(_ texto: String) -> [String] {
        var frases: [String] = []
        var atual = ""
        let letras = Array(texto)
        for (i, c) in letras.enumerated() {
            if c == "\n" {
                if !atual.trimmingCharacters(in: .whitespaces).isEmpty { frases.append(atual) }
                atual = ""
                continue
            }
            atual.append(c)
            let fimDeFrase = ".!?…".contains(c) && (i + 1 == letras.count || letras[i + 1].isWhitespace)
            if fimDeFrase, atual.count >= 12 { frases.append(atual); atual = "" }
        }
        if !atual.trimmingCharacters(in: .whitespaces).isEmpty { frases.append(atual) }
        var saida: [String] = []
        for f in frases.map({ $0.trimmingCharacters(in: .whitespaces) }) where !f.isEmpty {
            if saida.count >= 2, let ultimo = saida.last, ultimo.count + f.count + 1 <= 220 {
                saida[saida.count - 1] = ultimo + " " + f
            } else {
                saida.append(f)
            }
        }
        return saida
    }
}
