import AppKit

// Os atalhos de teclado do Crew, num lugar só. A regra: nenhum atalho depende da barra de
// menus — o SwiftUI troca a barra do Crew pela dele ("Crew, View, Window, Help") e tudo que
// morava no menu parava junto (⌘C, ⌘V, ⌘N…). Então cada tecla é resolvida pelo próprio app,
// nesta ordem, e a primeira camada que tratar fica com ela:
//
//  1. Navegador         com o cursor numa página ou no endereço: ⌘T ⌘W ⌘L ⌘R ⌘[ ⌘] ⌘F ⇧⌘C ⌃Tab
//                       (`NavegadorServico.tecla`, chamado pela camada 3).
//  2. Edição            ⌘C ⌘X ⌘V ⌘A ⌘Z ⇧⌘Z, entregues direto a quem está com o cursor: campo de
//                       texto, fala da conversa, página do navegador, terminal (`Atalhos.edicao`).
//                       ⌘V passa antes pelo campo do chat, que transforma arquivo/imagem em anexo.
//  3. Janela das sessões ⌘J ⌘N ⌘W ⌘G ⌥M ⌘←→↑↓ ⌃⌘←→ e Enter/Esc da confirmação (`AppCrewView.vigiarTeclas`).
//  4. Telas             atalhos de botão do SwiftUI: ⌘F (busca da barra lateral), ⌥⌘↑↓, ⌃⌘S.
//  5. Menu do Crew      o que sobrar e estiver no menu (⌘, ⌘Q ⌘H ⌘M… e ⌘1 … ⌘6, os setores do
//                       app, na ordem da barra de setores), achado na lista de
//                       itens e executado direto (`Atalhos.doMenu`, chamado pela janela).
//
// As camadas 1–3 rodam antes de o macOS distribuir a tecla (monitor local); 4 e 5, na vez da
// janela. Atalho novo de menu = uma linha no menu; atalho novo de tela = camada 3 ou 4.

@MainActor
enum Atalhos {
    /// O campo do chat que está com o cursor: recebe o ⌘V antes de todo mundo e devolve true se
    /// ficou com ele (arquivo ou imagem copiados viram anexo). Texto comum segue o caminho normal.
    private(set) static var campoDoChat: (dono: UUID, colar: () -> Bool)?

    static func assumirColar(_ dono: UUID, _ colar: @escaping () -> Bool) { campoDoChat = (dono, colar) }
    static func soltarColar(_ dono: UUID) { if campoDoChat?.dono == dono { campoDoChat = nil } }

    /// Camada 2. true = alguém tratou.
    static func edicao(_ evento: NSEvent) -> Bool {
        let mods = evento.modifierFlags.intersection([.command, .control, .option, .shift])
        let tecla = evento.charactersIgnoringModifiers?.lowercased() ?? ""
        let acao: Selector
        switch (mods, tecla) {
        case (.command, "c"): acao = #selector(NSText.copy(_:))
        case (.command, "x"): acao = #selector(NSText.cut(_:))
        case (.command, "a"): acao = #selector(NSText.selectAll(_:))
        case (.command, "z"): acao = Selector(("undo:"))
        case ([.command, .shift], "z"): acao = Selector(("redo:"))
        case (.command, "v"):
            if let campo = campoDoChat, campo.colar() { return true }
            acao = #selector(NSText.paste(_:))
        default: return false
        }
        // Direto para quem está com o cursor (e quem vem depois dele na cadeia).
        return NSApp.sendAction(acao, to: nil, from: nil)
    }

    /// Camada 5: procura o atalho nos itens do menu e executa a ação do item.
    static func doMenu(_ menu: NSMenu, _ evento: NSEvent) -> Bool {
        let mods = evento.modifierFlags.intersection([.command, .control, .option, .shift])
        guard mods.contains(.command), let tecla = evento.charactersIgnoringModifiers?.lowercased(), !tecla.isEmpty else { return false }
        func procurar(_ m: NSMenu) -> NSMenuItem? {
            for item in m.items {
                if let sub = item.submenu, let achado = procurar(sub) { return achado }
                let chave = item.keyEquivalent
                guard !chave.isEmpty, item.action != nil, chave.lowercased() == tecla else { continue }
                // Letra maiúscula no item quer dizer "com ⇧".
                var pedidos = item.keyEquivalentModifierMask.intersection([.command, .control, .option, .shift])
                if chave != chave.lowercased() { pedidos.insert(.shift) }
                if pedidos == mods { return item }
            }
            return nil
        }
        guard let item = procurar(menu), let acao = item.action else { return false }
        return NSApp.sendAction(acao, to: item.target, from: item)
    }
}
