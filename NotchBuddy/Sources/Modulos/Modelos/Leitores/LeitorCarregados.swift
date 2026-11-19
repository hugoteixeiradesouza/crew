import Foundation

// O que o Ollama tem carregado na memória agora: `GET /api/ps` no servidor local.
// Só 127.0.0.1. Servidor parado = resposta nula, e o módulo mostra só o que está em disco.
// Nunca sobe o servidor.

struct ModeloCarregado: Identifiable, Sendable, Hashable {
    let nome: String
    /// Memória total que o modelo ocupa.
    let memoria: Int64
    /// Parte dela na GPU (memória unificada, no Apple Silicon).
    let memoriaGPU: Int64
    let expiraEm: Date?
    var id: String { nome }
}

enum LeitorCarregados {
    static let endereco = URL(string: "http://127.0.0.1:11434/api/ps")!

    private struct Resposta: Decodable {
        struct Item: Decodable {
            let name: String
            let size: Int64?
            let size_vram: Int64?
            let expires_at: String?
        }
        let models: [Item]
    }

    /// Lê de forma síncrona (roda na fila do Amostrador, nunca na main). Nil = servidor parado.
    static func ler(tempoMax: TimeInterval = 1.5) -> [ModeloCarregado]? {
        var pedido = URLRequest(url: endereco, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: tempoMax)
        pedido.httpMethod = "GET"
        let caixa = Caixa()
        let pronto = DispatchSemaphore(value: 0)
        let tarefa = sessao.dataTask(with: pedido) { dados, resp, _ in
            if let dados, (resp as? HTTPURLResponse)?.statusCode == 200 { caixa.guardar(dados) }
            pronto.signal()
        }
        tarefa.resume()
        if pronto.wait(timeout: .now() + tempoMax + 0.5) == .timedOut { tarefa.cancel(); return nil }
        guard let dados = caixa.dados, let r = try? JSONDecoder().decode(Resposta.self, from: dados) else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return r.models.map { m in
            // O Ollama manda nanossegundos (9 casas); o formatador só aceita até 3.
            let expira = m.expires_at.flatMap { s -> Date? in
                iso.date(from: s) ?? iso.date(from: s.replacingOccurrences(
                    of: #"\.(\d{3})\d+"#, with: ".$1", options: .regularExpression))
            }
            return ModeloCarregado(nome: m.name, memoria: m.size ?? 0, memoriaGPU: m.size_vram ?? 0, expiraEm: expira)
        }
    }

    /// Sessão própria: sem cache, sem cookies, sem proxy do sistema (é localhost).
    private static let sessao: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.connectionProxyDictionary = [:]
        c.timeoutIntervalForRequest = 2
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    private final class Caixa: @unchecked Sendable {
        private let trava = NSLock()
        private var _dados: Data?
        func guardar(_ d: Data) { trava.lock(); _dados = d; trava.unlock() }
        var dados: Data? { trava.lock(); defer { trava.unlock() }; return _dados }
    }
}
