import Foundation
import WebKit
import CommonCrypto
import SQLite3
import Security

// Importar do Arc: os espaços com as abas (fixadas e soltas), os favoritos e as contas
// (cookies: o que mantém cada site logado) de cada perfil do Arc.
// - Abas e espaços vêm de `StorableSidebar.json` (texto puro).
// - Cookies vêm do banco `User Data/<perfil>/Cookies`, cifrado com a chave "Arc Safe Storage"
//   do Keychain: o macOS pergunta ao Hugo antes de entregar a chave ao Crew. A chave só vive
//   na memória durante a importação.
// - Cada perfil do Arc que não é o padrão vira um armazenamento separado do WebKit (as contas
//   de um perfil não se misturam com as de outro, como no Arc). O padrão entra no armazenamento
//   comum do navegador do Crew.
// Nada no Arc é alterado: os arquivos são só lidos (o banco, por uma cópia temporária).
// Cookie que já existe no Crew nunca é trocado, então desfazer devolve exatamente o de antes.
// Senhas salvas não entram (o Hugo usa o app Senhas da Apple).

enum ArcLeitor {
    struct Aba: Sendable, Hashable { var titulo: String; var url: String; var fixada: Bool }
    struct Espaco: Sendable, Hashable { var id: String; var titulo: String; var abas: [Aba] }
    struct Perfil: Sendable, Hashable, Identifiable {
        /// Pasta do perfil em `User Data` ("Default", "Profile 2"…).
        var pasta: String
        var espacos: [Espaco] = []
        var favoritos: [Aba] = []
        var cookies = 0
        var sites = 0
        var id: String { pasta }
        var padrao: Bool { pasta == "Default" }
        var nome: String { padrao ? "Padrão" : pasta.replacingOccurrences(of: "Profile", with: "Perfil") }
        var abas: Int { espacos.reduce(0) { $0 + $1.abas.count } + favoritos.count }
    }
    struct Cookie: Sendable {
        var host: String, nome: String, valor: String, caminho: String
        var expira: Date?
        var seguro: Bool, soHttp: Bool
        var mesmoSite: Int
    }
    enum Falha: LocalizedError {
        case semChave, banco(String)
        var errorDescription: String? {
            switch self {
            case .semChave: return "O macOS não entregou a chave do Arc (o pedido foi negado ou o Arc não está neste Mac)."
            case .banco(let m): return "Não deu para ler os cookies do Arc: \(m)"
            }
        }
    }

    static var base: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Arc")
    }
    static var instalado: Bool { FileManager.default.fileExists(atPath: base.appendingPathComponent("StorableSidebar.json").path) }

    private static func bancoDeCookies(_ pasta: String) -> URL {
        base.appendingPathComponent("User Data").appendingPathComponent(pasta).appendingPathComponent("Cookies")
    }

    // MARK: O que há para importar (sem chave nenhuma)

    static func previa() -> [Perfil] {
        var perfis: [String: Perfil] = [:]
        func perfil(_ pasta: String) -> Perfil { perfis[pasta] ?? Perfil(pasta: pasta) }
        func pastaDe(_ p: Any?) -> String {
            guard let d = p as? [String: Any], let c = d["custom"] as? [String: Any], let z = c["_0"] as? [String: Any],
                  let dir = z["directoryBasename"] as? String else { return "Default" }
            return dir
        }
        if let data = try? Data(contentsOf: base.appendingPathComponent("StorableSidebar.json")),
           let raiz = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let lateral = raiz["sidebar"] as? [String: Any], let caixas = lateral["containers"] as? [Any],
           let caixa = caixas.compactMap({ $0 as? [String: Any] }).first(where: { $0["spaces"] != nil }) {
            var itens: [String: [String: Any]] = [:]
            for i in (caixa["items"] as? [Any] ?? []).compactMap({ $0 as? [String: Any] }) {
                if let id = i["id"] as? String { itens[id] = i }
            }
            // As abas debaixo de um item (pastas entram achatadas).
            func abas(_ id: String, fixada: Bool, fundo: Int = 0) -> [Aba] {
                guard fundo < 8, let item = itens[id] else { return [] }
                if let tab = (item["data"] as? [String: Any])?["tab"] as? [String: Any],
                   let url = tab["savedURL"] as? String, !url.isEmpty {
                    let titulo = (item["title"] as? String) ?? (tab["savedTitle"] as? String) ?? url
                    return [Aba(titulo: titulo.isEmpty ? url : titulo, url: url, fixada: fixada)]
                }
                return (item["childrenIds"] as? [String] ?? []).flatMap { abas($0, fixada: fixada, fundo: fundo + 1) }
            }
            var n = 0
            for e in (caixa["spaces"] as? [Any] ?? []).compactMap({ $0 as? [String: Any] }) {
                guard let id = e["id"] as? String else { continue }
                n += 1
                var lista: [Aba] = []
                let ids = e["containerIDs"] as? [String] ?? []
                for (k, v) in ids.enumerated() where k + 1 < ids.count && (v == "pinned" || v == "unpinned") {
                    lista += abas(ids[k + 1], fixada: v == "pinned")
                }
                let pasta = pastaDe(e["profile"])
                var p = perfil(pasta)
                p.espacos.append(Espaco(id: id, titulo: (e["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Arc \(n)",
                                        abas: lista.filter(\.fixada) + lista.filter { !$0.fixada }))
                perfis[pasta] = p
            }
            // Favoritos (os ícones do topo do Arc): a lista alterna perfil e id do recipiente.
            let topo = caixa["topAppsContainerIDs"] as? [Any] ?? []
            for (k, v) in topo.enumerated() {
                guard let id = v as? String, k > 0 else { continue }
                let pasta = pastaDe(topo[k - 1])
                var p = perfil(pasta)
                p.favoritos += abas(id, fixada: true)
                perfis[pasta] = p
            }
        }
        // Perfis que só têm contas (sem espaço próprio) também entram.
        let pastas = (try? FileManager.default.contentsOfDirectory(atPath: base.appendingPathComponent("User Data").path)) ?? []
        for pasta in pastas where pasta == "Default" || pasta.hasPrefix("Profile ") {
            guard FileManager.default.fileExists(atPath: bancoDeCookies(pasta).path) else { continue }
            var p = perfil(pasta)
            if let (c, s) = try? comCopia(pasta, { db in try contar(db) }) { p.cookies = c; p.sites = s }
            perfis[pasta] = p
        }
        return perfis.values.filter { $0.abas > 0 || $0.cookies > 0 }
            .sorted { $0.padrao != $1.padrao ? $0.padrao : $0.pasta.localizedStandardCompare($1.pasta) == .orderedAscending }
    }

    // MARK: Banco de cookies (cópia temporária, só leitura)

    private static func comCopia<T>(_ pasta: String, _ f: (OpaquePointer) throws -> T) throws -> T {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("crew-arc-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let copia = tmp.appendingPathComponent("Cookies")
        do { try FileManager.default.copyItem(at: bancoDeCookies(pasta), to: copia) } catch { throw Falha.banco(error.localizedDescription) }
        var db: OpaquePointer?
        guard sqlite3_open_v2(copia.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            sqlite3_close(db)
            throw Falha.banco("o arquivo não abriu")
        }
        defer { sqlite3_close(db) }
        return try f(db)
    }

    private static func contar(_ db: OpaquePointer) throws -> (Int, Int) {
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, "select count(*), count(distinct host_key) from cookies", -1, &st, nil) == SQLITE_OK else {
            throw Falha.banco("consulta recusada")
        }
        defer { sqlite3_finalize(st) }
        guard sqlite3_step(st) == SQLITE_ROW else { return (0, 0) }
        return (Int(sqlite3_column_int64(st, 0)), Int(sqlite3_column_int64(st, 1)))
    }

    // MARK: Chave e decifragem

    /// Pede ao Keychain a senha "Arc Safe Storage" (o macOS mostra o pedido ao Hugo) e deriva a
    /// chave dos cookies, como o Chromium faz: PBKDF2-SHA1, sal "saltysalt", 1003 voltas, 16 bytes.
    static func chave() throws -> [UInt8] {
        let pedido: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                     kSecAttrService as String: "Arc Safe Storage",
                                     kSecAttrAccount as String: "Arc",
                                     kSecReturnData as String: true,
                                     kSecMatchLimit as String: kSecMatchLimitOne]
        var saida: CFTypeRef?
        guard SecItemCopyMatching(pedido as CFDictionary, &saida) == errSecSuccess, let senha = saida as? Data, !senha.isEmpty else {
            throw Falha.semChave
        }
        let sal = Array("saltysalt".utf8)
        var chave = [UInt8](repeating: 0, count: 16)
        let ok = senha.withUnsafeBytes { s in
            CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), s.bindMemory(to: Int8.self).baseAddress, senha.count,
                                 sal, sal.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003, &chave, chave.count)
        }
        guard ok == kCCSuccess else { throw Falha.semChave }
        return chave
    }

    /// "v10" + AES-128-CBC (IV de 16 espaços). Do banco versão 24 em diante o texto começa com o
    /// SHA-256 do domínio (32 bytes), que sai.
    private static func decifrar(_ cifrado: [UInt8], chave: [UInt8], comPrefixo: Bool) -> String? {
        guard cifrado.count > 3, cifrado[0] == 0x76, cifrado[1] == 0x31, cifrado[2] == 0x30 else { return nil }
        let corpo = Array(cifrado[3...])
        let iv = [UInt8](repeating: 0x20, count: 16)
        var claro = [UInt8](repeating: 0, count: corpo.count + kCCBlockSizeAES128)
        var n = 0
        let ok = CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                         chave, chave.count, iv, corpo, corpo.count, &claro, claro.count, &n)
        guard ok == kCCSuccess else { return nil }
        var bytes = Array(claro[..<n])
        if comPrefixo { guard bytes.count >= 32 else { return nil }; bytes.removeFirst(32) }
        return String(bytes: bytes, encoding: .utf8)
    }

    /// Os cookies do perfil, já decifrados e ainda válidos.
    static func cookies(pasta: String, chave: [UInt8]) throws -> [Cookie] {
        try comCopia(pasta) { db in
            var versao = 0
            var st: OpaquePointer?
            if sqlite3_prepare_v2(db, "select value from meta where key = 'version'", -1, &st, nil) == SQLITE_OK,
               sqlite3_step(st) == SQLITE_ROW, let t = sqlite3_column_text(st, 0) { versao = Int(String(cString: t)) ?? 0 }
            sqlite3_finalize(st)
            st = nil
            let sql = "select host_key, name, encrypted_value, path, expires_utc, is_secure, is_httponly, samesite, has_expires from cookies"
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { throw Falha.banco("consulta recusada") }
            defer { sqlite3_finalize(st) }
            func texto(_ i: Int32) -> String { sqlite3_column_text(st, i).map { String(cString: $0) } ?? "" }
            var out: [Cookie] = []
            let agora = Date()
            while sqlite3_step(st) == SQLITE_ROW {
                let n = Int(sqlite3_column_bytes(st, 2))
                guard n > 0, let p = sqlite3_column_blob(st, 2) else { continue }
                let cifrado = Array(UnsafeBufferPointer(start: p.assumingMemoryBound(to: UInt8.self), count: n))
                guard let valor = decifrar(cifrado, chave: chave, comPrefixo: versao >= 24) else { continue }
                // O Chromium conta o tempo em microssegundos desde 1601.
                var expira: Date?
                if sqlite3_column_int(st, 8) != 0 {
                    let d = Date(timeIntervalSince1970: Double(sqlite3_column_int64(st, 4)) / 1_000_000 - 11_644_473_600)
                    if d <= agora { continue }
                    expira = d
                }
                out.append(Cookie(host: texto(0), nome: texto(1), valor: valor, caminho: texto(3), expira: expira,
                                  seguro: sqlite3_column_int(st, 5) != 0, soHttp: sqlite3_column_int(st, 6) != 0,
                                  mesmoSite: Int(sqlite3_column_int(st, 7))))
            }
            return out
        }
    }
}

/// O que a importação fez (para dizer ao Hugo e para desfazer).
struct ResultadoArc: Equatable {
    var espacos = 0, abas = 0, cookies = 0, jaExistiam = 0
    var erro: String?
}

/// O que entrou, guardado para desfazer exatamente.
private struct RegistroArc: Codable {
    /// Cookies postos no armazenamento comum: [domínio, nome, caminho].
    var cookiesPadrao: [[String]] = []
    /// Abas postas no espaço Geral.
    var abasGeral: [String] = []
    /// Armazenamentos criados (um por perfil do Arc que não é o padrão).
    var armazens: [String] = []
}

extension NavegadorServico {
    private static var registroArc: URL { HookServer.supportDir.appendingPathComponent("arc-importado.json") }

    var temImportacaoDoArc: Bool { FileManager.default.fileExists(atPath: Self.registroArc.path) }

    private func lerRegistro() -> RegistroArc {
        (try? Data(contentsOf: Self.registroArc)).flatMap { try? JSONDecoder().decode(RegistroArc.self, from: $0) } ?? RegistroArc()
    }

    /// Importa os perfis escolhidos. Importar de novo só acrescenta o que falta.
    func importarDoArc(_ perfis: [ArcLeitor.Perfil]) async -> ResultadoArc {
        var r = ResultadoArc()
        var registro = lerRegistro()
        // A chave: um pedido só do macOS, fora da main (ele espera o clique do Hugo).
        let chave: [UInt8]
        do { chave = try await Task.detached { try ArcLeitor.chave() }.value } catch {
            r.erro = error.localizedDescription
            return r
        }
        for (n, perfil) in perfis.enumerated() {
            // Perfil que não é o padrão: armazenamento próprio (o mesmo a cada importação).
            var armazemId: String?
            if !perfil.padrao {
                armazemId = espacos.first { $0.origem == perfil.pasta }?.perfil ?? UUID().uuidString
                if let a = armazemId, !registro.armazens.contains(a) { registro.armazens.append(a) }
            }
            let armazem = Self.armazem(armazemId)

            // Contas (cookies).
            let pasta = perfil.pasta
            do {
                let lidos = try await Task.detached { try ArcLeitor.cookies(pasta: pasta, chave: chave) }.value
                let existentes = Set(await armazem.httpCookieStore.allCookies().map { "\($0.domain)|\($0.name)|\($0.path)" })
                for c in lidos {
                    guard !existentes.contains("\(c.host)|\(c.nome)|\(c.caminho)") else { r.jaExistiam += 1; continue }
                    var p: [HTTPCookiePropertyKey: Any] = [.domain: c.host, .name: c.nome, .value: c.valor,
                                                           .path: c.caminho.isEmpty ? "/" : c.caminho]
                    if c.seguro { p[.secure] = "TRUE" }
                    if c.soHttp { p[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
                    if let e = c.expira { p[.expires] = e }
                    if c.mesmoSite == 1 { p[.sameSitePolicy] = "lax" } else if c.mesmoSite == 2 { p[.sameSitePolicy] = "strict" }
                    guard let cookie = HTTPCookie(properties: p) else { continue }
                    await armazem.httpCookieStore.setCookie(cookie)
                    r.cookies += 1
                    if perfil.padrao { registro.cookiesPadrao.append([c.host, c.nome, c.caminho]) }
                }
            } catch {
                r.erro = error.localizedDescription
            }

            // Espaços e abas.
            for (k, e) in perfil.espacos.enumerated() {
                let id = "arc:" + e.id
                if espaco(id) == nil {
                    let cor = Projetos.cores[(n * 3 + k + 1) % Projetos.cores.count]
                    acrescentar(EspacoNav(id: id, nome: e.titulo, cor: cor, perfil: armazemId, origem: perfil.pasta))
                    r.espacos += 1
                }
                r.abas += juntar(e.abas, em: id).count
            }
            // Favoritos: no primeiro espaço do perfil; os do padrão, no Geral.
            if !perfil.favoritos.isEmpty {
                if perfil.padrao || perfil.espacos.isEmpty && armazemId == nil {
                    garantir(projeto: nil)
                    let novas = juntar(perfil.favoritos, em: Self.geral)
                    registro.abasGeral += novas
                    r.abas += novas.count
                } else if let primeiro = perfil.espacos.first {
                    r.abas += juntar(perfil.favoritos, em: "arc:" + primeiro.id).count
                }
            }
        }
        if let data = try? JSONEncoder().encode(registro) { try? data.write(to: Self.registroArc, options: .atomic) }
        return r
    }

    /// Tira tudo o que a importação pôs: espaços do Arc, abas no Geral, cookies e os
    /// armazenamentos dos perfis. O que já era do Crew fica como estava.
    func desfazerImportacaoDoArc() async -> ResultadoArc {
        var r = ResultadoArc()
        let registro = lerRegistro()
        let doArc = espacos.filter { $0.id.hasPrefix("arc:") }
        r.espacos = doArc.count
        r.abas = doArc.reduce(0) { $0 + $1.abas.count } + registro.abasGeral.count
        doArc.forEach { apagarEspaco($0.id) }
        registro.abasGeral.forEach { tirarAba($0) }
        let alvo = Set(registro.cookiesPadrao.map { $0.joined(separator: "|") })
        let comum = WKWebsiteDataStore.default().httpCookieStore
        for c in await comum.allCookies() where alvo.contains("\(c.domain)|\(c.name)|\(c.path)") {
            await comum.deleteCookie(c)
            r.cookies += 1
        }
        for a in registro.armazens {
            if let id = UUID(uuidString: a) { try? await WKWebsiteDataStore.remove(forIdentifier: id) }
        }
        try? FileManager.default.removeItem(at: Self.registroArc)
        return r
    }
}

// MARK: - Histórico

extension ArcLeitor {
    /// As páginas visitadas no Arc, de todos os perfis, as mais recentes primeiro. Lê uma cópia
    /// temporária do banco `History` (o Arc mantém o original travado); nada no Arc muda.
    static func historico(limite: Int) -> [VisitaNav] {
        let dados = base.appendingPathComponent("User Data")
        let pastas = (try? FileManager.default.contentsOfDirectory(atPath: dados.path)) ?? []
        var todas: [VisitaNav] = []
        for pasta in pastas where pasta == "Default" || pasta.hasPrefix("Profile ") {
            let banco = dados.appendingPathComponent(pasta).appendingPathComponent("History")
            guard FileManager.default.fileExists(atPath: banco.path) else { continue }
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("crew-arc-" + UUID().uuidString)
            guard (try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)) != nil else { continue }
            defer { try? FileManager.default.removeItem(at: tmp) }
            let copia = tmp.appendingPathComponent("History")
            guard (try? FileManager.default.copyItem(at: banco, to: copia)) != nil else { continue }
            var db: OpaquePointer?
            guard sqlite3_open_v2(copia.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
                sqlite3_close(db)
                continue
            }
            defer { sqlite3_close(db) }
            var st: OpaquePointer?
            let sql = "select url, title, visit_count, last_visit_time from urls where hidden = 0 and url like 'http%' order by last_visit_time desc limit \(limite)"
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { continue }
            defer { sqlite3_finalize(st) }
            while sqlite3_step(st) == SQLITE_ROW {
                guard let u = sqlite3_column_text(st, 0) else { continue }
                let titulo = sqlite3_column_text(st, 1).map { String(cString: $0) } ?? ""
                // O Chromium conta o tempo em microssegundos desde 1601.
                let unix = Double(sqlite3_column_int64(st, 3)) / 1_000_000 - 11_644_473_600
                todas.append(VisitaNav(url: String(cString: u), titulo: titulo,
                                       ultima: Date(timeIntervalSince1970: max(unix, 0)),
                                       vezes: max(Int(sqlite3_column_int64(st, 2)), 1)))
            }
        }
        return Array(todas.sorted { $0.ultima > $1.ultima }.prefix(limite))
    }
}
