import AppKit

// O que o comando universal mostra: uma linha de resultado, de qualquer fonte, sempre no mesmo
// formato. Quem decide o que entra e em que ordem é o ComandoServico; a tela só desenha.

/// O desenho à esquerda da linha.
enum IconeComando: Equatable {
    /// SF Symbol.
    case simbolo(String)
    /// O ícone que o Finder mostra para o caminho (app, arquivo, pasta).
    case arquivo(String)
    /// Bolinha com a cor do projeto ou da sessão (hex).
    case cor(String)
}

/// Os blocos da lista, em ordem fixa. É a ordem fixa que deixa os arquivos (que chegam depois)
/// entrarem sem tirar do lugar o que já estava na tela.
enum GrupoComando: Int, CaseIterable {
    /// Resposta direta ao que foi digitado: a conta, a tradução, o endereço.
    case resposta
    /// Apps, o Crew (sessões, projetos, ações, páginas), ajustes do sistema, abas do navegador.
    case melhores
    /// Arquivos e pastas do índice do macOS.
    case arquivos
    /// Pesquisar na web e perguntar ao Claude Code: sempre por último, sempre escolha dele.
    case adiante

    var titulo: String? {
        switch self {
        case .resposta: nil
        case .melhores: nil
        case .arquivos: "Arquivos"
        case .adiante: nil
        }
    }
}

@MainActor
struct ResultadoComando: Identifiable {
    /// Estável entre aberturas (é a chave do aprendizado): "app:/Applications/Safari.app".
    let id: String
    var titulo: String
    var subtitulo = ""
    var icone: IconeComando
    /// O que é, em uma palavra, à direita da linha: "App", "Sessão", "Ação"…
    var tipo: String
    var grupo: GrupoComando = .melhores
    var pontos = 0.0
    /// Resultado em destaque (o valor da conta, o texto traduzido): linha mais alta.
    var destaque: String?
    /// O que o Enter faz, em uma palavra ("Abrir", "Copiar").
    var rotuloEnter = "Abrir"
    /// O que o ⌘Enter faz (nil = não tem ação secundária).
    var rotuloSecundario: String?
    /// Entra no aprendizado (o que ele escolhe sobe)? Resposta de conta não entra.
    var aprende = true
    /// Linha que só informa (ex.: "traduzindo…"): Enter não faz nada.
    var inerte = false
    var acao: @MainActor () -> Void = {}
    var secundaria: (@MainActor () -> Void)?
}

extension NSPasteboard {
    /// Põe um texto na área de transferência (substitui o que estava).
    @MainActor
    static func copiar(_ texto: String) {
        general.clearContents()
        general.setString(texto, forType: .string)
    }
}
