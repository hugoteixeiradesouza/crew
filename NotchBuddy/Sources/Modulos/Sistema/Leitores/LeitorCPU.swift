import Foundation
import IOKit

struct AmostraCPU: Sendable {
    var total: Double = 0       // 0…1
    var sistema: Double = 0
    var usuario: Double = 0
    var eficiencia: Double = 0  // média dos núcleos E
    var desempenho: Double = 0  // média dos núcleos P
    var nucleosE = 0
    var nucleosP = 0
}

/// Uso de CPU por núcleo (delta de ticks de `host_processor_info`). Só na fila do amostrador.
final class LeitorCPU: @unchecked Sendable {
    private var anterior: [Int32] = []
    /// tipo de cada núcleo lógico: "E" ou "P"
    private lazy var tipos: [Int: String] = Self.topologia()

    func ler() -> AmostraCPU {
        var n: natural_t = 0
        var info: processor_info_array_t?
        var nInfo: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &n, &info, &nInfo) == KERN_SUCCESS,
              let info else { return AmostraCPU() }
        defer { vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(Int(nInfo) * MemoryLayout<integer_t>.stride)) }
        let atual = Array(UnsafeBufferPointer(start: info, count: Int(nInfo)))
        defer { anterior = atual }
        guard anterior.count == atual.count else { return AmostraCPU() }

        var a = AmostraCPU()
        var somaU = 0.0, somaS = 0.0, somaT = 0.0
        var e = (uso: 0.0, n: 0), p = (uso: 0.0, n: 0)
        let st = Int(CPU_STATE_MAX)
        for c in 0..<Int(n) {
            let i = c * st
            let u = Double(atual[i + Int(CPU_STATE_USER)] &- anterior[i + Int(CPU_STATE_USER)])
                  + Double(atual[i + Int(CPU_STATE_NICE)] &- anterior[i + Int(CPU_STATE_NICE)])
            let s = Double(atual[i + Int(CPU_STATE_SYSTEM)] &- anterior[i + Int(CPU_STATE_SYSTEM)])
            let o = Double(atual[i + Int(CPU_STATE_IDLE)] &- anterior[i + Int(CPU_STATE_IDLE)])
            let t = u + s + o
            guard t > 0 else { continue }
            somaU += u; somaS += s; somaT += t
            let uso = (u + s) / t
            if tipos[c] == "E" { e.uso += uso; e.n += 1 } else { p.uso += uso; p.n += 1 }
        }
        guard somaT > 0 else { return a }
        a.usuario = somaU / somaT
        a.sistema = somaS / somaT
        a.total = a.usuario + a.sistema
        a.nucleosE = e.n; a.nucleosP = p.n
        a.eficiencia = e.n > 0 ? e.uso / Double(e.n) : 0
        a.desempenho = p.n > 0 ? p.uso / Double(p.n) : 0
        return a
    }

    /// Lê no IORegistry (AppleARMPE → cpuN, "cluster-type") quem é E e quem é P.
    /// Sem isso (Intel), tudo conta como P.
    private static func topologia() -> [Int: String] {
        var mapa: [Int: String] = [:]
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleARMPE"), &it) == kIOReturnSuccess else { return mapa }
        defer { IOObjectRelease(it) }
        var servico = IOIteratorNext(it)
        while servico != 0 {
            var filhos: io_iterator_t = 0
            if IORegistryEntryGetChildIterator(servico, kIOServicePlane, &filhos) == kIOReturnSuccess {
                var filho = IOIteratorNext(filhos)
                while filho != 0 {
                    var nome = [CChar](repeating: 0, count: 128)
                    IORegistryEntryGetName(filho, &nome)
                    let s = nome.textoC
                    if s.hasPrefix("cpu"), let idx = Int(s.dropFirst(3)),
                       let d = IORegistryEntryCreateCFProperty(filho, "cluster-type" as CFString, kCFAllocatorDefault, 0)?
                            .takeRetainedValue() as? Data,
                       let tipo = String(data: d, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters.union(.whitespaces)) {
                        // M5 em diante: "E"/"M"/"P" (P = super). Para o Crew: E é eficiência, o resto desempenho.
                        mapa[idx] = tipo == "E" ? "E" : "P"
                    }
                    IOObjectRelease(filho)
                    filho = IOIteratorNext(filhos)
                }
                IOObjectRelease(filhos)
            }
            IOObjectRelease(servico)
            servico = IOIteratorNext(it)
        }
        return mapa
    }
}
