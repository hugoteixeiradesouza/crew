import Foundation

// MARK: - Conversa com as sessões do Claude Code, sem chave de API
// Ler: o transcript local da sessão (caminho chega pelos hooks).
// Falar: pelo Xirp — `xirp session message` digita na sessão aberta e
// `xirp session new` abre uma nova. Sessão fora do Xirp só pode ser lida.

struct SessionMessage: Identifiable, Equatable {
    let id: Int          // posição no transcript — estável entre releituras
    let fromUser: Bool
    let text: String
    var images: [Data] = []   // imagens anexadas (PNG/JPEG do transcript)
    /// Mensagem do Hugo esperando na fila do Claude Code (enviada com ele ocupado)
    var naFila = false
    /// Marco de "conversa resumida": o Claude Code compactou o contexto aqui. O resumão que ele
    /// grava no transcript como se fosse fala do Hugo não é conversa e não aparece.
    var resumo = false
    /// O que o Claude fez nesta altura do turno: as ferramentas usadas, com o resultado de cada
    /// uma (`PassosConversa.swift`). Fala só com passos tem `text` vazio.
    var passos: [PassoConversa] = []
    /// Marco de fim de turno: quanto ele levou (o Claude Code grava ao terminar).
    var duracaoTurno: TimeInterval?
    /// Modo de permissão em que o pedido foi feito ("auto", "default", "acceptEdits", "plan"…).
    var modoPermissao: String?

    /// É fala de verdade (texto, imagem ou marco de resumo), não só passos ou marco de tempo.
    var ehFala: Bool { !text.isEmpty || !images.isEmpty || resumo }
}

enum TranscriptReader {
    /// Últimas falas (Hugo e Claude) da sessão. O JSONL é formato interno do
    /// Claude Code: o que não reconhecer é ignorado, nunca quebra.
    /// Só as falas (é o que a ilha mostra); os passos das ferramentas vêm por `ler`.
    static func messages(path: String?, limit: Int = 40) -> [SessionMessage] {
        ler(path: path, limit: limit).mensagens.filter(\.ehFala).map { m in
            var f = m; f.passos = []; return f
        }
    }

    /// Uma linha do transcript já interpretada. O transcript só cresce e linha escrita não muda:
    /// cada uma é interpretada uma vez só (imagem em base64 pesa) e guardada pela posição.
    private struct LinhaLida {
        var msg: SessionMessage?
        /// É um pedido do Hugo: o turno em andamento começa nele.
        var ehPedido = false
        var quando: Date?
        /// Resposta do Claude: id dela e quantos tokens já tinha escrito.
        var respostaId: String?
        var tokens = 0
        /// Resultados de ferramenta que a linha traz, pelo id do uso.
        var resultados: [String: ResultadoPasso] = [:]
    }

    nonisolated(unsafe) private static var linhasGuardadas: [String: [Int: LinhaLida]] = [:]
    nonisolated(unsafe) private static var janelasBoas: [String: UInt64] = [:]
    private static let travaLinhas = NSLock()

    /// Lê só o fim do transcript, de trás para a frente, e para assim que juntou as `limit`
    /// falas mais recentes: abrir uma conversa longa não relê nem reinterpreta a conversa
    /// inteira, e reler enquanto o Claude escreve só interpreta as linhas novas.
    static func ler(path: String?, limit: Int) -> LeituraConversa {
        guard let path, let fh = FileHandle(forReadingAtPath: path) else { return LeituraConversa() }
        defer { try? fh.close() }
        let size = (try? fh.seekToEnd()) ?? 0
        travaLinhas.lock()
        var guardadas = linhasGuardadas[path] ?? [:]
        // Começa pela janela que serviu da última vez: conversa com passos longos precisa de
        // vários MB para juntar as falas, e reler crescendo de 1 MB em 1 MB a cada 0,8 s lia o
        // mesmo fim de arquivo três ou quatro vezes.
        var janela: UInt64 = janelasBoas[path] ?? 1_000_000
        travaLinhas.unlock()
        let teto: UInt64 = 64_000_000
        var r: (leitura: LeituraConversa, parouCedo: Bool, menor: Int)
        while true {
            let start = size > janela ? size - janela : 0
            r = lerJanela(fh, de: start, limit: limit, guardadas: &guardadas)
            if r.parouCedo || start == 0 || janela >= teto {
                r.leitura.temMais = r.parouCedo
                break
            }
            janela *= 4
        }
        // Guarda só as linhas que ainda estão em uso (do começo do que se mostra para a frente).
        let menor = r.menor
        guardadas = guardadas.filter { $0.key >= menor }
        travaLinhas.lock()
        if linhasGuardadas.count > 6, linhasGuardadas[path] == nil { linhasGuardadas.removeAll(); janelasBoas.removeAll() }
        linhasGuardadas[path] = guardadas
        // A menor janela (1, 4, 16, 64 MB) que cobre do começo do que se mostra até o fim, com folga.
        let usado = menor == Int.max ? 0 : size - min(size, UInt64(menor))
        var boa: UInt64 = 1_000_000
        while boa < teto, boa < usado + usado / 4 { boa *= 4 }
        janelasBoas[path] = boa
        travaLinhas.unlock()
        return r.leitura
    }

    private static let marcaFila = Data("queue-operation".utf8)
    private static let marcasDeFala = [Data("\"type\":\"user\"".utf8), Data("\"type\":\"assistant\"".utf8),
                                       Data("queued_command".utf8), Data("turn_duration".utf8)]

    private static func lerJanela(_ fh: FileHandle, de start: UInt64, limit: Int,
                                  guardadas: inout [Int: LinhaLida]) -> (leitura: LeituraConversa, parouCedo: Bool, menor: Int) {
        try? fh.seek(toOffset: start)
        guard let lido = try? fh.readToEnd() else { return (LeituraConversa(), false, Int.max) }
        let data = Data(lido)   // índices a partir de zero
        // Onde começa e termina cada linha.
        var linhas: [(lo: Int, hi: Int)] = []
        var lo = 0
        while lo < data.count {
            let hi = data[lo...].firstIndex(of: 0x0A) ?? data.count
            if hi > lo { linhas.append((lo, hi)) }
            lo = hi + 1
        }

        // Fila do Claude Code (o que o Hugo mandou com ele ocupado e ainda não foi lido):
        // precisa da ordem em que aconteceu. São linhas pequenas e raras.
        var fila: [(id: Int, texto: String)] = []
        for l in linhas where data.range(of: marcaFila, in: l.lo..<l.hi) != nil {
            guard let obj = try? JSONSerialization.jsonObject(with: data[l.lo..<l.hi]) as? [String: Any],
                  obj["type"] as? String == "queue-operation" else { continue }
            let texto = (obj["content"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            switch obj["operation"] as? String {
            case "enqueue": fila.append((Int(start) + l.lo, texto))
            case "remove": if let k = fila.firstIndex(where: { $0.texto == texto }) { fila.remove(at: k) }
            case "dequeue": if !fila.isEmpty { fila.removeFirst() }
            case "popAll": fila.removeAll()
            default: break
            }
        }

        // Falas, da mais nova para a mais antiga, até juntar as pedidas.
        var falas: [SessionMessage] = []
        var nFalas = 0
        // Os resultados vêm depois dos usos no arquivo: lendo de trás para a frente, já estão
        // aqui quando o uso aparece.
        var resultados: [String: ResultadoPasso] = [:]
        var porResposta: [String: Int] = [:]
        var inicio: Date?
        var turnoAchado = false
        var parouCedo = false
        var menor = Int.max
        for l in linhas.reversed() {
            let pos = Int(start) + l.lo
            let linha: LinhaLida
            if let g = guardadas[pos] {
                linha = g
            } else {
                linha = interpretar(data, l.lo..<l.hi, id: pos)
                // A última linha pode estar pela metade (sendo escrita): só guarda linha fechada.
                if l.hi < data.count { guardadas[pos] = linha }
            }
            if !turnoAchado {
                if let rid = linha.respostaId { porResposta[rid] = max(porResposta[rid] ?? 0, linha.tokens) }
                if linha.ehPedido { inicio = linha.quando; turnoAchado = true }
            }
            if !linha.resultados.isEmpty { resultados.merge(linha.resultados) { a, _ in a } }
            if var m = linha.msg {
                for k in m.passos.indices where m.passos[k].resultado == nil {
                    guard let r = resultados[m.passos[k].id] else { continue }
                    m.passos[k].resultado = r
                    if let fim = r.quando, let ini = m.passos[k].quando { m.passos[k].duracao = fim.timeIntervalSince(ini) }
                }
                falas.append(m); menor = pos
                if m.ehFala { nFalas += 1 }
            }
            // O limite conta falas (pedido, resposta), não passos de ferramenta.
            if nFalas >= limit, turnoAchado { parouCedo = l.lo > 0; break }
        }
        var out = Array(falas.reversed())
        // Ainda na fila: aparece no fim, marcada, até o Claude ler
        for f in fila {
            let texto = TextoDoPedido.limpar(f.texto)
            if !texto.isEmpty { out.append(SessionMessage(id: f.id, fromUser: true, text: texto, naFila: true)) }
        }
        let andamento = AndamentoTurno(inicio: inicio, tokens: porResposta.values.reduce(0, +))
        return (LeituraConversa(mensagens: out, temMais: false, andamento: andamento), parouCedo, menor)
    }

    /// Interpreta uma linha do transcript. O JSONL é formato interno do Claude Code: o que não
    /// reconhecer vira linha vazia, nunca quebra.
    private static func interpretar(_ data: Data, _ faixa: Range<Int>, id: Int) -> LinhaLida {
        // Atalho barato: só decodifica as linhas que interessam
        guard marcasDeFala.contains(where: { data.range(of: $0, in: faixa) != nil }),
              let obj = try? JSONSerialization.jsonObject(with: data[faixa]) as? [String: Any],
              let type = obj["type"] as? String else { return LinhaLida() }
        let quando = (obj["timestamp"] as? String).flatMap { instante(iso: $0) }
        // Mensagem lida no meio do turno: vira fala do Hugo na conversa. O pedido vem como texto
        // ou, quando tem imagem colada, como lista de blocos (texto + imagem).
        if type == "attachment", let a = obj["attachment"] as? [String: Any] {
            guard a["type"] as? String == "queued_command", a["commandMode"] as? String ?? "prompt" == "prompt",
                  (a["origin"] as? [String: Any])?["kind"] as? String ?? "human" == "human" else { return LinhaLida() }
            let (bruto, imagens) = conteudo(a["prompt"])
            let t = TextoDoPedido.limpar(bruto, humano: (a["origin"] as? [String: Any])?["kind"] as? String == "human")
            guard !t.isEmpty || !imagens.isEmpty else { return LinhaLida() }
            return LinhaLida(msg: SessionMessage(id: id, fromUser: true, text: t, images: imagens))
        }
        // Fim de turno: quanto levou.
        if type == "system" {
            guard obj["subtype"] as? String == "turn_duration", let ms = obj["durationMs"] as? Double else { return LinhaLida() }
            return LinhaLida(msg: SessionMessage(id: id, fromUser: false, text: "", duracaoTurno: ms / 1000))
        }
        guard type == "user" || type == "assistant",
              obj["isSidechain"] as? Bool != true,
              let msg = obj["message"] as? [String: Any] else { return LinhaLida() }
        var linha = LinhaLida()
        let partes = msg["content"] as? [[String: Any]] ?? []
        // Resultado de ferramenta (vem numa linha "user", que não é fala do Hugo).
        if type == "user" {
            for p in partes where p["type"] as? String == "tool_result" {
                guard let uso = p["tool_use_id"] as? String else { continue }
                linha.resultados[uso] = LeitorPassos.resultado(bloco: p, estruturado: obj["toolUseResult"], quando: quando)
            }
            if !linha.resultados.isEmpty { return linha }
        }
        guard obj["isMeta"] as? Bool != true else { return linha }
        if obj["isCompactSummary"] as? Bool == true {
            return LinhaLida(msg: SessionMessage(id: id, fromUser: false, text: "", resumo: true))
        }
        if type == "assistant", let mid = msg["id"] as? String,
           let n = (msg["usage"] as? [String: Any])?["output_tokens"] as? Int {
            linha.respostaId = mid
            linha.tokens = n
        }
        var (text, images) = conteudo(msg["content"])
        var passos: [PassoConversa] = []
        if type == "assistant" {
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            for (k, p) in partes.enumerated() {
                switch p["type"] as? String {
                case "tool_use":
                    guard let uso = p["id"] as? String, let nome = p["name"] as? String else { continue }
                    passos.append(LeitorPassos.passo(id: uso, nome: nome, entrada: p["input"] as? [String: Any] ?? [:], quando: quando))
                case "thinking":
                    // Só o tempo: o raciocínio em si não é mostrado.
                    if let ms = obj["thinkingDurationMs"] as? Double, ms >= 1000 {
                        passos.append(LeitorPassos.pensamento(id: "pensou-\(id)-\(k)", ms: Int(ms), quando: quando))
                    }
                default: break
                }
            }
        } else {
            // Aviso do Claude Code de que o Hugo interrompeu: não é fala dele, é um marco do turno.
            if TextoDoPedido.ehInterrupcao(text) {
                linha.msg = SessionMessage(id: id, fromUser: false, text: "",
                                           passos: [LeitorPassos.interrupcao(id: "parou-\(id)", quando: quando)])
                return linha
            }
            // Retorno de um comando do Hugo (/model, /context, ! ls): fica na conversa, logo
            // depois do comando, como resposta — não é fala dele.
            if let saida = TextoDoPedido.saidaDeComando(text) {
                linha.msg = SessionMessage(id: id, fromUser: false, text: saida)
                return linha
            }
            // Quem mandou: o transcript diz (teclado do Hugo, aviso de tarefa, outra sessão).
            let origem = (obj["origin"] as? [String: Any])?["kind"] as? String
            if let origem, origem != "human" { return linha }
            // Texto colado vem embrulhado em marcas; lembrete do sistema sai; o resto é dele.
            text = TextoDoPedido.limpar(text, humano: origem == "human")
        }
        guard !text.isEmpty || !images.isEmpty || !passos.isEmpty else { return linha }
        if type == "user" {
            linha.ehPedido = true
            linha.quando = quando
        }
        linha.msg = SessionMessage(id: id, fromUser: type == "user", text: text, images: images, passos: passos,
                                   modoPermissao: type == "user" ? obj["permissionMode"] as? String : nil)
        return linha
    }

    /// Texto e imagens de um conteúdo do transcript: texto puro ou lista de blocos.
    private static func conteudo(_ c: Any?) -> (String, [Data]) {
        if let s = c as? String { return (s, []) }
        guard let partes = c as? [[String: Any]] else { return ("", []) }
        let texto = partes.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
            .joined(separator: "\n")
        let imagens: [Data] = partes.compactMap { p in
            guard p["type"] as? String == "image",
                  let src = p["source"] as? [String: Any],
                  let b64 = src["data"] as? String else { return nil }
            return Data(base64Encoded: b64)
        }
        return (texto, imagens)
    }

    /// Data ISO do transcript ("2026-11-13T03:15:13.874Z", sempre em UTC). Conta na mão: o
    /// `ISO8601DateFormatter` custava mais que o resto da leitura da linha.
    static func instante(iso s: String) -> Date? {
        let u = Array(s.utf8)
        guard u.count >= 20, u[4] == 45, u[7] == 45, u[10] == 84, u[13] == 58, u[16] == 58, u.last == 90 else { return nil }
        func n(_ de: Int, _ quantos: Int) -> Int? {
            var v = 0
            for k in de..<(de + quantos) {
                guard k < u.count, u[k] >= 48, u[k] <= 57 else { return nil }
                v = v * 10 + Int(u[k] - 48)
            }
            return v
        }
        guard let ano = n(0, 4), let mes = n(5, 2), let dia = n(8, 2), let h = n(11, 2), let mi = n(14, 2), let seg = n(17, 2),
              (1...12).contains(mes), (1...31).contains(dia) else { return nil }
        var fracao = 0.0
        if u[19] == 46 {
            var escala = 0.1
            for k in 20..<(u.count - 1) {
                guard u[k] >= 48, u[k] <= 57 else { return nil }
                fracao += Double(u[k] - 48) * escala
                escala /= 10
            }
        }
        // Dias desde 1970 pelo calendário gregoriano (algoritmo de "dias desde a era civil").
        let a = mes <= 2 ? ano - 1 : ano
        let era = (a >= 0 ? a : a - 399) / 400
        let anoDaEra = a - era * 400
        let diaDoAno = (153 * (mes + (mes > 2 ? -3 : 9)) + 2) / 5 + dia - 1
        let diaDaEra = anoDaEra * 365 + anoDaEra / 4 - anoDaEra / 100 + diaDoAno
        let dias = era * 146097 + diaDaEra - 719468
        return Date(timeIntervalSince1970: Double(dias * 86400 + h * 3600 + mi * 60 + seg) + fracao)
    }
}

/// O que se leu do fim do transcript.
struct LeituraConversa {
    var mensagens: [SessionMessage] = []
    /// Há falas mais antigas que não vieram nesta leitura.
    var temMais = false
    var andamento = AndamentoTurno()
}

extension TranscriptReader {
    /// Até onde cada transcript já foi lido e os títulos achados. O transcript só cresce:
    /// a cada pedido lê-se só o pedaço novo (antes relia até 1 MB a cada evento e a cada 40 s).
    private struct LeituraTitulo { var fim: UInt64; var custom: String?; var ai: String? }
    nonisolated(unsafe) private static var leituras: [String: LeituraTitulo] = [:]
    private static let travaLeituras = NSLock()

    /// Título da sessão: o do /rename, senão o que o Claude Code gera sozinho.
    static func title(path: String?) -> String? {
        guard let path, let fh = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? fh.close() }
        let size = (try? fh.seekToEnd()) ?? 0
        travaLeituras.lock()
        var l = leituras[path] ?? LeituraTitulo(fim: size > 1_000_000 ? size - 1_000_000 : 0)
        travaLeituras.unlock()
        if size < l.fim { l = LeituraTitulo(fim: size > 1_000_000 ? size - 1_000_000 : 0) }  // arquivo trocado
        guard size > l.fim else { return l.custom ?? l.ai }
        try? fh.seek(toOffset: l.fim)
        guard let data = try? fh.readToEnd() else { return l.custom ?? l.ai }
        // Só até a última quebra de linha: a linha sendo escrita fica para a próxima leitura.
        guard let ultimaQuebra = data.lastIndex(of: UInt8(ascii: "\n")) else { return l.custom ?? l.ai }
        let completo = data[data.startIndex...ultimaQuebra]
        let marca = Data("-title\"".utf8)
        for linha in completo.split(separator: UInt8(ascii: "\n")) where linha.range(of: marca) != nil {
            guard let o = try? JSONSerialization.jsonObject(with: Data(linha)) as? [String: Any] else { continue }
            if let c = o["customTitle"] as? String, !c.isEmpty { l.custom = c }
            if let a = o["aiTitle"] as? String, !a.isEmpty { l.ai = a }
        }
        l.fim += UInt64(completo.count)
        travaLeituras.lock()
        leituras[path] = l
        travaLeituras.unlock()
        return l.custom ?? l.ai
    }
}

/// Como vai o turno em andamento: desde quando o Claude trabalha no pedido e quantos tokens
/// já escreveu nele (o "1m 8s · ↓ 8.3k tokens" do terminal).
struct AndamentoTurno: Equatable {
    var inicio: Date?
    var tokens = 0
}

/// Um pedaço do pedido a entregar na sessão: texto digitado ou arquivo colado.
enum PecaEnvio: Equatable {
    case texto(String)
    case arquivo(URL)
}

struct XirpProject: Identifiable, Hashable {
    let id: String
    let name: String
    let path: String
}

enum Xirp {
    static var executable: String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [home + "/.local/share/chirp/cli/external/xirp", "/opt/homebrew/bin/xirp", "/usr/local/bin/xirp"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static var available: Bool { executable != nil }

    /// Roda o CLI fora da main. Devolve (saída, código).
    static func run(_ args: [String]) async -> (String, Int32) {
        guard let exe = executable else { return ("xirp não encontrado", -1) }
        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: exe)
                p.arguments = args
                // Saída e erro separados: aviso no stderr não pode estragar o JSON.
                let out = Pipe(), err = Pipe()
                p.standardOutput = out
                p.standardError = err
                do { try p.run() } catch { cont.resume(returning: (error.localizedDescription, -1)); return }
                let data = out.fileHandleForReading.readDataToEndOfFile()
                let errData = err.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                let text = p.terminationStatus == 0 ? data : (errData.isEmpty ? data : errData)
                cont.resume(returning: (String(data: text, encoding: .utf8) ?? "", p.terminationStatus))
            }
        }
    }

    private static func json(_ args: [String]) async -> Any? {
        let (out, code) = await run(args)
        guard code == 0 else { return nil }
        return try? JSONSerialization.jsonObject(with: Data(out.utf8))
    }

    /// Id da sessão no Xirp a partir do session_id do Claude Code (nil = não roda no Xirp).
    /// Busca direta pelo id (vale para sessões de qualquer projeto); reserva: lista de todos os projetos.
    /// (`session list` sem `--all` só enxerga o projeto da pasta de onde o Crew chama o CLI.)
    static func sessionId(forClaudeSession sid: String) async -> String? {
        if let s = await json(["session", "get", sid, "--json"]) as? [String: Any], let id = s["id"] as? String {
            return id
        }
        guard let list = await json(["session", "list", "--all", "--limit", "300", "--json"]) as? [[String: Any]]
        else { return nil }
        return list.first { ($0["cliSessionId"] as? String) == sid || ($0["id"] as? String) == sid }?["id"] as? String
    }

    /// Nome que o Hugo deu à sessão no Xirp (só se renomeada lá; nome automático não conta).
    static func customName(forClaudeSession sid: String) async -> String? {
        guard let s = await json(["session", "get", sid, "--json"]) as? [String: Any],
              s["isCustomName"] as? Bool == true,
              let name = s["name"] as? String, !name.isEmpty else { return nil }
        return name
    }

    static func projects() async -> [XirpProject] {
        guard let list = await json(["project", "list", "--json"]) as? [[String: Any]] else { return [] }
        return list.compactMap { p in
            guard let id = p["id"] as? String, let path = p["path"] as? String else { return nil }
            return XirpProject(id: id, name: p["name"] as? String ?? URL(fileURLWithPath: path).lastPathComponent, path: path)
        }
    }

    /// Manda texto para a sessão aberta, como se o Hugo digitasse e desse Enter.
    static func message(xirpId: String, text: String, enter: Bool = true) async -> String? {
        let (out, code) = await run(["session", "message", xirpId, text] + (enter ? [] : ["--no-enter"]))
        return code == 0 ? nil : out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Renomeia a sessão no Xirp (o nome que aparece na barra lateral de lá).
    static func rename(xirpId: String, name: String) async -> String? {
        let (out, code) = await run(["session", "update", xirpId, "--name", name])
        return code == 0 ? nil : out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Para a sessão no Xirp (encerra o Claude Code dela).
    static func stop(xirpId: String) async -> String? {
        let (out, code) = await run(["session", "stop", xirpId])
        return code == 0 ? nil : out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Abre uma sessão nova do Claude Code no projeto. Sem worktree do Xirp: o
    /// isolamento é o que o CLAUDE.md de cada projeto manda (ex.: scripts/sessao.sh).
    /// Devolve o id da sessão criada no Xirp, ou o erro.
    static func newSession(projectId: String, prompt: String) async -> Result<String?, NewSessionError> {
        let (out, code) = await run(["session", "new", "--goal", prompt, "--project", projectId,
                                     "--no-worktree", "--harness", "claude", "--json"])
        guard code == 0 else { return .failure(NewSessionError(message: out.trimmingCharacters(in: .whitespacesAndNewlines))) }
        let obj = try? JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any]
        let session = (obj?["session"] as? [String: Any]) ?? obj
        return .success((session?["cliSessionId"] as? String) ?? (session?["id"] as? String))
    }

    struct NewSessionError: Error { let message: String }
}

// MARK: - Responder sessões fora do Xirp
// Acha o terminal da sessão pelo tty do processo do Claude Code e entrega o texto lá:
// painel do tmux (send-keys), aba do Terminal da Apple (do script) ou do iTerm (write text).
// Ghostty, terminal do VS Code e Claude Desktop não aceitam texto de fora.

enum SessionChannel: Equatable {
    case xirp(String)
    case tmux(pane: String)
    case terminal(tty: String)
    case iterm(tty: String)
    case none(app: String)
}

enum TerminalBridge {
    /// tty do processo, ex.: "/dev/ttys012"
    static func tty(of pid: pid_t) async -> String? {
        let (out, code) = await run("/bin/ps", ["-o", "tty=", "-p", String(pid)])
        let t = out.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code == 0, !t.isEmpty, t != "??" else { return nil }
        return "/dev/" + t
    }

    static var tmuxPath: String? {
        ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func tmuxPane(forTTY tty: String) async -> String? {
        guard let tmux = tmuxPath else { return nil }
        let (out, code) = await run(tmux, ["list-panes", "-a", "-F", "#{pane_tty} #{pane_id}"])
        guard code == 0 else { return nil }
        return out.split(separator: "\n").first { $0.hasPrefix(tty + " ") }.map { String($0.split(separator: " ")[1]) }
    }

    /// Por onde dá para falar com a sessão.
    static func channel(claudePid: pid_t?, bundleId: String?, xirpId: String?) async -> SessionChannel {
        if let xirpId { return .xirp(xirpId) }
        if let pid = claudePid, let tty = await tty(of: pid) {
            if let pane = await tmuxPane(forTTY: tty) { return .tmux(pane: pane) }
            if bundleId == "com.apple.Terminal" { return .terminal(tty: tty) }
            if bundleId == "com.googlecode.iterm2" { return .iterm(tty: tty) }
        }
        let names = ["com.mitchellh.ghostty": "Ghostty", "com.microsoft.VSCode": "VS Code",
                     "com.anthropic.claudefordesktop": "Claude Desktop", "com.spotify.xirp": "Xirp"]
        return .none(app: bundleId.flatMap { names[$0] } ?? "app dela")
    }

    /// Arquivo "colado" (bracketed paste): o Claude Code transforma o caminho de uma imagem em
    /// anexo de verdade ([Image #1]); outro tipo de arquivo chega como caminho, que ele lê.
    static func colado(_ url: URL) -> String { "\u{1B}[200~" + url.path + "\u{1B}[201~" }

    /// Entrega o pedido em peças, na ordem: texto digitado e arquivo colado no ponto em que o
    /// Hugo pôs a marca ([Image #N]). O Claude Code troca cada caminho de imagem colado pelo
    /// anexo de verdade, no lugar certo da frase. nil = ok; senão, o erro.
    static func send(pecas: [PecaEnvio], via ch: SessionChannel) async -> String? {
        if case .xirp(let id) = ch {
            // (texto, enter). Quebra de linha no Xirp: "\\" + Enter no fim da linha.
            var ops: [(String, Bool)] = []
            var ultimaEhTexto = false
            for peca in pecas {
                switch peca {
                case .arquivo(let u):
                    ops.append((colado(u), false)); ultimaEhTexto = false
                case .texto(let t):
                    let linhas = t.components(separatedBy: "\n")
                    for l in linhas.dropLast() { ops.append((l + "\\", true)) }
                    if let fim = linhas.last, !fim.isEmpty { ops.append((fim, false)); ultimaEhTexto = true }
                    else { ultimaEhTexto = false }
                }
            }
            if ultimaEhTexto, let n = ops.indices.last { ops[n].1 = true } else { ops.append((" ", true)) }
            for (texto, enter) in ops {
                if let err = await Xirp.message(xirpId: id, text: texto, enter: enter) { return err }
            }
            return nil
        }
        let tudo = pecas.map { peca -> String in
            switch peca {
            case .arquivo(let u): return colado(u)
            case .texto(let t): return t.contains("\n") ? "\u{1B}[200~" + t + "\u{1B}[201~" : t
            }
        }.joined()
        return await entregar(tudo, via: ch)
    }

    /// Entrega o texto (com os anexos colados antes) e dá Enter. nil = ok; senão, o erro.
    static func send(_ text: String, anexos: [URL] = [], via ch: SessionChannel) async -> String? {
        // Várias linhas (Shift+Enter no chat): vai como colagem, senão cada quebra seria um Enter
        // e a mensagem chegaria pela metade.
        let textoEntregue = text.contains("\n") ? "\u{1B}[200~" + text + "\u{1B}[201~" : text
        if case .xirp(let id) = ch {
            for a in anexos {
                if let err = await Xirp.message(xirpId: id, text: colado(a), enter: false) { return err }
            }
            // O Xirp descarta a colagem (e a quebra junto). No Claude Code, "\\" + Enter no fim de
            // uma linha vira quebra de linha em vez de enviar: cada linha vai assim, a última envia.
            let linhas = text.components(separatedBy: "\n")
            for (i, linha) in linhas.dropLast().enumerated() {
                let l = (i == 0 && !anexos.isEmpty ? " " : "") + linha + "\\"
                if let err = await Xirp.message(xirpId: id, text: l) { return err }
            }
            let ultima = (linhas.count == 1 && !anexos.isEmpty ? " " : "") + (linhas.last ?? "")
            return await Xirp.message(xirpId: id, text: ultima)
        }
        return await entregar(anexos.isEmpty ? textoEntregue : anexos.map(colado).joined() + " " + textoEntregue, via: ch)
    }

    /// O campo do Claude Code (a última linha que começa com "❯") ainda mostra a mensagem?
    static func aindaNoCampo(_ tela: String, amostra: String, colou: Bool) -> Bool {
        let moldura = CharacterSet(charactersIn: "│┃| \t")
        guard let linha = tela.components(separatedBy: "\n").map({ $0.trimmingCharacters(in: moldura) })
            .last(where: { $0.hasPrefix("❯") || $0.hasPrefix(">") }) else { return false }
        let campo = linha.dropFirst().trimmingCharacters(in: .whitespaces)
        guard !campo.isEmpty else { return false }
        if !amostra.isEmpty, campo.hasPrefix(amostra) { return true }
        return colou && (campo.contains("[Pasted text") || campo.contains("[Image #"))
    }

    /// Digita o texto já montado no terminal da sessão e dá Enter (tmux, Terminal, iTerm).
    private static func entregar(_ text: String, via ch: SessionChannel) async -> String? {
        switch ch {
        case .xirp:
            return nil
        case .tmux(let pane):
            guard let tmux = tmuxPath else { return "tmux não encontrado" }
            let (o1, c1) = await run(tmux, ["send-keys", "-t", pane, "-l", text])
            if c1 != 0 { return o1 }
            // O Enter colado no texto era engolido: o Claude Code trata uma rajada de teclas como
            // colagem, e o Enter virava parte dela — a mensagem ficava no campo e só saía junto
            // com a seguinte. Espera o texto assentar (mais, se há colagem ou imagem) e só então envia.
            let colou = text.contains("\u{1B}[200~")
            try? await Task.sleep(for: .milliseconds(colou ? 450 : text.count > 400 ? 250 : 120))
            let (o2, c2) = await run(tmux, ["send-keys", "-t", pane, "Enter"])
            if c2 != 0 { return o2 }
            // Confere: se o texto continua no campo do Claude Code, o Enter não pegou — de novo.
            // Só reenvia vendo o próprio texto na linha do campo (nunca um Enter às cegas, que
            // poderia confirmar um pedido de permissão).
            let amostra = String(text.prefix { $0 != "\n" && $0 != "\u{1B}" }.trimmingCharacters(in: .whitespaces).prefix(16))
            for _ in 0..<2 {
                try? await Task.sleep(for: .milliseconds(550))
                let (tela, c3) = await run(tmux, ["capture-pane", "-p", "-t", pane])
                guard c3 == 0, aindaNoCampo(tela, amostra: amostra, colou: colou) else { break }
                _ = await run(tmux, ["send-keys", "-t", pane, "Enter"])
            }
            return nil
        case .terminal(let tty):
            return await osascript("""
            tell application "Terminal"
                repeat with w in windows
                    repeat with t in tabs of w
                        if tty of t is "\(tty)" then
                            do script \(appleString(text)) in t
                            return "ok"
                        end if
                    end repeat
                end repeat
            end tell
            return "não achei a aba"
            """)
        case .iterm(let tty):
            return await osascript("""
            tell application "iTerm2"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if tty of s is "\(tty)" then
                                tell s to write text \(appleString(text))
                                return "ok"
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            return "não achei a sessão"
            """)
        case .none(let app):
            return "Essa sessão roda no \(app), que não aceita texto de fora."
        }
    }

    private static func appleString(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private static func osascript(_ src: String) async -> String? {
        let (out, code) = await run("/usr/bin/osascript", ["-e", src])
        let r = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return code == 0 && r == "ok" ? nil : (r.isEmpty ? "falhou" : r)
    }

    private static func run(_ exe: String, _ args: [String]) async -> (String, Int32) {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: exe)
                p.arguments = args
                let out = Pipe(); p.standardOutput = out; p.standardError = out
                do { try p.run() } catch { cont.resume(returning: (error.localizedDescription, -1)); return }
                let d = out.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                cont.resume(returning: (String(data: d, encoding: .utf8) ?? "", p.terminationStatus))
            }
        }
    }
}
