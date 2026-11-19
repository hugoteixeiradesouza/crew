import Foundation

// Rotina = um pedido guardado que abre uma sessão do Claude Code num projeto, pela agenda ou à mão.

/// Uma tentativa de rodar (abriu sessão, falhou ou foi pulada).
struct ExecucaoRotina: Codable, Identifiable, Equatable, Sendable {
    enum Origem: String, Codable, Sendable {
        /// Pela agenda, na hora.
        case agenda
        /// Pela agenda, atrasada (recuperação de execução perdida).
        case recuperada
        /// Clique do Hugo em "Rodar agora".
        case manual

        var texto: String {
            switch self {
            case .agenda: return "agenda"
            case .recuperada: return "recuperada"
            case .manual: return "à mão"
            }
        }
    }

    var id = UUID()
    var quando: Date
    var origem: Origem
    /// session_id do Claude Code, quando a sessão abriu.
    var sessao: String?
    var ok: Bool
    /// Por que não rodou (quando `ok` é false).
    var motivo: String?
}

struct Rotina: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var nome = ""
    /// Pasta do projeto onde a sessão abre.
    var pasta = ""
    /// O pedido (prompt) com que a sessão começa.
    var pedido = ""
    /// nil = o padrão do CLI; senão `fable`, `opus`, `sonnet`, `haiku`.
    var modelo: String?
    /// Modo de permissão: nil = o padrão do CLI; senão `acceptEdits`, `plan`, `auto`.
    var modo: String?
    var agenda = AgendaRotina.manual
    /// Roda sozinha pela agenda? Só o Hugo liga (chave na lista, com a confirmação da primeira vez).
    var ligada = false
    /// Perdeu a hora (Mac dormindo, Crew fechado): roda uma vez ao voltar? Padrão: não.
    var recuperarPerdida = false
    /// Última vez que abriu sessão.
    var ultimaExecucao: Date?
    var proximaExecucao: Date?
    /// As últimas tentativas, da mais nova para a mais velha (até `PoliticaRotinas.maxHistorico`).
    var historico: [ExecucaoRotina] = []
    var criadaEm = Date()
    /// Rotina de um Homie: a sessão abre na pasta dele, com a identidade dele, só lendo, e entrega
    /// uma página na tela dele (ver `HomiesServico`). nil = rotina de projeto.
    var homie: UUID?
    /// Rotina de Homie: enxerga os MCPs da pasta dele (`.mcp.json`)? nil/false = nenhum MCP.
    var comMcps: Bool?

    var nomeProjeto: String { URL(fileURLWithPath: pasta).lastPathComponent }

    /// Dá para salvar?
    var completa: Bool {
        !nome.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !pasta.isEmpty
            && !pedido.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && agenda.valida
    }
}

/// O que vai para `rotinas.json`.
struct ArquivoRotinas: Codable {
    var versao = 1
    var rotinas: [Rotina] = []
}
