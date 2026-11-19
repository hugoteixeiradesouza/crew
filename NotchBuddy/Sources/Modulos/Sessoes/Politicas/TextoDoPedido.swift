import Foundation

// O texto de uma fala do Hugo como o Claude Code grava no transcript → o texto que ele digitou.
// O transcript embrulha coisas em marcas: texto colado vem dentro de <pasted_content id="…">,
// comando de barra vem como <command-name>/x</command-name>, e o que é do sistema (lembretes,
// avisos de tarefa, saída de comando local) vem em marcas próprias. Antes, qualquer fala que
// começasse com "<" era jogada fora inteira — e uma mensagem com texto colado começa assim.
// Regra pura (só Foundation): compila sozinha no teste de `testes/conversa/`.

enum TextoDoPedido {
    /// Marcas cujo conteúdo é do sistema, nunca fala do Hugo: saem com tudo o que têm dentro.
    private static let ruido = [
        "system-reminder", "local-command-caveat", "local-command-stdout", "local-command-stderr",
        "task-notification", "tools-used-before-summary", "bash-stdout", "bash-stderr",
        "command-message", "user-prompt-submit-hook", "agent-message", "cross-session-message",
        "ide_opened_file", "ide_selection", "ide_diagnostics",
    ]

    /// Marcas que só embrulham o que o Hugo escreveu ou colou: sai a marca, fica o conteúdo.
    private static let embrulho = ["pasted_content", "pasted-content", "pasted_text", "pasted-text", "user-input"]

    /// O texto que o Hugo mandou, sem as marcas. Vazio = não há fala dele ali (só ruído).
    /// `humano`: o transcript diz que a linha veio do teclado dele (`origin.kind == "human"`);
    /// sem essa certeza, um texto que é só um bloco de marca desconhecida é tratado como ruído.
    static func limpar(_ bruto: String, humano: Bool = false) -> String {
        var t = bruto
        guard t.contains("<") else { return aparar(t) }

        // Comando de barra: "/model opus", como aparece no terminal.
        if let nome = conteudo(de: "command-name", em: t) {
            let args = conteudo(de: "command-args", em: t) ?? ""
            let comando = (nome.hasPrefix("/") ? nome : "/" + nome) + (args.isEmpty ? "" : " " + args)
            t = removerBloco("command-name", de: t)
            t = removerBloco("command-args", de: t)
            t = comando + "\n" + t
        }
        // Comando de shell digitado com "!": mostra o comando, não a saída.
        if let comando = conteudo(de: "bash-input", em: t) {
            t = removerBloco("bash-input", de: t)
            t = "! " + comando + "\n" + t
        }
        for marca in ruido { t = removerBloco(marca, de: t) }
        for marca in embrulho { t = removerMarca(marca, de: t) }
        t = aparar(t)
        // O que sobrou é um bloco só de uma marca que não conhecemos (<algo>…</algo>): recado de
        // sistema de um tipo novo. Só vale quando não há certeza de que veio do teclado do Hugo
        // (ele pode colar HTML).
        if !humano, t.hasPrefix("<"), ehBlocoUnico(t) { return "" }
        return t
    }

    /// Marcas em que o Claude Code grava o retorno de um comando rodado pelo Hugo (`/model`,
    /// `/context`, `! ls`…).
    private static let saidas = ["local-command-stdout", "local-command-stderr", "bash-stdout", "bash-stderr"]

    /// O retorno de um comando, para aparecer na conversa logo depois dele. nil = a linha não é
    /// retorno de comando, ou veio vazio. Linha que traz o próprio comando não conta: ela é a
    /// fala do Hugo.
    static func saidaDeComando(_ bruto: String) -> String? {
        guard saidas.contains(where: { bruto.contains("<" + $0) }),
              !bruto.contains("<command-name"), !bruto.contains("<bash-input") else { return nil }
        var partes: [String] = []
        for marca in saidas {
            let m = NSRegularExpression.escapedPattern(for: marca)
            guard let re = regex("<\(m)(?:\\s[^>]*)?>(.*?)</\(m)(?:\\s[^>]*)?>") else { continue }
            for achado in re.matches(in: bruto, range: NSRange(bruto.startIndex..., in: bruto)) {
                guard let faixa = Range(achado.range(at: 1), in: bruto) else { continue }
                partes.append(String(bruto[faixa]))
            }
        }
        var t = partes.joined(separator: "\n")
        // Cores do terminal não são texto.
        if let cores = regex("\u{1B}\\[[0-9;?]*[A-Za-z]") {
            t = cores.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t), withTemplate: "")
        }
        t = aparar(t)
        return t.isEmpty || t == "(no content)" ? nil : t
    }

    /// Aviso do Claude Code de que o Hugo interrompeu (não é fala dele).
    static func ehInterrupcao(_ texto: String) -> Bool {
        aparar(texto).hasPrefix("[Request interrupted by user")
    }

    private static func aparar(_ s: String) -> String {
        // Colagem deixa linhas em branco sobrando nas pontas e em volta do que foi tirado.
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        while t.contains("\n\n\n") { t = t.replacingOccurrences(of: "\n\n\n", with: "\n\n") }
        return t
    }

    private static func regex(_ padrao: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: padrao, options: [.dotMatchesLineSeparators])
    }

    /// O que está dentro de <marca>…</marca> (a primeira).
    private static func conteudo(de marca: String, em t: String) -> String? {
        let m = NSRegularExpression.escapedPattern(for: marca)
        guard let re = regex("<\(m)(?:\\s[^>]*)?>(.*?)</\(m)(?:\\s[^>]*)?>"),
              let achado = re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)),
              let faixa = Range(achado.range(at: 1), in: t) else { return nil }
        return String(t[faixa]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Tira <marca>…</marca> com o conteúdo (todas as vezes).
    private static func removerBloco(_ marca: String, de t: String) -> String {
        guard t.contains("<" + marca) else { return t }
        let m = NSRegularExpression.escapedPattern(for: marca)
        guard let re = regex("<\(m)(?:\\s[^>]*)?>.*?</\(m)(?:\\s[^>]*)?>") else { return t }
        return re.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t), withTemplate: "")
    }

    /// Tira só as marcas de abrir e fechar (o fechamento pode repetir o id: </pasted_content id="1">).
    private static func removerMarca(_ marca: String, de t: String) -> String {
        guard t.contains("<" + marca) || t.contains("</" + marca) else { return t }
        let m = NSRegularExpression.escapedPattern(for: marca)
        guard let re = regex("</?\(m)(?:\\s[^>]*)?>\\n?") else { return t }
        return re.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t), withTemplate: "")
    }

    /// O texto inteiro é um <algo …>…</algo>?
    private static func ehBlocoUnico(_ t: String) -> Bool {
        guard let re = regex("^<([A-Za-z_][\\w-]*)(?:\\s[^>]*)?>.*</\\1(?:\\s[^>]*)?>$") else { return false }
        return re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) != nil
    }
}
