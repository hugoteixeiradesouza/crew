import Foundation
import Observation

// Arquivos grandes e duplicados nas pastas pessoais. Arquivo pessoal: nunca marcado por padrão,
// nunca na limpeza de um clique da ilha. Varre só no botão, fora da main.

@Observable @MainActor
final class ArquivosServico {
    static let shared = ArquivosServico()

    static let opcoesMB = [50, 100, 250, 500, 1000]
    /// 0 = qualquer.
    static let opcoesMeses = [0, 1, 3, 6, 12]

    // MARK: Arquivos grandes

    var minimoMB = 100 { didSet { Ajustes.definir("disco", "grandes.minimoMB", minimoMB) } }
    var mesesParado = 0 { didSet { Ajustes.definir("disco", "grandes.meses", mesesParado) } }
    var estado: EstadoBusca = .nunca
    /// Tudo ≥ o menor tamanho oferecido; os filtros são aplicados em memória.
    var todos: [ArquivoGrande] = []
    var vistos = 0
    var selecionados: Set<String> = []
    var confirmacao: [ArquivoGrande]?
    var retirados: [Retirado] = []
    var movendo = false
    var ultimo: ResultadoMover?

    // MARK: Duplicados

    enum EstadoDup: Equatable {
        case nunca
        case rodando(etapa: String, feito: Int, total: Int)
        case cancelado
        case pronto(Date)
        var rodando: Bool { if case .rodando = self { return true }; return false }
    }
    var estadoDup: EstadoDup = .nunca
    var grupos: [GrupoDuplicado] = []
    /// Cópia a manter por grupo (começa na sugestão).
    var manter: [String: String] = [:]
    /// Grupos que o Hugo incluiu (nenhum por padrão).
    var incluidos: Set<String> = []
    var confirmacaoDup: [(grupo: GrupoDuplicado, manter: String, sair: [String])]?
    var retiradosDup: [Retirado] = []
    var preparandoDup = false
    var movendoDup = false
    var ultimoDup: ResultadoMover?

    @ObservationIgnored private var tarefa: Task<Void, Never>?
    @ObservationIgnored private var tarefaDup: Task<Void, Never>?

    private init() {
        let mb = Int(Ajustes.double("disco", "grandes.minimoMB", padrao: 100))
        minimoMB = Self.opcoesMB.contains(mb) ? mb : 100
        let m = Int(Ajustes.double("disco", "grandes.meses", padrao: 0))
        mesesParado = Self.opcoesMeses.contains(m) ? m : 0
    }

    func parar() {
        tarefa?.cancel(); tarefa = nil
        tarefaDup?.cancel(); tarefaDup = nil
        if estado.procurando { estado = .nunca }
        if estadoDup.rodando { estadoDup = .cancelado }
    }

    var filtrados: [ArquivoGrande] {
        let min = Int64(minimoMB) * 1_000_000
        let corte = mesesParado == 0 ? Date.distantFuture
            : (Calendar.current.date(byAdding: .month, value: -mesesParado, to: Date()) ?? Date())
        return todos.filter { $0.bytes >= min && $0.ultimoUso <= corte }
    }
    var selecionadosItens: [ArquivoGrande] { filtrados.filter { selecionados.contains($0.id) } }
    var totalSelecionado: Int64 { selecionadosItens.reduce(0) { $0 + $1.bytes } }

    func procurar() {
        guard !estado.procurando, !movendo else { return }
        let acesso = AcessoVarredura.atual()
        let minimo = Int64(Self.opcoesMB.min() ?? 50) * 1_000_000
        estado = .procurando("Procurando arquivos grandes…")
        confirmacao = nil
        tarefa = Task.detached(priority: .utility) { [weak self] in
            let r = VarreduraArquivos.executar(minimo: minimo, diasParado: 0, acesso: acesso)
            await MainActor.run { [weak self] in
                guard let self, !Task.isCancelled else { return }
                self.todos = r.arquivos
                self.vistos = r.vistos
                self.selecionados = []
                self.estado = .pronto(Date())
            }
        }
    }

    func alternar(_ id: String) {
        if selecionados.contains(id) { selecionados.remove(id) } else { selecionados.insert(id) }
    }

    /// Revalida (existe, mesmo tamanho, política ainda permite) e abre a confirmação.
    func prepararConfirmacao() {
        let alvo = selecionadosItens
        guard !alvo.isEmpty, !movendo else { return }
        let acesso = AcessoVarredura.atual()
        var validos: [ArquivoGrande] = []
        var fora: [Retirado] = []
        var sairam: Set<String> = []
        for a in alvo {
            let tamanho = (try? FileManager.default.attributesOfItem(atPath: a.caminho))?[.size] as? NSNumber
            if let m = PoliticaArquivos.motivoRecusa(URL(fileURLWithPath: a.caminho), acesso: acesso) {
                fora.append(Retirado(nome: a.nome, motivo: m))
                sairam.insert(a.id)
            } else if tamanho == nil {
                fora.append(Retirado(nome: a.nome, motivo: "Não existe mais."))
                sairam.insert(a.id)
            } else {
                validos.append(a)
            }
        }
        retirados = fora
        selecionados.subtract(sairam)
        todos.removeAll { sairam.contains($0.id) }
        confirmacao = validos.isEmpty ? nil : validos
    }

    func cancelarConfirmacao() { confirmacao = nil; retirados = [] }

    func confirmarMover() {
        guard let alvo = confirmacao, !movendo else { return }
        let acesso = AcessoVarredura.atual()
        movendo = true
        Task.detached(priority: .userInitiated) { [weak self] in
            let r = LixeiraCaminhos.mover(alvo.map { AlvoLixeira(nome: $0.nome, caminho: $0.caminho, bytes: $0.bytes) }) {
                PoliticaArquivos.motivoRecusa(URL(fileURLWithPath: $0.caminho), acesso: acesso)
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.movendo = false
                self.confirmacao = nil
                self.ultimo = r
                let foram = Set(r.movidos.map(\.caminho))
                self.todos.removeAll { foram.contains($0.caminho) }
                self.selecionados.subtract(foram)
                self.grupos = self.grupos.compactMap { Self.semCaminhos($0, foram) }
                DiscoServico.shared.volume = LeitorVolume.ler()
                Log.de("disco").info("Arquivos grandes → Lixeira: \(r.movidos.count), \(r.bytes) bytes; falhas \(r.falhas.count)")
            }
        }
    }

    // MARK: Duplicados

    var recuperavelDup: Int64 { grupos.reduce(0) { $0 + $1.recuperavel } }
    var totalIncluidoDup: Int64 { grupos.filter { incluidos.contains($0.id) }.reduce(0) { $0 + $1.recuperavel } }

    func procurarDuplicados() {
        guard !estadoDup.rodando, !movendoDup else { return }
        let acesso = AcessoVarredura.atual()
        estadoDup = .rodando(etapa: "Listando arquivos…", feito: 0, total: 0)
        confirmacaoDup = nil
        tarefaDup = Task.detached(priority: .utility) { [weak self] in
            let g = await Duplicados.executar(acesso: acesso) { p in
                await MainActor.run {
                    let s = ArquivosServico.shared
                    if s.estadoDup.rodando { s.estadoDup = .rodando(etapa: p.etapa, feito: p.feito, total: p.total) }
                }
            }
            let cancelado = Task.isCancelled
            await MainActor.run { [weak self] in
                guard let self else { return }
                if cancelado { self.estadoDup = .cancelado; return }
                self.grupos = g
                self.manter = Dictionary(uniqueKeysWithValues: g.map { ($0.id, $0.sugestao) })
                self.incluidos = []
                self.estadoDup = .pronto(Date())
                Log.de("disco").info("Duplicados: \(g.count) grupos")
            }
        }
    }

    func cancelarDuplicados() {
        tarefaDup?.cancel()
        tarefaDup = nil
        estadoDup = .cancelado
    }

    func alternarGrupo(_ id: String) {
        if incluidos.contains(id) { incluidos.remove(id) } else { incluidos.insert(id) }
    }

    /// Revalida cada grupo incluído: a cópia que fica ainda existe; as que saem não mudaram
    /// (mesma data e tamanho) e ainda batem com a que fica no início e no fim.
    func prepararConfirmacaoDup() {
        guard !preparandoDup, !movendoDup else { return }
        let alvo = grupos.filter { incluidos.contains($0.id) }.map { ($0, manter[$0.id] ?? $0.sugestao) }
        guard !alvo.isEmpty else { return }
        let acesso = AcessoVarredura.atual()
        preparandoDup = true
        Task.detached(priority: .userInitiated) { [weak self] in
            var ok: [(grupo: GrupoDuplicado, manter: String, sair: [String])] = []
            var fora: [Retirado] = []
            for (g, fica) in alvo {
                let nome = (fica as NSString).lastPathComponent
                guard Self.inalterado(fica, g), let amostraFica = Self.amostra(fica) else {
                    fora.append(Retirado(nome: nome, motivo: "A cópia que fica mudou ou sumiu — grupo fora."))
                    continue
                }
                var sair: [String] = []
                for c in g.caminhos where c != fica {
                    if let m = PoliticaArquivos.motivoRecusa(URL(fileURLWithPath: c), acesso: acesso) {
                        fora.append(Retirado(nome: (c as NSString).lastPathComponent, motivo: m))
                    } else if !Self.inalterado(c, g) || Self.amostra(c) != amostraFica {
                        fora.append(Retirado(nome: (c as NSString).lastPathComponent, motivo: "Mudou desde a comparação."))
                    } else {
                        sair.append(c)
                    }
                }
                if !sair.isEmpty { ok.append((g, fica, sair)) }
            }
            let validos = ok
            let retirados = fora
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.preparandoDup = false
                self.retiradosDup = retirados
                self.confirmacaoDup = validos.isEmpty ? nil : validos
            }
        }
    }

    func cancelarConfirmacaoDup() { confirmacaoDup = nil; retiradosDup = [] }

    func confirmarMoverDup() {
        guard let alvo = confirmacaoDup, !movendoDup else { return }
        let acesso = AcessoVarredura.atual()
        movendoDup = true
        let pares = alvo.flatMap { item in
            item.sair.map { (AlvoLixeira(nome: (($0 as NSString).lastPathComponent), caminho: $0, bytes: item.grupo.bytes), item.manter) }
        }
        Task.detached(priority: .userInitiated) { [weak self] in
            let fica = Dictionary(pares.map { ($0.0.caminho, $0.1) }, uniquingKeysWith: { a, _ in a })
            let r = LixeiraCaminhos.mover(pares.map(\.0)) { a in
                // A cópia que fica tem de continuar lá, sempre.
                guard let k = fica[a.caminho], existeSemSeguir(URL(fileURLWithPath: k)) else {
                    return "A cópia que fica sumiu — esta não sai."
                }
                return PoliticaArquivos.motivoRecusa(URL(fileURLWithPath: a.caminho), acesso: acesso)
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.movendoDup = false
                self.confirmacaoDup = nil
                self.ultimoDup = r
                let foram = Set(r.movidos.map(\.caminho))
                self.grupos = self.grupos.compactMap { Self.semCaminhos($0, foram) }
                self.incluidos = self.incluidos.intersection(Set(self.grupos.map(\.id)))
                self.todos.removeAll { foram.contains($0.caminho) }
                self.selecionados.subtract(foram)
                DiscoServico.shared.volume = LeitorVolume.ler()
                Log.de("disco").info("Duplicados → Lixeira: \(r.movidos.count), \(r.bytes) bytes; falhas \(r.falhas.count)")
            }
        }
    }

    // MARK: Apoio (fora da main)

    nonisolated static func inalterado(_ c: String, _ g: GrupoDuplicado) -> Bool {
        guard let a = try? FileManager.default.attributesOfItem(atPath: c),
              (a[.type] as? FileAttributeType) == .typeRegular,
              let d = a[.modificationDate] as? Date, let antes = g.datas[c] else { return false }
        return abs(d.timeIntervalSince(antes)) < 1
    }

    nonisolated static func amostra(_ c: String) -> String? {
        guard let t = (try? FileManager.default.attributesOfItem(atPath: c))?[.size] as? NSNumber else { return nil }
        return Duplicados.amostra(c, tamanho: t.int64Value)
    }

    nonisolated static func semCaminhos(_ g: GrupoDuplicado, _ foram: Set<String>) -> GrupoDuplicado? {
        let resta = g.caminhos.filter { !foram.contains($0) }
        guard resta.count > 1 else { return nil }
        if resta.count == g.caminhos.count { return g }
        return GrupoDuplicado(id: g.id, caminhos: resta, bytes: g.bytes, datas: g.datas,
                              sugestao: resta.contains(g.sugestao) ? g.sugestao : (Guardiao.sugerir(resta) ?? resta[0]))
    }
}
