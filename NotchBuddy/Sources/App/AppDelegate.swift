import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    private(set) var islandController: IslandWindowController?
    private var espacoIlha: EspacoProprio?
    private var saidaRespondida = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ignore SIGPIPE — prevents crash when nb-hook closes socket before we write response
        signal(SIGPIPE, SIG_IGN)
        // O Dock às vezes segura um ícone antigo em cache: o app impõe o do próprio pacote.
        if let u = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let icone = NSImage(contentsOf: u) {
            NSApp.applicationIconImage = icone
        }
        // Modo de captura: fotografa as telas e sai (sem Keychain, hooks, pollers nem barra de menu)
        if let dir = CaptureTool.requested {
            Gravar.desligado = true   // capturas nunca gravam nos ajustes de verdade
            NSApp.setActivationPolicy(.accessory)
            CaptureTool.run(into: dir)
            return
        }
        // Gerador de ícones: redesenha o ícone do app e o da barra de menus e sai
        if let dir = GeradorDeIcones.requested {
            NSApp.setActivationPolicy(.accessory)
            GeradorDeIcones.run(into: dir)
            exit(0)
        }
        // Warm up Keychain cache on main thread BEFORE any poller or view touches it
        _ = KeychainStore.shared
        NSApp.setActivationPolicy(.accessory)
        setupMenuBarItem()
        setupIsland()
    }

    // MARK: - crew://

    func application(_ application: NSApplication, open urls: [URL]) {
        for u in urls { Automacao.abrir(u) }
    }

    // MARK: - Menu bar

    private func setupMenuBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }
        button.image = NSImage(named: "MenuBarIcon") ?? NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "Crew")
        button.image?.size = NSSize(width: 24, height: 18)
        button.image?.accessibilityDescription = "Crew"
        button.image?.isTemplate = true

        let menu = NSMenu()
        menu.addItem(withTitle: "Abrir o app do Crew", action: #selector(abrirApp), keyEquivalent: "")
        menu.addItem(withTitle: "Nova sessão…", action: #selector(novaSessao), keyEquivalent: "n")
        menu.addItem(withTitle: "Abrir a ilha", action: #selector(openIsland), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Ajustes…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Sair do Crew", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        statusItem?.menu = menu
    }

    // MARK: - Actions

    @objc private func openIsland() {
        islandController?.expand(to: .overview)
    }

    @objc private func openSettings() { JanelaAjustes.shared.abrir() }
    @objc private func abrirApp() { JanelaCrew.shared.abrir() }
    @objc private func novaSessao() { AlvoMenu.shared.nova() }

    private func abrirCentral(modulo: String?) {
        // Ferramenta com tela de trabalho abre no setor dela, no app; os Ajustes ficam com a configuração.
        if let modulo, Setores.temTela(modulo) { JanelaCrew.shared.abrir(ferramenta: modulo); return }
        JanelaAjustes.shared.abrir(modulo.map { .modulo($0) })
    }

    /// Clique no ícone do Dock (enquanto o app está aberto) traz a janela de volta.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !JanelaAjustes.shared.aberta || JanelaCrew.shared.aberta { JanelaCrew.shared.abrir() }
        else { JanelaAjustes.shared.abrir() }
        return false
    }

    /// Fechar a janela não encerra o Crew: ele continua no notch.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Sair do Crew no meio de uma gravação de tela: primeiro a gravação para e o MP4 fecha
    /// (sem isso o arquivo fica ilegível); só então o app sai. Com teto de tempo, para o Crew
    /// nunca ficar preso sem sair.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard GravacaoServico.shared.precisaFecharAntesDeSair else { return .terminateNow }
        Task { @MainActor in
            await GravacaoServico.shared.fecharParaSair()
            self.responderSaida()
        }
        // Em modo comum: enquanto o app espera para sair, o laço não roda no modo padrão.
        let teto = Timer(timeInterval: 9, repeats: false) { [weak self] _ in MainActor.assumeIsolated { self?.responderSaida() } }
        RunLoop.main.add(teto, forMode: .common)
        return .terminateLater
    }

    private func responderSaida() {
        guard !saidaRespondida else { return }
        saidaRespondida = true
        NSApp.reply(toApplicationShouldTerminate: true)
    }

    /// Ao encerrar, os motores externos caem junto (renderização, prévia): nada fica órfão.
    func applicationWillTerminate(_ notification: Notification) {
        VideoServico.shared.parar()
        FalaServico.shared.desligar()   // derruba o servidor da voz humanizada
    }

    // MARK: - Island setup

    private func setupIsland() {
        islandController = IslandWindowController()
        islandController?.showWindow(nil)
        // A ilha num espaço próprio, acima das áreas de trabalho: não some ao trocar de tela
        if let janela = islandController?.window {
            espacoIlha = EspacoProprio()
            espacoIlha?.incluir(janela)
        }
        islandController?.fsm.launch()
        HookServer.shared.start()
        MediaService.shared.start()
        NivelService.shared.start()
        Registro.shared.iniciar()
        if AgentTask.integracoesLigadas { startIntegrationPollers() }
        NotificationCenter.default.addObserver(self, selector: #selector(openSettings),
                                               name: .openFullSettings, object: nil)
        // crew://ilha[/<modulo>]
        NotificationCenter.default.addObserver(forName: .abrirIlha, object: nil, queue: .main) { [weak self] n in
            let id = n.object as? String
            MainActor.assumeIsolated {
                if let id, Registro.shared.estaLigado(id), Registro.shared.modulo(id)?.temAba == true {
                    AppState.shared.moduloAberto = id
                    self?.islandController?.expand(to: .modulo)
                } else {
                    self?.islandController?.expand(to: .overview)
                }
            }
        }
        // Central numa página: com a janela já aberta, a própria CentralView troca a página
        NotificationCenter.default.addObserver(forName: .abrirCentral, object: nil, queue: .main) { [weak self] n in
            let id = n.object as? String
            MainActor.assumeIsolated { self?.abrirCentral(modulo: id) }
        }
    }

    private func startIntegrationPollers() {
        N8nPoller.shared.start()
        VercelPoller.shared.start()
        ResendPoller.shared.start()
        GithubPoller.shared.start()
        StripePoller.shared.start()
        CalcomPoller.shared.start()
        NotionPoller.shared.start()
    }
}
