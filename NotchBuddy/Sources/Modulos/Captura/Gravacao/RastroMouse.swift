import AppKit

// O rastro do mouse de uma gravação: onde o ponteiro estava e onde houve clique, com o tempo do
// vídeo. Vai num JSON ao lado do MP4 e é o que deixa a edição dar zoom sozinha nos cliques.
// Só posição e clique — nenhuma tecla é lida. Só existe enquanto uma gravação roda: parado, não
// há timer nem monitor de eventos.

/// O que foi gravado, para situar o mouse dentro do vídeo.
struct QuadroGravado: Sendable {
    var alvo: AlvoGravacao
    /// Retângulo gravado, em pontos, na área de trabalho inteira (origem no canto de cima à
    /// esquerda da tela principal, y para baixo).
    var retangulo: CGRect
    var cursorNoVideo: Bool
}

struct RastroGravado: Sendable {
    struct Amostra: Sendable {
        var t: TimeInterval
        var x: CGFloat
        var y: CGFloat
    }

    struct Clique: Sendable {
        var t: TimeInterval
        var x: CGFloat
        var y: CGFloat
        var direito: Bool
    }

    /// Tempos no relógio de `ProcessInfo.systemUptime`; posições na área de trabalho inteira.
    var amostras: [Amostra]
    var cliques: [Clique]
    var fim: TimeInterval

    /// O JSON que vai ao lado do vídeo. `inicio` é o zero do vídeo no mesmo relógio. Posições
    /// viram fração do quadro gravado (0–1, origem em cima à esquerda).
    func json(quadro: QuadroGravado, inicio: TimeInterval) -> String {
        let r = quadro.retangulo
        let w = max(1, r.width), h = max(1, r.height)
        func n(_ v: Double, _ casas: Int) -> String { String(format: "%.\(casas)f", locale: Locale(identifier: "en_US_POSIX"), v) }
        func ponto(_ x: CGFloat, _ y: CGFloat) -> (String, String) { (n((x - r.minX) / w, 4), n((y - r.minY) / h, 4)) }

        // O que veio antes do zero do vídeo (a contagem, o macOS preparando) fica de fora; a
        // última posição de antes vira a posição no tempo zero.
        var linhas: [String] = []
        linhas.reserveCapacity(amostras.count)
        if let antes = amostras.last(where: { $0.t <= inicio }) {
            let p = ponto(antes.x, antes.y)
            linhas.append("[0.000,\(p.0),\(p.1)]")
        }
        for a in amostras where a.t > inicio {
            let p = ponto(a.x, a.y)
            linhas.append("[\(n(a.t - inicio, 3)),\(p.0),\(p.1)]")
        }
        let toques = cliques.filter { $0.t >= inicio }.map { c -> String in
            let p = ponto(c.x, c.y)
            return "{\"t\":\(n(c.t - inicio, 3)),\"x\":\(p.0),\"y\":\(p.1),\"botao\":\"\(c.direito ? "direito" : "esquerdo")\"}"
        }
        return """
        {
          "versao": 1,
          "alvo": "\(quadro.alvo.rawValue)",
          "quadro": {"x": \(n(r.minX, 1)), "y": \(n(r.minY, 1)), "largura": \(n(r.width, 1)), "altura": \(n(r.height, 1))},
          "cursorNoVideo": \(quadro.cursorNoVideo),
          "duracao": \(n(max(0, fim - inicio), 3)),
          "cliques": [\(toques.joined(separator: ","))],
          "mouse": [\(linhas.joined(separator: ","))]
        }

        """
    }
}

@MainActor
final class RastroMouse {
    /// Amostras por segundo (só entram as que mudaram de lugar).
    static let ritmo: Double = 30
    /// Teto de amostras guardadas (umas 3 h de mouse em movimento sem parar).
    private static let teto = 320_000

    private var timer: Timer?
    private var monitores: [Any] = []
    private var amostras: [RastroGravado.Amostra] = []
    private var cliques: [RastroGravado.Clique] = []
    private var ultima: CGPoint?
    /// Houve leituras iguais à última (mouse parado) desde a amostra guardada.
    private var parado: TimeInterval?

    var rodando: Bool { timer != nil }

    func comecar() {
        guard timer == nil else { return }
        amostras = []
        cliques = []
        ultima = nil
        parado = nil
        ler()
        let t = Timer(timeInterval: 1 / Self.ritmo, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.ler() }
        }
        t.tolerance = 0.008
        RunLoop.main.add(t, forMode: .common)
        timer = t
        // Só os botões do mouse. O monitor global não vê o que vai para o próprio Crew: o local cobre.
        let botoes: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: botoes, handler: { [weak self] e in
            let (t, direito) = (e.timestamp, e.type != .leftMouseDown)
            MainActor.assumeIsolated { self?.clique(t, direito) }
        }) { monitores.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: botoes, handler: { [weak self] e in
            let (t, direito) = (e.timestamp, e.type != .leftMouseDown)
            MainActor.assumeIsolated { self?.clique(t, direito) }
            return e
        }) { monitores.append(m) }
    }

    /// Para de ler e devolve o que juntou.
    func terminar() -> RastroGravado {
        timer?.invalidate()
        timer = nil
        for m in monitores { NSEvent.removeMonitor(m) }
        monitores = []
        let agora = ProcessInfo.processInfo.systemUptime
        if let u = ultima, parado != nil { amostras.append(.init(t: agora, x: u.x, y: u.y)) }
        let r = RastroGravado(amostras: amostras, cliques: cliques, fim: agora)
        amostras = []
        cliques = []
        ultima = nil
        parado = nil
        return r
    }

    /// Posição do ponteiro na área de trabalho inteira, com a origem em cima (como no vídeo).
    private static func ponteiro() -> CGPoint {
        let p = NSEvent.mouseLocation
        let altura = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: p.x, y: altura - p.y)
    }

    private func ler() {
        let agora = ProcessInfo.processInfo.systemUptime
        let p = Self.ponteiro()
        if let u = ultima, abs(u.x - p.x) < 0.5, abs(u.y - p.y) < 0.5 {
            parado = agora
            return
        }
        guard amostras.count < Self.teto else { return }
        // Voltou a andar depois de parado: marca até quando ficou no lugar, para quem ligar os
        // pontos com uma reta não inventar um movimento lento.
        if let u = ultima, let ate = parado { amostras.append(.init(t: ate, x: u.x, y: u.y)) }
        parado = nil
        ultima = p
        amostras.append(.init(t: agora, x: p.x, y: p.y))
    }

    private func clique(_ t: TimeInterval, _ direito: Bool) {
        guard timer != nil, cliques.count < 20_000 else { return }
        let p = Self.ponteiro()
        cliques.append(.init(t: t, x: p.x, y: p.y, direito: direito))
    }
}
