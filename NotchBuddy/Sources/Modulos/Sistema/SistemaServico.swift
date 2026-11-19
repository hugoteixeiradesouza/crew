import AppKit
import Observation

// Dados do módulo Sistema. Três amostradores com ritmos diferentes; nenhum roda sem uma tela
// assinando (aba na ilha ou página na Central). Ver docs/ARQUITETURA.md §7.

@Observable @MainActor
final class SistemaServico {
    static let shared = SistemaServico()

    var cpu = AmostraCPU()
    /// Uso total de CPU, um ponto por leitura (o mais novo no fim).
    var historicoCPU: [Double] = []
    var memoria = AmostraMemoria()
    var rede = AmostraRede()
    var gpu: Double?
    var temperatura: Double?
    var processos: [InfoProcesso] = []
    var disco = AmostraDisco()
    var bateria: AmostraBateria?
    var carga = AmostraCarga()
    /// Monitor de atividade: todos os processos (só lido com o monitor na tela).
    var monitor = AmostraMonitor()
    /// Apps abertos (nome e ícone de verdade no monitor), atualizado junto com o monitor.
    var apps: [pid_t: NSRunningApplication] = [:]

    static let pontosHistorico = 90

    /// Partes que uma tela pode assinar (o indicador da ilha fechada só precisa de uma).
    enum Parte: CaseIterable { case rapido, temperatura, processos, lento, monitor }
    /// O que a aba e a Central assinam por padrão (o monitor só quando aberto).
    static let partesPadrao: Set<Parte> = [.rapido, .temperatura, .processos, .lento]

    @ObservationIgnored private var rapido: Amostrador<RapidoValor>!
    @ObservationIgnored private var temp: Amostrador<Double?>!
    @ObservationIgnored private var procs: Amostrador<[InfoProcesso]>!
    @ObservationIgnored private var lento: Amostrador<LentoValor>!
    @ObservationIgnored private var mon: Amostrador<AmostraMonitor>!
    @ObservationIgnored private let leitorMonitor = LeitorMonitor()

    private struct RapidoValor: Sendable { let cpu: AmostraCPU; let mem: AmostraMemoria; let rede: AmostraRede; let gpu: Double? }
    private struct LentoValor: Sendable { let disco: AmostraDisco; let bateria: AmostraBateria?; let carga: AmostraCarga }

    private init() {
        let cpu = LeitorCPU(), rede = LeitorRede(), leitorProcs = LeitorProcessos()
        rapido = Amostrador("sistema.rapido", intervalo: 1,
            ler: { RapidoValor(cpu: cpu.ler(), mem: LeitorMemoria.ler(), rede: rede.ler(), gpu: LeitorGPU.ler()) },
            entregar: { [weak self] v in
                guard let self else { return }
                self.cpu = v.cpu; self.memoria = v.mem; self.rede = v.rede; self.gpu = v.gpu
                self.historicoCPU.append(v.cpu.total)
                if self.historicoCPU.count > Self.pontosHistorico { self.historicoCPU.removeFirst(self.historicoCPU.count - Self.pontosHistorico) }
            })
        temp = Amostrador("sistema.temperatura", intervalo: 3,
            ler: { LeitorTemperatura.ler() },
            entregar: { [weak self] v in self?.temperatura = v })
        procs = Amostrador("sistema.processos", intervalo: 2,
            ler: { leitorProcs.ler() },
            entregar: { [weak self] v in self?.processos = v })
        lento = Amostrador("sistema.lento", intervalo: 10,
            ler: { LentoValor(disco: LeitorDisco.ler(), bateria: LeitorBateria.ler(), carga: LeitorCarga.ler()) },
            entregar: { [weak self] v in self?.disco = v.disco; self?.bateria = v.bateria; self?.carga = v.carga })
        let lm = leitorMonitor
        mon = Amostrador("sistema.monitor", intervalo: 2,
            ler: { lm.ler() },
            entregar: { [weak self] v in
                guard let self else { return }
                var apps: [pid_t: NSRunningApplication] = [:]
                for a in NSWorkspace.shared.runningApplications { apps[a.processIdentifier] = a }
                self.apps = apps
                self.monitor = v
            })
    }

    /// O monitor está na aba Rede: conta as conexões de cada processo (só aí — custa mais).
    func monitorContaConexoes(_ sim: Bool) { leitorMonitor.contarConexoes = sim }

    @ObservationIgnored private var usuarios: [uid_t: String] = [:]
    func nomeUsuario(_ uid: uid_t) -> String {
        if let n = usuarios[uid] { return n }
        let n = getpwuid(uid).map { String(cString: $0.pointee.pw_name) } ?? "\(uid)"
        usuarios[uid] = n
        return n
    }

    /// Uma tela começou a mostrar o Sistema (todas as partes, ou só as que ela usa).
    func assinar(_ quem: String, _ partes: Set<Parte> = SistemaServico.partesPadrao) {
        for p in partes { amostrador(p)(true, quem) }
    }

    /// A tela saiu: se ninguém mais olha, os timers param.
    func soltar(_ quem: String, _ partes: Set<Parte> = SistemaServico.partesPadrao) {
        for p in partes { amostrador(p)(false, quem) }
    }

    private func amostrador(_ p: Parte) -> (Bool, String) -> Void {
        switch p {
        case .rapido:      return { $0 ? self.rapido.assinar($1) : self.rapido.soltar($1) }
        case .temperatura: return { $0 ? self.temp.assinar($1) : self.temp.soltar($1) }
        case .processos:   return { $0 ? self.procs.assinar($1) : self.procs.soltar($1) }
        case .lento:       return { $0 ? self.lento.assinar($1) : self.lento.soltar($1) }
        case .monitor:     return { $0 ? self.mon.assinar($1) : self.mon.soltar($1) }
        }
    }
}
