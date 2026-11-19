import Foundation

// Procura o rótulo de uma pasta de cache:
// chave exata, depois apelido, depois bundle id,
// sem diferença de maiúsculas. A tabela está em `RotulosTabela.swift`.

enum Rotulos {
    private static let porChave: [String: Rotulo] = {
        var d: [String: Rotulo] = [:]
        for r in todos { d[r.chave.lowercased()] = r }
        return d
    }()

    private static let porApelido: [String: Rotulo] = {
        var d: [String: Rotulo] = [:]
        for r in todos { for a in r.aliases { d[a.lowercased()] = r } }
        return d
    }()

    private static let porBundle: [String: Rotulo] = {
        var d: [String: Rotulo] = [:]
        for r in todos { for b in r.bundles { d[b.lowercased()] = r } }
        return d
    }()

    static func rotulo(_ nomePasta: String) -> Rotulo? {
        let k = nomePasta.lowercased()
        return porChave[k] ?? porApelido[k] ?? porBundle[k]
    }

    /// Só os rótulos "seguro" entram na lista de caches de apps.
    static func seguro(_ nomePasta: String) -> Rotulo? {
        guard let r = rotulo(nomePasta), r.nivel == .seguro else { return nil }
        return r
    }

    /// Explicação curta em português, pelo tipo do rótulo.
    static func explicacao(tipo: String) -> String {
        switch tipo {
        case "browser": return "Cache do navegador (páginas e imagens). Refaz ao navegar; o primeiro acesso a cada site fica um pouco mais lento."
        case "updater": return "Sobras de atualizações já instaladas. Não faz falta."
        case "logs": return "Registros antigos. Os apps não precisam deles para funcionar."
        case "system": return "Cache de um serviço do macOS. O sistema refaz sozinho."
        case "media", "photos", "design": return "Miniaturas e prévias. O app refaz quando abrir os arquivos de novo."
        case "build": return "Arquivos de build. Refeitos no próximo build (que fica mais lento)."
        case "packages": return "Pacotes baixados. Baixam de novo quando precisar."
        case "store": return "Cache da App Store. Refeito sozinho."
        default: return "Cache do app. Ele refaz sozinho quando precisar."
        }
    }
}
