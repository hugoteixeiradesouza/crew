import Foundation
import CoreServices

// Lista os apps de /Applications e ~/Applications (um nível de subpasta). Tamanho e último uso
// vêm do índice do Spotlight; quem não tem tamanho lá é medido com `du` (Disco/Tamanhos).
// Tudo aqui roda fora da main.

struct AppInstalado: Sendable, Hashable, Identifiable {
    let nome: String
    let caminho: String
    let bundleID: String?
    var bytes: Int64?
    var ultimoUso: Date?
    var id: String { caminho }
    var alvo: AlvoApp { AlvoApp(nome: nome, bundleID: bundleID, caminho: caminho) }
}

enum LeitorApps {
    /// Pacotes .app nas raízes e uma pasta abaixo (`/Applications/Utilities/…`, pastas de
    /// fabricante). Mais fundo não: entraria no miolo de pacotes. `legiveis` = false se alguma
    /// raiz existe mas não abriu (a visão do que está instalado está capenga).
    static func pacotes(home: String = PoliticaDesinstalar.home) -> (urls: [URL], legiveis: Bool) {
        let fm = FileManager.default
        var vistos = Set<String>()
        var res: [URL] = []
        var legiveis = true
        func considerar(_ u: URL) {
            guard u.pathExtension == "app", vistos.insert(u.standardizedFileURL.path).inserted else { return }
            res.append(u)
        }
        for raiz in PoliticaDesinstalar.raizesApps(home: home) {
            guard fm.fileExists(atPath: raiz) else { continue }
            guard let itens = try? fm.contentsOfDirectory(at: URL(fileURLWithPath: raiz, isDirectory: true),
                                                          includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                                                          options: [.skipsHiddenFiles]) else {
                legiveis = false
                continue
            }
            for i in itens {
                if i.pathExtension == "app" {
                    considerar(i)
                } else if let v = try? i.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                          v.isDirectory == true, v.isSymbolicLink != true {
                    let dentro = (try? fm.contentsOfDirectory(at: i, includingPropertiesForKeys: nil,
                                                              options: [.skipsHiddenFiles])) ?? []
                    dentro.forEach(considerar)
                }
            }
        }
        return (res, legiveis)
    }

    /// Nome e bundle id de um pacote (sem Spotlight: barato, serve à vigia).
    static func alvo(_ url: URL) -> AlvoApp {
        let b = Bundle(url: url)
        let info = b?.infoDictionary ?? [:]
        let nome = [info["CFBundleDisplayName"], info["CFBundleName"]]
            .compactMap { $0 as? String }.first { !$0.isEmpty } ?? url.deletingPathExtension().lastPathComponent
        return AlvoApp(nome: nome, bundleID: b?.bundleIdentifier, caminho: url.standardizedFileURL.path)
    }

    /// Apps que o desinstalador pode oferecer: sem os do sistema (em /System ou no volume só de
    /// leitura — Safari e cia. que o macOS mostra em /Applications) e sem o próprio Crew.
    static func oferecivel(_ url: URL, _ a: AlvoApp) -> Bool {
        if PoliticaDesinstalar.appProtegido(caminho: a.caminho, bundleID: a.bundleID) { return false }
        let soLeitura = (try? url.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly ?? false
        return !soLeitura
    }

    /// Índice da vigia e das órfãs: caminho → app.
    static func indice() -> (apps: [String: AlvoApp], legiveis: Bool) {
        let (urls, ok) = pacotes()
        var d: [String: AlvoApp] = [:]
        for u in urls { let a = alvo(u); d[a.caminho] = a }
        return (d, ok)
    }

    /// Lista completa para a Central (com Spotlight).
    static func listar() -> [AppInstalado] {
        pacotes().urls.compactMap { u in
            let a = alvo(u)
            guard oferecivel(u, a) else { return nil }
            let md = MDItemCreate(nil, a.caminho as CFString)
            return AppInstalado(nome: a.nome, caminho: a.caminho, bundleID: a.bundleID,
                                bytes: md.flatMap(tamanhoSpotlight), ultimoUso: md.flatMap(ultimoUsoSpotlight))
        }
        .sorted { $0.nome.localizedCaseInsensitiveCompare($1.nome) == .orderedAscending }
    }

    /// `kMDItemLogicalSize`. Zero ou ausente = desconhecido (vai para o `du`).
    static func tamanhoSpotlight(_ md: MDItem) -> Int64? {
        guard let v = MDItemCopyAttribute(md, "kMDItemLogicalSize" as CFString) else { return nil }
        let n = (v as? NSNumber)?.int64Value ?? 0
        return n > 0 ? n : nil
    }

    /// `kMDItemLastUsedDate`: nil para app nunca aberto ou volume sem índice.
    static func ultimoUsoSpotlight(_ md: MDItem) -> Date? {
        MDItemCopyAttribute(md, kMDItemLastUsedDate) as? Date
    }
}
