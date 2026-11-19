import AppKit

// Conversas de exemplo (JSONL no formato do Claude Code) para o modo de capturas: a mensagem
// com texto colado e imagens — a forma que sumia do chat — e um turno com os passos das
// ferramentas (comando com saída longa, leituras em sequência, edição, erro, bloqueio do modo
// automático e um passo ainda rodando).

enum ConversaExemplo {
    private static func gravar(_ nome: String, _ linhas: [[String: Any]]) -> String {
        let caminho = NSTemporaryDirectory() + nome
        let txt = linhas.compactMap { try? JSONSerialization.data(withJSONObject: $0) }
            .compactMap { String(data: $0, encoding: .utf8) }.joined(separator: "\n") + "\n"
        try? txt.write(toFile: caminho, atomically: true, encoding: .utf8)
        return caminho
    }

    private static func hora(_ segundos: Int) -> String {
        String(format: "2026-11-13T11:%02d:%02d.000Z", 40 + segundos / 60, segundos % 60)
    }

    private static func hugo(_ conteudo: Any, em s: Int, modo: String = "auto") -> [String: Any] {
        ["type": "user", "timestamp": hora(s), "origin": ["kind": "human"], "permissionMode": modo,
         "message": ["role": "user", "content": conteudo]]
    }

    private static func claude(_ texto: String, em s: Int) -> [String: Any] {
        ["type": "assistant", "timestamp": hora(s),
         "message": ["role": "assistant", "id": "msg_t\(s)", "usage": ["output_tokens": 180], "content": [["type": "text", "text": texto]]]]
    }

    private static func pensou(_ ms: Int, em s: Int) -> [String: Any] {
        ["type": "assistant", "timestamp": hora(s), "thinkingDurationMs": ms,
         "message": ["role": "assistant", "id": "msg_p\(s)", "content": [["type": "thinking", "thinking": ""]]]]
    }

    private static func uso(_ id: String, _ nome: String, _ entrada: [String: Any], em s: Int) -> [String: Any] {
        ["type": "assistant", "timestamp": hora(s),
         "message": ["role": "assistant", "id": "msg_" + id, "usage": ["output_tokens": 90],
                     "content": [["type": "tool_use", "id": id, "name": nome, "input": entrada]]]]
    }

    private static func volta(_ id: String, _ conteudo: String, em s: Int, erro: Bool = false, estruturado: [String: Any]? = nil) -> [String: Any] {
        var o: [String: Any] = ["type": "user", "timestamp": hora(s),
                                "message": ["role": "user", "content": [["type": "tool_result", "tool_use_id": id, "content": conteudo, "is_error": erro]]]]
        if let estruturado { o["toolUseResult"] = estruturado }
        return o
    }

    private static func lido(_ linhas: Int, de total: Int? = nil) -> [String: Any] {
        ["type": "text", "file": ["numLines": linhas, "totalLines": total ?? linhas]]
    }

    /// Uma "captura de tela" desenhada em código, para servir de imagem colada.
    private static func imagem(_ cor: NSColor, _ titulo: String) -> [String: Any] {
        let tamanho = NSSize(width: 420, height: 260)
        let img = NSImage(size: tamanho)
        img.lockFocus()
        NSColor(white: 0.09, alpha: 1).setFill()
        NSRect(origin: .zero, size: tamanho).fill()
        cor.withAlphaComponent(0.85).setFill()
        NSBezierPath(roundedRect: NSRect(x: 18, y: 200, width: 150, height: 14), xRadius: 7, yRadius: 7).fill()
        NSColor(white: 1, alpha: 0.12).setFill()
        for i in 0..<5 {
            NSBezierPath(roundedRect: NSRect(x: 18, y: 160 - CGFloat(i) * 30, width: CGFloat(380 - i * 46), height: 12), xRadius: 6, yRadius: 6).fill()
        }
        (titulo as NSString).draw(at: NSPoint(x: 18, y: 228), withAttributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor(white: 1, alpha: 0.8)])
        img.unlockFocus()
        let png = img.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0) }?.representation(using: .png, properties: [:]) ?? Data()
        return ["type": "image", "source": ["type": "base64", "media_type": "image/png", "data": png.base64EncodedString()]]
    }

    /// Mensagem com texto colado (itens numerados) e duas imagens, como o Claude Code grava:
    /// o texto colado dentro de <pasted_content>, depois o que foi digitado e as marcas [Image #N].
    static func colada() -> String {
        let colado = """
        1. o menu lateral está apertado: quando troco de setor, a lista de sessões abre por cima e eu perco onde estava.
        2. o navegador não guarda as abas quando fecho a janela.
        3. no chat, o que eu digitei não aparece: só as imagens.
        """
        let texto = "\n\n<pasted_content id=\"2660\">\n\(colado)\n</pasted_content id=\"2660\">\n\n4. quero ver os passos do Claude como no terminal.[Image #1] [Image #2]"
        return gravar("crew-captura-colada.jsonl", [
            hugo("o que mudou na barra lateral ontem?", em: 0),
            claude("Ontem a barra ganhou os **seis setores** e o atalho ⌘1 … ⌘6. A lista de sessões continua a mesma.", em: 6),
            hugo([["type": "text", "text": texto], imagem(.systemBlue, "Chat do Crew"), imagem(.systemOrange, "Terminal")], em: 60),
            ["type": "user", "isMeta": true, "timestamp": hora(60),
             "message": ["role": "user", "content": [["type": "text", "text": "[Image: source: /tmp/imagem-colada-1.png]"]]]],
            pensou(6400, em: 61),
            uso("c1", "Read", ["file_path": "/Users/hugo/dev/crew/NotchBuddy/Sources/Modulos/Sessoes/Chat/SessionChat.swift"], em: 68),
            volta("c1", "…", em: 69, estruturado: lido(564)),
            uso("c2", "Bash", ["command": "testes/conversa/conferir.sh", "description": "Conferir o leitor da conversa com o transcript de verdade"], em: 72),
            volta("c2", "== Caso real\n  leitor antigo: 0 letras de texto e 2 imagens\n  leitor novo: o texto inteiro e 2 imagens\n67 conferências, 0 falhas", em: 84),
            claude("Achei: o leitor jogava fora toda fala que começasse com `<` — e texto colado chega embrulhado em `<pasted_content>`. Agora só a marca sai; o texto fica inteiro, com as duas imagens.", em: 90),
            ["type": "system", "subtype": "turn_duration", "durationMs": 30000, "timestamp": hora(90)],
        ])
    }

    /// Um turno terminado (recolhido) e um em andamento, com cada tipo de passo.
    static func passos() -> String {
        let saida = (["** BUILD SUCCEEDED **", "Compilando 214 arquivos Swift", "Ligando Crew.app"] + (1...110).map { "CompileSwift normal arm64 Arquivo\($0).swift" })
            .joined(separator: "\n")
        return gravar("crew-captura-passos.jsonl", [
            hugo("a conversa está mostrando os passos?", em: 0),
            uso("p0", "Grep", ["pattern": "CaminhoTurno", "path": "NotchBuddy/Sources"], em: 3),
            volta("p0", "a.swift:1\nb.swift:2\nc.swift:3", em: 4),
            uso("p00", "Read", ["file_path": "/p/PassosTurno.swift"], em: 5),
            volta("p00", "…", em: 6, estruturado: lido(310)),
            claude("Sim: cada ferramenta vira uma linha, e o turno recolhe quando termina.", em: 12),
            ["type": "system", "subtype": "turn_duration", "durationMs": 12000, "timestamp": hora(12)],

            hugo("compila, roda os testes e me diz o que quebrou", em: 60),
            pensou(8200, em: 61),
            claude("Vou ler os arquivos do leitor antes de compilar.", em: 70),
            uso("p1", "Read", ["file_path": "/p/Chat/SessionChat.swift"], em: 71),
            volta("p1", "…", em: 72, estruturado: lido(620)),
            uso("p2", "Read", ["file_path": "/p/Chat/PassosConversa.swift"], em: 72),
            volta("p2", "…", em: 73, estruturado: lido(380)),
            uso("p3", "Read", ["file_path": "/p/Politicas/TextoDoPedido.swift"], em: 73),
            volta("p3", "…", em: 74, estruturado: lido(104)),
            uso("p4", "Read", ["file_path": "/p/Central/ConversaCrew.swift", "limit": 200], em: 74),
            volta("p4", "…", em: 75, estruturado: lido(200, de: 1199)),
            uso("p5", "Bash", ["command": "xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Release build 2>&1 | tail -120",
                               "description": "Compilar o Crew"], em: 76),
            volta("p5", saida, em: 141),
            uso("p6", "Edit", ["file_path": "/p/Politicas/TextoDoPedido.swift", "old_string": "a", "new_string": "b"], em: 144),
            volta("p6", "ok", em: 145, estruturado: ["filePath": "/p/Politicas/TextoDoPedido.swift", "structuredPatch": [["lines": [
                "         // Comandos de barra e lembretes do sistema chegam como tags; não são conversa.",
                "-        if text.hasPrefix(\"<\") { text = \"\" }",
                "+        text = TextoDoPedido.limpar(text, humano: origem == \"human\")",
                "+        // Texto colado vem embrulhado em marcas: sai a marca, fica o texto."]]]]),
            uso("p7", "Bash", ["command": "testes/conversa/conferir.sh", "description": "Rodar a conferência do leitor"], em: 147),
            volta("p7", "Exit code 1\n  FALHOU: comando de barra sem argumento\n66 conferências, 1 falhas", em: 153, erro: true),
            uso("p8", "Bash", ["command": "scripts/instalar.sh", "description": "Instalar o Crew para testar"], em: 155),
            volta("p8", "Permission for this action was denied by the Claude Code auto mode classifier. Reason: reiniciar o Crew derruba as sessões abertas; \(Usuario.nome) não autorizou. If you have other tasks, continue.", em: 156, erro: true),
            uso("p9", "Agent", ["description": "Varrer as transcrições atrás de outras formas de mensagem", "prompt": "…", "subagent_type": "Explore"], em: 158),
            volta("p9", "Async agent launched", em: 159, estruturado: ["isAsync": true, "agentId": "a1"]),
            uso("p10", "WebFetch", ["url": "https://code.claude.com/docs/pt/hooks", "prompt": "…"], em: 160),
            volta("p10", "A página descreve os eventos de hook do Claude Code.\nPreToolUse roda antes de cada ferramenta.", em: 164),
            claude("Um teste falhou no comando de barra sem argumento. Corrigindo.", em: 166),
            uso("p11", "Bash", ["command": "testes/conversa/conferir.sh 2>&1 | tail -5", "description": "Rodar a conferência de novo"], em: 168),
        ])
    }

    // MARK: Entregáveis (tabela, código, resposta longa) — dados fictícios, de nenhum projeto.

    /// Uma pasta de projeto de mentira no temporário, para os caminhos das cenas existirem
    /// (caminho só vira link quando o arquivo existe).
    static func pastaExemplo() -> String {
        let raiz = NSTemporaryDirectory() + "crew-captura-projeto"
        let fm = FileManager.default
        for (arquivo, linhas) in [("Fontes/Leitor.swift", 80), ("Fontes/Tabela.swift", 40), ("roteiro.md", 12)] {
            let caminho = raiz + "/" + arquivo
            try? fm.createDirectory(atPath: (caminho as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            let txt = (1...linhas).map { "// linha \($0)" }.joined(separator: "\n")
            try? txt.write(toFile: caminho, atomically: true, encoding: .utf8)
        }
        return raiz
    }

    private static func resposta(_ nome: String, pedido: String, _ texto: String) -> String {
        gravar(nome, [
            hugo(pedido, em: 0),
            claude(texto, em: 20),
            ["type": "system", "subtype": "turn_duration", "durationMs": 20000, "timestamp": hora(20)],
        ])
    }

    /// Tabela com uma coluna curta, uma média e uma de lista longa (17 linhas).
    static let textoTabelaLista: String = {
        let rotas = ["Depósito Norte → Loja Centro", "Depósito Norte → Loja Jardim", "Depósito Sul → Loja Centro",
                     "Depósito Sul → Quiosque Praça", "Loja Centro → Loja Jardim", "Fábrica → Depósito Norte",
                     "Fábrica → Depósito Sul", "Depósito Norte → Quiosque Praça", "Loja Jardim → Depósito Sul"]
        let itens = ["Caixa organizadora 30 L", "Fita adesiva larga", "Etiqueta térmica 100×50", "Palete de madeira",
                     "Filme plástico esticável", "Lacre numerado", "Saco de ráfia", "Cantoneira de papelão",
                     "Envelope de segurança", "Bobina de papel kraft", "Caneta marcadora", "Luva de proteção"]
        var linhas = ["| # | Origem → Destino | Itens (quantidade) |", "|---|---|---|"]
        for n in 1...17 {
            let quantos = [6, 2, 4, 7, 1, 5, 3][n % 7]
            let lista = (0..<quantos).map { k in "\(itens[(n * 3 + k * 5) % itens.count]) (\((n * 7 + k * 13) % 48 + 2))" }
            linhas.append("| \(n) | \(rotas[(n * 2) % rotas.count]) | \(lista.joined(separator: " · ")) |")
        }
        return """
        Levantei as transferências pendentes. São **17 remessas**, 9 delas saindo do Depósito Norte:

        \(linhas.joined(separator: "\n"))

        As remessas 4 e 11 são as maiores (7 itens cada). Quer que eu agrupe por origem antes de gerar as guias?
        """
    }()

    static func tabelaLista() -> String {
        resposta("crew-captura-tabela-lista.jsonl", pedido: "quais transferências estão pendentes e o que vai em cada uma?", textoTabelaLista)
    }

    /// Tabela de números: valores, porcentagem e variação com sinal.
    static func tabelaNumeros() -> String {
        resposta("crew-captura-tabela-numeros.jsonl", pedido: "me dá o resumo do semestre por mês", """
        ## Resumo do semestre

        Fechamento de janeiro a junho, com a variação sobre o mês anterior:

        | Mês | Pedidos | Receita | Ticket médio | Devoluções | Variação |
        |:----|--------:|--------:|-------------:|-----------:|---------:|
        | Janeiro | 1.204 | R$ 86.420,50 | R$ 71,78 | 1,8% | — |
        | Fevereiro | 1.118 | R$ 79.905,00 | R$ 71,47 | 2,1% | -7,5% |
        | Março | 1.467 | R$ 112.380,90 | R$ 76,61 | 1,4% | +40,6% |
        | Abril | 1.390 | R$ 104.112,35 | R$ 74,90 | 1,6% | -7,4% |
        | Maio | 1.622 | R$ 131.749,00 | R$ 81,23 | 1,2% | +26,5% |
        | Junho | 1.588 | R$ 127.004,80 | R$ 79,98 | 1,3% | -3,6% |

        Março e maio puxaram o semestre; fevereiro foi o único mês abaixo de **R$ 80 mil**.

        Por canal, no mesmo período:

        | Canal | Pedidos | Participação | Observação |
        |---|---|---|---|
        | Loja física | 4.910 | 58,5% | Estável; melhor mês em maio |
        | Site | 2.730 | 32,5% | Cresceu depois da troca do frete em março |
        | Telefone | 749 | 9,0% | Caindo desde fevereiro |
        """)
    }

    /// Blocos de código com linguagem, comando, diff e caminhos de arquivo (com linha).
    static func codigo() -> String {
        let raiz = pastaExemplo()
        return resposta("crew-captura-codigo.jsonl", pedido: "onde o leitor quebra e como eu rodo a conferência?", """
        O erro está em `Fontes/Leitor.swift:42`: a linha que começa com `<` era descartada inteira. A tabela é montada em Fontes/Tabela.swift:18 e o roteiro fica em \(raiz)/roteiro.md.

        Para conferir, rode na pasta do projeto:

        ```bash
        # compila só o leitor e roda as 67 conferências
        testes/conversa/conferir.sh --todas --saida /tmp/conferencia.txt && tail -n 5 /tmp/conferencia.txt
        ```

        A correção, em três linhas:

        ```diff
         // Comandos de barra e lembretes chegam como marcas; não são conversa.
        -if texto.hasPrefix("<") { texto = "" }
        +texto = TextoDoPedido.limpar(texto, humano: origem == "human")
        +// Texto colado vem embrulhado: sai a marca, fica o texto.
        ```

        E a regra nova, inteira:

        ```swift
        enum TextoDoPedido {
            /// Tira só as marcas de colagem; o que o Hugo digitou fica como veio.
            static func limpar(_ texto: String, humano: Bool) -> String {
                guard humano else { return "" }
                return texto.replacingOccurrences(of: #"</?pasted_content[^>]*>"#, with: "", options: .regularExpression)
            }
        }
        ```

        Documentação do formato: https://code.claude.com/docs/pt/hooks
        """)
    }

    /// Resposta longa: títulos em níveis, listas, checklist, citação e separador.
    static func longa() -> String {
        resposta("crew-captura-longa.jsonl", pedido: "como ficou a migração? o que falta?", """
        # Migração do cadastro — situação

        A migração terminou em **3 das 4 etapas**. Falta só a conferência final, que depende de uma decisão sua.

        ## O que mudou na prática

        - **1.284 cadastros** passaram para o formato novo; nenhum ficou sem dono.
        - 31 tinham telefone duplicado e foram unidos:
          - 27 automáticos (mesmo nome e mesmo telefone);
          - 4 conferidos um a um.
        - O relatório antigo continua funcionando até sexta.

        ## O que falta

        1. Decidir o que fazer com os **12 cadastros sem e-mail**.
        2. Rodar a conferência final (uns 4 minutos).
        3. Desligar o formato antigo.

        ### Conferido até aqui

        - [x] Cópia de segurança antes de mexer
        - [x] Contagem igual antes e depois (1.284)
        - [ ] Conferência final com o relatório de sexta
        - [ ] Aviso para quem usa o relatório antigo

        > Atenção: desligar o formato antigo não tem volta simples. Se preferir, deixo os dois lado a lado por mais uma semana.

        ## Como desfazer

        Tudo o que foi unido está guardado por identificador: desfazer devolve os 31 cadastros em menos de um minuto.

        ---

        Minha recomendação: manter os 12 sem e-mail como estão e seguir para a conferência. Posso rodar agora?
        """)
    }

    /// Tabela larga (9 colunas): não cabe na conversa, rola para o lado.
    static let textoTabelaLarga: String = {
        var linhas = ["| Código | Produto | Categoria | Fornecedor | Estoque | Mínimo | Custo | Preço | Última entrada | Situação |",
                      "|---|---|---|---|---|---|---|---|---|---|"]
        let produtos = ["Caixa organizadora 30 L", "Fita adesiva larga", "Etiqueta térmica 100×50", "Filme esticável", "Lacre numerado", "Saco de ráfia"]
        let categorias = ["Embalagem", "Expedição", "Identificação"]
        let fornecedores = ["Fornecedor Alfa", "Fornecedor Beta", "Fornecedor Gama"]
        for n in 1...24 {
            let estoque = (n * 37) % 400, minimo = 60 + (n * 11) % 90
            linhas.append("| P-\(1000 + n * 7) | \(produtos[n % 6]) | \(categorias[n % 3]) | \(fornecedores[(n * 2) % 3]) | \(estoque) | \(minimo) | R$ \(n * 3 + 2),40 | R$ \(n * 5 + 9),90 | \(String(format: "%02d", n % 27 + 1))/0\(n % 6 + 1)/2026 | \(estoque < minimo ? "Abaixo do mínimo" : "Em dia") |")
        }
        return "Estoque completo, com custo e preço:\n\n" + linhas.joined(separator: "\n") + "\n\nSão 24 produtos; os que estão abaixo do mínimo aparecem na última coluna."
    }()

    static func tabelaLarga() -> String {
        resposta("crew-captura-tabela-larga.jsonl", pedido: "lista o estoque completo", textoTabelaLarga)
    }

    /// Para medir a montagem: uma resposta com tabela grande (linhas × 6 colunas).
    static func textoTabelaGrande(linhas n: Int) -> String {
        var linhas = ["| # | Origem → Destino | Itens (quantidade) | Peso | Valor | Situação |", "|---|---|---|---|---|---|"]
        for i in 1...n {
            let lista = (0..<(i % 6 + 1)).map { "Item de exemplo \($0 + i) (\(i * 3 % 40 + 1))" }.joined(separator: " · ")
            linhas.append("| \(i) | Depósito \(i % 4 + 1) → Loja \(i % 9 + 1) | \(lista) | \(i * 13 % 900) kg | R$ \(i * 17),50 | \(i % 3 == 0 ? "Pendente" : "Conferida") |")
        }
        return "Segue a lista completa.\n\n" + linhas.joined(separator: "\n") + "\n\nFim da lista."
    }
}
