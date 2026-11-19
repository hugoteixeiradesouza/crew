// Corpo do Homie ("Polido"): o boneco de volume com luz de estúdio — cor inteira do estado,
// luz de cima, sombra na própria cor (não preto), sombra do boné no rosto e uma luz de recorte
// embaixo que o destaca do fundo escuro. O mesmo código pinta o Homie do notch, o da entrada
// (GreetingCanvasView) e o do envio de arquivos (UploadCanvasView).
//
// Custo por quadro: os degradês que dependem da cor ficam prontos em `TonsDoCorpo` e só são
// refeitos quando a cor muda (o motor guarda o último); os que não dependem são constantes.
// Nada de desfoque: a luz de recorte são poucas passadas de traço, menos quanto menor o desenho.
import SwiftUI

/// Degradês do corpo para uma cor. Montar custa pouco, mas não precisa ser a cada quadro.
struct TonsDoCorpo {
    let cor: Cor3
    /// Cor local: mais clara em cima (luz), mais funda embaixo.
    let base: Gradient
    /// Volume: a borda de baixo e dos lados entra em sombra da própria cor.
    let volume: Gradient
    /// Sombra que o boné faz no rosto.
    let sombraBone: Gradient
    /// O que aparece pela abertura do fecho do boné: o corpo, na sombra.
    let fechoFundo: Color
    let fechoSombra: Gradient

    init(_ c: Cor3) {
        cor = c
        base = Gradient(stops: [.init(color: Tom.cor(Tom.claro(c, 0.26)), location: 0),
                                .init(color: Tom.cor(c), location: 0.52),
                                .init(color: Tom.cor(Tom.sombra(c, 0.20)), location: 1)])
        let v = Tom.sombra(c, 0.5)
        volume = Gradient(stops: [.init(color: Tom.cor(v, 0), location: 0),
                                  .init(color: Tom.cor(v, 0), location: 0.58),
                                  .init(color: Tom.cor(v, 0.40), location: 1)])
        let s = Tom.sombra(c, 0.55)
        sombraBone = Gradient(stops: [.init(color: Tom.cor(s, 0.62), location: 0),
                                      .init(color: Tom.cor(s, 0.30), location: 0.35),
                                      .init(color: Tom.cor(s, 0), location: 1)])
        fechoFundo = Tom.cor(Tom.sombra(c, 0.22))
        let f = Tom.sombra(c, 0.7)
        fechoSombra = Gradient(colors: [Tom.cor(f, 0.75), Tom.cor(f, 0)])
    }
}

@MainActor
enum HomieCorpo {
    /// Cor de base do corpo: o branco de sempre ou a cor escolhida nos ajustes.
    static var corBase: Cor3 {
        BotStyle.corBase.map { (CGFloat($0.0), CGFloat($0.1), CGFloat($0.2)) } ?? (0.925, 0.929, 0.945)
    }

    /// Luz de frente, larga e fraca (dá barriga ao rosto sem virar "bola de vidro").
    private static let luzDeFrente = Gradient(colors: [Color.white.opacity(0.16), Color.white.opacity(0)])

    /// Luz de recorte: passadas largas e fracas que se somam na borda de baixo. O desenho de
    /// referência usa 9; nos tamanhos menores a soma na borda é a mesma com menos passadas
    /// (a maciez entre elas some em menos de um ponto de tela).
    private static func recorte(_ a: Double) -> Gradient {
        Gradient(stops: [.init(color: Color.white.opacity(0), location: 0), .init(color: Color.white.opacity(a), location: 1)])
    }
    private static let recorte9 = recorte(0.050), recorte5 = recorte(0.088), recorte3 = recorte(0.143), recorte2 = recorte(0.206)

    /// Pinta o corpo em `path` (centrado na origem; rx/ry = meia largura/altura).
    static func pintar(ctx: inout GraphicsContext, path: Path, R: CGFloat, rx: CGFloat, ry: CGFloat,
                       tons: TonsDoCorpo, sombraDoBone: Bool) {
        // 1. Cor local
        ctx.fill(path, with: .linearGradient(tons.base, startPoint: CGPoint(x: 0, y: -ry), endPoint: CGPoint(x: 0, y: ry)))
        // 2. Volume
        ctx.fill(path, with: .radialGradient(tons.volume, center: CGPoint(x: 0, y: -ry * 0.42), startRadius: 0, endRadius: R * 1.62))
        // 3. Luz de frente
        ctx.fill(path, with: .radialGradient(luzDeFrente, center: CGPoint(x: rx * 0.10, y: ry * 0.12), startRadius: 0, endRadius: R * 0.95))
        // 4. Sombra do boné no rosto: é ela que assenta o boné na cabeça
        if sombraDoBone {
            let y0 = -ry * 0.40
            ctx.fill(path, with: .linearGradient(tons.sombraBone, startPoint: CGPoint(x: 0, y: y0), endPoint: CGPoint(x: 0, y: y0 + R * 0.30)))
        }
        // 5. Luz de recorte embaixo (rebatida): separa a silhueta do fundo escuro
        let (n, g): (Int, Gradient) = R >= 40 ? (9, recorte9) : R >= 13.5 ? (5, recorte5) : R >= 6.6 ? (3, recorte3) : (2, recorte2)
        var d = ctx
        d.clip(to: path)
        for i in 0..<n {
            let k = CGFloat(i) / CGFloat(n - 1)
            d.stroke(path, with: .linearGradient(g, startPoint: CGPoint(x: 0, y: ry * (0.05 + 0.45 * (1 - k))), endPoint: CGPoint(x: 0, y: ry * 1.05)),
                     lineWidth: R * (0.03 + 0.21 * k))
        }
    }

    /// Mini-Homies (um por sessão, na cor dela): o mesmo material, só a cor local — no tamanho
    /// deles o resto não aparece, e são vários desenhados por quadro.
    static func pintarMini(ctx: inout GraphicsContext, path: Path, ry: CGFloat, tons: TonsDoCorpo) {
        ctx.fill(path, with: .linearGradient(tons.base, startPoint: CGPoint(x: 0, y: -ry), endPoint: CGPoint(x: 0, y: ry)))
    }

    /// Mão: o mesmo material do corpo.
    static func pintarMao(ctx: inout GraphicsContext, path: Path, meiaAltura: CGFloat, tons: TonsDoCorpo) {
        ctx.fill(path, with: .linearGradient(tons.base, startPoint: CGPoint(x: 0, y: -meiaAltura), endPoint: CGPoint(x: 0, y: meiaAltura)))
    }
}

extension BotEngine {
    /// Cor do corpo agora: a base (branco ou a cor escolhida) puxada para a cor do estado.
    /// O estado é dono da cor inteira (antes pintava só a metade de baixo). Mini-Homies e
    /// integrações têm cor fixa.
    func corDoCorpo() -> Cor3 {
        if let bc = bodyColor, let k = bc.components, k.count >= 3 { return (k[0], k[1], k[2]) }
        return Tom.mix(HomieCorpo.corBase, col, min(1, tint * 1.12) * (1 - morph))
    }

    /// Degradês do corpo na cor de agora; refeitos só quando a cor muda.
    func tonsDoCorpoAgora() -> TonsDoCorpo {
        // arredondada a 1/1024: a cor chega ao alvo por aproximação e, sem isso, mudaria
        // (sem se ver) a cada quadro por um bom tempo
        func q(_ v: CGFloat) -> CGFloat { (v * 1024).rounded() / 1024 }
        let k = corDoCorpo()
        let c: Cor3 = (q(k.0), q(k.1), q(k.2))
        if let t = tonsCorpo, t.cor == c { return t }
        let t = TonsDoCorpo(c)
        tonsCorpo = t
        return t
    }
}
