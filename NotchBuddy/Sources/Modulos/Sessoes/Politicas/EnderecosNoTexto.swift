import Foundation

// Acha os endereços da web num texto, para virarem link: com esquema (https://…), com www.,
// ou só o domínio ("app.exemplo.com.br/op/p/abc"). Regra pura, só Foundation.
// O detector do sistema sozinho erra para os dois lados: ignora nada, mas "acha" nome de
// arquivo (README.md vira site da Moldávia). Sem esquema, só vale domínio com terminação
// conhecida e que não esteja colado num caminho de arquivo.

enum EnderecosNoTexto {
    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    /// Terminações aceitas num endereço escrito sem "https://".
    private static let terminacoes: Set<String> = [
        "com", "br", "org", "net", "io", "dev", "app", "ai", "co", "me", "gov", "edu", "info", "xyz", "tech",
        "sh", "so", "to", "ly", "gg", "tv", "us", "uk", "pt", "eu", "de", "fr", "es", "it", "ca", "au", "jp",
        "cloud", "site", "online", "store", "blog", "page", "art", "link", "run", "build", "new",
    ]

    static func achar(em texto: String) -> [(NSRange, URL)] {
        guard let detector else { return [] }
        let ns = texto as NSString
        return detector.matches(in: texto, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            guard let url = m.url, let esquema = url.scheme?.lowercased(), esquema == "http" || esquema == "https" else { return nil }
            let escrito = ns.substring(with: m.range).lowercased()
            if escrito.hasPrefix("http://") || escrito.hasPrefix("https://") { return (m.range, url) }
            // Sem esquema: o domínio tem que ser de verdade…
            let dominio = String(escrito.prefix { $0 != "/" && $0 != "?" && $0 != "#" && $0 != ":" })
            guard dominio.range(of: #"^([a-z0-9-]+\.)+[a-z]{2,}$"#, options: .regularExpression) != nil,
                  let fim = dominio.split(separator: ".").last, terminacoes.contains(String(fim)) else { return nil }
            // …e não pode ser pedaço de um caminho ou de um e-mail ("docs/site.com", "a@b.com").
            if m.range.location > 0 {
                let antes = ns.substring(with: NSRange(location: m.range.location - 1, length: 1))
                if antes.range(of: #"[/\\.@\w~-]"#, options: .regularExpression) != nil { return nil }
            }
            // Escrito sem esquema, abre por https.
            var c = URLComponents(url: url, resolvingAgainstBaseURL: false)
            c?.scheme = "https"
            return (m.range, c?.url ?? url)
        }
    }
}
