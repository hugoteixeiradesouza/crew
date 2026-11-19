import SwiftUI
import AppKit

// O tema do app do Crew: escuro, calmo, com cara de app de conversa. Cores, medidas e as
// peças que se repetem (botões, chips, abas, o Homie vivo). Tudo que a janela das sessões
// desenha sai daqui — nada de List/Picker/botão com a cara padrão do sistema.

enum Tema {
    // Superfícies (do fundo para a frente)
    static let fundo = Color(hex: "#0A0A0C")
    static let lateral = Color(hex: "#0F0F12")
    static let painel = Color(hex: "#151518")
    static let elevado = Color(hex: "#1C1C21")

    // Linhas e estados de toque
    static let borda = Color.white.opacity(0.07)
    static let bordaForte = Color.white.opacity(0.14)
    static let hover = Color.white.opacity(0.05)
    static let selecao = Color.white.opacity(0.09)

    // Texto
    static let texto = Color(hex: "#F1F2F4")
    static let texto2 = Color(hex: "#A1A5AE")
    static let texto3 = Color(hex: "#6A6E77")

    // Destaque: um só — o branco do Homie. Ação principal é pílula clara com texto escuro.
    static let destaque = Color(hex: "#F1F2F4")
    static let sobreDestaque = Color(hex: "#0B0C0E")

    // Estados das sessões (as mesmas cores da ilha)
    static let ambar = Color(hex: "#FBBF24")
    static let azul = Color(hex: "#38BDF8")
    static let verde = Color(hex: "#34D399")
    static let vermelho = Color(hex: "#F87171")
    static let cinza = Color(hex: "#9398A1")

    // Medidas
    static let larguraLateral: CGFloat = 280
    static let larguraConversa: CGFloat = 760
    static let raioCartao: CGFloat = 18
    static let raioLinha: CGFloat = 10

    /// Títulos: SF arredondada.
    static func titulo(_ tamanho: CGFloat, _ peso: Font.Weight = .semibold) -> Font {
        .system(size: tamanho, weight: peso, design: .rounded)
    }
}

// MARK: - Botões

/// Botão redondo só com ícone (ações do cabeçalho, anexar, "+").
struct BotaoIcone: View {
    let icone: String
    var ajuda = ""
    var lado: CGFloat = 28
    var cor: Color = Tema.texto2
    var corHover: Color = Tema.texto
    var ativo = false
    let acao: () -> Void

    @State private var hover = false
    @Environment(\.isEnabled) private var habilitado

    var body: some View {
        Button(action: acao) {
            Image(systemName: icone)
                .font(.system(size: lado * 0.46, weight: .medium))
                .foregroundStyle(ativo || hover ? corHover : cor)
                .frame(width: lado, height: lado)
                .background(Circle().fill(ativo ? Tema.selecao : hover ? Tema.hover : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(ajuda)
        .opacity(habilitado ? 1 : 0.35)
    }
}

/// Botão em pílula, com texto (e ícone). Um estilo por papel.
struct BotaoPilula: View {
    enum Estilo { case primario, secundario, discreto, ambar, azul, perigo }

    let titulo: String
    var icone: String? = nil
    var estilo: Estilo = .secundario
    var altura: CGFloat = 32
    var ocupado = false
    let acao: () -> Void

    @State private var hover = false
    @Environment(\.isEnabled) private var habilitado

    var body: some View {
        Button(action: acao) {
            HStack(spacing: 6) {
                if ocupado {
                    ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 14, height: 14)
                } else if let icone {
                    Image(systemName: icone).font(.system(size: altura * 0.36, weight: .semibold))
                }
                Text(titulo).font(.system(size: altura * 0.4, weight: .semibold)).lineLimit(1)
            }
            .foregroundStyle(corTexto)
            .padding(.horizontal, altura * 0.45)
            .frame(height: altura)
            .background(Pilula().fill(corFundo))
            .overlay(Pilula().strokeBorder(estilo == .secundario ? Tema.borda : .clear))
            .contentShape(Pilula())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .opacity(habilitado ? 1 : 0.4)
    }

    private var corTexto: Color {
        switch estilo {
        case .primario, .ambar, .azul: return Tema.sobreDestaque
        case .secundario: return Tema.texto
        case .discreto: return hover ? Tema.texto : Tema.texto2
        case .perigo: return Tema.vermelho
        }
    }

    private var corFundo: Color {
        switch estilo {
        case .primario: return hover ? .white : Tema.destaque
        case .ambar: return hover ? Tema.ambar.clarear(0.15) : Tema.ambar
        case .azul: return hover ? Tema.azul.clarear(0.15) : Tema.azul
        case .secundario: return Color.white.opacity(hover ? 0.13 : 0.07)
        case .discreto: return hover ? Tema.hover : .clear
        case .perigo: return Tema.vermelho.opacity(hover ? 0.22 : 0.13)
        }
    }
}

private extension Color {
    /// Mistura com branco (0…1) — o realce do hover nas pílulas coloridas.
    func clarear(_ quanto: Double) -> Color {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .white
        return Color(red: Double(c.redComponent) + (1 - Double(c.redComponent)) * quanto,
                     green: Double(c.greenComponent) + (1 - Double(c.greenComponent)) * quanto,
                     blue: Double(c.blueComponent) + (1 - Double(c.blueComponent)) * quanto)
    }
}

// MARK: - Chips

/// O desenho de um chip: ponto ou ícone, texto e a setinha de menu.
struct RotuloChip: View {
    var icone: String? = nil
    var ponto: Color? = nil
    let texto: String
    /// Valor escolhido pelo Hugo (texto claro); falso = o padrão, mais apagado.
    var forte = false
    var seta = false
    var hover = false
    var altura: CGFloat = 28

    var body: some View {
        HStack(spacing: 6) {
            if let ponto { Circle().fill(ponto).frame(width: 7, height: 7) }
            if let icone {
                Image(systemName: icone).font(.system(size: 10.5, weight: .medium))
            }
            // Nome comprido (projeto) corta com reticências em vez de empurrar os outros chips.
            Text(texto).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: 170)
            if seta {
                Image(systemName: "chevron.down").font(.system(size: 7.5, weight: .bold)).opacity(0.6)
            }
        }
        .foregroundStyle(forte || hover ? Tema.texto : Tema.texto2)
        .padding(.horizontal, 10)
        .frame(height: altura)
        .background(Pilula().fill(Color.white.opacity(hover ? 0.09 : 0.045)))
        .overlay(Pilula().strokeBorder(Tema.borda))
        .contentShape(Pilula())
    }
}

/// Chip que abre um menu (projeto, motor, modelo, modo).
struct MenuChip: View {
    var icone: String? = nil
    var ponto: Color? = nil
    let texto: String
    var forte = false
    var ajuda = ""
    let itens: @MainActor () -> [ItemMenu]

    @State private var hover = false

    var body: some View {
        BotaoMenu(itens: itens) {
            RotuloChip(icone: icone, ponto: ponto, texto: texto, forte: forte, seta: true, hover: hover)
        }
        .fixedSize()
        .onHover { hover = $0 }
        .help(ajuda)
    }
}

/// Chip clicável (atalhos do início).
struct BotaoChip: View {
    var icone: String? = nil
    var ponto: Color? = nil
    let texto: String
    var cor: Color? = nil
    let acao: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: acao) {
            HStack(spacing: 6) {
                if let ponto { Circle().fill(ponto).frame(width: 7, height: 7) }
                if let icone { Image(systemName: icone).font(.system(size: 10.5, weight: .semibold)) }
                Text(texto).font(.system(size: 12, weight: .medium)).lineLimit(1)
            }
            .foregroundStyle(cor ?? (hover ? Tema.texto : Tema.texto2))
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Pilula().fill((cor ?? .white).opacity(hover ? (cor == nil ? 0.08 : 0.2) : (cor == nil ? 0.035 : 0.11))))
            .overlay(Pilula().strokeBorder(cor.map { $0.opacity(0.35) } ?? Tema.borda))
            .contentShape(Pilula())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// Estado da sessão em pílula: ponto e palavra, na cor do estado.
struct PilulaEstado: View {
    let texto: String
    let cor: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(cor).frame(width: 6, height: 6)
            Text(texto).font(.system(size: 11.5, weight: .medium))
        }
        .foregroundStyle(cor)
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(Pilula().fill(cor.opacity(0.12)))
    }
}

// MARK: - Abas

/// Abas em trilho (Sessões | Projetos | Histórico): a pílula da escolhida desliza.
struct AbasCrew<Valor: Hashable>: View {
    let itens: [(valor: Valor, titulo: String)]
    @Binding var selecao: Valor
    @Namespace private var espaco

    var body: some View {
        HStack(spacing: 2) {
            ForEach(itens.indices, id: \.self) { i in
                let item = itens[i]
                let escolhida = item.valor == selecao
                Button {
                    withAnimation(.snappy(duration: 0.22)) { selecao = item.valor }
                } label: {
                    Text(item.titulo)
                        .font(.system(size: 12, weight: escolhida ? .semibold : .medium))
                        .foregroundStyle(escolhida ? Tema.texto : Tema.texto2)
                        .frame(maxWidth: .infinity)
                        .frame(height: 26)
                        .background {
                            if escolhida {
                                Pilula().fill(Color.white.opacity(0.1))
                                    .matchedGeometryEffect(id: "aba", in: espaco)
                            }
                        }
                        .contentShape(Pilula())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Pilula().fill(Color.white.opacity(0.035)))
        .overlay(Pilula().strokeBorder(Tema.borda))
    }
}

// MARK: - Layout

/// Chips em linha, quebrando para a linha de baixo quando não cabem; cada linha centralizada.
struct FluxoCrew: Layout {
    var espaco: CGFloat = 8
    var centralizado = true

    private func linhas(_ largura: CGFloat, _ subviews: Subviews) -> [(itens: [(Int, CGSize)], largura: CGFloat, altura: CGFloat)] {
        var out: [(itens: [(Int, CGSize)], largura: CGFloat, altura: CGFloat)] = []
        var atual: [(Int, CGSize)] = []
        var x: CGFloat = 0, alt: CGFloat = 0
        for (i, s) in subviews.enumerated() {
            let t = s.sizeThatFits(.unspecified)
            if !atual.isEmpty, x + espaco + t.width > largura {
                out.append((atual, x, alt))
                atual = []; x = 0; alt = 0
            }
            x += (atual.isEmpty ? 0 : espaco) + t.width
            alt = max(alt, t.height)
            atual.append((i, t))
        }
        if !atual.isEmpty { out.append((atual, x, alt)) }
        return out
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let largura = proposal.width ?? .infinity
        let l = linhas(largura, subviews)
        let altura = l.map(\.altura).reduce(0, +) + espaco * CGFloat(max(0, l.count - 1))
        return CGSize(width: proposal.width ?? (l.map(\.largura).max() ?? 0), height: altura)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for linha in linhas(bounds.width, subviews) {
            var x = bounds.minX + (centralizado ? (bounds.width - linha.largura) / 2 : 0)
            for (i, t) in linha.itens {
                subviews[i].place(at: CGPoint(x: x, y: y + (linha.altura - t.height) / 2),
                                  proposal: ProposedViewSize(t))
                x += t.width + espaco
            }
            y += linha.altura + espaco
        }
    }
}

/// Pílula: duas retas e dois meios-círculos. (O `Capsule` do sistema é um retângulo de cantos
/// redondos com um trecho de comprimento zero em cada ponta: contornado, deixa um risco ali.)
struct Pilula: InsettableShape {
    var recuo: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: recuo, dy: recuo)
        let raio = min(r.width, r.height) / 2
        guard r.width > r.height + 0.5 else { return Path(ellipseIn: r) }
        // Duas retas e dois meios-círculos, sem trecho de comprimento zero nas pontas.
        var p = Path()
        p.move(to: CGPoint(x: r.minX + raio, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - raio, y: r.minY))
        p.addArc(center: CGPoint(x: r.maxX - raio, y: r.midY), radius: raio,
                 startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: r.minX + raio, y: r.maxY))
        p.addArc(center: CGPoint(x: r.minX + raio, y: r.midY), radius: raio,
                 startAngle: .degrees(90), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()
        return p
    }

    func inset(by amount: CGFloat) -> Pilula { Pilula(recuo: recuo + amount) }
}

/// A forma do campo de escrever: pílula enquanto tem uma linha só; quando cresce, retângulo
/// de cantos bem redondos (o raio fica, a altura aumenta).
struct FormaCampo: InsettableShape {
    var raio: CGFloat = 24
    var recuo: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: recuo, dy: recuo)
        if r.height <= (raio - recuo) * 2 + 0.5 { return Pilula().path(in: r) }
        return Path(roundedRect: r, cornerRadius: raio - recuo, style: .continuous)
    }

    func inset(by amount: CGFloat) -> FormaCampo { FormaCampo(raio: raio, recuo: recuo + amount) }
}

/// Linha fina de separação.
struct Fio: View {
    var body: some View { Rectangle().fill(Tema.borda).frame(height: 1) }
}

// MARK: - Homie

/// Para onde o Homie olha (-1…1 em cada eixo). Caixa sem publicação: o desenho lê a cada
/// quadro, então mexer o mouse não refaz tela nenhuma.
final class OlharHomie {
    var x: CGFloat = 0
    var y: CGFloat = 0
    /// O olhar do Homie da barra lateral: acompanha o mouse pela janela toda.
    @MainActor static let lateral = OlharHomie()
}

/// O Homie vivo, inteiro (com o boné), fora da ilha: a cara do app. Grande no início,
/// pequeno no topo da barra lateral. Para de animar quando a janela não está à vista.
struct HomieVivo: View {
    var estado: BotState = .idle
    var tamanho: CGFloat = 160
    /// Intervalo mínimo entre quadros (nil = o da tela: 60 ou 120 por segundo, liso).
    var quadro: Double? = nil
    var olhar: OlharHomie? = nil

    @StateObject private var engine = BotEngine()
    @Environment(\.telaVisivel) private var visivel

    var body: some View {
        TimelineView(.animation(minimumInterval: quadro, paused: !visivel)) { tempo in
            Canvas { contexto, area in
                _ = tempo.date
                engine.lookX = olhar?.x ?? 0
                engine.lookY = olhar?.y ?? 0
                // Música tocando: todo Homie põe o fone, como o da ilha.
                engine.headphonesOn = MediaService.shared.nowPlaying?.isPlaying == true
                engine.avancar()
                engine.drawHandsBehind(context: contexto, size: area)
                engine.draw(context: contexto, size: area)
                engine.drawHandsAndExtras(context: contexto, size: area)
            }
        }
        .frame(width: tamanho, height: tamanho)
        .allowsHitTesting(false)
        .onChange(of: estado) { _, novo in engine.setState(novo) }
        .onAppear { engine.setState(estado, force: true) }
    }
}

// MARK: - Janela à vista

/// Diz se a janela que hospeda a tela está à vista (não minimizada nem toda coberta).
/// Com ela escondida, o Homie para e ninguém relê transcript nem terminal.
struct VigiaDaJanela: NSViewRepresentable {
    @Binding var visivel: Bool

    func makeNSView(context: Context) -> NSView {
        let v = Vigia()
        v.aoMudar = { novo in if visivel != novo { visivel = novo } }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class Vigia: NSView {
        var aoMudar: ((Bool) -> Void)?
        private var observador: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observador { NotificationCenter.default.removeObserver(observador) }
            observador = nil
            guard let janela = window else { return }
            observador = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: janela, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.avisar() }
            }
            avisar()
        }

        private func avisar() {
            guard let janela = window else { return }
            let v = janela.occlusionState.contains(.visible)
            // Fora da atualização da tela: mexer em estado no meio dela é ignorado.
            DispatchQueue.main.async { [weak self] in self?.aoMudar?(v) }
        }
    }
}

// MARK: - Lateral recolhida

/// Com a barra lateral recolhida, os botões da janela ficam por cima do canto do conteúdo:
/// os cabeçalhos começam depois deles (e do botão de mostrar a lateral).
private struct RecuoTituloKey: EnvironmentKey { static let defaultValue: CGFloat = 0 }

extension EnvironmentValues {
    var recuoTitulo: CGFloat {
        get { self[RecuoTituloKey.self] }
        set { self[RecuoTituloKey.self] = newValue }
    }
}

// MARK: - Diálogo

/// A confirmação do app do Crew: escurece a janela e põe a pergunta no meio. Enter confirma,
/// Esc ou clique fora cancela.
struct DialogoCrew: View {
    let titulo: String
    let texto: String
    /// Ação secundária, à esquerda (em vermelho).
    var perigo: String? = nil
    var aoPerigo: () -> Void = {}
    let confirmar: String
    let aoConfirmar: () -> Void
    let aoCancelar: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).onTapGesture(perform: aoCancelar)
            VStack(alignment: .leading, spacing: 10) {
                Text(titulo).font(Tema.titulo(16, .bold)).foregroundStyle(Tema.texto)
                Text(texto)
                    .font(.system(size: 13))
                    .foregroundStyle(Tema.texto2)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    if let perigo {
                        Button(action: aoPerigo) {
                            Text(perigo).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Tema.vermelho.opacity(0.85))
                        }
                        .buttonStyle(.plain)
                        .help("A sessão continua rodando onde está; só sai da lista do Crew")
                    }
                    Spacer()
                    BotaoPilula(titulo: "Cancelar", estilo: .discreto, altura: 34, acao: aoCancelar)
                    BotaoPilula(titulo: confirmar, estilo: .ambar, altura: 34, acao: aoConfirmar)
                }
                .padding(.top, 10)
            }
            .padding(22)
            .frame(width: 440)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Tema.elevado))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Tema.bordaForte))
            .shadow(color: .black.opacity(0.5), radius: 40, y: 16)
        }
        .transition(.opacity)
    }
}
