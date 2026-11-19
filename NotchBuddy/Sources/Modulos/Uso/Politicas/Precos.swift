import Foundation

// Preços de referência por modelo — o ÚNICO lugar com valores em dinheiro do módulo Uso.
// Fonte: tabela de preços da API da Anthropic (referência `claude-api`, conferida na data abaixo).
// São preços de API: o Hugo pode estar em assinatura, então o custo é estimativa e os tokens são
// o número firme. Modelo fora da tabela fica só em tokens (nunca se inventa preço).
//
// Escrita de cache: 1,25× a entrada (5 min) e 2× a entrada (1 h). Leitura de cache: preço próprio.
// Modo rápido (`speed: "fast"`) só tem preço conhecido no Opus 5 e no Opus 5.5 (2× o padrão).
// Não há acréscimo por contexto longo nesta tabela: a referência não lista nenhum para estes modelos.

struct Preco: Sendable {
    /// US$ por milhão de tokens.
    let entrada: Double
    let saida: Double
    let leituraCache: Double
    /// Multiplicador do modo rápido; nil = preço do modo rápido desconhecido.
    var rapido: Double? = nil
}

enum Precos {
    /// Data em que a tabela foi conferida (aparece na Central).
    static let conferidoEm = "05/10/2026"

    /// Por prefixo do id do modelo (o mais longo que casar vence): `claude-haiku-4-5-20251001` → haiku 4.5.
    static let tabela: [(prefixo: String, nome: String, preco: Preco)] = [
        ("claude-fable-5-1", "Fable 5.1", Preco(entrada: 10, saida: 50, leituraCache: 0.25)),
        ("claude-fable-5", "Fable 5", Preco(entrada: 10, saida: 50, leituraCache: 1.00)),
        ("claude-opus-5-5", "Opus 5.5", Preco(entrada: 4, saida: 20, leituraCache: 0.20, rapido: 2)),
        ("claude-opus-5", "Opus 5", Preco(entrada: 5, saida: 25, leituraCache: 0.50, rapido: 2)),
        ("claude-sonnet-5", "Sonnet 5", Preco(entrada: 2, saida: 10, leituraCache: 0.20)),
        ("claude-haiku-4-5", "Haiku 4.5", Preco(entrada: 1, saida: 5, leituraCache: 0.10)),
    ]

    private static func entrada(_ modelo: String) -> (prefixo: String, nome: String, preco: Preco)? {
        tabela.filter { modelo == $0.prefixo || modelo.hasPrefix($0.prefixo + "-") }
            .max { $0.prefixo.count < $1.prefixo.count }
    }

    static func preco(_ modelo: String) -> Preco? { entrada(modelo)?.preco }

    /// "Opus 5.5" em vez de "claude-opus-5-5"; modelo fora da tabela fica com o id.
    static func nome(_ modelo: String) -> String {
        if let e = entrada(modelo) { return e.nome }
        return modelo.hasPrefix("claude-") ? String(modelo.dropFirst(7)) : modelo
    }

    /// Custo estimado em US$; nil se o modelo (ou o modo rápido dele) não tem preço conhecido.
    static func custo(_ t: Tokens, modelo: String) -> Double? {
        guard let p = preco(modelo) else { return nil }
        var mult = 1.0
        if t.rapidas > 0 {
            guard let r = p.rapido else { return nil }
            // Só a parte rápida paga o multiplicador; aproximação pela fração de mensagens rápidas.
            mult = 1 + (r - 1) * Double(t.rapidas) / Double(max(1, t.mensagens))
        }
        let base = Double(t.entrada) * p.entrada
            + Double(t.saida) * p.saida
            + Double(t.escrita5m) * p.entrada * 1.25
            + Double(t.escrita1h) * p.entrada * 2
            + Double(t.leituraCache) * p.leituraCache
        return base * mult / 1_000_000
    }
}
