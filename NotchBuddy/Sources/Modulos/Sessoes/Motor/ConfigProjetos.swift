import Foundation

// O que o Hugo configurou em cada projeto (a chave é a raiz do repositório): como ele aparece
// (nome, ícone, fixado, nota), com o que toda sessão nova nasce (modelo, esforço, modo,
// instrução fixa, isolamento) e se as sessões dele fazem som.
// Tudo num arquivo só, `projetos.json`. A cor continua em `Projetos` (é a mesma da ilha).

struct ConfigProjeto: Codable, Equatable, Sendable {
    /// Nome de exibição; nil = o nome da pasta.
    var nome: String?
    /// SF Symbol do projeto; nil = pasta.
    var icone: String?
    /// Fica no topo da lista.
    var fixado = false
    /// Anotação livre do Hugo (de quem é, o que não pode tocar).
    var nota = ""

    /// Padrões das sessões novas; nil = o padrão do Claude Code.
    var modelo: String?
    var esforco: String?
    var modo: String?
    /// Vai junto das instruções do Claude Code em toda sessão aberta pelo Crew neste projeto.
    var instrucao = ""

    /// Cada sessão nova abre numa pasta própria, criada por um comando do projeto.
    var isolar = false
    /// Roda na raiz do projeto; `{nome}` vira o nome da sessão.
    var comandoIsolar = ""
    /// Onde o comando deixa a pasta, a partir da raiz; `{nome}` vira o nome da sessão.
    var pastaIsolar = ""

    /// As sessões deste projeto não tocam som.
    var semSom = false

    init() {}

    // Campo que faltar no arquivo fica no padrão: versão nova do Crew lê arquivo antigo.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nome = try c.decodeIfPresent(String.self, forKey: .nome)
        icone = try c.decodeIfPresent(String.self, forKey: .icone)
        fixado = try c.decodeIfPresent(Bool.self, forKey: .fixado) ?? false
        nota = try c.decodeIfPresent(String.self, forKey: .nota) ?? ""
        modelo = try c.decodeIfPresent(String.self, forKey: .modelo)
        esforco = try c.decodeIfPresent(String.self, forKey: .esforco)
        modo = try c.decodeIfPresent(String.self, forKey: .modo)
        instrucao = try c.decodeIfPresent(String.self, forKey: .instrucao) ?? ""
        isolar = try c.decodeIfPresent(Bool.self, forKey: .isolar) ?? false
        comandoIsolar = try c.decodeIfPresent(String.self, forKey: .comandoIsolar) ?? ""
        pastaIsolar = try c.decodeIfPresent(String.self, forKey: .pastaIsolar) ?? ""
        semSom = try c.decodeIfPresent(Bool.self, forKey: .semSom) ?? false
    }

    /// O isolamento está ligado e tem o que precisa para rodar.
    var isolamentoPronto: Bool {
        isolar && !comandoIsolar.trimmingCharacters(in: .whitespaces).isEmpty
            && !pastaIsolar.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

/// As opções que o Crew oferece para modelo, esforço e modo (as mesmas do campo de nova sessão).
enum OpcoesSessao {
    static let modelos: [(nome: String, valor: String?)] = [
        ("Padrão", nil), ("Fable", "fable"), ("Opus", "opus"), ("Sonnet", "sonnet"), ("Haiku", "haiku"),
    ]
    static let esforcos: [(nome: String, valor: String?)] = [
        ("Padrão", nil), ("Baixo", "low"), ("Médio", "medium"), ("Alto", "high"), ("Muito alto", "xhigh"), ("Máximo", "max"),
    ]
    static let modos: [(nome: String, valor: String?, detalhe: String)] = [
        ("Padrão", nil, "pede permissão a cada ação"),
        ("Aceitar edições", "acceptEdits", "edita arquivos sem perguntar"),
        ("Planejar", "plan", "só lê e propõe um plano"),
        ("Automático", "auto", "decide sozinho o que precisa de permissão"),
    ]
    static let icones = ["folder.fill", "hammer.fill", "shippingbox.fill", "globe", "cart.fill", "chart.bar.fill",
                         "fork.knife", "building.2.fill", "gamecontroller.fill", "book.fill", "bolt.fill",
                         "cpu.fill", "paintbrush.fill", "server.rack", "person.2.fill", "sparkles"]
}

@MainActor
final class ConfigProjetos: ObservableObject {
    static let shared = ConfigProjetos()

    @Published private(set) var todas: [String: ConfigProjeto] = [:]
    /// Ordem que o Hugo deu à lista (raízes); o que não está aqui vem depois, na ordem de sempre.
    @Published private(set) var ordem: [String] = []

    private struct Arquivo: Codable {
        var versao = 1
        var projetos: [String: ConfigProjeto] = [:]
        var ordem: [String] = []
    }

    private static var arquivo: URL { HookServer.supportDir.appendingPathComponent("projetos.json") }
    private let fila = DispatchQueue(label: "crew.projetos-config", qos: .utility)

    private init() {
        guard !CaptureTool.ativo, let data = try? Data(contentsOf: Self.arquivo) else { return }
        if let a = try? JSONDecoder().decode(Arquivo.self, from: data) {
            todas = a.projetos
            ordem = a.ordem
        } else {
            // Existe e não deu para ler: guarda uma cópia antes de qualquer gravação nova.
            let copia = HookServer.supportDir.appendingPathComponent("projetos.ilegivel-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: Self.arquivo, to: copia)
            Log.de("sessoes").error("projetos.json ilegível; cópia em \(copia.lastPathComponent)")
        }
    }

    func de(_ raiz: String?) -> ConfigProjeto {
        raiz.flatMap { todas[$0] } ?? ConfigProjeto()
    }

    /// Lê a configuração do projeto que contém a pasta (qualquer pasta dentro dele).
    func daPasta(_ cwd: String?) -> ConfigProjeto { de(Projetos.raiz(de: cwd)) }

    func mudar(_ raiz: String, _ mexer: (inout ConfigProjeto) -> Void) {
        var c = de(raiz)
        mexer(&c)
        if c.nome?.trimmingCharacters(in: .whitespaces).isEmpty == true { c.nome = nil }
        guard c != todas[raiz] else { return }
        if c == ConfigProjeto() { todas[raiz] = nil } else { todas[raiz] = c }
        gravar()
    }

    /// Sobe ou desce o projeto na lista (`visiveis` = a ordem que está na tela agora).
    func mover(_ raiz: String, passo: Int, visiveis: [String]) {
        var l = visiveis
        guard let i = l.firstIndex(of: raiz), l.indices.contains(i + passo) else { return }
        l.swapAt(i, i + passo)
        ordem = l
        gravar()
    }

    /// Fixados primeiro; dentro de cada grupo, a ordem do Hugo e depois a de chegada.
    func ordenar(_ lista: [ProjetoCrew]) -> [ProjetoCrew] {
        let posicao = Dictionary(uniqueKeysWithValues: ordem.enumerated().map { ($1, $0) })
        return lista.enumerated().sorted { a, b in
            let fa = de(a.element.caminho).fixado, fb = de(b.element.caminho).fixado
            if fa != fb { return fa }
            let pa = posicao[a.element.caminho] ?? Int.max, pb = posicao[b.element.caminho] ?? Int.max
            return pa != pb ? pa < pb : a.offset < b.offset
        }.map(\.element)
    }

    private func gravar() {
        guard !CaptureTool.ativo else { return }
        let a = Arquivo(projetos: todas, ordem: ordem)
        let destino = Self.arquivo
        fila.async {
            let e = JSONEncoder()
            e.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? e.encode(a) { try? data.write(to: destino, options: .atomic) }
        }
    }
}

// MARK: - Isolamento

/// Cria a pasta própria da sessão com o comando que o Hugo configurou no projeto.
enum IsolamentoProjeto {
    /// Nome da sessão a partir do pedido: até três palavras, minúsculas, sem acento, mais a hora.
    static func nome(doPedido pedido: String, agora: Date = Date()) -> String {
        let limpo = pedido.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR")).lowercased()
        let palavras = limpo.split { !($0.isASCII && ($0.isLetter || $0.isNumber)) }
            .map(String.init).filter { $0.count > 2 }.prefix(3)
        let f = DateFormatter()
        f.dateFormat = "HHmm"
        let base = String(palavras.joined(separator: "-").prefix(24))
        return (base.isEmpty ? "sessao" : base) + "-" + f.string(from: agora)
    }

    /// Roda o comando na raiz e devolve a pasta onde a sessão abre.
    static func preparar(raiz: String, config: ConfigProjeto, pedido: String) async -> Result<String, MotorCrew.Falha> {
        let nome = nome(doPedido: pedido)
        let comando = config.comandoIsolar.replacingOccurrences(of: "{nome}", with: nome)
        let relativa = config.pastaIsolar.replacingOccurrences(of: "{nome}", with: nome)
        let pasta = relativa.hasPrefix("/") ? relativa : (raiz as NSString).appendingPathComponent(relativa)
        // Shell de login, como o motor: o comando enxerga o PATH do terminal do Hugo.
        let r = await Processo.rodar("/bin/zsh", ["-lc", "cd \"$0\" && " + comando, raiz], tempoMax: 120)
        guard r.ok else {
            let m = (r.erro.isEmpty ? r.saida : r.erro).trimmingCharacters(in: .whitespacesAndNewlines)
            return .failure(.init(mensagem: "O comando de isolamento falhou: " + (m.isEmpty ? "sem mensagem" : String(m.suffix(240)))))
        }
        var ehPasta: ObjCBool = false
        guard FileManager.default.fileExists(atPath: pasta, isDirectory: &ehPasta), ehPasta.boolValue else {
            return .failure(.init(mensagem: "O comando rodou, mas a pasta não apareceu: \(pasta)"))
        }
        return .success(pasta)
    }
}
