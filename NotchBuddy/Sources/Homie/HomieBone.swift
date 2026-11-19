// Boné do Homie ("Polido"): snapback de tecido virado para trás, sem traço de nanquim.
// A copa é uma meia-esfera sobre a cabeça, projetada pelo mesmo giro dos olhos (yaw): os gomos
// são meridianos, o fecho fica na frente da esfera (estreita em perspectiva e some ao ir para
// trás) e a aba é uma placa curta e grossa presa atrás, de ponta redonda.
// Abaixo de ~44 pt o desenho simplifica: aba mais grossa, sem gomos, sem fecho, sem botão.
//
// Custo por quadro: a geometria (`FormaBone`) é guardada pelo motor e só refeita quando o
// tamanho ou o giro mudam; os degradês que dependem da cor do boné ficam em `TonsDoBone`,
// refeitos só quando a cor muda nos ajustes; os demais são constantes.
import SwiftUI

/// Geometria do boné para um tamanho e um giro.
struct FormaBone {
    let R: CGFloat, rx: CGFloat, ry: CGFloat, yaw: CGFloat
    let baseY: CGFloat, topY: CGFloat, halfW: CGFloat
    let detalhe: Detalhe

    let copa: Path
    let aba: Path
    /// Caixa da aba, para os degradês.
    let abaRect: CGRect
    let abaPontaEsq: Bool
    let faixa: CGRect
    /// Gomos (só no desenho cheio; vazio nos menores).
    let costuras: Path
    /// Fecho (só no desenho cheio e enquanto está de frente).
    let fecho: Fecho?
    let botao: CGRect

    struct Fecho {
        let abertura: Path, arco: Path
        let tira: CGRect, caixa: CGRect
        let frente: CGFloat
    }

    func serve(R: CGFloat, rx: CGFloat, ry: CGFloat, yaw: CGFloat) -> Bool {
        self.R == R && self.rx == rx && self.ry == ry && self.yaw == yaw
    }

    init(R: CGFloat, rx: CGFloat, ry: CGFloat, yaw: CGFloat) {
        self.R = R; self.rx = rx; self.ry = ry; self.yaw = yaw
        let detalhe = Detalhe(R: R)
        self.detalhe = detalhe
        let baseY = -ry * 0.40
        let dy = ry * 1.22
        let phi0 = asin(min(1, -baseY / dy))
        let dx = rx * 1.02 / cos(phi0)
        let ringR = dx * cos(phi0)
        let bandH = R * 0.13
        let halfW = rx * 1.02
        let topY = -ry * 1.22
        self.baseY = baseY; self.topY = topY; self.halfW = halfW

        // Copa: larga, de topo achatado
        var dome = Path()
        dome.move(to: CGPoint(x: -halfW, y: baseY))
        dome.addCurve(to: CGPoint(x: 0, y: topY),
                      control1: CGPoint(x: -halfW, y: -ry * 1.00), control2: CGPoint(x: -rx * 0.62, y: topY))
        dome.addCurve(to: CGPoint(x: halfW, y: baseY),
                      control1: CGPoint(x: rx * 0.62, y: topY), control2: CGPoint(x: halfW, y: -ry * 1.00))
        dome.closeSubpath()
        copa = dome

        // Aba: placa horizontal presa atrás, à esquerda (azimute −118°), vista de lado
        let a = -118 * CGFloat.pi / 180 + yaw
        let L = rx * 0.42, hw = R * 0.26
        let sa = sin(a), ca = abs(hw * cos(a))
        let x0 = min(ringR * sa, (ringR + L) * sa) - ca
        let x1 = max(ringR * sa, (ringR + L) * sa) + ca
        let rootX = ringR * sa
        let ponta = abs(x0 - rootX) > abs(x1 - rootX)
        // A ponta nunca passa da tela do desenho (meia largura = R/0,6)
        let limite = R * 1.61
        let tipX = max(-limite, min(limite, ponta ? x0 : x1)), innerX = ponta ? x1 : x0
        let esp = R * 0.155 * detalhe.aba
        let topo = baseY - esp
        let s: CGFloat = ponta ? -1 : 1
        // Afina até a ponta, que é redonda (placa vista de lado, não um risco). O topo fica reto,
        // na linha da faixa; é a face de baixo que sobe — aba reta, levemente empinada.
        let espPonta = esp * 0.70
        let rr = min(espPonta * 0.5, abs(tipX - innerX) * 0.5)
        var b = Path()
        b.move(to: CGPoint(x: innerX, y: topo))
        b.addLine(to: CGPoint(x: tipX - s * rr, y: topo))
        b.addQuadCurve(to: CGPoint(x: tipX, y: topo + rr), control: CGPoint(x: tipX, y: topo))
        b.addQuadCurve(to: CGPoint(x: tipX - s * rr, y: topo + espPonta), control: CGPoint(x: tipX, y: topo + espPonta))
        b.addLine(to: CGPoint(x: innerX, y: baseY))
        b.closeSubpath()
        aba = b
        abaRect = CGRect(x: min(tipX, innerX), y: topo, width: abs(tipX - innerX), height: esp)
        abaPontaEsq = ponta

        faixa = CGRect(x: -dx, y: baseY - bandH, width: dx * 2, height: bandH)
        botao = CGRect(x: -R * 0.075, y: topY - R * 0.035, width: R * 0.15, height: R * 0.075)

        // Gomos: seis meridianos; só o trecho virado para nós
        var seams = Path()
        if detalhe == .cheio {
            for k in 0..<6 {
                let theta = CGFloat(k) * .pi / 3 + .pi / 6 + yaw
                if cos(theta) < 0 { continue }
                var started = false
                for i in 0...24 {
                    let phi = phi0 + (CGFloat.pi / 2 - phi0) * CGFloat(i) / 24
                    // a costura que cai bem na borda da silhueta não é desenhada (dobrava o contorno)
                    if cos(theta) * cos(phi) > 0.04 {
                        let pt = CGPoint(x: dx * sin(theta) * cos(phi), y: -dy * sin(phi))
                        if !started { seams.move(to: pt); started = true } else { seams.addLine(to: pt) }
                    } else { started = false }
                }
            }
        }
        costuras = seams

        // Fecho na frente da esfera: abertura em arco e a tira de pressão
        let frente = cos(yaw)
        if frente > 0.12, detalhe == .cheio {
            let cx = ringR * sin(yaw)
            let gw = R * 0.46 * frente, gh = R * 0.25
            let g = CGRect(x: cx - gw / 2, y: baseY - gh, width: gw, height: gh)
            var arco = Path()
            arco.move(to: CGPoint(x: g.minX, y: g.maxY))
            arco.addLine(to: CGPoint(x: g.minX, y: g.minY + gh * 0.52))
            arco.addCurve(to: CGPoint(x: g.maxX, y: g.minY + gh * 0.52),
                          control1: CGPoint(x: g.minX, y: g.minY - gh * 0.16), control2: CGPoint(x: g.maxX, y: g.minY - gh * 0.16))
            arco.addLine(to: CGPoint(x: g.maxX, y: g.maxY))
            var ab = arco; ab.closeSubpath()
            fecho = Fecho(abertura: ab, arco: arco,
                          tira: CGRect(x: g.minX, y: g.maxY - gh * 0.50, width: gw, height: gh * 0.34),
                          caixa: g, frente: frente)
        } else {
            fecho = nil
        }
    }
}

/// Cores e degradês do boné para a cor escolhida nos ajustes.
struct TonsDoBone {
    let rgb: (Double, Double, Double)
    let aba: Gradient, copa: Gradient, faixa: Gradient, tira: Gradient, botao: Gradient
    let debrum: Color, ilhosClaro: Color

    init(_ rgb: (Double, Double, Double)) {
        self.rgb = rgb
        let cap: Cor3 = (CGFloat(rgb.0), CGFloat(rgb.1), CGFloat(rgb.2))
        // Aba: face de cima clara, canto de baixo escuro (tem espessura, não é um risco)
        aba = Gradient(stops: [.init(color: Tom.cor(Tom.claro(cap, 0.30)), location: 0),
                               .init(color: Tom.cor(Tom.claro(cap, 0.12)), location: 0.42),
                               .init(color: Tom.cor(Tom.escuro(cap, 0.18)), location: 0.56),
                               .init(color: Tom.cor(Tom.escuro(cap, 0.40)), location: 1)])
        copa = Gradient(stops: [.init(color: Tom.cor(Tom.claro(cap, 0.24)), location: 0),
                                .init(color: Tom.cor(cap), location: 0.55),
                                .init(color: Tom.cor(Tom.escuro(cap, 0.22)), location: 1)])
        faixa = Gradient(colors: [Tom.cor(Tom.escuro(cap, 0.30)), Tom.cor(Tom.escuro(cap, 0.42))])
        tira = Gradient(colors: [Tom.cor(Tom.claro(cap, 0.10)), Tom.cor(Tom.escuro(cap, 0.25))])
        botao = Gradient(colors: [Tom.cor(Tom.claro(cap, 0.36)), Tom.cor(Tom.claro(cap, 0.08))])
        debrum = Tom.cor(Tom.escuro(cap, 0.55))
        ilhosClaro = Tom.cor(Tom.claro(cap, 0.62))
    }
}

@MainActor
enum HomieBone {
    private static var tonsGuardados: TonsDoBone?
    /// Tons na cor do boné dos ajustes (a cor é uma só para todos os Homies).
    static var tons: TonsDoBone {
        let rgb = BotStyle.capRGB
        if let t = tonsGuardados, t.rgb == rgb { return t }
        let t = TonsDoBone(rgb)
        tonsGuardados = t
        return t
    }

    // Luzes e sombras que não dependem da cor
    private static let sombraRaizAba = Gradient(colors: [Color.black.opacity(0.38), Color.black.opacity(0)])
    private static let fioDaAba = Gradient(colors: [Color.white.opacity(0.30), Color.white.opacity(0)])
    private static let volumeCopa = Gradient(stops: [.init(color: Color.black.opacity(0), location: 0),
                                                     .init(color: Color.black.opacity(0), location: 0.50),
                                                     .init(color: Color.black.opacity(0.42), location: 1)])
    private static let brilhoTecido = Gradient(colors: [Color.white.opacity(0.13), Color.white.opacity(0)])
    private static let recorteCopa = Gradient(stops: [.init(color: Color.white.opacity(0.36), location: 0),
                                                      .init(color: Color.white.opacity(0.10), location: 0.6),
                                                      .init(color: Color.white.opacity(0), location: 1)])
    private static let nanquim = Color(red: 0.04, green: 0.04, blue: 0.05)

    /// Desenha o boné (origem no centro do corpo). `corpo` dá a cor que aparece pela abertura do fecho.
    static func pintar(ctx: inout GraphicsContext, forma f: FormaBone, corpo: TonsDoCorpo) {
        let t = tons
        let R = f.R, rx = f.rx
        let cheio = f.detalhe == .cheio
        let contorno = BotStyle.outline
        let traco = StrokeStyle(lineWidth: R * 0.065, lineCap: .round, lineJoin: .round)

        // --- Aba
        let ar = f.abaRect
        if contorno { ctx.stroke(f.aba, with: .color(nanquim), style: traco) }
        ctx.fill(f.aba, with: .linearGradient(t.aba, startPoint: CGPoint(x: 0, y: ar.minY), endPoint: CGPoint(x: 0, y: ar.maxY)))
        // some para dentro da copa (sombra da cabeça sobre a raiz da aba)
        let raizX = f.abaPontaEsq ? ar.maxX : ar.minX, pontaX = f.abaPontaEsq ? ar.minX : ar.maxX
        ctx.fill(f.aba, with: .linearGradient(sombraRaizAba, startPoint: CGPoint(x: raizX, y: 0),
                                              endPoint: CGPoint(x: raizX + (pontaX - raizX) * 0.45, y: 0)))
        if cheio {
            // fio de luz na quina de cima (nos tamanhos pequenos não chega a um ponto de tela)
            var naAba = ctx
            naAba.clip(to: f.aba)
            naAba.stroke(f.aba, with: .linearGradient(fioDaAba, startPoint: CGPoint(x: 0, y: ar.minY), endPoint: CGPoint(x: 0, y: ar.midY)),
                         lineWidth: R * 0.035)
        }

        // --- Copa
        ctx.fill(f.copa, with: .linearGradient(t.copa, startPoint: CGPoint(x: 0, y: f.topY), endPoint: CGPoint(x: 0, y: f.baseY)))
        // volume: os lados caem em sombra
        ctx.fill(f.copa, with: .radialGradient(volumeCopa, center: CGPoint(x: -rx * 0.12, y: f.topY * 0.9), startRadius: 0, endRadius: R * 1.55))
        // brilho de tecido, largo e fosco, no alto à esquerda
        ctx.fill(f.copa, with: .radialGradient(brilhoTecido, center: CGPoint(x: -rx * 0.30, y: f.topY * 0.82), startRadius: 0, endRadius: R * 0.62))

        var d = ctx
        d.clip(to: f.copa)

        // --- Gomos: costura em baixo-relevo (sulco escuro + fio de luz ao lado)
        if cheio {
            d.stroke(f.costuras.offsetBy(dx: R * 0.014, dy: 0), with: .color(Color.white.opacity(0.07)),
                     style: StrokeStyle(lineWidth: R * 0.014, lineCap: .round))
            d.stroke(f.costuras, with: .color(Color.black.opacity(0.34)), style: StrokeStyle(lineWidth: R * 0.016, lineCap: .round))
        }

        // --- Faixa
        let fr = f.faixa
        d.fill(Path(fr), with: .linearGradient(t.faixa, startPoint: CGPoint(x: 0, y: fr.minY), endPoint: CGPoint(x: 0, y: fr.maxY)))
        if cheio {
            d.fill(Path(CGRect(x: fr.minX, y: fr.minY - R * 0.012, width: fr.width, height: R * 0.014)), with: .color(Color.black.opacity(0.30)))
            d.fill(Path(CGRect(x: fr.minX, y: fr.minY + R * 0.002, width: fr.width, height: R * 0.012)), with: .color(Color.white.opacity(0.07)))
        }

        // --- Fecho: a abertura mostra a cor do corpo (na sombra do boné), com a tira de pressão
        if let fe = f.fecho {
            d.fill(fe.abertura, with: .color(corpo.fechoFundo))
            var g = d
            g.clip(to: fe.abertura)
            g.fill(Path(fe.caixa.insetBy(dx: -R * 0.02, dy: -R * 0.05)), with: .linearGradient(
                corpo.fechoSombra, startPoint: CGPoint(x: 0, y: fe.caixa.minY),
                endPoint: CGPoint(x: 0, y: fe.caixa.minY + fe.caixa.height * 0.62)))
            g.fill(Path(fe.tira), with: .linearGradient(t.tira, startPoint: CGPoint(x: 0, y: fe.tira.minY), endPoint: CGPoint(x: 0, y: fe.tira.maxY)))
            let hr = R * 0.019
            var furos = Path()
            for i in 0..<3 {
                let hx = fe.tira.minX + fe.tira.width * (0.20 + CGFloat(i) * 0.20)
                furos.addEllipse(in: CGRect(x: hx - hr * fe.frente, y: fe.tira.midY - hr, width: 2 * hr * fe.frente, height: 2 * hr))
            }
            g.fill(furos, with: .color(Color.black.opacity(0.45)))
            let hx = fe.tira.minX + fe.tira.width * 0.80
            g.fill(Path(ellipseIn: CGRect(x: hx - hr * fe.frente, y: fe.tira.midY - hr, width: 2 * hr * fe.frente, height: 2 * hr)),
                   with: .color(t.ilhosClaro))
            // borda da abertura: debrum escuro
            d.stroke(fe.arco, with: .color(t.debrum), style: StrokeStyle(lineWidth: R * 0.034, lineCap: .butt, lineJoin: .round))
        }

        // --- Luz de recorte no alto da copa: é o que desenha o boné contra o fundo escuro
        d.stroke(f.copa, with: .linearGradient(recorteCopa, startPoint: CGPoint(x: 0, y: f.topY), endPoint: CGPoint(x: 0, y: f.baseY)),
                 lineWidth: R * (cheio ? 0.035 : 0.09))

        // --- Contorno de nanquim (ajuste "Contorno") e botão do topo
        if contorno { ctx.stroke(f.copa, with: .color(nanquim), style: traco) }
        if cheio {
            ctx.fill(Path(ellipseIn: f.botao), with: .linearGradient(t.botao, startPoint: CGPoint(x: 0, y: f.botao.minY), endPoint: CGPoint(x: 0, y: f.botao.maxY)))
        }
    }
}

extension BotEngine {
    /// Boné do Homie para quem desenha o personagem fora do motor (entrada, envio de arquivos),
    /// para ele ser o mesmo em todo lugar. rx/ry = meia largura/altura do corpo; `pele` = cor do
    /// corpo, que aparece pela abertura do fecho.
    static func drawHomieCap(ctx: inout GraphicsContext, R: CGFloat, rx: CGFloat, ry: CGFloat, yaw: CGFloat,
                             pele: Cor3 = (0.925, 0.929, 0.945)) {
        HomieBone.pintar(ctx: &ctx, forma: FormaBone(R: R, rx: rx, ry: ry, yaw: yaw), corpo: TonsDoCorpo(pele))
    }

    /// Boné do motor: a geometria só é refeita quando o tamanho ou o giro mudam.
    func drawCap(ctx: inout GraphicsContext, R: CGFloat, rx: CGFloat, ry: CGFloat) {
        // giro arredondado a 0,002 rad: não se vê, e o boné parado não é refeito a cada quadro
        let giro = (yaw * 500).rounded() / 500
        let forma: FormaBone
        if let f = formaBone, f.serve(R: R, rx: rx, ry: ry, yaw: giro) { forma = f } else {
            forma = FormaBone(R: R, rx: rx, ry: ry, yaw: giro)
            formaBone = forma
        }
        HomieBone.pintar(ctx: &ctx, forma: forma, corpo: tonsDoCorpoAgora())
    }
}
