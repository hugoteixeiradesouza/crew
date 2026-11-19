import Foundation

// Homies: regras puras (sem disco, sem tela). Um Homie é quem faz: tem nome, função, instrução
// e uma pasta própria. A sessão é só uma conversa com ele.

struct Homie: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var nome = ""
    /// Uma linha: o papel dele ("Assistente pessoal do Hugo").
    var funcao = ""
    /// Como ele trabalha: vai junto das instruções do Claude Code em toda conversa.
    var instrucao = ""
    /// Apelido do modelo (`fable`, `opus`…); nil = o padrão do CLI.
    var modelo: String? = nil
    /// A pasta dele: CLAUDE.md, `.mcp.json`, `.claude/skills/` e a memória moram aqui.
    var pasta = ""
    /// A última conversa aberta com ele (session_id do Claude Code).
    var ultimaSessao: String? = nil
    /// Nasceu de um briefing e o Claude Code ainda está montando: a conversa dele é a da montagem.
    var emConstrucao = false
    /// A quem ele responde: o Homie que coordena o time dele (nil = ninguém).
    var chefe: UUID? = nil

    init(id: UUID = UUID(), nome: String = "", funcao: String = "", instrucao: String = "", modelo: String? = nil,
         pasta: String = "", ultimaSessao: String? = nil, emConstrucao: Bool = false, chefe: UUID? = nil) {
        self.id = id; self.nome = nome; self.funcao = funcao; self.instrucao = instrucao; self.modelo = modelo
        self.pasta = pasta; self.ultimaSessao = ultimaSessao; self.emConstrucao = emConstrucao; self.chefe = chefe
    }

    // Campo novo nunca quebra o homies.json já gravado: o que falta entra com o padrão.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        nome = try c.decodeIfPresent(String.self, forKey: .nome) ?? ""
        funcao = try c.decodeIfPresent(String.self, forKey: .funcao) ?? ""
        instrucao = try c.decodeIfPresent(String.self, forKey: .instrucao) ?? ""
        modelo = try c.decodeIfPresent(String.self, forKey: .modelo)
        pasta = try c.decodeIfPresent(String.self, forKey: .pasta) ?? ""
        ultimaSessao = try c.decodeIfPresent(String.self, forKey: .ultimaSessao)
        emConstrucao = try c.decodeIfPresent(Bool.self, forKey: .emConstrucao) ?? false
        chefe = try c.decodeIfPresent(UUID.self, forKey: .chefe)
    }
}

/// A página que uma rotina do Homie entrega (`paginas/<rotina>.json` na pasta dele): o resumo e
/// os movimentos que ele propõe. Nada do que está nela foi feito: cada ação espera o clique.
struct PaginaHomie: Equatable, Sendable {
    struct Acao: Equatable, Sendable, Identifiable {
        /// Posição na página ("0", "1"…).
        var id: String
        var titulo: String
        /// O pedido inteiro que o Homie recebe se o Hugo clicar em "Fazer".
        var pedido: String
        /// Nome do Homie que deve fazer (vazio = o dono da página).
        var quem = ""
    }

    var titulo = ""
    /// O texto da página (markdown).
    var resumo = ""
    var acoes: [Acao] = []
    /// Rodou e não havia o que dizer: a página fica guardada, mas não avisa.
    var semNovidade = false

    /// Lê o arquivo que o Homie escreveu. Formato de fora: o que faltar entra vazio, ação sem
    /// título ou sem pedido é descartada, no máximo `maxAcoes`. Sem resumo e sem ação = nil.
    static func ler(_ data: Data) -> PaginaHomie? {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        func s(_ d: [String: Any], _ k: String) -> String { (d[k] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        var p = PaginaHomie(titulo: String(s(o, "titulo").prefix(120)), resumo: String(s(o, "resumo").prefix(20_000)))
        p.semNovidade = o["semNovidade"] as? Bool == true
        for a in (o["acoes"] as? [[String: Any]] ?? []) where p.acoes.count < PoliticaHomies.maxAcoes {
            let titulo = s(a, "titulo"), pedido = s(a, "pedido")
            guard !titulo.isEmpty, !pedido.isEmpty else { continue }
            p.acoes.append(Acao(id: String(p.acoes.count), titulo: String(titulo.prefix(160)), pedido: String(pedido.prefix(4000)), quem: s(a, "quem")))
        }
        return p.resumo.isEmpty && p.acoes.isEmpty && !p.semNovidade ? nil : p
    }
}

/// A ficha do Homie na pasta dele (`homie.json`): o que o Claude Code escreve ao montar ou
/// ajustar um Homie, e por onde o Crew fica sabendo.
struct FichaHomie: Codable, Equatable {
    var nome: String?
    var funcao: String?
    var instrucao: String?
    var modelo: String?
    /// A montagem terminou.
    var pronto: Bool?
}

enum PoliticaHomies {
    /// Nome de pasta a partir do nome do Homie: minúsculas, sem acento, só letras, números e hífen.
    static func slug(_ nome: String) -> String {
        let limpo = nome.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR")).lowercased()
        var s = ""
        for c in limpo.unicodeScalars {
            if (c.value >= 97 && c.value <= 122) || (c.value >= 48 && c.value <= 57) {
                s.unicodeScalars.append(c)
            } else if !s.hasSuffix("-") && !s.isEmpty {
                s.append("-")
            }
        }
        while s.hasSuffix("-") { s.removeLast() }
        return s.isEmpty ? "homie" : String(s.prefix(40))
    }

    /// Pasta livre para um Homie novo: `slug`, `slug-2`, `slug-3`… (`ocupadas` = nomes já em uso).
    static func nomeDePasta(_ nome: String, ocupadas: Set<String>) -> String {
        let base = slug(nome)
        if !ocupadas.contains(base) { return base }
        var n = 2
        while ocupadas.contains("\(base)-\(n)") { n += 1 }
        return "\(base)-\(n)"
    }

    /// O que toda conversa com o Homie recebe além das instruções do Claude Code. `time` = quem
    /// responde a ele (com o time, ele coordena); `chefe` = a quem ele responde.
    static func instrucaoDaSessao(_ h: Homie, time: [Homie] = [], chefe: Homie? = nil) -> String {
        var linhas = ["Você é \(h.nome), um Homie do Crew de \(Usuario.nome)."]
        let f = h.funcao.trimmingCharacters(in: .whitespacesAndNewlines)
        if !f.isEmpty { linhas.append("Função: \(f)") }
        let i = h.instrucao.trimmingCharacters(in: .whitespacesAndNewlines)
        if !i.isEmpty { linhas.append(i) }
        linhas.append("A sua pasta é a pasta desta sessão: o que você precisa lembrar entre conversas fica nela.")
        if let chefe { linhas.append("Você faz parte do time de \(chefe.nome): ele pode te passar trabalho e juntar o seu resultado ao dos outros.") }
        if !time.isEmpty { linhas.append(instrucaoDoTime(time)) }
        return linhas.joined(separator: "\n")
    }

    /// Como o Homie que coordena usa o time: cada membro é um subagente que trabalha a partir da
    /// própria pasta. Só o coordenador fala com o Hugo.
    static func instrucaoDoTime(_ time: [Homie]) -> String {
        var l = ["", "Você coordena um time. Quem responde a você:"]
        for m in time {
            let f = m.funcao.trimmingCharacters(in: .whitespacesAndNewlines)
            l.append("- \(m.nome)\(f.isEmpty ? "" : " — \(f)") — pasta: \(m.pasta)")
        }
        l.append("""
            Como usar o time:
            - Quando o pedido tocar a área de um deles, passe a parte dele pela ferramenta Agent (um subagente por Homie; em paralelo quando as partes não dependem uma da outra). No pedido ao subagente diga: que ele é aquele Homie, que deve ler primeiro o `CLAUDE.md` e as `notas/` da pasta dele, a tarefa, e o resultado que você espera.
            - Peça a resposta em três linhas: Situação (feito, parcial ou travado), Resultado, Evidência (de onde tirou).
            - Você continua dono do pedido: junte os resultados, confira o que não fecha e responda a \(Usuario.nome) numa voz só, dizendo quem levantou o quê.
            - O que for pequeno ou for da sua própria função, faça você mesmo. Não passe trabalho só para ter passado.
            - Nenhum deles age fora do Mac nem faz o que não tem volta sem o sim de \(Usuario.nome); isso vale para o que você passar a eles.
            """)
        return l.joined(separator: "\n")
    }

    /// Quem responde a `id`, direto ou por meio de outro (o time inteiro abaixo dele).
    static func time(de id: UUID, em homies: [Homie]) -> [Homie] {
        var out: [Homie] = []
        var vistos: Set<UUID> = [id]
        var fila = [id]
        while !fila.isEmpty {
            let atual = fila.removeFirst()
            for h in homies where h.chefe == atual && !vistos.contains(h.id) {
                vistos.insert(h.id); out.append(h); fila.append(h.id)
            }
        }
        return out
    }

    /// `chefe` pode coordenar `id`? Não pode ser ele mesmo nem alguém que já responde a ele
    /// (senão fecha um círculo).
    static func podeCoordenar(_ chefe: UUID, a id: UUID, em homies: [Homie]) -> Bool {
        chefe != id && !time(de: id, em: homies).contains { $0.id == chefe }
    }

    /// A equipe na ordem da tela: cada coordenador seguido de quem responde a ele, com o recuo.
    /// Chefe que não existe mais (ou círculo no arquivo) = aparece no primeiro nível.
    static func equipe(_ homies: [Homie]) -> [(homie: Homie, nivel: Int)] {
        let ids = Set(homies.map(\.id))
        var out: [(homie: Homie, nivel: Int)] = []
        var postos = Set<UUID>()
        func por(_ h: Homie, _ nivel: Int) {
            guard !postos.contains(h.id) else { return }
            postos.insert(h.id); out.append((h, nivel))
            for m in homies where m.chefe == h.id { por(m, min(nivel + 1, 3)) }
        }
        for h in homies where h.chefe == nil || !ids.contains(h.chefe!) { por(h, 0) }
        for h in homies { por(h, 0) }
        return out
    }

    // MARK: Rotinas

    /// Quantas ações uma página pode propor.
    static let maxAcoes = 6

    /// Onde a rotina escreve a página, a partir da pasta do Homie.
    static func arquivoDaPagina(_ rotina: UUID) -> String { "paginas/\(rotina.uuidString.lowercased()).json" }

    /// O pedido com que a sessão de uma rotina abre: o que o Hugo configurou, e como entregar.
    /// Ninguém responde durante a execução, então ela não pergunta: propõe e termina.
    static func pedidoDaRotina(nome: String, entrega: String, rotina: UUID, quando: String, comTime: Bool) -> String {
        """
        Rode agora a rotina "\(nome)" (\(quando)). Ninguém responde durante esta execução: não pergunte nada, faça tudo de uma vez e termine.

        --- o que \(Usuario.nome) quer receber ---
        \(entrega.trimmingCharacters(in: .whitespacesAndNewlines))
        --- fim ---

        Como entregar: escreva o arquivo `\(arquivoDaPagina(rotina))` na sua pasta (substitua o que houver), em JSON válido, exatamente neste formato:
        {"titulo": "título curto da página", "resumo": "a página em markdown, curta, o que \(Usuario.nome) lê em um minuto", "acoes": [{"titulo": "o movimento numa frase", "pedido": "o pedido completo, com todo o contexto, que quem for fazer recebe se \(Usuario.nome) aprovar", "quem": "nome do Homie que deve fazer, ou vazio se for você"}], "semNovidade": false}

        Regras desta execução:
        - Só leia. O único arquivo que você escreve é essa página (e, se precisar lembrar de algo, notas em `notas/`).
        - Não execute nenhuma ação: proponha em `acoes`, no máximo \(maxAcoes), em ordem de importância. Cada uma só acontece se \(Usuario.nome) clicar.
        - Não invente número, nome nem data. O que não deu para levantar, diga na página que não deu e por quê.
        - Se não houver nada novo a dizer, escreva a página com "semNovidade": true e um resumo de uma linha.\(comTime ? "\n- Use o seu time para levantar cada parte e diga na página quem levantou o quê." : "")
        - Sua última mensagem é uma linha dizendo que a página está pronta.
        """
    }

    /// O CLAUDE.md que nasce na pasta do Homie. Escrito uma vez; depois é dele e do Hugo.
    static func guia(_ h: Homie) -> String {
        """
        # \(h.nome)

        \(h.funcao.isEmpty ? "Homie do Crew de \(Usuario.nome)." : h.funcao)

        Esta pasta é sua. O Crew abre as conversas com você aqui.

        ## Como trabalhar

        - Português, direto, sem enrolar. Entregue pronto.
        - Não invente número, nome nem data: levante antes de afirmar.
        - O que for para lembrar depois (preferências de \(Usuario.nome), pendências, decisões) vai para a
          sua memória ou para `notas/` nesta pasta.
        - Antes de qualquer coisa que saia do Mac ou não tenha volta (enviar mensagem, apagar,
          pagar, publicar), diga o que vai fazer e espere o sim de \(Usuario.nome).
        - Ferramenta ligada a um projeto específico só se usa quando \(Usuario.nome) pedir aquele projeto.

        ## O que é seu

        - `CLAUDE.md` — este guia. Pode ser editado.
        - `.mcp.json` — os servidores MCP só seus.
        - `.claude/skills/` — as suas skills.
        - `notas/` — o que você guarda.
        """
    }

    static let modelosAceitos: Set<String> = ["fable", "opus", "sonnet", "haiku"]

    /// Aplica a ficha da pasta ao Homie. Só entra o que veio preenchido e válido; nome vazio e
    /// modelo desconhecido são ignorados. Devolve o Homie como fica (igual = nada mudou).
    static func aplicar(_ f: FichaHomie, a h: Homie) -> Homie {
        var n = h
        if let v = f.nome?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty { n.nome = String(v.prefix(40)) }
        if let v = f.funcao?.trimmingCharacters(in: .whitespacesAndNewlines) { n.funcao = String(v.prefix(120)) }
        if let v = f.instrucao?.trimmingCharacters(in: .whitespacesAndNewlines) { n.instrucao = String(v.prefix(2000)) }
        if let v = f.modelo?.lowercased(), modelosAceitos.contains(v) { n.modelo = v }
        if f.pronto == true { n.emConstrucao = false }
        return n
    }

    /// O pedido que abre a montagem: o briefing do Hugo, como ele falou.
    static func pedidoDeMontagem(briefing: String, nome: String) -> String {
        let n = nome.trimmingCharacters(in: .whitespacesAndNewlines)
        return (n.isEmpty ? "" : "Nome que eu quero para ele: \(n)\n\n") + "Briefing do Homie novo:\n\n" + briefing
    }

    /// O que a conversa de montagem recebe além das instruções do Claude Code: nela o Claude Code
    /// não é o Homie, é quem monta o Homie com o Hugo, dentro da pasta dele.
    static var instrucaoDeMontagem: String { """
        Você é o montador de Homies do Crew, o app de \(Usuario.nome). Nesta conversa você NÃO é o Homie: você constrói um Homie novo junto com \(Usuario.nome), na pasta desta sessão. Um Homie é um colega de trabalho com função fixa, que \(Usuario.nome) chama pelo Crew; cada conversa com ele é uma sessão do Claude Code aberta nesta pasta, então tudo o que você escrever aqui (guia, skills, MCPs, notas) é o que ele vai ser.

        Como conduzir:
        1. A primeira mensagem é o briefing de \(Usuario.nome), do jeito que ele falou. Entenda o que ele quer que o Homie faça por ele.
        2. Pergunte só o que muda a construção, de uma vez, no máximo cinco perguntas curtas: o que ele faz no dia a dia e o que entrega; com que contas, sistemas e arquivos trabalha; o que nunca pode fazer sem pedir; como deve falar; o que precisa lembrar entre conversas. O que o briefing já respondeu, não pergunte.
        3. Proponha em poucas linhas, antes de escrever qualquer arquivo: nome, função em uma frase, o que ele sabe fazer (as skills), que ferramentas usa (os MCPs) e os limites. Espere o sim de \(Usuario.nome).
        4. Construa, só dentro desta pasta:
           - `CLAUDE.md`: quem ele é, a função, como trabalha, o que entrega, os limites e onde guarda o que precisa lembrar (`notas/`). Em português, direto, sem enrolar.
           - `.claude/skills/<nome-da-skill>/SKILL.md` para cada tarefa que ele vai repetir, com `name` e `description` no cabeçalho e o passo a passo no corpo. Só as que o briefing pede; não invente skill para encher.
           - `.mcp.json` só com os servidores que \(Usuario.nome) confirmou. Credencial sempre por variável de ambiente (`${NOME_DA_VARIAVEL}`), nunca escrita no arquivo; se faltar um segredo, diga qual variável ele precisa definir e não peça o valor na conversa.
           - `notas/contexto.md` com o contexto que \(Usuario.nome) deu: pessoas, sistemas, preferências, o que ele explicou.
           - `homie.json`, por último: `{"nome": "...", "funcao": "uma frase", "instrucao": "2 a 5 frases de como ele trabalha", "modelo": null, "pronto": true}`. `modelo` é `null` (o padrão) ou `"fable"`, `"opus"`, `"sonnet"`, `"haiku"`. É por este arquivo que o Crew atualiza o cartão do Homie; escreva-o de novo sempre que nome, função ou instrução mudarem.
        5. Termine listando o que criou e dizendo a \(Usuario.nome) para clicar em "Nova conversa" para falar com o Homie pronto. Se ele pedir ajuste depois, ajuste os arquivos nesta mesma conversa.

        Regras:
        - Trabalhe só dentro desta pasta. Não mexa em `~/.claude/settings.json`, em configuração global nem em pasta de outro projeto.
        - Projetos de \(Usuario.nome) são mundos separados: não traga dado, credencial nem ferramenta de um projeto para o Homie, a não ser que \(Usuario.nome) peça aquele projeto pelo nome. Ferramenta de projeto que você enxergar nesta sessão não entra no Homie por conta própria.
        - O Homie nunca age fora do Mac nem faz o que não tem volta (enviar, apagar, pagar, publicar) sem o sim de \(Usuario.nome): escreva isso no guia dele.
        - Não invente conta, sistema, número ou nome: o que você não sabe, pergunte.
        - Sem emoji.
        """ }

    /// O primeiro Homie: o assistente pessoal.
    static var assistente: Homie {
        Homie(nome: "Homie",
              funcao: "Assistente pessoal de \(Usuario.nome)",
              instrucao: "Ajude \(Usuario.nome) com o dia dele: lembrar, organizar, pesquisar, redigir e conferir. Quando o pedido for vago, faça a leitura mais útil e diga qual foi.")
    }
}
