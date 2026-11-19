import AppKit
import SwiftUI

// O app do Crew: a janela das sessões (JanelaCrew), com ícone no Dock e menu próprio enquanto
// está aberta, e a janela de Ajustes (JanelaAjustes) à parte, pelo menu "Ajustes…" (⌘,).
// Fechadas as duas, o Crew volta a morar só no notch e na barra de menu (sem ícone no Dock).

@MainActor
final class JanelaCrew: NSObject, NSWindowDelegate {
    static let shared = JanelaCrew()

    private var janela: NSWindow?

    var aberta: Bool { janela?.isVisible == true }

    /// O Hugo está com o app do Crew na frente: janela à vista e o Crew é o app ativo.
    var naFrente: Bool {
        guard let w = janela, w.isVisible, NSApp.isActive else { return false }
        return w.occlusionState.contains(.visible)
    }

    /// Abre (ou traz para a frente) o app do Crew: as sessões.
    func abrir() {
        if let w = janela { Janelas.mostrar(w); return }
        let w = JanelaDoCrew(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
                         styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.title = "Crew"
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.appearance = NSAppearance(named: .darkAqua)
        w.backgroundColor = NSColor(red: 0.039, green: 0.039, blue: 0.047, alpha: 1)
        w.contentView = NSHostingView(rootView: AppCrewView())
        w.contentMinSize = NSSize(width: 900, height: 600)
        w.isReleasedWhenClosed = false
        w.delegate = self
        // Nome novo: a janela antiga (Central, com as páginas dos módulos) não impõe o tamanho dela.
        if !w.setFrameUsingName("CrewSessoes") { w.center() }
        w.setFrameAutosaveName("CrewSessoes")
        janela = w
        Janelas.mostrar(w)
    }

    func windowWillClose(_ notification: Notification) {
        janela?.contentView = nil
        janela = nil
        Janelas.fechou()
    }
}

/// A janela de Ajustes: as páginas dos módulos e os ajustes gerais (a antiga Central).
/// Só abre pelo menu "Ajustes…" (⌘,) e pelos atalhos que levam direto à página de um módulo.
@MainActor
final class JanelaAjustes: NSObject, NSWindowDelegate {
    static let shared = JanelaAjustes()

    private var janela: NSWindow?

    var aberta: Bool { janela?.isVisible == true }

    func abrir(_ pagina: PaginaCentral? = nil) {
        if let w = janela {
            if let pagina { NotificationCenter.default.post(name: .irParaPagina, object: pagina) }
            Janelas.mostrar(w)
            return
        }
        let w = JanelaDoCrew(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
                         styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.title = "Ajustes do Crew"
        w.titlebarAppearsTransparent = true
        w.toolbarStyle = .unified
        w.contentView = NSHostingView(rootView: CentralView(pagina: pagina ?? .geral))
        w.contentMinSize = NSSize(width: 860, height: 560)
        w.isReleasedWhenClosed = false
        w.delegate = self
        if !w.setFrameUsingName("CrewAjustes") { w.center() }
        w.setFrameAutosaveName("CrewAjustes")
        janela = w
        Janelas.mostrar(w)
    }

    func windowWillClose(_ notification: Notification) {
        // Solta o conteúdo: as telas saem de cena e os leitores (Amostrador) param.
        janela?.contentView = nil
        janela = nil
        Janelas.fechou()
    }
}

/// Com alguma janela aberta o Crew é app de Dock; fechadas as duas, volta a morar só no notch.
@MainActor
enum Janelas {
    static func mostrar(_ w: NSWindow) {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        MenuDoCrew.instalar()
        // Virar app de Dock recria o ícone do Dock: o do pacote entra de novo.
        if let u = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let icone = NSImage(contentsOf: u) {
            NSApp.applicationIconImage = icone
        }
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func fechou() {
        // O delegate roda antes de a janela sumir: confere no próximo ciclo.
        DispatchQueue.main.async {
            if !JanelaCrew.shared.aberta && !JanelaAjustes.shared.aberta {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}

extension Notification.Name {
    /// Com a janela de Ajustes aberta: troca a página (`object`: PaginaCentral).
    static let irParaPagina = Notification.Name("crew.irParaPagina")
    /// App do Crew: volta para o início, com o campo de pedido pronto para uma sessão nova.
    static let novaSessao = Notification.Name("crew.novaSessao")
    /// App do Crew na frente e uma sessão entregou ou falhou (`object`: id da task): em vez
    /// do aviso da ilha, a sessão ganha uma ênfase discreta na lista.
    static let sessaoPedeAtencao = Notification.Name("crew.sessaoPedeAtencao")
    /// App do Crew: abre uma sessão (`object`: id da task, String).
    static let abrirSessaoNoApp = Notification.Name("crew.abrirSessaoNoApp")
}

/// Menu principal enquanto o Crew é app de Dock (antes ele não tinha barra de menu nenhuma).
@MainActor
enum MenuDoCrew {
    private static var nosso: NSMenu?
    private static var vigia: NSKeyValueObservation?

    /// Põe o menu do Crew na barra. O SwiftUI troca o menu principal pelo padrão dele (sem
    /// Arquivo nem Editar — e aí ⌘C, ⌘V, ⌘X, ⌘A e ⌘Z param de funcionar): toda vez que isso
    /// acontece, o nosso volta.
    static func instalar() {
        if let nosso {
            if NSApp.mainMenu !== nosso { NSApp.mainMenu = nosso }
            return
        }
        let principal = NSMenu()

        let app = NSMenu(title: "Crew")
        app.addItem(withTitle: "Sobre o Crew", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(item("Ajustes…", ",", #selector(AlvoMenu.ajustes)))
        app.addItem(.separator())
        app.addItem(withTitle: "Ocultar o Crew", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(.separator())
        app.addItem(withTitle: "Sair do Crew", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        principal.addItem(submenu(app))

        let arquivo = NSMenu(title: "Arquivo")
        arquivo.addItem(item("Nova sessão", "n", #selector(AlvoMenu.nova)))
        arquivo.addItem(.separator())
        arquivo.addItem(withTitle: "Fechar janela", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        principal.addItem(submenu(arquivo))

        let editar = NSMenu(title: "Editar")
        editar.addItem(withTitle: "Desfazer", action: Selector(("undo:")), keyEquivalent: "z")
        editar.addItem(withTitle: "Refazer", action: Selector(("redo:")), keyEquivalent: "Z")
        editar.addItem(.separator())
        editar.addItem(withTitle: "Recortar", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editar.addItem(withTitle: "Copiar", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editar.addItem(withTitle: "Colar", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editar.addItem(withTitle: "Selecionar tudo", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        principal.addItem(submenu(editar))

        let ir = NSMenu(title: "Ir")
        // Os setores do app: ⌘1 … ⌘6, na ordem da barra de setores.
        for s in Setor.allCases {
            let i = item(s.nome, "\(s.numero)", #selector(AlvoMenu.irParaSetor(_:)))
            i.tag = s.numero
            ir.addItem(i)
        }
        ir.addItem(.separator())
        ir.addItem(item("Abrir a ilha", "", #selector(AlvoMenu.ilha)))
        principal.addItem(submenu(ir))

        let janela = NSMenu(title: "Janela")
        janela.addItem(withTitle: "Minimizar", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        janela.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        principal.addItem(submenu(janela))
        NSApp.windowsMenu = janela

        nosso = principal
        NSApp.mainMenu = principal
        // A vigia abaixo não basta: o SwiftUI às vezes troca o menu sem que ela dispare (visto em
        // 2026-11-12: a barra ficou "Crew, View, Window, Help" e ⌘C/⌘V morreram no app inteiro).
        // Então o menu é conferido antes de cada tecla com ⌘ — o atalho é resolvido logo depois,
        // já no menu certo — e quando o app ou uma janela volta para a frente.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { evento in
            // Camada 2 de `Atalhos.swift`: copiar, colar, recortar, selecionar tudo, desfazer.
            guard evento.modifierFlags.contains(.command) else { return evento }
            let tratou: Bool = MainActor.assumeIsolated { repor(); return Atalhos.edicao(evento) }
            return tratou ? nil : evento
        }
        for nome in [NSApplication.didBecomeActiveNotification, NSWindow.didBecomeKeyNotification] {
            NotificationCenter.default.addObserver(forName: nome, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { repor() }
            }
        }
        vigia = NSApp.observe(\.mainMenu, options: [.new]) { _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if let nosso, NSApp.mainMenu !== nosso { NSApp.mainMenu = nosso }
                }
            }
        }
    }

    /// Um atalho de teclado resolvido pelo menu do Crew, esteja ele na barra ou não. É a fonte
    /// única dos atalhos do app: o que está no menu (⌘N, ⌘C, ⌘V, ⌘,…) vale sempre, mesmo quando
    /// o SwiftUI troca a barra de menus pela dele. Quem chama é a janela (`JanelaDoCrew`), depois
    /// que as telas tiveram a vez delas — o mesmo ponto em que o macOS consultaria o menu.
    static func atalho(_ evento: NSEvent) -> Bool {
        // (`NSMenu.performKeyEquivalent` não serve aqui: fora da barra, o menu não executa nada.)
        guard let nosso, NSApp.activationPolicy() == .regular else { return false }
        return Atalhos.doMenu(nosso, evento)
    }

    /// O menu do Crew de volta, se foi trocado (só enquanto o Crew é app de Dock).
    private static func repor() {
        guard let nosso, NSApp.activationPolicy() == .regular, NSApp.mainMenu !== nosso else { return }
        NSApp.mainMenu = nosso
    }

    private static func submenu(_ m: NSMenu) -> NSMenuItem {
        let i = NSMenuItem(title: m.title, action: nil, keyEquivalent: "")
        i.submenu = m
        return i
    }

    private static func item(_ titulo: String, _ tecla: String, _ acao: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: titulo, action: acao, keyEquivalent: tecla)
        i.target = AlvoMenu.shared
        return i
    }
}

@MainActor
final class AlvoMenu: NSObject {
    static let shared = AlvoMenu()
    @objc func ajustes() { JanelaAjustes.shared.abrir() }
    @objc func sessoes() { JanelaCrew.shared.abrir() }
    @objc func nova() {
        JanelaCrew.shared.abrir()
        // Janela recém-criada: a tela ainda não escuta; avisa no próximo ciclo.
        DispatchQueue.main.async { NotificationCenter.default.post(name: .novaSessao, object: nil) }
    }
    @objc func ilha() { NotificationCenter.default.post(name: .abrirIlha, object: nil) }
}

/// Janela do Crew (sessões e Ajustes): atalho que nenhuma tela tratou vai para o menu do Crew.
final class JanelaDoCrew: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        super.performKeyEquivalent(with: event) || MenuDoCrew.atalho(event)
    }
}
