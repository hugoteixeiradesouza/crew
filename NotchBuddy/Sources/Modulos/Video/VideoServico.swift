import AVFoundation
import AppKit
import SwiftUI

// O estado do módulo Vídeo: o motor (instalado ou não), os projetos, a renderização em curso,
// a prévia aberta e os vídeos prontos. Nada roda parado: o motor só tem processo vivo enquanto
// instala, renderiza ou serve a prévia — e `parar()` derruba os três.

struct ProjetoVideo: Identifiable, Hashable {
    let nome: String
    let pasta: URL
    let modificado: Date
    var id: String { nome }
}

struct VideoPronto: Identifiable, Hashable {
    let url: URL
    let data: Date
    let bytes: Int64
    var id: String { url.path }
    var nome: String { url.deletingPathExtension().lastPathComponent }
}

@MainActor
@Observable
final class VideoServico {
    static let shared = VideoServico()
    static let modulo = "video"

    struct Aviso: Equatable {
        let texto: String
        let erro: Bool
    }

    struct Render: Equatable {
        let projeto: String
        let composicao: String
        let saida: URL
        var fase = "Montando o projeto"
        var feitos = 0
        var total = 0
        var fracao: Double { total > 0 ? min(1, Double(feitos) / Double(total)) : 0 }
    }

    struct Previa: Equatable {
        let projeto: String
        let porta: Int
        var pronta = false
        var url: URL { URL(string: "http://localhost:\(porta)")! }
    }

    private(set) var instalado = MotorRemotion.instalado
    private(set) var versaoInstalada = MotorRemotion.versaoInstalada
    /// Instalação em curso: a última linha do que o npm disse.
    private(set) var instalando: String?
    private(set) var tamanhoMotor: Int64 = 0
    private(set) var projetos: [ProjetoVideo] = []
    private(set) var composicoes: [String: [String]] = [:]
    private(set) var lendoComposicoes: Set<String> = []
    private(set) var prontos: [VideoPronto] = []
    private(set) var miniaturas: [String: NSImage] = [:]
    private(set) var duracoes: [String: Double] = [:]
    private(set) var render: Render?
    private(set) var previa: Previa?
    /// Legendas pela fala: dá para transcrever no idioma do ditado? (nil = ainda não conferido)
    private(set) var fala: TranscricaoFala.Estado?
    /// Baixando o modelo de fala: fração de 0 a 1.
    private(set) var baixandoFala: Double?
    /// Projeto cuja gravação está sendo transcrita agora.
    private(set) var transcrevendo: String?
    var aviso: Aviso?

    @ObservationIgnored private let log = Log.de("video")
    @ObservationIgnored private var procInstalar: ProcessoVivo?
    @ObservationIgnored private var procRender: ProcessoVivo?
    @ObservationIgnored private var procPrevia: ProcessoVivo?
    @ObservationIgnored private var ultimasLinhas: [String] = []
    @ObservationIgnored private var ultimoPasso = -1
    /// Só no modo de capturas do app: dados de exemplo, nada lido do disco nem executado.
    @ObservationIgnored private var exemplo = false

    private init() {}

    // MARK: Ligar / desligar

    func parar() {
        procInstalar?.parar(); procInstalar = nil; instalando = nil
        procRender?.parar(); procRender = nil; render = nil
        fecharPrevia()
        Arbitro.shared.retirar("video.render")
    }

    // MARK: Leitura

    /// Relê o disco (ao abrir a página e depois de cada ação; sem vigia).
    func atualizar() {
        guard !exemplo else { return }
        instalado = MotorRemotion.instalado
        versaoInstalada = MotorRemotion.versaoInstalada
        projetos = Self.listarProjetos()
        prontos = Self.listarProntos()
        for p in prontos where miniaturas[p.id] == nil { Task { await carregarMiniatura(p) } }
        if instalado { Task { tamanhoMotor = await MotorRemotion.tamanho() } }
    }

    private static func listarProjetos() -> [ProjetoVideo] {
        let fm = FileManager.default
        let itens = (try? fm.contentsOfDirectory(at: MotorRemotion.videos, includingPropertiesForKeys: [.contentModificationDateKey],
                                                 options: [.skipsHiddenFiles])) ?? []
        return itens.compactMap { u -> ProjetoVideo? in
            guard fm.fileExists(atPath: u.appendingPathComponent("index.ts").path) else { return nil }
            // A data do projeto é a do arquivo mexido por último (a pasta não muda quando um arquivo muda)
            let arquivos = (try? fm.contentsOfDirectory(at: u, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            let data = arquivos.compactMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }.max()
            return ProjetoVideo(nome: u.lastPathComponent, pasta: u, modificado: data ?? .distantPast)
        }.sorted { $0.modificado > $1.modificado }
    }

    private static func listarProntos() -> [VideoPronto] {
        let chaves: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        let itens = (try? FileManager.default.contentsOfDirectory(at: MotorRemotion.saidas, includingPropertiesForKeys: chaves,
                                                                  options: [.skipsHiddenFiles])) ?? []
        return itens.filter { ["mp4", "mov", "webm", "gif"].contains($0.pathExtension.lowercased()) }.compactMap { u in
            let v = try? u.resourceValues(forKeys: Set(chaves))
            return VideoPronto(url: u, data: v?.contentModificationDate ?? .distantPast, bytes: Int64(v?.fileSize ?? 0))
        }.sorted { $0.data > $1.data }
    }

    private func carregarMiniatura(_ p: VideoPronto) async {
        let asset = AVURLAsset(url: p.url)
        if let d = try? await asset.load(.duration) { duracoes[p.id] = d.seconds }
        let gerador = AVAssetImageGenerator(asset: asset)
        gerador.appliesPreferredTrackTransform = true
        gerador.maximumSize = CGSize(width: 480, height: 480)
        let meio = CMTime(seconds: min(1, (duracoes[p.id] ?? 0) / 2), preferredTimescale: 600)
        if let r = try? await gerador.image(at: meio) {
            miniaturas[p.id] = NSImage(cgImage: r.image, size: .zero)
        }
    }

    // MARK: Motor

    func instalar() {
        guard instalando == nil else { return }
        if let motivo = MotorRemotion.motivoIndisponivel { aviso = Aviso(texto: motivo, erro: true); return }
        guard let npm = MotorRemotion.npm else { return }
        do { try MotorRemotion.prepararPasta() } catch {
            aviso = Aviso(texto: "Não consegui criar a pasta do motor: \(error.localizedDescription)", erro: true)
            return
        }
        aviso = nil
        instalando = "Baixando o Remotion…"
        ultimasLinhas = []
        procInstalar = ProcessoVivo(npm, ["install", "--no-audit", "--no-fund", "--loglevel=error"], pasta: MotorRemotion.pasta,
                                    ambiente: MotorRemotion.ambiente,
                                    linha: { [weak self] l in self?.anotar(l); self?.instalando = Self.curta(l) },
                                    fim: { [weak self] codigo in self?.instalouPacotes(codigo) })
        if procInstalar == nil { instalando = nil; aviso = Aviso(texto: "Não consegui rodar o npm.", erro: true) }
    }

    /// Segundo passo: o navegador sem janela que desenha os quadros (o Remotion baixa o dele).
    private func instalouPacotes(_ codigo: Int32) {
        guard procInstalar?.foiParado != true else { procInstalar = nil; instalando = nil; return }
        guard codigo == 0, MotorRemotion.instalado else {
            procInstalar = nil; instalando = nil
            aviso = Aviso(texto: "A instalação falhou.\n" + ultimasLinhas.suffix(5).joined(separator: "\n"), erro: true)
            return
        }
        instalando = "Baixando o navegador de renderização…"
        procInstalar = ProcessoVivo(MotorRemotion.cli.path, ["browser", "ensure"], pasta: MotorRemotion.pasta,
                                    ambiente: MotorRemotion.ambiente,
                                    linha: { [weak self] l in self?.anotar(l); self?.instalando = Self.curta(l) },
                                    fim: { [weak self] codigo in
            guard let self else { return }
            let parado = self.procInstalar?.foiParado == true
            self.procInstalar = nil; self.instalando = nil
            self.atualizar()
            if parado { return }
            self.aviso = codigo == 0
                ? Aviso(texto: "Motor de vídeo instalado.", erro: false)
                : Aviso(texto: "O motor foi instalado, mas o navegador de renderização não baixou (ele tenta de novo na primeira renderização).", erro: true)
        })
    }

    func cancelarInstalacao() { procInstalar?.parar() }

    /// Tira o motor do disco. Os projetos de vídeo e os vídeos prontos ficam.
    func removerMotor() {
        guard instalando == nil, render == nil else { return }
        fecharPrevia()
        try? FileManager.default.removeItem(at: MotorRemotion.pasta.appendingPathComponent("node_modules"))
        tamanhoMotor = 0
        atualizar()
        aviso = Aviso(texto: "Motor removido. Seus projetos e vídeos prontos continuam no lugar.", erro: false)
    }

    private func anotar(_ linha: String) {
        ultimasLinhas.append(linha)
        if ultimasLinhas.count > 300 { ultimasLinhas.removeFirst(ultimasLinhas.count - 300) }
    }

    private static func curta(_ linha: String) -> String {
        let l = linha.trimmingCharacters(in: .whitespaces)
        return l.count > 90 ? String(l.prefix(89)) + "…" : l
    }

    // MARK: Projetos

    /// Cria um projeto com o vídeo de partida. Devolve o nome da pasta.
    @discardableResult
    func criar(nome: String, titulo: String? = nil) -> Result<ProjetoVideo, MotorRemotion.Falha> {
        let base = MotorRemotion.nomeDePasta(nome)
        guard !base.isEmpty else { return .failure(.init(texto: "Dê um nome ao vídeo (letras ou números).")) }
        let fm = FileManager.default
        var pasta = MotorRemotion.pastaDoProjeto(base)
        var n = 2
        while fm.fileExists(atPath: pasta.path) { pasta = MotorRemotion.pastaDoProjeto("\(base)-\(n)"); n += 1 }
        do {
            try MotorRemotion.prepararPasta()
            try fm.createDirectory(at: pasta.appendingPathComponent("public"), withIntermediateDirectories: true)
            try ModeloVideo.indice.write(to: pasta.appendingPathComponent("index.ts"), atomically: true, encoding: .utf8)
            let t = (titulo?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? nome
            try ModeloVideo.raiz(titulo: t).write(to: pasta.appendingPathComponent("Raiz.tsx"), atomically: true, encoding: .utf8)
        } catch {
            return .failure(.init(texto: "Não consegui criar o projeto: \(error.localizedDescription)"))
        }
        atualizar()
        return .success(ProjetoVideo(nome: pasta.lastPathComponent, pasta: pasta, modificado: Date()))
    }

    /// Transforma uma gravação de tela num projeto de vídeo pronto para editar: copia o arquivo
    /// para dentro do projeto (no APFS a cópia não ocupa espaço), leva o rastro do mouse,
    /// transcreve a fala para as legendas, escreve o kit de edição, o roteiro de partida e o guia
    /// e, se pedido, abre a sessão do Claude Code que edita — enxergando o projeto de onde o
    /// vídeo vem (`contexto`), só para leitura.
    func editarGravacao(_ origem: URL, projeto contexto: ModeloEdicao.Contexto? = nil,
                        abrirSessao sessao: Bool = true) async -> Result<ProjetoVideo, MotorRemotion.Falha> {
        guard instalado else { return .failure(.init(texto: "Instale o motor de vídeo antes (Ajustes do Crew › Vídeo).")) }
        let asset = AVURLAsset(url: origem)
        guard let segundos = try? await asset.load(.duration).seconds, segundos > 0,
              let trilha = try? await asset.loadTracks(withMediaType: .video).first,
              let (tamanho, giro) = try? await trilha.load(.naturalSize, .preferredTransform) else {
            return .failure(.init(texto: "Não consegui ler a gravação."))
        }
        let real = tamanho.applying(giro)
        // Largura e altura pares: o H.264 não aceita ímpar.
        let largura = max(2, Int(abs(real.width).rounded()) / 2 * 2), altura = max(2, Int(abs(real.height).rounded()) / 2 * 2)
        let fps = 30
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH'h'mm"
        let data = (try? origem.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
        let fm = FileManager.default
        let base = MotorRemotion.nomeDePasta("gravacao " + f.string(from: data))
        var pasta = MotorRemotion.pastaDoProjeto(base)
        var n = 2
        while fm.fileExists(atPath: pasta.path) { pasta = MotorRemotion.pastaDoProjeto("\(base)-\(n)"); n += 1 }
        let arquivo = "gravacao." + (origem.pathExtension.isEmpty ? "mp4" : origem.pathExtension.lowercased())
        let midia = pasta.appendingPathComponent("public/" + arquivo)
        // O rastro do mouse (posição e cliques) que o Crew guarda ao lado da gravação.
        let rastro = PoliticaGravacao.rastro(de: origem)
        let comMouse = fm.fileExists(atPath: rastro.path)
        let juntadas: Int
        do {
            try MotorRemotion.prepararPasta()
            try fm.createDirectory(at: pasta.appendingPathComponent("public"), withIntermediateDirectories: true)
            try fm.createDirectory(at: pasta.appendingPathComponent("kit"), withIntermediateDirectories: true)
            // Som do Mac e microfone vêm em trilhas separadas: viram uma só (a imagem não é recodificada).
            juntadas = try await MidiaGravacao.levar(origem, para: midia)
            let mouse = pasta.appendingPathComponent("public/" + ModeloEdicao.arquivoMouse)
            if comMouse { try fm.copyItem(at: rastro, to: mouse) }
            else { try ModeloEdicao.mouseVazio.write(to: mouse, atomically: true, encoding: .utf8) }
            try TranscricaoFala.Legendas.vazias.json().write(to: pasta.appendingPathComponent("public/" + ModeloEdicao.arquivoLegendas))
            for (caminho, texto) in KitEdicao.arquivos {
                try texto.write(to: pasta.appendingPathComponent(caminho), atomically: true, encoding: .utf8)
            }
            let titulo = contexto?.nome ?? "Gravação de tela"
            try ModeloEdicao.gravacaoTS(arquivo: arquivo, largura: largura, altura: altura, fps: fps, segundos: segundos)
                .write(to: pasta.appendingPathComponent("gravacao.ts"), atomically: true, encoding: .utf8)
            try ModeloEdicao.temaTS(projeto: titulo, cor: contexto?.cor ?? "#FF7A59")
                .write(to: pasta.appendingPathComponent("tema.ts"), atomically: true, encoding: .utf8)
            try ModeloEdicao.roteiroTS(titulo: titulo, autor: NSFullUserName(), segundos: segundos)
                .write(to: pasta.appendingPathComponent("roteiro.ts"), atomically: true, encoding: .utf8)
            if let contexto { try Self.guardarContexto(contexto, em: pasta) }
        } catch {
            try? fm.removeItem(at: pasta)
            return .failure(.init(texto: "Não consegui criar o projeto: \(error.localizedDescription)"))
        }
        let projeto = ProjetoVideo(nome: pasta.lastPathComponent, pasta: pasta, modificado: Date())
        // A fala vira legenda (neste Mac). Sem ela a edição segue: o guia diz à sessão o que houve.
        let fala = await transcrever(midia, de: projeto, segundos: segundos)
        try? ModeloEdicao.guia(arquivo: arquivo, largura: largura, altura: altura, fps: fps, segundos: segundos, comMouse: comMouse,
                               trilhasJuntadas: juntadas, fala: fala, contexto: contexto, nomeDoProjetoDeVideo: projeto.nome)
            .write(to: pasta.appendingPathComponent("CLAUDE.md"), atomically: true, encoding: .utf8)
        atualizar()
        if sessao { abrirSessao(projeto, pedido: ModeloEdicao.pedidoInicial(contexto: contexto)) }
        return .success(projeto)
    }

    // MARK: Legendas pela fala

    /// Idioma da fala: o mesmo do ditado (Ajustes › Voz).
    var idiomaDaFala: String { Ajustes.string("voz", "idioma") ?? "pt-BR" }

    /// Confere se dá para transcrever (não baixa nada, não pede permissão).
    func conferirFala() {
        guard !exemplo else { return }
        let idioma = idiomaDaFala
        Task { fala = await TranscricaoFala.estado(idioma: idioma) }
    }

    /// Baixa o modelo de fala do idioma do ditado (da Apple, pelo sistema). Só por clique.
    func baixarModeloDeFala() {
        guard baixandoFala == nil else { return }
        let idioma = idiomaDaFala
        baixandoFala = 0
        Task {
            do {
                try await TranscricaoFala.baixarModelo(idioma: idioma) { fracao in
                    Task { @MainActor in if VideoServico.shared.baixandoFala != nil { VideoServico.shared.baixandoFala = fracao } }
                }
                aviso = Aviso(texto: "Modelo de fala de \(idioma) instalado: as próximas edições já saem com legenda.", erro: false)
            } catch {
                aviso = Aviso(texto: "O modelo de fala não baixou: \((error as? TranscricaoFala.Falha)?.texto ?? error.localizedDescription)", erro: true)
            }
            baixandoFala = nil
            fala = await TranscricaoFala.estado(idioma: idioma)
        }
    }

    /// Transcreve a gravação do projeto e grava `public/legendas.json`.
    private func transcrever(_ midia: URL, de projeto: ProjetoVideo, segundos: Double) async -> ModeloEdicao.Fala {
        let idioma = idiomaDaFala
        let estado = await TranscricaoFala.estado(idioma: idioma)
        fala = estado
        switch estado {
        case .semSuporte(let motivo): return .indisponivel(motivo)
        case .faltaModelo: return .indisponivel("falta baixar o modelo de fala de \(idioma) em Ajustes do Crew › Vídeo")
        case .pronto: break
        }
        transcrevendo = projeto.nome
        defer { transcrevendo = nil }
        do {
            let legendas = try await TranscricaoFala.transcrever(midia, idioma: idioma, prazo: max(90, segundos))
            try legendas.json().write(to: projeto.pasta.appendingPathComponent("public/" + ModeloEdicao.arquivoLegendas))
            return legendas.frases.isEmpty ? .semFala : .transcrita(frases: legendas.frases.count, idioma: legendas.idioma)
        } catch {
            let motivo = (error as? TranscricaoFala.Falha)?.texto ?? error.localizedDescription
            log.error("transcrição falhou: \(motivo, privacy: .public)")
            return .indisponivel(motivo)
        }
    }

    /// A gravação que está dentro de um projeto de vídeo (nil = o projeto não nasceu de uma).
    static func gravacaoDe(_ p: ProjetoVideo) -> URL? {
        let itens = (try? FileManager.default.contentsOfDirectory(at: p.pasta.appendingPathComponent("public"), includingPropertiesForKeys: nil)) ?? []
        return itens.first { $0.deletingPathExtension().lastPathComponent == "gravacao" && ["mp4", "mov"].contains($0.pathExtension.lowercased()) }
    }

    /// Refaz as legendas de um projeto já criado (depois de baixar o modelo, ou de trocar o idioma).
    /// Só troca `public/legendas.json`: roteiro, tema e o resto da edição ficam como estão.
    func refazerLegendas(_ p: ProjetoVideo) {
        guard transcrevendo == nil, let midia = Self.gravacaoDe(p) else { return }
        Task {
            let segundos = (try? await AVURLAsset(url: midia).load(.duration).seconds) ?? 0
            switch await transcrever(midia, de: p, segundos: segundos) {
            case .transcrita(let n, let idioma):
                aviso = Aviso(texto: "Legendas de \(p.nome) refeitas: \(n == 1 ? "1 frase" : "\(n) frases") (\(idioma)).", erro: false)
            case .semFala:
                aviso = Aviso(texto: "Não achei fala na gravação de \(p.nome).", erro: false)
            case .indisponivel(let motivo):
                aviso = Aviso(texto: "Sem legendas em \(p.nome): \(motivo).", erro: true)
            }
        }
    }

    // MARK: Projeto de origem

    private static let arquivoContexto = "crew.json"

    private static func guardarContexto(_ c: ModeloEdicao.Contexto, em pasta: URL) throws {
        let dados = try JSONSerialization.data(withJSONObject: ["projeto": c.caminho, "nome": c.nome, "cor": c.cor], options: [.prettyPrinted, .sortedKeys])
        try dados.write(to: pasta.appendingPathComponent(arquivoContexto))
    }

    /// De que projeto do Hugo é este vídeo (guardado ao criar a edição; nil = nenhum, ou a pasta sumiu).
    static func contexto(de p: ProjetoVideo) -> ModeloEdicao.Contexto? {
        guard let dados = try? Data(contentsOf: p.pasta.appendingPathComponent(arquivoContexto)),
              let d = try? JSONSerialization.jsonObject(with: dados) as? [String: String],
              let caminho = d["projeto"], FileManager.default.fileExists(atPath: caminho) else { return nil }
        return .init(nome: d["nome"] ?? URL(fileURLWithPath: caminho).lastPathComponent, caminho: caminho, cor: d["cor"] ?? "#FF7A59")
    }

    func carregarComposicoes(_ projeto: String) {
        guard instalado, !lendoComposicoes.contains(projeto), !exemplo else { return }
        lendoComposicoes.insert(projeto)
        Task {
            switch await MotorRemotion.composicoes(projeto) {
            case .success(let ids): composicoes[projeto] = ids
            case .failure(let f):
                composicoes[projeto] = []
                aviso = Aviso(texto: "O projeto \(projeto) não montou:\n\(f.texto)", erro: true)
            }
            lendoComposicoes.remove(projeto)
        }
    }

    func mostrarNoFinder(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }

    /// Manda o projeto para o Lixo (dá para recuperar de lá).
    func apagarProjeto(_ p: ProjetoVideo) {
        if previa?.projeto == p.nome { fecharPrevia() }
        NSWorkspace.shared.recycle([p.pasta]) { [weak self] _, _ in Task { @MainActor in self?.atualizar() } }
        composicoes[p.nome] = nil
    }

    func apagarVideo(_ v: VideoPronto) {
        NSWorkspace.shared.recycle([v.url]) { [weak self] _, _ in Task { @MainActor in self?.atualizar() } }
        miniaturas[v.id] = nil
    }

    /// Abre uma sessão do Claude Code na pasta do projeto, já com o pedido (vazio = em branco).
    /// Vídeo ligado a um projeto do Hugo: a sessão enxerga a pasta dele, só para leitura.
    func abrirSessao(_ p: ProjetoVideo, pedido: String = "") {
        var opcoes = MotorCrew.Opcoes()
        if let c = Self.contexto(de: p) {
            opcoes.pastasExtras = [c.caminho]
            opcoes.somenteLeitura = [c.caminho]
            opcoes.instrucao = ModeloEdicao.instrucao(contexto: c)
            opcoes.nome = "Vídeo · \(c.nome)"
        }
        Task {
            switch await MotorCrew.nova(pasta: p.pasta.path, pedido: pedido, opcoes: opcoes) {
            case .success:
                Central.abrirSessoes()
            case .failure:
                aviso = Aviso(texto: MotorCrew.motivoIndisponivel ?? "Não consegui abrir a sessão do Claude Code.", erro: true)
            }
        }
    }

    // MARK: Renderizar

    /// Começa a renderizar e volta na hora. O andamento fica em `render` e na barra da ilha.
    @discardableResult
    func renderizar(projeto: String, composicao: String, props: String? = nil) -> Result<URL, MotorRemotion.Falha> {
        guard instalado else { return .failure(.init(texto: "O motor de vídeo não está instalado (Ajustes do Crew › Vídeo).")) }
        guard render == nil else { return .failure(.init(texto: "Já há um vídeo renderizando (\(render!.projeto)). Espere terminar.")) }
        guard FileManager.default.fileExists(atPath: MotorRemotion.pastaDoProjeto(projeto).appendingPathComponent("index.ts").path) else {
            return .failure(.init(texto: "Projeto de vídeo não encontrado: \(projeto)."))
        }
        try? FileManager.default.createDirectory(at: MotorRemotion.saidas, withIntermediateDirectories: true)
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let saida = MotorRemotion.saidas.appendingPathComponent("\(projeto) \(composicao) \(f.string(from: Date())).mp4")
        var args = ["render", MotorRemotion.entrada(projeto), composicao, saida.path, MotorRemotion.midia(projeto)]
        if let props, !props.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { args.append("--props=\(props)") }
        ultimasLinhas = []
        ultimoPasso = -1
        render = Render(projeto: projeto, composicao: composicao, saida: saida)
        aviso = nil
        procRender = ProcessoVivo(MotorRemotion.cli.path, args, pasta: MotorRemotion.pasta, ambiente: MotorRemotion.ambiente,
                                  linha: { [weak self] l in self?.andamento(l) },
                                  fim: { [weak self] codigo in self?.renderTerminou(codigo) })
        guard procRender != nil else {
            render = nil
            return .failure(.init(texto: "Não consegui rodar o motor de vídeo."))
        }
        sinalRender()
        return .success(saida)
    }

    func cancelarRender() { procRender?.parar() }

    private func andamento(_ linha: String) {
        anotar(linha)
        guard var r = render else { return }
        if let (a, b) = Self.fracao(linha, "Rendered") { r.fase = "Desenhando os quadros"; r.feitos = a; r.total = b }
        else if let (a, b) = Self.fracao(linha, "Encoded") { r.fase = "Gravando o arquivo"; r.feitos = a; r.total = b }
        else if linha.contains("Bundl") { r.fase = "Montando o projeto" }
        else if linha.contains("Headless Shell") { r.fase = "Baixando o navegador de renderização" }
        guard r != render else { return }
        render = r
        // A barra da ilha só é trocada a cada 5 %: nada de redesenhar o notch a cada quadro.
        let passo = Int(r.fracao * 20) + (r.fase.hasPrefix("Gravando") ? 100 : 0)
        if passo != ultimoPasso { ultimoPasso = passo; sinalRender() }
    }

    /// "Rendered 52/60, …" → (52, 60).
    private static func fracao(_ linha: String, _ palavra: String) -> (Int, Int)? {
        guard let r = linha.range(of: palavra + " ") else { return nil }
        let resto = linha[r.upperBound...].prefix { $0.isNumber || $0 == "/" }
        let partes = resto.split(separator: "/")
        guard partes.count == 2, let a = Int(partes[0]), let b = Int(partes[1]), b > 0 else { return nil }
        return (a, b)
    }

    private func sinalRender() {
        guard let r = render else { return }
        let pct = r.total > 0 ? " \(Int(r.fracao * 100)) %" : ""
        Arbitro.shared.publicar(Sinal(id: "video.render", lugar: .barra, prioridade: .atividade, clicavel: true,
                                      conteudo: AnyView(AvisoVideo(icone: "film", texto: "\(r.fase)\(pct) — \(r.projeto)", cor: Color(hex: "#A78BFA")))))
    }

    private func renderTerminou(_ codigo: Int32) {
        guard let r = render else { return }
        let parado = procRender?.foiParado == true
        procRender = nil
        render = nil
        Arbitro.shared.retirar("video.render")
        atualizar()
        if parado {
            try? FileManager.default.removeItem(at: r.saida)
            aviso = Aviso(texto: "Renderização cancelada.", erro: false)
            return
        }
        if codigo == 0, FileManager.default.fileExists(atPath: r.saida.path) {
            aviso = Aviso(texto: "Vídeo pronto: \(r.saida.lastPathComponent)", erro: false)
            Arbitro.shared.publicar(Sinal(id: "video.aviso", lugar: .barra, prioridade: .alerta, duracao: 8, clicavel: true,
                                          conteudo: AnyView(AvisoVideo(icone: "checkmark.circle.fill", texto: "Vídeo pronto: \(r.projeto)", cor: Color(hex: "#34D399")))))
            NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
        } else {
            // O motivo de verdade é a linha "Error: …"; sem ela, as últimas linhas do que o motor disse.
            let uteis = ultimasLinhas.filter { !$0.hasPrefix("Rendered") && !$0.hasPrefix("Encoded") }
            let erros = uteis.filter { $0.contains("Error:") || $0.contains("error:") }
            let motivo = (erros.isEmpty ? Array(uteis.suffix(6)) : Array(erros.suffix(2))).joined(separator: "\n")
            aviso = Aviso(texto: "A renderização de \(r.projeto) falhou.\n\(motivo)", erro: true)
            Arbitro.shared.publicar(Sinal(id: "video.aviso", lugar: .barra, prioridade: .alerta, duracao: 8, clicavel: true,
                                          conteudo: AnyView(AvisoVideo(icone: "exclamationmark.triangle.fill", texto: "O vídeo \(r.projeto) não renderizou", cor: .orange))))
            log.error("render falhou: \(motivo, privacy: .public)")
        }
    }

    /// O motivo da última falha (para a ferramenta do Claude devolver à sessão).
    var ultimoErro: String? { aviso?.erro == true ? aviso?.texto : nil }

    // MARK: Prévia (Remotion Studio)

    /// Sobe a prévia do projeto (um servidor local do motor) e abre no navegador do Crew.
    func abrirPrevia(_ projeto: String) {
        guard instalado else { return }
        if let p = previa, p.projeto == projeto, procPrevia?.rodando == true {
            if p.pronta { mostrar(p.url) }
            return
        }
        fecharPrevia()
        guard let porta = Self.portaLivre() else { aviso = Aviso(texto: "Não achei uma porta livre para a prévia.", erro: true); return }
        previa = Previa(projeto: projeto, porta: porta)
        aviso = nil
        procPrevia = ProcessoVivo(MotorRemotion.cli.path, ["studio", MotorRemotion.entrada(projeto), MotorRemotion.midia(projeto), "--port=\(porta)", "--no-open"],
                                  pasta: MotorRemotion.pasta, ambiente: MotorRemotion.ambiente,
                                  linha: { [weak self] l in
            guard let self, var p = self.previa, !p.pronta else { return }
            self.anotar(l)
            if l.contains("localhost:\(porta)") || l.contains("Server ready") {
                p.pronta = true
                self.previa = p
                self.mostrar(p.url)
            }
        }, fim: { [weak self] _ in
            guard let self, self.previa?.porta == porta else { return }
            let caiu = self.procPrevia?.foiParado != true
            self.procPrevia = nil
            self.previa = nil
            if caiu { self.aviso = Aviso(texto: "A prévia fechou sozinha.\n" + self.ultimasLinhas.suffix(4).joined(separator: "\n"), erro: true) }
        })
        if procPrevia == nil { previa = nil; aviso = Aviso(texto: "Não consegui abrir a prévia.", erro: true) }
    }

    func fecharPrevia() {
        procPrevia?.parar()
        procPrevia = nil
        previa = nil
    }

    private func mostrar(_ url: URL) {
        Central.abrirSessoes()
        // A janela do app pode estar nascendo agora: o pedido chega depois de ela montar.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            NotificationCenter.default.post(name: .abrirNoNavegador, object: url)
        }
    }

    private static func portaLivre() -> Int? {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var end = sockaddr_in()
        end.sin_family = sa_family_t(AF_INET)
        end.sin_addr.s_addr = inet_addr("127.0.0.1")
        end.sin_port = 0
        var tamanho = socklen_t(MemoryLayout<sockaddr_in>.size)
        let ok = withUnsafeMutablePointer(to: &end) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { s in
                bind(fd, s, tamanho) == 0 && getsockname(fd, s, &tamanho) == 0
            }
        }
        return ok ? Int(UInt16(bigEndian: end.sin_port)) : nil
    }

    // MARK: Exemplo (modo de capturas)

    func exemploParaCaptura(instalado: Bool = true) {
        exemplo = true
        self.instalado = instalado
        versaoInstalada = instalado ? MotorRemotion.versao : nil
        tamanhoMotor = instalado ? 271_000_000 : 0
        fala = .faltaModelo
        guard instalado else { projetos = []; prontos = []; return }
        let base = MotorRemotion.videos
        projetos = [("lancamento-crew", 600.0), ("tutorial-ditado", 86_400.0 * 2)].map {
            ProjetoVideo(nome: $0.0, pasta: base.appendingPathComponent($0.0), modificado: Date().addingTimeInterval(-$0.1))
        }
        composicoes = ["lancamento-crew": ["Abertura", "Vertical"], "tutorial-ditado": ["Abertura"]]
        prontos = [("lancamento-crew Abertura", 300.0, 4_200_000), ("tutorial-ditado Abertura", 90_000.0, 11_800_000)].map {
            VideoPronto(url: MotorRemotion.saidas.appendingPathComponent($0.0 + ".mp4"), data: Date().addingTimeInterval(-$0.1), bytes: Int64($0.2))
        }
        duracoes = [prontos[0].id: 12, prontos[1].id: 48]
        render = Render(projeto: "lancamento-crew", composicao: "Vertical", saida: prontos[0].url, fase: "Desenhando os quadros", feitos: 132, total: 300)
    }
}

/// A linha do Vídeo na barra da ilha fechada: o clique leva à página do módulo.
struct AvisoVideo: View {
    let icone: String
    let texto: String
    let cor: Color

    var body: some View {
        AvisoBarra(icone: icone, texto: texto, cor: cor)
            .contentShape(Rectangle())
            .onTapGesture { Central.abrir(modulo: VideoServico.modulo) }
    }
}
