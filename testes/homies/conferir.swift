import Foundation

// Conferência das regras dos Homies: quem coordena quem, a ordem da equipe na tela, a leitura
// da página que a rotina entrega e o pedido com que a rotina abre.

@main
enum Conferir {
    nonisolated(unsafe) static var falhas = 0
    nonisolated(unsafe) static var feitas = 0

    static func confere(_ ok: Bool, _ o: String) {
        feitas += 1
        if !ok { falhas += 1; print("  FALHOU: \(o)") }
    }

    static func main() {
        // Time
        let cfo = Homie(nome: "CFO", funcao: "Coordena o financeiro", pasta: "/h/cfo")
        let analista = Homie(nome: "Analista", funcao: "Junta os números", pasta: "/h/analista", chefe: cfo.id)
        let previsor = Homie(nome: "Previsor", pasta: "/h/previsor", chefe: cfo.id)
        let estagiario = Homie(nome: "Estagiário", pasta: "/h/est", chefe: analista.id)
        let solto = Homie(nome: "Solto", pasta: "/h/solto")
        let todos = [solto, estagiario, analista, cfo, previsor]
        confere(PoliticaHomies.time(de: cfo.id, em: todos).map(\.nome).sorted() == ["Analista", "Estagiário", "Previsor"], "o time inclui quem responde por meio de outro")
        confere(PoliticaHomies.time(de: solto.id, em: todos).isEmpty, "quem não coordena não tem time")
        confere(!PoliticaHomies.podeCoordenar(cfo.id, a: cfo.id, em: todos), "ninguém coordena a si mesmo")
        confere(!PoliticaHomies.podeCoordenar(estagiario.id, a: cfo.id, em: todos), "quem responde ao chefe não vira chefe dele")
        confere(PoliticaHomies.podeCoordenar(solto.id, a: cfo.id, em: todos), "um de fora pode coordenar")
        let ordem = PoliticaHomies.equipe(todos)
        confere(ordem.map(\.homie.nome) == ["Solto", "CFO", "Analista", "Estagiário", "Previsor"], "cada coordenador vem seguido do time")
        confere(ordem.map(\.nivel) == [0, 0, 1, 2, 1], "o recuo segue a hierarquia")
        // Círculo e chefe sumido no arquivo: todo mundo aparece uma vez
        var a = Homie(nome: "A"), b = Homie(nome: "B")
        a.chefe = b.id; b.chefe = a.id
        let orfao = Homie(nome: "Órfão", chefe: UUID())
        let torto = PoliticaHomies.equipe([a, b, orfao])
        confere(Set(torto.map(\.homie.nome)) == ["A", "B", "Órfão"] && torto.count == 3, "círculo e chefe sumido não somem com ninguém")
        // Instrução
        let comTime = PoliticaHomies.instrucaoDaSessao(cfo, time: [analista, previsor])
        confere(comTime.contains("Analista — Junta os números — pasta: /h/analista") && comTime.contains("ferramenta Agent"), "o coordenador recebe o time e como usar")
        confere(!PoliticaHomies.instrucaoDaSessao(solto).contains("coordena"), "sem time, sem instrução de time")
        confere(PoliticaHomies.instrucaoDaSessao(analista, chefe: cfo).contains("time de CFO"), "o membro sabe a quem responde")
        // Homie gravado antes do campo novo
        let antigo = try? JSONDecoder().decode(Homie.self, from: Data(#"{"nome":"Velho","pasta":"/x"}"#.utf8))
        confere(antigo?.nome == "Velho" && antigo?.chefe == nil, "homies.json antigo continua lendo")

        // Página
        let json = #"{"titulo":"Manhã","resumo":"**Caixa** ok","acoes":[{"titulo":"Cobrar X","pedido":"Redija a cobrança para X","quem":"Analista"},{"titulo":"sem pedido"},{"titulo":"Cancelar Y","pedido":"Liste o que cancelar"}]}"#
        let p = PaginaHomie.ler(Data(json.utf8))
        confere(p?.titulo == "Manhã" && p?.resumo == "**Caixa** ok", "título e resumo da página")
        confere(p?.acoes.map(\.titulo) == ["Cobrar X", "Cancelar Y"] && p?.acoes.map(\.id) == ["0", "1"], "ação sem pedido é descartada")
        confere(p?.acoes.first?.quem == "Analista" && p?.acoes.last?.quem == "", "quem faz cada ação")
        confere(PaginaHomie.ler(Data("não é json".utf8)) == nil, "arquivo quebrado não vira página")
        confere(PaginaHomie.ler(Data("{}".utf8)) == nil, "página vazia não vira página")
        confere(PaginaHomie.ler(Data(#"{"resumo":"nada novo","semNovidade":true}"#.utf8))?.semNovidade == true, "sem novidade")
        let muitas = (0..<20).map { #"{"titulo":"a\#($0)","pedido":"p"}"# }.joined(separator: ",")
        confere(PaginaHomie.ler(Data("{\"acoes\":[\(muitas)]}".utf8))?.acoes.count == PoliticaHomies.maxAcoes, "teto de ações")

        // Pedido da rotina
        let rid = UUID()
        let pedido = PoliticaHomies.pedidoDaRotina(nome: "Página da manhã", entrega: "  caixa e 3 movimentos \n", rotina: rid, quando: "hoje às 07:30", comTime: false)
        confere(pedido.contains("paginas/\(rid.uuidString.lowercased()).json"), "o pedido diz onde escrever a página")
        confere(pedido.contains("\ncaixa e 3 movimentos\n--- fim ---"), "o que o Hugo configurou vai inteiro e limpo")
        confere(pedido.contains("Não execute nenhuma ação") && pedido.contains("Ninguém responde"), "a rotina só propõe e não pergunta")
        confere(!pedido.contains("seu time"), "sem time, o pedido não fala em time")
        confere(PoliticaHomies.pedidoDaRotina(nome: "x", entrega: "y", rotina: rid, quando: "", comTime: true).contains("Use o seu time"), "com time, o pedido manda usar")

        // Ferramentas: servidores MCP só da pasta do Homie.
        confere(FerramentasHomie.nome("  Meu Notion! ") == "meu-notion", "o nome da ferramenta sai limpo")
        confere(FerramentasHomie.nome("crew") == nil && FerramentasHomie.nome(" ?? ") == nil, "nome reservado ou vazio não passa")
        confere(FerramentasHomie.erroDoEndereco("https://mcp.notion.com/mcp") == nil, "https serve")
        confere(FerramentasHomie.erroDoEndereco("http://127.0.0.1:3845/mcp") == nil, "http neste Mac serve")
        confere(FerramentasHomie.erroDoEndereco("http://exemplo.com/mcp") != nil && FerramentasHomie.erroDoEndereco("notion") != nil, "http de fora e texto solto não servem")
        confere(FerramentasHomie.argumentosLigar("notion", .http("https://mcp.notion.com/mcp")) == ["mcp", "add", "--scope", "local", "--transport", "http", "notion", "https://mcp.notion.com/mcp"], "ligar por endereço vale só na pasta")
        confere(FerramentasHomie.argumentosLigar("apps-do-mac", .comando("npx", ["-y", "x@1"])) == ["mcp", "add", "--scope", "local", "apps-do-mac", "--", "npx", "-y", "x@1"], "ligar por comando vale só na pasta")
        confere(Set(FerramentasHomie.catalogo.map(\.id)).count == FerramentasHomie.catalogo.count && FerramentasHomie.catalogo.allSatisfy { FerramentasHomie.nome($0.id) == $0.id }, "o catálogo não repete nome e todos são nomes válidos")
        confere(FerramentasHomie.catalogo.allSatisfy { if case .http(let u) = $0.servidor { return FerramentasHomie.erroDoEndereco(u) == nil }; return true }, "todo endereço do catálogo é aceito")
        let cj = Data(#"{"projects":{"/h/ana":{"mcpServers":{"notion":{"type":"http","url":"https://mcp.notion.com/mcp"}}},"/outro":{"mcpServers":{"loja":{"type":"http","url":"https://x.y/mcp"}}}}}"#.utf8)
        let mj = Data(#"{"mcpServers":{"mac":{"command":"npx","args":["-y","z"]},"notion":{"type":"http","url":"https://velho"}}}"#.utf8)
        let lig = FerramentasHomie.ligadas(claudeJson: cj, mcpJson: mj, pastas: ["/h/ana"])
        confere(lig.map(\.nome) == ["mac", "notion"], "ele enxerga as da aba e as da pasta, sem repetir")
        confere(lig.first { $0.nome == "notion" }?.origem == .crew && lig.first { $0.nome == "mac" }?.destino == "npx -y z", "a da aba vence a da pasta; comando aparece inteiro")
        confere(lig.first { $0.nome == "notion" }?.servidor == .http("https://mcp.notion.com/mcp") && lig.first { $0.nome == "mac" }?.servidor == .comando("npx", ["-y", "z"]), "a conectada sabe se religar em outro Homie")
        confere(!lig.contains { $0.nome == "loja" }, "ferramenta de outra pasta não entra")
        let cfg = FerramentasHomie.configDaRotina(claudeJson: cj, mcpJson: mj, pastas: ["/h/ana"]).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: [String: Any]] }
        confere(cfg?["mcpServers"].map { Set($0.keys) } == ["mac", "notion"], "a rotina recebe só as ferramentas dele")
        confere(FerramentasHomie.configDaRotina(claudeJson: cj, mcpJson: nil, pastas: ["/h/bia"]) == nil, "sem ferramenta, a rotina vai sem MCP")
        confere(FerramentasHomie.situacao("x:\n  Status: ✔ Connected\n") == .conectada, "lê conectada")
        confere(FerramentasHomie.situacao("  Status: ! Needs authentication") == .faltaEntrar, "lê falta entrar")
        confere(FerramentasHomie.situacao("  Status: ✘ Failed to connect") == .falhou("✘ Failed to connect"), "lê a falha")

        print("\n\(feitas) conferências, \(falhas) falhas")
        exit(falhas == 0 ? 0 : 1)
    }
}
