import AppKit

// Tempo por app em foco — só por evento do macOS, nenhum timer:
//   • troca de app (didActivateApplication) fecha o trecho do anterior e abre o do novo;
//   • tela apagada, Mac dormindo, sessão trocada ou tela bloqueada pausam (fecham o trecho);
//   • acordou/desbloqueou: abre um trecho novo com o app da frente.
// O próprio Crew não conta. Trecho que atravessa a meia-noite é dividido entre os dois dias.

@MainActor
final class FocoApps {
    /// (bundle id, nome, segundos, início do trecho)
    typealias Entrega = @MainActor (String, String, Double, Date) -> Void

    private let entregar: Entrega
    private var atual: (bundle: String, nome: String, inicio: Date)?
    private var pausas: Set<String> = []
    private var pausado: Bool { !pausas.isEmpty }

    /// Nunca contam como uso: a tela de bloqueio, o protetor de tela e o próprio Crew.
    static let ignorados: Set<String> = ["com.apple.loginwindow", "com.apple.ScreenSaver.Engine",
                                         "com.apple.ScreenSaver.Engine.legacyScreenSaver"]

    /// A sessão está com a tela bloqueada agora? (vale ao ligar e ao acordar)
    static func telaBloqueada() -> Bool {
        guard let d = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        if let b = d["CGSSessionScreenIsLocked"] as? Bool { return b }
        return ((d["CGSSessionScreenIsLocked"] as? Int) ?? 0) != 0
    }
    private var observadores: [(NotificationCenter, NSObjectProtocol)] = []

    init(entregar: @escaping Entrega) { self.entregar = entregar }

    func ligar() {
        guard observadores.isEmpty else { return }
        let ws = NSWorkspace.shared.notificationCenter
        let dist = DistributedNotificationCenter.default()
        func ouvir(_ c: NotificationCenter, _ n: Notification.Name, _ f: @escaping @MainActor (Notification) -> Void) {
            let o = c.addObserver(forName: n, object: nil, queue: .main) { nota in
                let caixa = UncheckedSendable(nota)
                MainActor.assumeIsolated { f(caixa.valor) }
            }
            observadores.append((c, o))
        }
        ouvir(ws, NSWorkspace.didActivateApplicationNotification) { [weak self] n in
            let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            // Trocar de app é o Hugo usando o Mac: se alguma "volta" se perdeu, destrava aqui
            if let self, self.pausado, !Self.telaBloqueada(),
               let b = app?.bundleIdentifier, !Self.ignorados.contains(b) { self.pausas.removeAll() }
            self?.trocou(para: app)
        }
        // Cada motivo de pausa tem o seu par; só volta a contar quando TODOS saíram. Antes, a tela
        // acender (ainda bloqueada) retomava a contagem e o loginwindow somava horas.
        let pares: [(Notification.Name, Notification.Name, String, NotificationCenter)] = [
            (NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification, "tela", ws),
            (NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification, "sono", ws),
            (NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification, "sessao", ws),
            (Notification.Name("com.apple.screenIsLocked"), Notification.Name("com.apple.screenIsUnlocked"), "bloqueio", dist),
        ]
        for (para, volta, motivo, c) in pares {
            ouvir(c, para) { [weak self] _ in self?.pausar(motivo) }
            ouvir(c, volta) { [weak self] _ in self?.retomar(motivo) }
        }
        pausas = Self.telaBloqueada() ? ["bloqueio"] : []
        trocou(para: NSWorkspace.shared.frontmostApplication)
    }

    func desligar() {
        fechar()
        for (c, o) in observadores { c.removeObserver(o) }
        observadores.removeAll()
    }

    /// O app da frente agora e há quanto tempo (o trecho em curso ainda não foi entregue).
    var trechoAtual: (bundle: String, nome: String, segundos: Double)? {
        atual.map { ($0.bundle, $0.nome, Date().timeIntervalSince($0.inicio)) }
    }

    /// Entrega o trecho em curso sem encerrar o foco (antes de gravar ou resumir).
    func consolidar() {
        guard let a = atual else { return }
        fechar()
        atual = (a.bundle, a.nome, Date())
    }

    private func trocou(para app: NSRunningApplication?) {
        fechar()
        guard !pausado, let app, let bundle = app.bundleIdentifier,
              bundle != Bundle.main.bundleIdentifier, !Self.ignorados.contains(bundle) else { return }
        atual = (bundle, app.localizedName ?? bundle, Date())
    }

    private func pausar(_ motivo: String) {
        fechar()
        pausas.insert(motivo)
    }

    private func retomar(_ motivo: String) {
        guard pausas.remove(motivo) != nil else { return }
        // Acordou mas a tela continua bloqueada: segue pausado até o desbloqueio
        if pausas.isEmpty, Self.telaBloqueada() { pausas.insert("bloqueio") }
        guard !pausado else { return }
        trocou(para: NSWorkspace.shared.frontmostApplication)
    }

    private func fechar() {
        guard let a = atual else { return }
        atual = nil
        let fim = Date()
        let cal = Calendar.current
        var inicio = a.inicio
        // Divide na meia-noite
        while !cal.isDate(inicio, inSameDayAs: fim),
              let meiaNoite = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: inicio)) {
            entregar(a.bundle, a.nome, meiaNoite.timeIntervalSince(inicio), inicio)
            inicio = meiaNoite
        }
        let s = fim.timeIntervalSince(inicio)
        if s >= 1 { entregar(a.bundle, a.nome, s, inicio) }
    }
}
