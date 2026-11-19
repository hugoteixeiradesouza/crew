import AppKit
import CoreAudio
import Observation
import SwiftUI

// Volume e mudo por app — fase 2 do Áudio (docs/ARQUITETURA.md §5).
//
// Sob demanda: só existe tap para app cujo volume/mudo o Hugo mexeu e que está tocando (ou já
// tinha tap). Volume 100 % e sem mudo = o tap sai e o app volta ao som normal do macOS. Nenhum
// app ajustado = nenhum tap, nenhum timer: só os avisos do Core Audio (lista de processos, quem
// começou/parou de tocar, saída padrão), que não custam nada parados.
//
// Os ajustes ficam por bundle id (`modulo.audio.porApp`) e voltam sozinhos quando o app toca de
// novo. Apps de chamada são ignorados por padrão (o tap quebra o cancelamento de eco deles).

@Observable @MainActor
final class VolumePorApp {
    static let shared = VolumePorApp()

    enum EstadoTap: Equatable {
        /// Ajustado, mas o app não está tocando: o tap sobe quando ele tocar.
        case esperando
        case montando
        case ativo
        case falhou(String)
        case ignorado
        case semPermissao
    }

    /// Apps com cliente de áudio aberto (agrupados no app dono), tocando primeiro.
    private(set) var apps: [AppAudio] = []
    /// Só os não neutros (volume ≠ 100 % ou mudo).
    private(set) var ajustes: [String: AjusteApp] = [:]
    private(set) var estados: [String: EstadoTap] = [:]
    private(set) var permissao: PermissaoCaptura = .desconhecida
    private(set) var ultimoMexido: String?
    /// Apps com saída fixa que está desconectada: tocando na padrão até ela voltar.
    private(set) var naReserva: Set<String> = []

    var ignorados: [String] {
        didSet {
            Gravar.padrao.set(ignorados, forKey: Ajustes.chave("audio", "ignorados"))
            reconciliar()
        }
    }
    var atalhosLigados: Bool {
        didSet {
            Ajustes.definir("audio", "atalhos", atalhosLigados)
            aplicarAtalhos()
        }
    }
    /// Combinações que o macOS recusou (outro app já usa).
    private(set) var atalhosRecusados: [AtalhosVolume.Acao] = []

    var tocando: [AppAudio] { apps.filter(\.tocando) }
    func ajuste(_ bundle: String) -> AjusteApp { ajustes[bundle] ?? AjusteApp() }
    func ignorado(_ bundle: String) -> Bool { ignorados.contains(bundle) }
    var temTapAtivo: Bool { estados.values.contains(.ativo) }

    @ObservationIgnored private let log = Log.de("audio")
    @ObservationIgnored private var ativo = false
    @ObservationIgnored private var parametros: [String: ParametrosTap] = [:]
    /// O que foi pedido ao motor por app (processos + saída), para não pedir de novo à toa.
    @ObservationIgnored private var montados: [String: String] = [:]
    @ObservationIgnored private var ouvintesSistema: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    @ObservationIgnored private var ouvintesProcesso: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    @ObservationIgnored private var donos: [pid_t: (bundle: String, nome: String, pid: pid_t)?] = [:]
    @ObservationIgnored private var icones: [String: NSImage] = [:]
    @ObservationIgnored private var relerPendente: DispatchWorkItem?
    @ObservationIgnored private var monitor: Timer?
    @ObservationIgnored private var ciclosVistos: [String: (ciclos: UInt64, parado: Int)] = [:]
    @ObservationIgnored private var recriacoes: [String: [Date]] = [:]
    @ObservationIgnored private var pedindoPermissao = false
    @ObservationIgnored private var observadorSaida: NSObjectProtocol?
    @ObservationIgnored private lazy var atalhos = AtalhosVolume { [weak self] a in self?.atalho(a) }
    @ObservationIgnored private let meuPid = ProcessInfo.processInfo.processIdentifier
    /// Último nome visto de cada saída (para avisar "AirPods desconectou" depois que ela sumiu).
    @ObservationIgnored private var nomesSaida: [String: String] = [:]
    @ObservationIgnored private var dispositivosPendente: DispatchWorkItem?

    private init() {
        ignorados = UserDefaults.standard.stringArray(forKey: Ajustes.chave("audio", "ignorados")) ?? IgnoradosPadrao.bundles
        atalhosLigados = Ajustes.bool("audio", "atalhos", padrao: false)
        // Modo de capturas: lê o mesmo UserDefaults do Crew de verdade, mas não pode criar tap.
        if CaptureTool.ativo { return }
        if let salvo = UserDefaults.standard.dictionary(forKey: Ajustes.chave("audio", "porApp")) {
            for (bundle, v) in salvo {
                guard let d = v as? [String: Any] else { continue }
                let a = AjusteApp(volume: d["v"] as? Double ?? 1, mudo: d["m"] as? Bool ?? false, saidaUID: d["s"] as? String)
                if !a.neutro { ajustes[bundle] = a }
            }
        }
    }

    // MARK: Ciclo

    func iniciar() {
        guard !ativo, !CaptureTool.ativo else { return }
        ativo = true
        // O que sobrou de uma execução anterior (Crew que caiu) sai antes de qualquer coisa.
        MotorTaps.shared.limparOrfaos()
        permissao = PermissaoCaptura.atual()
        ouvir(kAudioHardwarePropertyProcessObjectList) { [weak self] in self?.agendarReler() }
        ouvir(kAudioHardwarePropertyDefaultOutputDevice) { [weak self] in self?.saidaMudou() }
        // Fone conectou/desconectou: app com saída fixa vai para a padrão e volta. Um instante de
        // espera, porque o Bluetooth anuncia o dispositivo antes de ele aceitar fluxo.
        ouvir(kAudioHardwarePropertyDevices) { [weak self] in self?.agendarDispositivos() }
        observadorSaida = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                                                 object: nil, queue: nil) { _ in
            MotorTaps.shared.removerTodosAgora()
        }
        relerProcessos()
        aplicarAtalhos()
        log.info("volume por app: \(self.ajustes.count) app(s) com ajuste salvo; permissão \(String(describing: self.permissao), privacy: .public)")
    }

    func parar() {
        guard ativo else { return }
        ativo = false
        relerPendente?.cancel()
        monitor?.invalidate(); monitor = nil
        atalhos.desligar()
        for (endereco, bloco) in ouvintesSistema {
            var a = endereco
            AudioObjectRemovePropertyListenerBlock(CoreAudioHW.sistema, &a, .main, bloco)
        }
        ouvintesSistema.removeAll()
        for (obj, bloco) in ouvintesProcesso {
            var a = CoreAudioHW.endereco(kAudioProcessPropertyIsRunningOutput)
            AudioObjectRemovePropertyListenerBlock(obj, &a, .main, bloco)
        }
        ouvintesProcesso.removeAll()
        if let o = observadorSaida { NotificationCenter.default.removeObserver(o) }
        observadorSaida = nil
        MotorTaps.shared.removerTodosAgora()
        montados.removeAll()
        estados.removeAll()
    }

    private func ouvir(_ sel: AudioObjectPropertySelector, _ acao: @escaping @MainActor @Sendable () -> Void) {
        var a = CoreAudioHW.endereco(sel)
        let bloco = Self.bloco(acao)
        if AudioObjectAddPropertyListenerBlock(CoreAudioHW.sistema, &a, .main, bloco) == noErr {
            ouvintesSistema.append((a, bloco))
        }
    }

    /// O Core Audio chama na fila principal (`.main` no registro).
    private nonisolated static func bloco(_ acao: @escaping @MainActor @Sendable () -> Void) -> AudioObjectPropertyListenerBlock {
        { _, _ in MainActor.assumeIsolated { acao() } }
    }

    // MARK: Ações (UI e atalhos)

    func definirVolume(_ bundle: String, _ volume: Double, hud: Bool = true) {
        var a = ajuste(bundle)
        a.volume = min(max(volume, 0), AjusteApp.maximo)
        if a.volume > 0.004 && a.mudo && volume > ajuste(bundle).volume { a.mudo = false }
        aplicar(bundle, a, hud: hud)
    }

    func alternarMudo(_ bundle: String, hud: Bool = true) {
        var a = ajuste(bundle)
        a.mudo.toggle()
        aplicar(bundle, a, hud: hud)
    }

    /// Volta ao normal: 100 %, sem mudo, sem tap.
    func restaurar(_ bundle: String) { aplicar(bundle, AjusteApp(), hud: false) }

    /// Saída fixa do app (UID) ou nil para seguir a padrão.
    func definirSaida(_ bundle: String, _ uid: String?) {
        var a = ajuste(bundle)
        a.saidaUID = uid
        aplicar(bundle, a, hud: false)
    }

    func ignorar(_ bundle: String, _ sim: Bool) {
        if sim { if !ignorados.contains(bundle) { ignorados.append(bundle) } }
        else { ignorados.removeAll { $0 == bundle } }
    }

    private func aplicar(_ bundle: String, _ a: AjusteApp, hud: Bool) {
        ultimoMexido = bundle
        if case .falhou = estados[bundle] { estados[bundle] = nil }
        if a.neutro { ajustes[bundle] = nil } else { ajustes[bundle] = a }
        parametros[bundle]?.alvo = a.ganho
        salvar()
        if !a.neutro && permissao == .naoPerguntada && !ignorado(bundle) {
            pedirPermissao()
        }
        reconciliar()
        if hud { mostrarHUD(bundle, a) }
    }

    private func salvar() {
        var d: [String: Any] = [:]
        for (b, a) in ajustes {
            var x: [String: Any] = ["v": a.volume, "m": a.mudo]
            if let s = a.saidaUID { x["s"] = s }
            d[b] = x
        }
        Ajustes.definir("audio", "porApp", d)
    }

    func pedirPermissao() {
        guard !pedindoPermissao else { return }
        pedindoPermissao = true
        PermissaoCaptura.pedir { [weak self] p in
            guard let self else { return }
            self.pedindoPermissao = false
            self.permissao = p
            self.log.info("permissão de captura de áudio: \(String(describing: p), privacy: .public)")
            self.reconciliar()
        }
    }

    func reverPermissao() {
        let antes = permissao
        permissao = PermissaoCaptura.atual()
        if permissao != antes { reconciliar() }
    }

    // MARK: Processos

    private func agendarReler() {
        relerPendente?.cancel()
        let item = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.relerProcessos() } }
        relerPendente = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: item)
    }

    private func relerProcessos() {
        guard ativo else { return }
        let lista = CoreAudioProcessos.lista().filter { $0.pid != meuPid }
        // Avisos de "começou/parou de tocar" por processo
        let objetos = Set(lista.map(\.objeto))
        for (obj, bloco) in ouvintesProcesso where !objetos.contains(obj) {
            var a = CoreAudioHW.endereco(kAudioProcessPropertyIsRunningOutput)
            AudioObjectRemovePropertyListenerBlock(obj, &a, .main, bloco)
            ouvintesProcesso[obj] = nil
        }
        for obj in objetos where ouvintesProcesso[obj] == nil {
            var a = CoreAudioHW.endereco(kAudioProcessPropertyIsRunningOutput)
            let bloco = Self.bloco { [weak self] in self?.agendarReler() }
            if AudioObjectAddPropertyListenerBlock(obj, &a, .main, bloco) == noErr { ouvintesProcesso[obj] = bloco }
        }
        // Agrupa no app dono
        let pids = Set(lista.map(\.pid))
        donos = donos.filter { pids.contains($0.key) }
        var grupos: [String: (nome: String, pid: pid_t, objs: [AudioObjectID], tocando: Bool)] = [:]
        for p in lista {
            if donos[p.pid] == nil {
                donos[p.pid] = CoreAudioProcessos.donoDe(pid: p.pid, bundle: p.bundle).map {
                    ($0.bundleIdentifier ?? p.bundle, $0.localizedName ?? p.bundle, $0.processIdentifier)
                }
            }
            guard let dono = donos[p.pid] ?? nil, dono.pid != meuPid else { continue }
            var g = grupos[dono.bundle] ?? (dono.nome, dono.pid, [], false)
            g.objs.append(p.objeto)
            g.tocando = g.tocando || p.tocando
            grupos[dono.bundle] = g
        }
        let novos = grupos.map { AppAudio(id: $0.key, nome: $0.value.nome, pid: $0.value.pid,
                                          processos: $0.value.objs.sorted(), tocando: $0.value.tocando) }
            .sorted { ($0.tocando ? 0 : 1, $0.nome.localizedLowercase) < ($1.tocando ? 0 : 1, $1.nome.localizedLowercase) }
        if novos != apps { apps = novos }
        reconciliar()
    }

    // MARK: Taps

    /// Decide, app a app, se o tap deve existir — e pede ao motor montar/remontar/desmontar.
    private func reconciliar() {
        guard ativo else { return }
        let saida = saidaAtual()
        let presentes = ajustes.values.contains { $0.saidaUID != nil }
            ? CoreAudioHW.dispositivos().filter(\.temSaida) : []
        for d in presentes { nomesSaida[d.uid] = d.nome }
        if let saida { nomesSaida[saida.uid] = saida.nome }
        var queridos: Set<String> = []
        var reserva: Set<String> = []
        for (bundle, a) in ajustes where !a.neutro {
            guard let app = apps.first(where: { $0.id == bundle }) else { estados[bundle] = .esperando; continue }
            if ignorado(bundle) { estados[bundle] = .ignorado; continue }
            if permissao == .negada { estados[bundle] = .semPermissao; continue }
            if permissao == .naoPerguntada || pedindoPermissao {
                estados[bundle] = .esperando
                // Ajuste salvo e o app tocando: é a hora de o macOS perguntar (uma vez).
                if app.tocando && !pedindoPermissao { pedirPermissao() }
                continue
            }
            // Falhou: não insiste sozinho (tenta de novo quando o Hugo mexer ou a saída mudar).
            if case .falhou = estados[bundle], montados[bundle] == nil { continue }
            // Sob demanda: sobe quando o app toca; depois fica enquanto o app tiver áudio aberto.
            guard app.tocando || montados[bundle] != nil else { estados[bundle] = .esperando; continue }
            let escolha = EscolhaSaida.efetiva(fixa: a.saidaUID, presentes: presentes.map(\.uid), padrao: saida?.uid)
            guard let uid = escolha.uid, let destino = escolha.reserva || a.saidaUID == nil
                    ? saida : presentes.first(where: { $0.uid == uid }) else {
                estados[bundle] = .falhou("sem saída de som"); continue
            }
            if escolha.reserva { reserva.insert(bundle) }
            let deriva = EscolhaSaida.deriva(saidaUID: destino.uid, padraoUID: saida?.uid,
                                             bluetooth: destino.transporte == .bluetooth)
            queridos.insert(bundle)
            let assinatura = "\(app.processos)|\(destino.uid)|\(deriva)"
            guard montados[bundle] != assinatura else { continue }
            montados[bundle] = assinatura
            let par = parametros[bundle] ?? ParametrosTap(ganho: a.ganho)
            par.alvo = a.ganho
            parametros[bundle] = par
            if estados[bundle] != .ativo { estados[bundle] = .montando }
            MotorTaps.shared.garantir(chave: bundle, processos: app.processos, saida: destino, deriva: deriva,
                                      parametros: par) { [weak self] r in
                guard let self, self.montados[bundle] == assinatura else { return }
                switch r {
                case .ok: self.estados[bundle] = .ativo
                case .falhou(let m):
                    self.estados[bundle] = .falhou(m)
                    self.montados[bundle] = nil
                }
                self.ajustarMonitor()
            }
        }
        for bundle in montados.keys where !queridos.contains(bundle) {
            montados[bundle] = nil
            MotorTaps.shared.remover(bundle)
            ciclosVistos[bundle] = nil
        }
        avisarReserva(reserva, montando: queridos)
        for bundle in estados.keys where ajustes[bundle] == nil { estados[bundle] = nil }
        for bundle in parametros.keys where ajustes[bundle] == nil && montados[bundle] == nil { parametros[bundle] = nil }
        ajustarMonitor()
    }

    private func saidaAtual() -> DispositivoAudio? {
        let id = CoreAudioHW.padrao(.saida)
        return id == 0 ? nil : CoreAudioHW.ler(id)
    }

    /// Saída padrão mudou: remonta os taps na saída nova (o aggregate é preso a uma saída).
    private func saidaMudou() {
        for (b, e) in estados { if case .falhou = e { estados[b] = nil } }
        if !montados.isEmpty { log.info("saída mudou: remontando \(self.montados.count) tap(s)") }
        reconciliar()
    }

    private func agendarDispositivos() {
        dispositivosPendente?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                for (b, e) in self.estados { if case .falhou = e { self.estados[b] = nil } }
                self.reconciliar()
            }
        }
        dispositivosPendente = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: item)
    }

    /// Aviso na ilha quando um app com saída fixa cai para a padrão (desconectou) ou volta.
    private func avisarReserva(_ agora: Set<String>, montando: Set<String>) {
        guard agora != naReserva else { return }
        let padrao = saidaAtual().map { ColunaDispositivos.nomeCurto($0.nome) } ?? "saída padrão"
        for b in agora.subtracting(naReserva) {
            let fixa = ajustes[b]?.saidaUID.flatMap { nomesSaida[$0] }.map(ColunaDispositivos.nomeCurto) ?? "A saída"
            log.notice("saída de \(b, privacy: .public) desconectada: na padrão (\(padrao, privacy: .public))")
            publicarAviso(b, "\(nome(b)) → \(padrao) (\(fixa) desconectou)", cor: "#F5A524")
        }
        for b in naReserva.subtracting(agora) where ajustes[b]?.saidaUID != nil && montando.contains(b) {
            let fixa = ajustes[b]?.saidaUID.flatMap { nomesSaida[$0] }.map(ColunaDispositivos.nomeCurto) ?? "a saída dele"
            log.notice("saída de \(b, privacy: .public) voltou: \(fixa, privacy: .public)")
            publicarAviso(b, "\(nome(b)) → \(fixa) de novo", cor: "#34D399")
        }
        naReserva = agora
    }

    private func publicarAviso(_ bundle: String, _ texto: String, cor: String) {
        Arbitro.shared.publicar(Sinal(id: "audio.app.saida", lugar: .barra, prioridade: .alerta, duracao: 4,
                                      conteudo: AnyView(AvisoSaidaApp(icone: icone(bundle), texto: texto, cor: Color(hex: cor)))))
    }

    // MARK: Monitor de saúde (só com tap de pé)

    private func ajustarMonitor() {
        let precisa = !montados.isEmpty
        if precisa && monitor == nil {
            let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.verificarSaude() }
            }
            t.tolerance = 0.5
            RunLoop.main.add(t, forMode: .common)
            monitor = t
        } else if !precisa, let m = monitor {
            m.invalidate()
            monitor = nil
            ciclosVistos.removeAll()
        }
    }

    /// O callback parou (saída sumiu, o macOS reiniciou o áudio…)? Remonta. Três vezes em um
    /// minuto sem voltar: desiste e desmonta — o app fica com o som normal, nunca mudo.
    private func verificarSaude() {
        if permissao != .concedida {
            reverPermissao()
            if permissao == .negada { return }
        }
        for (bundle, _) in montados where estados[bundle] == .ativo {
            guard let par = parametros[bundle] else { continue }
            let c = par.ciclos.load(ordering: .relaxed)
            var visto = ciclosVistos[bundle] ?? (c, 0)
            visto.parado = c == visto.ciclos ? visto.parado + 1 : 0
            visto.ciclos = c
            ciclosVistos[bundle] = visto
            guard visto.parado >= 2 else { continue }
            ciclosVistos[bundle] = nil
            var vezes = (recriacoes[bundle] ?? []).filter { Date.now.timeIntervalSince($0) < 60 }
            vezes.append(.now)
            recriacoes[bundle] = vezes
            montados[bundle] = nil
            if vezes.count > 3 {
                log.error("tap de \(bundle, privacy: .public) parou 3× em 1 min: desisto (app com som normal)")
                MotorTaps.shared.remover(bundle)
                estados[bundle] = .falhou("o áudio parou de responder; o app ficou com o som normal")
                continue
            }
            log.notice("tap de \(bundle, privacy: .public) parou de rodar: remontando")
            estados[bundle] = .montando
            reconciliarForcando(bundle)
        }
    }

    /// Remonta do zero: tira o tap atual e deixa o `reconciliar` montar de novo (mesmo destino).
    private func reconciliarForcando(_ bundle: String) {
        MotorTaps.shared.remover(bundle)
        montados[bundle] = nil
        if let app = apps.first(where: { $0.id == bundle }), !app.tocando {
            // Já tinha tap: o reconciliar só remonta tocando; aqui remonta de qualquer jeito.
            montados[bundle] = "forcar"
        }
        reconciliar()
    }

    // MARK: Atalhos

    private func aplicarAtalhos() {
        guard ativo else { return }
        if atalhosLigados { atalhos.ligar() } else { atalhos.desligar() }
        atalhosRecusados = atalhosLigados ? atalhos.recusadas : []
    }

    /// O app que os atalhos controlam agora.
    var alvoAtalho: String? {
        AlvoAtalho.escolher(tocando: tocando.map(\.id).filter { !ignorado($0) },
                            abertos: Set(apps.map(\.id)),
                            frente: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                            ultimoMexido: ultimoMexido.flatMap { ignorado($0) ? nil : $0 })
    }

    private func atalho(_ acao: AtalhosVolume.Acao) {
        guard let alvo = alvoAtalho else {
            Arbitro.shared.publicar(Sinal(id: "audio.app", lugar: .barra, prioridade: .hud, duracao: 1.4,
                                          conteudo: AnyView(AvisoAudio(icone: "speaker.slash", texto: "Nenhum app tocando agora",
                                                                       cor: Color(hex: "#8E939C")))))
            return
        }
        switch acao {
        case .subir: definirVolume(alvo, EscalaVolume.passo(ajuste(alvo).volume, subir: true))
        case .descer: definirVolume(alvo, EscalaVolume.passo(ajuste(alvo).volume, subir: false))
        case .mudo: alternarMudo(alvo)
        }
    }

    // MARK: HUD na ilha fechada

    private func mostrarHUD(_ bundle: String, _ a: AjusteApp) {
        let valor = a.mudo ? 0 : a.volume
        Arbitro.shared.publicar(Sinal(id: "audio.app", lugar: .barra, prioridade: .hud,
                                      homie: .fones(min(1, valor)), duracao: 1.6,
                                      conteudo: AnyView(HUDVolumeApp(icone: icone(bundle), nome: nome(bundle),
                                                                     volume: a.volume, mudo: a.mudo))))
    }

    // MARK: Nome e ícone

    func icone(_ bundle: String) -> NSImage {
        if let i = icones[bundle] { return i }
        let i: NSImage
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
            i = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            i = NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage()
        }
        icones[bundle] = i
        return i
    }

    func nome(_ bundle: String) -> String {
        if let a = apps.first(where: { $0.id == bundle }) { return a.nome }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return IgnoradosPadrao.nomes[bundle] ?? bundle
    }

    // MARK: Capturas

    /// Só para o modo de capturas: apps de exemplo, sem tocar no Core Audio.
    func exemploParaCaptura() {
        apps = [
            AppAudio(id: "com.spotify.client", nome: "Spotify", pid: 1, processos: [1], tocando: true),
            AppAudio(id: "com.google.Chrome", nome: "Google Chrome", pid: 2, processos: [2], tocando: true),
            AppAudio(id: "com.apple.Safari", nome: "Safari", pid: 3, processos: [3], tocando: true),
            AppAudio(id: "com.hnc.Discord", nome: "Discord", pid: 4, processos: [4], tocando: false),
        ]
        ajustes = ["com.google.Chrome": AjusteApp(volume: 0.45, saidaUID: CoreAudioHW.ler(CoreAudioHW.padrao(.saida))?.uid),
                   "com.apple.Safari": AjusteApp(volume: 1, mudo: true, saidaUID: "fone-desconectado"),
                   "com.hnc.Discord": AjusteApp(volume: 1.8)]
        naReserva = ["com.apple.Safari"]
        estados = ["com.google.Chrome": .ativo, "com.apple.Safari": .ativo, "com.hnc.Discord": .esperando]
        permissao = .concedida
    }
}
