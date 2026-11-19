import AppKit

// Os apps instalados, para o comando universal abrir pelo nome. A lista é lida do disco quando
// o painel abre (fora da thread principal) e fica na memória; nada vigia as pastas.

struct AppDoComando: Sendable, Equatable {
    let caminho: String
    /// Nome como o Finder mostra ("Ajustes do Sistema"), sem ".app".
    let nome: String
    /// Nome do pacote no disco ("System Settings"): também acha.
    let nomeNoDisco: String
}

enum FonteApps {
    private static let pastas: [String] = [
        "/Applications",
        "/System/Applications",
        "/System/Applications/Utilities",
        "/System/Library/CoreServices/Applications",
        NSHomeDirectory() + "/Applications",
    ]

    /// Lê as pastas de apps (um nível, mais um nível de subpasta: "/Applications/Utilities").
    static func ler() async -> [AppDoComando] {
        await Task.detached(priority: .userInitiated) { varrer() }.value
    }

    private static func varrer() -> [AppDoComando] {
        let fm = FileManager.default
        var vistos = Set<String>()
        var apps: [AppDoComando] = []

        func entra(_ caminho: String) {
            guard vistos.insert(caminho).inserted else { return }
            let noDisco = ((caminho as NSString).lastPathComponent as NSString).deletingPathExtension
            var nome = fm.displayName(atPath: caminho)
            if nome.lowercased().hasSuffix(".app") { nome = String(nome.dropLast(4)) }
            apps.append(AppDoComando(caminho: caminho, nome: nome, nomeNoDisco: noDisco))
        }

        for pasta in pastas {
            guard let itens = try? fm.contentsOfDirectory(atPath: pasta) else { continue }
            for item in itens where !item.hasPrefix(".") {
                let caminho = pasta + "/" + item
                if item.hasSuffix(".app") {
                    entra(caminho)
                } else if pasta == "/Applications" || pasta.hasSuffix("/Applications"), !item.contains(".") {
                    // Subpasta ("/Applications/Setapp", "/Applications/Utilities"): só um nível.
                    guard let dentro = try? fm.contentsOfDirectory(atPath: caminho) else { continue }
                    for d in dentro where d.hasSuffix(".app") { entra(caminho + "/" + d) }
                }
            }
        }
        // O Finder não mora em nenhuma dessas pastas.
        let finder = "/System/Library/CoreServices/Finder.app"
        if fm.fileExists(atPath: finder) { entra(finder) }
        return apps.sorted { $0.nome.localizedCaseInsensitiveCompare($1.nome) == .orderedAscending }
    }
}
