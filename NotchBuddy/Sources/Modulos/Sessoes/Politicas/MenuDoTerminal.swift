import Foundation

// Lê a tela do terminal de uma sessão (texto do `tmux capture-pane`) e acha o menu que um
// comando do Claude Code abriu — `/model`, `/effort`… —, para o Crew mostrar as opções no
// próprio chat. Regra pura, só Foundation: dá para conferir sozinha.
//
// O menu do Claude Code é uma lista numerada com um ponteiro na opção marcada:
//
//      Select model
//      ❯ 1. Default (recommended)   Opus · mais capaz
//        2. Sonnet                  rápido
//
// Tela que não é lista numerada (/resume, /config) não vira botões: o Crew só avisa que o
// comando espera resposta no terminal.

struct MenuDoTerminal: Equatable, Sendable {
    struct Opcao: Equatable, Sendable, Identifiable {
        var numero: Int
        var titulo: String
        var detalhe: String?
        var id: Int { numero }
    }

    var titulo: String
    var opcoes: [Opcao]
    /// Posição (na lista) da opção em que o ponteiro está.
    var marcada: Int
    /// A tela espera resposta, mas não é uma lista que o Crew saiba mostrar.
    var soNoTerminal = false

    /// Os comandos que o campo sugere ao digitar "/".
    static let comandos: [(nome: String, descricao: String)] = [
        ("model", "trocar o modelo da sessão"),
        ("effort", "quanto o modelo pensa"),
        ("compact", "resumir a conversa para liberar contexto"),
        ("clear", "começar conversa nova na mesma sessão"),
        ("context", "quanto do contexto está em uso"),
        ("cost", "custo da sessão"),
        ("usage", "uso do plano"),
        ("permissions", "regras de permissão"),
        ("mcp", "servidores MCP"),
        ("agents", "agentes"),
        ("memory", "editar a memória"),
        ("review", "revisar as mudanças"),
        ("rewind", "voltar a um ponto anterior"),
        ("resume", "retomar outra conversa"),
        ("config", "ajustes do Claude Code"),
        ("status", "estado da sessão"),
        ("help", "ajuda"),
    ]

    private static let ponteiros: Set<Character> = ["❯", ">", "›", "▶", "→"]
    private static let moldura = CharacterSet(charactersIn: "│┃|╭╮╰╯─━ \t")

    /// O menu que está na tela agora (nil = nenhum).
    static func ler(_ tela: String) -> MenuDoTerminal? {
        let linhas = tela.components(separatedBy: "\n").map { $0.trimmingCharacters(in: moldura) }
        // Cada linha numerada: (linha, ponteiro, número, texto).
        var numeradas: [(linha: Int, ponteiro: Bool, numero: Int, texto: String)] = []
        for (i, l) in linhas.enumerated() {
            var resto = Substring(l)
            var ponteiro = false
            if let p = resto.first, ponteiros.contains(p) {
                ponteiro = true
                resto = resto.dropFirst().drop { $0 == " " }
            }
            let digitos = resto.prefix { $0.isNumber }
            guard !digitos.isEmpty, digitos.count <= 2, let n = Int(digitos) else { continue }
            let depois = resto.dropFirst(digitos.count)
            guard depois.hasPrefix(". ") else { continue }
            let texto = depois.dropFirst(2).trimmingCharacters(in: .whitespaces)
            guard !texto.isEmpty else { continue }
            numeradas.append((i, ponteiro, n, texto))
        }
        // O menu é o último grupo que começa em 1, sobe de um em um e tem um ponteiro.
        guard let fim = numeradas.indices.last else { return telaQueEspera(linhas) }
        var inicio = fim
        while inicio > 0, numeradas[inicio].numero != 1 { inicio -= 1 }
        let grupo = Array(numeradas[inicio...fim])
        let emOrdem = grupo.enumerated().allSatisfy { $0.element.numero == $0.offset + 1 }
        guard grupo.count >= 2, emOrdem, grupo.filter(\.ponteiro).count == 1,
              let marcada = grupo.firstIndex(where: \.ponteiro) else { return telaQueEspera(linhas) }
        // Menu de verdade fica no pé da tela: depois dele só vêm dicas ("Enter to confirm").
        let depois = linhas[(grupo[grupo.count - 1].linha + 1)...].filter { !$0.isEmpty }
        guard depois.count <= 6 else { return nil }
        // Título: a linha com texto mais perto, acima da primeira opção.
        var titulo = ""
        var i = grupo[0].linha - 1
        var achadas: [String] = []
        while i >= 0, achadas.count < 2 {
            if linhas[i].isEmpty { if !achadas.isEmpty { break } } else { achadas.insert(linhas[i], at: 0) }
            i -= 1
        }
        titulo = achadas.first ?? ""
        let opcoes = grupo.map { g -> Opcao in
            // "Nome      explicação": duas ou mais colunas de espaço separam o detalhe.
            if let corte = g.texto.range(of: #"\s{2,}"#, options: .regularExpression) {
                let detalhe = g.texto[corte.upperBound...].trimmingCharacters(in: .whitespaces)
                return Opcao(numero: g.numero, titulo: String(g.texto[..<corte.lowerBound]), detalhe: detalhe.isEmpty ? nil : detalhe)
            }
            return Opcao(numero: g.numero, titulo: g.texto, detalhe: nil)
        }
        return MenuDoTerminal(titulo: titulo, opcoes: opcoes, marcada: marcada)
    }

    /// Tela sem lista numerada mas com a dica de quem espera tecla ("Esc to cancel", "Enter to …").
    private static func telaQueEspera(_ linhas: [String]) -> MenuDoTerminal? {
        let pe = linhas.filter { !$0.isEmpty }.suffix(4).joined(separator: " ").lowercased()
        let espera = ["esc to cancel", "esc to exit", "esc to close", "esc to go back", "enter to confirm", "enter to select"]
        guard espera.contains(where: pe.contains) else { return nil }
        return MenuDoTerminal(titulo: "", opcoes: [], marcada: 0, soNoTerminal: true)
    }
}
