import SwiftUI
import AppKit

@main
struct NotchBuddyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        Settings {
            // A janela que o macOS abre no ⌘, quando o SwiftUI é dono do menu: os Ajustes inteiros
            // (barra lateral e páginas), iguais aos da JanelaAjustes — nunca só a página "Crew".
            CentralView().frame(minWidth: 860, idealWidth: 1000, minHeight: 560, idealHeight: 700)
        }
    }
}
