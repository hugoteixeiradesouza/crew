import AppKit
import SwiftUI

// A janela do comando universal: um painel flutuante, sem moldura, que aparece por cima de
// qualquer app SEM ativar o Crew (o app que estava na frente continua na frente; ao fechar, o
// teclado volta para ele). Fecha com Esc, ao escolher um resultado ou ao clicar fora.
// Todo o teclado da lista é tratado aqui, na janela: ↑ ↓ Enter ⌘Enter Esc valem com o cursor
// no campo de texto e nunca dependem da barra de menus.

final class JanelaComando: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ evento: NSEvent) {
        if evento.type == .keyDown, PainelComando.shared.tecla(evento, em: self) { return }
        super.sendEvent(evento)
    }
}

@MainActor
final class PainelComando: NSObject, NSWindowDelegate {
    static let shared = PainelComando()

    static let largura: CGFloat = 680
    /// Altura da janela (transparente): o cartão cresce dentro dela, de cima para baixo.
    static let altura: CGFloat = 640

    private var janela: JanelaComando?

    /// Altura do cartão dentro da janela (a janela é maior e transparente em volta).
    var alturaCartao: CGFloat = 120
    /// O Hugo está arrastando o painel: a posição nova fica lembrada.
    var arrastando = false
    /// Para onde o Homie do painel olha: o mouse.
    static let olhar = OlharHomie()
    private var vigias: [Any] = []
    private static let chavePosicao = "modulo.comando.posicao"

    func mostrar() {
        let w = janela ?? criar()
        janela = w
        w.setFrame(quadroInicial(), display: true)
        w.makeKeyAndOrderFront(nil)
        focarCampo()
        vigiar()
    }

    func esconder() {
        soltarVigias()
        janela?.orderOut(nil)
    }

    /// Onde o painel abre: onde o Hugo o deixou da última vez (se ainda cabe numa tela); sem
    /// isso, na tela onde o mouse está, um pouco acima do meio (como o Spotlight).
    private func quadroInicial() -> NSRect {
        let tamanho = NSSize(width: Self.largura, height: Self.altura)
        if let p = UserDefaults.standard.string(forKey: Self.chavePosicao) {
            let quadro = NSRect(origin: NSPointFromString(p), size: tamanho)
            // O cartão (o topo da janela) precisa estar inteiro numa tela.
            let cartao = NSRect(x: quadro.minX + 30, y: quadro.maxY - 8 - 120, width: Self.largura - 60, height: 120)
            if NSScreen.screens.contains(where: { $0.visibleFrame.contains(cartao) }) { return quadro }
        }
        let ponto = NSEvent.mouseLocation
        let tela = NSScreen.screens.first { NSMouseInRect(ponto, $0.frame, false) } ?? NSScreen.main
        guard let area = tela?.visibleFrame else { return NSRect(origin: .zero, size: tamanho) }
        let topo = area.maxY - area.height * 0.2
        return NSRect(x: area.midX - Self.largura / 2, y: topo - Self.altura, width: Self.largura, height: Self.altura)
    }

    /// Dois cliques na alça: esquece a posição e volta para o lugar de sempre.
    func voltarAoLugar() {
        UserDefaults.standard.removeObject(forKey: Self.chavePosicao)
        janela?.setFrame(quadroInicial(), display: true, animate: true)
    }

    func windowDidMove(_ notification: Notification) {
        guard arrastando, let w = janela else { return }
        UserDefaults.standard.set(NSStringFromPoint(w.frame.origin), forKey: Self.chavePosicao)
    }

    /// O cartão, em coordenadas da tela.
    private var cartaoNaTela: NSRect? {
        guard let q = janela?.frame else { return nil }
        return NSRect(x: q.minX + 30, y: q.maxY - 8 - alturaCartao, width: q.width - 60, height: alturaCartao)
    }

    /// Enquanto o painel está aberto: clique fora do cartão fecha (em outro app, em outra
    /// janela do Crew ou na parte transparente da janela do painel) e o Homie segue o mouse.
    private func vigiar() {
        soltarVigias()
        let cliques: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let v = NSEvent.addGlobalMonitorForEvents(matching: cliques, handler: { _ in
            MainActor.assumeIsolated { ComandoServico.shared.fechar() }
        }) { vigias.append(v) }
        if let v = NSEvent.addLocalMonitorForEvents(matching: cliques, handler: { [weak self] evento in
            let fora: Bool = MainActor.assumeIsolated {
                guard let self, let cartao = self.cartaoNaTela else { return false }
                return !cartao.contains(NSEvent.mouseLocation)
            }
            if fora { MainActor.assumeIsolated { ComandoServico.shared.fechar() } }
            return evento
        }) { vigias.append(v) }
        let moveu: (NSEvent) -> Void = { [weak self] _ in MainActor.assumeIsolated { self?.olharParaOMouse() } }
        if let v = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: moveu) { vigias.append(v) }
        if let v = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseUp], handler: { [weak self] evento in
            MainActor.assumeIsolated {
                self?.olharParaOMouse()
                if evento.type == .leftMouseUp { self?.arrastando = false }
            }
            return evento
        }) { vigias.append(v) }
        olharParaOMouse()
    }

    private func soltarVigias() {
        vigias.forEach { NSEvent.removeMonitor($0) }
        vigias = []
        arrastando = false
    }

    /// Os olhos do Homie apontam para o mouse (ele mora no canto de cima, à esquerda, do cartão).
    private func olharParaOMouse() {
        guard let q = janela?.frame else { return }
        let homie = NSPoint(x: q.minX + 30 + 37, y: q.maxY - 8 - 29)
        let m = NSEvent.mouseLocation
        Self.olhar.x = tanh((m.x - homie.x) / 260)
        Self.olhar.y = tanh((m.y - homie.y) / 220)
    }

    private func criar() -> JanelaComando {
        let w = JanelaComando(contentRect: NSRect(x: 0, y: 0, width: Self.largura, height: Self.altura),
                              styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                              backing: .buffered, defer: false)
        w.isFloatingPanel = true
        w.level = .modalPanel
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        w.hidesOnDeactivate = false
        w.becomesKeyOnlyIfNeeded = false
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false   // a sombra é do cartão (a janela é maior que ele)
        w.isReleasedWhenClosed = false
        w.isMovable = true              // arrasta-se pela alça do cartão (`AlcaDoPainel`)
        w.isMovableByWindowBackground = false
        w.acceptsMouseMovedEvents = true
        w.animationBehavior = .none
        w.appearance = NSAppearance(named: .darkAqua)
        w.delegate = self
        let tela = PainelComandoView()
            .frame(width: Self.largura, height: Self.altura, alignment: .top)
        w.contentView = NSHostingView(rootView: tela)
        return w
    }

    /// O cursor vai para o campo assim que a janela vira a do teclado.
    private func focarCampo() {
        DispatchQueue.main.async { [weak self] in
            guard let w = self?.janela, let raiz = w.contentView else { return }
            if let campo = Self.campo(em: raiz) { w.makeFirstResponder(campo) }
        }
    }

    private static func campo(em v: NSView) -> NSTextField? {
        if let c = v as? NSTextField, c.isEditable { return c }
        for s in v.subviews { if let c = campo(em: s) { return c } }
        return nil
    }

    /// Clicou fora (outro app ou outra janela ficou com o teclado): fecha.
    func windowDidResignKey(_ notification: Notification) {
        ComandoServico.shared.fechar()
    }

    /// Teclas da lista. true = tratada (não chega ao campo de texto).
    fileprivate func tecla(_ evento: NSEvent, em janela: NSWindow) -> Bool {
        let s = ComandoServico.shared
        guard s.aberto else { return false }
        let mods = evento.modifierFlags.intersection([.command, .control, .option, .shift])
        // Compondo acento ou caractere (texto marcado): a tecla é do campo.
        if let editor = janela.firstResponder as? NSTextView, editor.hasMarkedText() { return false }
        switch Int(evento.keyCode) {
        case 53:   // Esc: com texto, limpa; vazio, fecha
            if s.texto.isEmpty { s.fechar() } else { s.texto = "" }
            return true
        case 125 where mods.isEmpty, 48 where mods.isEmpty:   // ↓ · Tab
            s.andar(1)
            return true
        case 126 where mods.isEmpty, 48 where mods == .shift:   // ↑ · ⇧Tab
            s.andar(-1)
            return true
        case 45 where mods == .control:   // ⌃N
            s.andar(1)
            return true
        case 35 where mods == .control:   // ⌃P
            s.andar(-1)
            return true
        case 36, 76:   // Enter · ⌘Enter
            if mods.isEmpty { s.executar(); return true }
            if mods == .command { s.executar(secundaria: true); return true }
            return false
        default:
            return false
        }
    }
}
