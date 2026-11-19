import Foundation
import Observation

// Simuladores do iOS desligados. Lista só no botão; apagar é definitivo (`simctl delete`) e só com clique na confirmação.

@Observable @MainActor
final class SimuladoresServico {
    static let shared = SimuladoresServico()

    /// Xcode instalado? Lido do disco quando a página abre.
    var temXcode = false
    var estado: EstadoBusca = .nunca
    /// Nil depois de procurar = o `simctl` não respondeu.
    var lista: [Simulador]?
    var selecionados: Set<String> = []
    var confirmacao: [Simulador]?
    var apagando = false
    var ultimo: (apagados: [Simulador], falhas: [Retirado], quando: Date)?

    @ObservationIgnored private var tarefa: Task<Void, Never>?

    private init() { temXcode = Simuladores.temXcode }

    var total: Int64 { (lista ?? []).reduce(0) { $0 + $1.bytes } }
    var selecionadosItens: [Simulador] { (lista ?? []).filter { selecionados.contains($0.id) } }

    func parar() {
        tarefa?.cancel()
        tarefa = nil
        if estado.procurando { estado = .nunca }
    }

    /// Página abriu: só confere o Xcode (lido do disco). Listar fica no botão — o `simctl` sobe o
    /// serviço do Simulador, que fica rodando depois.
    func aoAparecer() {
        temXcode = Simuladores.temXcode
    }

    func listar() {
        guard temXcode, !estado.procurando, !apagando else { return }
        estado = .procurando("Perguntando ao simctl…")
        confirmacao = nil
        tarefa = Task.detached(priority: .utility) { [weak self] in
            let l = await Simuladores.listar(medir: true)
            await MainActor.run { [weak self] in
                guard let self, !Task.isCancelled else { return }
                self.lista = l
                // Apagar é definitivo: nada vem marcado.
                self.selecionados = []
                self.estado = .pronto(Date())
            }
        }
    }

    func alternar(_ id: String) {
        if selecionados.contains(id) { selecionados.remove(id) } else { selecionados.insert(id) }
    }

    func prepararConfirmacao() {
        let alvo = selecionadosItens
        confirmacao = alvo.isEmpty ? nil : alvo
    }

    func cancelarConfirmacao() { confirmacao = nil }

    /// Clique explícito do Hugo em "Apagar de vez".
    func confirmarApagar() {
        guard let alvo = confirmacao, !apagando else { return }
        apagando = true
        Task.detached(priority: .userInitiated) { [weak self] in
            let r = await Simuladores.apagar(alvo)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.apagando = false
                self.confirmacao = nil
                self.ultimo = (r.apagados, r.falhas, Date())
                let foram = Set(r.apagados.map(\.id))
                self.lista?.removeAll { foram.contains($0.id) }
                self.selecionados.subtract(foram)
                DiscoServico.shared.volume = LeitorVolume.ler()
                Log.de("disco").info("Simuladores apagados: \(r.apagados.count); falhas \(r.falhas.count)")
            }
        }
    }
}
