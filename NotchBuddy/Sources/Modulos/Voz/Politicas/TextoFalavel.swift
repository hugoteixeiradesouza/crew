import Foundation

// Regra pura: transforma markdown em texto que dá para ouvir. Bloco de código vira "trecho de
// código", link é lido pelo texto dele, e os símbolos de formatação somem.

enum TextoFalavel {
    static let marcaCodigo = "Trecho de código."

    /// Texto inteiro, pronto para a voz.
    static func limpar(_ markdown: String) -> String {
        blocos(markdown).map(limparBloco).filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    /// Só o primeiro parágrafo de verdade (título sozinho e código no começo não contam),
    /// com um teto de tamanho para a leitura não se arrastar.
    static func primeiroParagrafo(_ markdown: String, teto: Int = 600) -> String {
        for bruto in blocos(markdown) {
            let linhas = bruto.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            let soTitulo = linhas.allSatisfy { $0.hasPrefix("#") || ehRegua($0) }
            if soTitulo || bruto == marcaCodigo { continue }
            let limpo = limparBloco(bruto)
            if limpo.isEmpty { continue }
            return cortar(limpo, teto)
        }
        return ""
    }

    // MARK: Por dentro

    /// Separa em parágrafos (linha em branco), com cada bloco de código já trocado pela marca.
    private static func blocos(_ markdown: String) -> [String] {
        var saida: [String] = []
        var atual: [String] = []
        var emCodigo = false
        func fechar() {
            let b = atual.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !b.isEmpty { saida.append(b) }
            atual = []
        }
        for linha in markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let t = linha.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("```") || t.hasPrefix("~~~") {
                if !emCodigo { fechar(); saida.append(marcaCodigo) }
                emCodigo.toggle()
                continue
            }
            if emCodigo { continue }
            if t.isEmpty { fechar() } else { atual.append(linha) }
        }
        fechar()
        return saida
    }

    private static func ehRegua(_ linha: String) -> Bool {
        linha.count >= 3 && linha.allSatisfy { "-*_= ".contains($0) }
    }

    private static func limparBloco(_ bloco: String) -> String {
        if bloco == marcaCodigo { return bloco }
        var linhas: [String] = []
        for bruta in bloco.components(separatedBy: "\n") {
            var l = bruta.trimmingCharacters(in: .whitespaces)
            if ehRegua(l) { continue }
            // Linha separadora de tabela (|---|:---:|)
            if l.hasPrefix("|"), l.allSatisfy({ "|-: ".contains($0) }) { continue }
            l = trocar(l, #"^(>\s*)+"#, "")                    // citação
            l = trocar(l, #"^#{1,6}\s*"#, "")                  // título
            l = trocar(l, #"^[-*+]\s+\[[ xX]\]\s+"#, "")       // caixa de tarefa
            l = trocar(l, #"^([-*+]|\d+[.)])\s+"#, "")         // marcador de lista
            if l.hasPrefix("|") {                              // linha de tabela: células separadas por vírgula
                l = l.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }.joined(separator: ", ")
            }
            l = trocar(l, #"!\[([^\]]*)\]\([^)]*\)"#, "$1")    // imagem: fica a descrição
            l = trocar(l, #"\[([^\]]+)\]\([^)]*\)"#, "$1")     // link: fica o texto
            l = trocar(l, #"\[([^\]]+)\]\[[^\]]*\]"#, "$1")    // link por referência
            l = trocar(l, #"<https?://[^>\s]+>"#, "link")
            l = trocar(l, #"https?://[^\s)\]]+"#, "link")      // endereço solto
            l = trocar(l, #"</?[A-Za-z][^>]*>"#, "")           // tag HTML
            l = trocar(l, #"`([^`]*)`"#, "$1")                 // código na linha: fica o conteúdo
            l = trocar(l, #"(\*\*\*|\*\*|__|~~)"#, "")         // negrito, riscado
            l = trocar(l, #"(?<![\w])[*_](?=\S)|(?<=\S)[*_](?![\w])"#, "")   // itálico
            l = trocar(l, #"[`*#|~^\\]"#, "")                  // sobra de símbolo
            l = trocar(l, #"\s*(→|->|=>)\s*"#, ", ")           // setas viram pausa
            l = trocar(l, #"\s{2,}"#, " ").trimmingCharacters(in: .whitespaces)
            if l.isEmpty { continue }
            // Item de lista ou título sem ponto final: ganha um, para a voz respirar
            if let u = l.last, !".!?:;,…".contains(u) { l += "." }
            linhas.append(l)
        }
        return linhas.joined(separator: " ")
    }

    private static func trocar(_ s: String, _ padrao: String, _ por: String) -> String {
        s.replacingOccurrences(of: padrao, with: por, options: .regularExpression)
    }

    /// Corta no fim de uma frase, se houver uma antes do teto.
    private static func cortar(_ s: String, _ teto: Int) -> String {
        guard s.count > teto else { return s }
        let pedaco = String(s.prefix(teto))
        if let fim = pedaco.range(of: #"[.!?](\s|$)"#, options: [.regularExpression, .backwards]),
           pedaco.distance(from: pedaco.startIndex, to: fim.lowerBound) > teto / 3 {
            return String(pedaco[..<pedaco.index(after: fim.lowerBound)])
        }
        return pedaco + "…"
    }
}
