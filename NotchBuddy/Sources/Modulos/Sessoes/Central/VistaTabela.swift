import SwiftUI
import AppKit

// A tabela de uma resposta, desenhada à mão (AppKit): é o que deixa uma tabela de centenas de
// linhas leve — só o que está na tela é desenhado — e o cabeçalho preso no topo enquanto a
// conversa rola. As regras (largura das colunas, coluna de número, lista dentro da célula)
// vêm de `RegrasTabela`; aqui é só medir o texto e desenhar.

/// Por qual coluna a tabela está ordenada.
struct OrdenacaoTabela: Equatable {
    var coluna: Int
    var crescente: Bool
}

/// Uma tabela pronta para desenhar: o texto de cada célula já montado e medido uma vez.
@MainActor
final class ModeloTabela {
    struct Coluna {
        let nome: String
        let titulo: NSAttributedString
        let numerica: Bool
        let direita: Bool
        /// A coluna é de lista: cada célula mostra um item por linha.
        let separador: String?
        let natural: CGFloat
        let minima: CGFloat
    }

    struct Celula {
        let texto: NSAttributedString
        let limpo: String
        /// Largura do conteúdo numa linha só (na coluna de lista, a do maior item).
        let natural: CGFloat
        /// Quantos itens a célula de lista tem (1 fora de lista).
        let itens: Int
        let link: URL?
    }

    static let margemX: CGFloat = 12
    static let margemY: CGFloat = 7
    static let entreItens: CGFloat = 3

    let tabela: TabelaResposta
    let tamanho: CGFloat
    let colunas: [Coluna]
    let celulas: [[Celula]]
    let alturaLinha: CGFloat

    var naturais: [Double] { colunas.map { Double($0.natural) } }
    var minimas: [Double] { colunas.map { Double($0.minima) } }
    var direita: [Bool] { colunas.map(\.direita) }

    private static let guardados: NSCache<NSString, ModeloTabela> = {
        let c = NSCache<NSString, ModeloTabela>()
        c.countLimit = 60
        return c
    }()

    /// O modelo de uma tabela (guardado: montar e medir é a parte cara).
    static func de(_ tabela: TabelaResposta, tamanho: CGFloat, pasta: String?) -> ModeloTabela {
        let chave = "\(tabela.hashValue)|\(tabela.linhas.count)|\(tamanho)|\(pasta ?? "")" as NSString
        if let m = guardados.object(forKey: chave) { return m }
        let m = ModeloTabela(tabela, tamanho: tamanho, pasta: pasta)
        guardados.setObject(m, forKey: chave)
        return m
    }

    init(_ tabela: TabelaResposta, tamanho: CGFloat, pasta: String?) {
        self.tabela = tabela
        self.tamanho = tamanho
        let n = tabela.colunas
        let fonte = NSFont.systemFont(ofSize: tamanho)
        let fonteNumero = NSFont.monospacedDigitSystemFont(ofSize: tamanho, weight: .regular)
        let fonteTitulo = NSFont.systemFont(ofSize: max(10.5, tamanho - 1.5), weight: .semibold)
        let cor = NSColor(Color(hex: "#DDE0E5"))
        alturaLinha = ceil(NSLayoutManager().defaultLineHeight(for: fonte))

        var colunas: [Coluna] = []
        var porColuna: [[Celula]] = []
        for c in 0..<n {
            let brutas = tabela.linhas.map { $0[c] }
            let numerica = RegrasTabela.colunaNumerica(brutas)
            let direita = tabela.alinhamento[c].map { $0 == .direita } ?? numerica
            let separador = numerica ? nil : RegrasTabela.separadorDeLista(brutas)
            let f = numerica ? fonteNumero : fonte

            let estilo = NSMutableParagraphStyle()
            estilo.lineSpacing = 2
            estilo.alignment = direita ? .right : tabela.alinhamento[c] == .centro ? .center : .left
            if separador != nil {
                estilo.paragraphSpacing = Self.entreItens
                estilo.headIndent = 12      // item que quebra continua recuado: dá para ver onde começa o próximo
            }

            var maiorNatural: CGFloat = 0
            var maiorPalavra = 0
            let celulas: [Celula] = brutas.map { bruta in
                let limpo = RegrasTabela.limpo(bruta)
                let partes = separador.map { RegrasTabela.itens(bruta, separador: $0) } ?? [bruta]
                let texto = NSMutableAttributedString()
                var natural: CGFloat = 0
                for (k, parte) in partes.enumerated() {
                    let pedaco = Self.trecho(parte, fonte: f, cor: cor)
                    natural = max(natural, ceil(pedaco.size().width))
                    texto.append(pedaco)
                    if k < partes.count - 1 { texto.append(NSAttributedString(string: "\n", attributes: [.font: f])) }
                }
                var link: URL?
                if limpo.contains("/") || limpo.contains("www.") {
                    TextoRico.ligarEnderecos(texto, pasta: pasta)
                    // O texto é desenhado direto, sem campo de texto: o link ganha a cor aqui.
                    texto.enumerateAttribute(.link, in: NSRange(location: 0, length: texto.length)) { v, faixa, _ in
                        guard let u = v as? URL else { return }
                        if link == nil { link = u }
                        texto.removeAttribute(.link, range: faixa)
                        texto.addAttributes([.foregroundColor: NSColor(Tema.azul), .underlineStyle: NSUnderlineStyle.single.rawValue], range: faixa)
                    }
                }
                texto.addAttribute(.paragraphStyle, value: estilo, range: NSRange(location: 0, length: texto.length))
                maiorNatural = max(maiorNatural, natural)
                for palavra in limpo.split(separator: " ") { maiorPalavra = max(maiorPalavra, palavra.count) }
                return Celula(texto: texto, limpo: limpo, natural: natural, itens: max(partes.count, 1), link: link)
            }

            let estiloTitulo = NSMutableParagraphStyle()
            estiloTitulo.alignment = estilo.alignment
            estiloTitulo.lineBreakMode = .byWordWrapping
            let titulo = Self.trecho(tabela.cabecalho[c], fonte: fonteTitulo, cor: NSColor(Tema.texto2))
            let larguraTitulo = ceil(titulo.size().width) + 14    // espaço da seta de ordenação
            titulo.addAttribute(.paragraphStyle, value: estiloTitulo, range: NSRange(location: 0, length: titulo.length))

            let margens = Self.margemX * 2
            let natural = max(maiorNatural, larguraTitulo) + margens
            var minima = natural
            if !numerica && natural > 170 {
                if separador != nil {
                    minima = min(natural, 240 + margens)
                } else {
                    let palavra = CGFloat(maiorPalavra) * tamanho * 0.58
                    minima = min(natural, max(palavra, 150, larguraTitulo) + margens)
                }
            }
            colunas.append(Coluna(nome: RegrasTabela.limpo(tabela.cabecalho[c]), titulo: titulo, numerica: numerica,
                                  direita: direita, separador: separador, natural: natural, minima: minima))
            porColuna.append(celulas)
        }
        self.colunas = colunas
        celulas = tabela.linhas.indices.map { r in (0..<n).map { porColuna[$0][r] } }
    }

    /// O texto de uma célula. Sem marca de markdown (quase sempre), não passa pelo leitor.
    private static func trecho(_ s: String, fonte: NSFont, cor: NSColor) -> NSMutableAttributedString {
        guard s.contains(where: { "*_~`[<\\".contains($0) }) else {
            return NSMutableAttributedString(string: s, attributes: [.font: fonte, .foregroundColor: cor])
        }
        let comQuebra = s.replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
        return TextoRico.inline(comQuebra, fonte: fonte, cor: cor)
    }

    /// As linhas que aparecem, na ordem em que aparecem (índices da tabela original).
    func linhas(filtro: String, ordenacao: OrdenacaoTabela?) -> [Int] {
        var visiveis = RegrasTabela.filtrar(tabela.linhas, texto: filtro)
        if let o = ordenacao, o.coluna < colunas.count {
            let ordem = RegrasTabela.ordenar(tabela.linhas, coluna: o.coluna, crescente: o.crescente, numerica: colunas[o.coluna].numerica)
            let dentro = Set(visiveis)
            visiveis = ordem.filter { dentro.contains($0) }
        }
        return visiveis
    }
}

/// A tabela desenhada. Fica dentro de uma `RolagemTabela`.
final class VistaTabela: NSView {
    private(set) var modelo: ModeloTabela?
    private(set) var linhas: [Int] = []
    private var ordenacao: OrdenacaoTabela?

    var aoTocar: (@MainActor () -> Void)?
    var aoOrdenar: ((Int) -> Void)?
    var aoCopiar: ((String) -> Void)?
    /// Os itens do clique direito, para a célula (linha original, coluna) embaixo do mouse.
    var itensDoMenu: ((Int?, Int?) -> [ItemMenu])?

    // Leiaute
    private var disponivel: CGFloat = -1
    private var pronto = false
    private(set) var larguras: [CGFloat] = []
    private var xs: [CGFloat] = []
    private var alturas: [CGFloat] = []
    private var ys: [CGFloat] = []
    private(set) var alturaCabecalho: CGFloat = 30
    private(set) var tamanhoTotal: CGSize = .zero

    private let cabecalho = CabecalhoTabela()
    private var sobre: (linha: Int, coluna: Int)?
    private var piscando: (linha: Int, coluna: Int)?
    private var apertou: NSPoint?
    private var vigias: [NSObjectProtocol] = []

    static let fundoCabecalho = NSColor(Color(hex: "#1B1B20"))
    /// Só no modo de capturas: rola a conversa em volta até a tabela passar tantos pontos do
    /// topo, para fotografar o cabeçalho preso.
    static var rolarNaCaptura: CGFloat?
    /// O cabeçalho mudou de lugar (a rolagem em volta reposiciona as setas de borda).
    var aoMoverCabecalho: (() -> Void)?
    var topoCabecalho: CGFloat { cabecalho.frame.minY }

    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(cabecalho)
        cabecalho.aoClicar = { [weak self] c in self?.aoOrdenar?(c) }
    }

    required init?(coder: NSCoder) { fatalError("sem storyboard") }

    override var isFlipped: Bool { true }

    func definir(_ novo: ModeloTabela, linhas novas: [Int], ordenacao nova: OrdenacaoTabela?) {
        let mudou = novo !== modelo || novas != linhas
        if mudou || nova != ordenacao {
            modelo = novo
            linhas = novas
            ordenacao = nova
            if mudou { pronto = false; sobre = nil }
            cabecalho.ordenacao = nova
            needsDisplay = true
            cabecalho.needsDisplay = true
        }
    }

    // MARK: Leiaute

    /// Reparte as colunas na largura disponível e mede a altura de cada linha. Devolve o
    /// tamanho da tabela (pode ser mais larga que o disponível: aí rola para o lado).
    @discardableResult
    func preparar(disponivel novo: CGFloat, esticarAte: CGFloat = 0) -> CGSize {
        guard let modelo else { return .zero }
        if pronto, novo == disponivel { return tamanhoTotal }
        disponivel = novo
        pronto = true
        let r = RegrasTabela.larguras(naturais: modelo.naturais, minimas: modelo.minimas, disponivel: Double(novo))
        larguras = r.colunas.map { CGFloat($0.rounded(.down)) }
        // Tabela mais estreita que a barra de ações: a coluna de lista (ou, sem ela, a de texto
        // mais larga) leva a sobra, para as duas terminarem juntas.
        let sobra = min(esticarAte, novo) - larguras.reduce(0, +)
        let deTexto = modelo.colunas.indices.filter { !modelo.colunas[$0].numerica }
        if sobra > 0, let c = deTexto.last(where: { modelo.colunas[$0].separador != nil }) ?? deTexto.max(by: { larguras[$0] < larguras[$1] }) {
            larguras[c] += sobra
        }
        xs = []
        var x: CGFloat = 0
        for l in larguras { xs.append(x); x += l }
        let largura = max(x, 1)
        let margens = ModeloTabela.margemX * 2

        func altura(_ texto: NSAttributedString, _ larguraTexto: CGFloat) -> CGFloat {
            ceil(texto.boundingRect(with: NSSize(width: larguraTexto, height: .greatestFiniteMagnitude),
                                    options: [.usesLineFragmentOrigin, .usesFontLeading]).height)
        }
        var cab: CGFloat = 16
        for (c, coluna) in modelo.colunas.enumerated() {
            cab = max(cab, altura(coluna.titulo, larguras[c] - margens - 14))
        }
        alturaCabecalho = cab + 14

        alturas = []
        ys = []
        var y: CGFloat = 0
        for r in linhas {
            var h = modelo.alturaLinha
            for (c, celula) in modelo.celulas[r].enumerated() {
                let dentro = larguras[c] - margens
                if celula.natural <= dentro {
                    // Cabe numa linha (ou um item por linha): não precisa medir.
                    if celula.itens > 1 {
                        h = max(h, CGFloat(celula.itens) * (modelo.alturaLinha + 2) + CGFloat(celula.itens - 1) * ModeloTabela.entreItens - 2)
                    }
                } else {
                    h = max(h, altura(celula.texto, dentro))
                }
            }
            ys.append(y)
            alturas.append(h + ModeloTabela.margemY * 2)
            y += h + ModeloTabela.margemY * 2
        }
        if linhas.isEmpty { y = 44 }
        tamanhoTotal = CGSize(width: largura, height: alturaCabecalho + y)
        setFrameSize(tamanhoTotal)
        cabecalho.modelo = modelo
        cabecalho.larguras = larguras
        fixarCabecalho()
        needsDisplay = true
        return tamanhoTotal
    }

    // MARK: Cabeçalho preso

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        for v in vigias { NotificationCenter.default.removeObserver(v) }
        vigias = []
        guard window != nil else { return }
        // Toda rolagem em volta (a da tabela e a da conversa) reposiciona o cabeçalho.
        var v = superview
        while let atual = v {
            if let recorte = atual as? NSClipView {
                recorte.postsBoundsChangedNotifications = true
                vigias.append(NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: recorte, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.fixarCabecalho() }
                })
            }
            v = atual.superview
        }
        fixarCabecalho()
        if let quanto = Self.rolarNaCaptura {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.rolarParaCaptura(quanto) }
        }
    }

    /// O cabeçalho acompanha o topo da parte visível da tabela, até a última linha.
    func fixarCabecalho() {
        var y: CGFloat = 0
        let visivel = visibleRect
        if !visivel.isEmpty, visivel.minY > 0 {
            let limite = bounds.height - alturaCabecalho - (alturas.last ?? 0)
            y = max(0, min(visivel.minY, limite))
        }
        let novo = NSRect(x: 0, y: y, width: bounds.width, height: alturaCabecalho)
        if cabecalho.frame != novo { cabecalho.frame = novo }
        if cabecalho.flutuando != (y > 0) { cabecalho.flutuando = y > 0; cabecalho.needsDisplay = true }
        aoMoverCabecalho?()
    }

    private func rolarParaCaptura(_ quanto: CGFloat) {
        var fora: NSScrollView?
        var v = superview
        while let atual = v {
            if let r = atual as? NSScrollView, !(r is RolagemTabela) { fora = r }
            v = atual.superview
        }
        guard let fora, let documento = fora.documentView else { return }
        let topo = documento.convert(NSPoint.zero, from: self).y
        fora.contentView.scroll(to: NSPoint(x: 0, y: topo + (documento.isFlipped ? quanto : -quanto)))
        fora.reflectScrolledClipView(fora.contentView)
        fixarCabecalho()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        fixarCabecalho()
    }

    // MARK: Desenho

    private func retangulo(linha i: Int) -> NSRect {
        NSRect(x: 0, y: alturaCabecalho + ys[i], width: bounds.width, height: alturas[i])
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let modelo, pronto else { return }
        if linhas.isEmpty {
            let aviso = NSAttributedString(string: "Nenhuma linha com esse texto.", attributes: [
                .font: NSFont.systemFont(ofSize: modelo.tamanho - 0.5), .foregroundColor: NSColor(Tema.texto3)])
            aviso.draw(at: NSPoint(x: ModeloTabela.margemX, y: alturaCabecalho + 13))
            return
        }
        for i in linhas.indices {
            let r = retangulo(linha: i)
            if r.maxY < dirtyRect.minY { continue }
            if r.minY > dirtyRect.maxY { break }
            let original = linhas[i]
            if i % 2 == 1 {
                NSColor.white.withAlphaComponent(0.034).setFill()
                r.fill()
            }
            if sobre?.linha == i {
                NSColor.white.withAlphaComponent(0.04).setFill()
                r.fill()
            }
            if i > 0 {
                NSColor.white.withAlphaComponent(0.055).setFill()
                NSRect(x: 0, y: r.minY, width: r.width, height: 1).fill()
            }
            for (c, celula) in modelo.celulas[original].enumerated() where c < larguras.count {
                let caixa = NSRect(x: xs[c], y: r.minY, width: larguras[c], height: r.height)
                guard caixa.intersects(dirtyRect) else { continue }
                if let p = piscando, p.linha == original, p.coluna == c {
                    NSColor(Tema.verde).withAlphaComponent(0.2).setFill()
                    NSBezierPath(roundedRect: caixa.insetBy(dx: 3, dy: 2), xRadius: 5, yRadius: 5).fill()
                } else if let s = sobre, s.linha == i, s.coluna == c, !celula.limpo.isEmpty {
                    NSColor.white.withAlphaComponent(0.06).setFill()
                    NSBezierPath(roundedRect: caixa.insetBy(dx: 3, dy: 2), xRadius: 5, yRadius: 5).fill()
                }
                celula.texto.draw(with: caixa.insetBy(dx: ModeloTabela.margemX, dy: ModeloTabela.margemY),
                                  options: [.usesLineFragmentOrigin, .usesFontLeading])
            }
        }
    }

    // MARK: Mouse

    private func celula(em ponto: NSPoint) -> (linha: Int, coluna: Int)? {
        let y = ponto.y - alturaCabecalho
        guard y >= 0, let i = ys.indices.last(where: { ys[$0] <= y }), y < ys[i] + alturas[i],
              let c = xs.indices.last(where: { xs[$0] <= ponto.x }), ponto.x < xs[c] + larguras[c] else { return nil }
        return (i, c)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    private func marcar(_ novo: (linha: Int, coluna: Int)?) {
        guard novo?.linha != sobre?.linha || novo?.coluna != sobre?.coluna else { return }
        for i in [sobre?.linha, novo?.linha].compactMap({ $0 }) where i < alturas.count { setNeedsDisplay(retangulo(linha: i)) }
        sobre = novo
    }

    override func mouseMoved(with event: NSEvent) { marcar(celula(em: convert(event.locationInWindow, from: nil))) }
    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
    override func mouseExited(with event: NSEvent) { marcar(nil) }

    override func mouseDown(with event: NSEvent) {
        aoTocar?()
        apertou = convert(event.locationInWindow, from: nil)
    }

    /// Clique numa célula copia o valor dela (com ⌘, abre o link ou o arquivo que ela cita).
    override func mouseUp(with event: NSEvent) {
        let ponto = convert(event.locationInWindow, from: nil)
        defer { apertou = nil }
        guard let modelo, let a = apertou, abs(a.x - ponto.x) < 4, abs(a.y - ponto.y) < 4,
              let alvo = celula(em: ponto) else { return }
        let original = linhas[alvo.linha]
        let celula = modelo.celulas[original][alvo.coluna]
        if event.modifierFlags.contains(.command), let link = celula.link {
            TextoRico.abrir(link)
            return
        }
        guard !celula.limpo.isEmpty else { return }
        VistaTexto.copiar(celula.limpo)
        piscar(original, alvo.coluna)
        aoCopiar?(celula.limpo)
    }

    private func piscar(_ linha: Int, _ coluna: Int) {
        piscando = (linha, coluna)
        needsDisplay = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            guard let self, self.piscando?.linha == linha, self.piscando?.coluna == coluna else { return }
            self.piscando = nil
            self.needsDisplay = true
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        let alvo = celula(em: convert(event.locationInWindow, from: nil))
        guard let itens = itensDoMenu?(alvo.map { linhas[$0.linha] }, alvo?.coluna), !itens.isEmpty else { return }
        MenuCrew.abrirNoMouse(itens)
    }
}

/// A linha de títulos da tabela. Clique num título ordena por aquela coluna.
final class CabecalhoTabela: NSView {
    var modelo: ModeloTabela? { didSet { needsDisplay = true } }
    var larguras: [CGFloat] = [] { didSet { needsDisplay = true } }
    var ordenacao: OrdenacaoTabela?
    /// Está preso no topo, por cima das linhas: ganha uma sombra embaixo.
    var flutuando = false
    var aoClicar: ((Int) -> Void)?
    private var sobre: Int?

    override var isFlipped: Bool { true }

    private func coluna(em x: CGFloat) -> Int? {
        var inicio: CGFloat = 0
        for (c, l) in larguras.enumerated() {
            if x >= inicio && x < inicio + l { return c }
            inicio += l
        }
        return nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    private func marcar(_ novo: Int?) {
        guard novo != sobre else { return }
        sobre = novo
        toolTip = novo.flatMap { c in modelo.map { "Ordenar por \($0.colunas[c].nome.isEmpty ? "esta coluna" : $0.colunas[c].nome)" } }
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) { marcar(coluna(em: convert(event.locationInWindow, from: nil).x)) }
    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
    override func mouseExited(with event: NSEvent) { marcar(nil) }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    override func mouseDown(with event: NSEvent) {
        if let c = coluna(em: convert(event.locationInWindow, from: nil).x) { aoClicar?(c) }
    }

    override func draw(_ dirtyRect: NSRect) {
        VistaTabela.fundoCabecalho.setFill()
        bounds.fill()
        NSColor.white.withAlphaComponent(flutuando ? 0.16 : 0.09).setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
        guard let modelo else { return }
        var x: CGFloat = 0
        for (c, coluna) in modelo.colunas.enumerated() where c < larguras.count {
            defer { x += larguras[c] }
            let ordenada = ordenacao?.coluna == c
            let titulo = NSMutableAttributedString(attributedString: coluna.titulo)
            if ordenada || sobre == c {
                titulo.addAttribute(.foregroundColor, value: NSColor(Tema.texto), range: NSRange(location: 0, length: titulo.length))
            }
            // A seta fica do lado de fora do texto: à esquerda nas colunas alinhadas à direita.
            let seta: CGFloat = 14
            let dentro = NSRect(x: x + ModeloTabela.margemX + (coluna.direita ? seta : 0), y: 0,
                                width: larguras[c] - ModeloTabela.margemX * 2 - seta, height: bounds.height)
            let caixa = titulo.boundingRect(with: NSSize(width: dentro.width, height: .greatestFiniteMagnitude),
                                            options: [.usesLineFragmentOrigin, .usesFontLeading])
            let y = floor((bounds.height - ceil(caixa.height)) / 2)
            titulo.draw(with: NSRect(x: dentro.minX, y: y, width: dentro.width, height: ceil(caixa.height)),
                        options: [.usesLineFragmentOrigin, .usesFontLeading])
            guard ordenada || sobre == c else { continue }
            let simbolo = ordenada ? (ordenacao?.crescente == true ? "chevron.up" : "chevron.down") : "chevron.up.chevron.down"
            let cor = ordenada ? NSColor(Tema.azul) : NSColor(Tema.texto3)
            let config = NSImage.SymbolConfiguration(pointSize: 8, weight: .bold).applying(.init(paletteColors: [cor]))
            guard let img = NSImage(systemSymbolName: simbolo, accessibilityDescription: nil)?.withSymbolConfiguration(config) else { continue }
            let largura = min(ceil(caixa.width), dentro.width)
            let sx = coluna.direita ? dentro.maxX - largura - img.size.width - 4 : dentro.minX + largura + 4
            img.draw(in: NSRect(x: sx, y: floor((bounds.height - img.size.height) / 2), width: img.size.width, height: img.size.height))
        }
    }
}

/// A rolagem em volta da tabela. Na conversa só rola para o lado (e só quando a tabela não
/// cabe): a roda para cima e para baixo segue para a conversa. Ampliada, rola nos dois sentidos.
final class RolagemTabela: NSScrollView {
    let tabela = VistaTabela()
    var vertical = false {
        didSet {
            hasVerticalScroller = vertical
            verticalScrollElasticity = vertical ? .automatic : .none
            moldura()
        }
    }

    /// Na conversa a tabela tem a própria moldura; ampliada, quem emoldura é o cartão em volta.
    private func moldura() {
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerRadius = vertical ? 0 : 10
        layer?.borderWidth = vertical ? 0 : 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.09).cgColor
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.018).cgColor
    }

    private let bordaEsquerda = BordaRolagem(direita: false)
    private let bordaDireita = BordaRolagem(direita: true)
    private var vigia: NSObjectProtocol?

    override init(frame: NSRect) {
        super.init(frame: frame)
        drawsBackground = false
        borderType = .noBorder
        hasHorizontalScroller = true
        hasVerticalScroller = false
        autohidesScrollers = true
        scrollerStyle = .overlay
        verticalScrollElasticity = .none
        horizontalScrollElasticity = .automatic
        automaticallyAdjustsContentInsets = false
        documentView = tabela
        moldura()
        // Tabela mais larga que o espaço: uma seta em cada borda que ainda tem coluna escondida.
        for borda in [bordaEsquerda, bordaDireita] {
            addSubview(borda)
            borda.aoClicar = { [weak self] sentido in self?.andar(sentido) }
        }
        tabela.aoMoverCabecalho = { [weak self] in self?.atualizarBordas() }
        contentView.postsBoundsChangedNotifications = true
        vigia = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: contentView, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.atualizarBordas() }
        }
    }

    private func atualizarBordas() {
        let visivel = contentView.bounds
        let total = tabela.frame.width
        bordaEsquerda.isHidden = visivel.minX <= 1
        bordaDireita.isHidden = visivel.maxX >= total - 1
        let largura: CGFloat = 44
        bordaEsquerda.frame = NSRect(x: 0, y: 0, width: largura, height: bounds.height)
        bordaDireita.frame = NSRect(x: bounds.width - largura, y: 0, width: largura, height: bounds.height)
        // A seta fica na altura do cabeçalho, onde quer que ele esteja preso.
        let topo = tabela.topoCabecalho - (vertical ? visivel.minY : 0) + tabela.alturaCabecalho / 2
        for borda in [bordaEsquerda, bordaDireita] where borda.centro != topo {
            borda.centro = topo
            borda.needsDisplay = true
        }
    }

    /// Anda uma boa parte da largura visível para o lado (clique na seta da borda).
    private func andar(_ sentido: CGFloat) {
        let visivel = contentView.bounds
        let x = max(0, min(visivel.minX + sentido * visivel.width * 0.7, tabela.frame.width - visivel.width))
        NSAnimationContext.runAnimationGroup { contexto in
            contexto.duration = 0.25
            contentView.animator().setBoundsOrigin(NSPoint(x: x, y: visivel.minY))
        }
        reflectScrolledClipView(contentView)
    }

    override func tile() {
        super.tile()
        atualizarBordas()
    }

    required init?(coder: NSCoder) { fatalError("sem storyboard") }

    override func scrollWheel(with event: NSEvent) {
        if vertical { super.scrollWheel(with: event); return }
        let cabe = tabela.frame.width <= contentSize.width + 0.5
        if cabe || abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) {
            nextResponder?.scrollWheel(with: event)
        } else {
            super.scrollWheel(with: event)
        }
    }

    /// Ampliada, a tabela ocupa a largura da janela: refaz as colunas quando o tamanho muda.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if vertical, newSize.width > 0 { tabela.preparar(disponivel: newSize.width) }
    }
}

/// A borda de uma tabela que continua para o lado: escurece as colunas que estão saindo e mostra
/// a seta que anda para lá (para quem está no mouse, sem rolagem lateral).
final class BordaRolagem: NSView {
    let direita: Bool
    var centro: CGFloat = 20
    var aoClicar: ((CGFloat) -> Void)?
    private var sobre = false

    init(direita: Bool) {
        self.direita = direita
        super.init(frame: .zero)
        toolTip = direita ? "Mais colunas à direita" : "Voltar para a esquerda"
    }

    required init?(coder: NSCoder) { fatalError("sem storyboard") }

    override var isFlipped: Bool { true }

    private var botao: NSRect {
        NSRect(x: direita ? bounds.width - 30 : 6, y: centro - 12, width: 24, height: 24)
    }

    // Só a seta pega o clique: o resto da faixa deixa passar para a tabela.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, let s = superview else { return nil }
        return botao.insetBy(dx: -4, dy: -4).contains(convert(point, from: s)) ? self : nil
    }

    override func mouseDown(with event: NSEvent) { aoClicar?(direita ? 1 : -1) }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        let novo = botao.insetBy(dx: -4, dy: -4).contains(convert(event.locationInWindow, from: nil))
        if novo != sobre { sobre = novo; needsDisplay = true }
    }
    override func mouseExited(with event: NSEvent) { if sobre { sobre = false; needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let fundo = NSColor(Tema.fundo)
        let degrade = NSGradient(colors: [fundo.withAlphaComponent(0), fundo.withAlphaComponent(0.92)])
        degrade?.draw(in: bounds, angle: direita ? 0 : 180)
        let b = botao
        let circulo = NSBezierPath(ovalIn: b)
        NSColor(Color(hex: sobre ? "#34343B" : "#26262C")).setFill()
        circulo.fill()
        NSColor.white.withAlphaComponent(0.16).setStroke()
        circulo.lineWidth = 1
        circulo.stroke()
        let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .bold).applying(.init(paletteColors: [NSColor(Tema.texto)]))
        if let img = NSImage(systemSymbolName: direita ? "chevron.right" : "chevron.left", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
            img.draw(in: NSRect(x: b.midX - img.size.width / 2, y: b.midY - img.size.height / 2, width: img.size.width, height: img.size.height))
        }
    }
}

/// A tabela dentro do SwiftUI.
struct TabelaRolavel: NSViewRepresentable {
    let modelo: ModeloTabela
    let linhas: [Int]
    let ordenacao: OrdenacaoTabela?
    var vertical = false
    /// Largura da barra de ações: tabela mais estreita que isso estica até aqui.
    var esticarAte: CGFloat = 0
    let aoOrdenar: (Int) -> Void
    let aoCopiar: (String) -> Void
    let menu: (Int?, Int?) -> [ItemMenu]
    @Environment(\.aoTocarTexto) private var aoTocar

    func makeNSView(context: Context) -> RolagemTabela {
        let v = RolagemTabela(frame: .zero)
        v.vertical = vertical
        atualizar(v)
        return v
    }

    func updateNSView(_ v: RolagemTabela, context: Context) { atualizar(v) }

    private func atualizar(_ v: RolagemTabela) {
        v.tabela.aoTocar = aoTocar
        v.tabela.aoOrdenar = aoOrdenar
        v.tabela.aoCopiar = aoCopiar
        v.tabela.itensDoMenu = menu
        v.tabela.definir(modelo, linhas: linhas, ordenacao: ordenacao)
        if vertical, v.frame.width > 0 { v.tabela.preparar(disponivel: v.frame.width) }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView v: RolagemTabela, context: Context) -> CGSize? {
        if vertical { return proposal.replacingUnspecifiedDimensions(by: CGSize(width: 800, height: 500)) }
        var largura = proposal.width ?? 600
        if !largura.isFinite || largura <= 0 { largura = 600 }
        let t = v.tabela.preparar(disponivel: largura, esticarAte: esticarAte)
        return CGSize(width: min(t.width, largura), height: t.height)
    }
}
