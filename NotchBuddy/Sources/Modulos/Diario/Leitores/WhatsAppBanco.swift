import Foundation
import SQLite3

// Acesso ao banco local do WhatsApp para Mac — SÓ LEITURA, sempre fora da main.
// O banco fica nos Group Containers do WhatsApp e só abre com Acesso Total ao Disco (o Crew tem).
// Abre com `file:…?mode=ro`; se o SQLite recusar (WAL/shm em uso), copia .sqlite + -wal + -shm
// para uma pasta temporária, lê a cópia e apaga. Nunca escreve no banco do WhatsApp.

enum WhatsAppBanco {
    static var containers: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Group Containers")
    }

    /// Pastas de grupo do WhatsApp (shared, private, SMB, family).
    static func pastasGrupo() -> [URL] {
        let nomes = (try? FileManager.default.contentsOfDirectory(atPath: containers.path)) ?? []
        return nomes.filter { $0.lowercased().contains("whatsapp") }.sorted().map { containers.appendingPathComponent($0) }
    }

    /// Dá para listar a pasta do WhatsApp? (sem Acesso Total ao Disco, o macOS recusa)
    static func temAcesso() -> Bool {
        for p in pastasGrupo() {
            if (try? FileManager.default.contentsOfDirectory(atPath: p.path)) != nil { return true }
        }
        return false
    }

    static func sqlites(em raiz: URL, profundidade: Int = 4) -> [URL] {
        var r: [URL] = []
        func andar(_ u: URL, _ n: Int) {
            guard n >= 0, let itens = try? FileManager.default.contentsOfDirectory(at: u, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return }
            for i in itens {
                let v = try? i.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                if v?.isSymbolicLink == true { continue }
                if v?.isDirectory == true { andar(i, n - 1) }
                else if i.pathExtension == "sqlite" { r.append(i) }
            }
        }
        andar(raiz, profundidade)
        return r
    }

    // MARK: Abrir só leitura

    final class Conexao {
        let db: OpaquePointer
        private let copia: URL?
        init(db: OpaquePointer, copia: URL?) { self.db = db; self.copia = copia }
        deinit {
            sqlite3_close_v2(db)
            if let c = copia { try? FileManager.default.removeItem(at: c) }
        }

        func linhas(_ sql: String, _ binds: [Double] = [], _ cada: (OpaquePointer) -> Void) -> Bool {
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK, let st else { return false }
            defer { sqlite3_finalize(st) }
            for (i, b) in binds.enumerated() { sqlite3_bind_double(st, Int32(i + 1), b) }
            while sqlite3_step(st) == SQLITE_ROW { cada(st) }
            return true
        }
    }

    static func abrir(_ arquivo: URL) -> Conexao? {
        if let db = abrirRO(arquivo), testar(db) { return Conexao(db: db, copia: nil) }
        // Plano B: cópia temporária do banco com o WAL (leitura consistente sem tocar no original)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("crew-wa-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
            for suf in ["", "-wal", "-shm"] {
                let o = URL(fileURLWithPath: arquivo.path + suf)
                if FileManager.default.fileExists(atPath: o.path) {
                    try FileManager.default.copyItem(at: o, to: tmp.appendingPathComponent(arquivo.lastPathComponent + suf))
                }
            }
        } catch {
            try? FileManager.default.removeItem(at: tmp)
            return nil
        }
        let copia = tmp.appendingPathComponent(arquivo.lastPathComponent)
        var db: OpaquePointer?
        // A cópia é nossa: abre normal para o SQLite poder aplicar o WAL copiado
        guard sqlite3_open_v2(copia.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK, let db, testar(db) else {
            if let db { sqlite3_close_v2(db) }
            try? FileManager.default.removeItem(at: tmp)
            return nil
        }
        return Conexao(db: db, copia: tmp)
    }

    private static func abrirRO(_ arquivo: URL) -> OpaquePointer? {
        var c = URLComponents()
        c.scheme = "file"
        c.path = arquivo.path
        c.queryItems = [URLQueryItem(name: "mode", value: "ro")]
        var db: OpaquePointer?
        guard let uri = c.string,
              sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK, let db else {
            if let db { sqlite3_close_v2(db) }
            return nil
        }
        sqlite3_busy_timeout(db, 2000)
        return db
    }

    private static func testar(_ db: OpaquePointer) -> Bool {
        sqlite3_exec(db, "SELECT count(*) FROM sqlite_master", nil, nil, nil) == SQLITE_OK
    }

    static func texto(_ st: OpaquePointer, _ i: Int32) -> String? {
        guard let c = sqlite3_column_text(st, i) else { return nil }
        return String(cString: c)
    }

    // MARK: Diagnóstico (só estrutura — nunca conteúdo, nome ou número)

    static func diagnostico() -> String {
        var out = "Diagnóstico do WhatsApp — \(Date())\nSó estrutura: arquivos, tabelas, colunas, contagens e maior data. Nenhum conteúdo.\n\n"
        let pastas = pastasGrupo()
        out += "Pastas de grupo: \(pastas.count)\n"
        for p in pastas {
            let ok = (try? FileManager.default.contentsOfDirectory(atPath: p.path)) != nil
            out += "\n## \(p.lastPathComponent) — \(ok ? "legível" : "SEM ACESSO")\n"
            guard ok else { continue }
            for arq in sqlites(em: p) {
                let tam = (try? arq.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                let wal = (try? URL(fileURLWithPath: arq.path + "-wal").resourceValues(forKeys: [.fileSizeKey]))?.fileSize
                out += "\n### \(arq.path.replacingOccurrences(of: p.path, with: "…")) (\(tam) bytes\(wal.map { ", wal \($0) bytes" } ?? ""))\n"
                guard let c = abrir(arq) else { out += "  (não abriu)\n"; continue }
                var tabelas: [String] = []
                _ = c.linhas("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name") { st in
                    if let n = texto(st, 0) { tabelas.append(n) }
                }
                for t in tabelas {
                    var cols: [(String, String)] = []
                    _ = c.linhas("PRAGMA table_info(\"\(t)\")") { st in cols.append((texto(st, 1) ?? "?", texto(st, 2) ?? "")) }
                    var n: Int64 = -1
                    _ = c.linhas("SELECT count(*) FROM \"\(t)\"") { st in n = sqlite3_column_int64(st, 0) }
                    out += "  - \(t) [\(n) linhas]: " + cols.map { "\($0.0) \($0.1)" }.joined(separator: ", ") + "\n"
                    for (col, _) in cols where col.uppercased().contains("DATE") || col.uppercased().contains("TIME") {
                        var mx: Double = 0
                        _ = c.linhas("SELECT max(\"\(col)\") FROM \"\(t)\" WHERE typeof(\"\(col)\") IN ('integer','real')") { st in mx = sqlite3_column_double(st, 0) }
                        out += "      max(\(col)) = \(mx)\n"
                    }
                }
            }
        }
        return out
    }
}

// MARK: - Mensagens enviadas pelo Hugo (só as dele; só texto)

struct MensagemEnviada: Sendable {
    let id: Int64
    let data: Date
    let texto: String
    let conversa: String?
    let grupo: Bool
}

extension WhatsAppBanco {
    /// O banco das conversas (ChatStorage.sqlite, na pasta compartilhada do WhatsApp).
    static func bancoConversas() -> URL? {
        pastasGrupo().map { $0.appendingPathComponent("ChatStorage.sqlite") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Mensagens de texto ENVIADAS pelo Hugo depois de `desde` (segundos desde 2001, como o
    /// WhatsApp grava), da mais antiga para a mais nova. Só leitura.
    static func enviadas(desde: Double, limite: Int = 300) -> [MensagemEnviada] {
        guard let arq = bancoConversas(), let c = abrir(arq) else { return [] }
        var r: [MensagemEnviada] = []
        let sql = """
        SELECT m.Z_PK, m.ZMESSAGEDATE, m.ZTEXT, s.ZPARTNERNAME, s.ZSESSIONTYPE
        FROM ZWAMESSAGE m LEFT JOIN ZWACHATSESSION s ON s.Z_PK = m.ZCHATSESSION
        WHERE m.ZISFROMME = 1 AND m.ZTEXT IS NOT NULL AND length(m.ZTEXT) >= 4 AND m.ZMESSAGEDATE > ?
        ORDER BY m.ZMESSAGEDATE LIMIT \(limite)
        """
        _ = c.linhas(sql, [desde]) { st in
            guard let t = texto(st, 2) else { return }
            r.append(MensagemEnviada(id: sqlite3_column_int64(st, 0),
                                     data: Date(timeIntervalSinceReferenceDate: sqlite3_column_double(st, 1)),
                                     texto: t, conversa: texto(st, 3), grupo: sqlite3_column_int(st, 4) == 1))
        }
        return r
    }
}

// MARK: - Conversas (os dois lados), para a triagem entender o combinado

/// Uma mensagem de texto de uma conversa. Só vive na memória, durante a triagem.
struct MensagemWA: Sendable {
    let id: Int64
    let data: Date
    let texto: String
    let deMim: Bool
    let chat: Int64
    let conversa: String?
    let grupo: Bool
}

extension WhatsAppBanco {
    private static let colunas = """
    SELECT m.Z_PK, m.ZMESSAGEDATE, m.ZTEXT, m.ZISFROMME, m.ZCHATSESSION, s.ZPARTNERNAME, s.ZSESSIONTYPE
    FROM ZWAMESSAGE m LEFT JOIN ZWACHATSESSION s ON s.Z_PK = m.ZCHATSESSION
    """

    private static func mensagem(_ st: OpaquePointer) -> MensagemWA? {
        guard let t = texto(st, 2) else { return nil }
        return MensagemWA(id: sqlite3_column_int64(st, 0),
                          data: Date(timeIntervalSinceReferenceDate: sqlite3_column_double(st, 1)),
                          texto: t, deMim: sqlite3_column_int(st, 3) == 1, chat: sqlite3_column_int64(st, 4),
                          conversa: texto(st, 5), grupo: sqlite3_column_int(st, 6) == 1)
    }

    /// Mensagens de texto novas (enviadas e recebidas) depois de `desde`, da mais antiga para a
    /// mais nova. Só leitura.
    static func novas(desde: Double, limite: Int = 400) -> [MensagemWA] {
        guard let arq = bancoConversas(), let c = abrir(arq) else { return [] }
        var r: [MensagemWA] = []
        let sql = colunas + """
         WHERE m.ZTEXT IS NOT NULL AND length(m.ZTEXT) >= 2 AND m.ZMESSAGEDATE > ?
        ORDER BY m.ZMESSAGEDATE LIMIT \(limite)
        """
        _ = c.linhas(sql, [desde]) { st in if let m = mensagem(st) { r.append(m) } }
        return r
    }

    /// As últimas mensagens de uma conversa até `ate`, dentro da `janela` (segundos), da mais
    /// antiga para a mais nova — o contexto que a triagem lê. Só leitura.
    static func conversa(chat: Int64, ate: Date, janela: TimeInterval, limite: Int = 24) -> [MensagemWA] {
        guard let arq = bancoConversas(), let c = abrir(arq) else { return [] }
        var r: [MensagemWA] = []
        let fim = ate.timeIntervalSinceReferenceDate
        let sql = colunas + """
         WHERE m.ZCHATSESSION = ? AND m.ZTEXT IS NOT NULL AND m.ZMESSAGEDATE > ? AND m.ZMESSAGEDATE <= ?
        ORDER BY m.ZMESSAGEDATE DESC LIMIT \(limite)
        """
        _ = c.linhas(sql, [Double(chat), fim - janela, fim + 1]) { st in if let m = mensagem(st) { r.append(m) } }
        return r.reversed()
    }
}

extension WhatsAppBanco {
    /// O trecho da conversa com `nome` em volta de `momento` (antes e um pouco depois), para o
    /// Hugo entender uma sugestão. Lido na hora de mostrar; não fica guardado. Só leitura.
    static func trecho(nome: String, momento: Date, antes: TimeInterval = 3 * 3600, depois: TimeInterval = 30 * 60,
                       limite: Int = 14) -> [MensagemWA] {
        guard let arq = bancoConversas(), let c = abrir(arq) else { return [] }
        var chats: [Int64] = []
        _ = c.linhas("SELECT Z_PK, ZPARTNERNAME FROM ZWACHATSESSION") { st in
            if texto(st, 1) == nome { chats.append(sqlite3_column_int64(st, 0)) }
        }
        guard let chat = chats.first else { return [] }
        let todas = conversa(chat: chat, ate: momento.addingTimeInterval(depois), janela: antes + depois, limite: 60)
        // As mais próximas do momento, em ordem
        let perto = todas.sorted { abs($0.data.timeIntervalSince(momento)) < abs($1.data.timeIntervalSince(momento)) }
            .prefix(limite)
        return perto.sorted { $0.data < $1.data }
    }
}
