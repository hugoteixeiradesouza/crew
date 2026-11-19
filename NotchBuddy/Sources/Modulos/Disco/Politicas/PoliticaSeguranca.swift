import Foundation

// Política estrita de permitir/recusar: TODO caminho passa por `avaliar` antes de ir para a
// Lixeira, e o que não está explicitamente permitido é recusado.
//
// Decisões (sempre na direção de recusar mais, nunca menos):
// - Fora desta leva, e por isso sem regra de "permitir": artefatos de projeto
//   (node_modules/target/… por nome), worktrees de agentes, sobras do Cursor, extensões
//   antigas de editor, versões antigas de framework de navegador, simuladores
//   (CoreSimulator/Devices) e o instalador do macOS em /Applications.
// - `User/workspaceStorage` do VS Code e do Cursor saiu da lista permitida: guarda estado por
//   projeto (inclusive histórico de chat do Cursor) — não é cache puro.
// - `Zed/db` saiu: é o banco de estado local do Zed.
// - Sem memória de veredito: cada chamada lê o disco de novo (a revalidação antes de mover
//   precisa ver o estado de agora).

enum DecisaoSeguranca: Equatable, Sendable {
    case permitir
    /// Na lista de nunca-apagar.
    case nuncaApagar
    /// Não está na lista permitida.
    case foraDaLista

    var motivo: String? {
        switch self {
        case .permitir: return nil
        case .nuncaApagar: return "Local protegido — nunca sai."
        case .foraDaLista: return "Fora da lista do que pode sair com segurança."
        }
    }
}

enum PoliticaSeguranca {
    static let home: String = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path

    /// Caminhos do sistema que pedem administrador — não são oferecidos.
    static let prefixosDoSistema: [String] = [
        "/Library/Caches",
        "/Library/Updates",
        "/private/var/log",
        "/var/log",
        "/private/var/db/DiagnosticPipeline",
        "/Library/Logs/DiagnosticReports",
    ]

    /// Pastas de `~/Library/Caches` que nunca são oferecidas. CloudKit e FamilyCircle o macOS
    /// protege; os caches dos serviços de conta/identidade dá para apagar, mas aí o
    /// accountsd/akd/identityservicesd perdem a autorização guardada e voltam a pedir a senha
    /// do chaveiro para cada serviço — a enxurrada de "… quer usar o chaveiro de login".
    static let cachesProtegidosNomes: Set<String> = [
        "CloudKit",
        "FamilyCircle",
        "com.apple.accountsd",
        "com.apple.appleaccountd",
        "com.apple.amsaccountsd",
        "com.apple.akd",
        "com.apple.AuthenticationServicesCore.AuthenticationServicesAgent",
        "com.apple.identityservicesd",
        "com.apple.iCloudHelper",
        "com.apple.icloudwebd",
        "com.apple.itunescloudd",
        "com.apple.iCloudNotificationAgent",
        "PassKit",
    ]

    /// Pedaços de nome (sem maiúsculas, em qualquer posição) que marcam uma pasta de
    /// `~/Library/Caches` como identidade, autenticação ou pagamento. Fecha a classe: um
    /// serviço novo que ninguém viu ainda é recusado por padrão. Errar para mais é o lado seguro.
    static let cachesProtegidosPedacos: [String] = [
        "account",
        "icloud",
        "itunescloud",
        "appleid",
        "authkit",
        "authentication",
        "authorization",
        "identityservice",
        "keychain",
        "passkit",
    ]

    /// Pastas de `~/Library/Logs` que o macOS não deixa remover nem com FDA.
    static let logsProtegidos: Set<String> = ["DiagnosticReportsForNewHardware"]

    /// Contêineres cujo cache o macOS guarda.
    static let conteineresProtegidos: Set<String> = [
        "com.apple.Safari",
        "com.apple.Home",
        "com.apple.homed",
        "com.apple.HomeKit",
    ]

    /// Senhas, AuthKit, Apple ID, Apple Pay e Contas da Internet: limpar o cache deles faz o
    /// chaveiro pedir senha de novo — nunca oferecer.
    static let conteineresProtegidosPrefixos: [String] = [
        "com.apple.Passwords",
        "com.apple.AuthKit",
        "com.apple.AppleAccount",
        "com.apple.Accounts",
        "com.apple.PassKit",
        "com.apple.Internet-Accounts",
    ]

    static func conteinerProtegido(_ bundleID: String) -> Bool {
        conteineresProtegidos.contains(bundleID) || conteineresProtegidosPrefixos.contains { bundleID.hasPrefix($0) }
    }

    /// O caminho e tudo abaixo dele nunca sai.
    static func nuncaApagarPrefixos(home: String) -> [String] {
        [
            "\(home)/Library/Keychains",
            "\(home)/Library/Preferences",
            "\(home)/Library/Mail",
            "\(home)/System",
            "\(home)/Pictures",
            "\(home)/Music",
            "\(home)/Movies",
            "/Library",
            "/usr",
            "/bin",
            "/sbin",
            "/etc",
            "/var",
        ]
    }

    /// Raízes de conteúdo do Hugo: a pasta em si nunca sai (caches permitidos abaixo delas, sim).
    static func nuncaApagarExatos(home: String) -> [String] {
        [
            home,
            "\(home)/Library",
            "\(home)/Library/Application Support",
            "\(home)/Documents",
            "\(home)/Desktop",
            "\(home)/Downloads",
        ]
    }

    /// Caminhos (e o que está abaixo) que podem sair. Cada um é cache, build ou registro que
    /// se refaz. Os marcados "conferir" no catálogo (Archives, .android, .stack, bazel,
    /// Docker, Vagrant) se refazem, mas não sozinhos/rápido.
    static func prefixosPermitidos(home: String) -> [String] {
        [
            "\(home)/Library/Caches",
            "\(home)/Library/Developer/Xcode/DerivedData",
            "\(home)/Library/Developer/Xcode/iOS DeviceSupport",
            "\(home)/Library/Developer/Xcode/DocumentationCache",
            "\(home)/Library/Developer/Xcode/Archives",
            "\(home)/.npm",
            "\(home)/.npm/_npx",
            "\(home)/.npm/_logs",
            "\(home)/.cache/node/corepack",
            "\(home)/.yarn/cache",
            "\(home)/.pnpm-store",
            "\(home)/.gradle/caches",
            "\(home)/.android",
            "\(home)/.cocoapods",
            "\(home)/.sbt",
            "\(home)/.ivy2/cache",
            "\(home)/.cache/act",
            "\(home)/.zcompdump",
            "\(home)/.cargo/registry",
            "\(home)/.pub-cache",
            "\(home)/.hex/packages",
            "\(home)/.cache/rebar3",
            "\(home)/.nuget/packages",
            "\(home)/.bun/install/cache",
            "\(home)/.cabal/packages",
            "\(home)/Library/Caches/org.swift.swiftpm",
            "\(home)/.swiftpm/cache",
            "\(home)/.stack",
            "\(home)/.cache/bazel",
            "\(home)/.flutter",
            // Backups de iPhone/iPad (MobileSync/Backup) NÃO entram: não se recuperam.
            "\(home)/Library/Logs",
            "\(home)/Library/Logs/DiagnosticReports",
            "\(home)/.m2/repository",
            "\(home)/.gem",
            "\(home)/.bundle/cache",
            "\(home)/.composer/cache",
            "\(home)/.cargo/git",
            "\(home)/.terraform.d/plugin-cache",
            "\(home)/.vagrant.d/tmp",
            "\(home)/.zsh_sessions",
            "\(home)/.cache/go-build",
            "\(home)/go/pkg/mod/cache",
            "\(home)/Library/Application Support/Code/Cache",
            "\(home)/Library/Application Support/Code/CachedData",
            "\(home)/Library/Application Support/Code/CachedExtensionVSIXs",
            "\(home)/Library/Application Support/Cursor/Cache",
            "\(home)/Library/Application Support/Cursor/CachedData",
            "\(home)/Library/Caches/JetBrains",
            // `Application Support/JetBrains` NÃO entra: plugins e ajustes da IDE.
            "\(home)/Library/Caches/Zed",
            "\(home)/Library/Caches/ms-playwright",
            "\(home)/.cache/ms-playwright",
            "\(home)/Library/Application Support/Slack/Cache",
            "\(home)/Library/Application Support/Slack/Code Cache",
            "\(home)/Library/Application Support/discord/Cache",
            "\(home)/Library/Application Support/discord/Code Cache",
            "\(home)/Library/Application Support/Notion/Cache",
            "\(home)/Library/Application Support/Figma/Cache",
            "\(home)/Library/Application Support/Adobe/Common/Media Cache Files",
            "\(home)/Library/Application Support/Adobe/Common/Media Cache",
            "\(home)/Library/Containers/com.docker.docker",
            "\(home)/.vagrant.d/boxes",
        ]
    }

    private static let permitidosCasa = prefixosPermitidos(home: home)

    /// Pastas em que só o conteúdo sai; a pasta em si fica.
    static func soEsvaziar(home: String) -> [String] {
        [
            "\(home)/Library/Logs",
            "\(home)/Library/Logs/DiagnosticReports",
            "\(home)/Library/Caches",
        ]
    }

    // MARK: Entrada principal

    /// O Crew pode oferecer este caminho para limpeza (sem pedir administrador)?
    static func podeOferecer(_ url: URL) -> Bool {
        !pedeAdministrador(url) && avaliar(url) == .permitir
    }

    static func pedeAdministrador(_ url: URL) -> Bool {
        let c = url.standardizedFileURL.path
        return prefixosDoSistema.contains { c == $0 || c.hasPrefix($0 + "/") }
    }

    static func deveSoEsvaziar(_ url: URL) -> Bool {
        let c = url.standardizedFileURL.path
        if soEsvaziar(home: home).contains(c) { return true }
        return pastaDeMidiaDoTelegram(c, home: home)
    }

    static func avaliar(_ url: URL) -> DecisaoSeguranca {
        let u = url.standardizedFileURL
        let c = u.path
        let h = home

        if cacheProtegido(c, home: h) || conteinerProtegido(caminho: c, home: h) || logProtegido(c, home: h) {
            return .nuncaApagar
        }
        // Application Support/JetBrains: plugins e ajustes. Recusado antes da regra de
        // "pasta que termina em Cache" poder liberar uma subpasta.
        let jb = "\(h)/Library/Application Support/JetBrains"
        if c == jb || c.hasPrefix(jb + "/") { return .nuncaApagar }
        // Estado por projeto do VS Code/Cursor (histórico de chat do Cursor mora aqui).
        for app in ["Code", "Cursor"] {
            let ws = "\(h)/Library/Application Support/\(app)/User"
            if c == ws || c.hasPrefix(ws + "/") { return .nuncaApagar }
        }

        let permitidos = h == home ? permitidosCasa : prefixosPermitidos(home: h)
        for p in permitidos where c == p || c.hasPrefix(p + "/") { return .permitir }

        if cacheDeApplicationSupport(c, home: h) { return .permitir }
        if cacheDeConteiner(c, home: h) { return .permitir }
        if midiaDoTelegram(c, home: h) { return .permitir }

        for b in nuncaApagarPrefixos(home: h) where c == b || c.hasPrefix(b + "/") { return .nuncaApagar }
        if nuncaApagarExatos(home: h).contains(c) { return .nuncaApagar }

        return .foraDaLista
    }

    // MARK: Regras

    static func cacheProtegido(_ c: String, home: String) -> Bool {
        let raiz = "\(home)/Library/Caches"
        guard c.hasPrefix(raiz + "/") else { return false }
        let topo = c.dropFirst(raiz.count + 1).split(separator: "/").first.map(String.init) ?? ""
        return nomeDeCacheProtegido(topo)
    }

    static func nomeDeCacheProtegido(_ nome: String) -> Bool {
        if cachesProtegidosNomes.contains(nome) { return true }
        let n = nome.lowercased()
        return cachesProtegidosPedacos.contains { n.contains($0) }
    }

    static func logProtegido(_ c: String, home: String) -> Bool {
        let raiz = "\(home)/Library/Logs"
        guard c.hasPrefix(raiz + "/") else { return false }
        let topo = c.dropFirst(raiz.count + 1).split(separator: "/").first.map(String.init) ?? ""
        return logsProtegidos.contains(topo)
    }

    static func conteinerProtegido(caminho c: String, home: String) -> Bool {
        let raiz = "\(home)/Library/Containers/"
        guard c.hasPrefix(raiz) else { return false }
        guard let id = c.dropFirst(raiz.count).split(separator: "/").first.map(String.init) else { return false }
        return conteinerProtegido(id)
    }

    static func cacheDeApplicationSupport(_ c: String, home: String) -> Bool {
        let raiz = "\(home)/Library/Application Support/"
        guard c.hasPrefix(raiz) else { return false }
        let rel = String(c.dropFirst(raiz.count))
        guard !rel.isEmpty else { return false }
        let partes = rel.split(separator: "/").map(String.init)
        guard partes.count >= 2 else { return false }
        if CatalogoCaches.raizesAppSupportExcluidas.contains(partes[0]) { return false }
        if rel.hasSuffix("/Crashpad/completed") { return true }
        let ultimo = partes.last ?? ""
        if CatalogoCaches.nomesCacheAppSupport.contains(ultimo) { return true }
        if rel.contains("/Service Worker/CacheStorage") || rel.contains("/Service Worker/ScriptCache") { return true }
        if rel.contains("/User Data/"), CatalogoCaches.nomesCachePerfilChromium.contains(ultimo) { return true }
        return false
    }

    static func cacheDeConteiner(_ c: String, home: String) -> Bool {
        let raiz = "\(home)/Library/Containers/"
        guard c.hasPrefix(raiz) else { return false }
        let p = c.dropFirst(raiz.count).split(separator: "/").map(String.init)
        guard p.count >= 4, p[1] == "Data", p[2] == "Library", p[3] == "Caches" else { return false }
        return !conteinerProtegido(p[0])
    }

    /// `…/6N38VWS5BX.ru.keepcoder.Telegram/[canal/]account-*/postbox/media` (ou abaixo).
    /// O banco da conta mora em `postbox`: nada mais raso que `media` é permitido.
    static func midiaDoTelegram(_ c: String, home: String) -> Bool {
        guard let p = partesTelegram(c, home: home) else { return false }
        return inicioMidiaTelegram(p) != nil
    }

    static func pastaDeMidiaDoTelegram(_ c: String, home: String) -> Bool {
        guard let p = partesTelegram(c, home: home), let i = inicioMidiaTelegram(p) else { return false }
        return p.count == i + 3
    }

    private static func partesTelegram(_ c: String, home: String) -> [String]? {
        let raiz = "\(home)/Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram/"
        guard c.hasPrefix(raiz) else { return nil }
        let rel = c.dropFirst(raiz.count)
        guard !rel.isEmpty else { return nil }
        return rel.split(separator: "/").map(String.init)
    }

    private static func inicioMidiaTelegram(_ p: [String]) -> Int? {
        for i in 0...1 where p.count >= i + 3 {
            if p[i].hasPrefix("account-"), p[i + 1] == "postbox", p[i + 2] == "media" { return i }
        }
        return nil
    }
}
