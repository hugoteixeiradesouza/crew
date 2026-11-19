import AppKit
@preconcurrency import AVFoundation
import Combine
import Observation
import Speech

// Voz do Crew: ditado (fala → texto) e leitura em voz alta (texto → fala).
//
// Custo parado: zero. O motor de áudio e o reconhecedor só existem enquanto um ditado dura
// (`CapturaVoz`), e o sintetizador só enquanto há algo sendo lido. Sem timer. O que fica ligado
// em segundo plano é só o que o Hugo ligou nos ajustes, e sempre por evento:
//   • o atalho de segurar para falar (o macOS avisa a combinação exata);
//   • a assinatura de `AppState.$tasks` para ler a entrega quando a sessão termina.
//
// Privacidade: o reconhecimento é exigido no aparelho sempre que o Mac suporta o idioma. Se não
// suporta, o ditado NÃO cai para a rede sozinho: avisa, e só usa o reconhecimento da Apple se o
// Hugo ligar "permitir reconhecimento pela Apple (rede)". Nada é gravado em disco.

@Observable @MainActor
final class VozServico {
    static let shared = VozServico()
    static let modulo = "voz"

    enum Estado: Equatable {
        case parado
        case pedindoPermissao
        case ouvindo
        /// Parou de ouvir; o reconhecedor está fechando o texto (instantes).
        case finalizando
        case erro(String)
    }

    struct VozInstalada: Identifiable, Equatable {
        let id: String
        let nome: String
    }

    // MARK: Ditado — estado

    private(set) var estado: Estado = .parado
    /// O que foi entendido até agora, enquanto ouve.
    private(set) var textoParcial = ""
    /// O texto fechado do último ditado (vazio enquanto ouve).
    private(set) var textoFinal = ""
    /// 0…1, para o medidor.
    private(set) var nivel: Float = 0
    /// Quem pediu o ditado em curso (ou o último): cada tela usa o seu id e só ela recebe o texto.
    private(set) var dono: String?
    private(set) var microfone = PermissaoVoz.microfone()
    private(set) var fala = PermissaoVoz.fala()

    /// O melhor texto do ditado do `dono`: o parcial enquanto ouve, o final depois.
    var texto: String { textoFinal.isEmpty ? textoParcial : textoFinal }
    var ouvindo: Bool { estado == .ouvindo }
    var ocupado: Bool { estado == .ouvindo || estado == .finalizando || estado == .pedindoPermissao }

    /// As duas permissões juntas: negada se alguma foi negada; concedida só com as duas.
    var permissao: PermissaoVoz {
        if microfone == .negada || fala == .negada { return .negada }
        return microfone == .concedida && fala == .concedida ? .concedida : .naoPerguntada
    }

    // MARK: Leitura — estado

    /// O texto (como foi pedido) que está sendo lido agora.
    private(set) var falandoTexto: String?
    var falando: Bool { falandoTexto != nil || FalaServico.shared.ocupada }

    // MARK: Ajustes

    /// Idioma do ditado (identificador de `SFSpeechRecognizer.supportedLocales()`).
    var idioma: String { didSet { Ajustes.definir(Self.modulo, "idioma", idioma) } }
    /// "Permitir reconhecimento pela Apple (rede)": só vale quando o Mac não reconhece o idioma sozinho.
    var permitirRede: Bool { didSet { Ajustes.definir(Self.modulo, "permitirRede", permitirRede) } }
    /// Segurar para falar (atalho global).
    var atalhoLigado: Bool { didSet { Ajustes.definir(Self.modulo, "atalho", atalhoLigado); aplicar() } }
    var combinacao: AtalhoFalar.Combinacao {
        didSet { Ajustes.definir(Self.modulo, "combinacao", combinacao.rawValue); aplicar() }
    }
    /// Segurar a tecla Fn (Globo) para falar, de qualquer app.
    var teclaFnLigada: Bool { didSet { Ajustes.definir(Self.modulo, "teclaFn", teclaFnLigada); aplicar() } }
    /// Ao soltar, colar o texto no app em foco (senão, só copia).
    var colarNoApp: Bool { didSet { Ajustes.definir(Self.modulo, "colarNoApp", colarNoApp) } }
    /// O que o Crew faz com a fala antes de entregar (`Politicas/LapidarDitado.swift`).
    enum Lapidacao: String, CaseIterable, Identifiable, Sendable {
        case literal, limpar, formatar
        var id: String { rawValue }
        var rotulo: String {
            switch self {
            case .literal: "Literal (como o macOS transcreveu)"
            case .limpar: "Limpar (dicionário, muletas, correções, pontuação)"
            case .formatar: "Limpar e formatar (também monta lista)"
            }
        }
    }
    var lapidacao: Lapidacao { didSet { Ajustes.definir(Self.modulo, "lapidacao", lapidacao.rawValue) } }
    /// O dicionário do Hugo, "como eu falo -> como se escreve", uma entrada por linha ou
    /// separadas por ";" (a chave do ajuste continua "vocabulario"; a lista antiga, só de
    /// nomes separados por vírgula, segue valendo para acertar a maiúscula).
    var vocabulario: String { didSet { Ajustes.definir(Self.modulo, "vocabulario", vocabulario) } }
    /// O texto do segurar-para-falar vai para a sessão em foco (senão, só copia).
    var mandarParaSessao: Bool { didSet { Ajustes.definir(Self.modulo, "mandarParaSessao", mandarParaSessao) } }
    /// Identificador da voz escolhida (nil = a padrão do macOS para pt-BR).
    var vozId: String? { didSet { Ajustes.definir(Self.modulo, "voz", vozId) } }
    /// Velocidade da leitura (escala do AVSpeechUtterance; 0,5 = normal).
    var velocidade: Double { didSet { Ajustes.definir(Self.modulo, "velocidade", velocidade) } }
    /// Ler o primeiro parágrafo da entrega quando uma sessão termina.
    var lerEntrega: Bool { didSet { Ajustes.definir(Self.modulo, "lerEntrega", lerEntrega); aplicar() } }

    /// O macOS recusou a combinação do atalho (outro app usa).
    private(set) var atalhoRecusado = false
    /// A tecla Fn está ligada nos ajustes, mas o macOS não deixou escutar (falta Acessibilidade).
    private(set) var fnSemPermissao = false

    static let velocidades: ClosedRange<Double> = 0.35...0.62

    // MARK: Por dentro

    @ObservationIgnored private let log = Log.de("voz")
    @ObservationIgnored private var ativo = false
    @ObservationIgnored private var simulado = false
    @ObservationIgnored private var captura: CapturaVoz?
    @ObservationIgnored private var reconhecedor: SFSpeechRecognizer?
    @ObservationIgnored private var geracao = 0
    @ObservationIgnored private var aoTerminar: ((String?) -> Void)?
    @ObservationIgnored private var limiteFinal: DispatchWorkItem?
    @ObservationIgnored private var sintetizador: AVSpeechSynthesizer?
    @ObservationIgnored private var ouvinteFala: OuvinteFala?
    @ObservationIgnored private var naFila: [ObjectIdentifier: String] = [:]
    @ObservationIgnored private var assinaturaSessoes: AnyCancellable?
    @ObservationIgnored private var entregasVistas: [String: String] = [:]
    @ObservationIgnored private var primeiraLeitura = true
    @ObservationIgnored private var assinouEm = Date()
    @ObservationIgnored private lazy var atalho = AtalhoFalar(apertou: { VozGlobal.apertou() }, soltou: { VozGlobal.soltou() })

    @ObservationIgnored private lazy var teclaFn = TeclaFn(apertou: { VozGlobal.apertou() }, soltou: { VozGlobal.soltou() },
                                                           cancelou: { VozGlobal.cancelou() })

    private init() {
        let m = Self.modulo
        idioma = Ajustes.string(m, "idioma") ?? "pt-BR"
        permitirRede = Ajustes.bool(m, "permitirRede", padrao: false)
        atalhoLigado = Ajustes.bool(m, "atalho", padrao: false)
        combinacao = Ajustes.string(m, "combinacao").flatMap(AtalhoFalar.Combinacao.init(rawValue:)) ?? .controleOpcao
        teclaFnLigada = Ajustes.bool(m, "teclaFn", padrao: false)
        colarNoApp = Ajustes.bool(m, "colarNoApp", padrao: true)
        lapidacao = Ajustes.string(m, "lapidacao").flatMap(Lapidacao.init(rawValue:)) ?? .literal
        vocabulario = Ajustes.string(m, "vocabulario") ?? ""
        mandarParaSessao = Ajustes.bool(m, "mandarParaSessao", padrao: false)
        vozId = Ajustes.string(m, "voz")
        velocidade = Ajustes.double(m, "velocidade", padrao: Double(AVSpeechUtteranceDefaultSpeechRate))
        lerEntrega = Ajustes.bool(m, "lerEntrega", padrao: false)
    }

    // MARK: Ciclo do módulo

    func iniciar() {
        guard !ativo, !CaptureTool.ativo else { return }
        ativo = true
        aplicar()
    }

    /// Módulo desligado: solta microfone, voz, atalho e assinatura.
    func desligar() {
        ativo = false
        cancelarDitado()
        parar()
        aplicar()
        Arbitro.shared.retirar(VozGlobal.sinal)
    }

    /// Liga/desliga o que roda em segundo plano conforme os ajustes.
    private func aplicar() {
        guard ativo else {
            atalho.desligar()
            atalhoRecusado = false
            teclaFn.desligar()
            fnSemPermissao = false
            assinaturaSessoes = nil
            return
        }
        if atalhoLigado { atalho.ligar(combinacao) } else { atalho.desligar() }
        atalhoRecusado = atalhoLigado && atalho.recusado
        if teclaFnLigada { teclaFn.ligar() } else { teclaFn.desligar() }
        fnSemPermissao = teclaFnLigada && teclaFn.semPermissao
        if lerEntrega {
            guard assinaturaSessoes == nil else { return }
            entregasVistas = [:]
            primeiraLeitura = true
            assinouEm = Date()
            assinaturaSessoes = AppState.shared.$tasks
                .receive(on: DispatchQueue.main)
                .sink { [weak self] t in MainActor.assumeIsolated { self?.tarefasMudaram(t) } }
        } else {
            assinaturaSessoes = nil
        }
    }

    // MARK: Permissões

    /// Depois de liberar a Acessibilidade: tenta ligar a tecla Fn de novo.
    func tentarTeclaFn() { aplicar() }

    /// Relê o estado das permissões (não mostra pedido).
    func atualizarPermissoes() {
        guard !simulado else { return }
        let m = PermissaoVoz.microfone(), f = PermissaoVoz.fala()
        if m != microfone { microfone = m }
        if f != fala { fala = f }
    }

    /// Mostra os pedidos do macOS que faltam (microfone, depois reconhecimento de fala).
    /// Só chamar depois de explicar e com clique do Hugo.
    func pedirPermissoes() async {
        guard !simulado else { return }
        atualizarPermissoes()
        if microfone == .naoPerguntada { _ = await PermissaoVoz.pedirMicrofone() }
        atualizarPermissoes()
        if microfone == .concedida, fala == .naoPerguntada { _ = await PermissaoVoz.pedirFala() }
        atualizarPermissoes()
    }

    // MARK: Idiomas

    /// Idiomas que o reconhecedor conhece, com o nome em português.
    func idiomas() -> [(id: String, nome: String)] {
        let pt = Locale(identifier: "pt_BR")
        return SFSpeechRecognizer.supportedLocales()
            .map { l in
                let id = l.identifier.replacingOccurrences(of: "_", with: "-")
                return (id: id, nome: (pt.localizedString(forIdentifier: l.identifier) ?? id).capitalized(with: pt))
            }
            .sorted { $0.nome.localizedCaseInsensitiveCompare($1.nome) == .orderedAscending }
    }

    /// O Mac reconhece este idioma sozinho (sem rede)? nil = idioma desconhecido.
    func reconheceNoMac(_ idioma: String? = nil) -> Bool? {
        if simulado { return true }
        return SFSpeechRecognizer(locale: Locale(identifier: idioma ?? self.idioma))?.supportsOnDeviceRecognition
    }

    // MARK: Ditado

    /// Começa a ouvir. `dono` identifica quem pediu (só ele deve usar `texto`).
    /// Sem permissão ainda perguntada, só segue com `consentido: true` — a tela explica antes e
    /// chama de novo; aí o macOS mostra os pedidos. `aoTerminar` recebe o texto final (vazio =
    /// nada ouvido) ou nil se falhou (motivo em `estado`). Devolve false se não começou.
    @discardableResult
    func ditar(dono: String = "geral", consentido: Bool = false, aoTerminar: ((String?) -> Void)? = nil) -> Bool {
        guard !simulado, !ocupado else { return false }
        atualizarPermissoes()
        switch permissao {
        case .negada:
            let falta = microfone == .negada ? "o Microfone" : "o Reconhecimento de Fala"
            estado = .erro("O Crew está sem permissão para \(falta). Libere em Ajustes do Sistema › Privacidade e Segurança.")
            self.dono = dono
            return false
        case .naoPerguntada:
            guard consentido else { return false }
            self.dono = dono
            estado = .pedindoPermissao
            Task {
                await pedirPermissoes()
                // Parou/cancelou enquanto o pedido estava na tela: não começa a ouvir
                guard estado == .pedindoPermissao, self.dono == dono else { return }
                estado = .parado
                if permissao == .concedida {
                    if !comecar(dono, aoTerminar) { aoTerminar?(nil) }
                } else {
                    estado = .erro("Sem as duas permissões (Microfone e Reconhecimento de Fala) o ditado não funciona.")
                    aoTerminar?(nil)
                }
            }
            return true
        case .concedida:
            return comecar(dono, aoTerminar)
        }
    }

    /// Clique no microfone: começa, ou para se este dono já está ditando.
    func alternarDitado(dono: String = "geral", consentido: Bool = false) {
        if ocupado {
            if self.dono == dono { pararDitado() }
        } else {
            ditar(dono: dono, consentido: consentido)
        }
    }

    private func comecar(_ dono: String, _ aoTerminar: ((String?) -> Void)?) -> Bool {
        self.dono = dono
        textoParcial = ""
        textoFinal = ""
        nivel = 0
        guard let rec = SFSpeechRecognizer(locale: Locale(identifier: idioma)) else {
            estado = .erro("O macOS não tem reconhecimento de fala para \(idioma).")
            return false
        }
        let noMac = rec.supportsOnDeviceRecognition
        if !noMac && !permitirRede {
            estado = .erro("Este Mac não reconhece \(idioma) sem rede. Baixe o idioma em Ajustes do Sistema › Teclado › Ditado, ou ligue \"permitir reconhecimento pela Apple (rede)\" nos ajustes da Voz.")
            return false
        }
        guard rec.isAvailable else {
            estado = .erro(noMac ? "O reconhecimento de fala não está disponível agora."
                                 : "O reconhecimento pela Apple não está disponível agora (sem rede?).")
            return false
        }
        parar()   // não dita por cima da própria voz
        geracao += 1
        let g = geracao
        let c = CapturaVoz()
        do {
            try c.iniciar(reconhecedor: rec, noMac: noMac) { evento in
                DispatchQueue.main.async { MainActor.assumeIsolated { VozServico.shared.recebeu(evento, geracao: g) } }
            }
        } catch {
            c.cancelar()
            switch error {
            case CapturaVoz.Falha.semMicrofone: estado = .erro("Nenhum microfone disponível.")
            case CapturaVoz.Falha.motor(let m): estado = .erro("O microfone não abriu: \(m)")
            default: estado = .erro("O microfone não abriu.")
            }
            return false
        }
        captura = c
        reconhecedor = rec
        self.aoTerminar = aoTerminar
        estado = .ouvindo
        log.info("ditado: ouvindo (\(self.idioma, privacy: .public), \(noMac ? "no Mac" : "rede", privacy: .public))")
        return true
    }

    /// Para de ouvir; o texto final chega em instantes (`textoFinal`, `aoTerminar`).
    func pararDitado() {
        switch estado {
        case .pedindoPermissao:
            estado = .parado   // o pedido do macOS fica na tela, mas o ditado não começa depois
            let cb = aoTerminar
            aoTerminar = nil
            cb?(nil)
        case .ouvindo:
            estado = .finalizando
            nivel = 0
            captura?.encerrar()
            // Rede de segurança: se o reconhecedor não fechar, vale o que já foi entendido.
            // Um disparo só, cancelado quando o final chega.
            let g = geracao
            let item = DispatchWorkItem { [weak self] in
                guard let self, self.geracao == g, self.estado == .finalizando else { return }
                self.concluir(self.textoParcial)
            }
            limiteFinal = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: item)
        default:
            break
        }
    }

    /// Larga o ditado sem aproveitar o texto.
    func cancelarDitado() {
        guard ocupado else { return }
        soltarCaptura()
        textoParcial = ""
        estado = .parado
        let cb = aoTerminar
        aoTerminar = nil
        cb?(nil)
    }

    /// Tira o erro da tela.
    func limparErro() {
        if case .erro = estado { estado = .parado }
    }

    private func recebeu(_ evento: CapturaVoz.Evento, geracao g: Int) {
        guard g == geracao, captura != nil else { return }
        switch evento {
        case .nivel(let v):
            guard estado == .ouvindo else { return }
            let novo = max(v, nivel * 0.75)   // sobe na hora, desce suave
            if abs(novo - nivel) > 0.02 { nivel = novo }
        case .parcial(let t):
            if t != textoParcial { textoParcial = t }
        case .final(let t):
            concluir(t)
        case .erro(let motivo, let codigo):
            // Já tinha texto (ou já estava fechando): fica com o que foi entendido.
            if estado == .finalizando || !textoParcial.isEmpty {
                concluir(textoParcial)
            } else if codigo == 1110 || codigo == 203 {   // "nenhuma fala detectada"
                concluir("")
            } else {
                log.error("ditado: erro \(codigo) \(motivo, privacy: .public)")
                soltarCaptura()
                estado = .erro("O reconhecimento falhou: \(motivo)")
                let cb = aoTerminar
                aoTerminar = nil
                cb?(nil)
            }
        }
    }

    private func concluir(_ bruto: String) {
        soltarCaptura()
        textoFinal = bruto.trimmingCharacters(in: .whitespacesAndNewlines)
        textoParcial = ""
        estado = .parado
        let cb = aoTerminar
        aoTerminar = nil
        cb?(textoFinal)
    }

    /// Solta microfone, motor e reconhecedor: depois daqui não sobra nada rodando.
    private func soltarCaptura() {
        limiteFinal?.cancel()
        limiteFinal = nil
        captura?.cancelar()
        captura = nil
        reconhecedor = nil
        nivel = 0
    }

    // MARK: Ler em voz alta

    /// Vozes instaladas para português do Brasil (se não houver, as de português).
    func vozes() -> [VozInstalada] {
        let todas = AVSpeechSynthesisVoice.speechVoices()
        var pt = todas.filter { $0.language == "pt-BR" }
        if pt.isEmpty { pt = todas.filter { $0.language.hasPrefix("pt") } }
        // Voz Pessoal do Hugo (só aparece depois de permitida; pode não ser em português)
        pt += todas.filter { $0.voiceTraits.contains(.isPersonalVoice) && !pt.contains($0) }
        return pt.sorted { ($0.quality.rawValue, $1.name) > ($1.quality.rawValue, $0.name) }
            .map { v in
                let q = switch v.quality {
                case .premium: " (premium)"
                case .enhanced: " (aprimorada)"
                default: ""
                }
                return VozInstalada(id: v.identifier, nome: v.name + (v.voiceTraits.contains(.isPersonalVoice) ? " (Voz Pessoal)" : q))
            }
    }

    /// Lê o texto em voz alta (sem o markdown). Interrompe o que estiver sendo lido.
    func falar(_ texto: String) {
        enfileirar(TextoFalavel.limpar(texto), original: texto, interromper: true)
    }

    /// Fala sem interromper o que está sendo dito (avisos). `noMac`: direto na voz do macOS,
    /// sem passar pela voz humanizada.
    func anunciar(_ texto: String, noMac: Bool = false) {
        enfileirar(TextoFalavel.limpar(texto), original: texto, interromper: false, noMac: noMac)
    }

    /// Para a leitura e solta o sintetizador.
    func parar() {
        FalaServico.shared.calar()
        naFila = [:]
        sintetizador?.stopSpeaking(at: .immediate)
        sintetizador = nil
        ouvinteFala = nil
        if falandoTexto != nil { falandoTexto = nil }
    }

    /// Para tudo: ditado e leitura.
    func pararTudo() {
        if estado == .ouvindo { pararDitado() } else { cancelarDitado() }
        parar()
    }

    private func enfileirar(_ limpo: String, original: String, interromper: Bool, noMac: Bool = false) {
        guard !simulado, !limpo.isEmpty else { return }
        // Com o microfone aberto, a voz entraria no ditado
        guard !ocupado else { return }
        if interromper { parar() }
        // Voz do computador: com a voz humanizada escolhida, é ela quem fala (Fala/FalaServico.swift)
        if !noMac, FalaServico.shared.assumir(limpo, interromper: interromper) { return }
        let s = sintetizador ?? AVSpeechSynthesizer()
        if sintetizador == nil {
            let o = OuvinteFala()
            s.delegate = o
            ouvinteFala = o
            sintetizador = s
        }
        let u = AVSpeechUtterance(string: limpo)
        u.voice = vozId.flatMap(AVSpeechSynthesisVoice.init(identifier:)) ?? AVSpeechSynthesisVoice(language: "pt-BR")
        u.rate = Float(min(max(velocidade, Self.velocidades.lowerBound), Self.velocidades.upperBound))
        naFila[ObjectIdentifier(u)] = original
        if falandoTexto == nil { falandoTexto = original }
        s.speak(u)
    }

    fileprivate func falaComecou(_ id: ObjectIdentifier) {
        if let t = naFila[id], falandoTexto != t { falandoTexto = t }
    }

    fileprivate func falaAcabou(_ id: ObjectIdentifier) {
        guard naFila.removeValue(forKey: id) != nil else { return }
        if naFila.isEmpty { parar() }
    }

    // MARK: Ler a entrega quando a sessão termina

    private func tarefasMudaram(_ tarefas: [AgentTask]) {
        for t in tarefas where t.source == .claudeCode {
            guard let sid = t.sessionId else { continue }
            let antes = entregasVistas[sid]
            let agora = t.delivery ?? ""
            entregasVistas[sid] = agora
            guard !primeiraLeitura, lerEntrega, agora != antes, !agora.isEmpty else { continue }
            // Sessão restaurada ao abrir o Crew: a entrega dela é antiga
            if antes == nil && t.lastEvent < assinouEm { continue }
            // Só a entrega de quem terminou (erro e limite de uso têm aviso próprio)
            guard t.state == .finished else { continue }
            let paragrafo = TextoFalavel.primeiroParagrafo(agora)
            // Duas sessões terminando juntas: a segunda espera a primeira acabar de falar
            enfileirar(paragrafo, original: agora, interromper: false)
        }
        primeiraLeitura = false
    }

    // MARK: Capturas

    /// Só para o modo de capturas: permissões dadas e um ditado em curso, sem tocar no microfone.
    func exemploParaCaptura() {
        simulado = true
        microfone = .concedida
        fala = .concedida
        dono = "captura"
        textoParcial = "Roda os testes do módulo de voz e me avisa se algum falhar"
        textoFinal = ""
        nivel = 0.62
        estado = .ouvindo
    }
}

/// Recebe os avisos do sintetizador (podem chegar fora da main) e repassa só o identificador.
private final class OuvinteFala: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didStart u: AVSpeechUtterance) {
        let id = ObjectIdentifier(u)
        DispatchQueue.main.async { MainActor.assumeIsolated { VozServico.shared.falaComecou(id) } }
    }

    func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        let id = ObjectIdentifier(u)
        DispatchQueue.main.async { MainActor.assumeIsolated { VozServico.shared.falaAcabou(id) } }
    }

    func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) {
        let id = ObjectIdentifier(u)
        DispatchQueue.main.async { MainActor.assumeIsolated { VozServico.shared.falaAcabou(id) } }
    }
}
