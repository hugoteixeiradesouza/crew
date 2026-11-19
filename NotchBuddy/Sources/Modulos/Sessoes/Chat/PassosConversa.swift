import Foundation

// Os passos do Claude num turno — cada ferramenta que ele usou, com o que fez e o que voltou —
// lidos do transcript para a conversa mostrar o trabalho como o terminal do Claude Code mostra:
// "Rodou os testes · 3 linhas · +110 linhas", "Leu 4 arquivos", erro em destaque.
// Só Foundation: compila sozinho no teste de `testes/conversa/`.

/// Um passo do Claude: uma ferramenta usada (ou um marco do turno).
struct PassoConversa: Identifiable, Equatable, Sendable {
    enum Tipo: String, Sendable {
        case comando, leitura, edicao, escrita, busca, agente, web, navegador, tarefas, mensagem
        case pergunta, skill, ferramentas, outro
        /// O Claude pensou antes de agir (o "Thought for 8s" do terminal).
        case pensamento
        /// O Hugo interrompeu o turno.
        case interrupcao
    }

    let id: String
    var tipo: Tipo
    /// Nome da ferramenta no Claude Code ("Bash", "Read", "mcp__crew__sessoes_abertas").
    var ferramenta: String
    /// O que é, em português, para quem não programa: a descrição do comando, o nome do arquivo,
    /// o que foi buscado.
    var alvo: String
    /// O texto técnico por baixo (o comando do Bash, o caminho inteiro), em letra de máquina.
    var tecnico: String = ""
    var quando: Date?
    /// Rodando em segundo plano (o terminal segue sem esperar).
    var segundoPlano = false
    /// Quanto durou (o pensamento traz pronto; nas ferramentas sai do horário do resultado).
    var duracao: TimeInterval?
    /// nil = ainda rodando (o resultado não chegou ao transcript).
    var resultado: ResultadoPasso?
    /// O que este passo muda na lista de tarefas do Claude (só nas ferramentas de tarefas).
    var tarefa: MudancaTarefa?

    var rodando: Bool { resultado == nil && tipo != .pensamento && tipo != .interrupcao }

    /// O verbo entra na frase? Comando com descrição ("Compilar o Crew") já é uma frase: o ícone
    /// diz que é comando, e "Rodou Compilar o Crew" soa torto.
    var mostraVerbo: Bool { !(tipo == .comando && !tecnico.isEmpty) }

    /// A frase inteira do passo: "Lendo Setores.swift", "Compilar o Crew".
    var frase: String { !mostraVerbo ? alvo : alvo.isEmpty ? verbo : verbo + " " + alvo }

    /// "Rodou" / "Rodando": o verbo do passo, conforme já terminou ou não.
    var verbo: String {
        let feito = !rodando
        switch tipo {
        case .comando: return feito ? "Rodou" : "Rodando"
        case .leitura: return feito ? "Leu" : "Lendo"
        case .edicao: return feito ? "Editou" : "Editando"
        case .escrita: return feito ? "Escreveu" : "Escrevendo"
        case .busca: return feito ? "Buscou" : "Buscando"
        case .agente: return feito ? "Agente" : "Agente trabalhando"
        case .web: return feito ? "Consultou a web" : "Consultando a web"
        case .navegador: return feito ? "Navegador" : "No navegador"
        case .tarefas: return feito ? "Atualizou as tarefas" : "Atualizando as tarefas"
        case .mensagem: return feito ? "Mandou mensagem" : "Mandando mensagem"
        case .pergunta: return feito ? "Perguntou a você" : "Perguntando a você"
        case .skill: return feito ? "Usou a skill" : "Usando a skill"
        case .ferramentas: return feito ? "Carregou ferramentas" : "Carregando ferramentas"
        case .outro: return feito ? "Usou" : "Usando"
        case .pensamento: return "Pensou"
        case .interrupcao: return "Você interrompeu"
        }
    }

    /// Ícone (SF Symbols) do tipo.
    var icone: String {
        switch tipo {
        case .comando: return "terminal"
        case .leitura: return "doc.text"
        case .edicao: return "pencil.line"
        case .escrita: return "doc.badge.plus"
        case .busca: return "magnifyingglass"
        case .agente: return "person.2"
        case .web: return "globe"
        case .navegador: return "safari"
        case .tarefas: return "checklist"
        case .mensagem: return "paperplane"
        case .pergunta: return "questionmark.bubble"
        case .skill: return "sparkles"
        case .ferramentas: return "wrench.and.screwdriver"
        case .outro: return "puzzlepiece.extension"
        case .pensamento: return "brain"
        case .interrupcao: return "stop.circle"
        }
    }
}

/// O que voltou de um passo: resumo de uma linha, as primeiras linhas e quantas são ao todo.
struct ResultadoPasso: Equatable, Sendable {
    /// Uma frase curta: "214 linhas", "+12 −3 linhas", "sem saída".
    var resumo = ""
    /// As primeiras linhas da saída (até `tetoLinhas`), já cortadas na largura.
    var linhas: [String] = []
    /// Quantas linhas a saída tem ao todo.
    var total = 0
    var erro = false
    /// A permissão foi negada: "auto" = o modo automático bloqueou; "hugo" = o Hugo recusou.
    var negado: String?
    var quando: Date?
    /// Número que o Claude Code deu à tarefa criada por este passo.
    var tarefaId: String?

    static let tetoLinhas = 60
    static let tetoColunas = 400
}

/// De onde sai o passo: o bloco `tool_use` da resposta do Claude.
enum LeitorPassos {
    static func passo(id: String, nome: String, entrada: [String: Any], quando: Date?) -> PassoConversa {
        func s(_ k: String) -> String { (entrada[k] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        func arquivo(_ caminho: String) -> String { (caminho as NSString).lastPathComponent }
        var p = PassoConversa(id: id, tipo: .outro, ferramenta: nome, alvo: nome, quando: quando)
        switch nome {
        case "Bash", "BashOutput", "KillShell", "KillBash":
            p.tipo = .comando
            let comando = umaLinha(s("command"), 220)
            p.alvo = s("description").isEmpty ? comando : s("description")
            p.tecnico = s("description").isEmpty ? "" : comando
            p.segundoPlano = entrada["run_in_background"] as? Bool == true
            if nome != "Bash", p.alvo.isEmpty { p.alvo = nome == "BashOutput" ? "saída do comando em segundo plano" : "encerrou o comando em segundo plano" }
        case "Read", "NotebookRead":
            p.tipo = .leitura
            let c = s("file_path").isEmpty ? s("notebook_path") : s("file_path")
            p.alvo = arquivo(c); p.tecnico = c
        case "Edit", "MultiEdit", "NotebookEdit":
            p.tipo = .edicao
            let c = s("file_path").isEmpty ? s("notebook_path") : s("file_path")
            p.alvo = arquivo(c); p.tecnico = c
        case "Write":
            p.tipo = .escrita
            p.alvo = arquivo(s("file_path")); p.tecnico = s("file_path")
        case "Grep":
            p.tipo = .busca
            p.alvo = "“" + umaLinha(s("pattern"), 80) + "”"
            let onde = s("path").isEmpty ? s("glob") : s("path")
            p.tecnico = onde.isEmpty ? "" : "em " + onde
        case "Glob":
            p.tipo = .busca
            p.alvo = "arquivos " + umaLinha(s("pattern"), 80)
            p.tecnico = s("path").isEmpty ? "" : "em " + s("path")
        case "Agent", "Task":
            p.tipo = .agente
            p.alvo = s("description").isEmpty ? umaLinha(s("prompt"), 90) : s("description")
            p.tecnico = s("subagent_type")
        case "WebFetch":
            p.tipo = .web
            p.alvo = URL(string: s("url"))?.host ?? umaLinha(s("url"), 80)
            p.tecnico = s("url")
        case "WebSearch":
            p.tipo = .web
            p.alvo = "“" + umaLinha(s("query"), 90) + "”"
        case "TodoWrite", "TaskCreate", "TaskUpdate", "TaskList", "TaskGet":
            p.tipo = .tarefas
            p.alvo = umaLinha(s("subject").isEmpty ? s("description") : s("subject"), 90)
            p.tarefa = mudancaDeTarefa(nome: nome, entrada: entrada)
        case "TaskStop", "TaskOutput":
            p.tipo = .agente
            p.alvo = nome == "TaskStop" ? "parou uma tarefa em segundo plano" : "conferiu uma tarefa em segundo plano"
        case "SendMessage":
            p.tipo = .mensagem
            p.alvo = umaLinha(s("summary").isEmpty ? s("message") : s("summary"), 90)
        case "AskUserQuestion":
            p.tipo = .pergunta
            let perguntas = entrada["questions"] as? [[String: Any]] ?? []
            p.alvo = umaLinha(perguntas.first?["question"] as? String ?? "", 110)
        case "Skill":
            p.tipo = .skill
            p.alvo = s("skill")
        case "ToolSearch":
            p.tipo = .ferramentas
            p.alvo = umaLinha(s("query").replacingOccurrences(of: "select:", with: ""), 90)
        case "ExitPlanMode", "EnterPlanMode":
            p.tipo = .outro
            p.alvo = nome == "ExitPlanMode" ? "apresentou o plano" : "entrou no modo de planejar"
        default:
            if nome.hasPrefix("mcp__") {
                // mcp__servidor__ferramenta → "servidor: ferramenta"
                let partes = nome.dropFirst(5).components(separatedBy: "__")
                let servidor = partes.first ?? ""
                let acao = partes.dropFirst().joined(separator: " ").replacingOccurrences(of: "_", with: " ")
                let navegador = servidor.lowercased().contains("chrome") || servidor.lowercased().contains("browser")
                p.tipo = navegador ? .navegador : .outro
                p.alvo = navegador ? acao : servidor.replacingOccurrences(of: "_", with: " ") + ": " + acao
                // O dado que mais explica: endereço, consulta ou texto.
                for chave in ["url", "query", "text", "path", "tabela", "titulo"] where !s(chave).isEmpty {
                    p.tecnico = umaLinha(s(chave), 160); break
                }
            }
        }
        if p.alvo.isEmpty { p.alvo = nome }
        return p
    }

    /// O que a ferramenta de tarefas pede: a lista inteira (TodoWrite), uma tarefa nova
    /// (TaskCreate) ou a mudança de uma (TaskUpdate). Consulta (TaskList, TaskGet) não muda nada.
    static func mudancaDeTarefa(nome: String, entrada: [String: Any]) -> MudancaTarefa? {
        func s(_ d: [String: Any], _ k: String) -> String { (d[k] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        switch nome {
        case "TodoWrite":
            guard let todos = entrada["todos"] as? [[String: Any]] else { return nil }
            var lista: [TarefaConversa] = []
            for (k, t) in todos.enumerated() {
                let titulo = s(t, "content").isEmpty ? s(t, "subject") : s(t, "content")
                guard !titulo.isEmpty else { continue }
                lista.append(TarefaConversa(id: s(t, "id").isEmpty ? String(k + 1) : s(t, "id"), titulo: umaLinha(titulo, 140),
                                            fazendo: umaLinha(s(t, "activeForm"), 140),
                                            estado: TarefaConversa.Estado(claude: s(t, "status")) ?? .pendente))
            }
            return .lista(lista)
        case "TaskCreate":
            let titulo = s(entrada, "subject").isEmpty ? s(entrada, "description") : s(entrada, "subject")
            guard !titulo.isEmpty else { return nil }
            return .cria(titulo: umaLinha(titulo, 140), fazendo: umaLinha(s(entrada, "activeForm"), 140))
        case "TaskUpdate":
            let id = s(entrada, "taskId").isEmpty ? (entrada["taskId"] as? Int).map(String.init) ?? "" : s(entrada, "taskId")
            guard !id.isEmpty else { return nil }
            let estado = s(entrada, "status")
            let titulo = s(entrada, "subject"), fazendo = s(entrada, "activeForm")
            return .atualiza(id: id, estado: TarefaConversa.Estado(claude: estado), apaga: estado == "deleted",
                             titulo: titulo.isEmpty ? nil : umaLinha(titulo, 140), fazendo: fazendo.isEmpty ? nil : umaLinha(fazendo, 140))
        default: return nil
        }
    }

    /// O "Pensou por 8s" de um bloco de raciocínio.
    static func pensamento(id: String, ms: Int, quando: Date?) -> PassoConversa {
        PassoConversa(id: id, tipo: .pensamento, ferramenta: "", alvo: ms >= 1000 ? "por " + duracao(Double(ms) / 1000) : "",
                      quando: quando, duracao: Double(ms) / 1000)
    }

    static func interrupcao(id: String, quando: Date?) -> PassoConversa {
        PassoConversa(id: id, tipo: .interrupcao, ferramenta: "", alvo: "", quando: quando)
    }

    /// O resultado de uma ferramenta: o bloco `tool_result` (e o `toolUseResult` da linha, que
    /// traz o dado já estruturado: remendo da edição, linhas do arquivo lido).
    static func resultado(bloco: [String: Any], estruturado: Any?, quando: Date?) -> ResultadoPasso {
        var r = ResultadoPasso(quando: quando)
        r.erro = bloco["is_error"] as? Bool == true
        var texto = ""
        var imagens = 0
        if let s = bloco["content"] as? String {
            texto = s
        } else if let partes = bloco["content"] as? [[String: Any]] {
            texto = partes.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined(separator: "\n")
            imagens = partes.filter { $0["type"] as? String == "image" }.count
        }
        let e = estruturado as? [String: Any]
        // Tarefa criada: o número dela vem no resultado ("Task #3 created successfully").
        if let t = e?["task"] as? [String: Any] {
            r.tarefaId = t["id"] as? String ?? (t["id"] as? Int).map(String.init)
        }
        if r.tarefaId == nil, texto.hasPrefix("Task #") {
            let n = texto.dropFirst(6).prefix(while: \.isNumber)
            if !n.isEmpty { r.tarefaId = String(n) }
        }

        if r.erro {
            if texto.hasPrefix("Permission for this action was denied") || texto.contains("auto mode classifier") {
                r.negado = "auto"
                // "… Reason: [Motivo]. If you have other tasks…" → só o motivo.
                if let a = texto.range(of: "Reason: "), let b = texto.range(of: ". If you", range: a.upperBound..<texto.endIndex) {
                    texto = String(texto[a.upperBound..<b.lowerBound])
                }
            } else if texto.hasPrefix("The user doesn't want to proceed") {
                r.negado = "hugo"
                texto = ""
            }
            // Lembrete embutido no erro não é saída do comando.
            if let corte = texto.range(of: "<system-reminder>") { texto = String(texto[..<corte.lowerBound]) }
            guardar(texto, em: &r)
            r.resumo = r.negado == "auto" ? "bloqueado pelo modo automático" : r.negado == "hugo" ? "você recusou" : "deu erro"
            return r
        }

        // Edição e escrita: o remendo diz quantas linhas entraram e saíram.
        if let remendo = e?["structuredPatch"] as? [[String: Any]], e?["filePath"] != nil {
            var mais = 0, menos = 0
            var diff: [String] = []
            for trecho in remendo {
                for l in trecho["lines"] as? [String] ?? [] {
                    if l.hasPrefix("+") { mais += 1 } else if l.hasPrefix("-") { menos += 1 }
                    diff.append(l)
                }
            }
            if remendo.isEmpty, let conteudo = e?["content"] as? String {
                // Arquivo novo: sem remendo, vale o conteúdo.
                let n = conteudo.isEmpty ? 0 : conteudo.components(separatedBy: "\n").count
                r.resumo = "arquivo novo, \(plural(n, "linha", "linhas"))"
                return r
            }
            r.resumo = "+\(mais) −\(menos) " + (mais + menos == 1 ? "linha" : "linhas")
            r.total = diff.count
            r.linhas = diff.prefix(ResultadoPasso.tetoLinhas).map { cortar($0) }
            return r
        }
        // Leitura: o conteúdo é o próprio arquivo — basta dizer o tamanho.
        if let arq = e?["file"] as? [String: Any] {
            if let n = arq["numLines"] as? Int {
                let total = arq["totalLines"] as? Int ?? n
                r.resumo = total > n ? "\(n) de \(plural(total, "linha", "linhas"))" : plural(n, "linha", "linhas")
            } else {
                r.resumo = imagens > 0 || e?["type"] as? String == "image" ? "imagem" : "lido"
            }
            return r
        }
        // Agente lançado em segundo plano: o relatório chega depois.
        if e?["isAsync"] as? Bool == true {
            r.resumo = "lançado em segundo plano"
            return r
        }
        if let id = e?["backgroundTaskId"] as? String, !id.isEmpty {
            r.resumo = "rodando em segundo plano"
            return r
        }
        if let corte = texto.range(of: "<system-reminder>") { texto = String(texto[..<corte.lowerBound]) }
        guardar(texto, em: &r)
        if r.total == 0 { r.resumo = imagens > 0 ? (imagens == 1 ? "imagem" : "\(imagens) imagens") : "sem saída" }
        return r
    }

    /// Guarda as primeiras linhas (sem as vazias das pontas) e conta o total.
    private static func guardar(_ texto: String, em r: inout ResultadoPasso) {
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        var total = 0
        var linhas: [String] = []
        // Sem montar um vetor com a saída inteira (pode ter dezenas de milhares de linhas).
        t.enumerateLines { linha, _ in
            total += 1
            if linhas.count < ResultadoPasso.tetoLinhas { linhas.append(cortar(linha)) }
        }
        r.total = total
        r.linhas = linhas
    }

    private static func cortar(_ linha: String) -> String {
        linha.count > ResultadoPasso.tetoColunas ? String(linha.prefix(ResultadoPasso.tetoColunas)) + "…" : linha
    }

    /// O texto numa linha só, cortado em `teto` letras.
    static func umaLinha(_ s: String, _ teto: Int) -> String {
        let linhas = s.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var t = linhas.first ?? ""
        if linhas.count > 1 { t += " …" }
        return t.count > teto ? String(t.prefix(teto)) + "…" : t
    }

    static func plural(_ n: Int, _ um: String, _ varios: String) -> String { "\(n) \(n == 1 ? um : varios)" }

    /// "8s", "1m 8s", "1h 4m"
    static func duracao(_ segundos: TimeInterval) -> String {
        let s = max(0, Int(segundos.rounded()))
        return s < 60 ? "\(s)s" : s < 3600 ? "\(s / 60)m \(s % 60)s" : "\(s / 3600)h \(s % 3600 / 60)m"
    }
}

// MARK: - A lista de tarefas do Claude

/// Uma tarefa do plano que o Claude monta e vai marcando enquanto trabalha.
struct TarefaConversa: Identifiable, Equatable, Sendable {
    enum Estado: String, Sendable {
        case pendente, fazendo, feita

        /// O nome que o Claude Code usa ("pending", "in_progress", "completed").
        init?(claude: String) {
            switch claude {
            case "pending": self = .pendente
            case "in_progress": self = .fazendo
            case "completed": self = .feita
            default: return nil
            }
        }
    }

    var id: String
    var titulo: String
    /// A frase de quando está em andamento ("Rodando os testes"); vazia = vale o título.
    var fazendo = ""
    var estado: Estado = .pendente
}

/// O que um passo de tarefas muda na lista.
enum MudancaTarefa: Equatable, Sendable {
    case lista([TarefaConversa])
    case cria(titulo: String, fazendo: String)
    case atualiza(id: String, estado: TarefaConversa.Estado?, apaga: Bool, titulo: String?, fazendo: String?)
}

enum ListaDeTarefas {
    /// A lista como está agora: as mudanças dos passos, na ordem em que aconteceram. Só enxerga
    /// o que foi lido do transcript: mudança de tarefa criada antes disso é ignorada.
    static func montar(_ mensagens: [SessionMessage]) -> [TarefaConversa] {
        var lista: [TarefaConversa] = []
        for m in mensagens {
            for p in m.passos {
                guard let mudanca = p.tarefa, p.resultado?.erro != true else { continue }
                switch mudanca {
                case .lista(let nova):
                    lista = nova
                case .cria(let titulo, let fazendo):
                    // Plano novo depois de um plano concluído: o antigo sai.
                    if !lista.isEmpty, lista.allSatisfy({ $0.estado == .feita }) { lista = [] }
                    // Sem o resultado ainda, o número é o seguinte (é como o Claude Code numera).
                    let seguinte = (lista.compactMap { Int($0.id) }.max() ?? 0) + 1
                    let id = p.resultado?.tarefaId ?? String(seguinte)
                    guard !lista.contains(where: { $0.id == id }) else { continue }
                    lista.append(TarefaConversa(id: id, titulo: titulo, fazendo: fazendo))
                case .atualiza(let id, let estado, let apaga, let titulo, let fazendo):
                    guard let k = lista.firstIndex(where: { $0.id == id }) else { continue }
                    if apaga { lista.remove(at: k); continue }
                    if let estado { lista[k].estado = estado }
                    if let titulo { lista[k].titulo = titulo }
                    if let fazendo { lista[k].fazendo = fazendo }
                }
            }
        }
        return lista
    }
}

// MARK: - O turno, com o caminho

/// Uma entrada do caminho do turno: fala do Claude no meio do trabalho, um passo, ou uma
/// sequência de passos iguais ("Leu 4 arquivos").
enum ItemCaminho: Identifiable, Equatable {
    case fala(SessionMessage)
    case passo(PassoConversa)
    case grupo(id: String, tipo: PassoConversa.Tipo, passos: [PassoConversa])

    var id: String {
        switch self {
        case .fala(let m): return "f\(m.id)"
        case .passo(let p): return "p" + p.id
        case .grupo(let id, _, _): return "g" + id
        }
    }
}

/// Um turno da conversa no app do Crew: o pedido do Hugo, o caminho (falas e passos) e a
/// resposta final.
struct TurnoConversa: Identifiable, Equatable {
    let id: Int
    var user: SessionMessage?
    var caminho: [ItemCaminho] = []
    var answer: SessionMessage?
    /// O contexto foi resumido antes deste turno.
    var resumo = false
    /// Quanto o turno levou (o Claude Code grava ao terminar).
    var duracao: TimeInterval?

    /// Todos os passos de ferramenta do turno, na ordem.
    var passos: [PassoConversa] {
        caminho.flatMap { item -> [PassoConversa] in
            switch item {
            case .fala: return []
            case .passo(let p): return [p]
            case .grupo(_, _, let ps): return ps
            }
        }
    }

    /// O passo que está rodando agora (o último sem resultado).
    var passoRodando: PassoConversa? { passos.last(where: \.rodando) }

    /// Tipos em que uma sequência seguida vira uma linha só.
    private static let agrupaveis: Set<PassoConversa.Tipo> = [.leitura, .busca, .pensamento, .ferramentas, .tarefas]

    static func agrupar(_ mensagens: [SessionMessage]) -> [TurnoConversa] {
        var turnos: [TurnoConversa] = []
        // Por turno: as falas e passos do Claude, em ordem, antes de separar a resposta.
        var corridas: [[SessionMessage]] = []
        for m in mensagens {
            if m.resumo {
                turnos.append(TurnoConversa(id: m.id, resumo: true)); corridas.append([])
                continue
            }
            if m.fromUser || turnos.isEmpty {
                turnos.append(TurnoConversa(id: m.id, user: m.fromUser ? m : nil)); corridas.append([])
                if m.fromUser { continue }
            }
            if let d = m.duracaoTurno { turnos[turnos.count - 1].duracao = d }
            corridas[corridas.count - 1].append(m)
        }
        for i in turnos.indices {
            var falas = corridas[i].filter { !$0.text.isEmpty || !$0.images.isEmpty || !$0.passos.isEmpty }
            // A resposta é a última fala do Claude, se depois dela ele não usou mais ferramenta
            // (se usou, o turno ainda está no meio do trabalho e a fala é parte do caminho).
            let marcos: Set<PassoConversa.Tipo> = [.pensamento, .interrupcao]
            if let k = falas.lastIndex(where: { !$0.text.isEmpty || !$0.images.isEmpty }),
               falas[k...].allSatisfy({ $0.passos.allSatisfy { marcos.contains($0.tipo) } }) {
                var resposta = falas[k]
                // Marco junto da resposta (interrupção) continua no caminho.
                let sobra = resposta.passos
                resposta.passos = []
                turnos[i].answer = resposta
                if sobra.isEmpty { falas.remove(at: k) }
                else { falas[k] = SessionMessage(id: resposta.id, fromUser: false, text: "", passos: sobra) }
            }
            var caminho: [ItemCaminho] = []
            for m in falas {
                if !m.text.isEmpty || !m.images.isEmpty { caminho.append(.fala(m)) }
                for p in m.passos {
                    // Sequência do mesmo tipo vira um grupo.
                    if agrupaveis.contains(p.tipo), let anterior = caminho.last {
                        if case .passo(let a) = anterior, a.tipo == p.tipo {
                            caminho[caminho.count - 1] = .grupo(id: a.id, tipo: p.tipo, passos: [a, p]); continue
                        }
                        if case .grupo(let gid, let tipo, let ps) = anterior, tipo == p.tipo {
                            caminho[caminho.count - 1] = .grupo(id: gid, tipo: tipo, passos: ps + [p]); continue
                        }
                    }
                    caminho.append(.passo(p))
                }
            }
            turnos[i].caminho = caminho
        }
        return turnos
    }

    /// "5 comandos · leu 6 arquivos · editou 2": o que o turno fez, numa linha.
    var resumoDoCaminho: String {
        var n: [PassoConversa.Tipo: Int] = [:]
        var arquivosLidos = Set<String>(), arquivosEditados = Set<String>()
        var erros = 0, negados = 0
        for p in passos {
            n[p.tipo, default: 0] += 1
            if p.tipo == .leitura { arquivosLidos.insert(p.tecnico) }
            if p.tipo == .edicao || p.tipo == .escrita { arquivosEditados.insert(p.tecnico) }
            if p.resultado?.negado != nil { negados += 1 } else if p.resultado?.erro == true { erros += 1 }
        }
        let pl = LeitorPassos.plural
        var partes: [String] = []
        if let c = n[.comando] { partes.append(pl(c, "comando", "comandos")) }
        if !arquivosLidos.isEmpty { partes.append("leu " + pl(arquivosLidos.count, "arquivo", "arquivos")) }
        if !arquivosEditados.isEmpty { partes.append("mexeu em " + pl(arquivosEditados.count, "arquivo", "arquivos")) }
        if let c = n[.busca] { partes.append(pl(c, "busca", "buscas")) }
        if let c = n[.agente] { partes.append(pl(c, "agente", "agentes")) }
        if let c = n[.web] { partes.append(pl(c, "consulta à web", "consultas à web")) }
        if let c = n[.navegador] { partes.append(pl(c, "ação no navegador", "ações no navegador")) }
        let outras = (n[.outro] ?? 0) + (n[.skill] ?? 0) + (n[.mensagem] ?? 0) + (n[.pergunta] ?? 0)
        if outras > 0 { partes.append(pl(outras, "outra ferramenta", "outras ferramentas")) }
        if erros > 0 { partes.append(pl(erros, "erro", "erros")) }
        if negados > 0 { partes.append(pl(negados, "bloqueado", "bloqueados")) }
        if n[.interrupcao] != nil { partes.append("interrompido") }
        return partes.joined(separator: " · ")
    }

    /// Passos de ferramenta de verdade (sem "pensou" nem marco de interrupção).
    var totalDePassos: Int { passos.filter { $0.tipo != .pensamento && $0.tipo != .interrupcao }.count }
    var temErro: Bool { passos.contains { $0.resultado?.erro == true } }
}
