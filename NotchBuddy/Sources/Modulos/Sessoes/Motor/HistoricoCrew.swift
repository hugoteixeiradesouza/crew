import Foundation

// Histórico próprio do Crew: toda sessão do Claude Code que sai da lista (encerrada, fechada
// no terminal, tirada do Crew) fica guardada aqui, venha de onde vier. O Xirp só guarda as
// dele; as do motor do Crew (tmux) e as do terminal não apareciam em lugar nenhum.
// Um arquivo só, `historico-sessoes.json`, com as 300 mais recentes. A conversa em si é o
// transcript do Claude Code, que não é tocado.

struct SessaoEncerrada: Codable, Hashable {
    var sessionId: String
    var nome: String
    var pasta: String?
    var branch: String?
    var transcript: String?
    var quando: Date
}

@MainActor
final class HistoricoCrew: ObservableObject {
    static let shared = HistoricoCrew()

    /// Da mais recente para a mais antiga.
    @Published private(set) var lista: [SessaoEncerrada] = []

    private static let limite = 300
    private static var arquivo: URL { HookServer.supportDir.appendingPathComponent("historico-sessoes.json") }
    private let fila = DispatchQueue(label: "crew.historico-sessoes", qos: .utility)

    private init() {
        guard !CaptureTool.ativo, let data = try? Data(contentsOf: Self.arquivo) else { return }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        lista = (try? d.decode([SessaoEncerrada].self, from: data)) ?? []
    }

    /// A sessão saiu da lista: guarda (ou atualiza) a entrada dela.
    func guardar(_ t: AgentTask) {
        guard !CaptureTool.ativo, t.source == .claudeCode, !t.isIntegration, let sid = t.sessionId else { return }
        // Sessão que nem chegou a ter conversa não vira histórico.
        guard let caminho = t.transcriptPath, FileManager.default.fileExists(atPath: caminho) else { return }
        lista.removeAll { $0.sessionId == sid }
        lista.insert(SessaoEncerrada(sessionId: sid, nome: t.displayTitle, pasta: t.sessionCwd,
                                     branch: Projetos.branch(de: t.sessionCwd), transcript: caminho, quando: Date()),
                     at: 0)
        if lista.count > Self.limite { lista.removeLast(lista.count - Self.limite) }
        gravar()
    }

    /// Tira a entrada do histórico (o transcript continua no disco).
    func tirar(_ sessionId: String) {
        lista.removeAll { $0.sessionId == sessionId }
        gravar()
    }

    private func gravar() {
        let copia = lista
        let destino = Self.arquivo
        fila.async {
            let e = JSONEncoder()
            e.dateEncodingStrategy = .iso8601
            if let data = try? e.encode(copia) { try? data.write(to: destino, options: .atomic) }
        }
    }
}
