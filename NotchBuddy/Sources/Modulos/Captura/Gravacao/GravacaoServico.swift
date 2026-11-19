import AppKit
import AVFoundation
import ScreenCaptureKit
import SwiftUI

// Gravação de tela do Crew: tela inteira, uma janela ou uma área, com som do sistema, microfone
// e a bolha da câmera. Começa e para pelo mesmo atalho, pelo botão ou por `crew://captura/gravar`
// e `crew://captura/parar`. Parado não roda nada: sem stream, sem câmera, sem timer — só o
// atalho registrado no sistema. Nunca grava sem tecla ou clique do Hugo.

struct Gravacao: Identifiable, Hashable, Sendable {
    let url: URL
    let data: Date
    let bytes: Int64

    var id: String { url.path }
}

/// Um microfone ou uma câmera que dá para escolher (`id` = `uniqueID` do aparelho).
struct AparelhoGravacao: Identifiable, Hashable, Sendable {
    let id: String
    let nome: String
}

@Observable @MainActor
final class GravacaoServico {
    static let shared = GravacaoServico()
    static let sinal = "captura.gravando"
    static let mensagemSessao = "Olha esta gravação de tela."

    enum Fase: Equatable {
        case parado
        /// O Hugo está escolhendo a área ou a janela.
        case escolhendo(AlvoGravacao)
        case contagem(Int)
        case iniciando
        case gravando(desde: Date)
        case finalizando
    }

    private(set) var fase: Fase = .parado
    /// Última mensagem (guardada, cancelada, faltou permissão…), mostrada na página do módulo.
    var aviso: CapturaServico.Aviso?
    /// Da mais nova para a mais antiga.
    private(set) var gravacoes: [Gravacao] = []
    private(set) var duracoes: [String: TimeInterval] = [:]
    private(set) var miniaturas: [String: NSImage] = [:]
    private(set) var permissaoCamera = AVCaptureDevice.authorizationStatus(for: .video)
    private(set) var permissaoMicrofone = AVCaptureDevice.authorizationStatus(for: .audio)

    // Ajustes (`modulo.captura.gravacao.<nome>`)
    var microfone: Bool { didSet { guardar("microfone", microfone) } }
    var somDoSistema: Bool { didSet { guardar("somDoSistema", somDoSistema) } }
    var camera: Bool { didSet { guardar("camera", camera) } }
    /// Qual microfone e qual câmera (`uniqueID`); vazio = o padrão do macOS.
    var microfoneId: String { didSet { guardar("microfoneId", microfoneId) } }
    var cameraId: String { didSet { guardar("cameraId", cameraId) } }
    /// Guardar o rastro do mouse (posição e cliques) ao lado do vídeo, para a edição.
    var rastroDoMouse: Bool { didSet { guardar("rastroDoMouse", rastroDoMouse) } }
    private(set) var microfones: [AparelhoGravacao] = []
    private(set) var cameras: [AparelhoGravacao] = []
    var contagem: Bool { didSet { guardar("contagem", contagem) } }
    var cursor: Bool { didSet { guardar("cursor", cursor) } }
    /// A ilha do Crew (o Homie e o aviso "Gravando") aparece no vídeo? Padrão: não.
    var ilhaNoVideo: Bool { didSet { guardar("ilhaNoVideo", ilhaNoVideo) } }
    /// Quadros por segundo: 30 ou 60.
    var quadros: Int { didSet { guardar("quadros", Double(quadros)) } }
    /// Metade dos pixels numa tela Retina: arquivo menor.
    var leve: Bool { didSet { guardar("leve", leve) } }
    /// O que o atalho grava.
    var alvoPadrao: AlvoGravacao { didSet { guardar("alvo", alvoPadrao.rawValue) } }
    /// Diâmetro da bolha da câmera, em pontos.
    var ladoBolha: Double { didSet { guardar("bolha.lado", ladoBolha) } }

    // Atalho
    private(set) var combinacao: Combinacao
    private(set) var atalhoLigado: Bool
    private(set) var atalhoRecusado = false
    /// Esperando a combinação nova (gravador dos ajustes).
    private(set) var gravandoAtalho = false

    @ObservationIgnored private let log = Log.de("captura")
    @ObservationIgnored private lazy var atalho = AtalhoGravar { [weak self] in self?.alternar() }
    @ObservationIgnored private var monitorAtalho: Any?
    @ObservationIgnored private var ligado = false
    @ObservationIgnored private var exemplo = false
    @ObservationIgnored private var preparo: Task<Void, Never>?
    @ObservationIgnored private var gravador: GravadorTela?
    @ObservationIgnored private var destino: URL?
    @ObservationIgnored private let rastro = RastroMouse()
    @ObservationIgnored private var quadro: QuadroGravado?
    /// Zero do vídeo de reserva (quando o macOS não avisa o começo do arquivo).
    @ObservationIgnored private var inicioReserva: TimeInterval = 0
    /// O que ficou de fora desta gravação por falta de permissão ("sem o microfone").
    @ObservationIgnored private var ressalvas: [String] = []

    private init() {
        let m = CapturaServico.modulo
        microfone = Ajustes.bool(m, "gravacao.microfone", padrao: true)
        somDoSistema = Ajustes.bool(m, "gravacao.somDoSistema", padrao: true)
        camera = Ajustes.bool(m, "gravacao.camera", padrao: false)
        microfoneId = Ajustes.string(m, "gravacao.microfoneId") ?? ""
        cameraId = Ajustes.string(m, "gravacao.cameraId") ?? ""
        rastroDoMouse = Ajustes.bool(m, "gravacao.rastroDoMouse", padrao: true)
        contagem = Ajustes.bool(m, "gravacao.contagem", padrao: true)
        cursor = Ajustes.bool(m, "gravacao.cursor", padrao: true)
        ilhaNoVideo = Ajustes.bool(m, "gravacao.ilhaNoVideo", padrao: false)
        quadros = Int(Ajustes.double(m, "gravacao.quadros", padrao: 30)) == 60 ? 60 : 30
        leve = Ajustes.bool(m, "gravacao.leve", padrao: false)
        alvoPadrao = Ajustes.string(m, "gravacao.alvo").flatMap(AlvoGravacao.init(rawValue:)) ?? .tela
        ladoBolha = Ajustes.double(m, "gravacao.bolha.lado", padrao: 200)
        let p = Combinacao.padraoGravar
        if let nome = Ajustes.string(m, "gravacao.atalho.nome") {
            combinacao = Combinacao(tecla: UInt32(Ajustes.double(m, "gravacao.atalho.tecla", padrao: Double(p.tecla))),
                                    modificadores: UInt32(Ajustes.double(m, "gravacao.atalho.mods", padrao: Double(p.modificadores))),
                                    nomeTecla: nome)
        } else {
            combinacao = p
        }
        atalhoLigado = Ajustes.bool(m, "gravacao.atalho.ligado", padrao: true)
    }

    private func guardar(_ nome: String, _ valor: Any?) {
        Ajustes.definir(CapturaServico.modulo, "gravacao." + nome, valor)
    }

    // MARK: Ligar / desligar (junto com o módulo Captura)

    func iniciar() {
        ligado = true
        aplicarAtalho()
    }

    func parar() {
        ligado = false
        pararGravadorDeAtalho(reaplicar: false)
        atalho.desligar()
        atalhoRecusado = false
        switch fase {
        case .gravando: pararGravacao()
        case .escolhendo, .contagem, .iniciando: cancelar(silencioso: true)
        case .parado, .finalizando: break
        }
        PreviaGravacao.shared.fechar()
        Arbitro.shared.retirar(Self.sinal)
    }

    var gravando: Bool { if case .gravando = fase { true } else { false } }
    var ocupado: Bool { fase != .parado }

    // MARK: Pasta

    var pasta: URL { CapturaServico.shared.pasta.appendingPathComponent(PoliticaGravacao.subpasta, isDirectory: true) }

    /// A pasta como aparece na tela (no modo de capturas do app, a do Crew).
    var pastaMostrada: URL { CapturaServico.shared.pastaMostrada.appendingPathComponent(PoliticaGravacao.subpasta, isDirectory: true) }

    func abrirPasta() {
        try? FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
        NSWorkspace.shared.open(pasta)
    }

    // MARK: Permissões

    func atualizarPermissoes() {
        guard !exemplo else { return }
        permissaoCamera = AVCaptureDevice.authorizationStatus(for: .video)
        permissaoMicrofone = AVCaptureDevice.authorizationStatus(for: .audio)
    }

    /// Só por clique: o pedido do macOS (uma vez); já negada, abre os Ajustes do Sistema na lista.
    func pedirPermissao(_ tipo: AVMediaType) {
        let status = AVCaptureDevice.authorizationStatus(for: tipo)
        if status == .notDetermined {
            Task {
                _ = await AVCaptureDevice.requestAccess(for: tipo)
                atualizarPermissoes()
            }
        } else if status != .authorized {
            let painel = tipo == .video ? "Privacy_Camera" : "Privacy_Microphone"
            if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(painel)") {
                NSWorkspace.shared.open(u)
            }
        }
    }

    /// Relê os microfones e as câmeras ligados ao Mac (ao abrir os ajustes; sem vigia).
    func atualizarAparelhos() {
        guard !exemplo else { return }
        microfones = AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone], mediaType: .audio, position: .unspecified)
            .devices.map { AparelhoGravacao(id: $0.uniqueID, nome: $0.localizedName) }
        cameras = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
                                                   mediaType: .video, position: .unspecified)
            .devices.map { AparelhoGravacao(id: $0.uniqueID, nome: $0.localizedName) }
    }

    /// O aparelho escolhido, se ainda está ligado ao Mac; senão nil (vale o padrão do macOS).
    private static func aparelho(_ id: String) -> String? {
        id.isEmpty || AVCaptureDevice(uniqueID: id) == nil ? nil : id
    }

    // MARK: Começar

    /// O atalho e `crew://captura/gravar`: começa se está parado, para se está gravando, cancela
    /// se ainda está na escolha ou na contagem.
    func alternar(_ alvo: AlvoGravacao? = nil) {
        switch fase {
        case .parado: comecar(alvo ?? alvoPadrao)
        case .gravando: pararGravacao()
        case .escolhendo, .contagem: cancelar()
        case .iniciando, .finalizando: break
        }
    }

    func comecar(_ alvo: AlvoGravacao) {
        guard ligado, fase == .parado, !CaptureTool.ativo, !exemplo else { return }
        aviso = nil
        ressalvas = []
        atualizarPermissoes()
        CapturaServico.shared.atualizarPermissao()
        // A janela vem do seletor do macOS, que já é a autorização; tela e área pedem a permissão.
        if alvo != .janela, !CGPreflightScreenCaptureAccess() {
            falhou("Falta a permissão de Gravação de Tela para o Crew — sem ela o macOS não deixa gravar.",
                   naIlha: "Gravação: falta a permissão de Gravação de Tela")
            return
        }
        let mouse = NSEvent.mouseLocation
        let telaDoMouse = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        switch alvo {
        case .tela:
            guard let tela = telaDoMouse, let id = Self.numero(tela) else {
                falhou("Não achei a tela para gravar.")
                return
            }
            quadro = QuadroGravado(alvo: .tela, retangulo: CGDisplayBounds(id), cursorNoVideo: cursor)
            preparar(.tela(id), tela: tela, area: nil)
        case .area:
            fase = .escolhendo(.area)
            SeletorArea.shared.escolher { [weak self] escolha in
                guard let self, self.fase == .escolhendo(.area) else { return }
                guard let (tela, area) = escolha, let id = Self.numero(tela) else {
                    self.fase = .parado
                    self.aviso = .init(texto: "Gravação cancelada.", erro: false)
                    return
                }
                // Do AppKit (origem embaixo) para o ScreenCaptureKit (origem em cima, na tela).
                let naTela = CGRect(x: area.minX - tela.frame.minX, y: tela.frame.maxY - area.maxY,
                                    width: area.width, height: area.height)
                let daTela = CGDisplayBounds(id)
                self.quadro = QuadroGravado(alvo: .area, retangulo: naTela.offsetBy(dx: daTela.minX, dy: daTela.minY),
                                            cursorNoVideo: self.cursor)
                self.preparar(.area(id, naTela), tela: tela, area: area)
            }
        case .janela:
            fase = .escolhendo(.janela)
            SeletorJanela.shared.escolher { [weak self] filtro, motivo in
                guard let self, self.fase == .escolhendo(.janela) else { return }
                guard let filtro else {
                    self.fase = .parado
                    if let motivo {
                        self.falhou("O seletor de janelas do macOS não abriu: \(motivo)")
                    } else {
                        self.aviso = .init(texto: "Gravação cancelada.", erro: false)
                    }
                    return
                }
                self.preparar(.filtro(UncheckedSendable(filtro)), tela: telaDoMouse, area: nil)
            }
        }
    }

    private static func numero(_ tela: NSScreen) -> CGDirectDisplayID? {
        (tela.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    /// Bolha da câmera, moldura da área, contagem — e então grava.
    private func preparar(_ origem: PlanoGravacao.Origem, tela: NSScreen?, area: CGRect?) {
        var comMicrofone = microfone
        if microfone, permissaoMicrofone != .authorized {
            comMicrofone = false
            ressalvas.append("sem o microfone (falta a permissão)")
        }
        if camera {
            if case .filtro = origem {
                // Gravação de janela só leva a janela: a bolha não apareceria.
            } else if !BolhaCamera.shared.mostrar(lado: ladoBolha, em: tela, camera: Self.aparelho(cameraId)) {
                ressalvas.append(permissaoCamera == .authorized ? "sem a câmera (nenhuma encontrada)" : "sem a câmera (falta a permissão)")
            }
        }
        if let area { MolduraArea.shared.mostrar(area) }
        let centro = area.map { CGPoint(x: $0.midX, y: $0.midY) }
            ?? tela.map { CGPoint(x: $0.frame.midX, y: $0.frame.midY) } ?? .zero
        let comContagem = contagem
        fase = comContagem ? .contagem(3) : .iniciando
        preparo = Task { [weak self] in
            if comContagem {
                for n in stride(from: 3, through: 1, by: -1) {
                    guard let self, !Task.isCancelled else { return }
                    self.fase = .contagem(n)
                    PainelContagem.shared.mostrar(n, no: centro)
                    try? await Task.sleep(for: .seconds(1))
                }
                PainelContagem.shared.fechar()
            }
            guard let self, !Task.isCancelled else { return }
            await self.gravar(origem, comMicrofone: comMicrofone)
        }
    }

    private func gravar(_ origem: PlanoGravacao.Origem, comMicrofone: Bool) async {
        fase = .iniciando
        let pasta = self.pasta
        do {
            try FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
        } catch {
            limpar()
            falhou("Não consegui usar a pasta \(pasta.path): \(error.localizedDescription)")
            return
        }
        let existentes = Set((try? FileManager.default.contentsOfDirectory(atPath: pasta.path)) ?? [])
        let arquivo = pasta.appendingPathComponent(PoliticaCaptura.nomeLivre(PoliticaGravacao.nomeArquivo(Date()), existentes: existentes))
        // Fora da gravação: toda janela do Crew marcada como "não compartilhar" (prévias, moldura,
        // contagem) e a ilha, a não ser que o Hugo queira ela no vídeo. A bolha da câmera fica.
        let comIlha = ilhaNoVideo
        let fora = NSApp.windows.filter { ($0 is IslandPanel && !comIlha) || $0.sharingType == .none }
            .map { CGWindowID($0.windowNumber) }
        let plano = PlanoGravacao(origem: origem, foraDaGravacao: fora, destino: arquivo, somDoSistema: somDoSistema,
                                  microfone: comMicrofone, microfoneId: Self.aparelho(microfoneId), cursor: cursor,
                                  quadros: quadros, leve: leve)
        let g = GravadorTela { [weak self] motivo in
            Task { @MainActor in self?.parouSozinha(motivo) }
        }
        // O rastro começa antes do vídeo: o que vier antes do zero dele é cortado ao guardar.
        if rastroDoMouse { rastro.comecar() }
        do {
            try await g.comecar(plano)
        } catch {
            limpar()
            try? FileManager.default.removeItem(at: arquivo)
            CapturaServico.shared.atualizarPermissao()
            falhou("O macOS não começou a gravação: \(error.localizedDescription)", naIlha: "Gravação não começou — veja no Crew")
            return
        }
        guard fase == .iniciando else {
            // Cancelada enquanto o macOS preparava: joga fora.
            _ = await g.parar()
            try? FileManager.default.removeItem(at: arquivo)
            return
        }
        gravador = g
        destino = arquivo
        inicioReserva = ProcessInfo.processInfo.systemUptime
        if case .filtro = origem, let janela = g.janelaAoComecar {
            quadro = QuadroGravado(alvo: .janela, retangulo: janela, cursorNoVideo: cursor)
        }
        let desde = Date()
        fase = .gravando(desde: desde)
        log.info("gravação começou em \(arquivo.lastPathComponent, privacy: .public)")
        Arbitro.shared.publicar(Sinal(id: Self.sinal, lugar: .barra, prioridade: .alerta, clicavel: true,
                                      conteudo: AnyView(SinalGravando(desde: desde))))
    }

    // MARK: Parar

    /// Para e guarda. Chamado pelo atalho, pelo botão da ilha, pela página e por `crew://captura/parar`.
    func pararGravacao() {
        guard case .gravando(let desde) = fase, let g = gravador else { return }
        fase = .finalizando
        Arbitro.shared.retirar(Self.sinal)
        Task {
            let erro = await g.parar()
            await concluir(desde: desde, erro: erro)
        }
    }

    /// Há um arquivo de vídeo aberto: sair do Crew agora o estragaria.
    var precisaFecharAntesDeSair: Bool { gravador != nil }

    /// Ao sair do Crew: para a gravação e espera o MP4 fechar (e o rastro do mouse ser escrito).
    /// Volta em poucos segundos mesmo se o macOS não responder.
    func fecharParaSair() async {
        switch fase {
        case .gravando(let desde):
            guard let g = gravador else { return }
            fase = .finalizando
            Arbitro.shared.retirar(Self.sinal)
            let erro = await g.parar()
            await concluir(desde: desde, erro: erro, saindo: true)
        case .finalizando:
            // Já estava parando: espera terminar.
            let ate = Date().addingTimeInterval(8)
            while fase == .finalizando, Date() < ate { try? await Task.sleep(for: .milliseconds(50)) }
        case .escolhendo, .contagem, .iniciando:
            cancelar(silencioso: true)
        case .parado:
            break
        }
    }

    /// O macOS parou a gravação (botão dele na barra de menus, janela fechada, erro).
    private func parouSozinha(_ motivo: String?) {
        guard case .gravando(let desde) = fase, let g = gravador else { return }
        fase = .finalizando
        Arbitro.shared.retirar(Self.sinal)
        Task {
            await g.esperarArquivo(limite: 4)
            await concluir(desde: desde, erro: motivo)
        }
    }

    private func concluir(desde: Date, erro: String?, saindo: Bool = false) async {
        guard let arquivo = destino else { limpar(); return }
        let inicio = gravador?.inicioDoVideo ?? inicioReserva
        let tracos = rastro.rodando ? rastro.terminar() : nil
        let bytes = ((try? FileManager.default.attributesOfItem(atPath: arquivo.path)[.size] as? NSNumber)?.int64Value) ?? 0
        guard bytes > 0 else {
            limpar()
            try? FileManager.default.removeItem(at: arquivo)
            falhou("A gravação não deixou arquivo" + (erro.map { ": \($0)" } ?? "."), naIlha: "Gravação não saiu — veja no Crew")
            return
        }
        // Ainda em `.finalizando`: quem espera para sair do Crew espera o rastro também.
        if let tracos, let quadro {
            let onde = PoliticaGravacao.rastro(de: arquivo)
            let ok = await Task.detached(priority: .userInitiated) {
                (try? tracos.json(quadro: quadro, inicio: inicio).write(to: onde, atomically: true, encoding: .utf8)) != nil
            }.value
            let relogio = String(format: "%.2f", tracos.fim - inicio)
            log.info("rastro do mouse\(ok ? "" : " (não gravou)", privacy: .public): \(tracos.amostras.count) posições, \(tracos.cliques.count) cliques, \(relogio, privacy: .public) s pelo relógio")
        }
        limpar()
        let g = Gravacao(url: arquivo, data: desde, bytes: bytes)
        let tempo = Date().timeIntervalSince(desde)
        gravacoes.removeAll { $0.id == g.id }
        gravacoes.insert(g, at: 0)
        duracoes[g.id] = tempo
        log.info("gravação guardada: \(arquivo.lastPathComponent, privacy: .public), \(bytes) bytes")
        var texto = "Gravação guardada (\(PoliticaGravacao.duracao(tempo)), \(PoliticaGravacao.tamanho(bytes)))"
        if !ressalvas.isEmpty { texto += " — " + ressalvas.joined(separator: ", ") }
        if let erro { texto += ". O macOS avisou: \(erro)" }
        aviso = .init(texto: texto + ".", erro: erro != nil || !ressalvas.isEmpty)
        if saindo { return }
        if CapturaServico.shared.mostrarPrevia {
            PreviaGravacao.shared.mostrar(g)
        } else {
            Arbitro.shared.publicar(Sinal(id: "captura.aviso", lugar: .barra, prioridade: .hud, duracao: 5, clicavel: true,
                                          conteudo: AnyView(AvisoCaptura(icone: "record.circle", texto: "Gravação guardada (\(PoliticaGravacao.duracao(tempo)))",
                                                                         cor: Color(hex: "#34D399"), abre: true))))
        }
    }

    /// Sai da escolha ou da contagem sem gravar nada.
    func cancelar(silencioso: Bool = false) {
        switch fase {
        case .escolhendo, .contagem, .iniciando: break
        case .parado, .gravando, .finalizando: return
        }
        preparo?.cancel()
        SeletorArea.shared.cancelar()
        SeletorJanela.shared.cancelar()
        limpar()
        if !silencioso { aviso = .init(texto: "Gravação cancelada.", erro: false) }
    }

    /// Solta tudo o que uma gravação segura e volta ao repouso.
    private func limpar() {
        preparo = nil
        gravador = nil
        destino = nil
        quadro = nil
        if rastro.rodando { _ = rastro.terminar() }
        PainelContagem.shared.fechar()
        MolduraArea.shared.fechar()
        BolhaCamera.shared.fechar()
        Arbitro.shared.retirar(Self.sinal)
        fase = .parado
    }

    private func falhou(_ texto: String, naIlha: String? = nil) {
        log.error("\(texto, privacy: .public)")
        aviso = .init(texto: texto, erro: true)
        if let naIlha {
            Arbitro.shared.publicar(Sinal(id: "captura.aviso", lugar: .barra, prioridade: .alerta, duracao: 8, clicavel: true,
                                          conteudo: AnyView(AvisoCaptura(icone: "exclamationmark.triangle.fill", texto: naIlha,
                                                                         cor: Color(hex: "#F5A524"), abre: true))))
        }
    }

    // MARK: Câmera fora da gravação (para ver e pôr no lugar)

    func alternarBolha() {
        guard !ocupado, !exemplo, !CaptureTool.ativo else { return }
        atualizarPermissoes()
        if BolhaCamera.shared.naTela {
            BolhaCamera.shared.fechar()
        } else if !BolhaCamera.shared.mostrar(lado: ladoBolha, em: NSScreen.main, camera: Self.aparelho(cameraId)) {
            aviso = .init(texto: permissaoCamera == .authorized ? "Nenhuma câmera encontrada." : "Falta permitir a câmera para o Crew.", erro: true)
        }
    }

    // MARK: Lista

    /// Relê a pasta (ao abrir a página; sem vigia).
    func atualizar() {
        guard !exemplo else { return }
        atualizarPermissoes()
        let pasta = self.pasta
        Task {
            let lista = await Task.detached { Self.listar(pasta) }.value
            guard pasta == self.pasta else { return }
            gravacoes = lista
            let vivos = Set(lista.map(\.id))
            miniaturas = miniaturas.filter { vivos.contains($0.key) }
            duracoes = duracoes.filter { vivos.contains($0.key) }
        }
    }

    nonisolated static func listar(_ pasta: URL) -> [Gravacao] {
        let chaves: Set<URLResourceKey> = [.creationDateKey, .fileSizeKey]
        let itens = (try? FileManager.default.contentsOfDirectory(at: pasta, includingPropertiesForKeys: Array(chaves),
                                                                  options: [.skipsHiddenFiles])) ?? []
        return itens.filter { PoliticaGravacao.ehGravacao($0.lastPathComponent) }
            .map { u in
                let v = try? u.resourceValues(forKeys: chaves)
                return Gravacao(url: u, data: v?.creationDate ?? .distantPast, bytes: Int64(v?.fileSize ?? 0))
            }
            .sorted { ($0.data, $0.url.lastPathComponent) > ($1.data, $1.url.lastPathComponent) }
    }

    var totalEmDisco: Int64 { gravacoes.reduce(0) { $0 + $1.bytes } }

    /// Duração e primeiro quadro, uma vez por gravação, fora da main.
    func carregarDetalhes(_ g: Gravacao) async {
        guard !exemplo, miniaturas[g.id] == nil else { return }
        let url = g.url
        let r = await Task.detached(priority: .utility) { () -> (TimeInterval?, UncheckedSendable<CGImage?>) in
            let midia = AVURLAsset(url: url)
            let duracao = try? await midia.load(.duration).seconds
            let gerador = AVAssetImageGenerator(asset: midia)
            gerador.appliesPreferredTrackTransform = true
            gerador.maximumSize = CGSize(width: 640, height: 640)
            let quadro = try? await gerador.image(at: .zero).image
            return (duracao, UncheckedSendable(quadro))
        }.value
        if let d = r.0, d.isFinite { duracoes[g.id] = d }
        if let cg = r.1.valor {
            miniaturas[g.id] = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }
    }

    // MARK: O que fazer com uma gravação

    func tocar(_ g: Gravacao) { NSWorkspace.shared.open(g.url) }

    func mostrarNoFinder(_ g: Gravacao) { NSWorkspace.shared.activateFileViewerSelecting([g.url]) }

    func copiarCaminho(_ g: Gravacao) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(g.url.path, forType: .string)
    }

    /// Para a Lixeira (dá para desfazer por lá). Sempre por clique.
    func apagar(_ g: Gravacao) {
        guard !exemplo else { return }
        do {
            try FileManager.default.trashItem(at: g.url, resultingItemURL: nil)
        } catch {
            falhou("Não consegui mandar para a Lixeira: \(error.localizedDescription)")
            return
        }
        // O rastro do mouse vai junto (some junto, volta junto se o Hugo recuperar os dois).
        try? FileManager.default.trashItem(at: PoliticaGravacao.rastro(de: g.url), resultingItemURL: nil)
        gravacoes.removeAll { $0.id == g.id }
        miniaturas[g.id] = nil
        duracoes[g.id] = nil
        PreviaGravacao.shared.dispensar(g.id)
    }

    /// Entrega o arquivo à sessão em foco, pelo mesmo caminho da captura de imagem. Só por clique.
    func mandar(_ g: Gravacao, para sessao: AgentTask) async -> String? {
        await CapturaServico.shared.mandar(Captura(url: g.url, data: g.data), para: sessao, mensagem: Self.mensagemSessao)
    }

    // MARK: Atalho

    private func aplicarAtalho() {
        guard ligado, !gravandoAtalho, !exemplo else { return }
        atalho.aplicar(atalhoLigado ? combinacao : nil)
        atalhoRecusado = atalho.recusado
    }

    func ligarAtalho(_ v: Bool) {
        atalhoLigado = v
        guardar("atalho.ligado", v)
        aplicarAtalho()
    }

    func definirAtalho(_ c: Combinacao) {
        combinacao = c
        guardar("atalho.tecla", Double(c.tecla))
        guardar("atalho.mods", Double(c.modificadores))
        guardar("atalho.nome", c.nomeTecla)
        aplicarAtalho()
    }

    var atalhoEhPadrao: Bool { combinacao == .padraoGravar }
    /// Rótulo do atalho para os botões (nil = desligado).
    var rotuloAtalho: String? { atalhoLigado ? combinacao.rotulo : nil }

    /// Espera a próxima combinação apertada na janela de Ajustes (não escuta o teclado fora dela).
    func gravarAtalho() {
        pararGravadorDeAtalho(reaplicar: false)
        atalho.desligar()
        gravandoAtalho = true
        monitorAtalho = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] evento in
            MainActor.assumeIsolated {
                guard let self, self.gravandoAtalho else { return }
                if evento.keyCode == 53, evento.modifierFlags.intersection([.command, .control, .option]).isEmpty {
                    self.pararGravadorDeAtalho(reaplicar: true)   // Esc: fica como estava
                } else if let c = Combinacao.de(evento) {
                    self.pararGravadorDeAtalho(reaplicar: false)
                    self.definirAtalho(c)
                } else {
                    NSSound.beep()
                }
            }
            return nil
        }
    }

    func cancelarGravadorDeAtalho() { pararGravadorDeAtalho(reaplicar: true) }

    private func pararGravadorDeAtalho(reaplicar: Bool) {
        if let m = monitorAtalho { NSEvent.removeMonitor(m) }
        monitorAtalho = nil
        let estava = gravandoAtalho
        gravandoAtalho = false
        if reaplicar, estava { aplicarAtalho() }
    }

    // MARK: Exemplo (modo de capturas do app)

    /// Lista de exemplo com quadros desenhados em código. Nada é gravado, lido ou apagado.
    func exemploParaCaptura(gravando: Bool = false) {
        exemplo = true
        let pasta = CapturaServico.pastaPadrao.appendingPathComponent(PoliticaGravacao.subpasta)
        let agora = Date()
        let roteiro: [(CapturaExemplo.Tipo, TimeInterval, TimeInterval, Int64)] = [
            (.editor, 120, 42, 6_400_000), (.terminal, 4_300, 187, 31_800_000), (.painel, 97_000, 1_265, 214_000_000),
        ]
        gravacoes = []
        for (tipo, atras, duracao, bytes) in roteiro {
            let data = agora.addingTimeInterval(-atras)
            let g = Gravacao(url: pasta.appendingPathComponent(PoliticaGravacao.nomeArquivo(data)), data: data, bytes: bytes)
            gravacoes.append(g)
            duracoes[g.id] = duracao
            if let cg = CapturaExemplo.imagem(tipo) {
                miniaturas[g.id] = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            }
        }
        permissaoCamera = .authorized
        permissaoMicrofone = gravando ? .authorized : .denied
        aviso = nil
        fase = gravando ? .gravando(desde: agora.addingTimeInterval(-83)) : .parado
    }
}
