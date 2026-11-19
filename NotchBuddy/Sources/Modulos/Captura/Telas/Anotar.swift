import AppKit
import SwiftUI

// Anotação rápida de uma captura: seta, retângulo, traço livre, etiqueta de texto e tarja (bloco
// sólido que esconde o que está embaixo). Cor à escolha e desfazer. Não destrutivo: o original
// fica como está e a anotada é salva como cópia ao lado.

@Observable @MainActor
final class EstadoAnotar {
    let captura: Captura
    let imagem: CGImage
    let espessura: CGFloat
    private(set) var anotacoes: [Anotacao] = []
    /// A que está sendo arrastada agora.
    private(set) var rascunho: Anotacao?
    var ferramenta = FerramentaAnotacao.seta
    var cor = CorAnotacao.paleta[0]
    /// Etiqueta esperando o texto: onde fica (em pixels da imagem) e o que foi digitado.
    var textoEm: CGPoint?
    var textoDigitado = ""
    var aviso: String?

    init(captura: Captura, imagem: CGImage, anotacoes: [Anotacao] = []) {
        self.captura = captura
        self.imagem = imagem
        self.anotacoes = anotacoes
        espessura = DesenhoAnotacoes.espessura(para: CGSize(width: imagem.width, height: imagem.height))
    }

    var tamanho: CGSize { CGSize(width: imagem.width, height: imagem.height) }
    var tudo: [Anotacao] { anotacoes + (rascunho.map { [$0] } ?? []) }
    var mudou: Bool { !anotacoes.isEmpty }

    private func dentro(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x, 0), tamanho.width), y: min(max(p.y, 0), tamanho.height))
    }

    /// Arrasto na imagem (pontos já em pixels da imagem).
    func arrastar(de inicio: CGPoint, ate ponto: CGPoint) {
        guard ferramenta != .texto else { return }
        confirmarTexto()
        if var r = rascunho {
            if ferramenta == .traco { r.pontos.append(dentro(ponto)) } else { r.pontos = [r.pontos[0], dentro(ponto)] }
            rascunho = r
        } else {
            rascunho = Anotacao(ferramenta: ferramenta, cor: cor, pontos: [dentro(inicio), dentro(ponto)], espessura: espessura)
        }
    }

    func soltar(em ponto: CGPoint) {
        if ferramenta == .texto {
            confirmarTexto()
            textoEm = dentro(ponto)
            return
        }
        if let r = rascunho, !r.vazia { anotacoes.append(r) }
        rascunho = nil
    }

    func confirmarTexto() {
        defer { textoEm = nil; textoDigitado = "" }
        guard let p = textoEm else { return }
        let a = Anotacao(ferramenta: .texto, cor: cor, pontos: [p], texto: textoDigitado, espessura: espessura)
        if !a.vazia { anotacoes.append(a) }
    }

    func desfazer() {
        if textoEm != nil { textoEm = nil; textoDigitado = ""; return }
        if !anotacoes.isEmpty { anotacoes.removeLast() }
    }

    func compor() -> CGImage? {
        confirmarTexto()
        return DesenhoAnotacoes.compor(imagem, anotacoes)
    }
}

@MainActor
final class JanelaAnotar: NSObject, NSWindowDelegate {
    static let shared = JanelaAnotar()
    private var janelas: [String: NSWindow] = [:]

    func abrir(_ c: Captura) {
        if let w = janelas[c.id] {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        guard let imagem = DesenhoAnotacoes.abrir(c.url) else {
            CapturaServico.shared.aviso = .init(texto: "Não consegui abrir a imagem para anotar.", erro: true)
            return
        }
        let estado = EstadoAnotar(captura: c, imagem: imagem)
        // A janela nasce do tamanho da imagem, até caber bem na tela
        let area = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1280, height: 800)
        let escala = min(1, min((area.width * 0.8) / estado.tamanho.width, (area.height * 0.72) / estado.tamanho.height))
        let conteudo = NSSize(width: max(620, estado.tamanho.width * escala + 32),
                              height: max(360, estado.tamanho.height * escala + AnotarView.alturaBarras + 32))
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: conteudo),
                         styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        w.title = "Anotar — \(c.url.lastPathComponent)"
        w.identifier = NSUserInterfaceItemIdentifier(c.id)
        w.contentView = NSHostingView(rootView: AnotarView(estado: estado) { [weak self] in self?.fechar(c.id) })
        w.contentMinSize = NSSize(width: 620, height: 360)
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.center()
        janelas[c.id] = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func fechar(_ id: String) { janelas[id]?.close() }

    func windowWillClose(_ notification: Notification) {
        guard let w = notification.object as? NSWindow, let id = w.identifier?.rawValue else { return }
        w.contentView = nil
        janelas[id] = nil
    }
}

struct AnotarView: View {
    static let alturaBarras: CGFloat = 86
    @Bindable var estado: EstadoAnotar
    var fechar: () -> Void = {}
    @FocusState private var digitando: Bool

    var body: some View {
        VStack(spacing: 0) {
            barra
            Divider()
            GeometryReader { geo in
                let escala = min((geo.size.width - 32) / estado.tamanho.width, (geo.size.height - 32) / estado.tamanho.height, 1)
                let w = estado.tamanho.width * escala, h = estado.tamanho.height * escala
                ZStack(alignment: .topLeading) {
                    Image(decorative: estado.imagem, scale: 1).resizable().interpolation(.high)
                    Canvas { ctx, _ in
                        let itens = estado.tudo
                        ctx.withCGContext { cg in DesenhoAnotacoes.desenhar(itens, em: cg, escala: escala) }
                    }
                    if let p = estado.textoEm { campoTexto(p, escala) }
                }
                .frame(width: w, height: h)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .shadow(color: .black.opacity(0.25), radius: 10, y: 3)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { g in
                        estado.arrastar(de: CGPoint(x: g.startLocation.x / escala, y: g.startLocation.y / escala),
                                        ate: CGPoint(x: g.location.x / escala, y: g.location.y / escala))
                    }
                    .onEnded { g in
                        estado.soltar(em: CGPoint(x: g.location.x / escala, y: g.location.y / escala))
                        if estado.textoEm != nil { digitando = true }
                    })
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
            .background(Color(nsColor: .underPageBackgroundColor))
            Divider()
            rodape
        }
    }

    private var barra: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                ForEach(FerramentaAnotacao.allCases) { f in
                    Button { estado.confirmarTexto(); estado.ferramenta = f } label: {
                        Image(systemName: f.icone)
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 34, height: 26)
                            .foregroundColor(estado.ferramenta == f ? .white : .primary)
                            .background(estado.ferramenta == f ? Color.accentColor : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(f.nome)
                    .accessibilityLabel(f.nome)
                }
            }
            .padding(2)
            .background(Color.primary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(estado.ferramenta.nome).font(.system(size: 12)).foregroundColor(.secondary).frame(width: 96, alignment: .leading)
            HStack(spacing: 6) {
                ForEach(CorAnotacao.paleta) { c in
                    Button { estado.cor = c } label: {
                        Circle().fill(Color(cgColor: c.cg))
                            .frame(width: 18, height: 18)
                            .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 1))
                            .padding(3)
                            .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: estado.cor == c ? 2 : 0))
                    }
                    .buttonStyle(.plain)
                    .help(c.nome)
                    .accessibilityLabel(c.nome)
                }
            }
            .opacity(estado.ferramenta == .tarja ? 0.35 : 1)
            .help(estado.ferramenta == .tarja ? "A tarja é sempre preta e sólida" : "Cor")
            Spacer(minLength: 8)
            Button { estado.desfazer() } label: { Label("Desfazer", systemImage: "arrow.uturn.backward") }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!estado.mudou && estado.textoEm == nil)
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
    }

    private var rodape: some View {
        HStack(spacing: 10) {
            Text(estado.aviso ?? "O original fica como está. A anotada é salva como cópia, ao lado dele.")
                .font(.system(size: 11)).foregroundColor(estado.aviso == nil ? .secondary : .orange).lineLimit(1)
            Spacer(minLength: 8)
            Button("Copiar") {
                guard let img = estado.compor() else { return }
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.writeObjects([NSImage(cgImage: img, size: estado.tamanho)])
                estado.aviso = "Imagem anotada copiada."
            }
            Button("Salvar cópia") {
                guard let img = estado.compor(),
                      CapturaServico.shared.salvarAnotada(original: estado.captura, imagem: img) != nil else {
                    estado.aviso = "Não consegui salvar a cópia."
                    return
                }
                fechar()
            }
            .keyboardShortcut("s", modifiers: .command)
            .buttonStyle(.borderedProminent)
            .disabled(!estado.mudou && estado.textoEm == nil)
        }
        .padding(.horizontal, 14)
        .frame(height: 41)
    }

    /// Campo da etiqueta, no lugar onde ela vai ficar. Enter confirma.
    private func campoTexto(_ p: CGPoint, _ escala: CGFloat) -> some View {
        let tamanho = max(estado.espessura * 5 * escala, 9)
        return TextField("Texto", text: $estado.textoDigitado)
            .textFieldStyle(.plain)
            .font(.system(size: tamanho, weight: .semibold))
            .foregroundColor(Color(cgColor: estado.cor.contraste))
            .focused($digitando)
            .onSubmit { estado.confirmarTexto() }
            .padding(.horizontal, tamanho * 0.42).padding(.vertical, tamanho * 0.22)
            .frame(width: max(120, tamanho * 9), alignment: .leading)
            .background(Color(cgColor: estado.cor.cg))
            .clipShape(RoundedRectangle(cornerRadius: tamanho * 0.3))
            .offset(x: p.x * escala, y: p.y * escala)
    }
}
