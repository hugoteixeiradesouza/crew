import SwiftUI
import AppKit

// O menu do app do Crew: um balão só, com a mesma cara, para tudo que abre uma lista de
// escolhas — chip que abre opções (projeto, modelo, modo), o "…" do cabeçalho, dividir a tela
// e o clique com o botão direito. Quem usa descreve os itens (`ItemMenu`) e escolhe o gatilho:
// `BotaoMenu` / `MenuChip` (abre embaixo do botão) ou `.menuContexto { … }` (abre no mouse).
// Teclado: ↑ ↓ andam, Enter escolhe, Esc fecha. Clique fora fecha sem acionar o que está embaixo.

/// Uma linha do menu.
@MainActor
struct ItemMenu: Identifiable {
    enum Tipo { case acao, divisor, titulo }

    let id = UUID()
    var tipo: Tipo = .acao
    var titulo = ""
    /// Segunda linha, apagada (explica a opção).
    var detalhe: String? = nil
    /// SF Symbol à esquerda.
    var icone: String? = nil
    /// Bolinha de cor à esquerda (projeto).
    var ponto: Color? = nil
    /// A opção em vigor (ganha o "check" à direita).
    var marcado = false
    var destrutivo = false
    var desabilitado = false
    var acao: @MainActor () -> Void = {}

    static func acao(_ titulo: String, icone: String? = nil, ponto: Color? = nil, detalhe: String? = nil,
                     marcado: Bool = false, destrutivo: Bool = false, desabilitado: Bool = false,
                     _ acao: @escaping @MainActor () -> Void) -> ItemMenu {
        ItemMenu(titulo: titulo, detalhe: detalhe, icone: icone, ponto: ponto, marcado: marcado,
                 destrutivo: destrutivo, desabilitado: desabilitado, acao: acao)
    }

    static var divisor: ItemMenu { ItemMenu(tipo: .divisor) }
    static func titulo(_ t: String) -> ItemMenu { ItemMenu(tipo: .titulo, titulo: t) }

    var escolhivel: Bool { tipo == .acao && !desabilitado }
}

// MARK: - Apresentação

@MainActor
private final class EstadoMenu: ObservableObject {
    @Published var realce: UUID?
}

/// O conteúdo do balão.
private struct ListaMenu: View {
    let itens: [ItemMenu]
    @ObservedObject var estado: EstadoMenu
    /// Largura e altura fixas quando a lista não cabe na tela (vira rolagem).
    var caixa: CGSize? = nil
    let escolher: (ItemMenu) -> Void

    private var temEsquerda: Bool { itens.contains { $0.icone != nil || $0.ponto != nil } }

    var body: some View {
        Group {
            if let caixa {
                ScrollView { linhas }.scrollIndicators(.never).frame(width: caixa.width, height: caixa.height)
            } else {
                linhas.frame(minWidth: 190, maxWidth: 380).fixedSize()
            }
        }
        .background(Tema.elevado)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Tema.bordaForte))
        .environment(\.colorScheme, .dark)
    }

    private var linhas: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(itens) { item in
                switch item.tipo {
                case .divisor:
                    Rectangle().fill(Tema.borda).frame(height: 1).padding(.vertical, 4).padding(.horizontal, 8)
                case .titulo:
                    Text(item.titulo)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Tema.texto3)
                        .padding(.horizontal, 10).padding(.top, 6).padding(.bottom, 3)
                case .acao:
                    linha(item)
                }
            }
        }
        .padding(5)
    }

    private func linha(_ item: ItemMenu) -> some View {
        let cor = item.destrutivo ? Tema.vermelho : Tema.texto
        return HStack(spacing: 9) {
            if temEsquerda {
                Group {
                    if let p = item.ponto { Circle().fill(p).frame(width: 7, height: 7) }
                    else if let i = item.icone { Image(systemName: i).font(.system(size: 11.5, weight: .medium)) }
                    else { Color.clear }
                }
                .foregroundStyle(item.destrutivo ? Tema.vermelho : Tema.texto2)
                .frame(width: 16, height: 16)
            }
            VStack(alignment: .leading, spacing: 1.5) {
                Text(item.titulo).font(.system(size: 13)).foregroundStyle(cor).lineLimit(1)
                if let d = item.detalhe {
                    Text(d).font(.system(size: 11)).foregroundStyle(Tema.texto3).lineLimit(1)
                }
            }
            Spacer(minLength: 14)
            if item.marcado {
                Image(systemName: "checkmark").font(.system(size: 10.5, weight: .bold)).foregroundStyle(Tema.texto)
            }
        }
        .padding(.horizontal, 10)
        .frame(minHeight: item.detalhe == nil ? 30 : 42)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(estado.realce == item.id ? Color.white.opacity(0.09) : .clear))
        .contentShape(Rectangle())
        .opacity(item.desabilitado ? 0.4 : 1)
        .onHover { dentro in
            guard item.escolhivel else { return }
            if dentro { estado.realce = item.id } else if estado.realce == item.id { estado.realce = nil }
        }
        .onTapGesture { if item.escolhivel { escolher(item) } }
    }
}

/// A janela do balão: sem moldura, recebe o teclado enquanto está aberta.
private final class PainelMenu: NSPanel {
    var aoTeclar: ((UInt16) -> Bool)?
    var aoPerderFoco: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        if aoTeclar?(event.keyCode) != true { super.keyDown(with: event) }
    }

    override func resignKey() {
        super.resignKey()
        aoPerderFoco?()
    }
}

@MainActor
enum MenuCrew {
    private static var painel: PainelMenu?
    private static var vigia: Any?
    private static var itensAbertos: [ItemMenu] = []
    private static let estado = EstadoMenu()

    static var aberto: Bool { painel != nil }

    /// Só no modo de capturas do app: o balão desenhado sem janela.
    static func vistaParaCaptura(_ itens: [ItemMenu]) -> AnyView {
        AnyView(ListaMenu(itens: itens, estado: EstadoMenu(), escolher: { _ in }))
    }

    /// Abre embaixo de um botão (o retângulo dele na tela); sem espaço, abre em cima.
    static func abrir(_ itens: [ItemMenu], abaixoDe ancora: NSRect) {
        mostrar(itens) { tamanho, tela in
            var y = ancora.minY - 6 - tamanho.height
            if y < tela.minY + 8 { y = min(ancora.maxY + 6, tela.maxY - tamanho.height - 8) }
            return NSPoint(x: ancora.minX, y: y)
        }
    }

    /// Abre onde o mouse está (clique com o botão direito).
    static func abrirNoMouse(_ itens: [ItemMenu]) {
        let p = NSEvent.mouseLocation
        mostrar(itens) { tamanho, tela in
            var y = p.y - tamanho.height
            if y < tela.minY + 8 { y = min(p.y, tela.maxY - tamanho.height - 8) }
            return NSPoint(x: p.x + 2, y: y)
        }
    }

    static func fechar() {
        guard let p = painel else { return }
        painel = nil
        if let v = vigia { NSEvent.removeMonitor(v) }
        vigia = nil
        itensAbertos = []
        p.aoPerderFoco = nil
        p.orderOut(nil)
    }

    private static func escolher(_ item: ItemMenu) {
        fechar()
        // No próximo passo: a janela do app já voltou a ser a principal.
        DispatchQueue.main.async { item.acao() }
    }

    private static func mostrar(_ itens: [ItemMenu], onde: (NSSize, NSRect) -> NSPoint) {
        fechar()
        guard itens.contains(where: { $0.tipo == .acao }), !CaptureTool.ativo else { return }
        let mouse = NSEvent.mouseLocation
        let tela = (NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        estado.realce = nil
        itensAbertos = itens

        // Mede a lista inteira; se não couber na tela, vira rolagem na altura que cabe.
        var host = NSHostingView(rootView: ListaMenu(itens: itens, estado: estado, escolher: escolher))
        var tamanho = host.fittingSize
        let alturaMax = min(460, tela.height - 40)
        if tamanho.height > alturaMax {
            tamanho.height = alturaMax
            host = NSHostingView(rootView: ListaMenu(itens: itens, estado: estado, caixa: tamanho, escolher: escolher))
        }

        var origem = onde(tamanho, tela)
        origem.x = max(tela.minX + 8, min(origem.x, tela.maxX - tamanho.width - 8))
        origem.y = max(tela.minY + 8, origem.y)

        let p = PainelMenu(contentRect: NSRect(origin: origem, size: tamanho),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isReleasedWhenClosed = false
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .popUpMenu
        p.acceptsMouseMovedEvents = true
        host.frame = NSRect(origin: .zero, size: tamanho)
        p.contentView = host
        p.aoTeclar = { tecla in teclar(tecla) }
        p.aoPerderFoco = { fechar() }
        painel = p

        // Clique fora do balão: fecha e não aciona o que está embaixo (como um menu do sistema).
        vigia = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { evento in
            let janela = evento.window
            let fora: Bool = MainActor.assumeIsolated {
                guard let aberto = painel, janela !== aberto else { return false }
                fechar()
                return true
            }
            return fora ? nil : evento
        }

        p.alphaValue = 0
        p.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { c in
            c.duration = 0.12
            p.animator().alphaValue = 1
        }
    }

    /// ↑ ↓ andam, Enter escolhe, Esc fecha.
    private static func teclar(_ tecla: UInt16) -> Bool {
        let escolhiveis = itensAbertos.filter(\.escolhivel)
        let atual = escolhiveis.firstIndex { $0.id == estado.realce }
        switch tecla {
        case 53:
            fechar()
        case 125:
            estado.realce = escolhiveis.isEmpty ? nil : escolhiveis[min((atual ?? -1) + 1, escolhiveis.count - 1)].id
        case 126:
            estado.realce = escolhiveis.isEmpty ? nil : escolhiveis[max((atual ?? escolhiveis.count) - 1, 0)].id
        case 36, 76:
            if let i = atual { escolher(escolhiveis[i]) }
        default:
            return false
        }
        return true
    }
}

// MARK: - Gatilhos

/// Guarda a vista do botão para saber onde ele está na tela.
private final class CaixaAncora {
    weak var vista: NSView?
    var naTela: NSRect? {
        guard let v = vista, let janela = v.window else { return nil }
        return janela.convertToScreen(v.convert(v.bounds, to: nil))
    }
}

private struct AncoraMenu: NSViewRepresentable {
    let caixa: CaixaAncora
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        caixa.vista = v
        return v
    }
    func updateNSView(_ v: NSView, context: Context) { caixa.vista = v }
}

/// Qualquer botão que abre o menu do Crew embaixo dele.
struct BotaoMenu<Rotulo: View>: View {
    let itens: @MainActor () -> [ItemMenu]
    @ViewBuilder let rotulo: () -> Rotulo
    @State private var caixa = CaixaAncora()

    var body: some View {
        Button {
            if let r = caixa.naTela { MenuCrew.abrir(itens(), abaixoDe: r) }
        } label: {
            rotulo()
        }
        .buttonStyle(.plain)
        .background(AncoraMenu(caixa: caixa))
    }
}

/// Botão redondo de ícone que abre o menu ("…", dividir a tela).
struct BotaoIconeMenu: View {
    let icone: String
    var ajuda = ""
    let itens: @MainActor () -> [ItemMenu]
    @State private var hover = false

    var body: some View {
        BotaoMenu(itens: itens) {
            Image(systemName: icone)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(hover ? Tema.texto : Tema.texto2)
                .frame(width: 28, height: 28)
                .background(Circle().fill(hover ? Tema.hover : .clear))
                .contentShape(Circle())
        }
        .onHover { hover = $0 }
        .help(ajuda)
    }
}

/// Pega o clique com o botão direito (e o ⌃ clique) sem atrapalhar os outros cliques.
private struct CliqueDireito: NSViewRepresentable {
    let itens: @MainActor () -> [ItemMenu]

    final class Vista: NSView {
        var itens: (@MainActor () -> [ItemMenu])?

        private static func ehDireito(_ e: NSEvent?) -> Bool {
            guard let e else { return false }
            return e.type == .rightMouseDown || (e.type == .leftMouseDown && e.modifierFlags.contains(.control))
        }

        // Só existe para o clique direito: qualquer outro evento passa direto para a tela.
        override func hitTest(_ point: NSPoint) -> NSView? {
            Self.ehDireito(NSApp.currentEvent) ? super.hitTest(point) : nil
        }

        override func rightMouseDown(with event: NSEvent) { abrir() }
        override func mouseDown(with event: NSEvent) {
            if Self.ehDireito(event) { abrir() } else { super.mouseDown(with: event) }
        }

        private func abrir() {
            if let itens { MenuCrew.abrirNoMouse(itens()) }
        }
    }

    func makeNSView(context: Context) -> Vista {
        let v = Vista()
        v.itens = itens
        return v
    }
    func updateNSView(_ v: Vista, context: Context) { v.itens = itens }
}

extension View {
    /// Clique com o botão direito abre o menu do Crew com estes itens.
    func menuContexto(_ itens: @escaping @MainActor () -> [ItemMenu]) -> some View {
        overlay(CliqueDireito(itens: itens))
    }
}

/// Seletor de uma opção entre várias, no padrão do Crew: mostra a opção em vigor e abre o
/// menu do Crew com as outras. Substitui o seletor do sistema nas páginas de Ajustes.
struct SeletorCrew<Valor: Hashable>: View {
    @Binding var selecao: Valor
    let opcoes: [(valor: Valor, titulo: String)]
    /// Largura fixa (nil = do tamanho do texto).
    var largura: CGFloat? = nil
    /// O que aparece quando a opção em vigor não está na lista.
    var vazio = "Escolher"
    @State private var hover = false

    var body: some View {
        BotaoMenu(itens: {
            opcoes.map { o in ItemMenu.acao(o.titulo, marcado: o.valor == selecao) { selecao = o.valor } }
        }) {
            HStack(spacing: 8) {
                Text(opcoes.first { $0.valor == selecao }?.titulo ?? vazio)
                    .font(.system(size: 12.5))
                    .lineLimit(1)
                if largura != nil { Spacer(minLength: 0) }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(Tema.texto3)
            }
            .foregroundStyle(Tema.texto)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .frame(width: largura, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(hover ? 0.1 : 0.06)))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Tema.borda))
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .onHover { hover = $0 }
    }
}
