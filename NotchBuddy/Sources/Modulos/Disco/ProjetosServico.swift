import Foundation
import Observation

// Projetos parados: varre só quando o Hugo pede (botão), fora da main. Mover = Lixeira, com
// revalidação antes de confirmar e de novo imediatamente antes de cada pasta sair.

enum EstadoBusca: Equatable {
    case nunca
    case procurando(String)
    case pronto(Date)
    var procurando: Bool { if case .procurando = self { return true }; return false }
}

@Observable @MainActor
final class ProjetosServico {
    static let shared = ProjetosServico()
    static let opcoesMeses = [1, 3, 6, 12]

    var meses: Int = 3 {
        didSet { Ajustes.definir("disco", "projetos.meses", meses) }
    }
    var estado: EstadoBusca = .nunca
    var projetos: [ProjetoParado] = []
    var escondidos = EscondidosProjetos()
    /// Caminhos dos artefatos marcados.
    var selecionados: Set<String> = []
    var confirmacao: [ProjetoParado]?
    var retirados: [Retirado] = []
    var preparando = false
    var movendo = false
    var ultimo: ResultadoMover?
    /// Meses usados na última varredura (a lista vale para eles).
    var mesesDaLista = 3

    @ObservationIgnored private var tarefa: Task<Void, Never>?

    private init() {
        let m = Int(Ajustes.double("disco", "projetos.meses", padrao: 3))
        meses = Self.opcoesMeses.contains(m) ? m : 3
    }

    var total: Int64 { projetos.reduce(0) { $0 + $1.bytes } }
    var totalSelecionado: Int64 {
        projetos.flatMap(\.artefatos).filter { selecionados.contains($0.id) }.reduce(0) { $0 + $1.bytes }
    }
    var quantosSelecionados: Int { projetos.flatMap(\.artefatos).filter { selecionados.contains($0.id) }.count }

    func parar() {
        tarefa?.cancel()
        tarefa = nil
        if estado.procurando { estado = .nunca }
    }

    func procurar() {
        guard !estado.procurando, !movendo else { return }
        let acesso = AcessoVarredura.atual()
        let meses = self.meses
        estado = .procurando("Procurando projetos…")
        confirmacao = nil
        tarefa = Task.detached(priority: .utility) { [weak self] in
            let r = await VarreduraProjetos.executar(meses: meses, acesso: acesso) { texto in
                await MainActor.run {
                    let s = ProjetosServico.shared
                    if s.estado.procurando { s.estado = .procurando(texto) }
                }
            }
            await MainActor.run { [weak self] in
                guard let self, !Task.isCancelled else { return }
                self.projetos = r.projetos
                self.escondidos = r.escondidos
                self.mesesDaLista = meses
                self.selecionados = Set(r.projetos.flatMap(\.artefatos).filter(\.marcadoPorPadrao).map(\.id))
                self.estado = .pronto(Date())
                Log.de("disco").info("Projetos parados: \(r.projetos.count) projetos, \(r.escondidos.total) escondidos, \(r.pastasLidas) pastas")
            }
        }
    }

    func alternar(_ id: String) {
        if selecionados.contains(id) { selecionados.remove(id) } else { selecionados.insert(id) }
    }

    func alternarProjeto(_ p: ProjetoParado) {
        let ids = Set(p.artefatos.map(\.id))
        if ids.isSubset(of: selecionados) { selecionados.subtract(ids) } else { selecionados.formUnion(ids) }
    }

    /// Só o que está marcado, projeto a projeto.
    private var marcados: [ProjetoParado] {
        projetos.compactMap { p in
            var q = p
            q.artefatos = p.artefatos.filter { selecionados.contains($0.id) }
            return q.artefatos.isEmpty ? nil : q
        }
    }

    func prepararConfirmacao() {
        guard !preparando, !movendo else { return }
        let alvo = marcados
        guard !alvo.isEmpty else { return }
        let acesso = AcessoVarredura.atual()
        preparando = true
        Task.detached(priority: .userInitiated) { [weak self] in
            let (validos, retirados) = await VarreduraProjetos.revalidar(alvo, acesso: acesso)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.preparando = false
                self.retirados = retirados
                let ficam = Set(validos.flatMap(\.artefatos).map(\.id))
                let sairam = Set(alvo.flatMap(\.artefatos).map(\.id)).subtracting(ficam)
                self.selecionados.subtract(sairam)
                self.confirmacao = validos.isEmpty ? nil : validos
            }
        }
    }

    func cancelarConfirmacao() {
        confirmacao = nil
        retirados = []
    }

    /// Clique explícito do Hugo em "Mover para a Lixeira".
    func confirmarMover() {
        guard let alvo = confirmacao, !movendo else { return }
        let acesso = AcessoVarredura.atual()
        movendo = true
        Task.detached(priority: .userInitiated) { [weak self] in
            let cwds = AtividadeProjeto.pastasDeTrabalho()
            var porCaminho: [String: (ArtefatoProjeto, ProjetoParado)] = [:]
            for p in alvo { for a in p.artefatos { porCaminho[a.caminho] = (a, p) } }
            let alvos = alvo.flatMap { p in
                p.artefatos.map { AlvoLixeira(nome: "\(p.nome)/\($0.pastaRelativa)", caminho: $0.caminho, bytes: $0.bytes) }
            }
            let r = LixeiraCaminhos.mover(alvos) { a in
                guard let (art, proj) = porCaminho[a.caminho] else { return "Não está mais na lista." }
                return VarreduraProjetos.aindaPodeSair(art, projeto: proj, cwds: cwds, acesso: acesso)
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.movendo = false
                self.confirmacao = nil
                self.ultimo = r
                let foram = Set(r.movidos.map(\.caminho))
                self.selecionados.subtract(foram)
                self.projetos = self.projetos.compactMap { p in
                    var q = p
                    q.artefatos.removeAll { foram.contains($0.caminho) }
                    return q.artefatos.isEmpty ? nil : q
                }
                DiscoServico.shared.volume = LeitorVolume.ler()
                Log.de("disco").info("Projetos → Lixeira: \(r.movidos.count) pastas, \(r.bytes) bytes; falhas \(r.falhas.count)")
            }
        }
    }
}
