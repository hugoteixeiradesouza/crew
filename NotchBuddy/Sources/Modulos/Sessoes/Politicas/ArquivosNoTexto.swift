import Foundation

// Acha os arquivos citados numa resposta do jeito que o Claude escreve — `Fontes/Leitor.swift`,
// `Leitor.swift:42`, `/caminho/inteiro.md:10-20` — para virarem link (⌘ clique abre dentro do
// Crew). Completa o `CaminhosNoTexto`, que só pega caminho inteiro (desde "/" ou "~/") e sem
// ":linha". Caminho relativo é procurado na pasta da sessão. Só vale o que existe no disco e é
// arquivo: é o que impede "e/ou" ou "v1.2" de virar link. Regra pura, só Foundation.

enum ArquivosNoTexto {
    struct Achado: Equatable {
        var faixa: NSRange
        var url: URL
        /// A linha citada depois dos dois pontos ("arquivo:42"), se houver.
        var linha: Int?
    }

    private static let padrao = try? NSRegularExpression(
        pattern: #"(?<![\w/.~@:-])((?:~/|\.{1,2}/|/)?(?:[\w@+\-][\w.@+\-]*/)*[\w@+\-][\w.@+\-]*\.[A-Za-z][A-Za-z0-9]{0,7})(?::(\d{1,6})(?:[-:]\d{1,6})?)?(?![\w/])"#)
    /// Resposta enorme não é varrida além disso.
    private static let maximo = 80

    static func achar(em texto: String, pasta: String?) -> [Achado] {
        guard let padrao, texto.contains(".") else { return [] }
        let ns = texto as NSString
        let fm = FileManager.default
        var out: [Achado] = []
        var conferidos: [String: URL?] = [:]
        for m in padrao.matches(in: texto, range: NSRange(location: 0, length: ns.length)).prefix(maximo) {
            let escrito = ns.substring(with: m.range(at: 1))
            let linha = m.range(at: 2).location == NSNotFound ? nil : Int(ns.substring(with: m.range(at: 2)))
            let url: URL?
            if let ja = conferidos[escrito] {
                url = ja
            } else {
                var caminho: String?
                if escrito.hasPrefix("/") { caminho = escrito }
                else if escrito.hasPrefix("~/") { caminho = (escrito as NSString).expandingTildeInPath }
                else if let pasta { caminho = (pasta as NSString).appendingPathComponent(escrito) }
                var ehPasta: ObjCBool = false
                if let c = caminho, fm.fileExists(atPath: c, isDirectory: &ehPasta), !ehPasta.boolValue {
                    url = URL(fileURLWithPath: c).standardizedFileURL
                } else {
                    url = nil
                }
                conferidos[escrito] = url
            }
            // Caminho inteiro sem ":linha" já é assunto do `CaminhosNoTexto`.
            guard let url, !(linha == nil && (escrito.hasPrefix("/") || escrito.hasPrefix("~/"))) else { continue }
            out.append(Achado(faixa: m.range, url: url, linha: linha))
        }
        return out
    }
}
