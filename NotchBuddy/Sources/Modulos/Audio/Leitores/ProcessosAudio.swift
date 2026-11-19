import AppKit
import CoreAudio
import Darwin

// Quem está usando o áudio agora, pelo Core Audio (macOS 14.2+): a lista de "objetos de
// processo" do HAL e, de cada um, o pid, o bundle id e se está tocando (saída ativa).
//
// O som de muitos apps sai de um processo auxiliar (Chrome → "Google Chrome Helper", Safari →
// WebKit): `donoDe` sobe até o app que o Hugo reconhece, para o volume ser do app e não do helper.

/// Um processo com cliente de áudio aberto.
struct ProcessoAudio: Equatable, Sendable {
    let objeto: AudioObjectID
    let pid: pid_t
    let bundle: String
    let tocando: Bool
}

/// Um app (o dono) com os seus processos de áudio.
struct AppAudio: Identifiable, Equatable, Sendable {
    /// Bundle id do app dono — também a chave dos ajustes salvos.
    let id: String
    let nome: String
    let pid: pid_t
    /// Objetos de processo do HAL (o app e os auxiliares dele), em ordem.
    let processos: [AudioObjectID]
    let tocando: Bool
}

enum CoreAudioProcessos {
    static func lista() -> [ProcessoAudio] {
        var addr = CoreAudioHW.endereco(kAudioHardwarePropertyProcessObjectList)
        var tam: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(CoreAudioHW.sistema, &addr, 0, nil, &tam) == noErr, tam > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(tam) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(CoreAudioHW.sistema, &addr, 0, nil, &tam, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            guard let pid = pidDe(id) else { return nil }
            return ProcessoAudio(objeto: id, pid: pid, bundle: bundleDe(id) ?? "", tocando: tocando(id))
        }
    }

    static func tocando(_ id: AudioObjectID) -> Bool {
        var addr = CoreAudioHW.endereco(kAudioProcessPropertyIsRunningOutput)
        var v: UInt32 = 0
        var tam = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(id, &addr, 0, nil, &tam, &v) == noErr && v != 0
    }

    private static func pidDe(_ id: AudioObjectID) -> pid_t? {
        var addr = CoreAudioHW.endereco(kAudioProcessPropertyPID)
        var v: pid_t = -1
        var tam = UInt32(MemoryLayout<pid_t>.size)
        return AudioObjectGetPropertyData(id, &addr, 0, nil, &tam, &v) == noErr && v > 0 ? v : nil
    }

    private static func bundleDe(_ id: AudioObjectID) -> String? {
        var addr = CoreAudioHW.endereco(kAudioProcessPropertyBundleID)
        var valor: Unmanaged<CFString>?
        var tam = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let st = withUnsafeMutablePointer(to: &valor) { AudioObjectGetPropertyData(id, &addr, 0, nil, &tam, $0) }
        guard st == noErr, let v = valor else { return nil }
        return v.takeRetainedValue() as String
    }

    // MARK: Dono

    /// O app que o Hugo reconhece por trás de um processo de áudio, ou nil (daemon do sistema,
    /// som de alerta, processo sem app) — esses não entram na lista.
    @MainActor
    static func donoDe(pid: pid_t, bundle: String) -> NSRunningApplication? {
        func regular(_ p: pid_t) -> NSRunningApplication? {
            guard let a = NSRunningApplication(processIdentifier: p), a.activationPolicy == .regular,
                  a.bundleIdentifier != nil else { return nil }
            return a
        }
        if let a = regular(pid) { return a }
        // 1) responsável (SPI pública na libSystem, sem framework privado): é o que liga o
        //    WebKit do Safari ao Safari. Se sumir numa versão do macOS, cai nas outras regras.
        if let r = responsavel(pid), let a = regular(r) { return a }
        // 2) árvore de processos (helpers do Chrome, Electron…)
        var p = pid
        for _ in 0..<6 {
            guard let pai = paiDe(p), pai > 1 else { break }
            if let a = regular(pai) { return a }
            p = pai
        }
        // 3) prefixo do bundle ("com.google.Chrome.helper" → "com.google.Chrome")
        guard !bundle.isEmpty else { return nil }
        return NSWorkspace.shared.runningApplications.first { a in
            guard a.activationPolicy == .regular, let b = a.bundleIdentifier else { return false }
            return bundle.hasPrefix(b + ".")
        }
    }

    private typealias FuncResponsavel = @convention(c) (pid_t) -> pid_t
    private static let funcResponsavel: FuncResponsavel? = {
        guard let s = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid") else { return nil }
        return unsafeBitCast(s, to: FuncResponsavel.self)
    }()

    private static func responsavel(_ pid: pid_t) -> pid_t? {
        guard let f = funcResponsavel else { return nil }
        let r = f(pid)
        return r > 0 && r != pid ? r : nil
    }

    private static func paiDe(_ pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var tam = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &tam, nil, 0) == 0, tam > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }
}
