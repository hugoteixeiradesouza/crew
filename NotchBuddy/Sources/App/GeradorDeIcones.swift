import AppKit
import SwiftUI

// MARK: - Gerador de ícones (`Crew --icones <pasta do Assets.xcassets>`)
// O ícone do app ("Estúdio azul") e o da barra de menus são desenhados pelo mesmo código do
// Homie, então acompanham o personagem: mudou o desenho, roda de novo e os PNGs saem iguais a ele.
// Cada tamanho é desenhado direto no seu número de pixels, não reduzido de um grande: em 16 e
// 32 px o Homie entra no desenho simplificado (olho maior, aba grossa, sem gomos), como no notch.
// Não liga nada do app (hooks, pollers, ajustes): desenha, grava e sai.

@MainActor
enum GeradorDeIcones {
    static var requested: String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--icones"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    static func run(into pasta: String) {
        // Aparência padrão do Homie, não a dos ajustes de quem roda
        BotStyle.cap = true
        BotStyle.capRGB = (0x2B / 255.0, 0x2E / 255.0, 0x33 / 255.0)
        BotStyle.corBase = nil
        BotStyle.outline = false
        BotStyle.brows = false

        let app = pasta + "/AppIcon.appiconset/"
        let tamanhos: [(String, CGFloat)] = [
            ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32), ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
            ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256), ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
            ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
        ]
        for (nome, px) in tamanhos {
            gravar(Canvas { ctx, area in iconeDoApp(ctx: ctx, lado: area.width) }, largura: px, altura: px, em: app + nome)
        }
        // Barra de menus: 24 × 18 pt; os arquivos guardam o dobro (como os anteriores)
        let barra = pasta + "/MenuBarIcon.imageset/"
        for (nome, k) in [("menubar.png", 2.0), ("menubar@2x.png", 4.0), ("menubar@3x.png", 6.0)] as [(String, CGFloat)] {
            gravar(Canvas { ctx, _ in iconeDaBarra(ctx: ctx, escala: k) }, largura: 24 * k, altura: 18 * k, em: barra + nome)
        }
    }

    private static func gravar(_ desenho: some View, largura: CGFloat, altura: CGFloat, em caminho: String) {
        let r = ImageRenderer(content: desenho.frame(width: largura, height: altura))
        r.scale = 1
        r.isOpaque = false
        guard let img = r.cgImage, let png = NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("não foi possível desenhar \(caminho)\n".utf8))
            return
        }
        do { try png.write(to: URL(fileURLWithPath: caminho)); print(caminho) }
        catch { FileHandle.standardError.write(Data("não foi possível gravar \(caminho): \(error.localizedDescription)\n".utf8)) }
    }

    // MARK: Ícone do app — "Estúdio azul": o Homie branco, parado, no azulejo azul

    private static let azulDeCima: Cor3 = (0.33, 0.60, 1.0), azulDeBaixo: Cor3 = (0.17, 0.39, 0.93)

    /// Medidas em unidades de 1024 (grade do macOS: azulejo de 824, canto contínuo).
    private static func iconeDoApp(ctx: GraphicsContext, lado: CGFloat) {
        let u = lado / 1024
        let azulejo = Path(roundedRect: CGRect(x: 100 * u, y: 100 * u, width: 824 * u, height: 824 * u), cornerRadius: 186 * u, style: .continuous)

        // Sombra do azulejo (como no modelo da Apple)
        var s = ctx
        s.addFilter(.shadow(color: Color.black.opacity(0.30), radius: 10 * u, x: 0, y: 10 * u))
        s.fill(azulejo, with: .color(Tom.cor(azulDeBaixo)))

        var c = ctx
        c.clip(to: azulejo)
        c.fill(azulejo, with: .linearGradient(Gradient(colors: [Tom.cor(azulDeCima), Tom.cor(azulDeBaixo)]),
                                              startPoint: CGPoint(x: 0, y: 100 * u), endPoint: CGPoint(x: 0, y: 924 * u)))

        // nos tamanhos de lista (16/32 px) o personagem ocupa mais do azulejo
        let R = 250 * u * (lado <= 32 ? 1.12 : 1)
        let S = R / 0.3
        let cx = 556 * u, cy = 548 * u
        let rx = R * 1.14, ry = R * 0.88

        // chão: sombra de contato macia debaixo do corpo
        let chao = Tom.sombra(azulDeBaixo, 0.75)
        var ch = c
        ch.translateBy(x: cx, y: cy + ry * 1.02)
        ch.scaleBy(x: 1, y: 0.16)
        ch.fill(Path(ellipseIn: CGRect(x: -rx * 1.12, y: -rx * 1.12, width: rx * 2.24, height: rx * 2.24)),
                with: .radialGradient(Gradient(stops: [.init(color: Tom.cor(chao, 0.70), location: 0),
                                                       .init(color: Tom.cor(chao, 0.22), location: 0.50),
                                                       .init(color: Tom.cor(chao, 0), location: 1)]),
                                      center: .zero, startRadius: 0, endRadius: rx * 1.12))

        // O Homie parado (o motor centra em S/2, com o corpo 0,06 R abaixo)
        let e = BotEngine()
        e.nextBlink = .greatestFiniteMagnitude
        var h = c
        h.translateBy(x: cx - S / 2, y: cy - S / 2 - R * 0.06)
        e.draw(context: h, size: CGSize(width: S, height: S))

        // Brilho de vidro bem contido no alto do azulejo + fio de luz na borda
        c.fill(azulejo, with: .linearGradient(Gradient(colors: [Color.white.opacity(0.07), Color.white.opacity(0)]),
                                              startPoint: CGPoint(x: 0, y: 100 * u), endPoint: CGPoint(x: 0, y: 420 * u)))
        if lado >= 128 {
            c.stroke(azulejo, with: .linearGradient(Gradient(colors: [Color.white.opacity(0.38), Color.white.opacity(0.02)]),
                                                    startPoint: CGPoint(x: 0, y: 100 * u), endPoint: CGPoint(x: 0, y: 600 * u)), lineWidth: 5 * u)
        }
    }

    // MARK: Ícone da barra de menus — silhueta do Homie (imagem-modelo: só preto e transparência)

    /// Desenhado em pontos (24 × 18) e ampliado por `escala`: a silhueta é a do desenho pequeno
    /// do notch (aba curta e grossa, de ponta redonda) em qualquer densidade.
    private static func iconeDaBarra(ctx: GraphicsContext, escala: CGFloat) {
        let R: CGFloat = 8.2, rx = R * 1.14, ry = R * 0.88
        let preto = GraphicsContext.Shading.color(.black)
        var c = ctx
        c.scaleBy(x: escala, y: escala)
        c.translateBy(x: 12 + R * 0.20, y: 9 + R * 0.10)

        let bone = FormaBone(R: R, rx: rx, ry: ry, yaw: 0)
        c.fill(bone.aba, with: preto)
        c.fill(bone.copa, with: preto)

        // Corpo, com um fio de respiro debaixo do boné e os olhos vazados
        var corpo = c
        corpo.clip(to: Path(CGRect(x: -rx * 1.2, y: bone.baseY + R * 0.13, width: rx * 2.4, height: ry * 2)))
        corpo.fill(BotEngine().botPath(rx: rx, ry: ry, morph: 0, R: R), with: preto)
        corpo.blendMode = .destinationOut
        for lado in [-1.0, 1.0] as [CGFloat] {
            var o = corpo
            o.translateBy(x: lado * R * 0.40, y: R * 0.22)
            o.rotate(by: .radians(0.30))
            let w = R * 0.30, h = R * 0.56
            o.fill(Path(roundedRect: CGRect(x: -w / 2, y: -h / 2, width: w, height: h), cornerRadius: w / 2), with: preto)
        }
    }
}
