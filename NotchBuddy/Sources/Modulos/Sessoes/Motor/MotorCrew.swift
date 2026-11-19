import Foundation
import AppKit

// Motor próprio do Crew: abre o Claude Code pelo CLI, sem depender de outro app.
// Cada sessão é um tmux `crew-<session_id>` rodando `claude --session-id <id>` na pasta do
// projeto. Os hooks (nb-hook) avisam o Crew como em qualquer sessão; a conversa vem do
// transcript; falar com ela é `send-keys` no painel (TerminalBridge já acha pelo tty).
// O tmux é o servidor padrão do Hugo: a sessão continua viva com o Crew fechado e dá para
// entrar nela de qualquer terminal (`tmux attach -t crew-<id>`).

enum MotorCrew {
    struct Falha: Error { let mensagem: String }

    struct Opcoes: Sendable {
        /// Apelido ou id do modelo (`fable`, `opus`, `sonnet`, `haiku`…); nil = o padrão do CLI.
        var modelo: String? = nil
        /// `default`, `acceptEdits`, `plan`, `auto`…; nil = o padrão do CLI.
        var modo: String? = nil
        /// `low`, `medium`, `high`, `xhigh`, `max`; nil = o padrão do CLI.
        var esforco: String? = nil
        /// Instrução fixa do projeto: vai junto das instruções do Claude Code.
        var instrucao: String? = nil
        /// Nome da sessão (aparece no /resume e no título).
        var nome: String? = nil
        /// Pastas a mais que a sessão enxerga, além da dela (`--add-dir`).
        var pastasExtras: [String] = []
        /// Pastas em que a sessão não pode escrever: as ferramentas de edição são negadas lá
        /// dentro (`--disallowedTools "Edit(//pasta/**)"`). Ler continua valendo.
        var somenteLeitura: [String] = []
        /// Ferramentas negadas na sessão inteira, pelo nome do Claude Code ("Bash", "WebFetch").
        var negadas: [String] = []
        /// Que servidores MCP a sessão enxerga.
        var mcp: Mcp = .padrao

        enum Mcp: Sendable, Equatable {
            /// Os de sempre (conta, usuário e projeto).
            case padrao
            /// Nenhum.
            case nenhum
            /// Só os deste arquivo (`.mcp.json`); arquivo que não existe = nenhum.
            case so(String)
        }
    }

    static let prefixo = "crew-"

    static var tmux: String? { TerminalBridge.tmuxPath }

    static var claude: String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["/opt/homebrew/bin/claude", home + "/.local/bin/claude", home + "/.claude/local/claude",
                "/usr/local/bin/claude"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static var disponivel: Bool { tmux != nil && claude != nil }

    /// Por que o motor não funciona neste Mac (nil = funciona).
    static var motivoIndisponivel: String? {
        if claude == nil { return "Claude Code (CLI) não encontrado." }
        if tmux == nil { return "tmux não encontrado (brew install tmux)." }
        return nil
    }

    static func nomeTmux(_ sessionId: String) -> String { prefixo + sessionId }
    private static func alvo(_ sessionId: String) -> String { "=" + nomeTmux(sessionId) }

    /// Abre uma sessão nova na pasta, já com o pedido. Devolve o session_id do Claude Code.
    static func nova(pasta: String, pedido: String, opcoes: Opcoes = Opcoes()) async -> Result<String, Falha> {
        let sid = UUID().uuidString.lowercased()
        var args = listas(opcoes) + ["--session-id", sid]
        if let n = opcoes.nome, !n.isEmpty { args += ["--name", n] }
        args += extras(opcoes)
        let texto = pedido.trimmingCharacters(in: .whitespacesAndNewlines)
        if !texto.isEmpty { args.append(texto) }
        return await subir(sid, pasta: pasta, args: args)
    }

    /// Retoma uma conversa guardada (mesmo session_id) numa sessão nova do tmux.
    static func retomar(sessionId: String, pasta: String, opcoes: Opcoes = Opcoes()) async -> Result<String, Falha> {
        if await ehDoCrew(sessionId) { return .success(sessionId) }
        return await subir(sessionId, pasta: pasta, args: listas(opcoes) + ["--resume", sessionId] + extras(opcoes))
    }

    /// As opções do CLI que aceitam vários valores. Vão sempre ANTES de uma opção de valor único
    /// (`--session-id`, `--resume`): no fim da linha elas engoliriam o pedido como mais um valor.
    private static func listas(_ o: Opcoes) -> [String] {
        var a: [String] = []
        let pastas = o.pastasExtras.filter { !$0.isEmpty }
        if !pastas.isEmpty { a += ["--add-dir"] + pastas }
        // Regra de caminho absoluto do Claude Code: "//" + caminho sem a barra inicial.
        let negadas = o.somenteLeitura.filter { $0.hasPrefix("/") }.map { "Edit(/\($0)/**)" } + o.negadas.filter { !$0.isEmpty }
        if !negadas.isEmpty { a += ["--disallowedTools"] + negadas }
        switch o.mcp {
        case .padrao: break
        case .nenhum: a += ["--strict-mcp-config"]
        case .so(let arquivo):
            // `--mcp-config` também aceita vários valores: fica aqui, antes das opções de valor único.
            if FileManager.default.fileExists(atPath: arquivo) { a += ["--mcp-config", arquivo] }
            a += ["--strict-mcp-config"]
        }
        return a
    }

    private static func extras(_ o: Opcoes) -> [String] {
        var a: [String] = []
        if let m = o.modelo, !m.isEmpty { a += ["--model", m] }
        if let m = o.modo, !m.isEmpty { a += ["--permission-mode", m] }
        if let e = o.esforco, !e.isEmpty { a += ["--effort", e] }
        if let i = o.instrucao?.trimmingCharacters(in: .whitespacesAndNewlines), !i.isEmpty { a += ["--append-system-prompt", i] }
        return a
    }

    private static func subir(_ sid: String, pasta: String, args: [String]) async -> Result<String, Falha> {
        guard let tmux, let claude else { return .failure(Falha(mensagem: motivoIndisponivel ?? "Motor indisponível.")) }
        var ehPasta: ObjCBool = false
        guard FileManager.default.fileExists(atPath: pasta, isDirectory: &ehPasta), ehPasta.boolValue else {
            return .failure(Falha(mensagem: "A pasta não existe: \(pasta)"))
        }
        // Shell de login: o Claude Code enxerga o mesmo PATH e ambiente do terminal do Hugo.
        // Com vários argumentos o tmux executa direto (sem sh -c): o pedido não passa por aspas.
        let comando = ["/bin/zsh", "-lic", "exec \"$0\" \"$@\"", claude] + args
        let r = await Processo.rodar(tmux, ["new-session", "-d", "-s", nomeTmux(sid), "-x", "120", "-y", "40",
                                            "-c", pasta, "-e", "CREW_SESSAO=1"] + comando, tempoMax: 15)
        guard r.ok else {
            let m = (r.erro.isEmpty ? r.saida : r.erro).trimmingCharacters(in: .whitespacesAndNewlines)
            return .failure(Falha(mensagem: m.isEmpty ? "O tmux não abriu a sessão." : m))
        }
        return .success(sid)
    }

    /// A sessão roda no motor do Crew (tmux `crew-<id>` de pé)?
    static func ehDoCrew(_ sessionId: String) async -> Bool {
        guard let tmux else { return false }
        return await Processo.rodar(tmux, ["has-session", "-t", alvo(sessionId)], tempoMax: 5).ok
    }

    /// session_ids das sessões de pé no motor do Crew.
    static func abertas() async -> [String] {
        guard let tmux else { return [] }
        let r = await Processo.rodar(tmux, ["list-sessions", "-F", "#{session_name}"], tempoMax: 5)
        guard r.ok else { return [] }
        return r.saida.split(separator: "\n").compactMap { $0.hasPrefix(prefixo) ? String($0.dropFirst(prefixo.count)) : nil }
    }

    /// Encerra o Claude Code da sessão (a conversa fica salva e dá para retomar). nil = ok.
    static func encerrar(_ sessionId: String) async -> String? {
        guard let tmux else { return "tmux não encontrado" }
        let r = await Processo.rodar(tmux, ["kill-session", "-t", alvo(sessionId)], tempoMax: 5)
        return r.ok ? nil : r.erro.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// O que está na tela do terminal da sessão agora (texto puro). Serve para o que os hooks
    /// não contam: "confia nesta pasta?", login, erro ao abrir.
    static func tela(_ sessionId: String) async -> String? {
        guard let tmux else { return nil }
        let r = await Processo.rodar(tmux, ["capture-pane", "-p", "-J", "-t", alvo(sessionId) + ":"], tempoMax: 5)
        return r.ok ? r.saida : nil
    }

    /// Aperta uma tecla no terminal da sessão (`Enter`, `Escape`, `Up`, `Down`, `1`, `y`…). nil = ok.
    static func tecla(_ sessionId: String, _ tecla: String) async -> String? {
        guard let tmux else { return "tmux não encontrado" }
        let r = await Processo.rodar(tmux, ["send-keys", "-t", alvo(sessionId) + ":", tecla], tempoMax: 5)
        return r.ok ? nil : r.erro.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Abre a sessão num terminal de verdade (Terminal da Apple), ligada ao mesmo tmux.
    static func abrirNoTerminal(_ sessionId: String) async {
        guard let tmux else { return }
        let cmd = "\(tmux) attach -t '\(nomeTmux(sessionId))'"
        let src = "tell application \"Terminal\"\nactivate\ndo script \"\(cmd)\"\nend tell"
        _ = await Processo.rodar("/usr/bin/osascript", ["-e", src], tempoMax: 10)
    }
}
