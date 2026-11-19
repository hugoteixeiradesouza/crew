import Foundation

// A tabela é a única fonte do que é "artefato reconstruível" de um projeto: o que identifica o
// projeto, qual pasta sai, como volta e quão arriscado é tirar. Uma regra só PROPÕE um caminho;
// todo caminho ainda passa por `PoliticaArtefatos.avaliar` antes de ir para a Lixeira.

enum Reinstalacao: Hashable, Sendable {
    /// Comando rodado na raiz do projeto. `{raiz}` vira o caminho.
    case comando(String)
    /// Passos em texto, para ecossistemas sem um comando único confiável.
    case orientacao(String)
    /// npm/pnpm/yarn, escolhido pelo lockfile presente.
    case gerenciadorNode
    /// `pod install`, de onde o Podfile estiver.
    case cocoaPods
}

/// "seguro" entra marcado; "conferir" se refaz, mas custa tempo (nunca marcado por padrão).
enum NivelArtefato: Sendable, Hashable { case seguro, conferir }

struct RegraArtefato: Hashable, Sendable {
    /// Rótulo curto (aparece na linha).
    let tipo: String
    let ecossistema: String
    /// Pasta que sai, relativa à raiz (pode ter subpasta: `ios/Pods`).
    let pasta: String
    /// Um destes, relativo à raiz, precisa existir para a regra valer.
    let marcadores: [String]
    /// Extensões que identificam o projeto quando não há nome fixo (`.csproj`, `.tf`…).
    let extensoesMarcadoras: [String]
    /// Um destes precisa existir para reconstruir igual (relativo à pasta-mãe do artefato).
    let lockfiles: [String]
    /// Prova de que dá para reconstruir (relativo à pasta-mãe do artefato).
    let provasDeReconstrucao: [String]
    /// Se algum destes existir DENTRO do artefato, ele nunca sai (ex.: estado do Terraform).
    let recusarSeTiver: [String]
    let reinstalacao: Reinstalacao
    let nivel: NivelArtefato

    init(_ tipo: String, _ ecossistema: String, pasta: String, marcadores: [String], extensoes: [String] = [],
         lockfiles: [String] = [], provas: [String] = [], recusarSeTiver: [String] = [],
         reinstalacao: Reinstalacao, nivel: NivelArtefato = .seguro) {
        self.tipo = tipo
        self.ecossistema = ecossistema
        self.pasta = pasta
        self.marcadores = marcadores
        self.extensoesMarcadoras = extensoes
        self.lockfiles = lockfiles
        self.provasDeReconstrucao = provas
        self.recusarSeTiver = recusarSeTiver
        self.reinstalacao = reinstalacao
        self.nivel = nivel
    }

    /// `raiz` é mesmo um projeto desta regra? Marcadores lidos com `lstat` (não segue link).
    func valeNaRaiz(_ raiz: URL) -> Bool {
        if marcadores.contains(where: { existeSemSeguir(raiz.appendingPathComponent($0)) }) { return true }
        guard !extensoesMarcadoras.isEmpty,
              let filhos = try? FileManager.default.contentsOfDirectory(at: raiz, includingPropertiesForKeys: nil,
                                                                       options: [.skipsHiddenFiles]) else { return false }
        let quer = Set(extensoesMarcadoras)
        return filhos.contains { quer.contains($0.pathExtension.lowercased()) }
    }

    /// Esta pasta guarda algo que não pode ir embora, mesmo sendo do tipo que normalmente pode?
    /// Sem memória: o conteúdo pode mudar entre uma varredura e outra.
    func recusa(_ artefato: URL) -> Bool {
        recusarSeTiver.contains { existeSemSeguir(artefato.appendingPathComponent($0)) }
    }
}

/// Dá para trazer de volta igual?
enum EstadoReinstalacao: Sendable, Hashable {
    case reinstalavel
    /// Falta o lockfile (ou a prova de reconstrução): volta, mas talvez com versões diferentes.
    case semLockfile
    case naoSeAplica
}

func existeSemSeguir(_ url: URL) -> Bool {
    (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
}

enum CatalogoArtefatos {
    static let regras: [RegraArtefato] = [
        // JavaScript / TypeScript
        .init("Dependências", "Node", pasta: "node_modules", marcadores: ["package.json"],
              lockfiles: ["package-lock.json", "npm-shrinkwrap.json", "yarn.lock", "pnpm-lock.yaml", "bun.lockb", "bun.lock"],
              provas: ["package.json"], reinstalacao: .gerenciadorNode),
        .init("Build do Next.js", "Node", pasta: ".next", marcadores: ["package.json"], provas: ["package.json"],
              reinstalacao: .gerenciadorNode),
        .init("Build do Nuxt", "Node", pasta: ".nuxt",
              marcadores: ["nuxt.config.ts", "nuxt.config.js", "nuxt.config.mjs", "nuxt.config.cjs"], provas: ["package.json"],
              reinstalacao: .gerenciadorNode),
        .init("Saída do Nuxt", "Node", pasta: ".output",
              marcadores: ["nuxt.config.ts", "nuxt.config.js", "nuxt.config.mjs", "nuxt.config.cjs"], provas: ["package.json"],
              reinstalacao: .gerenciadorNode),
        .init("Build do SvelteKit", "Node", pasta: ".svelte-kit", marcadores: ["package.json"], provas: ["package.json"],
              reinstalacao: .gerenciadorNode),
        .init("Build do Astro", "Node", pasta: ".astro", marcadores: ["package.json"], provas: ["package.json"],
              reinstalacao: .gerenciadorNode),
        .init("Cache do Angular", "Node", pasta: ".angular", marcadores: ["package.json"], provas: ["package.json"],
              reinstalacao: .gerenciadorNode),
        .init("Cache do Turborepo", "Node", pasta: ".turbo", marcadores: ["package.json"], provas: ["package.json"],
              reinstalacao: .gerenciadorNode),
        .init("Cache do Parcel", "Node", pasta: ".parcel-cache", marcadores: ["package.json"], provas: ["package.json"],
              reinstalacao: .gerenciadorNode),
        .init("Cache do Vite", "Node", pasta: "node_modules/.vite", marcadores: ["package.json"], provas: ["../package.json"],
              reinstalacao: .gerenciadorNode),

        // Rust
        .init("Build do Rust", "Rust", pasta: "target", marcadores: ["Cargo.toml"], provas: ["Cargo.toml"],
              reinstalacao: .comando("cd \"{raiz}\" && cargo build")),

        // Python
        .init("Ambiente Python", "Python", pasta: "venv", marcadores: ["requirements.txt", "pyproject.toml"],
              provas: ["requirements.txt", "pyproject.toml"],
              reinstalacao: .orientacao("Recrie o ambiente Python do jeito de sempre (ex.: python3 -m venv venv && pip install -r requirements.txt).")),
        .init("Ambiente Python", "Python", pasta: ".venv", marcadores: ["requirements.txt", "pyproject.toml"],
              provas: ["requirements.txt", "pyproject.toml"],
              reinstalacao: .orientacao("Recrie o ambiente Python do jeito de sempre (ex.: uv sync, ou python3 -m venv .venv && pip install -r requirements.txt).")),
        .init("Cache do pytest", "Python", pasta: ".pytest_cache", marcadores: ["requirements.txt", "pyproject.toml"],
              reinstalacao: .orientacao("Volta sozinho na próxima vez que os testes rodarem.")),
        .init("Cache do mypy", "Python", pasta: ".mypy_cache", marcadores: ["requirements.txt", "pyproject.toml"],
              reinstalacao: .orientacao("Volta sozinho na próxima vez que o mypy rodar.")),
        .init("Cache do ruff", "Python", pasta: ".ruff_cache", marcadores: ["requirements.txt", "pyproject.toml"],
              reinstalacao: .orientacao("Volta sozinho na próxima vez que o ruff rodar.")),
        .init("Ambientes do tox", "Python", pasta: ".tox", marcadores: ["tox.ini"],
              reinstalacao: .comando("cd \"{raiz}\" && tox")),

        // Flutter / Dart
        .init("Cache do Dart", "Flutter", pasta: ".dart_tool", marcadores: ["pubspec.yaml"], lockfiles: ["pubspec.lock"],
              provas: ["pubspec.yaml"], reinstalacao: .comando("cd \"{raiz}\" && flutter pub get")),
        .init("Build do Flutter", "Flutter", pasta: "build", marcadores: ["pubspec.yaml"], lockfiles: ["pubspec.lock"],
              provas: ["pubspec.yaml"], reinstalacao: .comando("cd \"{raiz}\" && flutter pub get")),

        // Android / Gradle
        .init("Gradle", "Android", pasta: ".gradle",
              marcadores: ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts",
                           "android/build.gradle", "android/build.gradle.kts"],
              provas: ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts",
                       "android/build.gradle", "android/build.gradle.kts"],
              reinstalacao: .orientacao("Rode o build de sempre: o Gradle baixa de novo o que precisa.")),

        // Xcode / CocoaPods / SwiftPM
        .init("Pods", "CocoaPods", pasta: "Pods", marcadores: ["Podfile"], lockfiles: ["Podfile.lock"],
              reinstalacao: .cocoaPods),
        .init("Pods", "CocoaPods", pasta: "ios/Pods", marcadores: ["ios/Podfile"], lockfiles: ["Podfile.lock"],
              reinstalacao: .cocoaPods),
        .init("Build do Swift", "Swift", pasta: ".build", marcadores: ["Package.swift"], provas: ["Package.swift"],
              reinstalacao: .comando("cd \"{raiz}\" && swift build")),

        // Elixir
        .init("Build do Elixir", "Elixir", pasta: "_build", marcadores: ["mix.exs"], provas: ["mix.exs"],
              reinstalacao: .comando("cd \"{raiz}\" && mix compile")),
        .init("Dependências do Elixir", "Elixir", pasta: "deps", marcadores: ["mix.exs"], lockfiles: ["mix.lock"],
              provas: ["mix.exs"], reinstalacao: .comando("cd \"{raiz}\" && mix deps.get")),

        // JVM
        .init("Build do Maven", "Maven", pasta: "target", marcadores: ["pom.xml"], provas: ["pom.xml"],
              reinstalacao: .comando("cd \"{raiz}\" && mvn package")),
        .init("Build do Gradle", "Gradle", pasta: "build", marcadores: ["build.gradle", "build.gradle.kts"],
              provas: ["build.gradle", "build.gradle.kts"], reinstalacao: .comando("cd \"{raiz}\" && ./gradlew build")),
        .init("Build do sbt", "sbt", pasta: "target", marcadores: ["build.sbt"], provas: ["build.sbt"],
              reinstalacao: .comando("cd \"{raiz}\" && sbt compile")),
        .init("Build do sbt", "sbt", pasta: "project/target", marcadores: ["build.sbt"], provas: ["../build.sbt"],
              reinstalacao: .comando("cd \"{raiz}\" && sbt compile")),

        // .NET
        .init("Build do .NET", ".NET", pasta: "bin", marcadores: [], extensoes: ["csproj", "fsproj", "vbproj", "sln"],
              reinstalacao: .comando("cd \"{raiz}\" && dotnet build")),
        .init("Intermediários do .NET", ".NET", pasta: "obj", marcadores: [], extensoes: ["csproj", "fsproj", "vbproj", "sln"],
              reinstalacao: .comando("cd \"{raiz}\" && dotnet build")),

        // PHP / Ruby
        .init("Pacotes PHP", "PHP", pasta: "vendor", marcadores: ["composer.json"], lockfiles: ["composer.lock"],
              provas: ["composer.json"], reinstalacao: .comando("cd \"{raiz}\" && composer install")),
        .init("Gems", "Ruby", pasta: "vendor/bundle", marcadores: ["Gemfile"], lockfiles: ["../Gemfile.lock"],
              provas: ["../Gemfile"], reinstalacao: .comando("cd \"{raiz}\" && bundle install")),

        // Haskell
        .init("Build do Stack", "Haskell", pasta: ".stack-work", marcadores: ["stack.yaml"], provas: ["stack.yaml"],
              reinstalacao: .comando("cd \"{raiz}\" && stack build")),
        .init("Build do Cabal", "Haskell", pasta: "dist-newstyle", marcadores: [], extensoes: ["cabal"],
              reinstalacao: .comando("cd \"{raiz}\" && cabal build")),

        // Zig / OCaml / nativo
        .init("Cache do Zig", "Zig", pasta: ".zig-cache", marcadores: ["build.zig"], provas: ["build.zig"],
              reinstalacao: .comando("cd \"{raiz}\" && zig build")),
        .init("Cache do Zig", "Zig", pasta: "zig-cache", marcadores: ["build.zig"], provas: ["build.zig"],
              reinstalacao: .comando("cd \"{raiz}\" && zig build")),
        .init("Saída do Zig", "Zig", pasta: "zig-out", marcadores: ["build.zig"], provas: ["build.zig"],
              reinstalacao: .comando("cd \"{raiz}\" && zig build")),
        .init("Build do Dune", "OCaml", pasta: "_build", marcadores: ["dune-project"], provas: ["dune-project"],
              reinstalacao: .comando("cd \"{raiz}\" && dune build")),
        .init("Build do CMake", "CMake", pasta: "build", marcadores: ["CMakeLists.txt"], provas: ["CMakeLists.txt"],
              reinstalacao: .orientacao("Rode de novo a configuração e o build do CMake de sempre.")),

        // Infra / motores. `.terraform` pode guardar o estado da infraestrutura: com estado, nunca sai.
        .init("Plugins do Terraform", "Terraform", pasta: ".terraform", marcadores: [], extensoes: ["tf"],
              recusarSeTiver: ["terraform.tfstate", "terraform.tfstate.backup", "environment"],
              reinstalacao: .comando("cd \"{raiz}\" && terraform init"), nivel: .conferir),
        .init("Cache do Godot", "Godot", pasta: ".godot", marcadores: ["project.godot"], provas: ["project.godot"],
              reinstalacao: .orientacao("Volta sozinho na próxima vez que o projeto abrir no Godot.")),
        .init("Library do Unity", "Unity", pasta: "Library", marcadores: ["ProjectSettings/ProjectVersion.txt"],
              provas: ["ProjectSettings/ProjectVersion.txt"],
              reinstalacao: .orientacao("O Unity reimporta tudo na próxima abertura — num projeto grande, demora."), nivel: .conferir),
        .init("Temp do Unity", "Unity", pasta: "Temp", marcadores: ["ProjectSettings/ProjectVersion.txt"],
              reinstalacao: .orientacao("Volta sozinho na próxima abertura no Unity."), nivel: .conferir),
        .init("Intermediários do Unreal", "Unreal", pasta: "Intermediate", marcadores: [], extensoes: ["uproject"],
              reinstalacao: .orientacao("O Unreal refaz no próximo build."), nivel: .conferir),
        .init("Cache do Unreal", "Unreal", pasta: "DerivedDataCache", marcadores: [], extensoes: ["uproject"],
              reinstalacao: .orientacao("O Unreal refaz no próximo build, com shaders — o primeiro build demora."), nivel: .conferir),
    ]

    /// Regras pelo último componente da pasta (`target` → Rust, Maven, sbt).
    static let porNomeDePasta: [String: [RegraArtefato]] =
        Dictionary(grouping: regras) { ($0.pasta as NSString).lastPathComponent }

    /// Nomes que uma regra pode propor: a varredura de raízes não desce neles.
    static let nomesDeArtefato: Set<String> = Set(regras.map { ($0.pasta as NSString).lastPathComponent })

    // MARK: Reinstalação

    /// Dá para reconstruir igual? Provas e lockfiles relativos à pasta-mãe do artefato.
    /// Basta uma regra com toda a prova; regra que não pede prova não decide.
    static func estadoReinstalacao(_ regra: RegraArtefato, artefato: URL) -> EstadoReinstalacao {
        let mae = artefato.deletingLastPathComponent()
        func existe(_ rel: String) -> Bool { existeSemSeguir(mae.appendingPathComponent(rel).standardizedFileURL) }
        // Regras irmãs (mesmo tipo de pasta e ecossistema): `venv`/`.venv`, os dois caches do Zig.
        let irmas = regras.filter { $0.ecossistema == regra.ecossistema && $0.tipo == regra.tipo }
        var algumaPediu = false
        for r in irmas {
            guard !r.provasDeReconstrucao.isEmpty || !r.lockfiles.isEmpty else { continue }
            algumaPediu = true
            if !r.provasDeReconstrucao.isEmpty, !r.provasDeReconstrucao.contains(where: existe) { continue }
            if !r.lockfiles.isEmpty, !r.lockfiles.contains(where: existe) { continue }
            return .reinstalavel
        }
        return algumaPediu ? .semLockfile : .naoSeAplica
    }

    /// O comando (ou o passo) para trazer de volta.
    static func comoReinstalar(_ regra: RegraArtefato, raiz: URL) -> String {
        switch regra.reinstalacao {
        case .comando(let t):
            return t.replacingOccurrences(of: "{raiz}", with: raiz.path)
        case .orientacao(let t):
            return t
        case .gerenciadorNode:
            return "cd \"\(raiz.path)\" && \(gerenciadorNode(raiz)) install"
        case .cocoaPods:
            let ios = raiz.appendingPathComponent("ios")
            if existeSemSeguir(ios.appendingPathComponent("Podfile")) { return "cd \"\(ios.path)\" && pod install" }
            return "cd \"\(raiz.path)\" && pod install"
        }
    }

    static func gerenciadorNode(_ raiz: URL) -> String {
        func tem(_ n: String) -> Bool { existeSemSeguir(raiz.appendingPathComponent(n)) }
        if tem("pnpm-lock.yaml") { return "pnpm" }
        if tem("yarn.lock") { return "yarn" }
        if tem("bun.lockb") || tem("bun.lock") { return "bun" }
        return "npm"
    }
}
