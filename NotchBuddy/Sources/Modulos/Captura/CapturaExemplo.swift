import CoreGraphics
import CoreText
import Foundation

// Imagens de exemplo desenhadas em código (nenhuma captura de tela de verdade): servem para as
// cenas do modo de capturas (`Crew --capturas`) e para conferir o OCR e as anotações.

enum CapturaExemplo {
    enum Tipo: CaseIterable, Sendable { case editor, painel, terminal, recado }

    static func imagem(_ tipo: Tipo) -> CGImage? {
        switch tipo {
        case .editor: editor()
        case .painel: painel()
        case .terminal: terminal()
        case .recado: recado()
        }
    }

    /// Anotações de exemplo (uma de cada ferramenta), proporcionais à imagem.
    static func anotacoes(para imagem: CGImage) -> [Anotacao] {
        let w = CGFloat(imagem.width), h = CGFloat(imagem.height)
        let e = DesenhoAnotacoes.espessura(para: CGSize(width: w, height: h))
        let p = CorAnotacao.paleta
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * w, y: y * h) }
        return [
            Anotacao(ferramenta: .tarja, cor: p[0], pontos: [pt(0.285, 0.76), pt(0.40, 0.87)], espessura: e),
            Anotacao(ferramenta: .retangulo, cor: p[3], pontos: [pt(0.04, 0.57), pt(0.37, 0.70)], espessura: e),
            Anotacao(ferramenta: .seta, cor: p[0], pontos: [pt(0.80, 0.30), pt(0.50, 0.19)], espessura: e),
            Anotacao(ferramenta: .traco, cor: p[2],
                     pontos: (0...40).map { pt(0.60 + CGFloat($0) * 0.007, 0.56 + sin(CGFloat($0) / 3) * 0.04) }, espessura: e),
            Anotacao(ferramenta: .texto, cor: p[1], pontos: [pt(0.66, 0.31)], texto: "Confirmar isto", espessura: e),
        ]
    }

    // MARK: Peças

    private static func tela(_ w: Int, _ h: Int, _ desenho: (CGContext, CGFloat, CGFloat) -> Void) -> CGImage? {
        guard let espaco = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: espaco,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // Origem em cima à esquerda, como se lê
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        desenho(ctx, CGFloat(w), CGFloat(h))
        return ctx.makeImage()
    }

    private static func cor(_ hex: UInt32, _ alfa: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: alfa)
    }

    private static func caixa(_ ctx: CGContext, _ r: CGRect, _ c: CGColor, raio: CGFloat = 0) {
        ctx.setFillColor(c)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: min(raio, r.width / 2), cornerHeight: min(raio, r.height / 2), transform: nil))
        ctx.fillPath()
    }

    private static func texto(_ ctx: CGContext, _ s: String, _ x: CGFloat, _ y: CGFloat, _ tamanho: CGFloat,
                              _ c: CGColor, mono: Bool = false, forte: Bool = false) {
        let fonte = mono
            ? CTFontCreateWithName("Menlo-Regular" as CFString, tamanho, nil)
            : (CTFontCreateUIFontForLanguage(forte ? .emphasizedSystem : .system, tamanho, nil)
                ?? CTFontCreateWithName("Helvetica" as CFString, tamanho, nil))
        let atributos: [CFString: Any] = [kCTFontAttributeName: fonte, kCTForegroundColorAttributeName: c]
        let linha = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, s as CFString, atributos as CFDictionary)!)
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        ctx.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(linha, ctx)
    }

    private static func barraDeJanela(_ ctx: CGContext, _ w: CGFloat, titulo: String, fundo: CGColor, tinta: CGColor) {
        caixa(ctx, CGRect(x: 0, y: 0, width: w, height: 56), fundo)
        for (i, c) in [0xFF5F57, 0xFEBC2E, 0x28C840].enumerated() {
            ctx.setFillColor(cor(UInt32(c)))
            ctx.fillEllipse(in: CGRect(x: 24 + CGFloat(i) * 26, y: 20, width: 16, height: 16))
        }
        texto(ctx, titulo, 130, 36, 19, tinta, forte: true)
    }

    // MARK: Imagens

    private static func editor() -> CGImage? {
        tela(1280, 800) { ctx, w, h in
            caixa(ctx, CGRect(x: 0, y: 0, width: w, height: h), cor(0x1B1D23))
            barraDeJanela(ctx, w, titulo: "Pedido.swift — loja", fundo: cor(0x25282F), tinta: cor(0xC9CDD4))
            caixa(ctx, CGRect(x: 0, y: 56, width: 250, height: h - 56), cor(0x20232A))
            for (i, nome) in ["Pedido.swift", "Cliente.swift", "Estoque.swift", "Entrega.swift", "Testes"].enumerated() {
                if i == 0 { caixa(ctx, CGRect(x: 12, y: 84, width: 226, height: 34), cor(0x3B82F6, 0.28), raio: 7) }
                texto(ctx, nome, 30, 108 + CGFloat(i) * 40, 18, cor(i == 0 ? 0xFFFFFF : 0x9AA0AA))
            }
            let linhas: [(String, UInt32)] = [
                ("// Fecha o pedido e avisa o cliente", 0x6B7280),
                ("func fecharPedido(numero: Int) -> Bool {", 0xE5E7EB),
                ("    let total = somarItens(numero)", 0xE5E7EB),
                ("    guard total > 0 else { return false }", 0xF59E0B),
                ("    registrar(\"Pedido fechado\", total)", 0x34D399),
                ("    avisarCliente(numero)", 0xE5E7EB),
                ("    return true", 0xA78BFA),
                ("}", 0xE5E7EB),
            ]
            for (i, l) in linhas.enumerated() {
                let y = 130 + CGFloat(i) * 46
                texto(ctx, String(i + 12), 276, y, 20, cor(0x4B5563), mono: true)
                texto(ctx, l.0, 330, y, 22, cor(l.1), mono: true)
            }
            caixa(ctx, CGRect(x: 250, y: h - 150, width: w - 250, height: 150), cor(0x15171C))
            texto(ctx, "Compilado sem erros em 2,4 s", 280, h - 96, 20, cor(0x34D399), mono: true)
            texto(ctx, "12 testes passaram", 280, h - 54, 20, cor(0x9AA0AA), mono: true)
        }
    }

    private static func painel() -> CGImage? {
        tela(1280, 800) { ctx, w, h in
            caixa(ctx, CGRect(x: 0, y: 0, width: w, height: h), cor(0xF4F5F7))
            barraDeJanela(ctx, w, titulo: "Painel de vendas", fundo: cor(0xE7E9EE), tinta: cor(0x30343B))
            texto(ctx, "Vendas da semana", 60, 140, 40, cor(0x16181D), forte: true)
            texto(ctx, "Atualizado hoje às 14:05", 60, 180, 20, cor(0x6B7280))
            for (i, par) in [("Pedidos", "184"), ("Ticket médio", "R$ 72,40"), ("Entregas no prazo", "96%")].enumerated() {
                let x = 60 + CGFloat(i) * 395
                caixa(ctx, CGRect(x: x, y: 220, width: 365, height: 130), cor(0xFFFFFF), raio: 18)
                texto(ctx, par.0, x + 26, 262, 20, cor(0x6B7280))
                texto(ctx, par.1, x + 26, 320, 42, cor(0x16181D), forte: true)
            }
            caixa(ctx, CGRect(x: 60, y: 384, width: w - 120, height: 356), cor(0xFFFFFF), raio: 18)
            let valores: [CGFloat] = [0.42, 0.55, 0.38, 0.71, 0.64, 0.93, 0.80]
            for (i, v) in valores.enumerated() {
                let x = 120 + CGFloat(i) * 152, alto = v * 250
                caixa(ctx, CGRect(x: x, y: 690 - alto, width: 92, height: alto), cor(i == 5 ? 0x3B82F6 : 0xB9D2FB), raio: 10)
                texto(ctx, ["seg", "ter", "qua", "qui", "sex", "sáb", "dom"][i], x + 28, 722, 18, cor(0x6B7280))
            }
        }
    }

    private static func terminal() -> CGImage? {
        tela(1100, 620) { ctx, w, h in
            caixa(ctx, CGRect(x: 0, y: 0, width: w, height: h), cor(0x0E1013))
            barraDeJanela(ctx, w, titulo: "zsh — loja", fundo: cor(0x1C1F25), tinta: cor(0xC9CDD4))
            let linhas: [(String, UInt32)] = [
                ("$ git status", 0xE5E7EB),
                ("No ramo principal", 0x9AA0AA),
                ("Mudanças a serem enviadas:", 0x9AA0AA),
                ("    modificado: Pedido.swift", 0x34D399),
                ("    novo arquivo: Entrega.swift", 0x34D399),
                ("$ swift test", 0xE5E7EB),
                ("erro: Estoque.swift:48 valor negativo", 0xF4505E),
                ("11 de 12 testes passaram", 0xF59E0B),
            ]
            for (i, l) in linhas.enumerated() {
                texto(ctx, l.0, 36, 112 + CGFloat(i) * 56, 26, cor(l.1), mono: true)
            }
        }
    }

    private static func recado() -> CGImage? {
        tela(900, 420) { ctx, w, h in
            caixa(ctx, CGRect(x: 0, y: 0, width: w, height: h), cor(0xFFFFFF))
            texto(ctx, "Reunião de quinta", 50, 90, 44, cor(0x16181D), forte: true)
            texto(ctx, "Levar o relatório de entregas", 50, 170, 30, cor(0x30343B))
            texto(ctx, "Confirmar o horário com a equipe", 50, 224, 30, cor(0x30343B))
            texto(ctx, "Sala 3, às 10h30", 50, 278, 30, cor(0x30343B))
            texto(ctx, "Senha do visitante: 4821", 50, 350, 26, cor(0x6B7280))
        }
    }
}
