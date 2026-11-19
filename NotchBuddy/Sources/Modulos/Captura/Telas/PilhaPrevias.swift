import AppKit
import SwiftUI

// A pilha de prévias: depois de uma captura, um painel pequeno flutua no canto de baixo à direita
// da tela onde o mouse está. Não rouba o foco (o app em uso continua ativo), fica acima das outras
// janelas e some sozinho depois do tempo dos ajustes — a não ser que o mouse esteja em cima ou a
// prévia esteja fixada. Capturas seguidas empilham. Sumir da pilha não apaga o arquivo.
// Parado, o painel não existe: os prazos são disparos únicos, sem timer repetido.

@Observable @MainActor
final class PilhaPrevias {
    static let shared = PilhaPrevias()
    static let maximo = 5

    struct Item: Identifiable, Equatable {
        let captura: Captura
        var fixada = false
        var id: String { captura.id }
    }

    /// Da mais antiga para a mais nova (a nova fica embaixo, junto do canto).
    private(set) var itens: [Item] = []
    /// A prévia aberta (com as ações); as outras ficam em faixa.
    private(set) var aberta: String?
    /// Retorno da última ação de cada prévia ("Copiada", "Enviada para…", erro).
    private(set) var retornos: [String: CapturaServico.Aviso] = [:]
    private(set) var enviando: Set<String> = []

    @ObservationIgnored private var painel: NSPanel?
    @ObservationIgnored private var prazos: [String: DispatchWorkItem] = [:]
    @ObservationIgnored private var mouseDentro = false
    @ObservationIgnored private var tela: NSScreen?

    var fixadas: Set<String> { Set(itens.filter(\.fixada).map(\.id)) }

    // MARK: Entrar e sair

    func mostrar(_ c: Captura) {
        itens.removeAll { $0.id == c.id }
        itens.append(Item(captura: c))
        while itens.count > Self.maximo, let sai = itens.firstIndex(where: { !$0.fixada }) ?? itens.indices.first {
            cancelarPrazo(itens[sai].id)
            itens.remove(at: sai)
        }
        aberta = c.id
        if painel == nil {
            let mouse = NSEvent.mouseLocation
            tela = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
            montar()
        }
        agendar(c.id)
        ajustar()
    }

    /// Tira da pilha (o arquivo continua na pasta).
    func dispensar(_ id: String) {
        guard itens.contains(where: { $0.id == id }) else { return }
        cancelarPrazo(id)
        itens.removeAll { $0.id == id }
        retornos[id] = nil
        enviando.remove(id)
        if aberta == id { aberta = itens.last?.id }
        if itens.isEmpty { fechar() } else { ajustar() }
    }

    func fechar() {
        for (_, p) in prazos { p.cancel() }
        prazos = [:]
        itens = []
        retornos = [:]
        enviando = []
        aberta = nil
        mouseDentro = false
        painel?.orderOut(nil)
        painel?.contentView = nil
        painel = nil
    }

    func abrir(_ id: String) {
        aberta = id
        ajustar()
    }

    func alternarFixada(_ id: String) {
        guard let i = itens.firstIndex(where: { $0.id == id }) else { return }
        itens[i].fixada.toggle()
        if itens[i].fixada { cancelarPrazo(id) } else if !mouseDentro { agendar(id) }
    }

    // MARK: Prazo

    private func agendar(_ id: String) {
        cancelarPrazo(id)
        let tempo = CapturaServico.shared.tempoPrevia
        guard tempo > 0, !mouseDentro, itens.first(where: { $0.id == id })?.fixada == false else { return }
        let item = DispatchWorkItem { [weak self] in self?.dispensar(id) }
        prazos[id] = item
        DispatchQueue.main.asyncAfter(deadline: .now() + tempo, execute: item)
    }

    private func cancelarPrazo(_ id: String) { prazos.removeValue(forKey: id)?.cancel() }

    /// Mouse em cima segura tudo; ao sair, cada prévia ganha o tempo inteiro de novo.
    fileprivate func mouse(_ dentro: Bool) {
        guard dentro != mouseDentro else { return }
        mouseDentro = dentro
        if dentro {
            for (_, p) in prazos { p.cancel() }
            prazos = [:]
        } else {
            for i in itens where !i.fixada { agendar(i.id) }
        }
    }

    // MARK: Ações (sempre por clique)

    func retorno(_ id: String, _ texto: String, erro: Bool = false) {
        retornos[id] = CapturaServico.Aviso(texto: texto, erro: erro)
        ajustar()
        DispatchQueue.main.asyncAfter(deadline: .now() + (erro ? 6 : 2.5)) { [weak self] in
            guard let self, self.retornos[id]?.texto == texto else { return }
            self.retornos[id] = nil
            self.ajustar()
        }
    }

    func copiarImagem(_ c: Captura) {
        CapturaServico.shared.copiarImagem(c) ? retorno(c.id, "Imagem copiada") : retorno(c.id, "Não consegui copiar", erro: true)
    }

    func copiarTexto(_ c: Captura) {
        Task {
            let ok = await CapturaServico.shared.copiarTexto(de: c)
            retorno(c.id, ok ? "Texto copiado" : "Nenhum texto encontrado", erro: !ok)
        }
    }

    func mandar(_ c: Captura, para sessao: AgentTask) {
        guard !enviando.contains(c.id) else { return }
        enviando.insert(c.id)
        Task {
            let erro = await CapturaServico.shared.mandar(c, para: sessao)
            enviando.remove(c.id)
            if let erro { retorno(c.id, "Não foi: \(erro)", erro: true) } else { retorno(c.id, "Enviada para \(sessao.displayTitle)") }
        }
    }

    /// Só no modo de capturas do app: a pilha montada sem painel na tela.
    func exemploParaCaptura(_ capturas: [Captura]) {
        itens = capturas.map { Item(captura: $0) }
        if itens.count > 1 { itens[0].fixada = true }
        aberta = itens.last?.id
        retornos = [:]
    }

    // MARK: Painel

    private func montar() {
        let p = PainelPrevias(contentRect: NSRect(x: 0, y: 0, width: PilhaView.largura + 24, height: 200),
                              styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = true
        p.isReleasedWhenClosed = false
        p.animationBehavior = .utilityWindow
        // Fora das próximas capturas: a prévia de uma não aparece na foto da seguinte.
        p.sharingType = .none
        let host = HospedeiroPrevias(rootView: PilhaView())
        host.aoPassar = { [weak self] dentro in self?.mouse(dentro) }
        p.contentView = host
        painel = p
    }

    /// Ajusta o painel ao conteúdo, preso ao canto de baixo à direita.
    private func ajustar() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let p = self.painel, let host = p.contentView else { return }
            host.layoutSubtreeIfNeeded()
            let tamanho = host.fittingSize
            let area = (self.tela ?? NSScreen.main)?.visibleFrame ?? .zero
            let quadro = NSRect(x: area.maxX - tamanho.width - 8, y: area.minY + 8, width: tamanho.width, height: tamanho.height)
            p.setFrame(quadro, display: true)
            if !p.isVisible { p.orderFrontRegardless() }
        }
    }
}

/// Painel que não ativa o Crew: o app em uso continua na frente e com o teclado.
private final class PainelPrevias: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Aceita o primeiro clique (o painel nunca é a janela ativa) e avisa quando o mouse entra e sai,
/// mesmo com outro app na frente.
private final class HospedeiroPrevias: NSHostingView<PilhaView> {
    var aoPassar: ((Bool) -> Void)?
    private var area: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let nova = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(nova)
        area = nova
    }

    override func mouseEntered(with event: NSEvent) { aoPassar?(true) }
    override func mouseExited(with event: NSEvent) { aoPassar?(false) }
}

// MARK: - Telas

struct PilhaView: View {
    static let largura: CGFloat = 264
    private let pilha = PilhaPrevias.shared

    var body: some View {
        VStack(spacing: 8) {
            ForEach(pilha.itens) { item in
                if item.id == pilha.aberta {
                    PreviaAberta(item: item)
                } else {
                    PreviaFaixa(item: item)
                }
            }
        }
        .padding(12)
        .frame(width: Self.largura + 24)
    }
}

enum EstiloPrevia {
    static let fundo = Color(hex: "#111216")
    static let borda = Color.white.opacity(0.10)
    static let tinta = Color(hex: "#DADDE2")
    static let apagado = Color(hex: "#8A8F99")
    static let destaque = Color(hex: "#3B82F6")
    static let erro = Color(hex: "#F5A524")
    static let ok = Color(hex: "#34D399")

    static func hora(_ d: Date) -> String {
        d.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(Locale(identifier: "pt_BR")))
    }
}

private struct Cartao<Conteudo: View>: View {
    @ViewBuilder let conteudo: Conteudo

    var body: some View {
        conteudo
            .frame(width: PilhaView.largura)
            .background(EstiloPrevia.fundo)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(EstiloPrevia.borda, lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
    }
}

/// Miniatura de uma captura (carrega fora da main, uma vez).
struct MiniaturaCaptura: View {
    let captura: Captura
    private let s = CapturaServico.shared

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
            if let img = s.miniaturas[captura.id] {
                Image(nsImage: img).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "photo").font(.system(size: 18)).foregroundColor(.white.opacity(0.25))
            }
        }
        .task(id: captura.id) { await s.carregarMiniatura(captura) }
    }
}

private struct BotaoIconeCaptura: View {
    let icone: String
    let ajuda: String
    var cor: Color = EstiloPrevia.tinta
    let acao: () -> Void
    @State private var sobre = false

    var body: some View {
        Button(action: acao) {
            Image(systemName: icone)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundColor(cor)
                .frame(maxWidth: .infinity, minHeight: 28)
                .background(Color.white.opacity(sobre ? 0.14 : 0.06))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { sobre = $0 }
        .help(ajuda)
        .accessibilityLabel(ajuda)
    }
}

/// A prévia aberta: miniatura (arrasta o arquivo para fora), ações e "mandar para a sessão".
struct PreviaAberta: View {
    let item: PilhaPrevias.Item
    private let pilha = PilhaPrevias.shared
    private let s = CapturaServico.shared
    @ObservedObject private var estado = AppState.shared

    var body: some View {
        let c = item.captura
        Cartao {
            VStack(spacing: 8) {
                MiniaturaCaptura(captura: c)
                    .frame(width: PilhaView.largura - 16, height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .onDrag { NSItemProvider(contentsOf: c.url) ?? NSItemProvider() }
                    .overlay(alignment: .topLeading) {
                        redondo("xmark", "Tirar da pilha (o arquivo fica na pasta)") { pilha.dispensar(c.id) }.padding(6)
                    }
                    .overlay(alignment: .topTrailing) {
                        redondo(item.fixada ? "pin.fill" : "pin", item.fixada ? "Soltar (volta a sumir sozinha)" : "Fixar (não some sozinha)",
                                ativo: item.fixada) { pilha.alternarFixada(c.id) }.padding(6)
                    }
                    .overlay(alignment: .bottomLeading) {
                        Text(c.anotada ? "anotada · \(EstiloPrevia.hora(c.data))" : EstiloPrevia.hora(c.data))
                            .font(.system(size: 10, weight: .medium)).monospacedDigit()
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.black.opacity(0.55))
                            .clipShape(Capsule())
                            .padding(6)
                    }
                    .help("Arraste para soltar o arquivo em outro app")
                HStack(spacing: 5) {
                    BotaoIconeCaptura(icone: "doc.on.doc", ajuda: "Copiar a imagem") { pilha.copiarImagem(c) }
                    BotaoIconeCaptura(icone: "square.and.arrow.down", ajuda: "Salvar como…") { s.salvarComo(c) }
                    BotaoIconeCaptura(icone: "text.viewfinder", ajuda: "Copiar o texto da imagem") { pilha.copiarTexto(c) }
                    BotaoIconeCaptura(icone: "pencil.tip.crop.circle", ajuda: "Anotar (seta, retângulo, traço, texto, tarja)") { JanelaAnotar.shared.abrir(c) }
                    BotaoIconeCaptura(icone: "trash", ajuda: "Mandar para a Lixeira") { s.apagar(c) }
                }
                mandar(c)
                if let r = pilha.retornos[c.id] {
                    Text(r.texto)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(r.erro ? EstiloPrevia.erro : EstiloPrevia.ok)
                        .lineLimit(3).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(8)
        }
    }

    @ViewBuilder
    private func mandar(_ c: Captura) -> some View {
        // Lê `estado.tasks` para o nome acompanhar a sessão em foco.
        let _ = estado.focusId
        if let sessao = s.sessaoAlvo {
            let indo = pilha.enviando.contains(c.id)
            Button { pilha.mandar(c, para: sessao) } label: {
                HStack(spacing: 6) {
                    Image(systemName: indo ? "hourglass" : "paperplane.fill").font(.system(size: 11, weight: .semibold))
                    Text(indo ? "Mandando…" : "Mandar para \(sessao.displayTitle)")
                        .font(.system(size: 11.5, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 28)
                .background(EstiloPrevia.destaque.opacity(indo ? 0.5 : 1))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(indo)
            .help("Entrega esta imagem à sessão do Claude Code em foco: \(sessao.displayTitle)")
        } else {
            Text("Sem sessão do Claude Code em foco para mandar")
                .font(.system(size: 10.5)).foregroundColor(EstiloPrevia.apagado)
                .frame(maxWidth: .infinity, minHeight: 22)
        }
    }

    private func redondo(_ icone: String, _ ajuda: String, ativo: Bool = false, _ acao: @escaping () -> Void) -> some View {
        Button(action: acao) {
            Image(systemName: icone)
                .font(.system(size: 9.5, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 22, height: 22)
                .background(ativo ? EstiloPrevia.destaque : Color.black.opacity(0.6))
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(ajuda)
        .accessibilityLabel(ajuda)
    }
}

/// Uma prévia mais antiga, em faixa: clique abre; arrastar leva o arquivo.
struct PreviaFaixa: View {
    let item: PilhaPrevias.Item
    private let pilha = PilhaPrevias.shared

    var body: some View {
        let c = item.captura
        Cartao {
            HStack(spacing: 8) {
                MiniaturaCaptura(captura: c)
                    .frame(width: 54, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .onDrag { NSItemProvider(contentsOf: c.url) ?? NSItemProvider() }
                VStack(alignment: .leading, spacing: 1) {
                    Text(c.anotada ? "Anotada" : "Captura").font(.system(size: 11.5, weight: .medium)).foregroundColor(EstiloPrevia.tinta)
                    Text(EstiloPrevia.hora(c.data)).font(.system(size: 10)).monospacedDigit().foregroundColor(EstiloPrevia.apagado)
                }
                Spacer(minLength: 0)
                if item.fixada {
                    Image(systemName: "pin.fill").font(.system(size: 10)).foregroundColor(EstiloPrevia.destaque)
                }
                BotaoIconeCaptura(icone: "doc.on.doc", ajuda: "Copiar a imagem") { pilha.copiarImagem(c) }.frame(width: 30)
                BotaoIconeCaptura(icone: "xmark", ajuda: "Tirar da pilha (o arquivo fica na pasta)", cor: EstiloPrevia.apagado) { pilha.dispensar(c.id) }
                    .frame(width: 30)
            }
            .padding(7)
            .contentShape(Rectangle())
            .onTapGesture { pilha.abrir(c.id) }
            .help("Clique para abrir as ações desta captura")
        }
    }
}
