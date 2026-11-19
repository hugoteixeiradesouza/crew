import AppKit
import Foundation

// Quando um .app some de /Applications ou ~/Applications, é remoção ou atualização? Os
// atualizadores tiram a cópia velha antes de pôr a nova (brew, Sparkle, instaladores). Por isso
// a vigia espera um pouco e confere de novo: o mesmo bundle id voltou, ou existe outra cópia
// viva no Mac → não foi remoção.
//
// Uma espera fixa e uma conferência.

enum PoliticaApagado {
    /// Quanto esperar depois que o app some antes de conferir se voltou.
    static let espera: TimeInterval = 10
    /// Por quanto tempo um app apagado fica em "apagados recentemente".
    static let validade: TimeInterval = 7 * 24 * 3600
    static let maxRecentes = 12

    /// O FSEvents pode dar /Applications pelo caminho do volume de dados, e pasta com barra no fim.
    static func normalizar(_ caminho: String) -> String {
        var r = caminho
        let dados = "/System/Volumes/Data"
        if r.hasPrefix(dados + "/") { r.removeFirst(dados.count) }
        while r.count > 1 && r.hasSuffix("/") { r.removeLast() }
        return r
    }

    /// Mudança que pode pôr ou tirar um app: a própria raiz ou uma pasta direto dentro dela.
    /// Mais fundo é o miolo de um pacote mexendo (atualização, abertura) — a maior parte do
    /// tráfego em /Applications, ignorado.
    static func relevante(_ caminho: String, raizes: [String]) -> Bool {
        let n = normalizar(caminho)
        for r in raizes {
            if n == r { return true }
            guard n.hasPrefix(r + "/") else { continue }
            return !n.dropFirst(r.count + 1).contains("/")
        }
        return false
    }

    /// Caminhos que estavam em `antes` e não estão em `agora`.
    static func sumiram(antes: [String: AlvoApp], agora: [String: AlvoApp]) -> [AlvoApp] {
        antes.filter { agora[$0.key] == nil }.map(\.value).sorted { $0.nome < $1.nome }
    }

    /// Depois da espera: avisa?
    /// - sem bundle id: só daria casamento por nome — pouco para interromper o Hugo;
    /// - o mesmo id de volta nas raízes, ou outra cópia viva no Mac: atualização ou mudança de lugar;
    /// - o próprio Crew removeu: já foi revisado na hora.
    static func deveAvisar(_ app: AlvoApp, idsInstalados: Set<String>, outraCopia: Bool, removidoPeloCrew: Bool) -> Bool {
        guard !removidoPeloCrew, !outraCopia else { return false }
        guard let id = app.bundleID?.lowercased(), !id.isEmpty else { return false }
        if app.caminho.hasPrefix("/System/") { return false }
        if PoliticaDesinstalar.idsProtegidos.contains(where: { $0.lowercased() == id }) { return false }
        return !idsInstalados.contains(id)
    }

    /// O Launch Services conhece uma cópia viva fora do caminho de onde saiu (na Mesa, num disco
    /// externo, a nova que o atualizador preparou)? Lixeira e volume só de leitura (a imagem do
    /// instalador montada) não contam.
    static func outraCopia(_ app: AlvoApp) -> Bool {
        guard let id = app.bundleID, !id.isEmpty else { return false }
        return NSWorkspace.shared.urlsForApplications(withBundleIdentifier: id).contains { url in
            let c = normalizar(url.standardizedFileURL.path)
            guard c != normalizar(app.caminho), !naLixeira(c), FileManager.default.fileExists(atPath: c) else { return false }
            let soLeitura = (try? url.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly ?? false
            return !soLeitura
        }
    }

    static func naLixeira(_ caminho: String) -> Bool {
        caminho.split(separator: "/").contains { $0 == ".Trash" || $0 == ".Trashes" }
    }
}
