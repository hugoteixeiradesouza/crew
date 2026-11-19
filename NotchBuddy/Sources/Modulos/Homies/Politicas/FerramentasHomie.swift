import Foundation

// As ferramentas dos Homies: servidores MCP. Conecta-se uma vez, no módulo (numa pasta neutra
// do Crew, onde também acontece o login); em cada Homie o Hugo só ativa ou desativa o que quer,
// e ativar liga a mesma ferramenta só à pasta daquele Homie. O desenho é um
// catálogo de endereços ("conectar" grava o endereço e o login acontece no navegador). Aqui quem grava é o próprio Claude Code (`claude mcp add --scope
// local`), então a ferramenta vale só na pasta daquele Homie e não pede aprovação de projeto.
// Nenhuma credencial passa pelo Crew: o login é do Claude Code, no navegador.
// Só regra pura aqui (sem tela, sem processo), para a conferência em testes/homies.

struct FerramentaCatalogo: Identifiable, Equatable, Sendable {
    enum Servidor: Equatable, Sendable {
        case http(String)
        case comando(String, [String])
    }
    /// Como o Hugo entra: pelo navegador, sem nada, ou pelas permissões do macOS.
    enum Entrada: Equatable, Sendable { case navegador, nenhuma, mac }

    /// O nome do servidor MCP (é o que o Homie enxerga).
    let id: String
    let nome: String
    let resumo: String
    let icone: String
    let servidor: Servidor
    let entrada: Entrada
    var aviso: String? = nil
}

struct FerramentaLigada: Identifiable, Equatable, Sendable {
    enum Origem: Equatable, Sendable { case crew, pasta }
    let nome: String
    /// Endereço ou comando, para o Hugo reconhecer.
    let destino: String
    let http: Bool
    /// Como religar esta mesma ferramenta em outra pasta.
    let servidor: FerramentaCatalogo.Servidor
    /// `.crew` = ligada pela aba (dá para entrar e tirar); `.pasta` = escrita no `.mcp.json` dele.
    let origem: Origem
    var id: String { nome }
}

enum FerramentasHomie {
    /// Curto de propósito: apps do Mac, o que o Hugo usa no dia e os grandes da comunidade.
    /// Só entra aqui o que conecta sem chave digitada (login no navegador ou nada).
    static let catalogo: [FerramentaCatalogo] = [
        .init(id: "apps-do-mac", nome: "Apps do Mac", resumo: "Mail, Calendário, Contatos, Lembretes, Notas, Mensagens e Safari deste Mac",
              icone: "macbook", servidor: .comando("npx", ["-y", "mcp-icloud@2.1.4"]), entrada: .mac,
              aviso: "Servidor da comunidade (mcp-icloud), não é da Apple. Controla os apps por AppleScript, aqui no Mac; o macOS pede acesso a cada app no primeiro uso."),
        .init(id: "notion", nome: "Notion", resumo: "Páginas, busca e notas do seu workspace",
              icone: "doc.text", servidor: .http("https://mcp.notion.com/mcp"), entrada: .navegador),
        .init(id: "todoist", nome: "Todoist", resumo: "Tarefas, projetos e lembretes",
              icone: "checklist", servidor: .http("https://ai.todoist.net/mcp"), entrada: .navegador),
        .init(id: "linear", nome: "Linear", resumo: "Issues e triagem de projeto",
              icone: "line.3.horizontal.decrease.circle", servidor: .http("https://mcp.linear.app/mcp"), entrada: .navegador),
        .init(id: "trello", nome: "Trello", resumo: "Quadros, listas e cartões",
              icone: "rectangle.split.3x1", servidor: .http("https://mcp.trello.com/v1"), entrada: .navegador),
        .init(id: "clickup", nome: "ClickUp", resumo: "Tarefas, listas e documentos",
              icone: "square.stack.3d.up", servidor: .http("https://mcp.clickup.com/mcp"), entrada: .navegador),
        .init(id: "canva", nome: "Canva", resumo: "Designs, arquivos e exportações",
              icone: "paintpalette", servidor: .http("https://mcp.canva.com/mcp"), entrada: .navegador),
        .init(id: "supabase", nome: "Supabase", resumo: "Projetos, banco e funções",
              icone: "cylinder.split.1x2", servidor: .http("https://mcp.supabase.com/mcp"), entrada: .navegador),
        .init(id: "vercel", nome: "Vercel", resumo: "Projetos e deploys",
              icone: "triangle", servidor: .http("https://mcp.vercel.com"), entrada: .navegador),
        .init(id: "cloudflare", nome: "Cloudflare", resumo: "Workers, DNS e contas",
              icone: "cloud", servidor: .http("https://mcp.cloudflare.com/mcp"), entrada: .navegador),
        .init(id: "sentry", nome: "Sentry", resumo: "Erros e desempenho dos seus projetos",
              icone: "exclamationmark.triangle", servidor: .http("https://mcp.sentry.dev/mcp"), entrada: .navegador),
        .init(id: "context7", nome: "Context7", resumo: "Documentação atual de bibliotecas",
              icone: "books.vertical", servidor: .http("https://mcp.context7.com/mcp"), entrada: .nenhuma),
        .init(id: "zapier", nome: "Zapier", resumo: "Milhares de apps por uma conta Zapier",
              icone: "bolt", servidor: .http("https://mcp.zapier.com/api/v1/connect"), entrada: .navegador,
              aviso: "Serviço de terceiro: o que o Homie ler e escrever passa pela Zapier."),
        .init(id: "composio", nome: "Composio", resumo: "Gmail, Slack, GitHub e mais de mil apps por uma conta só",
              icone: "square.grid.3x3", servidor: .http("https://connect.composio.dev/mcp"), entrada: .navegador,
              aviso: "Serviço de terceiro: seus dados (e-mail, agenda) passam pela Composio. É o caminho mais rápido para muitas ferramentas de uma vez, não o mais reservado."),
    ]

    /// Nome de servidor aceito pelo Claude Code: minúsculas, números, hífen e sublinhado.
    /// Devolve o nome arrumado, ou nil se não sobra nada (ou é reservado).
    static func nome(_ bruto: String) -> String? {
        let limpo = bruto.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .folding(options: .diacriticInsensitive, locale: nil)
            .map { $0.isLetter && $0.isASCII || $0.isNumber || $0 == "_" ? $0 : "-" }
        let n = String(limpo).split(separator: "-").joined(separator: "-")
        guard !n.isEmpty, n.count <= 40, n != "crew" else { return nil }
        return n
    }

    /// Por que este endereço não serve (nil = serve). Só https, ou http neste Mac.
    static func erroDoEndereco(_ bruto: String) -> String? {
        let t = bruto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let u = URL(string: t), let esquema = u.scheme?.lowercased(), let host = u.host, !host.isEmpty else {
            return "Cole o endereço completo do servidor, começando por https://"
        }
        if esquema == "https" { return nil }
        if esquema == "http", ["127.0.0.1", "localhost", "::1"].contains(host) { return nil }
        return "Só https (ou http neste Mac, em 127.0.0.1)."
    }

    /// Os argumentos de `claude mcp` que ligam esta ferramenta só à pasta em que rodar.
    static func argumentosLigar(_ nome: String, _ servidor: FerramentaCatalogo.Servidor) -> [String] {
        switch servidor {
        case .http(let url): return ["mcp", "add", "--scope", "local", "--transport", "http", nome, url]
        case .comando(let c, let args): return ["mcp", "add", "--scope", "local", nome, "--", c] + args
        }
    }

    static func argumentosTirar(_ nome: String) -> [String] { ["mcp", "remove", nome, "--scope", "local"] }

    /// Os servidores de um bloco `mcpServers`, na forma que o Claude Code grava.
    private static func servidores(_ bloco: Any?) -> [String: [String: Any]] {
        (bloco as? [String: Any])?.compactMapValues { $0 as? [String: Any] } ?? [:]
    }

    /// O que o `~/.claude.json` guarda de ligado só a esta pasta.
    private static func locais(_ claudeJson: Data?, pastas: [String]) -> [String: [String: Any]] {
        guard let d = claudeJson, let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let projetos = j["projects"] as? [String: Any] else { return [:] }
        var tudo: [String: [String: Any]] = [:]
        for p in pastas {
            for (k, v) in servidores((projetos[p] as? [String: Any])?["mcpServers"]) { tudo[k] = v }
        }
        return tudo
    }

    private static func daPasta(_ mcpJson: Data?) -> [String: [String: Any]] {
        guard let d = mcpJson, let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return [:] }
        return servidores(j["mcpServers"])
    }

    private static func ligada(_ nome: String, _ c: [String: Any], _ origem: FerramentaLigada.Origem) -> FerramentaLigada {
        if let url = c["url"] as? String {
            return FerramentaLigada(nome: nome, destino: url, http: true, servidor: .http(url), origem: origem)
        }
        let comando = c["command"] as? String ?? "", args = c["args"] as? [String] ?? []
        return FerramentaLigada(nome: nome, destino: ([comando] + args).joined(separator: " "), http: false,
                                servidor: .comando(comando, args), origem: origem)
    }

    /// As ferramentas que o Homie enxerga: as ligadas pela aba e as do `.mcp.json` da pasta.
    /// `pastas` = o caminho dele como está e resolvido (o Claude Code guarda o resolvido).
    static func ligadas(claudeJson: Data?, mcpJson: Data?, pastas: [String]) -> [FerramentaLigada] {
        let l = locais(claudeJson, pastas: pastas)
        let p = daPasta(mcpJson).filter { l[$0.key] == nil }
        return (l.map { ligada($0.key, $0.value, .crew) } + p.map { ligada($0.key, $0.value, .pasta) })
            .sorted { $0.nome < $1.nome }
    }

    /// O arquivo de MCPs que a rotina recebe: os da pasta mais os ligados pela aba, e mais nenhum.
    /// nil = ele não tem ferramenta nenhuma.
    static func configDaRotina(claudeJson: Data?, mcpJson: Data?, pastas: [String]) -> Data? {
        var tudo = daPasta(mcpJson)
        for (k, v) in locais(claudeJson, pastas: pastas) { tudo[k] = v }
        guard !tudo.isEmpty else { return nil }
        return try? JSONSerialization.data(withJSONObject: ["mcpServers": tudo], options: [.prettyPrinted, .sortedKeys])
    }

    /// A linha "Status:" do `claude mcp get`, em palavras do Hugo.
    enum Situacao: Equatable, Sendable { case conectada, faltaEntrar, falhou(String) }

    static func situacao(_ saida: String) -> Situacao {
        let linha = saida.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("Status:") } ?? ""
        if linha.contains("Connected"), !linha.lowercased().contains("failed") { return .conectada }
        if linha.lowercased().contains("authentication") { return .faltaEntrar }
        let resto = linha.replacingOccurrences(of: "Status:", with: "").trimmingCharacters(in: .whitespaces)
        return .falhou(resto.isEmpty ? "o Claude Code não respondeu sobre ela" : resto)
    }
}
