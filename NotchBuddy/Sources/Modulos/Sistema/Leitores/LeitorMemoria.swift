import Foundation

struct AmostraMemoria: Sendable {
    var total: UInt64 = 0
    var usada: UInt64 = 0
    var app: UInt64 = 0
    var fixa: UInt64 = 0        // wired
    var comprimida: UInt64 = 0
    var swapUsado: UInt64 = 0
    /// 1 normal, 2 atenção, 4 crítica (kern.memorystatus_vm_pressure_level)
    var pressao: Int = 1
    var fracao: Double { total > 0 ? Double(usada) / Double(total) : 0 }
}

enum LeitorMemoria {
    /// Mesma conta do Monitor de Atividade.
    static func ler() -> AmostraMemoria {
        var m = AmostraMemoria()
        m.total = ProcessInfo.processInfo.physicalMemory
        var vm = vm_statistics64_data_t()
        var n = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let r = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(n)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &n) }
        }
        if r == KERN_SUCCESS {
            var pgTam: vm_size_t = 0
            host_page_size(mach_host_self(), &pgTam)
            let pg = UInt64(pgTam)
            let ativa = UInt64(vm.active_count) * pg, inativa = UInt64(vm.inactive_count) * pg
            let especulativa = UInt64(vm.speculative_count) * pg, fixa = UInt64(vm.wire_count) * pg
            let comprimida = UInt64(vm.compressor_page_count) * pg, purgavel = UInt64(vm.purgeable_count) * pg
            let externa = UInt64(vm.external_page_count) * pg
            let usada = ativa + inativa + especulativa + fixa + comprimida
            m.usada = usada > purgavel + externa ? usada - purgavel - externa : usada
            m.fixa = fixa
            m.comprimida = comprimida
            m.app = m.usada > fixa + comprimida ? m.usada - fixa - comprimida : 0
        }
        var swap = xsw_usage()
        var tam = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &tam, nil, 0) == 0 { m.swapUsado = swap.xsu_used }
        var nivel: Int32 = 1
        tam = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &nivel, &tam, nil, 0) == 0 { m.pressao = Int(nivel) }
        return m
    }
}
