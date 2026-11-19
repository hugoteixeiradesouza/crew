import Foundation
import Darwin

// MARK: - Encerrar processo (só com clique e confirmação do Hugo)

enum EncerrarProcesso {
    /// Processos do Hugo que derrubam a sessão inteira se forem encerrados.
    static let protegidos: Set<String> = ["loginwindow", "launchd"]

    /// nil = pode; senão, o motivo de não poder (aparece no lugar do botão).
    static func motivoBloqueio(_ p: ProcessoMonitor) -> String? {
        if p.pid == getpid() { return "É o próprio Crew." }
        if p.uid != getuid() {
            return p.uid == 0 ? "Processo do sistema (root): só com senha de administrador."
                              : "Processo de outro usuário do sistema: só com senha de administrador."
        }
        if protegidos.contains(p.nome) { return "Encerrar o \(p.nome) desconecta a sua sessão." }
        return nil
    }

    /// Manda o sinal se o pid ainda é o mesmo processo (mesmo início e dono) — pid pode ser
    /// reaproveitado entre a leitura e o clique. Retorna o erro, ou nil se deu certo.
    static func enviar(_ p: ProcessoMonitor, forcar: Bool) -> String? {
        if let m = motivoBloqueio(p) { return m }
        var k = kinfo_proc()
        var tam = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, p.pid]
        guard sysctl(&mib, 4, &k, &tam, nil, 0) == 0, tam > 0 else { return "O processo já tinha terminado." }
        let ini = k.kp_proc.p_starttime
        let inicio = Date(timeIntervalSince1970: Double(ini.tv_sec) + Double(ini.tv_usec) / 1e6)
        guard abs(inicio.timeIntervalSince(p.inicio)) < 0.001, k.kp_eproc.e_ucred.cr_uid == p.uid else {
            return "O processo já tinha terminado (o número foi reaproveitado por outro)."
        }
        if kill(p.pid, forcar ? SIGKILL : SIGTERM) != 0 {
            return errno == EPERM ? "O macOS não deixou (sem permissão)." : "Não deu: \(String(cString: strerror(errno)))."
        }
        Log.de("sistema").info("monitor: \(forcar ? "SIGKILL" : "SIGTERM", privacy: .public) pid \(p.pid) \(p.nome, privacy: .public)")
        return nil
    }
}
