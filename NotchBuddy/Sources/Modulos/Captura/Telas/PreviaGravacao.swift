import AppKit
import SwiftUI

// A prévia de uma gravação: quando a gravação para, um cartão flutua no canto de baixo à direita
// (o mesmo lugar e a mesma cara da prévia das capturas), sem roubar o foco, com o que fazer com o
// vídeo. Some sozinha (no mínimo 10 s, ou o tempo dos ajustes) salvo mouse em cima; sumir não
// apaga o arquivo. Parada, não existe: o prazo é um disparo único.

@Observable @MainActor
final class PreviaGravacao {
    static let shared = PreviaGravacao()

    private(set) var gravacao: Gravacao?
    private(set) var retorno: CapturaServico.Aviso?
    private(set) var enviando = false

    @ObservationIgnored private var painel: NSPanel?
    @ObservationIgnored private var prazo: DispatchWorkItem?
    @ObservationIgnored private var mouseDentro = false

    func mostrar(_ g: Gravacao) {
        gravacao = g
        retorno = nil
        enviando = false
        if painel == nil { montar() }
        agendar()
        ajustar()
    }

    func dispensar(_ id: String) {
        if gravacao?.id == id { fechar() }
    }

    func fechar() {
        prazo?.cancel()
        prazo = nil
        gravacao = nil
        retorno = nil
        enviando = false
        mouseDentro = false
        painel?.orderOut(nil)
        painel?.contentView = nil
        painel = nil
    }

    private func agendar() {
        prazo?.cancel()
        prazo = nil
        let tempo = CapturaServico.shared.tempoPrevia
        guard tempo > 0, !mouseDentro else { return }
        let item = DispatchWorkItem { [weak self] in self?.fechar() }
        prazo = item
        DispatchQueue.main.asyncAfter(deadline: .now() + max(10, tempo), execute: item)
    }

    private func mouse(_ dentro: Bool) {
        guard dentro != mouseDentro else { return }
        mouseDentro = dentro
        if dentro { prazo?.cancel() } else { agendar() }
    }

    // MARK: Ações (sempre por clique)

    func dizer(_ texto: String, erro: Bool = false) {
        retorno = .init(texto: texto, erro: erro)
        ajustar()
    }

    func mandar(para sessao: AgentTask) {
        guard let g = gravacao, !enviando else { return }
        enviando = true
        Task {
            let erro = await GravacaoServico.shared.mandar(g, para: sessao)
            enviando = false
            if let erro { dizer("Não foi: \(erro)", erro: true) } else { dizer("Enviada para \(sessao.displayTitle)") }
        }
    }

    /// Só no modo de capturas do app: o cartão montado sem painel na tela.
    func exemploParaCaptura(_ g: Gravacao) {
        gravacao = g
        retorno = nil
    }

    // MARK: Painel

    private func montar() {
        let p = PainelPreviaGravacao(contentRect: NSRect(x: 0, y: 0, width: PilhaView.largura + 24, height: 240),
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
        // Fora das capturas e das gravações seguintes.
        p.sharingType = .none
        let host = HospedeiroPreviaGravacao(rootView: PreviaGravacaoView())
        host.aoPassar = { [weak self] dentro in self?.mouse(dentro) }
        p.contentView = host
        painel = p
    }

    private func ajustar() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let p = self.painel, let host = p.contentView else { return }
            host.layoutSubtreeIfNeeded()
            let tamanho = host.fittingSize
            let mouse = NSEvent.mouseLocation
            let area = (NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main)?.visibleFrame ?? .zero
            p.setFrame(NSRect(x: area.maxX - tamanho.width - 8, y: area.minY + 8, width: tamanho.width, height: tamanho.height), display: true)
            if !p.isVisible { p.orderFrontRegardless() }
        }
    }
}

private final class PainelPreviaGravacao: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Aceita o primeiro clique e avisa quando o mouse entra e sai, mesmo com outro app na frente.
private final class HospedeiroPreviaGravacao: NSHostingView<PreviaGravacaoView> {
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

struct PreviaGravacaoView: View {
    private let previa = PreviaGravacao.shared
    private let g = GravacaoServico.shared
    @ObservedObject private var estado = AppState.shared

    var body: some View {
        Group {
            if let item = previa.gravacao { cartao(item) }
        }
        .padding(12)
        .frame(width: PilhaView.largura + 24)
    }

    private func cartao(_ item: Gravacao) -> some View {
        VStack(spacing: 8) {
            MiniaturaGravacao(gravacao: item)
                .frame(width: PilhaView.largura - 16, height: 140)
                .onTapGesture { g.tocar(item) }
                .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
                .overlay(alignment: .topLeading) {
                    Button { previa.fechar() } label: {
                        Image(systemName: "xmark").font(.system(size: 9.5, weight: .bold)).foregroundColor(.white)
                            .frame(width: 22, height: 22).background(Color.black.opacity(0.6)).clipShape(Circle())
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                    }
                    .buttonStyle(.plain).padding(6)
                    .help("Fechar (o vídeo fica na pasta)")
                }
                .overlay(alignment: .bottomLeading) {
                    Text("Gravação · \(PoliticaGravacao.tamanho(item.bytes))")
                        .font(.system(size: 10, weight: .medium)).monospacedDigit().foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.black.opacity(0.55)).clipShape(Capsule())
                        .padding(6)
                }
                .help("Clique para tocar; arraste para soltar o arquivo em outro app")
            HStack(spacing: 5) {
                botao("play.fill", "Tocar no app padrão") { g.tocar(item) }
                botao("folder", "Mostrar no Finder") { g.mostrarNoFinder(item) }
                botao("doc.on.clipboard", "Copiar o caminho do arquivo") {
                    g.copiarCaminho(item)
                    previa.dizer("Caminho copiado")
                }
                botao("film", "Editar: escolha de qual projeto é o vídeo; a sessão do Claude Code edita com o contexto dele") {
                    EscolhaProjetoVideo.perguntar { contexto in
                        previa.dizer("Criando o projeto de vídeo e transcrevendo a fala…")
                        Task {
                            switch await VideoServico.shared.editarGravacao(item.url, projeto: contexto) {
                            case .success(let p): previa.dizer("Projeto \(p.nome) criado: a sessão vai propor a edição")
                            case .failure(let f): previa.dizer(f.texto)
                            }
                        }
                    }
                }
                botao("trash", "Mandar para a Lixeira") { g.apagar(item) }
            }
            mandar
            if let r = previa.retorno {
                Text(r.texto)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(r.erro ? EstiloPrevia.erro : EstiloPrevia.ok)
                    .lineLimit(3).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(8)
        .frame(width: PilhaView.largura)
        .background(EstiloPrevia.fundo)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(EstiloPrevia.borda, lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
    }

    @ViewBuilder
    private var mandar: some View {
        let _ = estado.focusId
        if let sessao = CapturaServico.shared.sessaoAlvo {
            let indo = previa.enviando
            Button { previa.mandar(para: sessao) } label: {
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
            .help("Entrega o arquivo do vídeo à sessão do Claude Code em foco: \(sessao.displayTitle)")
        } else {
            Text("Sem sessão do Claude Code em foco para mandar")
                .font(.system(size: 10.5)).foregroundColor(EstiloPrevia.apagado)
                .frame(maxWidth: .infinity, minHeight: 22)
        }
    }

    private func botao(_ icone: String, _ ajuda: String, _ acao: @escaping () -> Void) -> some View {
        Button(action: acao) {
            Image(systemName: icone)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundColor(EstiloPrevia.tinta)
                .frame(maxWidth: .infinity, minHeight: 28)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(ajuda)
        .accessibilityLabel(ajuda)
    }
}
