import AppKit
import ImageIO
import SwiftUI

// Captura de tela do Crew: área, janela, tela inteira e texto da tela (OCR). Quem fotografa é o
// `screencapture` do próprio macOS (ele cuida da seleção e da permissão); o Crew guarda o arquivo,
// mostra a prévia e oferece o que fazer com ele. Nada roda parado: sem timer, sem vigia de pasta —
// só os atalhos registrados no sistema. Nunca captura sem tecla ou clique do Hugo.

struct Captura: Identifiable, Hashable, Sendable {
    let url: URL
    let data: Date

    var id: String { url.path }
    var anotada: Bool { url.deletingPathExtension().lastPathComponent.contains(PoliticaCaptura.sufixoAnotada) }
}

@Observable @MainActor
final class CapturaServico {
    static let shared = CapturaServico()
    static let modulo = "captura"

    struct Aviso: Equatable {
        let texto: String
        let erro: Bool
    }

    /// Capturas da pasta, da mais nova para a mais antiga.
    private(set) var recentes: [Captura] = []
    /// Captura acontecendo agora (a seleção do macOS está na tela).
    private(set) var emCurso: ModoCaptura?
    /// Última mensagem (cancelou, faltou permissão, copiou…), mostrada na página do módulo.
    var aviso: Aviso?
    /// O Crew tem a permissão de Gravação de Tela?
    private(set) var permissao = CGPreflightScreenCaptureAccess()
    private(set) var miniaturas: [String: NSImage] = [:]

    // Atalhos
    private(set) var combinacoes: [ModoCaptura: Combinacao] = [:]
    private(set) var atalhoLigado: [ModoCaptura: Bool] = [:]
    private(set) var recusados: Set<ModoCaptura> = []
    /// Atalho esperando a combinação nova (gravador dos ajustes).
    private(set) var gravando: ModoCaptura?

    // Ajustes
    var manter: Int { didSet { Ajustes.definir(Self.modulo, "manter", manter); podar() } }
    /// Segundos até a prévia sumir sozinha (0 = não some).
    var tempoPrevia: Double { didSet { Ajustes.definir(Self.modulo, "tempoPrevia", tempoPrevia) } }
    var mostrarPrevia: Bool { didSet { Ajustes.definir(Self.modulo, "mostrarPrevia", mostrarPrevia) } }
    /// O que vai escrito junto com a imagem mandada para a sessão (vazio = só a imagem).
    var mensagemSessao: String { didSet { Ajustes.definir(Self.modulo, "mensagemSessao", mensagemSessao) } }
    /// Pasta que o Hugo escolheu (nil = a do Crew).
    private(set) var pastaEscolhida: String?

    @ObservationIgnored private let log = Log.de("captura")
    @ObservationIgnored private lazy var atalhos = AtalhosCaptura { [weak self] modo in self?.capturar(modo) }
    @ObservationIgnored private var monitorGravador: Any?
    @ObservationIgnored private var ligado = false
    /// Só no modo de capturas do app: pasta de exemplo no lugar da de verdade.
    @ObservationIgnored private var pastaExemplo: URL?

    static let mensagemPadrao = "Olha esta captura de tela."

    private init() {
        let m = Self.modulo
        manter = Int(Ajustes.double(m, "manter", padrao: Double(PoliticaCaptura.manterPadrao)))
        tempoPrevia = Ajustes.double(m, "tempoPrevia", padrao: PoliticaCaptura.tempoPreviaPadrao)
        mostrarPrevia = Ajustes.bool(m, "mostrarPrevia", padrao: true)
        mensagemSessao = Ajustes.string(m, "mensagemSessao") ?? Self.mensagemPadrao
        pastaEscolhida = Ajustes.string(m, "pasta")
        for modo in ModoCaptura.allCases {
            let p = Combinacao.padrao(modo)
            let k = "atalho.\(modo.rawValue)"
            if let nome = Ajustes.string(m, k + ".nome") {
                combinacoes[modo] = Combinacao(tecla: UInt32(Ajustes.double(m, k + ".tecla", padrao: Double(p.tecla))),
                                               modificadores: UInt32(Ajustes.double(m, k + ".mods", padrao: Double(p.modificadores))),
                                               nomeTecla: nome)
            } else {
                combinacoes[modo] = p
            }
            atalhoLigado[modo] = Ajustes.bool(m, k + ".ligado", padrao: true)
        }
    }

    // MARK: Ligar / desligar

    func iniciar() {
        ligado = true
        aplicarAtalhos()
    }

    func parar() {
        ligado = false
        pararGravador(reaplicar: false)
        atalhos.desligar()
        recusados = []
        PilhaPrevias.shared.fechar()
        Arbitro.shared.retirar("captura.aviso")
    }

    // MARK: Pasta

    static var pastaPadrao: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("NotchBuddy/capturas", isDirectory: true)
    }

    var pasta: URL {
        if let pastaExemplo { return pastaExemplo }
        return pastaEscolhida.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? Self.pastaPadrao
    }

    /// A pasta como aparece nos ajustes (no modo de capturas do app, a do Crew).
    var pastaMostrada: URL { pastaExemplo == nil ? pasta : Self.pastaPadrao }

    /// Na pasta do Crew as mais antigas saem sozinhas; numa pasta do Hugo o Crew nunca tira nada.
    var pastaEhDoCrew: Bool { pastaEscolhida == nil }

    func escolherPasta() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.canCreateDirectories = true
        p.prompt = "Guardar aqui"
        p.message = "Onde o Crew guarda as capturas. Nesta pasta ele nunca apaga nada sozinho."
        guard p.runModal() == .OK, let url = p.url else { return }
        definirPasta(url.path)
    }

    func usarPastaDoCrew() { definirPasta(nil) }

    private func definirPasta(_ caminho: String?) {
        pastaEscolhida = caminho
        Ajustes.definir(Self.modulo, "pasta", caminho)
        miniaturas = [:]
        atualizar()
    }

    func abrirPasta() {
        try? FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
        NSWorkspace.shared.open(pasta)
    }

    // MARK: Permissão

    func atualizarPermissao() {
        guard pastaExemplo == nil else { return }
        permissao = CGPreflightScreenCaptureAccess()
    }

    /// Só por clique: o macOS mostra o pedido dele (uma vez) e os Ajustes do Sistema abrem na lista.
    func pedirPermissao() {
        if !CGRequestScreenCaptureAccess(),
           let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(u)
        }
        atualizarPermissao()
    }

    static let explicacaoPermissao = "O macOS só deixa fotografar a tela de outros apps com a permissão de Gravação de Tela para o Crew (Ajustes do Sistema › Privacidade e Segurança › Gravação de Tela e Áudio do Sistema). Depois de ligar, o macOS pede para reabrir o Crew. As imagens ficam neste Mac."

    // MARK: Capturar

    /// Único caminho que fotografa: chamado pelo atalho, pelo botão ou por `crew://captura/…`.
    func capturar(_ modo: ModoCaptura) {
        guard emCurso == nil, !CaptureTool.ativo, pastaExemplo == nil else { return }
        emCurso = modo
        aviso = nil
        Arbitro.shared.retirar("captura.aviso")
        Task {
            if modo == .texto { await capturarTexto() } else { await capturarImagem(modo) }
            emCurso = nil
        }
    }

    private func capturarImagem(_ modo: ModoCaptura) async {
        let pasta = self.pasta
        do {
            try FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
        } catch {
            falhou("Não consegui usar a pasta \(pasta.path): \(error.localizedDescription)")
            return
        }
        let existentes = Set((try? FileManager.default.contentsOfDirectory(atPath: pasta.path)) ?? [])
        let destino = pasta.appendingPathComponent(PoliticaCaptura.nomeLivre(PoliticaCaptura.nomeArquivo(Date()), existentes: existentes))
        let r = await rodar(modo, destino)
        atualizarPermissao()
        guard Self.temConteudo(destino) else {
            try? FileManager.default.removeItem(at: destino)
            explicarSemArquivo(r)
            return
        }
        log.info("captura \(modo.rawValue, privacy: .public) em \(destino.lastPathComponent, privacy: .public)")
        let c = Captura(url: destino, data: Date())
        await recarregar()
        podar()
        if mostrarPrevia { PilhaPrevias.shared.mostrar(c) }
        if !permissao {
            // Sem a permissão o macOS entrega a imagem só com o fundo de tela e as janelas do Crew.
            falhou("A captura saiu, mas sem a permissão de Gravação de Tela o macOS esconde as janelas dos outros apps.", naIlha: true)
        } else {
            aviso = Aviso(texto: "Captura guardada: \(destino.lastPathComponent)", erro: false)
        }
    }

    private func capturarTexto() async {
        let temporario = FileManager.default.temporaryDirectory.appendingPathComponent("crew-texto-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: temporario) }
        let r = await rodar(.texto, temporario)
        atualizarPermissao()
        guard Self.temConteudo(temporario) else {
            explicarSemArquivo(r)
            return
        }
        entregarTexto(await LeitorTexto.ler(temporario), semPermissao: !permissao)
    }

    private func rodar(_ modo: ModoCaptura, _ destino: URL) async -> Processo.Resultado {
        var tela: Int?
        if modo == .tela, NSScreen.screens.count > 1 {
            // Com mais de um monitor: a tela onde o mouse está (1 = a principal, na ordem do macOS).
            let mouse = NSEvent.mouseLocation
            tela = (NSScreen.screens.firstIndex { $0.frame.contains(mouse) } ?? 0) + 1
        }
        // A seleção fica na tela até o Hugo escolher ou apertar Esc; 3 min é o teto.
        return await Processo.rodar(PoliticaCaptura.executavel, PoliticaCaptura.argumentos(modo, destino: destino.path, tela: tela),
                                    tempoMax: 180)
    }

    private static func temConteudo(_ url: URL) -> Bool {
        ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0) > 0
    }

    /// O `screencapture` não deixou arquivo: ou o Hugo cancelou (Esc), ou falta a permissão.
    private func explicarSemArquivo(_ r: Processo.Resultado) {
        if !permissao {
            falhou("Falta a permissão de Gravação de Tela para o Crew — sem ela o macOS não entrega a imagem.", naIlha: true)
        } else if r.estourouTempo {
            aviso = Aviso(texto: "A seleção ficou aberta por 3 minutos e foi cancelada.", erro: false)
        } else if r.codigo != 0, !r.erro.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            falhou("O macOS não fez a captura: \(r.erro.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160))", naIlha: true)
        } else {
            aviso = Aviso(texto: "Captura cancelada.", erro: false)
        }
    }

    private func falhou(_ texto: String, naIlha: Bool = false) {
        log.error("\(texto, privacy: .public)")
        aviso = Aviso(texto: texto, erro: true)
        if naIlha {
            Arbitro.shared.publicar(Sinal(id: "captura.aviso", lugar: .barra, prioridade: .alerta, duracao: 8, clicavel: true,
                                          conteudo: AnyView(AvisoCaptura(icone: "exclamationmark.triangle.fill",
                                                                         texto: permissao ? "Captura não saiu — veja no Crew" : "Captura: falta a permissão de Gravação de Tela",
                                                                         cor: Color(hex: "#F5A524"), abre: true))))
        }
    }

    // MARK: Texto (OCR)

    /// Texto de uma captura já guardada → área de transferência.
    func copiarTexto(de c: Captura) async -> Bool {
        entregarTexto(await LeitorTexto.ler(c.url), semPermissao: false)
    }

    @discardableResult
    private func entregarTexto(_ texto: String?, semPermissao: Bool) -> Bool {
        guard let texto else {
            falhou("Não consegui ler a imagem para tirar o texto.", naIlha: true)
            return false
        }
        guard !texto.isEmpty else {
            aviso = Aviso(texto: semPermissao
                          ? "Nenhum texto encontrado — sem a permissão de Gravação de Tela o macOS esconde as janelas dos outros apps."
                          : "Nenhum texto encontrado nessa área.", erro: semPermissao)
            sinal("Nenhum texto encontrado", icone: "text.viewfinder", cor: Color(hex: "#9398A1"))
            return false
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(texto, forType: .string)
        aviso = Aviso(texto: "Texto copiado (\(texto.count) caracteres).", erro: false)
        sinal("Texto copiado: " + PoliticaCaptura.primeirasPalavras(texto), icone: "text.viewfinder", cor: Color(hex: "#34D399"))
        return true
    }

    /// Aviso passageiro na barra da ilha fechada.
    private func sinal(_ texto: String, icone: String, cor: Color) {
        Arbitro.shared.publicar(Sinal(id: "captura.aviso", lugar: .barra, prioridade: .hud, duracao: 3.5,
                                      conteudo: AnyView(AvisoCaptura(icone: icone, texto: texto, cor: cor, abre: false))))
    }

    // MARK: Lista

    /// Relê a pasta (ao abrir a página e depois de cada captura; sem vigia).
    func atualizar() {
        atualizarPermissao()
        Task { await recarregar() }
    }

    private func recarregar() async {
        guard pastaExemplo == nil else { return }
        let pasta = self.pasta
        let lista = await Task.detached { Self.listar(pasta) }.value
        guard pasta == self.pasta else { return }
        recentes = lista
        let vivos = Set(lista.map(\.id))
        miniaturas = miniaturas.filter { vivos.contains($0.key) }
    }

    nonisolated static func listar(_ pasta: URL) -> [Captura] {
        let chaves: [URLResourceKey] = [.creationDateKey]
        let itens = (try? FileManager.default.contentsOfDirectory(at: pasta, includingPropertiesForKeys: chaves,
                                                                  options: [.skipsHiddenFiles])) ?? []
        return itens.filter { PoliticaCaptura.ehCaptura($0.lastPathComponent) }
            .map { Captura(url: $0, data: (try? $0.resourceValues(forKeys: Set(chaves)).creationDate) ?? .distantPast) }
            .sorted { ($0.data, $0.url.lastPathComponent) > ($1.data, $1.url.lastPathComponent) }
    }

    /// Passou do limite: as mais antigas vão para a Lixeira. Só na pasta do Crew.
    private func podar() {
        guard pastaEhDoCrew, pastaExemplo == nil else { return }
        let fixadas = PilhaPrevias.shared.fixadas
        let saem = PoliticaCaptura.sobras(recentes.filter { !fixadas.contains($0.id) }, manter: manter) { $0.data }
        guard !saem.isEmpty else { return }
        for c in saem {
            try? FileManager.default.trashItem(at: c.url, resultingItemURL: nil)
            PilhaPrevias.shared.dispensar(c.id)
        }
        let foram = Set(saem.map(\.id))
        recentes.removeAll { foram.contains($0.id) }
        log.info("limite de \(self.manter): \(saem.count) capturas antigas para a Lixeira")
    }

    func carregarMiniatura(_ c: Captura) async {
        guard miniaturas[c.id] == nil else { return }
        let url = c.url
        let caixa = await Task.detached(priority: .utility) { UncheckedSendable(Self.reduzida(url, lado: 640)) }.value
        if let cg = caixa.valor {
            miniaturas[c.id] = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }
    }

    nonisolated static func reduzida(_ url: URL, lado: Int) -> CGImage? {
        guard let fonte = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opcoes: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                       kCGImageSourceThumbnailMaxPixelSize: lado,
                                       kCGImageSourceCreateThumbnailWithTransform: true]
        return CGImageSourceCreateThumbnailAtIndex(fonte, 0, opcoes as CFDictionary)
    }

    // MARK: O que fazer com uma captura

    func copiarImagem(_ c: Captura) -> Bool {
        guard let img = NSImage(contentsOf: c.url) else { return false }
        let pb = NSPasteboard.general
        pb.clearContents()
        return pb.writeObjects([img])
    }

    func salvarComo(_ c: Captura) {
        let p = NSSavePanel()
        p.nameFieldStringValue = c.url.lastPathComponent
        p.allowedContentTypes = [.png]
        p.level = .modalPanel
        NSApp.activate(ignoringOtherApps: true)
        guard p.runModal() == .OK, let destino = p.url else { return }
        do {
            if FileManager.default.fileExists(atPath: destino.path) { try FileManager.default.removeItem(at: destino) }
            try FileManager.default.copyItem(at: c.url, to: destino)
        } catch {
            falhou("Não consegui salvar em \(destino.path): \(error.localizedDescription)")
        }
    }

    /// Para a Lixeira (dá para desfazer por lá). Sempre por clique.
    func apagar(_ c: Captura) {
        do {
            try FileManager.default.trashItem(at: c.url, resultingItemURL: nil)
        } catch {
            falhou("Não consegui mandar para a Lixeira: \(error.localizedDescription)")
            return
        }
        recentes.removeAll { $0.id == c.id }
        miniaturas[c.id] = nil
        PilhaPrevias.shared.dispensar(c.id)
    }

    func mostrarNoFinder(_ c: Captura) { NSWorkspace.shared.activateFileViewerSelecting([c.url]) }

    /// Grava a cópia anotada ao lado do original (que fica intocado) e devolve a captura nova.
    func salvarAnotada(original: Captura, imagem: CGImage) -> Captura? {
        guard let png = DesenhoAnotacoes.png(imagem) else { return nil }
        let pasta = original.url.deletingLastPathComponent()
        let existentes = Set((try? FileManager.default.contentsOfDirectory(atPath: pasta.path)) ?? [])
        let destino = pasta.appendingPathComponent(PoliticaCaptura.nomeAnotada(de: original.url.lastPathComponent, existentes: existentes))
        do {
            try png.write(to: destino, options: .atomic)
        } catch {
            falhou("Não consegui salvar a cópia anotada: \(error.localizedDescription)")
            return nil
        }
        let nova = Captura(url: destino, data: Date())
        recentes.insert(nova, at: 0)
        if mostrarPrevia { PilhaPrevias.shared.mostrar(nova) }
        return nova
    }

    // MARK: Mandar para a sessão

    /// A sessão do Claude Code em foco (a mesma do Homie da ilha) — o destino do botão.
    var sessaoAlvo: AgentTask? {
        guard let t = AppState.shared.focusTask, t.source == .claudeCode, !t.isIntegration, t.sessionId != nil else { return nil }
        return t
    }

    /// Entrega a imagem à sessão pelo mesmo caminho dos anexos do chat. Só por clique, e para a
    /// sessão cujo nome estava no botão. nil = entregue; senão, o motivo.
    func mandar(_ c: Captura, para sessao: AgentTask, mensagem: String? = nil) async -> String? {
        guard !CaptureTool.ativo, pastaExemplo == nil else { return nil }
        guard FileManager.default.fileExists(atPath: c.url.path) else { return "O arquivo não está mais na pasta." }
        let xirp = await Xirp.sessionId(forClaudeSession: sessao.sessionId ?? "")
        let canal = await TerminalBridge.channel(claudePid: sessao.claudePid, bundleId: sessao.sessionAppBundleId, xirpId: xirp)
        if case .none(let app) = canal { return "Essa sessão roda no \(app), que não aceita arquivo de fora." }
        let erro = await TerminalBridge.send((mensagem ?? mensagemSessao).trimmingCharacters(in: .whitespacesAndNewlines), anexos: [c.url], via: canal)
        if erro == nil { log.info("captura mandada para a sessão \(sessao.displayTitle, privacy: .public)") }
        return erro.map { String($0.prefix(160)) }
    }

    // MARK: Atalhos

    private func aplicarAtalhos() {
        guard ligado, gravando == nil else { return }
        atalhos.aplicar(combinacoes.filter { atalhoLigado[$0.key] == true })
        recusados = atalhos.recusados
    }

    func ligarAtalho(_ modo: ModoCaptura, _ v: Bool) {
        atalhoLigado[modo] = v
        Ajustes.definir(Self.modulo, "atalho.\(modo.rawValue).ligado", v)
        aplicarAtalhos()
    }

    func definirAtalho(_ modo: ModoCaptura, _ c: Combinacao) {
        combinacoes[modo] = c
        let k = "atalho.\(modo.rawValue)"
        Ajustes.definir(Self.modulo, k + ".tecla", Double(c.tecla))
        Ajustes.definir(Self.modulo, k + ".mods", Double(c.modificadores))
        Ajustes.definir(Self.modulo, k + ".nome", c.nomeTecla)
        aplicarAtalhos()
    }

    func atalhoEhPadrao(_ modo: ModoCaptura) -> Bool { combinacoes[modo] == Combinacao.padrao(modo) }

    /// Rótulo do atalho para os botões (nil = desligado).
    func rotuloAtalho(_ modo: ModoCaptura) -> String? {
        atalhoLigado[modo] == true ? combinacoes[modo]?.rotulo : nil
    }

    /// Espera a próxima combinação apertada na janela de Ajustes (não escuta o teclado fora dela).
    /// Enquanto grava, os atalhos ficam soltos — senão a combinação atual dispararia a captura.
    func gravarAtalho(_ modo: ModoCaptura) {
        pararGravador(reaplicar: false)
        atalhos.desligar()
        gravando = modo
        monitorGravador = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] evento in
            MainActor.assumeIsolated {
                guard let self, let modo = self.gravando else { return }
                if evento.keyCode == 53, evento.modifierFlags.intersection([.command, .control, .option]).isEmpty {
                    self.pararGravador(reaplicar: true)   // Esc: fica como estava
                } else if let c = Combinacao.de(evento) {
                    self.pararGravador(reaplicar: false)
                    self.definirAtalho(modo, c)
                } else {
                    NSSound.beep()   // sem ⌃, ⌥ ou ⌘ não serve: continua esperando
                }
            }
            return nil
        }
    }

    func cancelarGravacao() { pararGravador(reaplicar: true) }

    private func pararGravador(reaplicar: Bool) {
        if let m = monitorGravador { NSEvent.removeMonitor(m) }
        monitorGravador = nil
        gravando = nil
        if reaplicar { aplicarAtalhos() }
    }

    // MARK: Exemplo (modo de capturas do app)

    /// Troca a pasta por uma de exemplo, com imagens desenhadas em código. Nada do Hugo é lido,
    /// fotografado ou gravado. `comProblemas`: sem permissão e com um atalho recusado.
    func exemploParaCaptura(comProblemas: Bool = false) {
        let pasta = FileManager.default.temporaryDirectory.appendingPathComponent("crew-captura-exemplo", isDirectory: true)
        try? FileManager.default.removeItem(at: pasta)
        try? FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
        pastaExemplo = pasta
        var lista: [Captura] = []
        let agora = Date()
        let roteiro: [(CapturaExemplo.Tipo, TimeInterval, Bool)] = [
            (.editor, 40, false), (.recado, 260, true), (.painel, 1_500, false),
            (.terminal, 5_400, false), (.recado, 93_000, false), (.painel, 180_000, false),
        ]
        for (tipo, atras, anotada) in roteiro {
            guard var img = CapturaExemplo.imagem(tipo) else { continue }
            let data = agora.addingTimeInterval(-atras)
            var nome = PoliticaCaptura.nomeArquivo(data)
            if anotada {
                img = DesenhoAnotacoes.compor(img, CapturaExemplo.anotacoes(para: img)) ?? img
                nome = PoliticaCaptura.nomeAnotada(de: nome, existentes: [])
            }
            let url = pasta.appendingPathComponent(nome)
            try? DesenhoAnotacoes.png(img)?.write(to: url)
            lista.append(Captura(url: url, data: data))
        }
        recentes = lista
        miniaturas = [:]
        permissao = !comProblemas
        recusados = comProblemas ? [.janela] : []
        aviso = comProblemas
            ? Aviso(texto: "Falta a permissão de Gravação de Tela para o Crew — sem ela o macOS não entrega a imagem.", erro: true)
            : nil
    }
}

/// A linha da Captura na barra da ilha fechada. Com `abre`, o clique leva à página do módulo.
struct AvisoCaptura: View {
    let icone: String
    let texto: String
    let cor: Color
    let abre: Bool

    var body: some View {
        AvisoBarra(icone: icone, texto: texto, cor: cor)
            .contentShape(Rectangle())
            .onTapGesture { if abre { Central.abrir(modulo: CapturaServico.modulo) } }
    }
}
