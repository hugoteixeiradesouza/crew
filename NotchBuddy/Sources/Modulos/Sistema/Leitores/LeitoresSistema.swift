import Foundation
import IOKit
import IOKit.ps

// Leitores pequenos do módulo Sistema. Todos sem subprocesso.

// MARK: - Rede (bytes por segundo, todas as interfaces menos loopback)

struct AmostraRede: Sendable {
    var entrada: Double = 0; var saida: Double = 0                  // bytes/s
    var pacotesEntrada: Double = 0; var pacotesSaida: Double = 0    // pacotes/s
    var totalEntrada: UInt64 = 0; var totalSaida: UInt64 = 0        // desde que a interface subiu
}

final class LeitorRede: @unchecked Sendable {
    private var anterior: (entrada: UInt64, saida: UInt64, pe: UInt64, ps: UInt64, t: UInt64)?

    func ler() -> AmostraRede {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var tam = 0
        guard sysctl(&mib, 6, nil, &tam, nil, 0) == 0, tam > 0 else { return AmostraRede() }
        var buf = [UInt8](repeating: 0, count: tam)
        guard sysctl(&mib, 6, &buf, &tam, nil, 0) == 0 else { return AmostraRede() }
        var entrada: UInt64 = 0, saida: UInt64 = 0, pe: UInt64 = 0, ps: UInt64 = 0
        var i = 0
        buf.withUnsafeBytes { p in
            while i + MemoryLayout<if_msghdr>.size <= tam {
                let h = p.load(fromByteOffset: i, as: if_msghdr.self)
                guard h.ifm_msglen > 0 else { break }
                if Int32(h.ifm_type) == RTM_IFINFO2, i + MemoryLayout<if_msghdr2>.size <= tam {
                    let h2 = p.load(fromByteOffset: i, as: if_msghdr2.self)
                    // Loopback fica de fora (tráfego local, não é rede)
                    if h2.ifm_flags & IFF_LOOPBACK == 0 {
                        entrada &+= h2.ifm_data.ifi_ibytes
                        saida &+= h2.ifm_data.ifi_obytes
                        pe &+= h2.ifm_data.ifi_ipackets
                        ps &+= h2.ifm_data.ifi_opackets
                    }
                }
                i += Int(h.ifm_msglen)
            }
        }
        let agora = DispatchTime.now().uptimeNanoseconds
        defer { anterior = (entrada, saida, pe, ps, agora) }
        var r = AmostraRede(totalEntrada: entrada, totalSaida: saida)
        guard let a = anterior, agora > a.t, entrada >= a.entrada, saida >= a.saida else { return r }
        let s = Double(agora - a.t) / 1e9
        r.entrada = Double(entrada - a.entrada) / s
        r.saida = Double(saida - a.saida) / s
        r.pacotesEntrada = Double(pe &- min(pe, a.pe)) / s
        r.pacotesSaida = Double(ps &- min(ps, a.ps)) / s
        return r
    }
}

// MARK: - GPU (uso, IORegistry PerformanceStatistics)

enum LeitorGPU {
    static func ler() -> Double? {
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(kIOAcceleratorClassName), &it) == kIOReturnSuccess else { return nil }
        defer { IOObjectRelease(it) }
        var maior: Double?
        var s = IOIteratorNext(it)
        while s != 0 {
            if let est = IORegistryEntryCreateCFProperty(s, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? [String: Any],
               let uso = est["Device Utilization %"] as? Int {
                maior = max(maior ?? 0, Double(uso) / 100)
            }
            IOObjectRelease(s)
            s = IOIteratorNext(it)
        }
        return maior
    }
}

// MARK: - Disco (volume de inicialização)

struct AmostraDisco: Sendable { var livre: Int64 = 0; var total: Int64 = 0 }

enum LeitorDisco {
    static func ler() -> AmostraDisco {
        let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
        return AmostraDisco(livre: v?.volumeAvailableCapacityForImportantUsage ?? 0, total: Int64(v?.volumeTotalCapacity ?? 0))
    }
}

// MARK: - Bateria

struct AmostraBateria: Sendable {
    var nivel: Double = 0            // 0…1
    var carregando = false
    var naTomada = false
    var minutosRestantes: Int?       // até acabar ou até encher
    var ciclos: Int?
    var saude: Double?               // capacidade máxima / de fábrica
}

enum LeitorBateria {
    static func ler() -> AmostraBateria? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let lista = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for fonte in lista {
            guard let d = IOPSGetPowerSourceDescription(info, fonte)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            var b = AmostraBateria()
            let atual = d[kIOPSCurrentCapacityKey] as? Int ?? 0, maximo = d[kIOPSMaxCapacityKey] as? Int ?? 100
            b.nivel = maximo > 0 ? Double(atual) / Double(maximo) : 0
            b.carregando = d[kIOPSIsChargingKey] as? Bool ?? false
            b.naTomada = d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            let min = b.carregando ? d[kIOPSTimeToFullChargeKey] as? Int : d[kIOPSTimeToEmptyKey] as? Int
            if let min, min > 0 { b.minutosRestantes = min }
            let s = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
            if s != 0 {
                func prop(_ k: String) -> Int? {
                    IORegistryEntryCreateCFProperty(s, k as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int
                }
                b.ciclos = prop("CycleCount")
                if let raw = prop("AppleRawMaxCapacity"), let projeto = prop("DesignCapacity"), projeto > 0 {
                    b.saude = Double(raw) / Double(projeto)
                } else if let dados = IORegistryEntryCreateCFProperty(s, "BatteryData" as CFString, kCFAllocatorDefault, 0)?
                            .takeRetainedValue() as? [String: Any],
                          let nominal = dados["NominalChargeCapacity"] as? Int,
                          let projeto = dados["DesignCapacity"] as? Int, projeto > 0 {
                    // Macs mais novos guardam as capacidades dentro de BatteryData
                    b.saude = Double(nominal) / Double(projeto)
                }
                IOObjectRelease(s)
            }
            return b
        }
        return nil
    }
}

// MARK: - Carga e tempo ligado

struct AmostraCarga: Sendable { var um: Double = 0; var cinco: Double = 0; var quinze: Double = 0; var ligadoHa: TimeInterval = 0 }

enum LeitorCarga {
    static func ler() -> AmostraCarga {
        var l = [Double](repeating: 0, count: 3)
        getloadavg(&l, 3)
        var boot = timeval()
        var tam = MemoryLayout<timeval>.size
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        sysctl(&mib, 2, &boot, &tam, nil, 0)
        let ligado = boot.tv_sec > 0 ? Date().timeIntervalSince1970 - Double(boot.tv_sec) : 0
        return AmostraCarga(um: l[0], cinco: l[1], quinze: l[2], ligadoHa: ligado)
    }
}
