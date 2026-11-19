import Foundation

// Acha caminhos de arquivo e de pasta num texto, para virarem link (⌘ clique abre: imagem no
// Pré-Visualização, pasta no Finder, o resto no app padrão). Só vale caminho inteiro — começando
// em "/" ou "~/" — e que exista no disco agora: é a conferência no disco que impede "e/ou" ou
// "/model" de virar link. Caminho com espaço ("Application Support") é estendido palavra a
// palavra enquanto ainda existir.

enum CaminhosNoTexto {
    private static let inicio = try? NSRegularExpression(pattern: #"(?<![\w/.~:-])(~/|/)[^\s`"'<>|*?]+"#)
    private static let sobra = CharacterSet(charactersIn: ".,;:!?)]}…")
    /// Texto muito longo (saída de comando) não é varrido além disso.
    private static let maximo = 60

    static func achar(em texto: String) -> [(NSRange, URL)] {
        guard let inicio, texto.contains("/") else { return [] }
        let ns = texto as NSString
        let fm = FileManager.default
        var out: [(NSRange, URL)] = []
        var fim = 0
        for m in inicio.matches(in: texto, range: NSRange(location: 0, length: ns.length)).prefix(maximo) {
            guard m.range.location >= fim else { continue }
            var faixa = m.range
            var achado: NSRange?
            // Tenta o trecho; se não existe, tira a pontuação do fim; se existe, tenta crescer
            // pelas palavras seguintes da mesma linha (nome com espaço).
            func existe(_ r: NSRange) -> Bool {
                let c = (ns.substring(with: r) as NSString).expandingTildeInPath
                return c.count > 1 && fm.fileExists(atPath: c)
            }
            var curta = faixa
            while curta.length > 1, !existe(curta),
                  let u = ns.substring(with: curta).unicodeScalars.last, sobra.contains(u) {
                curta.length -= 1
            }
            if existe(curta) { achado = curta }
            for _ in 0..<5 {
                let depois = faixa.location + faixa.length
                guard depois < ns.length, ns.character(at: depois) == 0x20 else { break }
                let resto = ns.substring(from: depois + 1)
                let palavra = resto.prefix { !$0.isWhitespace && !"`\"'<>|*?".contains($0) }
                guard !palavra.isEmpty else { break }
                faixa.length += 1 + (String(palavra) as NSString).length
                var tentativa = faixa
                while tentativa.length > 1, !existe(tentativa),
                      let u = ns.substring(with: tentativa).unicodeScalars.last, sobra.contains(u) {
                    tentativa.length -= 1
                }
                if existe(tentativa) { achado = tentativa }
            }
            guard let r = achado else { continue }
            let caminho = (ns.substring(with: r) as NSString).expandingTildeInPath
            // "/" sozinho e pastas do sistema de uma letra não interessam.
            guard caminho.count > 3 else { continue }
            out.append((r, URL(fileURLWithPath: caminho)))
            fim = r.location + r.length
        }
        return out
    }
}
