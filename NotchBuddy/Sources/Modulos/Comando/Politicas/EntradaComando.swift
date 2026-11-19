import Foundation

// O que o Hugo digitou no comando universal, lido por regra pura (sem UI, sem rede):
// é pedido de tradução? é endereço? parece pergunta? Quem decide o que aparece é o serviço;
// aqui só se classifica o texto.

enum EntradaComando {
    /// Minúsculas e sem acento: "Inglês" → "ingles". É assim que tudo é comparado.
    static func dobrar(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR")).lowercased()
    }

    // MARK: Tradução

    struct PedidoTraducao: Equatable {
        /// O texto a traduzir, como foi digitado.
        let texto: String
        /// Código do idioma pedido ("en", "pt"…); nil = o Hugo não disse (decide-se pelo idioma do texto).
        let destino: String?
    }

    /// Idiomas que o comando entende pelo nome, em português e em inglês.
    static let idiomas: [(codigo: String, nome: String, apelidos: [String])] = [
        ("en", "inglês", ["ingles", "english"]),
        ("pt", "português", ["portugues", "portuguese", "pt-br", "ptbr"]),
        ("es", "espanhol", ["espanhol", "spanish", "castelhano"]),
        ("fr", "francês", ["frances", "french"]),
        ("de", "alemão", ["alemao", "german"]),
        ("it", "italiano", ["italiano", "italian"]),
        ("ja", "japonês", ["japones", "japanese"]),
        ("zh", "chinês", ["chines", "chinese", "mandarim"]),
        ("ko", "coreano", ["coreano", "korean"]),
        ("ru", "russo", ["russo", "russian"]),
        ("ar", "árabe", ["arabe", "arabic"]),
        ("nl", "holandês", ["holandes", "dutch"]),
        ("pl", "polonês", ["polones", "polish"]),
        ("tr", "turco", ["turco", "turkish"]),
        ("uk", "ucraniano", ["ucraniano", "ukrainian"]),
        ("hi", "hindi", ["hindi"]),
        ("id", "indonésio", ["indonesio", "indonesian"]),
        ("th", "tailandês", ["tailandes", "thai"]),
        ("vi", "vietnamita", ["vietnamita", "vietnamese"]),
    ]

    static func codigoDoIdioma(_ nome: String) -> String? {
        let n = dobrar(nome.trimmingCharacters(in: .whitespaces))
        return idiomas.first { $0.apelidos.contains(n) || $0.codigo == n }?.codigo
    }

    /// Nome do idioma em português ("en-US" → "inglês"); desconhecido devolve o próprio código.
    static func nomeDoIdioma(_ codigo: String) -> String {
        let base = codigo.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init)?.lowercased() ?? codigo
        return idiomas.first { $0.codigo == base }?.nome ?? codigo
    }

    private static let verbos = ["traduz", "traduza", "traduzir", "traducao de", "traducao", "translate", "tradutor"]
    private static let ligacoes = ["para o", "para a", "para", "pra", "pro", "em", "to", "in", "into"]

    /// "traduz bom dia" · "traduzir bom dia para inglês" · "good morning em português".
    /// Sem verbo e sem idioma no fim não é pedido (texto solto em outra língua é detectado depois,
    /// pelo idioma — não aqui).
    static func traducao(_ entrada: String) -> PedidoTraducao? {
        let t = entrada.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 2 else { return nil }
        let palavras = t.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        let dobradas = palavras.map(dobrar)

        // Verbo no começo ("traduz", "tradução de").
        var inicio = 0
        for v in verbos.sorted(by: { $0.count > $1.count }) {
            let partes = v.split(separator: " ").map(String.init)
            if dobradas.count > partes.count, Array(dobradas.prefix(partes.count)) == partes {
                inicio = partes.count
                break
            }
        }
        // "traduz: texto"
        if inicio == 0, let primeira = dobradas.first, primeira.hasSuffix(":"), verbos.contains(String(primeira.dropLast())),
           dobradas.count > 1 {
            inicio = 1
        }

        // Idioma no fim, depois de "em", "para"…
        var fim = palavras.count
        var destino: String?
        if let ultimo = dobradas.last, let codigo = codigoDoIdioma(ultimo) {
            for l in ligacoes.sorted(by: { $0.count > $1.count }) {
                let partes = l.split(separator: " ").map(String.init)
                let onde = dobradas.count - 1 - partes.count
                if onde >= inicio, Array(dobradas[onde..<dobradas.count - 1]) == partes {
                    fim = onde
                    destino = codigo
                    break
                }
            }
        }

        guard inicio > 0 || destino != nil, fim > inicio else { return nil }
        var texto = palavras[inicio..<fim].joined(separator: " ")
        // Aspas em volta saem: traduz "bom dia".
        let aspas = CharacterSet(charactersIn: "\"“”'‘’")
        texto = texto.trimmingCharacters(in: aspas).trimmingCharacters(in: .whitespaces)
        guard !texto.isEmpty else { return nil }
        return PedidoTraducao(texto: texto, destino: destino)
    }

    // MARK: Endereço

    /// O texto é um endereço (e não uma busca)? Devolve a URL pronta para abrir.
    /// "github.com/x" → https · "localhost:3000" e IP → http · "https://…" como está.
    /// "3.5", "arquivo" e frases não são endereço.
    static func endereco(_ entrada: String) -> URL? {
        let t = entrada.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !t.contains(" ") else { return nil }
        let baixo = t.lowercased()
        if baixo.hasPrefix("http://") || baixo.hasPrefix("https://") {
            guard let u = URL(string: t), let h = u.host(), !h.isEmpty else { return nil }
            return u
        }
        guard !t.contains("://") else { return nil }
        let hospedeiroComPorta = t.split(separator: "/", omittingEmptySubsequences: false).first.map(String.init) ?? t
        let pedacos = hospedeiroComPorta.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard let nome = pedacos.first, !nome.isEmpty, pedacos.count <= 2 else { return nil }
        if pedacos.count == 2 { guard let porta = Int(pedacos[1]), (1...65535).contains(porta) else { return nil } }
        if nome.lowercased() == "localhost" || nome.range(of: #"^\d{1,3}(\.\d{1,3}){3}$"#, options: .regularExpression) != nil {
            return URL(string: "http://" + t)
        }
        let rotulos = nome.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard rotulos.count >= 2, rotulos.allSatisfy({ !$0.isEmpty }), let tld = rotulos.last else { return nil }
        let letras = CharacterSet.letters
        guard (2...24).contains(tld.count), tld.unicodeScalars.allSatisfy({ letras.contains($0) && $0.isASCII }) else { return nil }
        let permitido = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        guard rotulos.allSatisfy({ $0.unicodeScalars.allSatisfy { permitido.contains($0) } }) else { return nil }
        // "readme.md", "foto.png": nome de arquivo, não site.
        if rotulos.count == 2, !t.contains("/"), extensoesDeArquivo.contains(tld.lowercased()) { return nil }
        return URL(string: "https://" + t)
    }

    private static let extensoesDeArquivo: Set<String> = [
        "md", "txt", "pdf", "png", "jpg", "jpeg", "gif", "svg", "heic", "mov", "mp", "zip", "dmg", "pkg", "app",
        "swift", "js", "ts", "tsx", "jsx", "py", "rb", "go", "rs", "sh", "json", "yml", "yaml", "toml", "xml",
        "html", "css", "sql", "csv", "xls", "xlsx", "doc", "docx", "ppt", "pptx", "key", "pages", "numbers", "log",
    ]

    // MARK: Pergunta

    /// Parece pergunta ou pedido em frase (e não nome de coisa): "?" no fim, ou cinco palavras ou mais.
    static func parecePergunta(_ entrada: String) -> Bool {
        let t = entrada.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasSuffix("?") { return true }
        return t.split(separator: " ", omittingEmptySubsequences: true).count >= 5
    }

    // MARK: Ação com texto

    /// "nota comprar pão" com gatilhos ["nota", "anotar"] → "comprar pão". nil = não começa por um
    /// gatilho, ou não veio texto depois dele.
    static func textoDepois(de gatilhos: [String], em entrada: String) -> String? {
        let t = entrada.trimmingCharacters(in: .whitespacesAndNewlines)
        let dobrado = dobrar(t)
        for g in gatilhos.map(dobrar).sorted(by: { $0.count > $1.count }) {
            for separador in [" ", ": "] where dobrado.hasPrefix(g + separador) {
                // `dobrar` não muda a quantidade de caracteres nas letras do português.
                let resto = String(t.dropFirst(g.count + separador.count)).trimmingCharacters(in: .whitespaces)
                return resto.isEmpty ? nil : resto
            }
        }
        return nil
    }
}
