import AppKit
@preconcurrency import AVFoundation
import Combine
import Observation

// A voz do computador: quem fala quando o Crew lê uma resposta, dá um aviso ou uma sessão do
// Claude Code pede para falar. Dois motores de fala:
//   • a voz do macOS (`AVSpeechSynthesizer`, em `VozServico`): fala na hora, sem instalar nada;
//   • a voz humanizada (OmniVoice, motor externo): soa como gente, mas leva segundos para
//     gerar cada frase e ocupa ~1,05 GB de memória enquanto está ligada.
// Toda fala entra por `VozServico.falar`; aqui se decide o motor. Se o motor humanizado falhar
// ou não estiver instalado, a fala sai pela voz do macOS — o Crew nunca fica mudo por isso.
//
// Onde o tempo vai (medido num M2 de 16 GB, voz guardada, 32 passos): gerar uma frase curta
// leva de 6,5 a 11 s com o motor já ligado (varia com o que mais usa a GPU na hora), mais 1 a
// 10 s se ele estiver desligado. Ler e começar a tocar o áudio são milésimos. O que encurta:
//   • fala repetida não é gerada de novo (`CacheDeFala`): toca na hora, até com o motor desligado;
//   • os avisos das sessões abertas são gerados antes, em segundo plano, e esperam prontos;
//   • aviso que ainda não está pronto sai na voz do macOS (ajuste "aviso na hora") em vez de atrasar;
//   • o motor fica ligado um tempo depois da última fala e aquece ao abrir a página da voz;
//   • com o motor compilado com o ajuste do Crew, a velocidade (passos) é escolha do Hugo.
//
// Custo parado: zero de CPU. O servidor do motor só existe depois de um uso (fala, página da
// voz aberta, aviso para preparar) e é desligado depois do tempo escolhido sem uso, ou antes se
// a memória do Mac apertar; a assinatura das sessões só existe com o aviso por voz ligado.

@Observable @MainActor
final class FalaServico {
    static let shared = FalaServico()

    enum Motor: String, CaseIterable, Identifiable {
        case macos, omnivoice
        var id: String { rawValue }
        var rotulo: String { self == .macos ? "Voz do macOS (fala na hora)" : "Voz humanizada (OmniVoice, neste Mac)" }
    }

    enum Estado: Equatable { case parada, ligando, gerando, falando }

    /// Quanto o motor capricha em cada fala: os passos de geração. O tempo é proporcional a eles
    /// (32 passos ≈ 6,5 s numa frase curta neste Mac; 16 ≈ metade; 8 ≈ um quarto — conta feita
    /// pelo tempo medido por passo). Só vale com o motor compilado com o ajuste do Crew.
    enum Velocidade: String, CaseIterable, Identifiable {
        case rapida, equilibrada, melhor
        var id: String { rawValue }
        var passos: Int {
            switch self {
            case .rapida: 8
            case .equilibrada: 16
            case .melhor: 32
            }
        }
        var rotulo: String {
            switch self {
            case .rapida: "Mais rápida"
            case .equilibrada: "Equilibrada"
            case .melhor: "Melhor"
            }
        }
    }

    /// Por quanto tempo o motor fica ligado depois da última fala (minutos).
    static let temposLigado = [5, 20, 60]

    struct Aviso: Equatable {
        let texto: String
        let erro: Bool
    }

    /// Uma voz desenhada que o Hugo ainda está ouvindo, antes de guardar.
    struct Amostra: Equatable {
        let desenho: DesenhoDeVoz
        let wav: Data
    }

    /// O que a amostra de uma voz diz (e o que fica como texto da referência).
    static let fraseDeAmostra = "Oi, eu sou a voz do Crew. Estou aqui para te avisar do que acontece no seu Mac."
    /// Voz usada enquanto o Hugo não cria nenhuma: desenhada na hora, sem identidade fixa.
    static let desenhoPadrao = DesenhoDeVoz()

    // MARK: Ajustes

    var motor: Motor {
        didSet {
            Ajustes.definir(VozServico.modulo, "fala.motor", motor.rawValue)
            // Escolheu a voz humanizada (na página, que está aberta): o motor já vai ligando
            if motor == .omnivoice, oldValue != .omnivoice { aquecer() }
        }
    }
    /// A voz humanizada padrão (nil = a voz do motor, desenhada na hora).
    var vozId: String? {
        didSet {
            Ajustes.definir(VozServico.modulo, "fala.voz", vozId)
            // Com o motor ligado, a voz nova já fica registrada nele
            if vozId != oldValue, servidorLigado { aquecer() }
        }
    }
    /// As sessões do Claude Code podem falar pela ferramenta `falar`.
    var sessoesFalam: Bool { didSet { Ajustes.definir(VozServico.modulo, "fala.sessoes", sessoesFalam) } }
    /// Avisar por voz quando uma sessão pede aprovação ou pergunta algo (desligado por padrão).
    var avisarPendencia: Bool { didSet { Ajustes.definir(VozServico.modulo, "fala.avisarPendencia", avisarPendencia); aplicar() } }
    /// Aviso cuja voz humanizada ainda não está pronta sai na hora pela voz do macOS (e fica
    /// sendo gerado para a próxima vez). Desligado, o aviso espera a voz humanizada.
    var avisoNaHora: Bool { didSet { Ajustes.definir(VozServico.modulo, "fala.avisoNaHora", avisoNaHora) } }
    /// Minutos que o motor fica ligado depois da última fala.
    var manterLigado: Int {
        didSet {
            Ajustes.definir(VozServico.modulo, "fala.manterLigado", Double(manterLigado))
            servidor.ociosoMax = TimeInterval(manterLigado * 60)
        }
    }
    /// A escolha entre rapidez e capricho (só com o motor que aceita: `aceitaVelocidade`).
    var velocidade: Velocidade { didSet { Ajustes.definir(VozServico.modulo, "fala.velocidade", velocidade.rawValue) } }

    // MARK: Estado

    private(set) var estado = Estado.parada
    private(set) var instalado = MotorOmniVoice.instalado
    /// Instalação em curso: o passo (e a porcentagem do download).
    private(set) var instalando: String?
    private(set) var tamanhoMotor: Int64 = 0
    private(set) var servidorLigado = false
    /// Ligando o motor sem ter fala para dizer (página aberta, avisos para preparar).
    private(set) var aquecendo = false
    /// O motor instalado aceita a escolha de velocidade.
    private(set) var aceitaVelocidade = MotorOmniVoice.aceitaVelocidade
    /// Falas guardadas para repetir na hora: quantas e quanto ocupam.
    private(set) var falasGuardadas = 0
    private(set) var bytesDasFalas: Int64 = 0
    private(set) var vozes: [VozHumanizada] = []
    private(set) var amostra: Amostra?
    private(set) var gerandoAmostra = false
    private(set) var clonando = false
    var aviso: Aviso?

    var ocupada: Bool { estado != .parada }
    var vozPadrao: VozHumanizada? { vozes.first { $0.id == vozId } }
    /// A voz humanizada é quem fala agora (escolhida e instalada).
    var humanizadaEmUso: Bool { motor == .omnivoice && instalado }

    // MARK: Por dentro

    private struct Item {
        let id = UUID()
        let pedido: UUID
        let texto: String
        let voz: VozHumanizada?
        let geracao: Int
        /// Áudio já gerado (amostra): só toca.
        var pronto: Data?
    }

    @ObservationIgnored private let log = Log.de("voz")
    @ObservationIgnored private let servidor = ServidorOmniVoice()
    @ObservationIgnored private var ativo = false
    @ObservationIgnored private var exemplo = false
    @ObservationIgnored private var fila: [Item] = []
    @ObservationIgnored private var geracao = 0
    @ObservationIgnored private var corredor: Task<Void, Never>?
    @ObservationIgnored private var adiantadas: [UUID: Task<Data, Error>] = [:]
    @ObservationIgnored private var tocador: AVAudioPlayer?
    @ObservationIgnored private var ouvinte: OuvinteTocador?
    @ObservationIgnored private var fimDoToque: CheckedContinuation<Void, Never>?
    @ObservationIgnored private var procInstalar: ProcessoVivo?
    @ObservationIgnored private var passo = ""
    @ObservationIgnored private var ultimasLinhas: [String] = []
    @ObservationIgnored private var assinatura: AnyCancellable?
    @ObservationIgnored private var estadosVistos: [String: BotState] = [:]
    @ObservationIgnored private var primeiraLeitura = true
    @ObservationIgnored private let cache = CacheDeFala(pasta: MotorOmniVoice.falas)
    @ObservationIgnored private var aPreparar: [String] = []
    @ObservationIgnored private var preparo: Task<Void, Never>?
    @ObservationIgnored private var aquecimento: Task<Void, Never>?

    /// No máximo quantos avisos esperam na fila de preparo (cada um custa segundos de GPU).
    private static let maxAPreparar = 12

    private init() {
        let m = VozServico.modulo
        motor = Ajustes.string(m, "fala.motor").flatMap(Motor.init(rawValue:)) ?? .macos
        vozId = Ajustes.string(m, "fala.voz")
        sessoesFalam = Ajustes.bool(m, "fala.sessoes", padrao: true)
        avisarPendencia = Ajustes.bool(m, "fala.avisarPendencia", padrao: false)
        avisoNaHora = Ajustes.bool(m, "fala.avisoNaHora", padrao: true)
        let minutos = Int(Ajustes.double(m, "fala.manterLigado", padrao: 20))
        manterLigado = Self.temposLigado.contains(minutos) ? minutos : 20
        velocidade = Ajustes.string(m, "fala.velocidade").flatMap(Velocidade.init(rawValue:)) ?? .rapida   // Hugo ouviu os 8 passos e aprovou (2026-11-13)
        servidor.ociosoMax = TimeInterval(manterLigado * 60)
        servidor.mudou = { [weak self] in
            guard let self else { return }
            self.servidorLigado = self.servidor.ligado
            if self.servidor.ligado, self.estado == .ligando { self.estado = .gerando }
        }
    }

    // MARK: Ciclo do módulo

    func iniciar() {
        guard !ativo, !CaptureTool.ativo else { return }
        ativo = true
        MotorOmniVoice.limparSobra()
        atualizar()
        aplicar()
    }

    /// Módulo desligado (ou o Crew fechando): cala, derruba o servidor e a instalação.
    func desligar() {
        ativo = false
        calar()
        pararPreparo()
        servidor.desligar()
        procInstalar?.parar(); procInstalar = nil; instalando = nil
        aplicar()
    }

    private func aplicar() {
        guard ativo, avisarPendencia else { assinatura = nil; return }
        guard assinatura == nil else { return }
        estadosVistos = [:]
        primeiraLeitura = true
        assinatura = AppState.shared.$tasks
            .receive(on: DispatchQueue.main)
            .sink { [weak self] t in MainActor.assumeIsolated { self?.sessoesMudaram(t) } }
    }

    /// Relê o disco (ao abrir a página e depois de cada ação; sem vigia).
    func atualizar() {
        guard !exemplo else { return }
        instalado = MotorOmniVoice.instalado
        aceitaVelocidade = instalado && MotorOmniVoice.aceitaVelocidade
        tamanhoMotor = instalado ? MotorOmniVoice.tamanho() : 0
        vozes = VozHumanizada.listar()
        if let id = vozId, !vozes.contains(where: { $0.id == id }) { vozId = nil }
        contarFalas()
    }

    private func contarFalas() {
        let c = cache
        Task {
            let o = await Task.detached { c.ocupacao() }.value
            falasGuardadas = o.falas
            bytesDasFalas = o.bytes
        }
    }

    /// Apaga as falas guardadas (as próximas são geradas de novo).
    func limparFalas() {
        cache.limpar()
        falasGuardadas = 0
        bytesDasFalas = 0
    }

    // MARK: Aquecer e preparar

    /// Liga o motor e registra a voz padrão sem falar nada, para a próxima fala não esperar a
    /// ligada. Chamado quando faz sentido esperar uma fala: a página da voz aberta com a voz
    /// humanizada escolhida. Nunca no início do app.
    func aquecer() {
        guard ativo, humanizadaEmUso, !exemplo, instalando == nil, aquecimento == nil else { return }
        let voz = vozPadrao
        aquecendo = !servidor.ligado
        aquecimento = Task { [weak self] in
            try? await self?.servidor.aquecer(voz)
            self?.aquecendo = false
            self?.aquecimento = nil
        }
    }

    /// O nome de arquivo de uma fala no guardado: voz + velocidade + texto.
    private func chave(_ texto: String, _ voz: VozHumanizada?) -> String {
        let marca = voz.map { CacheDeFala.marca(id: $0.id, referencia: $0.referencia) }
            ?? "desenho:\(Self.desenhoPadrao.instrucoes):11"
        return CacheDeFala.chave(texto: texto, voz: marca, passos: passosEmVigor)
    }

    /// Os passos que o motor de fato usa: a escolha do Hugo, ou 32 no motor sem o ajuste.
    private var passosEmVigor: Int { aceitaVelocidade ? velocidade.passos : Velocidade.melhor.passos }

    /// A fala já está guardada inteira (toca na hora, sem gerar)?
    private func pronta(_ limpo: String, _ voz: VozHumanizada?) -> Bool {
        Self.pedacos(limpo).allSatisfy { cache.tem(chave($0, voz)) }
    }

    /// Gera em segundo plano, sem tocar, as falas que ainda não existem — para saírem na hora
    /// quando forem pedidas. Uma de cada vez, e só com a fila de fala vazia.
    private func preparar(_ textos: [String]) {
        guard ativo, humanizadaEmUso, !exemplo else { return }
        let voz = vozPadrao
        for t in textos.map(TextoFalavel.limpar) where !t.isEmpty && !aPreparar.contains(t) && !pronta(t, voz) {
            guard aPreparar.count < Self.maxAPreparar else { break }
            aPreparar.append(t)
        }
        prepararSeParado()
    }

    private func prepararSeParado() {
        guard preparo == nil, corredor == nil, !aPreparar.isEmpty else { return }
        preparo = Task { [weak self] in
            while let self, !Task.isCancelled, self.corredor == nil, let texto = self.aPreparar.first {
                self.aPreparar.removeFirst()
                guard self.humanizadaEmUso else { continue }
                let voz = self.vozPadrao
                for p in Self.pedacos(texto) where !self.cache.tem(self.chave(p, voz)) {
                    let item = Item(pedido: UUID(), texto: p, voz: voz, geracao: self.geracao)
                    // Falhou (motor fora do ar): desiste desta leva, sem aviso — ninguém pediu fala
                    guard (try? await self.gerar(item)) != nil else { self.aPreparar = []; break }
                }
            }
            self?.preparo = nil
        }
    }

    private func pararPreparo() {
        aPreparar = []
        preparo?.cancel()
        preparo = nil
        aquecimento?.cancel()
        aquecimento = nil
        aquecendo = false
    }

    // MARK: Falar

    /// Chamado por `VozServico` para cada fala: devolve true se a voz humanizada assumiu.
    func assumir(_ limpo: String, interromper: Bool) -> Bool {
        guard humanizadaEmUso, !exemplo else { return false }
        enfileirar(limpo, voz: vozPadrao)
        return true
    }

    /// Fala com uma voz humanizada escolhida pelo nome (ferramenta das sessões, botão "Ouvir").
    /// Sem nome, ou sem achar a voz, segue o caminho normal (`VozServico.falar`). Devolve quem falou.
    @discardableResult
    func falar(_ texto: String, voz nome: String? = nil) -> String {
        let v = VozServico.shared
        if let nome, instalado, !v.ocupado,
           let voz = vozes.first(where: { $0.id == nome || $0.nome.localizedCaseInsensitiveCompare(nome) == .orderedSame }) {
            let limpo = TextoFalavel.limpar(texto)
            guard !limpo.isEmpty else { return "nada a falar" }
            v.parar()
            enfileirar(limpo, voz: voz)
            return "voz humanizada \(voz.nome)"
        }
        v.falar(texto)
        return humanizadaEmUso ? "voz humanizada \(vozPadrao?.nome ?? "do motor")" : "voz do macOS"
    }

    private func enfileirar(_ limpo: String, voz: VozHumanizada?) {
        let pedido = UUID()
        for p in Self.pedacos(limpo) {
            fila.append(Item(pedido: pedido, texto: p, voz: voz, geracao: geracao))
        }
        correrSeParado()
    }

    private func correrSeParado() {
        guard corredor == nil, !fila.isEmpty else { return }
        estado = servidor.ligado ? .gerando : .ligando
        corredor = Task { [weak self] in await self?.correr() }
    }

    /// Cala a voz humanizada e esvazia a fila. O servidor continua ligado (desliga parado).
    func calar() {
        geracao += 1
        fila = []
        for t in adiantadas.values { t.cancel() }
        adiantadas = [:]
        tocador?.stop()
        tocouTudo()
    }

    private func correr() async {
        while !fila.isEmpty {
            let item = fila.removeFirst()
            guard item.geracao == geracao else { continue }
            do {
                let wav: Data
                if let pronto = item.pronto {
                    wav = pronto
                } else {
                    estado = servidor.ligado ? .gerando : .ligando
                    if let adiantada = adiantadas.removeValue(forKey: item.id) {
                        wav = try await adiantada.value
                    } else {
                        wav = try await gerar(item)
                    }
                }
                guard item.geracao == geracao else { continue }
                // Enquanto este pedaço toca, o próximo já vai sendo gerado
                if let prox = fila.first, prox.geracao == geracao, prox.pronto == nil, adiantadas[prox.id] == nil {
                    adiantadas[prox.id] = Task { [weak self] in
                        guard let self else { throw CancellationError() }
                        return try await self.gerar(prox)
                    }
                }
                estado = .falando
                await tocar(wav)
            } catch {
                guard item.geracao == geracao, !(error is CancellationError) else { continue }
                // O motor falhou: o resto deste pedido sai pela voz do macOS
                let resto = ([item.texto] + fila.filter { $0.pedido == item.pedido }.map(\.texto)).joined(separator: " ")
                fila.removeAll { $0.pedido == item.pedido }
                let motivo = (error as? ServidorOmniVoice.Falha)?.texto ?? error.localizedDescription
                log.error("voz humanizada falhou: \(motivo, privacy: .public)")
                aviso = Aviso(texto: "A voz humanizada falhou e a fala saiu pela voz do macOS.\n\(motivo)", erro: true)
                estado = .parada
                VozServico.shared.anunciar(resto, noMac: true)
            }
        }
        estado = .parada
        corredor = nil
        correrSeParado()   // entrou fala nova no último instante
        prepararSeParado() // e, sem fala, volta ao que estava sendo preparado
    }

    private func gerar(_ item: Item) async throws -> Data {
        // Já foi dita com esta voz e nesta velocidade: toca a guardada, sem motor
        let chave = chave(item.texto, item.voz)
        let c = cache
        if let guardada = await Task.detached(operation: { c.ler(chave) }).value { return guardada }
        // Sem voz guardada: desenho padrão com semente fixa (o timbre varia pouco entre falas)
        let wav = try await servidor.sintetizar(item.texto, voz: item.voz,
                                                instrucoes: item.voz == nil ? Self.desenhoPadrao.instrucoes : nil,
                                                semente: item.voz == nil ? 11 : nil,
                                                passos: aceitaVelocidade ? velocidade.passos : nil)
        Task.detached { c.guardar(chave, wav) }
        return wav
    }

    private func tocar(_ wav: Data) async {
        guard let p = try? AVAudioPlayer(data: wav) else { return }
        p.enableRate = true
        // A velocidade é a mesma dos ajustes da leitura (0,5 = normal na escala do macOS)
        p.rate = Float(min(max(VozServico.shared.velocidade / 0.5, 0.75), 1.3))
        let o = OuvinteTocador { [weak self] in self?.tocouTudo() }
        p.delegate = o
        tocador = p
        ouvinte = o
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            fimDoToque = c
            if !p.play() { tocouTudo() }
        }
    }

    private func tocouTudo() {
        tocador = nil
        ouvinte = nil
        let c = fimDoToque
        fimDoToque = nil
        c?.resume()
    }

    /// Como o texto é cortado para começar a falar mais cedo (`PedacosDeFala`).
    static func pedacos(_ texto: String) -> [String] { PedacosDeFala.cortar(texto) }

    // MARK: Motor — instalar, remover, desligar

    func instalar() {
        guard instalando == nil else { return }
        if let motivo = MotorOmniVoice.motivoIndisponivel { aviso = Aviso(texto: motivo, erro: true); return }
        do { try MotorOmniVoice.prepararPasta() } catch {
            aviso = Aviso(texto: "Não consegui criar a pasta do motor: \(error.localizedDescription)", erro: true)
            return
        }
        aviso = nil
        passo = "Preparando"
        instalando = passo
        ultimasLinhas = []
        procInstalar = ProcessoVivo("/bin/bash", MotorOmniVoice.argumentosDoRoteiro, pasta: MotorOmniVoice.pasta,
                                    ambiente: MotorOmniVoice.ambiente,
                                    linha: { [weak self] l in self?.linhaDaInstalacao(l) },
                                    fim: { [weak self] codigo in self?.instalou(codigo) })
        if procInstalar == nil { instalando = nil; aviso = Aviso(texto: "Não consegui começar a instalação.", erro: true) }
    }

    private func linhaDaInstalacao(_ linha: String) {
        let l = linha.trimmingCharacters(in: .whitespaces)
        if l.hasPrefix("PASSO: ") {
            passo = String(l.dropFirst(7))
            instalando = passo
        } else if l.hasSuffix("%"), let pct = l.split(separator: " ").last, Double(pct.dropLast()) != nil {
            // A barra do curl: "#####   43.2%"
            let texto = "\(passo) — \(pct.split(separator: ".").first ?? pct.dropLast())%"
            if texto != instalando { instalando = texto }
        } else if !l.isEmpty, !l.hasPrefix("#"), !l.hasPrefix("=") {
            ultimasLinhas.append(l)
            if ultimasLinhas.count > 20 { ultimasLinhas.removeFirst() }
        }
    }

    private func instalou(_ codigo: Int32) {
        let parado = procInstalar?.foiParado == true
        procInstalar = nil
        instalando = nil
        atualizar()
        if parado { return }
        if codigo == 0, instalado {
            aviso = Aviso(texto: vozes.isEmpty
                          ? "Motor de voz humanizada instalado. Crie uma voz abaixo ou use a voz do motor."
                          : "Motor de voz humanizada pronto. A velocidade da fala agora se escolhe acima.", erro: false)
        } else {
            aviso = Aviso(texto: "A instalação falhou.\n" + ultimasLinhas.suffix(6).joined(separator: "\n"), erro: true)
        }
    }

    func cancelarInstalacao() { procInstalar?.parar() }

    /// Compila o motor de novo com o ajuste do Crew (libera a escolha de velocidade). Baixa só
    /// o código (os pesos ficam) e leva cerca de um minuto; se falhar, o motor atual continua.
    func atualizarMotor() {
        guard instalando == nil, instalado, !aceitaVelocidade else { return }
        calar()
        pararPreparo()
        servidor.desligar()
        instalar()
    }

    /// Tira o motor do disco (programa e pesos). As vozes criadas ficam.
    func removerMotor() {
        guard instalando == nil else { return }
        calar()
        pararPreparo()
        servidor.desligar()
        MotorOmniVoice.remover()
        amostra = nil
        atualizar()
        aviso = Aviso(texto: "Motor removido. As vozes que você criou continuam guardadas; a fala voltou para a voz do macOS.", erro: false)
    }

    /// Desliga o servidor agora (libera a memória). Liga de novo sozinho na próxima fala.
    func desligarServidor() {
        calar()
        pararPreparo()
        servidor.desligar()
    }

    // MARK: Vozes

    /// Desenha uma voz pelos atributos e toca a amostra. Cada pedido dá uma voz diferente.
    func gerarAmostra(_ desenho: DesenhoDeVoz) {
        guard instalado, !gerandoAmostra, !exemplo else { return }
        gerandoAmostra = true
        aviso = nil
        Task {
            defer { gerandoAmostra = false }
            do {
                // A amostra vira a referência da voz: sempre no capricho máximo
                let wav = try await servidor.sintetizar(Self.fraseDeAmostra, voz: nil, instrucoes: desenho.instrucoes,
                                                        semente: Int.random(in: 1...999_999))
                amostra = Amostra(desenho: desenho, wav: wav)
                ouvirAmostra()
            } catch {
                aviso = Aviso(texto: (error as? ServidorOmniVoice.Falha)?.texto ?? error.localizedDescription, erro: true)
            }
        }
    }

    func ouvirAmostra() {
        guard let a = amostra else { return }
        VozServico.shared.parar()
        fila.append(Item(pedido: UUID(), texto: Self.fraseDeAmostra, voz: nil, geracao: geracao, pronto: a.wav))
        correrSeParado()
    }

    func descartarAmostra() { amostra = nil }

    /// Guarda a amostra aprovada como voz. A primeira voz guardada vira a padrão.
    func guardarAmostra(nome: String) {
        guard let a = amostra else { return }
        do {
            let voz = try VozHumanizada.guardar(nome: nome, origem: .desenhada, texto: Self.fraseDeAmostra,
                                                descricao: a.desenho.descricao, wav: a.wav)
            amostra = nil
            atualizar()
            if vozId == nil { vozId = voz.id }
            aviso = Aviso(texto: "Voz \(voz.nome) guardada.", erro: false)
        } catch {
            aviso = Aviso(texto: "Não consegui guardar a voz: \(error.localizedDescription)", erro: true)
        }
    }

    /// Cria uma voz a partir de uma gravação e do que é dito nela.
    func clonar(nome: String, arquivo: URL, transcricao: String) {
        guard !clonando else { return }
        clonando = true
        aviso = nil
        Task {
            defer { clonando = false }
            switch await VozHumanizada.converter(arquivo) {
            case .failure(let f):
                aviso = Aviso(texto: f.texto, erro: true)
            case .success(let wav):
                do {
                    let voz = try VozHumanizada.guardar(nome: nome, origem: .clonada,
                                                        texto: transcricao.trimmingCharacters(in: .whitespacesAndNewlines),
                                                        descricao: "Clonada de \(arquivo.lastPathComponent)", wav: wav)
                    atualizar()
                    if vozId == nil { vozId = voz.id }
                    aviso = Aviso(texto: "Voz \(voz.nome) criada. Clique em Ouvir para conferir.", erro: false)
                } catch {
                    aviso = Aviso(texto: "Não consegui guardar a voz: \(error.localizedDescription)", erro: true)
                }
            }
        }
    }

    func ouvir(_ voz: VozHumanizada) {
        guard instalado, !VozServico.shared.ocupado else { return }
        VozServico.shared.parar()
        enfileirar("Oi, \(Usuario.nome). É assim que eu falo quando o Crew tem algo para te contar.", voz: voz)
    }

    func remover(_ voz: VozHumanizada) {
        voz.apagar()
        servidor.esquecer(voz.id)
        if vozId == voz.id { vozId = nil }
        atualizar()
    }

    // MARK: Avisar quando uma sessão precisa do Hugo

    /// O que o Crew diz quando uma sessão precisa do Hugo. São frases fixas por projeto: dá
    /// para gerar antes e guardar.
    static func avisoDeAprovacao(_ nome: String) -> String { "\(nome) precisa da sua aprovação." }
    static func avisoDePergunta(_ nome: String) -> String { "\(nome) tem uma pergunta para você." }

    private func sessoesMudaram(_ tarefas: [AgentTask]) {
        var novos: [String] = []
        for t in tarefas where t.source == .claudeCode {
            let antes = estadosVistos[t.id]
            estadosVistos[t.id] = t.state
            guard avisarPendencia, !t.oculta else { continue }
            let nome = t.sessionCwd.map { ($0 as NSString).lastPathComponent } ?? t.displayTitle
            // Sessão que acabou de aparecer: os dois avisos dela já vão sendo preparados
            if antes == nil { novos += [Self.avisoDeAprovacao(nome), Self.avisoDePergunta(nome)] }
            guard !primeiraLeitura, antes != t.state else { continue }
            switch t.state {
            case .approval: avisar(Self.avisoDeAprovacao(nome))
            case .question: avisar(Self.avisoDePergunta(nome))
            default: break
            }
        }
        primeiraLeitura = false
        if !novos.isEmpty { preparar(novos) }
    }

    /// Um aviso tem hora: se a voz humanizada dele ainda não existe e o Hugo deixou "aviso na
    /// hora" ligado, sai já pela voz do macOS e a humanizada fica sendo gerada para a próxima.
    private func avisar(_ texto: String) {
        if humanizadaEmUso, avisoNaHora, !exemplo, !pronta(TextoFalavel.limpar(texto), vozPadrao) {
            VozServico.shared.anunciar(texto, noMac: true)
            preparar([texto])
        } else {
            VozServico.shared.anunciar(texto)
        }
    }

    // MARK: Capturas

    /// Só para o modo de capturas: motor instalado e vozes de exemplo, nada lido nem executado.
    func exemploParaCaptura(instalado: Bool = true) {
        exemplo = true
        self.instalado = instalado
        motor = instalado ? .omnivoice : .macos
        tamanhoMotor = instalado ? MotorOmniVoice.bytesDosPesos + 9_000_000 : 0
        servidorLigado = instalado
        aceitaVelocidade = instalado
        falasGuardadas = instalado ? 14 : 0
        bytesDasFalas = instalado ? 1_480_000 : 0
        guard instalado else { vozes = []; amostra = nil; return }
        vozes = [
            VozHumanizada(id: "clara", nome: "Clara", origem: .desenhada, textoDaReferencia: Self.fraseDeAmostra,
                          descricao: "Feminina, jovem adulta, tom médio", criada: Date().addingTimeInterval(-86_400)),
            VozHumanizada(id: "hugo", nome: Usuario.nome, origem: .clonada, textoDaReferencia: "",
                          descricao: "Clonada de minha-voz.m4a", criada: Date()),
        ]
        vozId = "clara"
        amostra = Amostra(desenho: DesenhoDeVoz(genero: .masculina, idade: .meiaIdade, tom: .grave), wav: Data())
    }
}

/// Recebe o fim do áudio (pode chegar fora da main) e repassa.
private final class OuvinteTocador: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {
    private let fim: @MainActor () -> Void
    init(_ fim: @escaping @MainActor () -> Void) { self.fim = fim }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let fim = fim
        DispatchQueue.main.async { MainActor.assumeIsolated { fim() } }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let fim = fim
        DispatchQueue.main.async { MainActor.assumeIsolated { fim() } }
    }
}
