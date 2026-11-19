import Darwin
import Foundation

// Pasta de trabalho (cwd) de cada processo do usuário, via `proc_pidinfo` — sem abrir `lsof`/`ps`.

enum DiretoriosDeProcessos {
    /// `proc_listallpids` devolve número de pids nas duas chamadas, não bytes.
    static func pids() -> [pid_t]? {
        let n = proc_listallpids(nil, 0)
        guard n > 0 else { return nil }
        // Folga para processos que nascem entre as duas chamadas.
        var lista = [pid_t](repeating: 0, count: Int(n) + 64)
        let lidos = proc_listallpids(&lista, Int32(MemoryLayout<pid_t>.size * lista.count))
        guard lidos > 0 else { return nil }
        return lista.prefix(Int(lidos)).filter { $0 > 0 }
    }

    static func cwd(_ pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let tam = MemoryLayout<proc_vnodepathinfo>.stride
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, Int32(tam)) == Int32(tam) else { return nil }
        return withUnsafePointer(to: &info.pvi_cdir.vip_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
        }
    }

    /// cwd de todo processo que dá para inspecionar (só os do usuário), menos `/`.
    /// Nil quando a própria lista de processos não pôde ser lida.
    static func todosSeLegivel() -> Set<String>? {
        guard let pids = pids() else { return nil }
        var dirs: Set<String> = []
        for pid in pids {
            guard let c = cwd(pid), !c.isEmpty, c != "/" else { continue }
            dirs.insert((c as NSString).standardizingPath)
        }
        return dirs
    }
}
