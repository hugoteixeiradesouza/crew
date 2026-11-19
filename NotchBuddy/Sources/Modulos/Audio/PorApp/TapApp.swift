import AudioToolbox
import CoreAudio
import Darwin
import Foundation
import Synchronization

// Volume de UM app: process tap + aggregate device + IOProc, escrito do zero a partir da técnica
// pública da Apple.
//
//   app ──► [tap privado, "muted when tapped"] ──► aggregate privado (saída atual + tap)
//                                                    └─ IOProc: lê o tap, aplica o ganho com
//                                                       rampa e limitador, escreve na saída
//
// Enquanto o IOProc roda, o macOS cala o som original do app e quem toca é o Crew. Desmontou
// (ou o Crew caiu), o app volta a soar direto. Montagem e desmontagem rodam na fila do motor
// (`MotorTaps`), nunca na main. O callback roda na thread de tempo real do Core Audio: nada de
// alocação, lock, log ou Swift concurrency lá dentro — só ponteiros preparados antes e atômicos.

/// Parâmetros que a main escreve e o callback lê (atômicos; o Float vai como bits).
final class ParametrosTap: Sendable {
    private let alvoBits: Atomic<UInt32>
    /// Quantas vezes o callback rodou — o monitor vê se parou.
    let ciclos = Atomic<UInt64>(0)

    init(ganho: Float) { alvoBits = Atomic(ganho.bitPattern) }

    var alvo: Float {
        get { Float(bitPattern: alvoBits.load(ordering: .relaxed)) }
        set { alvoBits.store(newValue.bitPattern, ordering: .relaxed) }
    }
}

/// Estado só do callback (memória própria, alocada na montagem).
struct EstadoRT {
    var ganhoAtual: Float = 0
    /// Coeficiente da rampa exponencial (~30 ms até 63 % do caminho).
    var coef: Float = 0.001
    /// Índice do primeiro buffer de entrada que é do tap (antes vêm as entradas do hardware).
    var primeiroBufferTap: Int = 0
}

enum ErroTap: Error, CustomStringConvertible {
    case coreAudio(String, OSStatus)
    case formato(String)

    var description: String {
        switch self {
        case .coreAudio(let etapa, let st): "\(etapa) falhou (\(st))"
        case .formato(let f): f
        }
    }
}

/// Os objetos de um tap montado. Desmontar na ordem: parar → IOProc → aggregate → tap.
final class TapApp: @unchecked Sendable {
    let chave: String
    let processos: [AudioObjectID]
    let saidaUID: String
    let parametros: ParametrosTap
    private(set) var tap: AudioObjectID = 0
    private(set) var deriva = true
    private(set) var agregado: AudioObjectID = 0
    private var proc: AudioDeviceIOProcID?
    private var rt: UnsafeMutablePointer<EstadoRT>?

    init(chave: String, processos: [AudioObjectID], saidaUID: String, parametros: ParametrosTap) {
        self.chave = chave
        self.processos = processos
        self.saidaUID = saidaUID
        self.parametros = parametros
    }

    /// Monta tudo. Se qualquer etapa falhar, desmonta o que já subiu e o app fica normal.
    func montar(deriva: Bool, entradasHardware: Int) throws {
        self.deriva = deriva
        do { try montarEtapas(deriva: deriva, entradasHardware: entradasHardware) }
        catch { desmontar(); throw error }
    }

    private func montarEtapas(deriva: Bool, entradasHardware: Int) throws {
        GuardaTaps.instalar()
        let desc = CATapDescription(stereoMixdownOfProcesses: processos)
        desc.name = GuardaTaps.prefixoNome + chave
        desc.isPrivate = true
        desc.muteBehavior = .mutedWhenTapped
        var tapID = AudioObjectID(0)
        var st = AudioHardwareCreateProcessTap(desc, &tapID)
        guard st == noErr, tapID != 0 else { throw ErroTap.coreAudio("criar o tap", st) }
        tap = tapID
        GuardaTaps.guardar(agregado: 0, tap: tapID)

        // O tap entrega Float32; se não, não arrisca.
        guard let fmt = Self.formatoTap(tapID), fmt.mFormatID == kAudioFormatLinearPCM,
              fmt.mFormatFlags & kAudioFormatFlagIsFloat != 0, fmt.mBitsPerChannel == 32 else {
            throw ErroTap.formato("o tap não entrega Float32")
        }

        let descAgregado: [String: Any] = [
            kAudioAggregateDeviceNameKey: GuardaTaps.prefixoNome + chave,
            kAudioAggregateDeviceUIDKey: GuardaTaps.prefixoUID + UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: saidaUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: saidaUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: desc.uuid.uuidString,
                // Ver EscolhaSaida.deriva: liga quando o relógio do app e o da saída diferem.
                kAudioSubTapDriftCompensationKey: deriva,
            ]],
        ]
        var aggID = AudioObjectID(0)
        st = AudioHardwareCreateAggregateDevice(descAgregado as CFDictionary, &aggID)
        guard st == noErr, aggID != 0 else { throw ErroTap.coreAudio("criar o aggregate", st) }
        agregado = aggID
        GuardaTaps.guardar(agregado: aggID, tap: 0)
        guard Self.esperarVivo(aggID) else { throw ErroTap.formato("o aggregate não ficou pronto") }

        // As saídas do aggregate têm que ser Float32 (o formato do IOProc).
        guard Self.saidasFloat32(aggID) else { throw ErroTap.formato("a saída não aceita Float32") }

        let taxa = Self.taxa(aggID) ?? 48_000
        let estado = UnsafeMutablePointer<EstadoRT>.allocate(capacity: 1)
        // Começa do zero e sobe pela rampa: entra sem clique.
        estado.initialize(to: EstadoRT(ganhoAtual: 0, coef: Float(1 - exp(-1 / (taxa * 0.030))),
                                       primeiroBufferTap: entradasHardware))
        rt = estado

        var procID: AudioDeviceIOProcID?
        st = AudioDeviceCreateIOProcIDWithBlock(&procID, aggID, nil, Self.bloco(parametros, estado))
        guard st == noErr, let procID else { throw ErroTap.coreAudio("criar o IOProc", st) }
        proc = procID

        // Entradas do próprio hardware (fone USB com microfone): desligadas para o IOProc, para o
        // macOS não abrir o microfone nem pedir a permissão dele.
        if entradasHardware > 0 { Self.desligarEntradasHardware(aggID, procID, entradasHardware) }

        st = AudioDeviceStart(aggID, procID)
        guard st == noErr else { throw ErroTap.coreAudio("ligar o IO", st) }
    }

    /// Parar → destruir IOProc → destruir aggregate → destruir tap. Idempotente.
    func desmontar() {
        if agregado != 0, let proc {
            AudioDeviceStop(agregado, proc)
            AudioDeviceDestroyIOProcID(agregado, proc)
        }
        proc = nil
        if agregado != 0 {
            AudioHardwareDestroyAggregateDevice(agregado)
            GuardaTaps.soltar(agregado: agregado, tap: 0)
            agregado = 0
        }
        if tap != 0 {
            AudioHardwareDestroyProcessTap(tap)
            GuardaTaps.soltar(agregado: 0, tap: tap)
            tap = 0
        }
        // O IOProc já parou (AudioDeviceStop fora da thread de IO só volta depois do último ciclo).
        if let rt { rt.deinitialize(count: 1); rt.deallocate() }
        rt = nil
    }

    // MARK: Callback de tempo real

    private struct Ponteiro: @unchecked Sendable { let p: UnsafeMutablePointer<EstadoRT> }

    /// O bloco nasce fora de qualquer ator (o Swift 6 derrubaria o app se ele herdasse a main).
    private nonisolated static func bloco(_ par: ParametrosTap, _ estado: UnsafeMutablePointer<EstadoRT>) -> AudioDeviceIOBlock {
        let ptr = Ponteiro(p: estado)
        return { _, entrada, _, saida, _ in
            processar(entrada, saida, par, ptr.p)
        }
    }

    /// Lê o tap, aplica o ganho (rampa por amostra) e o limitador, escreve em todas as saídas.
    /// Canal de saída sem canal correspondente no tap (5.1, por exemplo) fica em silêncio.
    nonisolated static func processar(_ entrada: UnsafePointer<AudioBufferList>,
                                              _ saida: UnsafeMutablePointer<AudioBufferList>,
                                              _ par: ParametrosTap, _ st: UnsafeMutablePointer<EstadoRT>) {
        par.ciclos.add(1, ordering: .relaxed)
        let alvo = par.alvo
        let coef = st.pointee.coef
        let inicio = st.pointee.ganhoAtual
        var fim = inicio

        let entradas = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: entrada))
        let saidas = UnsafeMutableAudioBufferListPointer(saida)
        let primeiro = st.pointee.primeiroBufferTap

        // Canais do tap (soma dos buffers a partir do primeiro do tap).
        var canaisTap = 0
        if primeiro < entradas.count {
            for b in primeiro..<entradas.count { canaisTap += Int(entradas[b].mNumberChannels) }
        }

        var canalGlobal = 0
        for o in 0..<saidas.count {
            let bufSaida = saidas[o]
            guard let dadosSaida = bufSaida.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let nCanais = max(Int(bufSaida.mNumberChannels), 1)
            let quadrosSaida = Int(bufSaida.mDataByteSize) / (4 * nCanais)
            for c in 0..<nCanais {
                defer { canalGlobal += 1 }
                // Acha o canal do tap (mono vai nos dois lados).
                let alvoCanal = canaisTap == 1 ? 0 : canalGlobal
                var origem: UnsafeMutablePointer<Float>?
                var passo = 1
                var quadrosTap = 0
                if alvoCanal < canaisTap {
                    var resto = alvoCanal
                    for b in primeiro..<entradas.count {
                        let n = Int(entradas[b].mNumberChannels)
                        if resto < n {
                            if let d = entradas[b].mData?.assumingMemoryBound(to: Float.self), n > 0 {
                                origem = d + resto
                                passo = n
                                quadrosTap = Int(entradas[b].mDataByteSize) / (4 * n)
                            }
                            break
                        }
                        resto -= n
                    }
                }
                let quadros = origem == nil ? 0 : min(quadrosSaida, quadrosTap)
                var g = inicio
                if let origem {
                    for f in 0..<quadros {
                        g += (alvo - g) * coef
                        var y = origem[f * passo] * g
                        // Limitador suave acima de 0,95: só age quando o reforço passa do teto.
                        let a = abs(y)
                        if a > 0.95 {
                            let lim = 0.95 + 0.05 * tanhf((a - 0.95) / 0.05)
                            y = y < 0 ? -lim : lim
                        }
                        dadosSaida[f * nCanais + c] = y
                    }
                }
                for f in quadros..<quadrosSaida { dadosSaida[f * nCanais + c] = 0 }
                if quadros > 0 { fim = g }
            }
        }
        // Sem saída ou sem tap neste ciclo: a rampa anda mesmo assim, para o mudo valer já.
        if fim == inicio && inicio != alvo { fim = alvo }
        st.pointee.ganhoAtual = fim
    }

    // MARK: Auxiliares (fila do motor)

    private static func formatoTap(_ id: AudioObjectID) -> AudioStreamBasicDescription? {
        var addr = CoreAudioHW.endereco(kAudioTapPropertyFormat)
        var f = AudioStreamBasicDescription()
        var tam = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        return AudioObjectGetPropertyData(id, &addr, 0, nil, &tam, &f) == noErr ? f : nil
    }

    private static func esperarVivo(_ id: AudioObjectID) -> Bool {
        for _ in 0..<40 {
            var addr = CoreAudioHW.endereco(kAudioDevicePropertyDeviceIsAlive)
            var v: UInt32 = 0
            var tam = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(id, &addr, 0, nil, &tam, &v) == noErr, v != 0 { return true }
            usleep(25_000)
        }
        return false
    }

    private static func taxa(_ id: AudioObjectID) -> Double? {
        var addr = CoreAudioHW.endereco(kAudioDevicePropertyNominalSampleRate)
        var v = Float64(0)
        var tam = UInt32(MemoryLayout<Float64>.size)
        return AudioObjectGetPropertyData(id, &addr, 0, nil, &tam, &v) == noErr && v > 0 ? v : nil
    }

    private static func saidasFloat32(_ id: AudioObjectID) -> Bool {
        for s in streams(id, kAudioObjectPropertyScopeOutput) {
            var addr = CoreAudioHW.endereco(kAudioStreamPropertyVirtualFormat)
            var f = AudioStreamBasicDescription()
            var tam = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            guard AudioObjectGetPropertyData(s, &addr, 0, nil, &tam, &f) == noErr else { return false }
            guard f.mFormatID == kAudioFormatLinearPCM, f.mFormatFlags & kAudioFormatFlagIsFloat != 0,
                  f.mBitsPerChannel == 32, f.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0 else { return false }
        }
        return true
    }

    static func streams(_ id: AudioObjectID, _ escopo: AudioObjectPropertyScope) -> [AudioStreamID] {
        var addr = CoreAudioHW.endereco(kAudioDevicePropertyStreams, escopo)
        var tam: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &tam) == noErr, tam > 0 else { return [] }
        var ids = [AudioStreamID](repeating: 0, count: Int(tam) / MemoryLayout<AudioStreamID>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &tam, &ids) == noErr else { return [] }
        return ids
    }

    /// `kAudioDevicePropertyIOProcStreamUsage`: liga só os streams de entrada que são do tap.
    /// A estrutura é de tamanho variável: ponteiro do IOProc, quantidade, um UInt32 por stream.
    private static func desligarEntradasHardware(_ agg: AudioObjectID, _ proc: AudioDeviceIOProcID, _ hw: Int) {
        let total = streams(agg, kAudioObjectPropertyScopeInput).count
        guard total > hw else { return }
        let tam = MemoryLayout<UnsafeMutableRawPointer>.size + 4 + 4 * total
        let mem = UnsafeMutableRawPointer.allocate(byteCount: tam, alignment: 8)
        defer { mem.deallocate() }
        mem.storeBytes(of: unsafeBitCast(proc, to: UnsafeMutableRawPointer.self), as: UnsafeMutableRawPointer.self)
        let base = MemoryLayout<UnsafeMutableRawPointer>.size
        mem.storeBytes(of: UInt32(total), toByteOffset: base, as: UInt32.self)
        for i in 0..<total {
            mem.storeBytes(of: UInt32(i < hw ? 0 : 1), toByteOffset: base + 4 + 4 * i, as: UInt32.self)
        }
        var addr = CoreAudioHW.endereco(kAudioDevicePropertyIOProcStreamUsage, kAudioObjectPropertyScopeInput)
        AudioObjectSetPropertyData(agg, &addr, 0, nil, UInt32(tam), mem)
    }
}

/// Dono de todos os taps. Tudo que monta/desmonta passa pela fila serial dele (fora da main).
final class MotorTaps: @unchecked Sendable {
    static let shared = MotorTaps()

    private let fila = DispatchQueue(label: "fr.louisraille.NotchBuddy.audio.taps", qos: .userInitiated)
    /// Só lido/escrito na `fila`.
    private var ativos: [String: TapApp] = [:]
    private let log = Log.de("audio")

    enum Resultado: Sendable { case ok, falhou(String) }

    /// Monta (ou remonta, se mudou o app/saída) o tap de um app. `pronto` volta na main.
    func garantir(chave: String, processos: [AudioObjectID], saida: DispositivoAudio, deriva: Bool, parametros: ParametrosTap,
                  forcar: Bool = false, pronto: @escaping @Sendable @MainActor (Resultado) -> Void) {
        fila.async { [self] in
            if let atual = ativos[chave] {
                if !forcar, atual.processos == processos, atual.saidaUID == saida.uid, atual.deriva == deriva, atual.parametros === parametros {
                    return
                }
                atual.desmontar()
                ativos[chave] = nil
            }
            let novo = TapApp(chave: chave, processos: processos, saidaUID: saida.uid, parametros: parametros)
            let hw = TapApp.streams(saida.id, kAudioObjectPropertyScopeInput).count
            let resultado: Resultado
            do {
                try novo.montar(deriva: deriva, entradasHardware: hw)
                ativos[chave] = novo
                log.info("tap ligado: \(chave, privacy: .public) → \(saida.nome, privacy: .public) (\(processos.count) processo(s))")
                resultado = .ok
            } catch {
                log.error("tap de \(chave, privacy: .public) não subiu: \(String(describing: error), privacy: .public)")
                resultado = .falhou(String(describing: error))
            }
            DispatchQueue.main.async { pronto(resultado) }
        }
    }

    func remover(_ chave: String) {
        fila.async { [self] in
            guard let t = ativos.removeValue(forKey: chave) else { return }
            t.desmontar()
            log.info("tap desligado: \(chave, privacy: .public)")
        }
    }

    /// Desmonta tudo e espera terminar — no máximo 2 s, para nunca travar a saída do Crew (se a
    /// fila estiver presa num pedido de permissão, o macOS desfaz os objetos quando o processo sai).
    func removerTodosAgora() {
        let feito = DispatchSemaphore(value: 0)
        fila.async { [self] in
            for t in ativos.values { t.desmontar() }
            if !ativos.isEmpty { log.info("taps desligados: \(self.ativos.count)") }
            ativos.removeAll()
            feito.signal()
        }
        _ = feito.wait(timeout: .now() + 2)
    }

    func limparOrfaos() {
        fila.async { [self] in
            let n = GuardaTaps.limparOrfaos()
            if n > 0 { log.notice("limpeza na abertura: \(n) objeto(s) de áudio órfão(s) do Crew destruído(s)") }
        }
    }
}
