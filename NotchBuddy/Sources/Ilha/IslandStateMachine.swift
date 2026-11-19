import Foundation

/// Pure 4-state FSM for island open/close logic.
/// No AppKit / AppState dependencies — communicates via `onTransition`.
@MainActor
final class IslandStateMachine {

    enum State: Equatable {
        case hidden   // island invisible (notch size)
        case petit    // compact island (notch + ears)
        case home     // expanded, overview
        case saudacao   // expanded, greeting animation
    }

    private(set) var state: State = .hidden

    /// Fired on every transition: (from, to)
    var onTransition: ((State, State) -> Void)?

    /// Tempo para fechar depois que o mouse sai (o ajuste "Auto-close"). Sem isso, usa homeToPetitDelay.
    var collapseDelay: (() -> TimeInterval)?
    /// true = ilha fixada (pin ou alerta esperando resposta): não fecha sozinha.
    var holdOpen: (() -> Bool)?
    /// true = a ilha não pode sumir (música tocando): compacta fica, não vai para escondida.
    var holdVisible: (() -> Bool)?

    /// home → petit delay (seconds). Override for debug.
    var homeToPetitDelay: TimeInterval = 15
    /// petit → hidden delay (seconds). Override for debug.
    var petitToHiddenDelay: TimeInterval = 60
    /// Tempo para a compacta sumir (o ajuste "Esconder depois de"). Sem isso, usa petitToHiddenDelay.
    var hideDelay: (() -> TimeInterval)?
    /// coucou → petit delay after greeting animation ends (no hover). ~0.6s syncs with canvas collapse.
    var greetAutoCollapseDelay: TimeInterval = 0.6
    /// coucou → petit delay when mouse is hovering over the greeting.
    var greetHoverCollapseDelay: TimeInterval = 10

    private var petitHideWork: DispatchWorkItem?
    private var homeCollapseWork: DispatchWorkItem?
    private var greetCollapseWork: DispatchWorkItem?
    private var hoverOpenWork: DispatchWorkItem?

    /// Mouse parado sobre a ilha por este tempo → abre. Curto, mas evita abrir
    /// só de passar o cursor a caminho da barra de menu.
    var hoverOpenDelay: TimeInterval = 0.18
    /// Verdadeiro → passar o mouse não abre (aviso clicável na barra); abre só com clique.
    var semAbrirNoHover: (() -> Bool)?

    // MARK: – Inputs

    /// App launched or debug "launch greeting"
    func launch() {
        cancelTimers()
        transition(to: .saudacao)
    }

    /// Mouse entered the island notch area
    func mouseEntered() {
        switch state {
        case .hidden:
            cancelTimers()
            transition(to: .petit)
            scheduleHoverOpen()
        case .petit:
            petitHideWork?.cancel()
            petitHideWork = nil
            scheduleHoverOpen()
        case .home:
            homeCollapseWork?.cancel()
            homeCollapseWork = nil
        case .saudacao:
            // Mouse hovering during greeting — cancel short auto-collapse, extend to hover delay
            scheduleGreetCollapse(delay: greetHoverCollapseDelay)
        }
    }

    /// Mouse left the island notch area
    func mouseLeft() {
        hoverOpenWork?.cancel(); hoverOpenWork = nil
        switch state {
        case .hidden:
            break
        case .petit:
            schedulePetitHide()
        case .home:
            scheduleHomeCollapse()
        case .saudacao:
            // Interrupt greeting immediately → compact (overrides 10s auto-collapse)
            greetCollapseWork?.cancel(); greetCollapseWork = nil
            transition(to: .petit)
        }
    }

    /// A ilha abriu por fora da FSM (alerta de sessão, menu, upload): alinha o estado
    /// sem disparar transição, senão o hover e o clique ficam sem efeito depois.
    func syncExpanded() {
        guard state != .home else { return }
        cancelTimers()
        state = .home
    }

    /// A ilha recolheu por fora (clique fora, OK, Esc): vai para compacta na hora.
    /// Antes ficava "aberta" na FSM até o auto-close, e o hover nesse meio-tempo travava.
    func forceCompact() {
        guard state == .home || state == .saudacao else { return }
        cancelTimers()
        transition(to: .petit)
    }

    /// Compact island clicked
    func click() {
        guard state == .petit else { return }
        cancelTimers()
        transition(to: .home)
    }

    /// Greeting animation finished (called at T.end ≈ 4.60 s).
    /// Schedules auto-collapse. Does not override a longer hover timer already running.
    func greetComplete() {
        guard state == .saudacao else { return }
        // If mouse entered before this fires (hover timer already running), don't override it
        if greetCollapseWork == nil {
            scheduleGreetCollapse(delay: greetAutoCollapseDelay)
        }
    }

    private func scheduleGreetCollapse(delay: TimeInterval) {
        greetCollapseWork?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.state == .saudacao else { return }
            self.transition(to: .petit)
        }
        greetCollapseWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    /// Non-alert work event: show compact from hidden (HookServer reveal)
    func reveal() {
        guard state == .hidden else { return }
        cancelTimers()
        transition(to: .petit)
        schedulePetitHide()
    }

    // MARK: – Timers

    private func scheduleHoverOpen() {
        hoverOpenWork?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.state == .petit else { return }
            self.hoverOpenWork = nil
            if self.semAbrirNoHover?() == true { return }
            self.transition(to: .home)
        }
        hoverOpenWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + hoverOpenDelay, execute: item)
    }

    private func schedulePetitHide() {
        petitHideWork?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.state == .petit else { return }
            if self.holdVisible?() == true { self.schedulePetitHide(); return }
            self.transition(to: .hidden)
        }
        petitHideWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + (hideDelay?() ?? petitToHiddenDelay), execute: item)
    }

    private func scheduleHomeCollapse() {
        homeCollapseWork?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.state == .home else { return }
            // Fixada/alerta pendente: confere de novo depois, para fechar quando soltar
            if self.holdOpen?() == true { self.scheduleHomeCollapse(); return }
            self.transition(to: .petit)
        }
        homeCollapseWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + (collapseDelay?() ?? homeToPetitDelay), execute: item)
    }

    func cancelTimers() {
        petitHideWork?.cancel();    petitHideWork = nil
        homeCollapseWork?.cancel(); homeCollapseWork = nil
        greetCollapseWork?.cancel(); greetCollapseWork = nil
        hoverOpenWork?.cancel(); hoverOpenWork = nil
    }

    private func transition(to new: State) {
        guard new != state else { return }
        let old = state
        state = new
        onTransition?(old, new)
    }

}
