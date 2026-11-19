import Foundation

// Como o comando universal casa o que foi digitado com um nome, e como ordena o que achou.
// Regras puras: sem UI, sem disco, sem relógio escondido (o "agora" vem de quem chama).

enum Casamento {
    /// Quanto `consulta` casa com `texto`, de 0 (não casa) a 1 (é o próprio nome).
    /// Na ordem: nome igual · começo do nome · começo de todas as palavras digitadas · iniciais
    /// ("vsc" → Visual Studio Code) · começo de uma palavra · pedaço no meio · letras na ordem.
    static func pontos(_ consulta: String, em texto: String) -> Double {
        let q = EntradaComando.dobrar(consulta).trimmingCharacters(in: .whitespaces)
        let t = EntradaComando.dobrar(texto)
        guard !q.isEmpty, !t.isEmpty else { return 0 }
        if t == q { return 1 }
        // Quanto do nome a consulta cobre: "saf" em "Safari" vale mais que em "Safari Technology Preview".
        let cobertura = Double(q.count) / Double(max(t.count, q.count))
        if t.hasPrefix(q) { return 0.86 + 0.1 * cobertura }

        let palavras = t.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        let pedidos = q.split(separator: " ").map(String.init)
        if pedidos.count > 1 {
            // Todas as palavras digitadas começam alguma palavra do nome.
            if pedidos.allSatisfy({ p in palavras.contains { $0.hasPrefix(p) } }) { return 0.74 + 0.1 * cobertura }
            if pedidos.allSatisfy({ t.contains($0) }) { return 0.5 + 0.1 * cobertura }
            return 0
        }
        if palavras.count > 1 {
            let iniciais = String(palavras.compactMap(\.first))
            if q.count >= 2, iniciais.hasPrefix(q) { return 0.72 + 0.08 * Double(q.count) / Double(iniciais.count) }
        }
        if palavras.dropFirst().contains(where: { $0.hasPrefix(q) }) { return 0.68 + 0.1 * cobertura }
        if q.count >= 2, t.contains(q) { return 0.5 + 0.1 * cobertura }
        // Letras na ordem, sem buraco grande: "sfri" → Safari. Só a partir de 3 letras.
        if q.count >= 3, let janela = menorJanela(q, t), janela <= q.count * 2 {
            return 0.22 + 0.18 * Double(q.count) / Double(janela)
        }
        return 0
    }

    /// O melhor casamento entre o nome e as palavras extras (apelidos); extra vale um pouco menos.
    static func pontos(_ consulta: String, titulo: String, extras: [String]) -> Double {
        var melhor = pontos(consulta, em: titulo)
        for e in extras { melhor = max(melhor, pontos(consulta, em: e) * 0.92) }
        return melhor
    }

    /// Tamanho do menor trecho de `t` que contém as letras de `q` na ordem (nil = não contém).
    private static func menorJanela(_ q: String, _ t: String) -> Int? {
        let qs = Array(q.filter { $0 != " " }), ts = Array(t)
        guard !qs.isEmpty, qs.count <= ts.count else { return nil }
        var melhor: Int?
        for inicio in ts.indices where ts[inicio] == qs[0] {
            var j = 0, fim = inicio
            for k in inicio..<ts.count {
                if ts[k] == qs[j] { j += 1; fim = k; if j == qs.count { break } }
            }
            if j == qs.count { melhor = min(melhor ?? Int.max, fim - inicio + 1) }
        }
        return melhor
    }
}

/// O que o Hugo escolhe sobe. Guardado só neste Mac (ajustes locais), com teto de tamanho.
struct AprendizadoComando: Codable, Equatable {
    struct Uso: Codable, Equatable {
        var vezes: Int
        var ultimo: Date
    }

    /// Por resultado (id estável): quantas vezes foi escolhido e quando.
    var usos: [String: Uso] = [:]
    /// Por texto digitado (dobrado): o que ele escolheu da última vez com aquele texto.
    var escolhas: [String: String] = [:]

    static let maxUsos = 400
    static let maxEscolhas = 300

    mutating func registrar(consulta: String, id: String, agora: Date) {
        var u = usos[id] ?? Uso(vezes: 0, ultimo: agora)
        u.vezes += 1
        u.ultimo = agora
        usos[id] = u
        let q = EntradaComando.dobrar(consulta).trimmingCharacters(in: .whitespaces)
        if !q.isEmpty, q.count <= 40 { escolhas[q] = id }
        // Teto: saem os usados há mais tempo.
        if usos.count > Self.maxUsos {
            let antigos = usos.sorted { $0.value.ultimo < $1.value.ultimo }.prefix(usos.count - Self.maxUsos).map(\.key)
            for k in antigos { usos[k] = nil }
            escolhas = escolhas.filter { usos[$0.value] != nil }
        }
        if escolhas.count > Self.maxEscolhas {
            // Sem data por escolha: ficam as dos resultados mais recentes.
            let ordenadas = escolhas.sorted { (usos[$0.value]?.ultimo ?? .distantPast) > (usos[$1.value]?.ultimo ?? .distantPast) }
            escolhas = Dictionary(uniqueKeysWithValues: ordenadas.prefix(Self.maxEscolhas).map { ($0.key, $0.value) })
        }
    }

    /// Quanto somar à pontuação de um resultado (0…0,6).
    /// - escolhido antes com este mesmo texto: +0,35 (é o que faz "sa" abrir o Safari de novo);
    /// - escolhido com um texto que começa igual: +0,15;
    /// - frequência: até +0,25, caindo pela metade a cada 30 dias sem uso.
    func bonus(consulta: String, id: String, agora: Date) -> Double {
        guard let u = usos[id] else { return 0 }
        let dias = max(0, agora.timeIntervalSince(u.ultimo) / 86400)
        let frescor = max(0.2, pow(0.5, dias / 30))
        var b = min(0.25, 0.07 * log2(1 + Double(u.vezes))) * frescor
        let q = EntradaComando.dobrar(consulta).trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return b }
        if escolhas[q] == id {
            b += 0.35
        } else if escolhas.contains(where: { $0.value == id && ($0.key.hasPrefix(q) || q.hasPrefix($0.key)) }) {
            b += 0.15
        }
        return b
    }

    /// Os mais usados, do mais para o menos (para a tela sem nada digitado).
    func maisUsados(_ n: Int, agora: Date) -> [String] {
        usos.map { (id: $0.key, peso: bonus(consulta: "", id: $0.key, agora: agora), ultimo: $0.value.ultimo) }
            .sorted { $0.peso != $1.peso ? $0.peso > $1.peso : $0.ultimo > $1.ultimo }
            .prefix(n).map(\.id)
    }
}

/// A lista do painel é montada em blocos de ordem fixa. É isso que faz os arquivos (que chegam
/// depois) entrarem sem tirar do lugar o que já estava na tela.
enum ListaComando {
    /// Ordena por pontuação, do maior para o menor; empate mantém a ordem de chegada.
    static func ordenar<T>(_ itens: [T], pontos: (T) -> Double) -> [T] {
        itens.enumerated().sorted { a, b in
            let pa = pontos(a.element), pb = pontos(b.element)
            return pa != pb ? pa > pb : a.offset < b.offset
        }.map(\.element)
    }

    /// Onde fica a seleção depois que a lista muda: no mesmo item, se ele ainda existe; senão no
    /// primeiro. Devolve o id a selecionar (nil = lista vazia).
    static func selecao(antes: String?, depois ids: [String]) -> String? {
        if let antes, ids.contains(antes) { return antes }
        return ids.first
    }

    /// Anda na lista sem dar a volta: no fim, fica no fim.
    static func andar(de atual: String?, passo: Int, em ids: [String]) -> String? {
        guard !ids.isEmpty else { return nil }
        guard let atual, let i = ids.firstIndex(of: atual) else { return passo >= 0 ? ids.first : ids.last }
        return ids[min(max(i + passo, 0), ids.count - 1)]
    }
}
