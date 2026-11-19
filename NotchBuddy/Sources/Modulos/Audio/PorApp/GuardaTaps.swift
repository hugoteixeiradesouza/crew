import CoreAudio
import Darwin
import Foundation

// Segurança do volume por app: o tap silencia o app original ("muted when tapped") e o Crew
// toca a cópia ajustada. Se o Crew morrer com o tap de pé, o app ficaria mudo. Três defesas:
//   1) crash: um handler de sinal destrói os aggregates e taps do Crew antes de o processo cair;
//   2) abertura: destrói o que sobrou com o prefixo do Crew (aggregate/tap que não seja privado);
//   3) o próprio macOS desfaz objetos privados quando o processo dono morre (inclusive `kill -9`,
//      que nenhum handler pega — medido na entrega).

enum GuardaTaps {
    /// Prefixo dos nomes e UIDs que o Crew cria. Só o que começa com isto é destruído na limpeza.
    static let prefixoNome = "Crew-porapp-"
    static let prefixoUID = "fr.louisraille.NotchBuddy.porapp."

    // Memória fixa, lida pelo handler de sinal sem alocar nem travar. Escrita só pela fila do
    // motor (serial). 0 = vazio.
    private static let vagas = 64
    private nonisolated(unsafe) static var agregados: UnsafeMutablePointer<AudioObjectID> = {
        let p = UnsafeMutablePointer<AudioObjectID>.allocate(capacity: vagas)
        p.initialize(repeating: 0, count: vagas)
        return p
    }()
    private nonisolated(unsafe) static var taps: UnsafeMutablePointer<AudioObjectID> = {
        let p = UnsafeMutablePointer<AudioObjectID>.allocate(capacity: vagas)
        p.initialize(repeating: 0, count: vagas)
        return p
    }()
    private nonisolated(unsafe) static var instalado = false

    /// Liga o handler (uma vez, antes do primeiro tap). Não toma o lugar de handler de outro:
    /// sinal que já tem dono fica com ele.
    static func instalar() {
        guard !instalado else { return }
        instalado = true
        _ = agregados; _ = taps   // aloca agora, fora do handler
        for sinal in [SIGABRT, SIGSEGV, SIGBUS, SIGTRAP, SIGILL, SIGFPE, SIGTERM, SIGHUP, SIGINT] {
            var antigo = sigaction()
            guard sigaction(sinal, nil, &antigo) == 0 else { continue }
            let atual = unsafeBitCast(antigo.__sigaction_u.__sa_handler, to: Int.self)
            guard atual == 0 /* SIG_DFL */ else { continue }
            var novo = sigaction()
            novo.__sigaction_u.__sa_handler = guardaTapsSinal
            sigemptyset(&novo.sa_mask)
            novo.sa_flags = SA_RESETHAND
            sigaction(sinal, &novo, nil)
        }
    }

    static func guardar(agregado: AudioObjectID, tap: AudioObjectID) {
        if agregado != 0 { ocupar(agregados, agregado) }
        if tap != 0 { ocupar(taps, tap) }
    }

    static func soltar(agregado: AudioObjectID, tap: AudioObjectID) {
        for i in 0..<vagas {
            if agregado != 0 && agregados[i] == agregado { agregados[i] = 0 }
            if tap != 0 && taps[i] == tap { taps[i] = 0 }
        }
    }

    private static func ocupar(_ p: UnsafeMutablePointer<AudioObjectID>, _ id: AudioObjectID) {
        for i in 0..<vagas where p[i] == 0 { p[i] = id; return }
    }

    /// Chamado pelo handler: aggregates primeiro (param o IO), depois os taps (o app volta a soar).
    fileprivate static func destruirTudoNoSinal() {
        for i in 0..<vagas where agregados[i] != 0 { AudioHardwareDestroyAggregateDevice(agregados[i]) }
        for i in 0..<vagas where taps[i] != 0 { AudioHardwareDestroyProcessTap(taps[i]) }
    }

    // MARK: Limpeza na abertura

    /// Destrói aggregates e taps com o prefixo do Crew que ainda existam. Devolve quantos.
    static func limparOrfaos() -> Int {
        var n = 0
        for id in lerLista(kAudioHardwarePropertyDevices) {
            guard let uid = textoCF(id, kAudioDevicePropertyDeviceUID), uid.hasPrefix(prefixoUID) else { continue }
            if AudioHardwareDestroyAggregateDevice(id) == noErr { n += 1 }
        }
        for id in lerLista(kAudioHardwarePropertyTapList) {
            guard let nome = nomeDoTap(id), nome.hasPrefix(prefixoNome) else { continue }
            if AudioHardwareDestroyProcessTap(id) == noErr { n += 1 }
        }
        return n
    }

    private static func lerLista(_ sel: AudioObjectPropertySelector) -> [AudioObjectID] {
        var addr = CoreAudioHW.endereco(sel)
        var tam: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(CoreAudioHW.sistema, &addr, 0, nil, &tam) == noErr, tam > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(tam) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(CoreAudioHW.sistema, &addr, 0, nil, &tam, &ids) == noErr else { return [] }
        return ids
    }

    static func textoCF(_ id: AudioObjectID, _ sel: AudioObjectPropertySelector) -> String? {
        var addr = CoreAudioHW.endereco(sel)
        var valor: Unmanaged<CFString>?
        var tam = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let st = withUnsafeMutablePointer(to: &valor) { AudioObjectGetPropertyData(id, &addr, 0, nil, &tam, $0) }
        guard st == noErr, let v = valor else { return nil }
        return v.takeRetainedValue() as String
    }

    private static func nomeDoTap(_ id: AudioObjectID) -> String? {
        var addr = CoreAudioHW.endereco(kAudioTapPropertyDescription)
        var valor: Unmanaged<CATapDescription>?
        var tam = UInt32(MemoryLayout<Unmanaged<CATapDescription>?>.size)
        let st = withUnsafeMutablePointer(to: &valor) { AudioObjectGetPropertyData(id, &addr, 0, nil, &tam, $0) }
        guard st == noErr, let v = valor else { return nil }
        return v.takeRetainedValue().name
    }
}

/// Handler de sinal (C). Destrói o que o Crew criou e deixa o sinal seguir (SA_RESETHAND já
/// devolveu o padrão): o processo cai como cairia, mas sem deixar app mudo.
private func guardaTapsSinal(_ sinal: Int32) {
    GuardaTaps.destruirTudoNoSinal()
    raise(sinal)
}
