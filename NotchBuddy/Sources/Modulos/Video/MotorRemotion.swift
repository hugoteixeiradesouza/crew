import Foundation

// O motor de vídeo: o Remotion (vídeo escrito em React) rodando ao lado do Crew, como processo
// Node à parte — docs/ARQUITETURA.md, "Motores externos". Nada dele entra no binário do Crew.
//
//   ~/Library/Application Support/NotchBuddy/motores/remotion/
//     package.json, node_modules/   o motor (instalado pelo botão dos Ajustes; ~260 MB)
//     CLAUDE.md                     o guia que as sessões do Claude Code leem ao editar um vídeo
//     videos/<nome>/                um projeto de vídeo: index.ts + Raiz.tsx (+ o que a sessão criar)
//   ~/Movies/Crew/                  os vídeos renderizados
//
// Os projetos ficam dentro da pasta do motor para acharem o `node_modules` dele sem cópia
// (o Node sobe as pastas procurando): um motor só serve a todos os vídeos.
//
// Licença do Remotion: grátis para pessoa física e para empresa de até 3 pessoas; acima disso,
// licença paga (remotion.dev/license). Fica dito na página do módulo.

enum MotorRemotion {
    /// Versão fixada: atualizar é trocar aqui e reinstalar (o Remotion pede as peças na mesma versão).
    static let versao = "4.0.543"

    static var pasta: URL { HookServer.supportDir.appendingPathComponent("motores/remotion") }
    static var videos: URL { pasta.appendingPathComponent("videos") }
    static var saidas: URL {
        FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0].appendingPathComponent("Crew")
    }
    static var cli: URL { pasta.appendingPathComponent("node_modules/.bin/remotion") }

    static var instalado: Bool { FileManager.default.isExecutableFile(atPath: cli.path) }

    /// Versão instalada (nil = não instalado ou ilegível).
    static var versaoInstalada: String? {
        let p = pasta.appendingPathComponent("node_modules/remotion/package.json")
        guard let d = try? Data(contentsOf: p),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        return j["version"] as? String
    }

    // MARK: Node

    private static let pastasDeBinarios: [String] = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["/opt/homebrew/bin", "/usr/local/bin", home + "/.volta/bin", home + "/.local/bin", "/usr/bin", "/bin"]
    }()

    private static func achar(_ nome: String) -> String? {
        pastasDeBinarios.map { $0 + "/" + nome }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static var node: String? { achar("node") }
    static var npm: String? { achar("npm") }

    /// Por que o motor não pode ser instalado neste Mac (nil = pode).
    static var motivoIndisponivel: String? {
        if node == nil { return "Node.js não encontrado neste Mac (brew install node)." }
        if npm == nil { return "npm não encontrado neste Mac (vem com o Node.js)." }
        return nil
    }

    /// Ambiente dos processos do motor: o PATH de um app aberto pelo Finder não tem o Homebrew.
    static var ambiente: [String: String] {
        var e = ProcessInfo.processInfo.environment
        e["PATH"] = pastasDeBinarios.joined(separator: ":")
        e["NO_UPDATE_NOTIFIER"] = "1"
        e["npm_config_update_notifier"] = "false"
        e["npm_config_fund"] = "false"
        e["npm_config_audit"] = "false"
        return e
    }

    // MARK: Arquivos do motor

    /// Escreve (ou atualiza) package.json, tsconfig e o guia das sessões. Não instala nada.
    static func prepararPasta() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: videos, withIntermediateDirectories: true)
        try fm.createDirectory(at: saidas, withIntermediateDirectories: true)
        try escrever(ModeloVideo.pacote(versao: versao), em: pasta.appendingPathComponent("package.json"))
        try escrever(ModeloVideo.tsconfig, em: pasta.appendingPathComponent("tsconfig.json"))
        try escrever(ModeloVideo.guia(saidas: saidas.path), em: pasta.appendingPathComponent("CLAUDE.md"))
    }

    private static func escrever(_ texto: String, em url: URL) throws {
        if (try? String(contentsOf: url, encoding: .utf8)) == texto { return }
        try texto.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Tamanho do motor em disco (bytes), para mostrar nos Ajustes. Fora da main.
    static func tamanho() async -> Int64 {
        let alvo = pasta.appendingPathComponent("node_modules").path
        let r = await Processo.rodar("/usr/bin/du", ["-sk", alvo], tempoMax: 20)
        guard r.ok, let kb = Int64(r.saida.split(separator: "\t").first ?? "") else { return 0 }
        return kb * 1024
    }

    // MARK: Projetos

    /// Nome de pasta seguro a partir do que o Hugo (ou a sessão) escreveu.
    static func nomeDePasta(_ texto: String) -> String {
        let semAcento = texto.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR")).lowercased()
        var saida = ""
        for c in semAcento.unicodeScalars {
            if CharacterSet.alphanumerics.contains(c), c.isASCII { saida.unicodeScalars.append(c) }
            else if !saida.hasSuffix("-") { saida.append("-") }
        }
        return String(saida.trimmingCharacters(in: CharacterSet(charactersIn: "-")).prefix(48))
    }

    static func pastaDoProjeto(_ nome: String) -> URL { videos.appendingPathComponent(nome) }
    /// Caminho de entrada relativo à pasta do motor (é de lá que o CLI roda).
    static func entrada(_ nome: String) -> String { "videos/\(nome)/index.ts" }
    /// A pasta de mídia é a do projeto: sem isto o Remotion procuraria `public/` na pasta do motor
    /// e `staticFile()` não acharia nada.
    static func midia(_ nome: String) -> String { "--public-dir=videos/\(nome)/public" }

    /// Composições de um projeto (os "vídeos" que ele define). Monta o projeto: leva alguns segundos.
    static func composicoes(_ nome: String) async -> Result<[String], Falha> {
        let r = await Processo.rodar(cli.path, ["compositions", entrada(nome), midia(nome), "--quiet"], pasta: pasta, tempoMax: 120)
        guard r.ok else { return .failure(Falha(texto: ultimasLinhas(r.erro.isEmpty ? r.saida : r.erro))) }
        // Os ids vêm na última linha; antes dela o Remotion às vezes avisa coisas ("Webpack config
        // change detected…"), que não são composição.
        let ultima = r.saida.split(whereSeparator: \.isNewline).last.map(String.init) ?? ""
        let ids = ultima.split(separator: " ").map(String.init).filter { id in
            !id.isEmpty && id.unicodeScalars.allSatisfy { ($0.isASCII && CharacterSet.alphanumerics.contains($0)) || $0 == "-" }
        }
        return .success(ids)
    }

    struct Falha: Error { let texto: String }

    static func ultimasLinhas(_ texto: String, _ n: Int = 6) -> String {
        texto.split(whereSeparator: \.isNewline).suffix(n).joined(separator: "\n")
    }
}

private extension Processo {
    /// `rodar` com pasta de trabalho e o ambiente do motor.
    static func rodar(_ executavel: String, _ argumentos: [String], pasta: URL, tempoMax: TimeInterval) async -> Resultado {
        // `env -C` não existe no macOS: um sh curto troca de pasta e passa os argumentos intactos.
        var env: [String] = []
        for (k, v) in MotorRemotion.ambiente where k == "PATH" || k.hasPrefix("npm_config") || k == "NO_UPDATE_NOTIFIER" {
            env.append("\(k)=\(v)")
        }
        return await rodar("/usr/bin/env", env + ["/bin/sh", "-c", "cd \"$0\" && exec \"$@\"", pasta.path, executavel] + argumentos,
                           tempoMax: tempoMax)
    }
}
