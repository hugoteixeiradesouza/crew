import SwiftUI
import AppKit
import CoreAudio
import AudioToolbox
import CoreGraphics

/// Brilho da tela e volume do som: o sistema avisa quando mudam (tecla, Central de Controle,
/// outro app) e a ilha mostra o nível por um instante, com o Homie reagindo.
/// Sem consulta periódica: parado, não gasta nada.
@MainActor
final class NivelService: ObservableObject {
    static let shared = NivelService()

    enum Tipo { case brilho, volume }
    struct Nivel: Equatable {
        var tipo: Tipo
        var valor: Double      // 0…1
        var mudo = false
    }

    /// Nível sendo mostrado agora; nil = nada na tela.
    @Published private(set) var atual: Nivel?

    private var some: DispatchWorkItem?
    private var inicio = Date()
    private var dispositivo: AudioObjectID = 0
    private var ultimoVolume: Double?
    private var ultimoBrilho: Double?

    private init() {}

    /// Segunda via para saber que o Hugo apertou brilho: observa as teclas de sistema mesmo
    /// se a captura estiver caída.
    private var observadorTeclas: Any?

    func start() {
        inicio = Date()
        observadorTeclas = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) { e in
            guard e.subtype.rawValue == 8 else { return }
            let codigo = (e.data1 & 0xFFFF0000) >> 16
            guard codigo == 2 || codigo == 3 else { return }
            Task { @MainActor in NivelService.shared.marcarBrilhoManual() }
        }
        iniciarVolume()
        iniciarBrilho()
        atualizarTeclas()
    }

    private func mostrar(_ n: Nivel) {
        // Valores lidos ao abrir o app não contam como mudança
        guard Date().timeIntervalSince(inicio) > 1.5 else { return }
        let s = AppState.shared
        guard n.tipo == .brilho ? s.moduloBrilho : s.moduloVolume else { return }
        atual = n
        Arbitro.shared.publicar(Sinal(id: "nivel", lugar: .barra, prioridade: .hud,
                                      homie: n.tipo == .brilho ? .celular(n.mudo ? 0 : n.valor) : .fones(n.mudo ? 0 : n.valor),
                                      duracao: 1.6, conteudo: AnyView(NivelBarra(nivel: n, compacta: false))))
        some?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.atual = nil }
        some = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: item)
    }

    // MARK: Volume (CoreAudio)

    private static func endereco(_ sel: AudioObjectPropertySelector,
                                 _ escopo: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: sel, mScope: escopo, mElement: kAudioObjectPropertyElementMain)
    }

    private func iniciarVolume() {
        var addr = Self.endereco(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main) { _, _ in
            MainActor.assumeIsolated { NivelService.shared.trocarDispositivo() }
        }
        trocarDispositivo()
    }

    private func trocarDispositivo() {
        var id = AudioObjectID(0)
        var tam = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = Self.endereco(kAudioHardwarePropertyDefaultOutputDevice)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &tam, &id) == noErr,
              id != 0, id != dispositivo else { return }
        dispositivo = id
        ultimoVolume = lerVolume()
        for sel in [kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyMute] {
            var a = Self.endereco(sel, kAudioDevicePropertyScopeOutput)
            AudioObjectAddPropertyListenerBlock(id, &a, .main) { _, _ in
                MainActor.assumeIsolated { NivelService.shared.volumeMudou(id) }
            }
        }
    }

    private func lerVolume() -> Double? {
        var v = Float32(0)
        var tam = UInt32(MemoryLayout<Float32>.size)
        var a = Self.endereco(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeOutput)
        guard AudioObjectGetPropertyData(dispositivo, &a, 0, nil, &tam, &v) == noErr else { return nil }
        return Double(v)
    }

    private func lerMudo() -> Bool {
        var m = UInt32(0)
        var tam = UInt32(MemoryLayout<UInt32>.size)
        var a = Self.endereco(kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput)
        guard AudioObjectGetPropertyData(dispositivo, &a, 0, nil, &tam, &m) == noErr else { return false }
        return m != 0
    }

    private func volumeMudou(_ id: AudioObjectID) {
        guard id == dispositivo, let v = lerVolume() else { return }
        ultimoVolume = v
        mostrar(Nivel(tipo: .volume, valor: v, mudo: lerMudo()))
    }

    // MARK: Brilho (DisplayServices, o mesmo que a tecla de brilho usa)

    private typealias LerBrilho = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias GravarBrilho = @convention(c) (UInt32, Float) -> Int32
    private var gravarBrilhoFn: GravarBrilho?
    private typealias AvisoBrilho = @convention(c) (UnsafeMutableRawPointer?, UInt32, UnsafeMutableRawPointer?) -> Void
    private typealias Registrar = @convention(c) (UInt32, UnsafeMutableRawPointer?, AvisoBrilho) -> Int32
    private var lerBrilhoFn: LerBrilho?

    private func iniciarBrilho() {
        guard let h = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW),
              let ler = dlsym(h, "DisplayServicesGetBrightness"),
              let reg = dlsym(h, "DisplayServicesRegisterForBrightnessChangeNotifications") else {
            NSLog("Crew — brilho: DisplayServices indisponível")
            return
        }
        lerBrilhoFn = unsafeBitCast(ler, to: LerBrilho.self)
        if let g = dlsym(h, "DisplayServicesSetBrightness") { gravarBrilhoFn = unsafeBitCast(g, to: GravarBrilho.self) }
        let registrar = unsafeBitCast(reg, to: Registrar.self)
        // Tela embutida (a do notch); monitor externo comum não informa brilho.
        // Procura entre as telas ligadas, não só as visíveis: espelhando na TV o macOS só
        // mostra a TV, e a tela do Mac continua lá
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var n: UInt32 = 0
        CGGetOnlineDisplayList(16, &ids, &n)
        let tela = ids.prefix(Int(n)).first { CGDisplayIsBuiltin($0) != 0 } ?? CGMainDisplayID()
        ultimoBrilho = lerBrilho(tela)
        _ = registrar(tela, nil) { _, _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { NivelService.shared.brilhoMudou() }
            }
        }
        telaBrilho = tela
    }
    private var telaBrilho: UInt32 = 0

    private func lerBrilho(_ tela: UInt32) -> Double? {
        var v = Float(0)
        guard let f = lerBrilhoFn, f(tela, &v) == 0 else { return nil }
        return Double(v)
    }

    /// Última vez que o Hugo mexeu no brilho com a mão: tecla capturada ou mouse arrastando
    /// (slider da Central de Controle).
    private var ultimoBrilhoManual = Date.distantPast
    func marcarBrilhoManual() { ultimoBrilhoManual = Date() }

    private func brilhoMudou() {
        guard let v = lerBrilho(telaBrilho) else { return }
        // O aviso chega várias vezes durante a transição: só mostra se mudou de fato
        if let u = ultimoBrilho, abs(u - v) < 0.002 { return }
        ultimoBrilho = v
        if NSEvent.pressedMouseButtons != 0 { ultimoBrilhoManual = Date() }
        // O macOS não diz quem mudou o brilho. Regra fixa (pedido do Hugo: brilho automático
        // NUNCA aparece): só mostra com prova de que foi ele — tecla de brilho (pela captura ou
        // pelo observador de teclas de sistema) ou mouse arrastando o controle — no último 1,5 s.
        // Sem prova é automático (sensor de luz, tela escurecendo parada): não aparece, esteja
        // a captura ligada ou não (antes, captura caída = mostrava tudo).
        guard Date().timeIntervalSince(ultimoBrilhoManual) <= 1.5 else { return }
        mostrar(Nivel(tipo: .brilho, valor: v))
    }


    // MARK: Teclas de brilho/volume — o Crew aplica a mudança e só o aviso dele aparece

    private var tap: CFMachPort?
    /// Sem permissão de Acessibilidade o macOS não entrega as teclas: o aviso dele continua.
    @Published private(set) var semPermissaoTeclas = false

    /// Liga ou desliga a captura das teclas conforme os Ajustes.
    func atualizarTeclas() {
        let s = AppState.shared
        let quer = s.moduloAvisoProprio && (s.moduloBrilho || s.moduloVolume)
        if let tap { CGEvent.tapEnable(tap: tap, enable: quer); return }
        guard quer else { return }
        let mascara = CGEventMask(1 << 14)   // NX_SYSDEFINED: teclas de mídia, brilho e volume
        let aviso: CGEventTapCallBack = { _, tipo, evento, _ in
            if tipo == .tapDisabledByTimeout || tipo == .tapDisabledByUserInput {
                MainActor.assumeIsolated { if let t = NivelService.shared.tap { CGEvent.tapEnable(tap: t, enable: true) } }
                return Unmanaged.passUnretained(evento)
            }
            guard tipo.rawValue == 14, let ns = NSEvent(cgEvent: evento), ns.subtype.rawValue == 8 else {
                return Unmanaged.passUnretained(evento)
            }
            let data1 = ns.data1
            let codigo = (data1 & 0xFFFF0000) >> 16
            let apertou = ((data1 & 0xFF00) >> 8) == 0xA
            let fino = ns.modifierFlags.contains(.option) && ns.modifierFlags.contains(.shift)
            let tratou = MainActor.assumeIsolated {
                NivelService.shared.tecla(codigo: codigo, apertou: apertou, fino: fino)
            }
            return tratou ? nil : Unmanaged.passUnretained(evento)
        }
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: mascara, callback: aviso, userInfo: nil) else {
            semPermissaoTeclas = true
            Self.log("teclas: sem permissão — captura não ligou (Acessibilidade: \(AXIsProcessTrusted() ? "sim" : "não"))")
            return
        }
        semPermissaoTeclas = false
        Self.log("teclas: captura ligada (Acessibilidade: \(AXIsProcessTrusted() ? "sim" : "não"))")
        tap = t
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, t, 0), .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
    }

    /// Pede a permissão de Acessibilidade (abre o aviso do macOS) e tenta de novo.
    func pedirPermissaoTeclas() {
        let opcao = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opcao)
        esperarPermissao(tentativas: 90)
    }

    /// Confere a cada 2 s (até 3 min) se o Hugo já liberou; liberou, liga a captura na hora.
    private func esperarPermissao(tentativas: Int) {
        guard tentativas > 0, tap == nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if AXIsProcessTrusted() { self.atualizarTeclas() }
            else { self.esperarPermissao(tentativas: tentativas - 1) }
        }
    }

    /// true = o Crew cuidou da tecla (o macOS não vê, logo não mostra o aviso dele).
    private func tecla(codigo: Int, apertou: Bool, fino: Bool) -> Bool {
        let s = AppState.shared
        // Mesmos passos do macOS: 16 de 6,25% (Option+Shift: 64, mais fino)
        let passo = fino ? 1.0 / 64 : 1.0 / 16
        switch codigo {
        case 0, 1, 7:   // volume +, volume −, mudo
            guard s.moduloVolume, dispositivo != 0 else { return false }
            if apertou {
                if codigo == 7 {
                    gravarMudo(!lerMudo())
                } else {
                    let atual = lerVolume() ?? 0.5
                    let novo = min(1, max(0, (atual / passo).rounded() * passo + (codigo == 0 ? passo : -passo)))
                    if codigo == 0 && lerMudo() { gravarMudo(false) }
                    gravarVolume(novo)
                }
            }
            return true
        case 2, 3:      // brilho +, brilho −
            ultimoBrilhoManual = Date()   // foi o Hugo, mesmo se a tecla voltar para o macOS
            // Sem como ler o brilho desta tela (tampa fechada, só monitor externo): a tecla
            // volta para o macOS, senão ela some
            guard s.moduloBrilho, let gravar = gravarBrilhoFn, telaBrilho != 0,
                  let atual = lerBrilho(telaBrilho) else { return false }
            ultimoBrilhoManual = Date()
            if apertou {
                let novo = min(1, max(0, (atual / passo).rounded() * passo + (codigo == 2 ? passo : -passo)))
                if gravar(telaBrilho, Float(novo)) != 0 { return false }
            }
            return true
        default:
            return false
        }
    }

    private func gravarVolume(_ v: Double) {
        var f = Float32(v)
        var a = Self.endereco(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeOutput)
        AudioObjectSetPropertyData(dispositivo, &a, 0, nil, UInt32(MemoryLayout<Float32>.size), &f)
    }

    private func gravarMudo(_ m: Bool) {
        var u = UInt32(m ? 1 : 0)
        var a = Self.endereco(kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput)
        AudioObjectSetPropertyData(dispositivo, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &u)
    }

    /// Diagnóstico em ~/Library/Logs/NotchBuddy/nb.log (o mesmo log do HookServer).
    static func log(_ m: String) {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Logs/NotchBuddy")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = dir.appendingPathComponent("nb.log")
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        guard let d = "\(fmt.string(from: Date())) \(m)\n".data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: f) { h.seekToEndOfFile(); h.write(d); try? h.close() }
        else { try? d.write(to: f) }
    }
}
