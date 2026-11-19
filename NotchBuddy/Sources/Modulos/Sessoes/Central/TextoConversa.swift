import SwiftUI
import AppKit

// O texto de uma fala no app do Crew. A fala é lida em blocos (`BlocosResposta`) e repartida em
// partes: o texto corrido — parágrafos, títulos, listas, citações e blocos de código — fica num
// campo de texto só (NSTextView, sem edição), em que dá para selecionar de qualquer ponto a
// qualquer ponto e copiar (⌘C ou clique direito); cada tabela vira um entregável próprio
// (`TabelaConversa`: colunas medidas, copiar, CSV, ampliar). Os links ficam em azul e
// sublinhados, e só abrem com ⌘ clique (clique simples é para selecionar): página no navegador
// do Crew, arquivo por cima da janela do Crew.

/// Avisa quem está em volta que o Hugo clicou no texto (na grade, é o que põe o painel em foco:
/// o campo de texto fica com o clique e o gesto do SwiftUI não chega).
private struct AoTocarTextoKey: EnvironmentKey { static let defaultValue: (@MainActor () -> Void)? = nil }

/// A pasta da sessão: é onde um arquivo citado sem o caminho inteiro ("Fontes/Leitor.swift:42") é procurado.
private struct PastaDaSessaoKey: EnvironmentKey { static let defaultValue: String? = nil }

extension EnvironmentValues {
    var aoTocarTexto: (@MainActor () -> Void)? {
        get { self[AoTocarTextoKey.self] }
        set { self[AoTocarTextoKey.self] = newValue }
    }

    var pastaDaSessao: String? {
        get { self[PastaDaSessaoKey.self] }
        set { self[PastaDaSessaoKey.self] = newValue }
    }
}

/// Uma fala repartida: trechos de texto corrido e, entre eles, as tabelas.
struct ParteResposta: Identifiable {
    enum Tipo {
        case texto([BlocoResposta])
        case tabela(TabelaResposta)
    }

    let id: Int
    let tipo: Tipo
    /// Muda quando o conteúdo da parte muda (resposta chegando aos poucos só refaz o fim).
    let chave: Int
    /// O título mais próximo acima da tabela: vira o nome dela (janela ampliada, arquivo CSV).
    var titulo: String? = nil

    private final class Guardadas { let partes: [ParteResposta]; init(_ p: [ParteResposta]) { partes = p } }
    @MainActor private static let guardadas: NSCache<NSString, Guardadas> = {
        let c = NSCache<NSString, Guardadas>()
        c.countLimit = 300
        return c
    }()

    /// As partes de uma fala (guardadas: o SwiftUI pede de novo a cada desenho).
    @MainActor
    static func de(_ texto: String) -> [ParteResposta] {
        if let g = guardadas.object(forKey: texto as NSString) { return g.partes }
        var out: [ParteResposta] = []
        var corrido: [BlocoResposta] = []
        var titulo: String?
        func fecha() {
            guard !corrido.isEmpty else { return }
            out.append(ParteResposta(id: out.count, tipo: .texto(corrido), chave: corrido.hashValue))
            corrido = []
        }
        for bloco in BlocosResposta.ler(texto) {
            switch bloco {
            case .tabela(let t):
                fecha()
                out.append(ParteResposta(id: out.count, tipo: .tabela(t), chave: t.hashValue, titulo: titulo))
            case .titulo(_, let t):
                titulo = RegrasTabela.limpo(t)
                corrido.append(bloco)
            default:
                corrido.append(bloco)
            }
        }
        fecha()
        guardadas.setObject(Guardadas(out), forKey: texto as NSString)
        return out
    }
}

struct TextoConversa: View {
    let texto: String
    var tamanho: CGFloat = 14
    var cor: Color = Color(hex: "#DDE0E5")
    var entrelinha: CGFloat = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 10 + entrelinha) {
            ForEach(ParteResposta.de(texto)) { parte in
                switch parte.tipo {
                case .texto(let blocos):
                    TextoCorrido(blocos: blocos, chaveBlocos: parte.chave, textoBruto: texto,
                                 tamanho: tamanho, cor: cor, entrelinha: entrelinha)
                case .tabela(let tabela):
                    TabelaConversa(tabela: tabela, titulo: parte.titulo, tamanho: tamanho - 1)
                }
            }
        }
    }
}

/// Embaixo da resposta: copiar a resposta inteira (em markdown, como o Claude escreveu).
struct CopiarResposta: View {
    let texto: String
    @State private var hover = false
    @State private var copiado = false

    var body: some View {
        Button {
            VistaTexto.copiar(texto)
            copiado = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { copiado = false }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: copiado ? "checkmark" : "doc.on.doc").font(.system(size: 10.5, weight: .medium))
                Text(copiado ? "Copiado" : "Copiar resposta").font(.system(size: 11.5, weight: .medium))
            }
            .foregroundStyle(copiado ? Tema.verde : hover ? Tema.texto : Tema.texto3)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(hover ? Color.white.opacity(0.07) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("Copiar a resposta inteira")
        .padding(.leading, -8)
    }
}

/// Um trecho de texto corrido da fala, num campo de texto só.
struct TextoCorrido: NSViewRepresentable {
    let blocos: [BlocoResposta]
    let chaveBlocos: Int
    /// A fala inteira, em markdown: é o que "Copiar tudo" copia.
    let textoBruto: String
    var tamanho: CGFloat = 14
    var cor: Color = Color(hex: "#DDE0E5")
    var entrelinha: CGFloat = 4
    @Environment(\.aoTocarTexto) private var aoTocar
    @Environment(\.pastaDaSessao) private var pasta

    func makeNSView(context: Context) -> VistaTexto {
        let v = VistaTexto.nova()
        atualizar(v)
        return v
    }

    func updateNSView(_ v: VistaTexto, context: Context) { atualizar(v) }

    private func atualizar(_ v: VistaTexto) {
        v.aoTocar = aoTocar
        v.textoBruto = textoBruto
        let chave = "\(tamanho)|\(entrelinha)|\(cor.description)|\(pasta ?? "")|\(blocos.count)|\(chaveBlocos)"
        guard chave != v.chave else { return }
        v.chave = chave
        v.mostrar(TextoRico.montar(blocos, tamanho: tamanho, cor: NSColor(cor), entrelinha: entrelinha, pasta: pasta))
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView v: VistaTexto, context: Context) -> CGSize? {
        var largura = proposal.width ?? 600
        if !largura.isFinite || largura <= 0 { largura = 600 }
        return CGSize(width: largura, height: v.altura(para: largura))
    }
}

/// O campo de texto de uma fala: só leitura, sem fundo, do tamanho do texto. Desenha por baixo
/// do texto a caixa de cada bloco de código, a barra da citação e o fio do separador, e põe em
/// cima de cada bloco de código a faixa com a linguagem e o botão de copiar.
final class VistaTexto: NSTextView, NSTextViewDelegate {
    var chave = ""
    var textoBruto = ""
    var aoTocar: (@MainActor () -> Void)?
    var medida: (largura: CGFloat, altura: CGFloat)?
    private var enfeites: [TextoRico.Enfeite] = []
    private var faixas: [FaixaCodigo] = []

    static func nova() -> VistaTexto {
        // TextKit 1 de propósito: bloco de código, citação e fio usam NSTextTableBlock.
        let guarda = NSTextStorage()
        let leiaute = NSLayoutManager()
        guarda.addLayoutManager(leiaute)
        let caixa = NSTextContainer(size: NSSize(width: 600, height: CGFloat.greatestFiniteMagnitude))
        caixa.lineFragmentPadding = 0
        caixa.widthTracksTextView = true
        leiaute.addTextContainer(caixa)
        let v = VistaTexto(frame: .zero, textContainer: caixa)
        v.isEditable = false
        v.isSelectable = true
        v.drawsBackground = false
        v.textContainerInset = .zero
        v.isVerticallyResizable = false
        v.isHorizontallyResizable = false
        v.isAutomaticLinkDetectionEnabled = false
        v.displaysLinkToolTips = true
        v.linkTextAttributes = [
            .foregroundColor: NSColor(Tema.azul),
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .cursor: NSCursor.pointingHand,
        ]
        v.selectedTextAttributes = [.backgroundColor: NSColor(Tema.azul).withAlphaComponent(0.35)]
        v.delegate = v
        return v
    }

    func mostrar(_ montado: TextoRico.Montado) {
        textStorage?.setAttributedString(montado.texto)
        enfeites = montado.enfeites
        faixas.forEach { $0.removeFromSuperview() }
        faixas = montado.enfeites.compactMap { e in
            guard case .codigo(let linguagem, let fonte) = e.tipo else { return nil }
            let f = FaixaCodigo(rotulo: TextoRico.nomeDaLinguagem(linguagem), codigo: fonte, bloco: e.bloco, faixa: e.faixa)
            addSubview(f)
            return f
        }
        medida = nil
        needsDisplay = true
    }

    /// Altura do texto nessa largura (guardada: o SwiftUI pergunta várias vezes).
    func altura(para largura: CGFloat) -> CGFloat {
        if let m = medida, m.largura == largura { return m.altura }
        guard let caixa = textContainer, let leiaute = layoutManager else { return 0 }
        caixa.size = NSSize(width: largura, height: CGFloat.greatestFiniteMagnitude)
        leiaute.ensureLayout(for: caixa)
        let h = ceil(leiaute.usedRect(for: caixa).height)
        medida = (largura, h)
        posicionarFaixas()
        return h
    }

    /// Onde a caixa de um bloco (código, citação, fio) ficou, com as margens internas dele.
    private func caixa(de bloco: NSTextBlock, _ faixa: NSRange) -> NSRect? {
        guard let leiaute = layoutManager, faixa.location + faixa.length <= (textStorage?.length ?? 0) else { return nil }
        let glifos = leiaute.glyphRange(forCharacterRange: faixa, actualCharacterRange: nil)
        var r = leiaute.boundsRect(for: bloco, glyphRange: glifos)
        // O retângulo vem com a margem de fora (o respiro até o próximo bloco): ela não é da caixa.
        r.size.height -= bloco.width(for: .margin, edge: .maxY)
        return r.isEmpty ? nil : r
    }

    private func posicionarFaixas() {
        for f in faixas {
            guard let r = caixa(de: f.bloco, f.faixa) else { f.isHidden = true; continue }
            f.isHidden = false
            f.frame = NSRect(x: r.minX, y: r.minY, width: r.width, height: TextoRico.alturaFaixaCodigo)
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        posicionarFaixas()
    }

    override func draw(_ dirtyRect: NSRect) {
        for e in enfeites {
            guard let r = caixa(de: e.bloco, e.faixa), r.insetBy(dx: -2, dy: -2).intersects(dirtyRect) else { continue }
            switch e.tipo {
            case .codigo:
                let forma = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10)
                NSColor.white.withAlphaComponent(0.045).setFill()
                forma.fill()
                NSColor.white.withAlphaComponent(0.08).setStroke()
                forma.lineWidth = 1
                forma.stroke()
            case .citacao:
                NSColor.white.withAlphaComponent(0.22).setFill()
                NSBezierPath(roundedRect: NSRect(x: r.minX, y: r.minY + 1, width: 3, height: max(r.height - 2, 4)),
                             xRadius: 1.5, yRadius: 1.5).fill()
            case .fio:
                NSColor.white.withAlphaComponent(0.12).setFill()
                NSRect(x: r.minX, y: floor(r.midY), width: r.width, height: 1).fill()
            }
        }
        super.draw(dirtyRect)
    }

    override func mouseDown(with event: NSEvent) {
        aoTocar?()
        super.mouseDown(with: event)
    }

    /// Perdeu o foco: a seleção some (senão cada fala ficaria com um trecho marcado).
    override func resignFirstResponder() -> Bool {
        setSelectedRange(NSRange(location: 0, length: 0))
        return super.resignFirstResponder()
    }

    // Clique direito: o menu do Crew, com copiar a seleção e copiar tudo.
    override func menu(for event: NSEvent) -> NSMenu? { nil }

    override func rightMouseDown(with event: NSEvent) {
        let escolhido = selectedRange().length > 0 ? (string as NSString).substring(with: selectedRange()) : nil
        let tudo = textoBruto
        var itens: [ItemMenu] = []
        if let escolhido {
            itens.append(.acao("Copiar seleção", icone: "doc.on.doc", detalhe: "⌘C") { Self.copiar(escolhido) })
        }
        // Clique direito em cima de um bloco de código: copia só o código.
        let ponto = convert(event.locationInWindow, from: nil)
        if let f = faixas.first(where: { self.caixa(de: $0.bloco, $0.faixa)?.contains(ponto) == true }) {
            let codigo = f.codigo
            itens.append(.acao("Copiar este código", icone: "chevron.left.forwardslash.chevron.right") { Self.copiar(codigo) })
        }
        itens.append(.acao("Copiar a resposta inteira", icone: "doc.on.doc.fill") { Self.copiar(tudo) })
        MenuCrew.abrirNoMouse(itens)
    }

    static func copiar(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }

    /// Link só abre com ⌘ clique; sem o ⌘ o clique não faz nada (é para selecionar).
    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        guard NSApp.currentEvent?.modifierFlags.contains(.command) == true else { return true }
        guard let url = link as? URL ?? (link as? String).flatMap(URL.init(string:)) else { return true }
        MainActor.assumeIsolated { TextoRico.abrir(url) }
        return true
    }
}

/// A faixa de cima de um bloco de código: a linguagem à esquerda e "Copiar" à direita. Fica por
/// cima do campo de texto (não é texto: não entra na seleção nem na cópia).
final class FaixaCodigo: NSView {
    let codigo: String
    let bloco: NSTextBlock
    let faixa: NSRange
    private let rotulo: String
    private var sobre = false
    private var copiado = false

    init(rotulo: String, codigo: String, bloco: NSTextBlock, faixa: NSRange) {
        self.rotulo = rotulo
        self.codigo = codigo
        self.bloco = bloco
        self.faixa = faixa
        super.init(frame: .zero)
        toolTip = "Copiar o código"
    }

    required init?(coder: NSCoder) { fatalError("sem storyboard") }

    override var isFlipped: Bool { true }

    private var textoBotao: String { copiado ? "Copiado" : "Copiar" }
    private var areaBotao: NSRect {
        let l = ceil((textoBotao as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11.5, weight: .medium)]).width) + 38
        return NSRect(x: bounds.width - l - 5, y: 4, width: l, height: bounds.height - 6)
    }

    // Só o botão pega o clique; o resto da faixa deixa passar para o texto.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let s = superview else { return nil }
        return areaBotao.contains(convert(point, from: s)) ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) { marcar(areaBotao.contains(convert(event.locationInWindow, from: nil))) }
    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
    override func mouseExited(with event: NSEvent) { marcar(false) }
    override func resetCursorRects() { addCursorRect(areaBotao, cursor: .pointingHand) }

    private func marcar(_ novo: Bool) {
        guard novo != sobre else { return }
        sobre = novo
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        VistaTexto.copiar(codigo)
        copiado = true
        needsDisplay = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            self?.copiado = false
            self?.needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let apagado = NSColor(Tema.texto3)
        (rotulo as NSString).draw(at: NSPoint(x: 14, y: 8), withAttributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: apagado, .kern: 0.2])
        let cor = copiado ? NSColor(Tema.verde) : sobre ? NSColor(Tema.texto) : NSColor(Tema.texto2)
        let b = areaBotao
        if sobre && !copiado {
            NSColor.white.withAlphaComponent(0.07).setFill()
            NSBezierPath(roundedRect: b, xRadius: 6, yRadius: 6).fill()
        }
        let fonte = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium).applying(.init(paletteColors: [cor]))
        if let img = NSImage(systemSymbolName: copiado ? "checkmark" : "doc.on.doc", accessibilityDescription: nil)?
            .withSymbolConfiguration(config) {
            img.draw(in: NSRect(x: b.minX + 10, y: b.midY - img.size.height / 2, width: img.size.width, height: img.size.height))
        }
        let t = textoBotao as NSString
        let tam = t.size(withAttributes: [.font: fonte])
        t.draw(at: NSPoint(x: b.maxX - tam.width - 10, y: b.midY - tam.height / 2), withAttributes: [.font: fonte, .foregroundColor: cor])
    }
}

/// Blocos da resposta → texto com atributos do AppKit.
@MainActor
enum TextoRico {
    /// O que o campo de texto desenha por baixo de um bloco.
    struct Enfeite {
        enum Tipo {
            case codigo(linguagem: String, fonte: String)
            case citacao
            case fio
        }
        let tipo: Tipo
        let bloco: NSTextBlock
        let faixa: NSRange
    }

    struct Montado {
        let texto: NSAttributedString
        let enfeites: [Enfeite]
    }

    static let alturaFaixaCodigo: CGFloat = 30
    private static func branco(_ a: CGFloat) -> NSColor { NSColor.white.withAlphaComponent(a) }
    private static let dica = "⌘ clique para abrir"
    static let forte = NSColor(Color(hex: "#F5F6F8"))
    private static let apagado = NSColor(Color(hex: "#6B7079"))

    /// O nome que aparece na faixa do bloco de código. Comando de terminal é "Comando".
    static func nomeDaLinguagem(_ l: String) -> String {
        switch l {
        case "": return "Texto"
        case "bash", "sh", "zsh", "shell", "console", "fish", "terminal": return "Comando"
        case "diff", "patch": return "Diferença"
        case "js", "javascript": return "JavaScript"
        case "ts", "typescript": return "TypeScript"
        case "py", "python": return "Python"
        case "md", "markdown": return "Markdown"
        case "yml": return "YAML"
        case "txt", "text", "plaintext": return "Texto"
        default: return l.count <= 4 ? l.uppercased() : l.prefix(1).uppercased() + l.dropFirst()
        }
    }

    /// Página da web abre no navegador do Crew, ao lado da sessão; arquivo (imagem, PDF, texto)
    /// abre por cima da janela do Crew; o resto (mailto:) vai para o macOS.
    static func abrir(_ url: URL) {
        if ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            NotificationCenter.default.post(name: .abrirNoNavegador, object: url)
        } else if url.isFileURL {
            VisorCrew.abrir(url)
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    /// Markdown inteiro de uma vez (quem não reparte a fala em partes).
    static func montar(_ texto: String, tamanho: CGFloat, cor: NSColor, entrelinha: CGFloat) -> NSAttributedString {
        montar(BlocosResposta.ler(texto), tamanho: tamanho, cor: cor, entrelinha: entrelinha, pasta: nil).texto
    }

    static func montar(_ blocos: [BlocoResposta], tamanho: CGFloat, cor: NSColor, entrelinha: CGFloat, pasta: String?) -> Montado {
        let out = NSMutableAttributedString()
        var enfeites: [Enfeite] = []
        let fonte = NSFont.systemFont(ofSize: tamanho)
        let quebra = NSAttributedString(string: "\n", attributes: [.font: fonte])

        func ehItem(_ b: BlocoResposta?) -> Bool { if case .item? = b { return true } else { return false } }
        func ehTitulo(_ b: BlocoResposta?) -> Bool { if case .titulo? = b { return true } else { return false } }

        for (i, bloco) in blocos.enumerated() {
            let ultimo = i == blocos.count - 1
            let proximo = ultimo ? nil : blocos[i + 1]
            // O ritmo da resposta: itens da mesma lista ficam juntos, título cola no que ele
            // apresenta e se afasta do que veio antes, o resto respira igual.
            var depois: CGFloat = 8 + entrelinha
            if ultimo { depois = 0 }
            else if ehItem(bloco) && ehItem(proximo) { depois = max(2, entrelinha) }
            else if ehTitulo(bloco) { depois = 4 + entrelinha }

            func estilo() -> NSMutableParagraphStyle {
                let p = NSMutableParagraphStyle()
                p.lineSpacing = entrelinha
                p.paragraphSpacing = depois
                return p
            }
            func entra(_ a: NSAttributedString, _ p: NSParagraphStyle) {
                let m = NSMutableAttributedString(attributedString: a)
                if !ultimo { m.append(quebra) }
                m.addAttribute(.paragraphStyle, value: p, range: NSRange(location: 0, length: m.length))
                out.append(m)
            }
            func caixa(esquerda: CGFloat = 0, direita: CGFloat = 0, cima: CGFloat = 0, baixo: CGFloat = 0) -> NSTextBlock {
                // Uma tabela de uma célula só: é a forma de bloco que o TextKit desenha de verdade
                // (margens internas e externas); o bloco solto (NSTextBlock) é ignorado.
                let grade = NSTextTable()
                grade.numberOfColumns = 1
                grade.layoutAlgorithm = .automaticLayoutAlgorithm
                grade.setContentWidth(100, type: .percentageValueType)
                let b = NSTextTableBlock(table: grade, startingRow: 0, rowSpan: 1, startingColumn: 0, columnSpan: 1)
                b.setWidth(esquerda, type: .absoluteValueType, for: .padding, edge: .minX)
                b.setWidth(direita, type: .absoluteValueType, for: .padding, edge: .maxX)
                b.setWidth(cima, type: .absoluteValueType, for: .padding, edge: .minY)
                b.setWidth(baixo, type: .absoluteValueType, for: .padding, edge: .maxY)
                b.setWidth(depois, type: .absoluteValueType, for: .margin, edge: .maxY)
                return b
            }

            switch bloco {
            case .paragrafo(let s):
                entra(inline(s, fonte: fonte, cor: cor), estilo())

            case .titulo(let nivel, let s):
                let extra: CGFloat = nivel <= 1 ? 6 : nivel == 2 ? 3 : nivel == 3 ? 1 : 0
                let f = NSFont.systemFont(ofSize: tamanho + extra, weight: nivel <= 2 ? .bold : .semibold)
                let p = estilo()
                p.lineSpacing = 2
                if i > 0 { p.paragraphSpacingBefore = nivel <= 2 ? 10 : 6 }
                entra(inline(s, fonte: f, cor: nivel >= 4 ? NSColor(Color(hex: "#C9CCD3")) : forte), p)

            case .item(let marca, let s, let recuo):
                var sinal = "•", corSinal = apagado, corTexto = cor
                var fonteSinal = fonte
                switch marca {
                case .ponto: break
                case .numero(let n):
                    sinal = n
                    fonteSinal = NSFont.monospacedDigitSystemFont(ofSize: tamanho, weight: .regular)
                    corSinal = NSColor(Color(hex: "#8E939C"))
                case .feito:
                    sinal = "✓"
                    fonteSinal = NSFont.systemFont(ofSize: tamanho, weight: .bold)
                    corSinal = NSColor(Tema.verde)
                    corTexto = NSColor(Color(hex: "#A9ADB6"))
                case .aFazer:
                    sinal = "□"
                    corSinal = NSColor(Color(hex: "#8E939C"))
                }
                let m = NSMutableAttributedString(string: sinal + "\t", attributes: [.font: fonteSinal, .foregroundColor: corSinal])
                m.append(inline(s, fonte: fonte, cor: corTexto))
                let p = estilo()
                let inicio = CGFloat(recuo) * 20 + 2
                let larguraSinal = ceil((sinal as NSString).size(withAttributes: [.font: fonteSinal]).width)
                let comeco = inicio + max(larguraSinal, 8) + 9
                p.firstLineHeadIndent = inicio
                p.headIndent = comeco
                p.tabStops = [NSTextTab(textAlignment: .left, location: comeco)]
                entra(m, p)

            case .citacao(let s):
                let b = caixa(esquerda: 15, cima: 1, baixo: 1)
                let p = NSMutableParagraphStyle()
                p.lineSpacing = entrelinha
                p.textBlocks = [b]
                let m = inline(s, fonte: fonte, cor: NSColor(Color(hex: "#B4B8C1")))
                m.append(quebra)
                m.addAttribute(.paragraphStyle, value: p, range: NSRange(location: 0, length: m.length))
                enfeites.append(Enfeite(tipo: .citacao, bloco: b, faixa: NSRange(location: out.length, length: m.length)))
                out.append(m)

            case .codigo(let linguagem, let s):
                let b = caixa(esquerda: 14, direita: 14, cima: alturaFaixaCodigo, baixo: 12)
                let m = codigo(s, linguagem: linguagem, tamanho: max(11, tamanho - 1.5), bloco: b)
                enfeites.append(Enfeite(tipo: .codigo(linguagem: linguagem, fonte: s), bloco: b, faixa: NSRange(location: out.length, length: m.length)))
                out.append(m)

            case .fio:
                let b = caixa(cima: 3, baixo: 3)
                let p = NSMutableParagraphStyle()
                p.textBlocks = [b]
                p.maximumLineHeight = 3
                let m = NSAttributedString(string: "\n", attributes: [.font: NSFont.systemFont(ofSize: 1), .paragraphStyle: p])
                enfeites.append(Enfeite(tipo: .fio, bloco: b, faixa: NSRange(location: out.length, length: m.length)))
                out.append(m)

            case .tabela(let t):
                // Tabela tem tela própria (`TabelaConversa`); quem monta a fala inteira num texto
                // só recebe as linhas, uma por parágrafo.
                let linhas = ([t.cabecalho] + t.linhas).map { $0.map(RegrasTabela.limpo).joined(separator: "  ·  ") }
                entra(NSAttributedString(string: linhas.joined(separator: "\u{2028}"), attributes: [.font: fonte, .foregroundColor: cor]), estilo())
            }
        }
        // Bloco de código, citação e fio terminam em quebra de linha: no fim da fala ela sobra.
        if out.string.hasSuffix("\n") { out.deleteCharacters(in: NSRange(location: out.length - 1, length: 1)) }
        ligarEnderecos(out, pasta: pasta)
        return Montado(texto: out, enfeites: enfeites)
    }

    /// Um bloco de código: cada linha é um parágrafo da mesma caixa; linha comprida quebra e
    /// continua recuada (dá para ver onde a linha de verdade começa). Comentário fica apagado e,
    /// numa diferença, o que entrou fica verde e o que saiu, vermelho.
    private static func codigo(_ s: String, linguagem: String, tamanho: CGFloat, bloco: NSTextBlock) -> NSMutableAttributedString {
        let mono = NSFont.monospacedSystemFont(ofSize: tamanho, weight: .regular)
        let letra = ceil(("0" as NSString).size(withAttributes: [.font: mono]).width * 100) / 100
        let normal = NSColor(Color(hex: "#D5D8DD"))
        let comentario = NSColor(Color(hex: "#7B808A"))
        let diferenca = ["diff", "patch"].contains(linguagem)
        let cerquilha = ["bash", "sh", "zsh", "shell", "console", "fish", "terminal", "py", "python", "yaml", "yml", "toml", "ruby", "rb", "r", "make", "makefile", "dockerfile", "ini", "conf", ""].contains(linguagem)
        let barras = ["swift", "js", "javascript", "ts", "typescript", "tsx", "jsx", "c", "cpp", "h", "java", "kotlin", "go", "rust", "rs", "php", "dart", "scala", "cs", "jsonc"].contains(linguagem)
        let tracos = ["sql", "lua", "haskell"].contains(linguagem)
        let out = NSMutableAttributedString()
        var estilos: [Int: NSParagraphStyle] = [:]
        for linha in s.components(separatedBy: "\n") {
            let recuo = linha.prefix { $0 == " " }.count + linha.prefix { $0 == "\t" }.count * 4
            let p: NSParagraphStyle
            if let ja = estilos[recuo] { p = ja } else {
                let novo = NSMutableParagraphStyle()
                novo.lineSpacing = 3
                novo.textBlocks = [bloco]
                novo.headIndent = CGFloat(recuo + 2) * letra
                novo.lineBreakMode = .byWordWrapping
                estilos[recuo] = novo
                p = novo
            }
            var cor = normal
            let limpa = linha.trimmingCharacters(in: .whitespaces)
            if diferenca {
                if limpa.hasPrefix("+") && !limpa.hasPrefix("+++") { cor = NSColor(Color(hex: "#6EE7B7")) }
                else if limpa.hasPrefix("-") && !limpa.hasPrefix("---") { cor = NSColor(Color(hex: "#FCA5A5")) }
                else if limpa.hasPrefix("@@") || limpa.hasPrefix("+++") || limpa.hasPrefix("---") { cor = comentario }
            } else if (cerquilha && limpa.hasPrefix("#")) || (barras && limpa.hasPrefix("//")) || (tracos && limpa.hasPrefix("--")) {
                cor = comentario
            }
            out.append(NSAttributedString(string: linha + "\n", attributes: [.font: mono, .foregroundColor: cor, .paragraphStyle: p]))
        }
        return out
    }

    /// Negrito, itálico, `código`, riscado e [link](url) de um trecho.
    static func inline(_ s: String, fonte: NSFont, cor: NSColor) -> NSMutableAttributedString {
        let opcoes = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        let a = (try? AttributedString(markdown: s, options: opcoes)) ?? AttributedString(s)
        let out = NSMutableAttributedString()
        for run in a.runs {
            // Quebra de linha dentro do parágrafo não abre parágrafo novo (o espaço entre eles é maior).
            let trecho = String(a[run.range].characters).replacingOccurrences(of: "\n", with: "\u{2028}")
            let jeito = run.inlinePresentationIntent ?? []
            var f = fonte
            var attrs: [NSAttributedString.Key: Any] = [.foregroundColor: cor]
            if jeito.contains(.code) {
                f = NSFont.monospacedSystemFont(ofSize: fonte.pointSize - 1, weight: .regular)
                attrs[.backgroundColor] = branco(0.08)
                attrs[.foregroundColor] = NSColor(Color(hex: "#E8E9EC"))
            }
            var tracos: NSFontDescriptor.SymbolicTraits = []
            if jeito.contains(.stronglyEmphasized) {
                tracos.insert(.bold)
                attrs[.foregroundColor] = NSColor(Color(hex: "#F5F6F8"))
            }
            if jeito.contains(.emphasized) { tracos.insert(.italic) }
            if !tracos.isEmpty {
                let d = f.fontDescriptor.withSymbolicTraits(f.fontDescriptor.symbolicTraits.union(tracos))
                f = NSFont(descriptor: d, size: f.pointSize) ?? f
            }
            if jeito.contains(.strikethrough) { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if let link = run.link {
                attrs[.link] = link
                attrs[.toolTip] = "\(link.absoluteString) — \(dica)"
            }
            attrs[.font] = f
            out.append(NSAttributedString(string: trecho, attributes: attrs))
        }
        return out
    }

    /// Endereço escrito por extenso também vira link — com ou sem https://, inclusive dentro de
    /// bloco de código e de tabela.
    static func ligarEnderecos(_ out: NSMutableAttributedString, pasta: String? = nil) {
        let texto = out.string
        for (faixa, url) in enderecos(em: texto) where out.attribute(.link, at: faixa.location, effectiveRange: nil) == nil {
            out.addAttribute(.link, value: url, range: faixa)
            out.addAttribute(.toolTip, value: "\(url.isFileURL ? url.path : url.absoluteString) — \(dica)", range: faixa)
        }
        // Arquivo citado como o Claude escreve: relativo à pasta da sessão e com ":linha".
        for a in ArquivosNoTexto.achar(em: texto, pasta: pasta) {
            var livre = true
            out.enumerateAttribute(.link, in: a.faixa) { v, _, _ in if v != nil { livre = false } }
            guard livre else { continue }
            let caminho = (a.url.path as NSString).abbreviatingWithTildeInPath
            out.addAttribute(.link, value: a.url, range: a.faixa)
            out.addAttribute(.toolTip, value: "\(caminho)\(a.linha.map { ", linha \($0)" } ?? "") — \(dica)", range: a.faixa)
        }
    }

    /// Os endereços de um texto, com ou sem "https://" (`EnderecosNoTexto`), e os caminhos de
    /// arquivo ou pasta que existem no disco (`CaminhosNoTexto`), na ordem em que aparecem.
    static func enderecos(em texto: String) -> [(NSRange, URL)] {
        let web = EnderecosNoTexto.achar(em: texto)
        let caminhos = CaminhosNoTexto.achar(em: texto).filter { c in
            !web.contains { NSIntersectionRange($0.0, c.0).length > 0 }
        }
        return (web + caminhos).sorted { $0.0.location < $1.0.location }
    }
}
