import Foundation

// Onde procurar caches.
//
// Notas: textos em português; sem "Git Worktrees" (worktrees ficam para o módulo
// Agentes); sem `workspaceStorage` do VS Code/Cursor e sem `Zed/db` (estado, não cache);
// `~/.gem` vira "conferir" (guarda gems instaladas com --user-install, não só cache).

enum GrupoLimpeza: String, CaseIterable, Sendable {
    case desenvolvimento = "Desenvolvimento"
    case apps = "Caches de apps"
    case registros = "Registros do sistema"
}

struct DefinicaoDev: Sendable {
    let nome: String
    let explicacao: String
    let nivel: NivelRotulo
    let caminhos: [String]   // relativos à home
}

enum CatalogoCaches {
    // MARK: Ferramentas de desenvolvimento

    static let desenvolvimento: [DefinicaoDev] = [
        D("Xcode — DerivedData", "Builds e índices do Xcode. Refeitos no próximo build (o primeiro fica mais lento).",
          .seguro, ["Library/Developer/Xcode/DerivedData"]),
        D("Xcode — Archives", "Builds arquivados (.xcarchive) e símbolos de depuração. Não se refazem sozinhos: confira se ainda precisa de algum.",
          .conferir, ["Library/Developer/Xcode/Archives"]),
        D("Xcode — suporte a aparelhos", "Símbolos de cada versão de iOS que já conectou. Baixam de novo quando o aparelho conecta (demora).",
          .conferir, ["Library/Developer/Xcode/iOS DeviceSupport"]),
        D("Xcode — cache do app", "Cache interno do Xcode. Ele refaz sozinho.",
          .seguro, ["Library/Caches/com.apple.dt.Xcode"]),
        D("Xcode — documentação", "Documentação baixada pelo Xcode. Baixa de novo quando abrir.",
          .seguro, ["Library/Developer/Xcode/DocumentationCache"]),
        D("CocoaPods", "Cópia local das especificações do CocoaPods. Baixa de novo no próximo pod install.",
          .seguro, [".cocoapods/repos"]),
        D("Homebrew", "Instaladores já baixados pelo brew. O que está instalado continua; só baixa de novo se reinstalar.",
          .seguro, ["Library/Caches/Homebrew"]),
        D("npm", "Pacotes baixados pelo npm. Baixam de novo no próximo install.",
          .seguro, [".npm/_cacache"]),
        D("npm — npx", "Pacotes que o npx baixou para rodar uma vez. Baixam de novo se rodar de novo.",
          .seguro, [".npm/_npx"]),
        D("npm — registros", "Registros de execuções antigas do npm.",
          .seguro, [".npm/_logs"]),
        D("Corepack", "Versões de pnpm/yarn baixadas pelo Corepack. Baixam de novo quando precisar.",
          .seguro, [".cache/node/corepack"]),
        D("pnpm", "Depósito de pacotes do pnpm. Os projetos continuam funcionando; o próximo install baixa de novo.",
          .seguro, [".pnpm-store"]),
        D("Yarn", "Pacotes baixados pelo Yarn. Baixam de novo no próximo install.",
          .seguro, ["Library/Caches/Yarn"]),
        D("Gradle", "Dependências e builds em cache do Gradle. Baixam de novo no próximo build.",
          .seguro, [".gradle/caches"]),
        D("Flutter", "Cache do Flutter. Refeito no próximo uso.",
          .seguro, [".flutter"]),
        D("Hex (Elixir)", "Pacotes baixados pelo mix. Voltam no próximo mix deps.get.",
          .seguro, [".hex/packages"]),
        D("Rebar3 (Erlang)", "Cache do rebar3. Refeito no próximo build.",
          .seguro, [".cache/rebar3"]),
        D("NuGet (.NET)", "Pacotes baixados do NuGet. Baixam de novo no próximo restore.",
          .seguro, [".nuget/packages"]),
        D("Deno", "Módulos baixados pelo Deno. Baixam de novo quando rodar.",
          .seguro, ["Library/Caches/deno"]),
        D("Bun", "Pacotes baixados pelo Bun. Baixam de novo no próximo install.",
          .seguro, [".bun/install/cache"]),
        D("Cabal (Haskell)", "Pacotes baixados pelo Cabal.",
          .seguro, [".cabal/packages"]),
        D("Stack (Haskell)", "Inclui compiladores GHC baixados. Volta tudo, mas o próximo build demora muito.",
          .conferir, [".stack"]),
        D("Bazel", "Cache de build do Bazel (pode ter dezenas de GB). O próximo build demora muito.",
          .conferir, [".cache/bazel"]),
        D("Swift Package Manager", "Pacotes Swift baixados. Baixam de novo no próximo resolve.",
          .seguro, ["Library/Caches/org.swift.swiftpm", ".swiftpm/cache"]),
        D("Android (.android)", "Também guarda emuladores (AVD) e a chave do adb: recria, mas dá trabalho.",
          .conferir, [".android"]),
        D("Docker Desktop", "Imagens, contêineres e volumes do Docker. Imagens baixam de novo; volumes com dados se perdem.",
          .conferir, ["Library/Containers/com.docker.docker"]),
        D("VS Code — cache", "Cache do VS Code e extensões baixadas. Ele refaz sozinho.",
          .seguro, ["Library/Application Support/Code/Cache", "Library/Application Support/Code/CachedData",
                    "Library/Application Support/Code/CachedExtensionVSIXs"]),
        D("Cursor — cache", "Cache do Cursor. Ele refaz sozinho (o histórico de chat não é tocado).",
          .seguro, ["Library/Application Support/Cursor/Cache", "Library/Application Support/Cursor/CachedData"]),
        D("JetBrains", "Índices e saída de compilação das IDEs JetBrains. Refeitos ao abrir (plugins e ajustes ficam).",
          .seguro, ["Library/Caches/JetBrains"]),
        D("Zed", "Cache do editor Zed. Refeito sozinho.",
          .seguro, ["Library/Caches/Zed"]),
        D("Go", "Módulos e builds em cache do Go. Voltam no próximo build.",
          .seguro, ["go/pkg/mod/cache", ".cache/go-build"]),
        D("Maven", "Dependências baixadas pelo Maven. Baixam de novo no próximo build.",
          .seguro, [".m2/repository"]),
        D("SBT (Scala)", "Cache do sbt e do Ivy. Baixa de novo no próximo build.",
          .seguro, [".sbt", ".ivy2/cache"]),
        D("Ruby — gems", "Gems instaladas para o seu usuário. Programas instalados por gem install --user-install somem até reinstalar.",
          .conferir, [".gem"]),
        D("Bundler", "Gems em cache do Bundler. Voltam no próximo bundle install.",
          .seguro, [".bundle/cache"]),
        D("Composer (PHP)", "Pacotes em cache do Composer.",
          .seguro, [".composer/cache"]),
        D("Cargo (Rust)", "Registro e repositórios baixados pelo Cargo. Voltam no próximo build.",
          .seguro, [".cargo/registry", ".cargo/git"]),
        D("Terraform", "Plugins em cache do Terraform. Baixam de novo no próximo init.",
          .seguro, [".terraform.d/plugin-cache"]),
        D("GitHub Actions (act)", "Cache do act (Actions rodando local).",
          .seguro, [".cache/act"]),
        D("Vagrant", "Imagens de máquinas virtuais. Baixam de novo, mas são grandes.",
          .conferir, [".vagrant.d/boxes", ".vagrant.d/tmp"]),
        D("zsh", "Histórico por janela do Terminal e o cache de autocompletar. O zsh refaz.",
          .seguro, [".zsh_sessions", ".zcompdump"]),
        D("Apps Electron (Slack, Discord, Notion, Figma)", "Cache desses apps. Eles refazem sozinhos.",
          .seguro, ["Library/Application Support/Slack/Cache", "Library/Application Support/Slack/Code Cache",
                    "Library/Application Support/discord/Cache", "Library/Application Support/discord/Code Cache",
                    "Library/Application Support/Notion/Cache", "Library/Application Support/Figma/Cache"]),
        D("Playwright", "Navegadores baixados para testes. Voltam com playwright install.",
          .seguro, ["Library/Caches/ms-playwright", ".cache/ms-playwright"]),
    ]

    private static func D(_ n: String, _ e: String, _ nv: NivelRotulo, _ c: [String]) -> DefinicaoDev {
        DefinicaoDev(nome: n, explicacao: e, nivel: nv, caminhos: c)
    }

    /// Caminhos das definições de desenvolvimento (para não aparecerem duas vezes em "apps").
    static func caminhosDev(home: String) -> Set<String> {
        Set(desenvolvimento.flatMap { $0.caminhos.map { "\(home)/\($0)" } })
    }

    // MARK: Caches de apps fora de ~/Library/Caches (CacheDiscoveryPaths)

    static let nomesCacheAppSupport: Set<String> = [
        "Cache", "Code Cache", "GPUCache", "ShaderCache", "DawnWebGPUCache", "CachedData", "component_crx_cache",
    ]
    static let relativosCacheAppSupport = ["Crashpad/completed"]
    static let nomesCachePerfilChromium: Set<String> = ["GPUCache", "ShaderCache", "Code Cache", "Cache"]
    static let relativosPerfilChromium = ["Service Worker/CacheStorage", "Service Worker/ScriptCache"]

    /// Raízes de Application Support que não são cache de app (sensíveis).
    static let raizesAppSupportExcluidas: Set<String> = [
        "MobileSync", "CallHistoryDB", "AddressBook", "SyncServices", "Knowledge",
        "com.apple.TCC", "com.apple.sharedfilelist",
        "JetBrains", "Code", "Cursor",   // tratados nas definições de desenvolvimento
    ]

    /// Mídia em cache da Adobe (só os locais padrão "Common").
    static let adobe: [(relativo: String, chave: String)] = [
        ("Adobe/Common/Media Cache Files", "Adobe Media Cache Files"),
        ("Adobe/Common/Media Cache", "Adobe Media Cache"),
    ]

    /// Candidatos de cache dentro de `~/Library/Application Support/<app>/`.
    static func cachesAppSupport(em raizApp: URL, acesso: AcessoVarredura) -> [URL] {
        let fm = FileManager.default
        guard LocaisProtegidos.podeLer(raizApp, acesso: acesso) else { return [] }
        var res: [URL] = []
        var vistos = Set<String>()
        func add(_ u: URL) {
            guard LocaisProtegidos.podeLer(u, acesso: acesso) else { return }
            var dir: ObjCBool = false
            guard fm.fileExists(atPath: u.path, isDirectory: &dir), dir.boolValue else { return }
            let k = u.standardizedFileURL.path
            guard vistos.insert(k).inserted else { return }
            res.append(u.standardizedFileURL)
        }
        for n in nomesCacheAppSupport.sorted() { add(raizApp.appendingPathComponent(n, isDirectory: true)) }
        for r in relativosCacheAppSupport { add(raizApp.appendingPathComponent(r, isDirectory: true)) }
        let userData = raizApp.appendingPathComponent("User Data", isDirectory: true)
        if LocaisProtegidos.podeLer(userData, acesso: acesso),
           let perfis = try? fm.contentsOfDirectory(at: userData, includingPropertiesForKeys: [.isDirectoryKey],
                                                     options: [.skipsHiddenFiles]) {
            for p in perfis where (try? p.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                for n in nomesCachePerfilChromium.sorted() { add(p.appendingPathComponent(n, isDirectory: true)) }
                for r in relativosPerfilChromium { add(p.appendingPathComponent(r, isDirectory: true)) }
            }
        }
        return res
    }

    /// `~/Library/Containers/<id>/Data/Library/Caches[/<sub>]` — só com Acesso Total ao Disco.
    static func cachesDeConteineres(home: URL) -> [URL] {
        let fm = FileManager.default
        let raiz = home.appendingPathComponent("Library/Containers", isDirectory: true)
        guard let ids = try? fm.contentsOfDirectory(at: raiz, includingPropertiesForKeys: [.isDirectoryKey],
                                                    options: [.skipsHiddenFiles]) else { return [] }
        var res: [URL] = []
        for d in ids {
            guard !PoliticaSeguranca.conteinerProtegido(d.lastPathComponent) else { continue }
            let caches = d.appendingPathComponent("Data/Library/Caches", isDirectory: true)
            guard fm.fileExists(atPath: caches.path) else { continue }
            let filhos = (try? fm.contentsOfDirectory(at: caches, includingPropertiesForKeys: [.isDirectoryKey],
                                                      options: [.skipsHiddenFiles])) ?? []
            let subs = filhos.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            if subs.isEmpty { res.append(caches.standardizedFileURL) } else { res += subs.map(\.standardizedFileURL) }
        }
        return res
    }
}
