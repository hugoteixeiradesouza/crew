import SwiftUI

// Brilho e volume do sistema na ilha (teclas interceptadas, Homie de celular ou fones).

@MainActor
final class NivelModulo: Modulo {
    static let shared = NivelModulo()

    let id = "nivel"
    let nome = "Brilho e volume"
    let icone = "sun.max"
    let pilar = Pilar.mac
    let superficies: [Superficie] = [.ilha]
    let resumo = "Ao mudar o brilho ou o volume, a ilha mostra o nível e o Homie reage. Cada um liga e desliga aqui."
    var podeDesligar: Bool { false }

    func ajustes() -> AnyView? { AnyView(NivelAjustes()) }
}

struct NivelAjustes: View {
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var nivel = NivelService.shared

    var body: some View {
        LinhaModulo(icone: "sun.max.fill", titulo: "Brilho na ilha",
                    detalhe: "Ao mudar o brilho, a ilha mostra o nível e o \(state.nomeDoPersonagem) segura um celular que acende junto. O brilho automático (sensor de luz) não aparece.",
                    ligado: $state.moduloBrilho)
        Divider()
        LinhaModulo(icone: "speaker.wave.2.fill", titulo: "Volume na ilha",
                    detalhe: "Ao mudar o volume, a ilha mostra o nível e o \(state.nomeDoPersonagem) põe os fones e reage ao som.",
                    ligado: $state.moduloVolume)
        if state.moduloBrilho || state.moduloVolume {
            Divider()
            LinhaModulo(icone: "rectangle.on.rectangle.slash", titulo: "Só o aviso do Crew",
                        detalhe: "As teclas de brilho e volume passam pelo Crew: ele muda o brilho e o volume do Mac e o aviso do macOS não aparece.",
                        ligado: $state.moduloAvisoProprio)
            if state.moduloAvisoProprio && nivel.semPermissaoTeclas {
                HStack(spacing: 8) {
                    Text("Precisa da permissão de Acessibilidade para receber as teclas.")
                        .font(.system(size: 11)).foregroundColor(.orange)
                    Button("Dar permissão") { NivelService.shared.pedirPermissaoTeclas() }
                        .controlSize(.small)
                }
                .padding(.leading, 34)
            }
        }
    }
}
