import AppKit
import Combine
import SwiftUI

@MainActor
final class IslandWindowController: NSWindowController {

    private var islandPanel: IslandPanel!
    private var state: AppState { AppState.shared }

    // State machine (replaces all hover/absence/auto-close timers)
    let fsm = IslandStateMachine()

    private var wasInIsland = false
    private var frameTimer: Timer?
    private var keyMonitor: Any?
    private var viewSubscription: AnyCancellable?
    private var stateSubscription: AnyCancellable?
    private var chatHeightSubscription: AnyCancellable?
    /// Quanto o Hugo já puxou contra a trava neste gesto (+ para esticar, − para recolher).
    private var chatPull: CGFloat = 0
    private var chatPullReleased = false
    /// Último passo do puxão: diz se o gesto terminou num "peteleco"
    private var chatPullLastDy: CGFloat = 0
    /// Última aba aberta pelo Hugo — Option duas vezes reabre nela.
    private var ultimaVista: IslandView = .overview
    /// Quando o Option (sozinho) foi apertado da última vez; 0 = não conta para o toque duplo.
    private var optionApertadoEm: TimeInterval = 0
    /// O gesto atual começou com o chat já no fim? Só assim ele pode recolher a ilha:
    /// quem desce rolando e chega no fim precisa de um segundo movimento.
    private var chatGestureStartedAtBottom = false
    /// Roda de mouse não tem começo de gesto: uma pausa entre giros marca um movimento novo.
    private var chatLastWheelAt: TimeInterval = 0
    private var chatSnapBack: DispatchWorkItem?

    // Confused recovery timer (set by handleDizzy)
    private var confusedRecoveryTimer: DispatchWorkItem?

    // Finished-pin timer
    private var finishedPinTimer: DispatchWorkItem?

    // Bot-head hover (love emote — mirrors prototype botHover())
    private var hoverTimer: DispatchWorkItem?
    private var botHoverTimer: DispatchWorkItem?
    private var botHovering: Bool = false
    private var lastLoveTime: Double = 0
    private var botHoverStartPos: CGPoint = .zero

    // Window attach drag (M8)
    private var attachDragStart: NSPoint? = nil
    private var pendingIslandClick = false   // any island click → expand on mouseUp
    private var inAttachDrag = false
    private var dragGhostPanel: NSPanel? = nil
    private var dragGhostSize: CGFloat = 0
    private var ghostCurrentOrigin: NSPoint = .zero
    private var highlightPanel: NSPanel? = nil
    private var highlightWindowPid: pid_t = 0

    // Notch real dimensions (set on init)
    private var notchW: CGFloat = IslandConst.notchWidth
    private var notchH: CGFloat = IslandConst.notchHeight

    convenience init() {
        let screen = Self.notchScreen() ?? NSScreen.main!
        let nW = Self.notchWidth(for: screen)
        let nH = Self.notchHeight(for: screen)

        let panelW: CGFloat = 720
        let panelH: CGFloat = 320
        let sf = screen.frame
        let panel = IslandPanel(
            contentRect: NSRect(x: sf.midX - panelW/2, y: sf.maxY - panelH,
                                width: panelW, height: panelH),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.notchWidth  = nW
        panel.notchHeight = nH

        self.init(window: panel)
        self.islandPanel = panel
        self.notchW = nW
        self.notchH = nH
        setupPanel(screen: screen)
    }

    private func setupPanel(screen: NSScreen) {
        guard let panel = window as? IslandPanel else { return }
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        // A ilha nunca some: painel por padrão se esconde quando o app perde o foco (o que
        // acontece ao trocar de tela/área de trabalho) e reaparece depois; nem anima ao surgir.
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.ignoresMouseEvents = true

        // Propagate real notch dimensions to AppState
        AppState.shared.notchWidth  = notchW
        AppState.shared.notchHeight = notchH

        let contentSize = panel.contentRect(forFrameRect: panel.frame).size

        // Apple-recommended pattern: put NSHostingView and drag destination as siblings
        // inside a common superview, rather than embedding one inside the other.
        let container = NSView(frame: NSRect(origin: .zero, size: contentSize))
        container.autoresizingMask = [.width, .height]

        let hosting = NSHostingView(rootView: IslandRootView().environmentObject(AppState.shared))
        hosting.frame = NSRect(origin: .zero, size: contentSize)
        hosting.autoresizingMask = [.width, .height]

        // FileDropNSView sits below the hosting view (hitTest returns nil → no mouse interference).
        // AppKit routes NSDraggingDestination events to registered views independently of hitTest.
        let dropView = FileDropNSView(frame: NSRect(origin: .zero, size: contentSize))
        dropView.autoresizingMask = [.width, .height]
        dropView.onDragEntered = { [weak self] loc in
            Task { @MainActor in
                let iLoc = self?.windowToIsland(loc) ?? CGPoint(x: 320, y: 88)
                let s = AppState.shared
                // Com o chat aberto, o arquivo vai para a conversa
                if s.mode == .expanded && s.view == .prompt && s.moduloAnexosChat {
                    s.arrastoParaChat = true
                    s.arrastoSessao = s.chatSelection
                }
                AppState.shared.fileDragOver = true
                // enterZone sets isActive=true BEFORE hookExpand triggers re-render,
                // so IslandContainer sees isActive=true when state.view becomes .upload.
                UploadSequenceEngine.shared.enterZone(x: iLoc.x, y: iLoc.y)
                NotificationCenter.default.post(name: .hookExpand, object: IslandView.upload)
                NotificationCenter.default.post(name: .botMorphTo, object: CGFloat(1))
            }
        }
        dropView.onDragUpdated = { [weak self] loc in
            Task { @MainActor in
                let iLoc = self?.windowToIsland(loc) ?? CGPoint(x: 320, y: 88)
                UploadSequenceEngine.shared.updateCursor(x: iLoc.x, y: iLoc.y)
            }
        }
        dropView.onDragExited = {
            Task { @MainActor in
                AppState.shared.fileDragOver = false
                // Do NOT collapse — drag session still active; island stays open.
                NotificationCenter.default.post(name: .botMorphTo, object: CGFloat(0))
                UploadSequenceEngine.shared.exitZone()
                // Desistiu do arrasto que veio do chat: volta à conversa
                let s = AppState.shared
                if s.arrastoParaChat && s.view == .upload { s.voltarAoChatDoArrasto() }
            }
        }
        dropView.onFilesDropped = { urls in
            Task { @MainActor in
                await FileDropHandler.handle(urls: urls, state: AppState.shared)
            }
        }

        container.addSubview(hosting)    // z-bottom: SwiftUI + mouse events
        container.addSubview(dropView)   // z-top: drag only (hitTest→nil, transparent to mouse)
        panel.contentView = container

        startPolling()
        startKeyMonitor()
        wireFSM()

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposicionarNaTela() }
        }

        // Make panel key whenever the prompt/chat view becomes active
        // (nonactivatingPanel never auto-becomes key, but TextField needs it)
        viewSubscription = state.$view
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newView in
                guard let self else { return }
                if [.overview, .prompt, .media, .note, .settings, .modulo, .modulos].contains(newView) { self.ultimaVista = newView }
                if newView == .prompt {
                    self.islandPanel.makeKey()
                } else {
                    // Saiu do chat: próxima abertura escolhe a sessão de novo
                    // (menos durante um arrasto para o chat, que volta à mesma conversa)
                    self.state.chatSelectionSet = false
                    if !self.state.arrastoParaChat, self.state.chatHeight != AppState.chatMinHeight {
                        // volta ao tamanho compacto
                        self.state.chatHeight = AppState.chatMinHeight
                        self.state.chatExpanded = false
                    }
                }
            }
        // Chat aberto: o painel já fica do tamanho máximo, para não mudar de tamanho durante
        // o puxão (redimensionar a janela a cada passo fazia o topo da ilha tremer).
        // Aba de módulo alta: o mesmo — o painel cresce antes da ilha e encolhe depois dela.
        // Tela que cresce (abas de módulo com versão expandida, "Vira task?"): o painel já fica na
        // altura máxima dela enquanto está aberta, aberta ou não — o elástico não redimensiona nada.
        chatHeightSubscription = state.$mode.combineLatest(state.$view, state.$alturaAba, state.$moduloAberto)
            .map { modo, vista, alturaAba, modulo -> CGFloat in
                guard modo == .expanded else { return 0 }
                if vista == .prompt { return AppState.shared.chatMaxHeight }
                if vista.cresce, let h = ElasticoIlha.alta(vista, modulo: modulo) ?? alturaAba { return h }
                return 0
            }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] alta in self?.fitPanel(alturaIlha: alta) }

        // Chat com dois pontos de trava (compacto e esticado). Puxar contra a trava estica
        // só um pouco, como elástico; puxar com força solta e a ilha vai até o outro ponto
        // com mola (e um toque no trackpad). Soltou antes: volta.
        NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            let dy = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 12
            let dx = event.hasPreciseScrollingDeltas ? event.scrollingDeltaX : event.scrollingDeltaX * 12
            let phase = event.phase
            let momentum = !event.momentumPhase.isEmpty
            let ponto = event.locationInWindow
            let consumed: Bool = MainActor.assumeIsolated {
                guard let self else { return false }
                // Rolagem para o lado (abas de sessão) ou em cima da fileira de abas: é do conteúdo,
                // nunca mexe na altura da ilha. Decidido no começo do gesto, vale até o fim dele.
                if phase.contains(.began) || phase.contains(.mayBegin) || (phase.isEmpty && !momentum && self.gestoDoConteudo == nil) {
                    self.gestoDoConteudo = nil
                }
                if self.gestoDoConteudo == nil, abs(dx) + abs(dy) > 0.5 {
                    self.gestoDoConteudo = abs(dx) > abs(dy) * 0.8
                        || (AppState.shared.view == .prompt && self.sobreAbasDoChat(ponto))
                }
                if self.gestoDoConteudo == true {
                    if phase.contains(.ended) || phase.contains(.cancelled) { self.gestoDoConteudo = nil }
                    return false
                }
                if phase.contains(.ended) || phase.contains(.cancelled) { self.gestoDoConteudo = nil }
                // Telas que crescem (abas de módulo, "Vira task?"): o elástico do chat
                if ElasticoIlha.shared.rolar(dy: dy, phase: phase, momentum: momentum,
                                             ponto: ponto, janela: event.window) { return true }
                return self.handleChatScroll(dy: dy, phase: phase, momentum: momentum)
            }
            return consumed ? nil : event
        }
    }

    /// O gesto atual é do conteúdo (para o lado, ou sobre as abas de sessão)? nil = ainda não decidido.
    private var gestoDoConteudo: Bool?

    /// Ponto (coordenadas da janela) em cima da fileira de abas de sessão do chat: logo abaixo
    /// do cabeçalho da ilha (8 + 34 pt) até ~36 pt para baixo.
    private func sobreAbasDoChat(_ p: NSPoint) -> Bool {
        guard let panel = window else { return false }
        let doTopo = panel.frame.height - p.y
        return doTopo >= 40 && doTopo <= 82
    }

    /// Força para soltar a trava, em pontos de rolagem acumulados no mesmo gesto.
    private let chatPullThreshold: CGFloat = 70
    /// Soltou os dedos depois de puxar ao menos esta fração da força: completa a troca.
    private let chatPullCommitFraction: CGFloat = 0.45
    /// Último passo rápido assim (peteleco) também completa, mesmo com pouco puxão.
    private let chatPullFlick: CGFloat = 14
    /// Quanto a ilha cede no máximo enquanto se puxa contra a trava.
    private let chatPullMaxGive: CGFloat = 60

    private func handleChatScroll(dy: CGFloat, phase: NSEvent.Phase, momentum: Bool) -> Bool {
        let s = AppState.shared
        guard s.mode == .expanded, s.view == .prompt else { chatPull = 0; return false }
        let minH = AppState.chatMinHeight, maxH = s.chatMaxHeight

        if phase.contains(.began) || phase.contains(.mayBegin) {
            chatPull = 0; chatPullReleased = false; chatPullLastDy = 0
            chatGestureStartedAtBottom = s.chatAtBottom
        }
        if phase.isEmpty && !momentum {
            let now = ProcessInfo.processInfo.systemUptime
            if now - chatLastWheelAt > 0.35 { chatGestureStartedAtBottom = s.chatAtBottom }
            chatLastWheelAt = now
        }

        // Dedos saíram: puxou o bastante (ou deu um peteleco) completa; senão volta à trava
        if phase.contains(.ended) || phase.contains(.cancelled) {
            let pull = chatPull
            chatPull = 0
            guard pull != 0, !chatPullReleased else { return pull != 0 }
            let flick = abs(chatPullLastDy) >= chatPullFlick && chatPullLastDy.sign == pull.sign
            if !phase.contains(.cancelled) && (abs(pull) >= chatPullThreshold * chatPullCommitFraction || flick) {
                releaseChatLock(toExpanded: pull > 0)
            } else {
                s.chatAnimate = true
                s.chatHeight = s.chatExpanded ? maxH : minH
            }
            return true
        }

        // Inércia depois de soltar a trava (ou durante o puxão) não rola o conteúdo
        if momentum { return chatPullReleased || chatPull != 0 }
        if chatPullReleased { return true }

        let stretching = !s.chatExpanded && (dy > 0 || chatPull > 0)
        let shrinking = s.chatExpanded && s.chatAtBottom && chatGestureStartedAtBottom
            && (dy < 0 || chatPull < 0)
        guard stretching || shrinking, maxH > minH + 1 else { return false }

        chatPull = stretching ? max(0, chatPull + dy) : min(0, chatPull + dy)
        chatPullLastDy = dy
        if abs(chatPull) >= chatPullThreshold {
            releaseChatLock(toExpanded: stretching)
        } else {
            // Elástico: no começo acompanha o dedo, depois cede cada vez menos
            let give = chatPullMaxGive * (1 - exp(-abs(chatPull) / chatPullMaxGive))
            s.chatHeight = stretching ? minH + give : maxH - give
        }
        if phase.isEmpty {
            // Roda de mouse não avisa quando termina: parou de girar, decide como o trackpad
            chatSnapBack?.cancel()
            let item = DispatchWorkItem { [weak self] in
                guard let self else { return }
                let pull = self.chatPull
                if pull != 0 && !self.chatPullReleased {
                    if abs(pull) >= self.chatPullThreshold * self.chatPullCommitFraction {
                        self.releaseChatLock(toExpanded: pull > 0)
                    } else {
                        s.chatAnimate = true
                        s.chatHeight = s.chatExpanded ? maxH : minH
                    }
                }
                self.chatPull = 0
                self.chatPullReleased = false
            }
            chatSnapBack = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: item)
        }
        return true
    }

    /// Solta a trava: vai ao outro ponto com mola, toque no trackpad e som.
    private func releaseChatLock(toExpanded expanded: Bool) {
        let s = AppState.shared
        chatPullReleased = true
        chatPull = 0
        s.chatExpanded = expanded
        s.chatAnimate = true
        s.chatHeight = expanded ? s.chatMaxHeight : AppState.chatMinHeight
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        SoundEngine.shared.play("blip")
    }

    /// O painel transparente tem 320 de altura; o chat esticado e as abas altas precisam de
    /// mais. Mantém o topo. `alturaIlha` 0 = nenhuma tela alta aberta.
    private func fitPanel(alturaIlha: CGFloat) {
        let padrao: CGFloat = 320
        let precisa = max(padrao, alturaIlha + 24)
        if alturaIlha > 0, precisa >= (window?.frame.height ?? padrao) {
            applyPanelHeight(precisa)
            return
        }
        // Encolhendo: espera a ilha fechar, senão corta a animação no meio.
        // Arrasto para o chat: mantém o tamanho, senão a área de soltar encolhe sob o cursor.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            let s = AppState.shared
            guard !s.arrastoParaChat else { return }
            let agora: CGFloat
            if s.mode == .expanded && s.view == .prompt { agora = s.chatMaxHeight }
            else if s.mode == .expanded && s.view.cresce,
                    let h = ElasticoIlha.alta(s.view, modulo: s.moduloAberto) ?? s.alturaAba { agora = h }
            else { agora = 0 }
            self?.applyPanelHeight(max(padrao, agora + 24))
        }
    }

    private func applyPanelHeight(_ needed: CGFloat) {
        guard let panel = window, abs(panel.frame.height - needed) > 0.5 else { return }
        var f = panel.frame
        f.origin.y += f.height - needed
        f.size.height = needed
        // Refaz o layout antes de desenhar: sem isso, por um quadro o conteúdo fica
        // ancorado embaixo e o topo da ilha "pula"
        panel.setFrame(f, display: false)
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
    }

    // MARK: - FSM wiring

    private func wireFSM() {
        fsm.collapseDelay = { AppState.shared.autoCloseInterval }
        fsm.holdOpen = { AppState.shared.fixado || AppState.shared.isPinned }
        // Antes o ajuste "Esconder depois de" não estava ligado: a compacta sumia sempre em 60 s
        fsm.hideDelay = { AppState.shared.absenceInterval }
        fsm.semAbrirNoHover = { Arbitro.shared.barraClicavel }
        // Não some com música tocando, sessão trabalhando ou alguma coisa esperando o Hugo
        fsm.holdVisible = {
            let s = AppState.shared
            return s.musicaTocando || !s.pendingApprovals.isEmpty
                || s.tasks.contains { $0.source == .claudeCode && !$0.parada
                    && [.working, .thinking, .searching, .approval, .question].contains($0.state) }
        }
        fsm.onTransition = { [weak self] from, to in
            guard let self else { return }
            switch to {
            case .hidden:
                self.setMode(.hidden)

            case .petit:
                if from == .saudacao {
                    // Fire interrupt first so canvas collapse starts before mode change
                    NotificationCenter.default.post(name: .greetingInterrupt, object: nil)
                } else if from == .hidden {
                    SoundEngine.shared.play("peek")
                }
                // setMode BEFORE changing view: onChange(of: state.view) guards on .expanded,
                // so setting view while already compact won't trigger a spurious open animation.
                self.setMode(.compact)
                if from == .saudacao { self.state.view = self.defaultView() }
                // Start 60s hide timer if mouse is not currently over the island
                if !self.wasInIsland { self.fsm.mouseLeft() }

            case .home:
                self.expand(to: self.viewAoAbrir())
                // Start collapse timer if mouse not currently hovering
                if !self.wasInIsland {
                    self.fsm.mouseLeft()
                }

            case .saudacao:
                self.expand(to: .greeting)
            }
        }

        // FSM observes greetComplete notification
        NotificationCenter.default.addObserver(
            forName: .greetComplete, object: nil, queue: .main
        ) { [weak self] _ in
            self?.fsm.greetComplete()
        }
    }

    // MARK: - Mouse: por evento; laço de 60 Hz só perto da ilha
    //
    // Antes era um timer de 60 Hz rodando sempre, mesmo com a ilha escondida. Agora o mouse
    // chega por evento (mexeu → atualiza) e o laço rápido só liga com o cursor perto da ilha
    // ou com botão apertado (arrasto de arquivo do Finder não manda evento de mouse para cá).
    // Parado longe da ilha: nenhum timer.

    /// Margem em volta da ilha que liga o laço rápido (pontos).
    private let margemLacoRapido: CGFloat = 90
    /// Quando o laço rápido pode desligar (só desliga depois de um respiro, para não piscar).
    private var lacoRapidoAte: CFTimeInterval = 0
    private var mouseMonitors: [Any] = []
    private var reavaliarAgendado = false

    private func startPolling() {
        let tipos: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged,
                                             .otherMouseDragged, .leftMouseDown, .leftMouseUp]
        // Eventos de outros apps (ilha transparente ao mouse)
        if let g = NSEvent.addGlobalMonitorForEvents(matching: tipos, handler: { [weak self] _ in
            Task { @MainActor in self?.mouseMexeu() }
        }) { mouseMonitors.append(g) }
        // Eventos do próprio painel
        if let l = NSEvent.addLocalMonitorForEvents(matching: tipos, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.mouseMexeu() }
            return event
        }) { mouseMonitors.append(l) }
        (window as? IslandPanel)?.acceptsMouseMovedEvents = true

        // A ilha mudou (tamanho, modo, arrasto) com o mouse parado: reavalia uma vez.
        stateSubscription = state.objectWillChange
            .sink { [weak self] _ in
                guard let self, !self.reavaliarAgendado else { return }
                self.reavaliarAgendado = true
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        self.reavaliarAgendado = false
                        self.mouseMexeu()
                    }
                }
            }
        pollFrame()
    }

    private func mouseMexeu() {
        pollFrame()
        if precisaLacoRapido() {
            lacoRapidoAte = CACurrentMediaTime() + 0.4
            ligarLacoRapido()
        }
    }

    /// Cursor perto da ilha, botão apertado ou arrasto em andamento.
    private func precisaLacoRapido() -> Bool {
        if inAttachDrag || attachDragStart != nil || state.fileDragOver || state.arrastoParaChat { return true }
        if NSEvent.pressedMouseButtons != 0 { return true }
        guard let panel = window as? IslandPanel else { return false }
        let r = panel.currentIslandFrame(nw: notchW, nh: notchH)
            .offsetBy(dx: panel.frame.minX, dy: panel.frame.minY)
            .insetBy(dx: -margemLacoRapido, dy: -margemLacoRapido)
        return r.contains(NSEvent.mouseLocation)
    }

    private func ligarLacoRapido() {
        guard frameTimer == nil else { return }
        let t = Timer(timeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.pollFrame()
                if self.precisaLacoRapido() {
                    self.lacoRapidoAte = CACurrentMediaTime() + 0.4
                } else if CACurrentMediaTime() > self.lacoRapidoAte {
                    self.frameTimer?.invalidate()
                    self.frameTimer = nil
                }
            }
        }
        t.tolerance = 0.002
        RunLoop.main.add(t, forMode: .common)
        frameTimer = t
    }

    private func pollFrame() {
        guard let panel = window as? IslandPanel else { return }

        let mouse = NSEvent.mouseLocation

        // Convert mouse to panel-local coords (macOS: origin bottom-left)
        let pf = panel.frame
        let local = CGPoint(x: mouse.x - pf.minX, y: mouse.y - pf.minY)

        // Island rect in panel coords
        let islandRect = panel.currentIslandFrame(nw: notchW, nh: notchH)
        let inIsland   = islandRect.insetBy(dx: -6, dy: -6).contains(local)

        // Toggle click-through
        // Arrastando arquivo: a janela toda aceita, senão a ilha muda de tamanho, o cursor fica
        // fora dela, o arrasto "sai", a ilha volta… e fica nisso sem parar.
        let shouldAcceptMouse = inIsland || inAttachDrag || attachDragStart != nil
            || state.fileDragOver || state.arrastoParaChat
        if panel.ignoresMouseEvents == shouldAcceptMouse {
            panel.ignoresMouseEvents = !shouldAcceptMouse
            if shouldAcceptMouse, let cv = panel.contentView {
                panel.invalidateCursorRects(for: cv)
            }
        }

        // Mouse in screen coords (Y flipped, origin top-left) for Bot look-at
        let screenH = panel.screen?.frame.height ?? NSScreen.main!.frame.height
        let newPos = CGPoint(x: mouse.x - (panel.screen?.frame.minX ?? 0), y: screenH - mouse.y)
        let cur = AppState.shared.mousePosition
        if abs(newPos.x - cur.x) > 1 || abs(newPos.y - cur.y) > 1 {
            AppState.shared.mousePosition = newPos
        }

        // Feed FSM hover enter/leave
        if inIsland && !wasInIsland {
            guard !inAttachDrag else { wasInIsland = inIsland; return }
            // If in coucou: tell greeting to stay open (tc → infinity)
            if fsm.state == .saudacao {
                NotificationCenter.default.post(name: .greetingHover, object: nil)
            }
            fsm.mouseEntered()
        }
        if !inIsland && wasInIsland {
            fsm.mouseLeft()
        }
        wasInIsland = inIsland

        // Bot-head hover (love emote)
        let overBot = state.mode == .expanded && state.stateOverride == nil && isBotHit(local)
        if overBot && !botHovering { botHoverIn(mousePos: NSEvent.mouseLocation) }
        if !overBot && botHovering { botHoverOut() }
        botHovering = overBot
        if botHovering {
            let m = NSEvent.mouseLocation
            let dist = hypot(m.x - botHoverStartPos.x, m.y - botHoverStartPos.y)
            if dist > 40 {
                botHoverStartPos = m
                botHoverTimer?.cancel()
                scheduleLoveTimer()
            }
        }

        // Ghost Homie follows cursor + window highlight during drag (60 Hz, no throttle)
        if inAttachDrag {
            updateDragGhost()
            updateWindowHighlight()
        }
    }

    /// O ponto (coordenadas do painel) cai no aviso clicável da barra — a faixa embaixo do
    /// notch, à direita do Homie (mesma posição de `IslandRootView`).
    private func cliqueNoAvisoDaBarra(_ local: CGPoint) -> Bool {
        guard Arbitro.shared.barraClicavel, barraNaIlha(state.mode),
              let panel = window as? IslandPanel else { return false }
        let ilha = panel.currentIslandFrame(nw: notchW, nh: notchH)
        let faixa = CGRect(x: ilha.minX + 80, y: ilha.minY, width: ilha.width - 80, height: 52)
        return faixa.contains(local)
    }

    private var lastMouse: CGPoint = .zero

    // MARK: - Bot-head hover (love emote — mirrors prototype botHover())

    private func botHoverIn(mousePos: CGPoint) {
        guard state.mode == .expanded, state.stateOverride == nil else { return }
        guard CACurrentMediaTime() - lastLoveTime > 6 else { return }
        botHoverStartPos = mousePos
        NotificationCenter.default.post(name: .botBlink, object: nil)
        NotificationCenter.default.post(name: .botSetTgEs, object: CGFloat(1.08))
        SoundEngine.shared.play("hover")
        scheduleLoveTimer()
    }

    private func botHoverOut() {
        botHoverTimer?.cancel()
        NotificationCenter.default.post(name: .botSetTgEs, object: CGFloat(1))
    }

    private func scheduleLoveTimer() {
        botHoverTimer?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.botHovering, self.state.stateOverride == nil else { return }
            guard CACurrentMediaTime() - self.lastLoveTime > 6 else { return }
            self.lastLoveTime = CACurrentMediaTime()
            NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.love)
            SoundEngine.shared.play("love")
        }
        botHoverTimer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.9, execute: item)
    }

    private func scheduleHover(after delay: TimeInterval, action: @escaping () -> Void) {
        hoverTimer?.cancel()
        let item = DispatchWorkItem(block: action)
        hoverTimer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    // MARK: - Mode transitions

    private func modeLevel(_ m: IslandMode) -> Int {
        switch m { case .hidden: return 0; case .compact: return 1; case .expanded: return 2 }
    }

    func setMode(_ mode: IslandMode) {
        let prev = state.mode
        guard mode != prev else { return }
        let shrinking = modeLevel(mode) < modeLevel(prev)
        let anim: Animation = shrinking
            ? .timingCurve(0.45, 0, 0.2, 1, duration: 0.34)
            : .spring(response: 0.5, dampingFraction: 0.72)
        withAnimation(anim) { state.mode = mode }
        if mode == .expanded { SoundEngine.shared.play("open") }
        if prev == .expanded { SoundEngine.shared.play("close"); state.isPinned = false }
    }

    func expand(to view: IslandView) {
        state.view = view
        if state.mode == .expanded {
            // Already expanded — just switch view
        } else {
            setMode(.expanded)
        }
        state.lastActivity = .now
        if fsm.state != .home && view != .greeting {
            fsm.syncExpanded()
            if !wasInIsland { fsm.mouseLeft() }
        }
    }

    func collapse() {
        state.isPinned = false
        state.chatHeight = AppState.chatMinHeight
        state.chatExpanded = false
        state.mostrarParadas = false
        finishedPinTimer?.cancel()
        // FSM vai junto para compacta, na hora
        fsm.forceCompact()
        setMode(.compact)
        window?.resignKey()
    }

    /// Toque duplo no Option (sem outra tecla no meio, até 0,35 s entre os dois).
    private func handleOptionTap(_ event: NSEvent) {
        guard state.moduloOptionDuplo else { return }
        guard event.type == .flagsChanged else { optionApertadoEm = 0; return }
        let mods = event.modifierFlags.intersection([.command, .control, .option, .shift, .function])
        // Só conta o Option sozinho sendo apertado (teclas 58 e 61: esquerdo e direito)
        guard [58, 61].contains(event.keyCode) else { optionApertadoEm = 0; return }
        guard mods == .option else { return }  // soltou: espera o próximo aperto
        let agora = ProcessInfo.processInfo.systemUptime
        if optionApertadoEm > 0, agora - optionApertadoEm < 0.35 {
            optionApertadoEm = 0
            alternarFixada()
        } else {
            optionApertadoEm = agora
        }
    }

    private func alternarFixada() {
        if state.mode == .expanded {
            // Como clicar fora; solta o fixar. Alerta esperando resposta continua aberto.
            state.fixado = false
            guard !state.isPinned else { return }
            collapse()
        } else {
            state.fixado = true
            if ultimaVista == .prompt {
                state.openChat(state.chatSelection)
                expand(to: .prompt)
            } else {
                expand(to: ultimaVista)
            }
            islandPanel.makeKey()
        }
    }

    // MARK: - Keyboard (Escape closes)

    private func startKeyMonitor() {
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                guard let self = self else { return }
                if event.keyCode == 53 { // Escape
                    if self.state.mode == .expanded && !self.state.isPinned {
                        self.collapse()
                    }
                }
            }
        }

        // Hook server expand requests (alerts only)
        NotificationCenter.default.addObserver(forName: .hookExpand, object: nil, queue: .main) { [weak self] note in
            guard let self, let view = note.object as? IslandView else { return }
            self.expand(to: view)
        }

        // Hook server compact reveal (non-alert work events: session start, tool use, etc.)
        NotificationCenter.default.addObserver(forName: .hookReveal, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.fsm.reveal()
        }

        // Collapse requests from views (OK button, etc.)
        NotificationCenter.default.addObserver(forName: .islandCollapse, object: nil, queue: .main) { [weak self] _ in
            self?.collapse()
        }

        // .botDizzy — posted by BotEngine.slap() on 3rd hit; show confused view + recover after 3.3s
        NotificationCenter.default.addObserver(forName: .botDizzy, object: nil, queue: .main) { [weak self] _ in
            self?.handleDizzy()
        }

        // Window attach drag.
        // Uses MainActor.assumeIsolated (synchronous) to avoid race with pollFrame().
        // Global mouseUp is the reliable fallback when cursor is outside our panel frame.
        NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self else { return event }
            MainActor.assumeIsolated {
                guard self.wasInIsland else { return }
                self.pendingIslandClick = true
                self.hoverTimer?.cancel()
                self.botHoverTimer?.cancel()
                self.botHovering = false
                // Drag only starts when clicking directly on the bot head
                guard self.isBotHit(event.locationInWindow) else { return }
                self.attachDragStart = NSEvent.mouseLocation
                // Post slap only when expanded
                guard self.state.mode == .expanded else { return }
                NotificationCenter.default.post(name: .triggerSlap, object: nil)
            }
            return event
        }
        NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged) { [weak self] event in
            guard let self else { return event }
            MainActor.assumeIsolated {
                guard let start = self.attachDragStart, !self.inAttachDrag else { return }
                let m = NSEvent.mouseLocation
                guard hypot(m.x - start.x, m.y - start.y) > 3 else { return }
                self.inAttachDrag = true
                NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.love)
                self.showDragGhost()
            }
            return event
        }

        // mouseUp — local (cursor still in panel) + global (cursor moved outside panel frame)
        let finishDrag: @Sendable () -> Void = { [weak self] in
            Task { @MainActor in
                guard let self, self.inAttachDrag else { return }
                let mouse = NSEvent.mouseLocation
                self.inAttachDrag = false
                self.attachDragStart = nil
                self.state.stateOverride = nil
                self.hideDragGhost()
                if let ctx = self.windowContextAtPoint(mouse) {
                    self.state.promptContext = ctx
                    SoundEngine.shared.play("approve")
                    NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
                    self.expand(to: .prompt)
                }
            }
        }
        NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            guard let self else { return event }
            MainActor.assumeIsolated {
                let hadPendingClick = self.pendingIslandClick
                let wasDragging     = self.inAttachDrag
                self.pendingIslandClick = false
                if wasDragging {
                    finishDrag()
                } else {
                    self.attachDragStart = nil
                    // Clique no aviso clicável da barra é do aviso: a ilha não abre por cima dele
                    if hadPendingClick && self.state.mode != .expanded
                        && !self.cliqueNoAvisoDaBarra(event.locationInWindow) {
                        self.fsm.click()   // FSM petit→home; onTransition calls expand(to:)
                    }
                }
            }
            return event
        }
        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { _ in
            finishDrag()
        }

        // Clique fora da ilha (em outro app): recolhe na hora, sem esperar o auto-close.
        // Fixada ou com alerta esperando resposta, fica.
        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.state.mode == .expanded,
                      !self.state.fixado, !self.state.isPinned,
                      self.attachDragStart == nil, !self.inAttachDrag else { return }
                self.collapse()
            }
        }

        // Option duas vezes: abre e fixa a ilha na última aba; aberta, recolhe (como clicar fora)
        let optionHandler: (NSEvent) -> Void = { [weak self] event in
            MainActor.assumeIsolated { self?.handleOptionTap(event) }
        }
        NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown], handler: optionHandler)
        NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { event in
            optionHandler(event)
            return event
        }

        // Cmd+V no chat: arquivo ou imagem copiados viram anexo; texto cola normal
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])
            guard mods == .command, event.charactersIgnoringModifiers?.lowercased() == "v" else { return event }
            let colou: Bool = MainActor.assumeIsolated {
                let s = AppState.shared
                guard s.mode == .expanded, s.view == .prompt, s.moduloAnexosChat else { return false }
                return FileDropHandler.colarNoChat(state: s)
            }
            return colou ? nil : event
        }

        // Global hotkey to show island
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                guard let self, self.state.hotkeyEnabled else { return }
                let pressed = event.modifierFlags.intersection([.command, .control, .option, .shift]).rawValue
                guard pressed == self.state.hotkeyFlags, event.keyCode == self.state.hotkeyCode else { return }
                if self.state.mode == .hidden || self.state.mode == .compact {
                    self.expand(to: .overview)
                }
            }
        }

        // Track last external app for window context capture
        let ourBundle = Bundle.main.bundleIdentifier ?? ""
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let self else { return }
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               app.bundleIdentifier != ourBundle {
                self.state.lastExternalApp = app
            }
        }
    }

    // MARK: - Drag ghost window (Homie follows cursor during drag)

    private func showDragGhost() {
        guard dragGhostPanel == nil else { return }
        // Same size as compact bot: diameter=20 → canvasSize≈33, scale 2× for grab comfort
        let canvasSize: CGFloat = 40 / 0.6      // ~67
        dragGhostSize = canvasSize

        let mouse = NSEvent.mouseLocation
        let s = dragGhostSize
        ghostCurrentOrigin = NSPoint(x: mouse.x - s/2, y: mouse.y - s/2)

        let panel = NSPanel(
            contentRect: NSRect(x: ghostCurrentOrigin.x, y: ghostCurrentOrigin.y, width: s, height: s),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 4)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.ignoresMouseEvents = true

        let hosting = NSHostingView(
            rootView: GhostBotView(canvasSize: canvasSize)
        )
        hosting.frame = NSRect(x: 0, y: 0, width: s, height: s)
        panel.contentView = hosting
        panel.alphaValue = 0
        panel.orderFront(nil)
        dragGhostPanel = panel
        AppState.shared.isDraggingBot = true

        // Fade + scale-in handled by GhostBotView SwiftUI animation;
        // also fade in the window itself for extra smoothness
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    private func hideDragGhost() {
        dragGhostPanel?.close()
        dragGhostPanel = nil
        highlightPanel?.close()
        highlightPanel = nil
        highlightWindowPid = 0
        AppState.shared.isDraggingBot = false
    }

    private func updateDragGhost() {
        guard let panel = dragGhostPanel else { return }
        let s = dragGhostSize
        let mouse = NSEvent.mouseLocation
        // Direct follow — bot is "held", no trailing lag
        ghostCurrentOrigin = NSPoint(x: mouse.x - s/2, y: mouse.y - s/2)
        panel.setFrameOrigin(ghostCurrentOrigin)
    }

    // MARK: - Window highlight overlay (white border on target window during drag)

    private func updateWindowHighlight() {
        let mouse = NSEvent.mouseLocation
        guard let (appKitBounds, pid) = windowBoundsAtScreenPoint(mouse) else {
            // Fade out + close if no window under cursor
            if let old = highlightPanel {
                let captured = old
                highlightPanel = nil
                highlightWindowPid = 0
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.12
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                    captured.animator().alphaValue = 0
                }, completionHandler: { captured.close() })
            }
            return
        }

        if pid == highlightWindowPid, let existing = highlightPanel {
            // Same window — just track position (windows rarely move, instant is fine)
            existing.setFrame(appKitBounds, display: false)
        } else {
            // New window — close old immediately, fade-in new
            highlightPanel?.close()
            highlightPanel = nil
            highlightWindowPid = pid

            let panel = NSPanel(
                contentRect: appKitBounds,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered, defer: false
            )
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 2)
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            panel.ignoresMouseEvents = true

            let hosting = NSHostingView(rootView:
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.75), lineWidth: 3)
                    .shadow(color: Color.white.opacity(0.5), radius: 16)
                    .padding(2)
                    .ignoresSafeArea()
            )
            hosting.frame = CGRect(origin: .zero, size: appKitBounds.size)
            hosting.autoresizingMask = [.width, .height]
            panel.contentView = hosting
            panel.alphaValue = 0
            panel.orderFront(nil)
            highlightPanel = panel

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.14
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        }
    }

    private func windowBoundsAtScreenPoint(_ screenPoint: NSPoint) -> (CGRect, pid_t)? {
        guard let screen = window?.screen ?? NSScreen.main else { return nil }
        let screenMaxY = screen.frame.maxY
        let cgPoint = CGPoint(x: screenPoint.x, y: screenMaxY - screenPoint.y)

        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        let ourBundle = Bundle.main.bundleIdentifier ?? ""
        for info in list {
            guard let b = info[kCGWindowBounds as String] as? [String: Any],
                  let x = b["X"] as? CGFloat, let y = b["Y"] as? CGFloat,
                  let w = b["Width"] as? CGFloat, let h = b["Height"] as? CGFloat else { continue }
            guard CGRect(x: x, y: y, width: w, height: h).contains(cgPoint) else { continue }
            let pid = info[kCGWindowOwnerPID as String] as? pid_t ?? 0
            guard let app = NSRunningApplication(processIdentifier: pid),
                  app.bundleIdentifier != ourBundle,
                  app.activationPolicy == .regular else { continue }
            // CG → AppKit: flip Y
            return (CGRect(x: x, y: screenMaxY - y - h, width: w, height: h), pid)
        }
        return nil
    }

    // MARK: - Window context at screen point (for drag-attach)

    private func windowContextAtPoint(_ screenPoint: NSPoint) -> PromptContext? {
        let screen = window?.screen ?? NSScreen.main
        // CGWindowList uses top-left origin; NSEvent.mouseLocation uses bottom-left
        let screenMaxY = screen?.frame.maxY ?? NSScreen.main!.frame.maxY
        let cgPoint = CGPoint(x: screenPoint.x, y: screenMaxY - screenPoint.y)

        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        let ourBundle = Bundle.main.bundleIdentifier ?? ""

        for info in windowList {
            guard let b = info[kCGWindowBounds as String] as? [String: Any],
                  let x = b["X"] as? CGFloat, let y = b["Y"] as? CGFloat,
                  let w = b["Width"] as? CGFloat, let h = b["Height"] as? CGFloat else { continue }
            guard CGRect(x: x, y: y, width: w, height: h).contains(cgPoint) else { continue }

            let pid = info[kCGWindowOwnerPID as String] as? pid_t ?? 0
            guard let app = NSRunningApplication(processIdentifier: pid),
                  app.bundleIdentifier != ourBundle,
                  app.activationPolicy == .regular else { continue }

            return WindowContextCapture.captureActive(from: app)
        }
        return nil
    }

    // MARK: - Coordinate conversion: window (AppKit, y-up) → island coords (y-down, 0,0 = island top-left)

    func windowToIsland(_ loc: CGPoint) -> CGPoint {
        let panelH = window?.frame.height ?? 320
        let panelW = window?.frame.width  ?? 720
        let islandLeft = (panelW - IslandConst.expandedWidth) / 2
        // Island is glued to panel top; its bottom in AppKit = panelH - 176
        return CGPoint(
            x: loc.x - islandLeft,
            y: panelH - loc.y                // AppKit y is from bottom; island y from top
        )
    }

    // MARK: - Helpers

    func defaultView() -> IslandView {
        state.tasks.isEmpty ? .empty : .overview
    }

    /// Ao abrir pela ilha compacta: com música tocando, o mouse do lado da capa
    /// (à direita do notch) abre direto na aba de música.
    private func viewAoAbrir() -> IslandView {
        guard state.mode == .compact, state.musicaTocando, let panel = window else { return defaultView() }
        let xLocal = NSEvent.mouseLocation.x - panel.frame.minX
        return xLocal > panel.frame.width / 2 ? .media : defaultView()
    }

    func baseMode() -> IslandMode {
        guard state.isPresent else { return .hidden }
        return (state.tasks.isEmpty && !state.musicaTocando) ? .hidden : .compact
    }

    // MARK: - Activity reset (call on any user interaction in island)

    func resetActivity() {
        state.lastActivity = .now
    }

    // MARK: - Finished task pin (5.2s)

    func pinForFinished(taskId: String) {
        state.isPinned = true
        finishedPinTimer?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.state.removeTask(id: taskId)
            self.state.isPinned = false
            self.collapse()
        }
        finishedPinTimer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.2, execute: item)
    }

    // MARK: - Dizzy recovery (triggered by BotEngine.slap via .botDizzy)

    private func handleDizzy() {
        let prevView = state.view
        state.stateOverride = .dizzy
        expand(to: .confused)
        confusedRecoveryTimer?.cancel()
        let recovery = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.state.stateOverride = nil
            if self.state.view == .confused {
                let fallback = self.state.tasks.isEmpty ? IslandView.empty : .overview
                self.state.view = (prevView == .confused) ? fallback : prevView
            }
            NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
        }
        confusedRecoveryTimer = recovery
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.3, execute: recovery)
    }

    // MARK: - Bot hit test (for slap trigger)

    private func isBotHit(_ windowPoint: CGPoint) -> Bool {
        let s = AppState.shared
        let panelH = window?.frame.height ?? 320
        let panelW = window?.frame.width  ?? 720
        let (islandW, fixedH) = islandSize(mode: s.mode, view: s.view,
                                            progress: s.uploadProgress, nw: notchW, nh: notchH)
        // Chat view resizes dynamically — must match IslandContainer.chatPromptHeight
        let islandH: CGFloat
        if s.mode == .expanded && s.view == .prompt {
            islandH = s.chatHeight
        } else {
            islandH = fixedH
        }
        let islandMinX = (panelW - islandW) / 2
        let (cx, cy, diameter, _) = botPosition(mode: s.mode, view: s.view,
                                                  islandW: islandW, islandH: islandH,
                                                  uploadProgress: s.uploadProgress)
        let radius = (diameter / 0.6) / 2
        // botPosition cy is from island TOP; panel AppKit coords have y=0 at bottom
        // island top in AppKit coords = panelH (island glued to top of panel/screen)
        let botX = islandMinX + cx
        let botY = panelH - cy
        let dx = windowPoint.x - botX
        let dy = windowPoint.y - botY
        return dx*dx + dy*dy <= radius * radius
    }

    // MARK: - Notch detection (static)

    static func notchScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
    }

    static func notchWidth(for screen: NSScreen) -> CGFloat {
        // Tela sem notch (espelhando na TV, tampa fechada): sem as áreas ao lado do notch a
        // conta daria a largura da tela inteira e a ilha virava uma barra preta
        guard let esq = screen.auxiliaryTopLeftArea?.width,
              let dir = screen.auxiliaryTopRightArea?.width else { return IslandConst.notchWidth }
        let w = screen.frame.width - esq - dir
        return w > 0 ? w : IslandConst.notchWidth
    }

    /// Tela mudou (espelhar, conectar monitor, fechar a tampa): volta para o notch, ou para o
    /// topo da tela principal, com as medidas da tela nova.
    private func reposicionarNaTela() {
        guard let panel = islandPanel, let screen = Self.notchScreen() ?? NSScreen.main else { return }
        notchW = Self.notchWidth(for: screen)
        notchH = Self.notchHeight(for: screen)
        panel.notchWidth = notchW
        panel.notchHeight = notchH
        AppState.shared.notchWidth = notchW
        AppState.shared.notchHeight = notchH
        let sf = screen.frame
        let f = panel.frame
        panel.setFrame(NSRect(x: sf.midX - f.width/2, y: sf.maxY - f.height, width: f.width, height: f.height),
                       display: true)
    }

    static func notchHeight(for screen: NSScreen) -> CGFloat {
        let h = screen.safeAreaInsets.top
        return h > 0 ? h : IslandConst.notchHeight
    }

    nonisolated func cleanup() {
        // Called explicitly before release if needed
    }
}

// MARK: - IslandPanel

final class IslandPanel: NSPanel {
    var notchWidth:  CGFloat = IslandConst.notchWidth
    var notchHeight: CGFloat = IslandConst.notchHeight

    override var canBecomeKey:  Bool { true }
    override var canBecomeMain: Bool { false }

    /// Allow panel to sit in the menu bar / notch area — don't let macOS push it down.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        return frameRect
    }

    func currentIslandFrame(nw: CGFloat, nh: CGFloat) -> CGRect {
        let s = AppState.shared
        let (w, fixedH) = islandSize(mode: s.mode, view: s.view,
                                      progress: s.uploadProgress, nw: nw, nh: nh)
        let h: CGFloat
        if s.mode == .expanded && s.view == .prompt {
            h = s.chatHeight
        } else {
            h = fixedH
        }
        return CGRect(x: (frame.width - w) / 2, y: frame.height - h, width: w, height: h)
    }
}

// MARK: - Ghost bot view (animated scale-in on appear)

struct GhostBotView: View {
    let canvasSize: CGFloat
    @State private var scale: CGFloat = 0.35

    var body: some View {
        BotCanvasView(state: AppState.shared)
            .frame(width: canvasSize, height: canvasSize)
            .scaleEffect(scale)
            .onAppear {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) {
                    scale = 1.0
                }
            }
    }
}

// MARK: - Notification names

extension Notification.Name {
    static let triggerEmote     = Notification.Name("notchBuddy.triggerEmote")
    static let triggerSlap      = Notification.Name("notchBuddy.triggerSlap")
    static let botDizzy         = Notification.Name("notchBuddy.botDizzy")
    static let botGreet         = Notification.Name("notchBuddy.botGreet")
    static let botBlink         = Notification.Name("notchBuddy.botBlink")
    static let botSetTgEs       = Notification.Name("notchBuddy.botSetTgEs")
    static let botGulp          = Notification.Name("notchBuddy.botGulp")
    static let botMorphTo       = Notification.Name("notchBuddy.botMorphTo")
    static let islandAction     = Notification.Name("notchBuddy.islandAction")
    static let islandCollapse   = Notification.Name("notchBuddy.islandCollapse")
    static let openFullSettings = Notification.Name("notchBuddy.openFullSettings")
    static let hookReveal       = Notification.Name("notchBuddy.hookReveal")
    // Greeting ↔ IslandWindowController
    static let greetComplete    = Notification.Name("notchBuddy.greetComplete")
    static let greetingHover    = Notification.Name("notchBuddy.greetingHover")
    static let greetingInterrupt = Notification.Name("notchBuddy.greetingInterrupt")
}

// MARK: - islandSize (takes real notch dimensions)

/// Ilha fechada com um sinal na barra (brilho/volume, aviso): cresce um pouco para baixo do notch.
@MainActor
func barraNaIlha(_ mode: IslandMode) -> Bool {
    mode != .expanded && Arbitro.shared.barra != nil
}

@MainActor
func islandSize(mode: IslandMode, view: IslandView,
                progress: Double = 0,
                nw: CGFloat = IslandConst.notchWidth,
                nh: CGFloat = IslandConst.notchHeight) -> (CGFloat, CGFloat) {
    if barraNaIlha(mode) { return (max(nw + 200, 380), nh + 58) }
    switch mode {
    case .hidden:   return (nw, nh)
    case .compact:  return (nw + 160 + Arbitro.shared.larguraExtraCanto, nh)
    case .expanded:
        // Aba de módulo que pediu mais altura (ex.: monitor de atividade do Sistema)
        if view.cresce, let p = AppState.shared.puxaoAba { return (IslandConst.expandedWidth, p) }
        if view.cresce, let h = AppState.shared.alturaAba { return (IslandConst.expandedWidth, h) }
        let layout = IslandConst.layout(view)
        return (IslandConst.expandedWidth, layout.height)
    }
}
