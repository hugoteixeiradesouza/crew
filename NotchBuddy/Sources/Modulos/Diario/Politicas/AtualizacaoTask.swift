import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// "O que aconteceu?" — o Hugo conta em uma frase como anda uma task e o modelo local do Mac
// traduz em mudanças: esta foi feita / continua (título e prazo novos) / não precisa mais, e as
// tasks novas que nasceram dela ("agora tô fazendo o relatório" → nova task). Sem modelo, uma
// regra simples resolve o básico.

struct AtualizacaoTask: Sendable {
    enum Estado: String, Sendable { case feita, continua, ignorada }
    struct Nova: Sendable {
        var titulo: String
        var trechoPrazo: String?
    }
    var estado: Estado
    var novoTitulo: String?
    var trechoPrazo: String?
    var novas: [Nova]
    var comIA: Bool
}

#if canImport(FoundationModels)
@available(macOS 26, *)
@Generable
struct AtualizacaoGerada {
    @Guide(description: "como fica a task atual depois do que \(Usuario.nome) contou", .anyOf(["feita", "continua", "ignorada"]))
    var estado: String
    @Guide(description: "se a task atual continua mas mudou, o título novo curto (até 7 palavras); senão vazio")
    var novoTitulo: String
    @Guide(description: "se a task atual continua com prazo novo, as palavras exatas de \(Usuario.nome) sobre o prazo; senão vazio")
    var prazo: String
    @Guide(description: "tasks NOVAS que \(Usuario.nome) disse que vai fazer ou está fazendo agora (no máximo 3); vazio se nenhuma", .maximumCount(3))
    var novas: [NovaGerada]
}

@available(macOS 26, *)
@Generable
struct NovaGerada {
    @Guide(description: "título curto e assertivo, verbo no infinitivo + objeto (até 7 palavras), tirado do que \(Usuario.nome) disse")
    var titulo: String
    @Guide(description: "as palavras exatas de \(Usuario.nome) sobre o prazo desta task nova; vazio se não disse")
    var prazo: String
}
#endif

enum InterpretarAtualizacao {
    static var instrucoes: String { """
    \(Usuario.nome) está contando como anda uma task dele. Traduza em mudanças, sem inventar nada:
    - "feita": ele diz que aconteceu, resolveu, já foi, terminou, entregou.
    - "ignorada": não precisa mais, cancelou, desmarcou, não vai acontecer.
    - "continua": ainda falta; se mudou o que é ou o prazo, dê o título novo e/ou o prazo.
    - "novas": o que ele disse que está fazendo agora ou vai fazer depois, como task separada \\
    ("agora tô fazendo o relatório" → nova "Fazer o relatório"). Não repita a task atual como nova.
    Exemplo: task "Reunião com Diego" + "Diego veio, identificamos o que faltava e agora tô fazendo o relatório" \\
    → estado feita, novas ["Fazer o relatório"].
    Exemplo: task "Mandar proposta pra Carla" + "ela pediu pra mandar só amanhã cedo" → continua, prazo "amanhã cedo".
    """ }

    static func interpretar(_ texto: String, tarefa: String, assunto: String?, hora: Date) async -> AtualizacaoTask {
        #if canImport(FoundationModels)
        if #available(macOS 26, *), IAdoMac.disponivel {
            let f = DateFormatter()
            f.locale = Locale(identifier: "pt_BR")
            f.dateFormat = "EEEE, dd/MM/yyyy HH:mm"
            let pergunta = "Data e hora: \(f.string(from: hora))\nTask atual: \(tarefa)"
                + (assunto.map { " (\($0))" } ?? "") + "\nO \(Usuario.nome) contou: \"\(texto.prefix(600))\""
            do {
                let s = LanguageModelSession(instructions: instrucoes)
                let g = try await s.respond(to: pergunta, generating: AtualizacaoGerada.self).content
                let fonte = Prazos.normalizar(texto)
                func trecho(_ t: String) -> String? {
                    let x = t.trimmingCharacters(in: .whitespacesAndNewlines)
                    return x.isEmpty || !fonte.contains(Prazos.normalizar(x)) ? nil : x
                }
                let novas = g.novas.prefix(3).compactMap { n -> AtualizacaoTask.Nova? in
                    let t = TriagemIA.titulo(n.titulo.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'."))))
                    guard t.count >= 3, Prazos.normalizar(t) != Prazos.normalizar(tarefa) else { return nil }
                    return .init(titulo: t, trechoPrazo: trecho(n.prazo))
                }
                let novo = g.novoTitulo.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'.")))
                return AtualizacaoTask(estado: AtualizacaoTask.Estado(rawValue: g.estado) ?? .continua,
                                       novoTitulo: novo.isEmpty ? nil : TriagemIA.titulo(novo),
                                       trechoPrazo: trecho(g.prazo), novas: novas, comIA: true)
            } catch {}
        }
        #endif
        return heuristica(texto)
    }

    /// Sem modelo: "feito/já foi/resolvi/terminei" fecha; "cancelou/não precisa" ignora;
    /// "agora tô fazendo X" / "vou fazer X" abre X.
    static func heuristica(_ texto: String) -> AtualizacaoTask {
        let t = Prazos.normalizar(texto)
        var estado = AtualizacaoTask.Estado.continua
        if t.range(of: #"\b(feito|feita|ja foi|resolvi|resolvido|terminei|entreguei|aconteceu|veio|fizemos|identificamos)\b"#, options: .regularExpression) != nil { estado = .feita }
        if t.range(of: #"\b(cancel|desmarc|nao precisa|nao vai)"#, options: .regularExpression) != nil { estado = .ignorada }
        var novas: [AtualizacaoTask.Nova] = []
        if let r = texto.range(of: #"(?i)(agora (to|tô|estou) fazendo|vou fazer|preciso fazer) [^.,;!?]{3,60}"#, options: .regularExpression) {
            let obj = String(texto[r]).replacingOccurrences(of: #"(?i)^(agora (to|tô|estou) fazendo|vou fazer|preciso fazer) "#, with: "", options: .regularExpression)
            novas.append(.init(titulo: "Fazer " + obj, trechoPrazo: nil))
        }
        return AtualizacaoTask(estado: estado, novoTitulo: nil, trechoPrazo: nil, novas: novas, comIA: false)
    }
}
