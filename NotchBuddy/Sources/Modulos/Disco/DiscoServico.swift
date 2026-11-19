import Foundation
import Observation

// Dados do módulo Disco. Espaço do volume: um amostrador de 30 s que só roda com tela
// assinando. Varredura e envio para a Lixeira: só quando o Hugo pede, fora da main.

@Observable @MainActor
final class DiscoServico {
    static let shared = DiscoServico()

    enum Estado: Equatable {
        case nunca
        case varrendo(String)
        case pronto(Date)
    }

    var volume: AmostraVolume?
    var estado: Estado = .nunca
    var acesso: AcessoVarredura = .limitado
    var itens: [ItemLimpeza] = []
    var selecionados: Set<String> = []
    /// Lista revalidada esperando o clique de confirmação (nil = sem confirmação aberta).
    var confirmacao: [ItemLimpeza]?
    var retiradosNaRevalidacao: [Retirado] = []
    var preparando = false
    var movendo = false
    var ultimo: ResultadoLimpeza?

    @ObservationIgnored private var leitorVolume: Amostrador<AmostraVolume?>!
    @ObservationIgnored private var tarefa: Task<Void, Never>?

    private init() {
        leitorVolume = Amostrador("disco.volume", intervalo: 30,
                                  ler: { LeitorVolume.ler() },
                                  entregar: { [weak self] v in self?.volume = v })
        acesso = AcessoVarredura.atual()
    }

    func assinar(_ quem: String) {
        leitorVolume.assinar(quem)
        acesso = AcessoVarredura.atual()
    }
    func soltar(_ quem: String) { leitorVolume.soltar(quem) }

    func parar() {
        tarefa?.cancel()
        tarefa = nil
    }

    // MARK: Totais

    /// Soma do que está marcado como seguro (o número da ilha).
    var recuperavel: Int64 { itens.filter { $0.nivel == .seguro }.reduce(0) { $0 + $1.bytes } }
    var selecionadosItens: [ItemLimpeza] { itens.filter { selecionados.contains($0.id) } }
    var totalSelecionado: Int64 { selecionadosItens.reduce(0) { $0 + $1.bytes } }
    var varrendo: Bool { if case .varrendo = estado { return true }; return false }

    // MARK: Ações

    func procurar() {
        guard !varrendo, !movendo else { return }
        acesso = AcessoVarredura.atual()
        let acesso = self.acesso
        estado = .varrendo("Procurando…")
        confirmacao = nil
        tarefa = Task.detached(priority: .utility) { [weak self] in
            let itens = await Varredura.executar(acesso: acesso) { texto in
                await MainActor.run {
                    let s = DiscoServico.shared
                    if s.varrendo { s.estado = .varrendo(texto) }
                }
            }
            await MainActor.run { [weak self] in
                guard let self, !Task.isCancelled else { return }
                self.itens = itens
                self.selecionados = Set(itens.filter { $0.nivel == .seguro }.map(\.id))
                self.estado = .pronto(Date())
                self.volume = LeitorVolume.ler()
            }
        }
    }

    func alternar(_ id: String) {
        if selecionados.contains(id) { selecionados.remove(id) } else { selecionados.insert(id) }
    }

    /// Abre a confirmação: revalida o que está marcado (fora da main) e mostra só o que ainda vale.
    func prepararConfirmacao() {
        guard !preparando, !movendo else { return }
        let alvo = selecionadosItens
        guard !alvo.isEmpty else { return }
        let acesso = self.acesso
        preparando = true
        Task.detached(priority: .userInitiated) { [weak self] in
            let r = Lixeira.revalidar(alvo, acesso: acesso)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.preparando = false
                self.retiradosNaRevalidacao = r.retirados
                // O que mudou sai da lista também.
                let validos = Dictionary(uniqueKeysWithValues: r.validos.map { ($0.id, $0) })
                let saiu = Set(alvo.map(\.id)).subtracting(validos.keys)
                self.itens = self.itens.compactMap { saiu.contains($0.id) ? nil : (validos[$0.id] ?? $0) }
                self.selecionados.subtract(saiu)
                self.confirmacao = r.validos.isEmpty ? nil : r.validos
            }
        }
    }

    func cancelarConfirmacao() {
        confirmacao = nil
        retiradosNaRevalidacao = []
    }

    /// Clique explícito do Hugo em "Mover para a Lixeira".
    func confirmarMover() {
        guard let alvo = confirmacao, !movendo else { return }
        let acesso = self.acesso
        movendo = true
        Task.detached(priority: .userInitiated) { [weak self] in
            let r = Lixeira.mover(alvo, acesso: acesso)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.movendo = false
                self.confirmacao = nil
                self.ultimo = r
                let foram = Set(r.movidos.map(\.id))
                self.itens.removeAll { foram.contains($0.id) }
                self.selecionados.subtract(foram)
                self.volume = r.depois ?? LeitorVolume.ler()
                Log.de("disco").info("Lixeira: \(r.movidos.count) itens, \(r.bytesMovidos) bytes; falhas \(r.falhas.count)")
            }
        }
    }
}
