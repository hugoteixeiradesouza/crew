import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Anotação rápida de uma captura: o modelo (em pixels da imagem, origem em cima à esquerda) e o
// desenho. O mesmo desenho serve para a tela (escala da prévia) e para a cópia final (escala 1),
// então o que o Hugo vê é o que é salvo. O original nunca é regravado.

enum FerramentaAnotacao: String, CaseIterable, Sendable, Identifiable {
    case seta, retangulo, traco, texto, tarja

    var id: String { rawValue }

    var nome: String {
        switch self {
        case .seta: "Seta"
        case .retangulo: "Retângulo"
        case .traco: "Traço livre"
        case .texto: "Texto"
        case .tarja: "Tarja (esconde)"
        }
    }

    /// SF Symbol.
    var icone: String {
        switch self {
        case .seta: "arrow.up.right"
        case .retangulo: "rectangle"
        case .traco: "scribble"
        case .texto: "textformat"
        case .tarja: "rectangle.fill"
        }
    }
}

struct CorAnotacao: Hashable, Sendable, Identifiable {
    let nome: String
    let r: CGFloat, g: CGFloat, b: CGFloat

    var id: String { nome }
    var cg: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: 1) }
    /// Texto por cima desta cor: preto nas claras, branco nas escuras.
    var contraste: CGColor {
        let luz = 0.299 * r + 0.587 * g + 0.114 * b
        return luz > 0.62 ? CGColor(srgbRed: 0.07, green: 0.07, blue: 0.09, alpha: 1) : CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    }

    static let paleta: [CorAnotacao] = [
        CorAnotacao(nome: "Vermelho", r: 0.96, g: 0.26, b: 0.30),
        CorAnotacao(nome: "Laranja", r: 0.96, g: 0.65, b: 0.14),
        CorAnotacao(nome: "Verde", r: 0.20, g: 0.83, b: 0.60),
        CorAnotacao(nome: "Azul", r: 0.25, g: 0.56, b: 0.98),
        CorAnotacao(nome: "Branco", r: 1, g: 1, b: 1),
        CorAnotacao(nome: "Preto", r: 0.07, g: 0.07, b: 0.09),
    ]
}

struct Anotacao: Identifiable, Sendable {
    let id = UUID()
    let ferramenta: FerramentaAnotacao
    let cor: CorAnotacao
    /// Seta, retângulo e tarja: 2 pontos (começo e fim). Traço: todos. Texto: 1 (canto de cima).
    var pontos: [CGPoint]
    var texto = ""
    /// Espessura do traço em pixels da imagem.
    let espessura: CGFloat

    var caixa: CGRect {
        guard let a = pontos.first, let b = pontos.last else { return .zero }
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    /// Clique sem arrastar não vira anotação.
    var vazia: Bool {
        switch ferramenta {
        case .texto: return texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .traco: return pontos.count < 2
        case .seta:
            guard let a = pontos.first, let b = pontos.last else { return true }
            return hypot(a.x - b.x, a.y - b.y) < espessura * 2
        case .retangulo, .tarja: return caixa.width < espessura || caixa.height < espessura
        }
    }
}

enum DesenhoAnotacoes {
    /// Traço proporcional à imagem: uma captura de tela inteira e um recorte pequeno ficam com o
    /// mesmo peso visual.
    static func espessura(para tamanho: CGSize) -> CGFloat {
        min(max((max(tamanho.width, tamanho.height) / 260).rounded(), 3), 14)
    }

    /// Desenha num contexto com a origem em cima à esquerda (y para baixo). `escala` = pontos do
    /// contexto por pixel da imagem.
    static func desenhar(_ anotacoes: [Anotacao], em ctx: CGContext, escala: CGFloat) {
        for a in anotacoes where !a.pontos.isEmpty {
            ctx.saveGState()
            let e = a.espessura * escala
            let p = a.pontos.map { CGPoint(x: $0.x * escala, y: $0.y * escala) }
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.setLineWidth(e)
            ctx.setStrokeColor(a.cor.cg)
            ctx.setFillColor(a.cor.cg)
            switch a.ferramenta {
            case .tarja:
                // Tarja sólida (não é desfoque): o que está embaixo não volta com filtro nenhum.
                ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
                ctx.fill(a.caixa.applying(CGAffineTransform(scaleX: escala, y: escala)))
            case .retangulo:
                let r = a.caixa.applying(CGAffineTransform(scaleX: escala, y: escala))
                ctx.addPath(CGPath(roundedRect: r, cornerWidth: min(e, r.width / 2), cornerHeight: min(e, r.height / 2), transform: nil))
                ctx.strokePath()
            case .traco:
                ctx.beginPath()
                ctx.move(to: p[0])
                for q in p.dropFirst() { ctx.addLine(to: q) }
                ctx.strokePath()
            case .seta:
                seta(de: p[0], ate: p[p.count - 1], espessura: e, em: ctx)
            case .texto:
                texto(a.texto, em: p[0], cor: a.cor, tamanho: e * 5, ctx: ctx)
            }
            ctx.restoreGState()
        }
    }

    private static func seta(de a: CGPoint, ate b: CGPoint, espessura e: CGFloat, em ctx: CGContext) {
        let comprimento = hypot(b.x - a.x, b.y - a.y)
        guard comprimento > 0.5 else { return }
        let ux = (b.x - a.x) / comprimento, uy = (b.y - a.y) / comprimento
        let ponta = min(e * 4.2, comprimento * 0.6), meia = ponta * 0.52
        let base = CGPoint(x: b.x - ux * ponta, y: b.y - uy * ponta)
        ctx.beginPath()
        ctx.move(to: a)
        ctx.addLine(to: CGPoint(x: base.x + ux * e * 0.5, y: base.y + uy * e * 0.5))
        ctx.strokePath()
        ctx.beginPath()
        ctx.move(to: b)
        ctx.addLine(to: CGPoint(x: base.x - uy * meia, y: base.y + ux * meia))
        ctx.addLine(to: CGPoint(x: base.x + uy * meia, y: base.y - ux * meia))
        ctx.closePath()
        ctx.setLineWidth(max(1, e * 0.35))
        ctx.drawPath(using: .fillStroke)
    }

    /// Etiqueta: o texto numa plaquinha da cor escolhida (lê-se em cima de qualquer fundo).
    private static func texto(_ s: String, em origem: CGPoint, cor: CorAnotacao, tamanho: CGFloat, ctx: CGContext) {
        let linha = linhaDe(s, tamanho: tamanho, cor: cor.contraste)
        var sobe: CGFloat = 0, desce: CGFloat = 0, entre: CGFloat = 0
        let largura = CGFloat(CTLineGetTypographicBounds(linha, &sobe, &desce, &entre))
        let margemX = tamanho * 0.42, margemY = tamanho * 0.22
        let placa = CGRect(x: origem.x, y: origem.y, width: largura + margemX * 2, height: sobe + desce + margemY * 2)
        ctx.addPath(CGPath(roundedRect: placa, cornerWidth: tamanho * 0.3, cornerHeight: tamanho * 0.3, transform: nil))
        ctx.fillPath()
        // O contexto tem o y para baixo: desvira só o texto.
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        ctx.textPosition = CGPoint(x: placa.minX + margemX, y: placa.minY + margemY + sobe)
        CTLineDraw(linha, ctx)
    }

    private static func linhaDe(_ s: String, tamanho: CGFloat, cor: CGColor) -> CTLine {
        let fonte = CTFontCreateUIFontForLanguage(.emphasizedSystem, max(tamanho, 6), nil)
            ?? CTFontCreateWithName("Helvetica-Bold" as CFString, max(tamanho, 6), nil)
        let atributos: [CFString: Any] = [kCTFontAttributeName: fonte, kCTForegroundColorAttributeName: cor]
        let texto = CFAttributedStringCreate(nil, s.replacingOccurrences(of: "\n", with: " ") as CFString,
                                             atributos as CFDictionary)!
        return CTLineCreateWithAttributedString(texto)
    }

    /// Tamanho da plaquinha de um texto (em pixels da imagem), para a tela saber onde ele cai.
    static func tamanhoEtiqueta(_ s: String, espessura: CGFloat) -> CGSize {
        let tamanho = espessura * 5
        var sobe: CGFloat = 0, desce: CGFloat = 0, entre: CGFloat = 0
        let largura = CGFloat(CTLineGetTypographicBounds(linhaDe(s, tamanho: tamanho, cor: CGColor(gray: 0, alpha: 1)), &sobe, &desce, &entre))
        return CGSize(width: largura + tamanho * 0.84, height: sobe + desce + tamanho * 0.44)
    }

    /// A imagem com as anotações por cima, no tamanho original.
    static func compor(_ imagem: CGImage, _ anotacoes: [Anotacao]) -> CGImage? {
        let w = imagem.width, h = imagem.height
        guard let espaco = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: espaco,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(imagem, in: CGRect(x: 0, y: 0, width: w, height: h))
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        desenhar(anotacoes, em: ctx, escala: 1)
        return ctx.makeImage()
    }

    static func png(_ imagem: CGImage) -> Data? {
        let dados = NSMutableData()
        guard let destino = CGImageDestinationCreateWithData(dados, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destino, imagem, nil)
        return CGImageDestinationFinalize(destino) ? dados as Data : nil
    }

    static func abrir(_ url: URL) -> CGImage? {
        guard let fonte = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(fonte, 0, nil)
    }
}
