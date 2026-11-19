import SwiftUI

// Soltar arquivos na ilha: anexar ao chat, mandar por e-mail, guardar.

@MainActor
final class ArquivosModulo: Modulo {
    static let shared = ArquivosModulo()

    let id = "arquivos"
    let nome = "Arquivos"
    let icone = "tray.and.arrow.down"
    let pilar = Pilar.mac
    let superficies: [Superficie] = [.ilha]
    let resumo = "Arraste um arquivo até a ilha: anexa no chat de uma sessão, manda por e-mail ou guarda."
    var podeDesligar: Bool { false }

    func ajustes() -> AnyView? { AnyView(ArquivosAjustes()) }
}

struct ArquivosAjustes: View {
    @ObservedObject private var state = AppState.shared

    var body: some View {
        LinhaModulo(icone: "paperclip", titulo: "Arquivos no chat",
                    detalhe: "Arrastar para a ilha ou Cmd+V com o chat aberto anexa na conversa.",
                    ligado: $state.moduloAnexosChat)
    }
}
