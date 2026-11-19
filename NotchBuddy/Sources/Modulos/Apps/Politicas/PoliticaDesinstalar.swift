import Foundation

// Regras do desinstalador: onde ficam os apps, onde procurar sobras, o que casa com um app e o
// portão que todo caminho atravessa antes de ir para a Lixeira.
//
// O portão reaproveita a política do Disco (`Modulos/Disco/Politicas/PoliticaSeguranca.swift`)
// para os vetos — caches de conta/iCloud/chaveiro, contêineres de Senhas/Apple ID/Apple Pay,
// registros protegidos e as raízes de conteúdo nunca saem, nem desinstalando. A lista do que
// PODE sair é outra (o app e as pastas dele, não caches que se refazem).
//
// Regras (sempre recusando mais):
// - sobra só como filho DIRETO de uma raiz;
// - casamento só por nome chega desmarcado;
// - `~/Library/WebKit` entra como raiz (casamento só por bundle id);
// - app em volume só de leitura (os da Apple que o macOS põe em /Applications) não é listado;
// - sem helper de administrador: o que é do root aparece, mas fica, e o motivo é dito.

enum CategoriaSobra: String, Sendable, Hashable, CaseIterable {
    case app = "App"
    case applicationSupport = "Application Support"
    case caches = "Caches"
    case httpStorages = "HTTPStorages"
    case preferencias = "Preferências"
    case conteineres = "Contêiner"
    case grupo = "Contêiner de grupo"
    case estadoSalvo = "Estado salvo"
    case webkit = "WebKit"
    case registros = "Registros"
    case launchAgents = "LaunchAgent"
    case launchDaemons = "LaunchDaemon"
}

enum MotivoCasamento: Sendable, Hashable {
    /// O próprio pacote .app.
    case pacote
    /// Bundle id exato (ou com sufixo conhecido: .plist, .savedState, .binarycookies).
    case bundleID
    /// Contêiner de grupo `<time>.<bundle id>`.
    case grupo
    /// Só o nome inteiro bate com o nome do app: chega desmarcado.
    case nome

    var marcadoPorPadrao: Bool { self != .nome }
}

/// O que identifica um app para procurar as sobras dele (instalado ou já apagado).
struct AlvoApp: Sendable, Hashable {
    let nome: String
    let bundleID: String?
    /// Onde o pacote está (ou estava).
    let caminho: String
}

struct Sobra: Sendable, Hashable, Identifiable {
    let caminho: String
    let categoria: CategoriaSobra
    let motivo: MotivoCasamento
    /// nil = não deu para medir.
    var bytes: Int64?
    /// Sem permissão de escrita (pasta do administrador, ou protegida pelo macOS): sem helper,
    /// o Crew não consegue mover.
    var precisaAdmin: Bool
    /// Só nas sobras de apps já apagados: de quem era (nome ou bundle id).
    var dono: String? = nil
    var id: String { caminho }
    var nome: String { (caminho as NSString).lastPathComponent }
}

enum PoliticaDesinstalar {
    static var home: String { PoliticaSeguranca.home }

    // MARK: Raízes de apps

    static func raizesApps(home: String = PoliticaDesinstalar.home) -> [String] {
        ["/Applications", "\(home)/Applications"]
    }

    /// Ids que nunca são oferecidos: o próprio Crew.
    static let idsProtegidos: Set<String> = {
        var ids: Set<String> = ["fr.louisraille.NotchBuddy"]
        if let id = Bundle.main.bundleIdentifier { ids.insert(id) }
        return ids
    }()

    static func appProtegido(caminho: String, bundleID: String?) -> Bool {
        let c = (caminho as NSString).standardizingPath
        if c.hasPrefix("/System/") { return true }
        if c == (Bundle.main.bundlePath as NSString).standardizingPath { return true }
        if let id = bundleID, idsProtegidos.contains(id) { return true }
        return false
    }

    // MARK: Raízes de sobras

    struct Raiz: Sendable {
        let caminho: String
        let categoria: CategoriaSobra
    }

    static func raizesSobras(home: String = PoliticaDesinstalar.home) -> [Raiz] {
        let lib = "\(home)/Library"
        return [
            Raiz(caminho: "\(lib)/Application Support", categoria: .applicationSupport),
            Raiz(caminho: "\(lib)/Caches", categoria: .caches),
            Raiz(caminho: "\(lib)/HTTPStorages", categoria: .httpStorages),
            Raiz(caminho: "\(lib)/Preferences", categoria: .preferencias),
            Raiz(caminho: "\(lib)/Containers", categoria: .conteineres),
            Raiz(caminho: "\(lib)/Group Containers", categoria: .grupo),
            Raiz(caminho: "\(lib)/Saved Application State", categoria: .estadoSalvo),
            Raiz(caminho: "\(lib)/WebKit", categoria: .webkit),
            Raiz(caminho: "\(lib)/Logs", categoria: .registros),
            Raiz(caminho: "\(lib)/LaunchAgents", categoria: .launchAgents),
            Raiz(caminho: "/Library/LaunchDaemons", categoria: .launchDaemons),
            Raiz(caminho: "/Library/LaunchAgents", categoria: .launchAgents),
            Raiz(caminho: "/Library/Application Support", categoria: .applicationSupport),
        ]
    }

    // MARK: Portão

    /// Todo caminho passa aqui imediatamente antes de ir para a Lixeira. Não é o casamento (quem
    /// decide o que é de qual app é `motivo`): é a cerca. Um erro no casamento nunca leva nada
    /// fora de um pacote .app numa raiz de apps ou de um filho direto de uma raiz de sobras.
    static func podeSair(_ caminho: String, home: String = PoliticaDesinstalar.home) -> Bool {
        guard caminho.hasPrefix("/"), !caminho.contains("/../"), !caminho.hasSuffix("/..") else { return false }
        let c = (caminho as NSString).standardizingPath
        if c.hasPrefix("/System/") || c == "/" { return false }
        let pai = (c as NSString).deletingLastPathComponent
        let nome = (c as NSString).lastPathComponent
        if nome.isEmpty || nome == "." { return false }

        if (c as NSString).pathExtension == "app" {
            let raizes = raizesApps(home: home)
            let avo = (pai as NSString).deletingLastPathComponent
            guard raizes.contains(pai) || raizes.contains(avo) else { return false }
            // Lê o id do próprio pacote: o Crew instalado nunca sai, rode de onde rodar.
            return !appProtegido(caminho: c, bundleID: Bundle(path: c)?.bundleIdentifier)
        }

        guard let raiz = raizesSobras(home: home).first(where: { $0.caminho == pai }) else { return false }

        // Vetos do Disco: valem também ao desinstalar.
        if PoliticaSeguranca.nuncaApagarExatos(home: home).contains(c) { return false }
        if PoliticaSeguranca.cacheProtegido(c, home: home) { return false }
        if PoliticaSeguranca.conteinerProtegido(caminho: c, home: home) { return false }
        if PoliticaSeguranca.logProtegido(c, home: home) { return false }
        if raiz.categoria == .grupo, let id = PoliticaOrfas.bundleIDDeGrupo(nome),
           PoliticaSeguranca.conteinerProtegido(id) { return false }
        // Identidade, chaveiro e pagamento, em qualquer raiz (mesma lista do Disco).
        if PoliticaSeguranca.nomeDeCacheProtegido(nome) { return false }
        // O próprio Crew.
        let n = nome.lowercased()
        if idsProtegidos.contains(where: { n.hasPrefix($0.lowercased()) }) || n == "notchbuddy" || n.hasPrefix("crew-dev") {
            return false
        }
        return true
    }

    // MARK: Casamento

    /// Por que `nome` (filho direto de uma raiz da categoria) é do app — ou nil se não é.
    /// Estrito: bundle id exato; nome só se for o nome inteiro (nunca pedaço), e só nas raízes
    /// de nome humano. Assim desinstalar um app do Google não leva `Application Support/Google`.
    static func motivo(nome: String, categoria: CategoriaSobra, app: AlvoApp) -> MotivoCasamento? {
        let n = nome.lowercased()
        if let id = app.bundleID?.lowercased(), !id.isEmpty {
            if n == id || n == id + ".plist" || n == id + ".savedstate" || n == id + ".binarycookies" {
                return .bundleID
            }
            // LaunchAgents/Daemons costumam ser `com.vendor.App.helper.plist`.
            if categoria == .launchAgents || categoria == .launchDaemons,
               n.hasPrefix(id + "."), n.hasSuffix(".plist") {
                return .bundleID
            }
            // `<time>.<bundle id>` ou `group.<bundle id>`: o bundle id inteiro como sufixo.
            if categoria == .grupo, n.hasSuffix("." + id) { return .grupo }
        }
        if categoria == .applicationSupport || categoria == .registros {
            let nomeApp = app.nome.lowercased()
            if !nomeApp.isEmpty, n == nomeApp { return .nome }
        }
        return nil
    }

    /// Outro app instalado que também reivindica a sobra (duas cópias, ou suíte que divide a
    /// pasta). Se houver, a sobra fica: tirar seria estragar o app que continua.
    static func outroDono(nome: String, categoria: CategoriaSobra, app: AlvoApp, instalados: [AlvoApp]) -> AlvoApp? {
        instalados.first { o in
            o.caminho != app.caminho && motivo(nome: nome, categoria: categoria, app: o) != nil
        }
    }

    /// Mover `caminho` esbarra em permissão? (pasta-pai sem escrita, ou a própria pasta sem escrita —
    /// do root, ou protegida pelo macOS, como `Application Support/discord`.)
    static func precisaAdmin(_ caminho: String) -> Bool {
        let fm = FileManager.default
        let pai = (caminho as NSString).deletingLastPathComponent
        if !fm.isWritableFile(atPath: pai) { return true }
        var dir: ObjCBool = false
        if fm.fileExists(atPath: caminho, isDirectory: &dir), dir.boolValue,
           !fm.isWritableFile(atPath: caminho) { return true }
        return false
    }
}
