import SwiftUI

@MainActor
final class CapturaModulo: Modulo {
    static let shared = CapturaModulo()

    let id = CapturaServico.modulo
    let nome = "Captura"
    let icone = "camera.viewfinder"
    let pilar = Pilar.criar
    /// Na ilha por causa da gravação: enquanto grava, a barra mostra o tempo e o botão de parar.
    let superficies: [Superficie] = [.ilha, .atalho, .claude]
    let resumo = "Captura e gravação de tela por atalho. Foto: área, janela, tela inteira e texto da tela (vai direto para a área de transferência). Vídeo: tela, janela ou área, com microfone, som do Mac e a bolha da câmera; o mesmo atalho começa e para, e a ilha mostra o tempo. A prévia flutua no canto para copiar, anotar, arrastar ou mandar para a sessão em foco. Tudo fica neste Mac."

    func iniciar() {
        CapturaServico.shared.iniciar()
        GravacaoServico.shared.iniciar()
    }

    func parar() {
        GravacaoServico.shared.parar()
        CapturaServico.shared.parar()
    }

    func central() -> AnyView? { AnyView(CapturaCentral()) }
    func ajustes() -> AnyView? { AnyView(CapturaAjustes()) }

    /// `crew://captura/area|janela|tela|texto` — o mesmo que apertar o atalho. Não apaga nada.
    /// `crew://captura/gravar` (`?alvo=tela|janela|area`; sem alvo, o dos ajustes) começa a gravar
    /// se está parado; `crew://captura/parar` para e guarda.
    func executar(_ acao: String, _ parametros: [String: String]) -> Bool {
        let g = GravacaoServico.shared
        switch acao {
        case "gravar":
            if !g.ocupado { g.comecar(parametros["alvo"].flatMap(AlvoGravacao.init(rawValue:)) ?? g.alvoPadrao) }
            return true
        case "parar":
            if g.gravando { g.pararGravacao() } else { g.cancelar() }
            return true
        default: break
        }
        guard let modo = ModoCaptura(rawValue: acao) else { return false }
        CapturaServico.shared.capturar(modo)
        return true
    }
}
