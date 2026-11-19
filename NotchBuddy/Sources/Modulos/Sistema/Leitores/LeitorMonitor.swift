import Foundation
import Darwin
import IOKit
import IOKit.pwr_mgt

// Leitura do monitor de atividade (todos os processos do Mac). Só roda com o monitor na tela
// (assinatura do Amostrador, a cada 2 s). Técnica conferida no ActivityMonitor de Wiesław
// Šoltés (github.com/wieslawsoltes/ActivityMonitor — sem licença publicada, por isso nada do
// código dele foi copiado; só a técnica, que é das APIs da Apple):
//
//  • lista de todos: `sysctl KERN_PROC_ALL` (pid, pai, dono, início, nome) — vale para todos;
//  • números dos processos do Hugo: `proc_pid_rusage` V6 (CPU, memória, disco, energia,
//    despertares) e `proc_pidinfo PROC_PIDTASKINFO` (threads, residente);
//  • processos de outro usuário (root, _windowserver…): o macOS nega as duas chamadas sem
//    privilégio (medido neste Mac: 209 de 720 processos). O único caminho sem root é o `/bin/ps`
//    (setuid root): tempo de CPU e memória residente, uma vez por leitura, pelo `Processo.rodar`;
//  • rede por processo: só o `nettop`, que tem um direito privado da Apple
//    (com.apple.private.network.statistics) — fica de fora (exigiria subprocesso a cada leitura).

struct ProcessoMonitor: Sendable, Identifiable {
    let pid: pid_t
    let pai: pid_t
    let uid: uid_t
    let nome: String
    let caminho: String
    let inicio: Date
    /// Lido pela libproc (processo do Hugo). false = de outro usuário, só pelo ps (ou nada).
    let proprio: Bool
    var cpu: Double = 0                 // fração de um núcleo (1 = 100 %)
    var tempoCPU: Double?               // segundos acumulados
    var threads: Int?
    var memoria: UInt64?                // pegada física (próprio) ou residente (ps)
    var residente: UInt64?
    var energia: Double?                // watts (estimativa do kernel, ri_energy_nj)
    var despertares: Double?            // por segundo
    var impedeRepouso = false
    var lidos: UInt64?, escritos: UInt64?           // acumulados
    var lidosSeg: Double?, escritosSeg: Double?
    var conexoes: Int?                  // sockets abertos (só na aba Rede)
    var id: pid_t { pid }
}

struct TotaisMonitor: Sendable {
    var processos = 0
    var threads = 0
    var alheios = 0                     // de outro usuário
    var energia: Double = 0             // soma dos processos do Hugo (W)
    var discoLidoSeg: Double = 0, discoEscritoSeg: Double = 0
    var discoLeiturasSeg: Double = 0, discoEscritasSeg: Double = 0
    var discoLido: UInt64 = 0, discoEscrito: UInt64 = 0
}

struct AmostraMonitor: Sendable {
    var processos: [ProcessoMonitor] = []
    var totais = TotaisMonitor()
    /// O ps respondeu nesta leitura (processos do sistema com números).
    var comPS = false
    var lida = false
}

final class LeitorMonitor: @unchecked Sendable {
    private struct Antes { let inicio: UInt64; let cpuNs: UInt64; let lidos: UInt64; let escritos: UInt64; let energia: UInt64; let despertares: UInt64 }
    private var anterior: [pid_t: Antes] = [:]
    private var anteriorPS: [pid_t: (inicio: UInt64, cpu: Double)] = [:]
    private var discoAntes: (UInt64, UInt64, UInt64, UInt64, UInt64)?
    private var instante: UInt64 = 0
    private let base: (numer: UInt64, denom: UInt64) = {
        var tb = mach_timebase_info_data_t(); mach_timebase_info(&tb)
        return (UInt64(tb.numer), UInt64(tb.denom))
    }()

    private let trava = NSLock()
    private var _conexoes = false
    /// Contar sockets por processo (só com a aba Rede na frente).
    var contarConexoes: Bool {
        get { trava.lock(); defer { trava.unlock() }; return _conexoes }
        set { trava.lock(); _conexoes = newValue; trava.unlock() }
    }

    func ler() -> AmostraMonitor {
        let agora = DispatchTime.now().uptimeNanoseconds
        let dt = instante > 0 ? Double(agora &- instante) / 1e9 : 0
        let eu = getuid()
        let conexoes = contarConexoes
        let impedem = Self.pidsQueImpedemRepouso()
        let ps = Self.lerPS()

        var out = AmostraMonitor()
        out.comPS = !ps.isEmpty
        var novos: [pid_t: Antes] = [:]
        var novosPS: [pid_t: (inicio: UInt64, cpu: Double)] = [:]

        for k in Self.todos() {
            let pid = k.kp_proc.p_pid
            guard pid > 0 else { continue }
            let uid = k.kp_eproc.e_ucred.cr_uid
            let ini = k.kp_proc.p_starttime
            let inicioUs = UInt64(ini.tv_sec) * 1_000_000 + UInt64(ini.tv_usec)
            let caminho = Self.caminho(pid)
            var nome = caminho.isEmpty ? "" : (caminho as NSString).lastPathComponent
            if nome.isEmpty { nome = Self.comm(k) }

            var ru = rusage_info_v6()
            let okRU = withUnsafeMutablePointer(to: &ru) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V6, $0) }
            } == 0
            var p = ProcessoMonitor(pid: pid, pai: k.kp_eproc.e_ppid, uid: uid, nome: nome, caminho: caminho,
                                    inicio: Date(timeIntervalSince1970: Double(ini.tv_sec) + Double(ini.tv_usec) / 1e6),
                                    proprio: okRU)
            p.impedeRepouso = impedem.contains(pid)
            if okRU {
                let cpuNs = (ru.ri_user_time + ru.ri_system_time) * base.numer / base.denom
                let desp = ru.ri_interrupt_wkups + ru.ri_pkg_idle_wkups
                p.tempoCPU = Double(cpuNs) / 1e9
                p.memoria = ru.ri_phys_footprint
                p.residente = ru.ri_resident_size
                p.lidos = ru.ri_diskio_bytesread
                p.escritos = ru.ri_diskio_byteswritten
                var t = proc_taskinfo()
                if proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &t, Int32(MemoryLayout<proc_taskinfo>.size)) == Int32(MemoryLayout<proc_taskinfo>.size) {
                    p.threads = Int(t.pti_threadnum)
                }
                if let a = anterior[pid], a.inicio == inicioUs, dt > 0 {
                    p.cpu = Double(cpuNs &- min(cpuNs, a.cpuNs)) / 1e9 / dt
                    p.lidosSeg = Double(ru.ri_diskio_bytesread &- min(ru.ri_diskio_bytesread, a.lidos)) / dt
                    p.escritosSeg = Double(ru.ri_diskio_byteswritten &- min(ru.ri_diskio_byteswritten, a.escritos)) / dt
                    p.energia = Double(ru.ri_energy_nj &- min(ru.ri_energy_nj, a.energia)) / 1e9 / dt
                    p.despertares = Double(desp &- min(desp, a.despertares)) / dt
                    out.totais.energia += p.energia ?? 0
                }
                if conexoes { p.conexoes = Self.sockets(pid) }
                novos[pid] = Antes(inicio: inicioUs, cpuNs: cpuNs, lidos: ru.ri_diskio_bytesread,
                                   escritos: ru.ri_diskio_byteswritten, energia: ru.ri_energy_nj, despertares: desp)
            } else if let v = ps[pid] {
                p.tempoCPU = v.cpu
                p.memoria = v.rss
                p.residente = v.rss
                if let a = anteriorPS[pid], a.inicio == inicioUs, dt > 0 {
                    p.cpu = max(0, v.cpu - a.cpu) / dt
                }
                novosPS[pid] = (inicioUs, v.cpu)
            }
            if uid != eu { out.totais.alheios += 1 }
            out.processos.append(p)
        }
        anterior = novos
        anteriorPS = novosPS

        let (tarefas, threads) = Self.contagemSistema()
        out.totais.processos = tarefas > 0 ? tarefas : out.processos.count
        out.totais.threads = threads
        if let d = Self.disco() {
            out.totais.discoLido = d.0; out.totais.discoEscrito = d.1
            if let a = discoAntes, dt > 0 {
                out.totais.discoLidoSeg = Double(d.0 &- min(d.0, a.0)) / dt
                out.totais.discoEscritoSeg = Double(d.1 &- min(d.1, a.1)) / dt
                out.totais.discoLeiturasSeg = Double(d.2 &- min(d.2, a.2)) / dt
                out.totais.discoEscritasSeg = Double(d.3 &- min(d.3, a.3)) / dt
            }
            discoAntes = (d.0, d.1, d.2, d.3, 0)
        }
        out.lida = dt > 0
        instante = agora
        return out
    }

    // MARK: - Fontes

    /// Primeiro pid com este nome curto (capturas).
    static func pid(chamado nome: String) -> pid_t? {
        todos().first { comm($0) == nome }?.kp_proc.p_pid
    }

    private static func todos() -> [kinfo_proc] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var tam = 0
        guard sysctl(&mib, 4, nil, &tam, nil, 0) == 0, tam > 0 else { return [] }
        let passo = MemoryLayout<kinfo_proc>.stride
        var lista = [kinfo_proc](repeating: kinfo_proc(), count: tam / passo + 64)
        tam = lista.count * passo
        guard sysctl(&mib, 4, &lista, &tam, nil, 0) == 0 else { return [] }
        return Array(lista.prefix(tam / passo))
    }

    private static func caminho(_ pid: pid_t) -> String {
        var buf = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        return proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 ? buf.textoC : ""
    }

    private static func comm(_ k: kinfo_proc) -> String {
        var c = k.kp_proc.p_comm
        return withUnsafeBytes(of: &c) { b in
            String(decoding: b.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    /// Quantos sockets o processo tem abertos (só processos do Hugo).
    private static func sockets(_ pid: pid_t) -> Int? {
        let tam = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard tam > 0 else { return nil }
        let passo = MemoryLayout<proc_fdinfo>.stride
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(tam) / passo + 16)
        let lido = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, Int32(fds.count * passo))
        guard lido > 0 else { return nil }
        return fds.prefix(Int(lido) / passo).reduce(0) { $0 + ($1.proc_fdtype == UInt32(PROX_FDTYPE_SOCKET) ? 1 : 0) }
    }

    /// Processos com pedido ativo para o Mac não dormir (IOPM, sem privilégio).
    private static func pidsQueImpedemRepouso() -> Set<pid_t> {
        var d: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&d) == kIOReturnSuccess,
              let dic = d?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else { return [] }
        var r = Set<pid_t>()
        for (pid, lista) in dic {
            let tipos = lista.compactMap { $0[kIOPMAssertionTypeKey] as? String }
            if tipos.contains(where: { $0.contains("PreventUserIdleSystemSleep") || $0.contains("PreventSystemSleep")
                || $0.contains("NoIdleSleep") || $0.contains("PreventUserIdleDisplaySleep") || $0.contains("NoDisplaySleep") }) {
                r.insert(pid.int32Value)
            }
        }
        return r
    }

    /// Total de tarefas e threads do Mac (processor_set_statistics, sem privilégio).
    private static func contagemSistema() -> (Int, Int) {
        var pset: processor_set_name_t = 0
        guard processor_set_default(mach_host_self(), &pset) == KERN_SUCCESS else { return (0, 0) }
        defer { mach_port_deallocate(mach_task_self_, pset) }
        var info = processor_set_load_info()
        var n = mach_msg_type_number_t(MemoryLayout<processor_set_load_info>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(n)) {
                processor_set_statistics(pset, processor_set_flavor_t(PROCESSOR_SET_LOAD_INFO), $0, &n)
            }
        }
        return kr == KERN_SUCCESS ? (Int(info.task_count), Int(info.thread_count)) : (0, 0)
    }

    /// Disco: bytes e operações de leitura/escrita desde o boot (IORegistry, todos os discos).
    private static func disco() -> (UInt64, UInt64, UInt64, UInt64)? {
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &it) == kIOReturnSuccess else { return nil }
        defer { IOObjectRelease(it) }
        var r: (UInt64, UInt64, UInt64, UInt64) = (0, 0, 0, 0)
        var s = IOIteratorNext(it)
        while s != 0 {
            if let d = IORegistryEntryCreateCFProperty(s, "Statistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any] {
                func v(_ k: String) -> UInt64 { (d[k] as? NSNumber)?.uint64Value ?? 0 }
                r.0 &+= v("Bytes (Read)"); r.1 &+= v("Bytes (Write)")
                r.2 &+= v("Operations (Read)"); r.3 &+= v("Operations (Write)")
            }
            IOObjectRelease(s)
            s = IOIteratorNext(it)
        }
        return r
    }

    // MARK: - ps (processos de outro usuário)

    /// `/bin/ps` é setuid root: é o único jeito sem privilégio de ver tempo de CPU e memória dos
    /// processos do sistema. Roda pelo `Processo.rodar` (drena a saída, mata se travar) e esta
    /// fila espera a resposta — a fila é a do amostrador, nunca a main.
    private static func lerPS() -> [pid_t: (cpu: Double, rss: UInt64)] {
        let caixa = CaixaPS()
        let sinal = DispatchSemaphore(value: 0)
        Task.detached(priority: .utility) {
            let r = await Processo.rodar("/bin/ps", ["-axo", "pid=,time=,rss="], tempoMax: 3)
            caixa.guardar(r.ok ? r.saida : "")
            sinal.signal()
        }
        guard sinal.wait(timeout: .now() + 4) == .success else { return [:] }
        var out: [pid_t: (cpu: Double, rss: UInt64)] = [:]
        for linha in caixa.texto.split(separator: "\n") {
            let c = linha.split(separator: " ", omittingEmptySubsequences: true)
            guard c.count >= 3, let pid = pid_t(c[0]), let rss = UInt64(c[2]) else { continue }
            out[pid] = (tempoPS(c[1]), rss * 1024)
        }
        return out
    }

    /// "[dd-][hh:]mm:ss.cc" → segundos.
    static func tempoPS(_ s: Substring) -> Double {
        var dias = 0.0
        var resto = s
        if let i = s.firstIndex(of: "-") { dias = Double(s[..<i]) ?? 0; resto = s[s.index(after: i)...] }
        let partes = resto.split(separator: ":").map { Double($0) ?? 0 }
        let seg = partes.reduce(0) { $0 * 60 + $1 }
        return dias * 86400 + seg
    }

    private final class CaixaPS: @unchecked Sendable {
        private let trava = NSLock()
        private var _texto = ""
        func guardar(_ t: String) { trava.lock(); _texto = t; trava.unlock() }
        var texto: String { trava.lock(); defer { trava.unlock() }; return _texto }
    }
}

