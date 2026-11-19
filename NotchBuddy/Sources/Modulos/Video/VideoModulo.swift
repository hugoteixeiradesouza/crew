import SwiftUI

// Vídeo: vídeos escritos em código (React + Remotion), criados e editados pelas sessões do
// Claude Code e renderizados por um motor que roda ao lado do Crew.

@MainActor
final class VideoModulo: Modulo {
    static let shared = VideoModulo()

    let id = VideoServico.modulo
    let nome = "Vídeo"
    let icone = "film"
    let pilar = Pilar.criar
    let superficies: [Superficie] = [.ilha, .app, .claude]
    let resumo = "Vídeos feitos em código com o Remotion: você descreve, o Claude Code escreve o vídeo, o Crew mostra a prévia e renderiza. O motor roda ao lado do Crew, só quando você usa, e tudo fica neste Mac."

    func iniciar() { VideoServico.shared.atualizar() }
    func parar() { VideoServico.shared.parar() }

    func central() -> AnyView? { AnyView(VideoCentral()) }

    /// `crew://video/previa?projeto=<nome>` abre a prévia; `crew://video/fechar` fecha.
    func executar(_ acao: String, _ parametros: [String: String]) -> Bool {
        switch acao {
        case "previa":
            guard let p = parametros["projeto"], !p.isEmpty else { return false }
            VideoServico.shared.abrirPrevia(p)
            return true
        case "fechar":
            VideoServico.shared.fecharPrevia()
            return true
        default:
            return false
        }
    }
}
