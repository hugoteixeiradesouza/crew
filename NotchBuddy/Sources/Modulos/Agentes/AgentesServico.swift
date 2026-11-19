import Foundation
import Observation

// Dados do módulo Agentes: worktrees órfãs (podem ir para a Lixeira) e as ativas por repositório.
// Nada roda sozinho: a varredura acontece quando o Hugo pede ou quando uma tela do módulo abre,
// sempre fora da main. Tamanhos com `du`, via Processo.rodar.

@Observable @MainActor
final class AgentesServico {
    static let shared = AgentesServico()

    private(set) var orfas: [PoliticaWorktrees.Orfa] = []
    private(set) var ativas: [WorktreesAtivas.Repositorio] = []
    /// Tamanho em bytes, por caminho (só das órfãs). Ausente = ainda medindo.
    private(set) var tamanhos: [String: Int64] = [:]
    private(set) var varrendo = false
    private(set) var medindo = false
    private(set) var ultimaVarredura: Date?
    private(set) var movendo = false
    /// Resultado da última ida para a Lixeira, para mostrar na Central.
    private(set) var ultimoResultado: String?

    @ObservationIgnored private let log = Log.de("agentes")

    private init() {}

    var totalOrfas: Int64 { orfas.reduce(0) { $0 + (tamanhos[$1.caminho] ?? 0) } }
    var totalAtivas: Int { ativas.reduce(0) { $0 + $1.worktrees.filter { !$0.pastaSumiu }.count } }
    var ativasEmUso: Int { ativas.reduce(0) { $0 + $1.worktrees.filter(\.emUso).count } }

    /// Varre de novo se a última varredura tiver mais de `validade` segundos (ou nunca houve).
    func varrerSeVelho(validade: TimeInterval = 120) {
        if let u = ultimaVarredura, Date().timeIntervalSince(u) < validade { return }
        varrer()
    }

    func varrer() {
        guard !varrendo else { return }
        varrendo = true
        Task {
            let r = await Task.detached(priority: .utility) { Self.lerTudo() }.value
            orfas = r.orfas
            ativas = r.ativas
            tamanhos = tamanhos.filter { k, _ in r.orfas.contains { $0.caminho == k } }
            ultimaVarredura = Date()
            varrendo = false
            log.info("varredura: \(r.orfas.count) órfã(s), \(r.ativas.count) repositório(s) com worktrees")
            await medirTamanhos()
        }
    }

    private struct Leitura: Sendable {
        let orfas: [PoliticaWorktrees.Orfa]
        let ativas: [WorktreesAtivas.Repositorio]
    }

    nonisolated private static func lerTudo() -> Leitura {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let projetos = PoliticaWorktrees.projetosClaude(home: home)
        let vivo = PoliticaWorktrees.Vivo.agora(home: home)
        return Leitura(orfas: PoliticaWorktrees.orfas(home: home, projetosClaude: projetos, vivo: vivo),
                       ativas: WorktreesAtivas.ler(projetos: projetos, home: home, vivo: vivo))
    }

    private func medirTamanhos() async {
        let faltam = orfas.map(\.caminho).filter { tamanhos[$0] == nil }
        guard !faltam.isEmpty else { return }
        medindo = true
        for c in faltam {
            if let b = await Self.du(c) { tamanhos[c] = b }
        }
        medindo = false
    }

    /// `du -sk` (blocos de 1 KB realmente usados no disco).
    nonisolated static func du(_ caminho: String) async -> Int64? {
        let r = await Processo.rodar("/usr/bin/du", ["-sk", caminho], tempoMax: 120)
        guard let campo = r.saida.split(whereSeparator: { $0 == "\t" || $0 == " " }).first,
              let kb = Int64(campo) else { return nil }
        return kb * 1024
    }

    /// Move as worktrees escolhidas para a Lixeira. Cada uma passa de novo pelo portão (formato do
    /// caminho, fora do .coucou-sessoes, ainda órfã) e pela checagem de uso (processo, Cursor, lock)
    /// na hora; a que não passar fica onde está.
    func moverParaLixeira(_ caminhos: [String]) {
        guard !movendo, !caminhos.isEmpty else { return }
        movendo = true
        let tamanhosAntes = tamanhos
        Task {
            let r = await Task.detached(priority: .userInitiated) { Self.lixeira(caminhos) }.value
            let bytes = r.movidas.reduce(Int64(0)) { $0 + (tamanhosAntes[$1] ?? 0) }
            var partes = ["\(r.movidas.count) movida(s) para a Lixeira (\(FormatoAgentes.bytes(bytes)))."]
            if !r.recusadas.isEmpty {
                partes.append("\(r.recusadas.count) ficou(aram): " + r.recusadas.map { "\(($0.caminho as NSString).lastPathComponent) — \($0.porque)" }.joined(separator: "; "))
            }
            ultimoResultado = partes.joined(separator: " ")
            log.info("lixeira: \(r.movidas.count) movida(s), \(r.recusadas.count) recusada(s)")
            movendo = false
            varrendo = false
            ultimaVarredura = nil
            varrer()
        }
    }

    private struct ResultadoLixeira: Sendable {
        var movidas: [String] = []
        var recusadas: [(caminho: String, porque: String)] = []
    }

    nonisolated private static func lixeira(_ caminhos: [String]) -> ResultadoLixeira {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let vivo = PoliticaWorktrees.Vivo.agora(home: home)
        var r = ResultadoLixeira()
        for c in caminhos {
            let url = URL(fileURLWithPath: c, isDirectory: true)
            guard PoliticaWorktrees.podeIrParaLixeira(c, home: home) else {
                r.recusadas.append((c, "o git voltou a listar ou o caminho não é de worktree de agente")); continue
            }
            guard vivo.cwds != nil, !vivo.temProcessoDentro(c), !vivo.abertaNoCursor(c),
                  !PoliticaWorktrees.temLock(url) else {
                r.recusadas.append((c, "está em uso agora")); continue
            }
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                r.movidas.append(c)
            } catch {
                r.recusadas.append((c, error.localizedDescription))
            }
        }
        return r
    }
}

enum FormatoAgentes {
    static func bytes(_ b: Int64) -> String { ByteCountFormatter.string(fromByteCount: b, countStyle: .file) }

    /// "~/dev/x" em vez de "/Users/hugo/dev/x".
    static func curto(_ caminho: String) -> String { (caminho as NSString).abbreviatingWithTildeInPath }

    static func idade(_ d: Date?, agora: Date = Date()) -> String {
        guard let d else { return "—" }
        let s = max(0, agora.timeIntervalSince(d))
        if s < 60 { return "agora" }
        if s < 3600 { return "há \(Int(s / 60)) min" }
        if s < 86400 { return "há \(Int(s / 3600)) h" }
        let dias = Int(s / 86400)
        return dias == 1 ? "há 1 dia" : "há \(dias) dias"
    }
}
