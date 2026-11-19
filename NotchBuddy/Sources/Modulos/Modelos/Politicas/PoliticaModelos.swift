import Foundation

// Onde moram os modelos locais de IA e o que pode sair de lá.

enum PoliticaModelos {
    enum Origem: String, Sendable, CaseIterable {
        case ollama
        case lmStudio

        var nome: String {
            switch self {
            case .ollama: return "Ollama"
            case .lmStudio: return "LM Studio"
            }
        }
    }

    /// O Ollama respeita `OLLAMA_MODELS` (quem guarda os modelos num disco externo), então o
    /// caminho padrão é só o plano B.
    static func raizOllama(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                           ambiente: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let outro = ambiente["OLLAMA_MODELS"], !outro.isEmpty {
            return URL(fileURLWithPath: (outro as NSString).expandingTildeInPath, isDirectory: true)
                .standardizedFileURL
        }
        return home.appendingPathComponent(".ollama/models", isDirectory: true).standardizedFileURL
    }

    /// Local atual do LM Studio e o anterior à 0.3 (a atualização deixa o antigo para trás).
    static func raizesLMStudio(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        [
            home.appendingPathComponent(".lmstudio/models", isDirectory: true),
            home.appendingPathComponent(".cache/lm-studio/models", isDirectory: true),
        ].map(\.standardizedFileURL)
    }

    static func raizes(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                       ambiente: [String: String] = ProcessInfo.processInfo.environment) -> [URL] {
        [raizOllama(home: home, ambiente: ambiente)] + raizesLMStudio(home: home)
    }

    /// Onde o `ollama` costuma estar (Homebrew, instalador oficial, dentro do app).
    static let candidatosBinarioOllama = [
        "/opt/homebrew/bin/ollama",
        "/usr/local/bin/ollama",
        "/Applications/Ollama.app/Contents/Resources/ollama",
    ]

    static func binarioOllama() -> String? {
        candidatosBinarioOllama.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Algum sinal de que este Mac tem modelos locais (ou o Ollama instalado)? Só `stat`, barato.
    static func haAlgoInstalado() -> Bool {
        let fm = FileManager.default
        return raizes().contains { fm.fileExists(atPath: $0.path) } || binarioOllama() != nil
    }

    /// Um caminho só pode sair se estiver **dentro** de uma das raízes de modelos. A raiz em si
    /// nunca: esvaziar `~/.ollama/models` inteiro não é o que um modelo da lista significa.
    static func podeSair(_ url: URL,
                         home: URL = FileManager.default.homeDirectoryForCurrentUser,
                         ambiente: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        let caminho = url.standardizedFileURL.path
        guard FileManager.default.fileExists(atPath: caminho) else { return false }
        return raizes(home: home, ambiente: ambiente).contains { caminho.hasPrefix($0.path + "/") }
    }
}
