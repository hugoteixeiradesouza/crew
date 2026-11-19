import AppKit
import SwiftUI

// Elástico de telas que crescem — o mesmo comportamento do chat, num lugar só.
//   • Fechada: rolar para baixo estica a ilha seguindo o dedo (cede cada vez menos); puxou o
//     bastante (ou deu um peteleco), trava aberta com mola, toque no trackpad e som; soltou
//     antes, volta.
//   • Aberta: rolar para cima com a lista no fim (ou sem lista para rolar) encolhe do mesmo jeito
//     e trava fechada. No meio da lista, a rolagem é da lista.
// Para dar isso a uma tela: aba de módulo → `alturaExpandida` (e, se quiser, `expandirAba` /
// `recolherAba`) no módulo; outra tela → um caso em `alvo()`. Listas roláveis dentro dela
// usam `.rolagemDaIlha()` para avisar quando chegaram ao fim.

@MainActor
final class ElasticoIlha {
    static let shared = ElasticoIlha()

    /// O painel precisa caber a altura máxima antes de a ilha crescer (o controlador ajusta).
    var prepararPainel: ((CGFloat) -> Void)?

    struct Alvo {
        let baixa: CGFloat
        let alta: CGFloat
        let aberta: Bool
        let abrir: () -> Void
        let fechar: () -> Void
    }

    /// Altura máxima de uma tela que cresce (nil = não cresce). O painel fica desse tamanho
    /// enquanto ela está aberta — como no chat: redimensionar a janela no meio do gesto dá tranco.
    static func alta(_ view: IslandView, modulo: String?) -> CGFloat? {
        let s = AppState.shared
        switch view {
        case .modulo:
            return Registro.shared.modulo(modulo)?.alturaExpandida.map { min($0, s.alturaAbaMaxima) }
        case .sugestao:
            return min(DiarioServico.alturaPergunta, s.alturaAbaMaxima)
        default:
            return nil
        }
    }

    /// A tela na frente tem versão expandida? Qual altura e como abrir/fechar.
    func alvo() -> Alvo? {
        let s = AppState.shared
        guard s.mode == .expanded else { return nil }
        let baixa = IslandConst.layout(s.view).height
        switch s.view {
        case .modulo:
            guard let m = Registro.shared.modulo(s.moduloAberto), let h = m.alturaExpandida else { return nil }
            return Alvo(baixa: baixa, alta: min(h, s.alturaAbaMaxima), aberta: s.alturaAba != nil,
                        abrir: { m.expandirAba() }, fechar: { m.recolherAba() })
        case .sugestao:
            return Alvo(baixa: baixa, alta: min(DiarioServico.alturaPergunta, s.alturaAbaMaxima), aberta: s.alturaAba != nil,
                        abrir: { DiarioServico.shared.detalharPergunta() }, fechar: { DiarioServico.shared.recolherPergunta() })
        default:
            return nil
        }
    }

    // Os mesmos números do chat
    private let forca: CGFloat = 70
    private let fracaoParaCompletar: CGFloat = 0.45
    private let peteleco: CGFloat = 14
    private let cedeMax: CGFloat = 60

    private var puxao: CGFloat = 0
    private var ultimoPasso: CGFloat = 0
    private var soltou = false
    private var comecouNoFim = true
    private var ultimaRoda: TimeInterval = 0
    private var voltaRoda: DispatchWorkItem?

    /// true = o gesto é do elástico (não rola o conteúdo).
    func rolar(dy: CGFloat, phase: NSEvent.Phase, momentum: Bool, ponto: NSPoint, janela: NSWindow?) -> Bool {
        let s = AppState.shared
        guard let a = alvo(), a.alta > a.baixa + 1 else { puxao = 0; return false }

        if phase.contains(.began) || phase.contains(.mayBegin) {
            puxao = 0; soltou = false; ultimoPasso = 0
            comecouNoFim = Self.noFim(ponto, janela)
        }
        if phase.isEmpty && !momentum {
            let agora = ProcessInfo.processInfo.systemUptime
            if agora - ultimaRoda > 0.35 { comecouNoFim = Self.noFim(ponto, janela); soltou = false }
            ultimaRoda = agora
        }

        // Dedos saíram: puxou o bastante (ou peteleco) completa; senão volta à trava
        if phase.contains(.ended) || phase.contains(.cancelled) {
            let p = puxao
            puxao = 0
            guard p != 0, !soltou else { return p != 0 }
            let flick = abs(ultimoPasso) >= peteleco && ultimoPasso.sign == p.sign
            if !phase.contains(.cancelled) && (abs(p) >= forca * fracaoParaCompletar || flick) {
                travar(a, aberta: p > 0)
            } else {
                s.puxaoAba = nil   // volta com mola
            }
            return true
        }

        // Inércia depois de soltar a trava (ou durante o puxão) não rola o conteúdo
        if momentum { return soltou || puxao != 0 }
        if soltou { return true }

        let esticando = !a.aberta && (dy > 0 || puxao > 0)
        let encolhendo = a.aberta && comecouNoFim && (puxao < 0 || (dy < 0 && Self.noFim(ponto, janela)))
        guard esticando || encolhendo else { return false }

        puxao = esticando ? max(0, puxao + dy) : min(0, puxao + dy)
        ultimoPasso = dy
        if abs(puxao) >= forca {
            travar(a, aberta: esticando)
        } else {
            // Elástico: no começo acompanha o dedo, depois cede cada vez menos
            let cede = cedeMax * (1 - exp(-abs(puxao) / cedeMax))
            s.puxaoAba = esticando ? a.baixa + cede : a.alta - cede
        }
        if phase.isEmpty {
            // Roda de mouse não avisa quando termina: parou de girar, decide como o trackpad
            voltaRoda?.cancel()
            let item = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let p = self.puxao
                    if p != 0 && !self.soltou {
                        if abs(p) >= self.forca * self.fracaoParaCompletar { self.travar(a, aberta: p > 0) }
                        else { AppState.shared.puxaoAba = nil }
                    }
                    self.puxao = 0
                }
            }
            voltaRoda = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: item)
        }
        return true
    }

    /// A lista sob o cursor está no fim (ou não há lista rolável ali)? Lê a rolagem de verdade
    /// (a ScrollView do SwiftUI é um NSScrollView por baixo), sem depender de aviso da tela.
    static func noFim(_ ponto: NSPoint, _ janela: NSWindow?) -> Bool {
        guard let raiz = janela?.contentView else { return true }
        var v = raiz.hitTest(raiz.convert(ponto, from: nil))
        while let atual = v, !(atual is NSScrollView) { v = atual.superview }
        // Fora de lista (resumo, topo, cabeçalho): é "pegador" da ilha — recolhe
        guard let sv = v as? NSScrollView, let doc = sv.documentView else { return true }
        let visivel = sv.contentView.bounds
        let altura = doc.frame.height
        guard altura > visivel.height + 1 else { return true }   // cabe inteira: nada a rolar
        return doc.isFlipped ? visivel.maxY >= altura - 2 : visivel.minY <= 2
    }

    /// Solta a trava: vai ao outro ponto com mola, toque no trackpad e som.
    private func travar(_ a: Alvo, aberta: Bool) {
        soltou = true
        puxao = 0
        AppState.shared.abaNoFim = true
        aberta ? a.abrir() : a.fechar()
        AppState.shared.puxaoAba = nil
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        SoundEngine.shared.play("blip")
    }
}

extension View {
    /// Lista rolável dentro de uma tela que cresce: avisa a ilha quando está no fim (ou não rola),
    /// para rolar para cima recolher só aí — como o chat.
    func rolagemDaIlha() -> some View {
        // Lista curta não "puxa" sozinha (o rebote do macOS parecia arrastar o cartão)
        scrollBounceBehavior(.basedOnSize)
        .onScrollGeometryChange(for: Bool.self) { g in
            g.contentOffset.y + g.containerSize.height >= g.contentSize.height - 2
        } action: { _, noFim in
            AppState.shared.abaNoFim = noFim
        }
        .onDisappear { AppState.shared.abaNoFim = true }
    }
}
