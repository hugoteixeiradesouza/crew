import Foundation

// O que o Hugo já respondeu sobre "isso é task?". Cada resposta (Sim / Não é task, e também
// Feito / Ignorar numa pendência que veio sozinha) vira um exemplo:
//   • a triagem recebe os exemplos mais recentes no prompt — o modelo aprende o critério dele;
//   • o que ele recusou várias vezes, parecido, nem chega a ser perguntado de novo.
// Guarda só o título, o assunto e a origem — nunca o texto da mensagem nem da conversa.
// Arquivo: diario/aprendizado.json (local, apagável na Central junto com a fonte).

struct DecisaoTask: Codable, Equatable, Sendable {
    var data: Date
    var origem: TipoEntrada
    var titulo: String
    var assunto: String?
    /// true = virou task; false = não era task.
    var virou: Bool
}

@MainActor
final class Aprendizado {
    static let shared = Aprendizado()
    private(set) var decisoes: [DecisaoTask] = []
    private let maximo = 300
    private let log = Log.de("diario")

    private var arquivo: URL { DiarioServico.pasta.appendingPathComponent("aprendizado.json") }

    private init() {
        guard let d = try? Data(contentsOf: arquivo) else { return }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        decisoes = (try? dec.decode([DecisaoTask].self, from: d)) ?? []
    }

    func registrar(_ p: Pendencia, virou: Bool) {
        // Nota é o próprio Hugo escrevendo: não ensina nada sobre o que vira task sozinho
        guard p.origem != .nota, !CaptureTool.ativo else { return }
        decisoes.removeAll { Prazos.normalizar($0.titulo) == Prazos.normalizar(p.acao) && $0.origem == p.origem }
        decisoes.append(DecisaoTask(data: Date(), origem: p.origem, titulo: p.acao, assunto: p.assunto, virou: virou))
        if decisoes.count > maximo { decisoes.removeFirst(decisoes.count - maximo) }
        gravar()
        log.info("aprendizado: \(virou ? "virou task" : "não era task", privacy: .public) (\(self.decisoes.count) exemplos)")
    }

    /// Apaga os exemplos de uma origem (a fonte foi desligada e apagada).
    func esquecer(_ origem: TipoEntrada) {
        decisoes.removeAll { $0.origem == origem }
        gravar()
    }

    /// Exemplos para o prompt: as recusas e os aceites mais recentes da mesma origem (e, se
    /// faltar, de qualquer origem).
    func exemplos(_ origem: TipoEntrada, nao: Int = 8, sim: Int = 6) -> (nao: [String], sim: [String]) {
        func pegar(_ virou: Bool, _ n: Int) -> [String] {
            let mesma = decisoes.filter { $0.virou == virou && $0.origem == origem }
            let outras = decisoes.filter { $0.virou == virou && $0.origem != origem }
            return (mesma.suffix(n) + outras.suffix(max(0, n - mesma.count))).suffix(n).map { d in
                d.titulo + (d.assunto.map { " (\($0))" } ?? "")
            }
        }
        return (pegar(false, nao), pegar(true, sim))
    }

    /// Já recusado pelo menos 2 vezes algo parecido, e nunca aceito parecido: nem pergunta.
    func recusadoAntes(_ titulo: String, assunto: String?, origem: TipoEntrada) -> Bool {
        let alvo = Self.palavras(titulo + " " + (assunto ?? ""))
        guard !alvo.isEmpty else { return false }
        let parecidas = decisoes.filter { $0.origem == origem && Self.parecido(alvo, Self.palavras($0.titulo + " " + ($0.assunto ?? ""))) }
        return parecidas.filter { !$0.virou }.count >= 2 && !parecidas.contains(where: \.virou)
    }

    static func palavras(_ s: String) -> Set<String> {
        Set(Prazos.normalizar(s).split(whereSeparator: { !$0.isLetter }).map(String.init).filter { $0.count >= 4 })
    }

    static func parecido(_ a: Set<String>, _ b: Set<String>) -> Bool {
        guard !a.isEmpty, !b.isEmpty else { return false }
        return Double(a.intersection(b).count) / Double(a.union(b).count) >= 0.5
    }

    private func gravar() {
        guard !CaptureTool.ativo else { return }
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted]
        guard let d = try? enc.encode(decisoes) else { return }
        try? FileManager.default.createDirectory(at: DiarioServico.pasta, withIntermediateDirectories: true)
        try? d.write(to: arquivo, options: .atomic)
    }
}
