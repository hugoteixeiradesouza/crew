import SwiftUI

// "De qual projeto é o vídeo?" — a pergunta que o botão Editar de uma gravação faz antes de
// criar o projeto de vídeo. A sessão que edita nasce enxergando a pasta escolhida (só para
// ler) e tira dela o assunto, os nomes e a identidade visual. O sugerido é o projeto da sessão
// em foco; sem ela, o último em que o Hugo abriu sessão pelo Crew.

@MainActor
enum EscolhaProjetoVideo {
    static var sugerido: ProjetoCrew? {
        let p = ProjetosCrew.shared
        if let foco = p.projeto(de: AppState.shared.focusTask?.sessionCwd) { return foco }
        return p.ultimo.flatMap { u in p.lista.first { $0.caminho == u } }
    }

    /// Abre o menu onde o mouse está. Sem nenhum projeto no Crew, segue direto sem projeto.
    static func perguntar(_ escolher: @escaping @MainActor (ModeloEdicao.Contexto?) -> Void) {
        Task {
            await ProjetosCrew.shared.recarregar()
            guard !ProjetosCrew.shared.lista.isEmpty else { escolher(nil); return }
            MenuCrew.abrirNoMouse(itens(escolher))
        }
    }

    static func itens(_ escolher: @escaping @MainActor (ModeloEdicao.Contexto?) -> Void) -> [ItemMenu] {
        let primeiro = sugerido
        let resto = ProjetosCrew.shared.lista.filter { $0.caminho != primeiro?.caminho }
        func item(_ p: ProjetoCrew, marcado: Bool) -> ItemMenu {
            .acao(p.nome, ponto: Color(hex: p.cor), detalhe: p.caminhoCurto, marcado: marcado) {
                escolher(.init(nome: p.nome, caminho: p.caminho, cor: p.cor))
            }
        }
        var lista: [ItemMenu] = [.titulo("De qual projeto é o vídeo?")]
        if let primeiro { lista.append(item(primeiro, marcado: true)) }
        lista += resto.map { item($0, marcado: false) }
        lista.append(.divisor)
        lista.append(.acao("Nenhum projeto", icone: "minus.circle", detalhe: "Edita só pelo que a gravação mostra") { escolher(nil) })
        return lista
    }
}
