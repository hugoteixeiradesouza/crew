import Foundation

// Leitura dos transcripts locais do Claude Code (`~/.claude/projects/<pasta>/*.jsonl`, e os dos
// subagentes em `<sessão>/subagents/*.jsonl`) para somar o uso de tokens. Nada de rede.
//
// Cada linha `type: "assistant"` traz `message.model`, `message.usage`, `timestamp`, `sessionId` e
// `cwd`. A mesma mensagem (`message.id`) aparece em várias linhas seguidas — uma por bloco de
// conteúdo, com a contagem de saída crescendo — e também copiada em outro arquivo quando a sessão é
// retomada ou bifurcada. Regra: dentro do arquivo, a última linha da mensagem vale (soma-se só a
// diferença); entre arquivos, a mensagem conta uma vez só.
//
// Incremental: guarda por arquivo até onde já leu (só até a última quebra de linha) e retoma dali.
// Tudo aqui é puro e roda fora da main.

/// Tokens somados de um balde (dia × sessão × modelo).
struct Tokens: Codable, Sendable, Equatable {
    var entrada: Int64 = 0
    var saida: Int64 = 0
    var escrita5m: Int64 = 0
    var escrita1h: Int64 = 0
    var leituraCache: Int64 = 0
    var mensagens: Int = 0
    /// Mensagens no modo rápido (preço diferente).
    var rapidas: Int = 0

    var escrita: Int64 { escrita5m + escrita1h }
    var total: Int64 { entrada + saida + escrita5m + escrita1h + leituraCache }

    static func + (a: Tokens, b: Tokens) -> Tokens {
        Tokens(entrada: a.entrada + b.entrada, saida: a.saida + b.saida, escrita5m: a.escrita5m + b.escrita5m,
               escrita1h: a.escrita1h + b.escrita1h, leituraCache: a.leituraCache + b.leituraCache,
               mensagens: a.mensagens + b.mensagens, rapidas: a.rapidas + b.rapidas)
    }
    static func += (a: inout Tokens, b: Tokens) { a = a + b }

    /// O que `b` tem a mais que `a` (nunca negativo).
    static func delta(_ b: Tokens, menos a: Tokens) -> Tokens {
        Tokens(entrada: max(0, b.entrada - a.entrada), saida: max(0, b.saida - a.saida),
               escrita5m: max(0, b.escrita5m - a.escrita5m), escrita1h: max(0, b.escrita1h - a.escrita1h),
               leituraCache: max(0, b.leituraCache - a.leituraCache))
    }
}

/// Estado guardado em disco (`uso.json`): os baldes somados e até onde cada arquivo foi lido.
struct EstadoUso: Codable, Sendable {
    static let versaoAtual = 1
    /// Dias guardados. Mensagem mais velha que isso é ignorada (e sai da memória de duplicadas).
    static let diasGuardados = 60

    struct Arquivo: Codable, Sendable {
        var fim: UInt64
        /// Última mensagem contada neste arquivo, para somar só a diferença se a próxima linha for dela.
        var ultimo: Ultimo?
    }
    struct Ultimo: Codable, Sendable {
        var hash: UInt64
        var chave: String
        var contado: Tokens
    }
    struct Sessao: Codable, Sendable {
        var cwd: String?
        /// Transcript principal (não o de subagente), para o título.
        var caminho: String?
        var ultima: Double = 0
    }

    var versao = versaoAtual
    var arquivos: [String: Arquivo] = [:]
    /// Chave "dia|sessão|modelo" → tokens. `dia` = dias locais desde 1970.
    var baldes: [String: Tokens] = [:]
    var sessoes: [String: Sessao] = [:]
    /// Hash do `message.id` já contado, por dia (para esquecer os velhos).
    var vistos: [String: [UInt64]] = [:]

    static func chave(dia: Int, sessao: String, modelo: String) -> String { "\(dia)|\(sessao)|\(modelo)" }

    static func partes(_ chave: String) -> (dia: Int, sessao: String, modelo: String)? {
        let p = chave.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
        guard p.count == 3, let d = Int(p[0]) else { return nil }
        return (d, String(p[1]), String(p[2]))
    }
}

enum LeitorTranscripts {
    struct Resultado: Sendable {
        var estado: EstadoUso
        var arquivosLidos = 0
        var bytesLidos: UInt64 = 0
        var mensagensNovas = 0
        var segundos: Double = 0
    }

    static var raizPadrao: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects", isDirectory: true)
    }

    // MARK: Datas

    /// Dia local (dias desde 1970 no fuso do Mac) de um instante.
    static func dia(_ t: Double, fuso: TimeZone = .current) -> Int {
        let off = Double(fuso.secondsFromGMT(for: Date(timeIntervalSince1970: t)))
        return Int(((t + off) / 86400).rounded(.down))
    }

    static func hoje() -> Int { dia(Date().timeIntervalSince1970) }

    /// "2026-09-21T17:39:13.165Z" → segundos desde 1970 (UTC). Sem formatter: é chamado dezenas de milhares de vezes.
    static func instante(_ s: String) -> Double? {
        let u = Array(s.utf8)
        guard u.count >= 19, u[4] == 45, u[7] == 45, u[10] == 84 else { return nil }
        func n(_ a: Int, _ b: Int) -> Int? {
            var v = 0
            for i in a..<b { let c = Int(u[i]) - 48; guard c >= 0 && c <= 9 else { return nil }; v = v * 10 + c }
            return v
        }
        guard let y = n(0, 4), let mo = n(5, 7), let d = n(8, 10), let h = n(11, 13), let mi = n(14, 16), let se = n(17, 19)
        else { return nil }
        // Dias desde 1970 a partir da data civil (algoritmo de Howard Hinnant).
        let yy = mo <= 2 ? y - 1 : y
        let era = (yy >= 0 ? yy : yy - 399) / 400
        let yoe = yy - era * 400
        let doy = (153 * (mo + (mo > 2 ? -3 : 9)) + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        let dias = era * 146097 + doe - 719468
        var t = Double(dias * 86400 + h * 3600 + mi * 60 + se)
        if u.count > 20, u[19] == 46 {  // fração de segundo
            var i = 20, f = 0.0, escala = 0.1
            while i < u.count, u[i] >= 48, u[i] <= 57 { f += Double(u[i] - 48) * escala; escala /= 10; i += 1 }
            t += f
        }
        return t
    }

    /// FNV-1a de 64 bits (memória de duplicadas compacta).
    static func hash(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }
        return h
    }

    // MARK: Linha

    private struct Linha: Decodable {
        let type: String?
        let timestamp: String?
        let sessionId: String?
        let cwd: String?
        let message: Mensagem?
    }
    private struct Mensagem: Decodable {
        let id: String?
        let model: String?
        let usage: Uso?
    }
    private struct Uso: Decodable {
        let input_tokens: Int64?
        let output_tokens: Int64?
        let cache_creation_input_tokens: Int64?
        let cache_read_input_tokens: Int64?
        let cache_creation: Criacao?
        let speed: String?
    }
    private struct Criacao: Decodable {
        let ephemeral_5m_input_tokens: Int64?
        let ephemeral_1h_input_tokens: Int64?
    }

    // MARK: Leitura

    /// Lê o que é novo em `raiz` e devolve o estado atualizado. `estado` vem do disco (ou vazio).
    static func atualizar(_ estado: EstadoUso, raiz: URL = raizPadrao, agora: Date = Date()) -> Resultado {
        let inicio = Date()
        var r = Resultado(estado: estado)
        let hojeDia = dia(agora.timeIntervalSince1970)
        let corte = hojeDia - EstadoUso.diasGuardados

        // Memória de duplicadas: esquece os dias que já saíram da janela.
        for k in r.estado.vistos.keys where (Int(k) ?? 0) < corte { r.estado.vistos.removeValue(forKey: k) }
        for k in r.estado.baldes.keys where (EstadoUso.partes(k)?.dia ?? 0) < corte { r.estado.baldes.removeValue(forKey: k) }
        var vistos = Set<UInt64>()
        for l in r.estado.vistos.values { vistos.formUnion(l) }

        let arquivos = listar(raiz)
        let existentes = Set(arquivos.map(\.caminho))
        for k in r.estado.arquivos.keys where !existentes.contains(k) { r.estado.arquivos.removeValue(forKey: k) }

        let limiteIdade = agora.timeIntervalSince1970 - Double(EstadoUso.diasGuardados + 1) * 86400
        for a in arquivos {
            var pos = r.estado.arquivos[a.caminho] ?? EstadoUso.Arquivo(fim: 0)
            if a.tamanho < pos.fim { pos = EstadoUso.Arquivo(fim: 0) }   // arquivo trocado: relê (duplicadas já filtradas)
            guard a.tamanho > pos.fim else { continue }
            // Arquivo nunca lido e parado há mais que a janela: só marca até onde vai, sem ler.
            if pos.fim == 0, a.modificado < limiteIdade {
                r.estado.arquivos[a.caminho] = EstadoUso.Arquivo(fim: a.tamanho)
                continue
            }
            let lido = lerArquivo(a.caminho, de: pos, subagente: a.subagente, estado: &r.estado,
                                  vistos: &vistos, corte: corte)
            r.estado.arquivos[a.caminho] = lido.pos
            r.arquivosLidos += 1
            r.bytesLidos += lido.pos.fim - pos.fim
            r.mensagensNovas += lido.novas
        }
        r.segundos = Date().timeIntervalSince(inicio)
        return r
    }

    private struct ArquivoEncontrado { let caminho: String; let tamanho: UInt64; let modificado: Double; let subagente: Bool }

    private static func listar(_ raiz: URL) -> [ArquivoEncontrado] {
        let fm = FileManager.default
        let chaves: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        guard let e = fm.enumerator(at: raiz, includingPropertiesForKeys: chaves,
                                    options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var out: [ArquivoEncontrado] = []
        for case let url as URL in e where url.pathExtension == "jsonl" {
            guard let v = try? url.resourceValues(forKeys: Set(chaves)), v.isRegularFile == true else { continue }
            out.append(ArquivoEncontrado(caminho: url.path, tamanho: UInt64(v.fileSize ?? 0),
                                         modificado: v.contentModificationDate?.timeIntervalSince1970 ?? 0,
                                         subagente: url.path.contains("/subagents/")))
        }
        // Mais antigos primeiro: a cópia de uma mensagem (sessão retomada) conta para a sessão original.
        return out.sorted { $0.modificado < $1.modificado }
    }

    private static let marcaAssistente = Array("\"type\":\"assistant\"".utf8)
    private static let marcaUso = Array("\"usage\"".utf8)

    private static func lerArquivo(_ caminho: String, de inicio: EstadoUso.Arquivo, subagente: Bool,
                                   estado: inout EstadoUso, vistos: inout Set<UInt64>, corte: Int)
        -> (pos: EstadoUso.Arquivo, novas: Int) {
        var pos = inicio
        var novas = 0
        guard let fh = FileHandle(forReadingAtPath: caminho) else { return (pos, 0) }
        defer { try? fh.close() }
        do { try fh.seek(toOffset: pos.fim) } catch { return (pos, 0) }
        let decoder = JSONDecoder()
        var resto = Data()
        let bloco = 8 << 20
        while true {
            guard let pedaco = try? fh.read(upToCount: bloco), !pedaco.isEmpty else { break }
            var dados = resto
            dados.append(pedaco)
            // Só até a última quebra de linha: a linha sendo escrita fica para a próxima leitura.
            guard let ultimaQuebra = dados.lastIndex(of: 10) else { resto = dados; continue }
            let completo = dados[dados.startIndex...ultimaQuebra]
            resto = Data(dados[dados.index(after: ultimaQuebra)...])
            completo.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
                guard let base = buf.baseAddress else { return }
                var i = 0
                let n = buf.count
                while i < n {
                    let p = base + i
                    let fimLinha: Int
                    if let q = memchr(p, 10, n - i) { fimLinha = base.distance(to: UnsafeRawPointer(q)) } else { fimLinha = n }
                    let tam = fimLinha - i
                    if tam > 40, contem(p, tam, marcaAssistente), contem(p, tam, marcaUso) {
                        let linha = Data(bytes: p, count: tam)
                        if let l = try? decoder.decode(Linha.self, from: linha), l.type == "assistant" {
                            if processar(l, caminho: caminho, subagente: subagente, pos: &pos,
                                         estado: &estado, vistos: &vistos, corte: corte) { novas += 1 }
                        }
                    }
                    i = fimLinha + 1
                }
            }
            pos.fim += UInt64(completo.count)
        }
        return (pos, novas)
    }

    private static func contem(_ p: UnsafeRawPointer, _ n: Int, _ padrao: [UInt8]) -> Bool {
        padrao.withUnsafeBytes { memmem(p, n, $0.baseAddress, $0.count) != nil }
    }

    /// Soma uma linha de assistente. Devolve true se era mensagem nova.
    private static func processar(_ l: Linha, caminho: String, subagente: Bool, pos: inout EstadoUso.Arquivo,
                                  estado: inout EstadoUso, vistos: inout Set<UInt64>, corte: Int) -> Bool {
        guard let m = l.message, let u = m.usage, let modelo = m.model, !modelo.hasPrefix("<"),
              let ts = l.timestamp, let t = instante(ts) else { return false }
        let d = dia(t)
        guard d >= corte else { return false }
        let sessao = l.sessionId ?? "?"
        var tk = Tokens()
        tk.entrada = u.input_tokens ?? 0
        tk.saida = u.output_tokens ?? 0
        let criacao = u.cache_creation_input_tokens ?? 0
        if let c = u.cache_creation {
            tk.escrita1h = c.ephemeral_1h_input_tokens ?? 0
            tk.escrita5m = max(0, criacao - tk.escrita1h)
        } else {
            tk.escrita5m = criacao
        }
        tk.leituraCache = u.cache_read_input_tokens ?? 0

        // Sessão: cwd, transcript principal e última atividade.
        var s = estado.sessoes[sessao] ?? EstadoUso.Sessao()
        if s.cwd == nil, let c = l.cwd, !c.isEmpty { s.cwd = c }
        if !subagente, s.caminho == nil { s.caminho = caminho }
        s.ultima = max(s.ultima, t)
        estado.sessoes[sessao] = s

        let h = hash(m.id ?? (ts + sessao))
        // Mesma mensagem da linha anterior deste arquivo: soma só o que cresceu.
        if let ult = pos.ultimo, ult.hash == h {
            let delta = Tokens.delta(tk, menos: ult.contado)
            if delta.total > 0 { estado.baldes[ult.chave, default: Tokens()] += delta }
            pos.ultimo?.contado = Tokens(entrada: max(tk.entrada, ult.contado.entrada), saida: max(tk.saida, ult.contado.saida),
                                         escrita5m: max(tk.escrita5m, ult.contado.escrita5m),
                                         escrita1h: max(tk.escrita1h, ult.contado.escrita1h),
                                         leituraCache: max(tk.leituraCache, ult.contado.leituraCache))
            return false
        }
        // Já contada em outro arquivo (sessão retomada/bifurcada) ou mais acima.
        guard !vistos.contains(h) else { pos.ultimo = nil; return false }
        vistos.insert(h)
        estado.vistos[String(d), default: []].append(h)

        let chave = EstadoUso.chave(dia: d, sessao: sessao, modelo: modelo)
        var soma = tk
        soma.mensagens = 1
        soma.rapidas = u.speed == "fast" ? 1 : 0
        estado.baldes[chave, default: Tokens()] += soma
        pos.ultimo = EstadoUso.Ultimo(hash: h, chave: chave, contado: tk)
        return true
    }

    // MARK: Disco

    static var arquivoEstado: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("NotchBuddy/uso.json")
    }

    static func carregar(_ url: URL = arquivoEstado) -> EstadoUso {
        guard let d = try? Data(contentsOf: url),
              let e = try? JSONDecoder().decode(EstadoUso.self, from: d),
              e.versao == EstadoUso.versaoAtual else { return EstadoUso() }
        return e
    }

    static func salvar(_ e: EstadoUso, _ url: URL = arquivoEstado) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let d = try? JSONEncoder().encode(e) else { return }
        try? d.write(to: url, options: .atomic)
    }
}
