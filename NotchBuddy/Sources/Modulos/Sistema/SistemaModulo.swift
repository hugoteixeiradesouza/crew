import SwiftUI

@MainActor
final class SistemaModulo: Modulo {
    static let shared = SistemaModulo()

    let id = "sistema"
    let nome = "Sistema"
    let icone = "gauge.with.dots.needle.33percent"
    let pilar = Pilar.mac
    let superficies: [Superficie] = [.ilha, .claude]
    let resumo = "CPU, memória, temperatura, rede, disco e bateria. Só lê enquanto alguma tela está olhando."
    var temAba: Bool { true }
    var temBloco: Bool { true }
    var blocoPorPadrao: Bool { true }
    func bloco() -> AnyView { AnyView(SistemaBloco()) }

    func iniciar() {
        if Ajustes.bool(id, "avisos", padrao: true) { SistemaAlertas.shared.ligar() }
        SistemaIndicador.aplicar()
    }

    func parar() {
        SistemaAlertas.shared.desligar()
        SistemaIndicador.aplicar(ligado: false)
    }

    var alturaExpandida: CGFloat? { SistemaAba.alturaMonitor }
    func aba() -> AnyView { AnyView(SistemaAba()) }
    func central() -> AnyView? { AnyView(SistemaCentral()) }
    func ajustes() -> AnyView? { AnyView(SistemaAjustes()) }

    /// crew://sistema/indicador?tipo=cpu|memoria|temperatura|nenhum
    /// crew://sistema/monitor — abre a ilha já com o monitor de atividade expandido
    func executar(_ acao: String, _ parametros: [String: String]) -> Bool {
        if acao == "monitor" {
            NotificationCenter.default.post(name: .abrirIlha, object: id)
            // A ilha abre com mola; o pedido de altura vale com a aba na frente
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                MainActor.assumeIsolated { self.pedirAlturaAba(SistemaAba.alturaMonitor) }
            }
            return true
        }
        guard acao == "indicador", let t = IndicadorSistema(rawValue: parametros["tipo"] ?? "") else { return false }
        IndicadorSistema.atual = t
        SistemaIndicador.aplicar()
        return true
    }
}
