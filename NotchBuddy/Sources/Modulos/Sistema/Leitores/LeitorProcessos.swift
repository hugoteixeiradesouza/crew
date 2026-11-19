import Foundation
import Darwin

struct InfoProcesso: Sendable, Identifiable {
    let pid: pid_t
    let nome: String
    let cpu: Double         // fração de um núcleo (1 = 100 %)
    let memoria: UInt64     // phys_footprint
    var id: pid_t { pid }
}

/// Top processos por CPU, sem abrir `ps`/`top`: `proc_pid_rusage` em delta.
/// Só enxerga processos do próprio usuário (os do sistema, como o WindowServer, pedem root).
final class LeitorProcessos: @unchecked Sendable {
    private var anterior: [pid_t: UInt64] = [:]   // tempo de CPU (ns)
    private var instante: UInt64 = 0
    private let base: (numer: UInt64, denom: UInt64) = {
        var tb = mach_timebase_info_data_t(); mach_timebase_info(&tb)
        return (UInt64(tb.numer), UInt64(tb.denom))
    }()

    func ler(limite: Int = 8) -> [InfoProcesso] {
        let agora = DispatchTime.now().uptimeNanoseconds
        let n = proc_listallpids(nil, 0)
        guard n > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(n) + 32)
        let total = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        var tempos: [pid_t: UInt64] = [:]
        var lista: [InfoProcesso] = []
        let decorrido = Double(agora &- instante)
        for pid in pids.prefix(Int(max(total, 0))) where pid > 0 {
            var ru = rusage_info_current()
            let r = withUnsafeMutablePointer(to: &ru) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, $0) }
            }
            guard r == 0 else { continue }
            let ns = (ru.ri_user_time + ru.ri_system_time) * base.numer / base.denom
            tempos[pid] = ns
            guard instante > 0, decorrido > 0, let antes = anterior[pid], ns >= antes else { continue }
            let cpu = Double(ns - antes) / decorrido
            guard cpu > 0.001 else { continue }
            lista.append(InfoProcesso(pid: pid, nome: Self.nome(pid), cpu: cpu, memoria: ru.ri_phys_footprint))
        }
        anterior = tempos
        instante = agora
        return Array(lista.sorted { $0.cpu > $1.cpu }.prefix(limite))
    }

    private static func nome(_ pid: pid_t) -> String {
        var caminho = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        if proc_pidpath(pid, &caminho, UInt32(caminho.count)) > 0 {
            return (caminho.textoC as NSString).lastPathComponent
        }
        var curto = [CChar](repeating: 0, count: 64)
        proc_name(pid, &curto, UInt32(curto.count))
        return curto.textoC
    }
}
