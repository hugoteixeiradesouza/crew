import AppKit
import Foundation

// Sobras de apps que não estão mais instalados: o desinstalador ao contrário. A dificuldade
// toda é o falso positivo, então cada regra puxa para "tem dono" (e deixar quieto).
// Na dúvida, não oferece.

enum PoliticaOrfas {
    /// Raízes cujos filhos têm nome de bundle id. Caches ficam com o Disco (se refazem);
    /// Preferências e LaunchAgents ficam de fora (pequenos e cheios de ids de serviço que
    /// nunca aparecem como app — onde o "órfão" erraria mais).
    static func raizes(home: String = PoliticaDesinstalar.home) -> [PoliticaDesinstalar.Raiz] {
        let lib = "\(home)/Library"
        return [
            .init(caminho: "\(lib)/Application Support", categoria: .applicationSupport),
            .init(caminho: "\(lib)/Containers", categoria: .conteineres),
            .init(caminho: "\(lib)/Group Containers", categoria: .grupo),
            .init(caminho: "\(lib)/HTTPStorages", categoria: .httpStorages),
            .init(caminho: "\(lib)/Saved Application State", categoria: .estadoSalvo),
        ]
    }

    /// Menos apps que isso = a leitura de /Applications está quebrada (volume fora, sem
    /// permissão) e tudo pareceria órfão: não procura.
    static let minimoDeApps = 5
    /// Sem mexer há pelo menos isso. App recém-apagado é assunto da vigia ("apagados
    /// recentemente"), não desta lista.
    static let diasParado = 30

    struct Indice: Sendable {
        /// Bundle ids (minúsculos) dos .app nas raízes de apps.
        let ids: Set<String>
        var raizesLegiveis = true
        var completo: Bool { raizesLegiveis && ids.count >= PoliticaOrfas.minimoDeApps }

        /// Algum app instalado é dono deste id — exato ou pai (`com.vendor.App.Helper` é do
        /// `com.vendor.App`). Também pergunta ao Launch Services, que conhece apps fora das
        /// raízes (inclusive os do sistema).
        func temDono(_ bundleID: String) -> Bool {
            let baixo = bundleID.lowercased()
            // Mesmo fabricante de um app instalado (`com.spotify.installer` com o Spotify lá):
            // costuma ser helper/instalador dele. Na dúvida, tem dono.
            let p = baixo.split(separator: ".")
            if p.count >= 3 {
                let fabricante = p.prefix(2).joined(separator: ".") + "."
                if ids.contains(where: { $0.hasPrefix(fabricante) }) { return true }
            }
            var partes = baixo.split(separator: ".").map(String.init)
            while partes.count >= 2 {
                let id = partes.joined(separator: ".")
                if ids.contains(id) { return true }
                if NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil { return true }
                partes.removeLast()
            }
            return false
        }
    }

    /// Prefixos de bibliotecas/SDKs embutidos em apps (minúsculos).
    static let bibliotecas: [String] = [
        "org.sparkle-project", "io.sentry", "io.branch", "com.crashlytics", "com.google.firebase",
        "com.firebase", "com.microsoft.appcenter", "com.bugsnag", "com.squirrel", "com.github.electron",
    ]

    static func orfa(bundleID: String, indice: Indice) -> Bool {
        let id = bundleID.lowercased()
        guard !id.isEmpty else { return false }
        // Serviços da Apple não ficam em /Applications: nunca são "app apagado".
        guard !id.hasPrefix("com.apple.") else { return false }
        // Bibliotecas que vários apps embutem: a pasta é de quem as usa, não de um app.
        guard !bibliotecas.contains(where: { id == $0 || id.hasPrefix($0 + ".") }) else { return false }
        // Só duas partes (`io.sentry`, `io.branch`) costuma ser SDK, não app.
        guard id.split(separator: ".").count >= 3 else { return false }
        guard !PoliticaSeguranca.conteinerProtegido(bundleID) else { return false }
        guard !PoliticaDesinstalar.idsProtegidos.contains(where: { $0.lowercased() == id }) else { return false }
        return !indice.temDono(bundleID)
    }

    /// Bundle id dono de um filho direto de uma raiz, ou nil se o nome não diz.
    static func bundleID(nome: String, categoria: CategoriaSobra, caminho: String) -> String? {
        switch categoria {
        case .applicationSupport:
            // Dado de verdade: só pasta cujo nome inteiro já é um bundle id. Nomes humanos
            // (Google, Adobe, Docker) costumam ser divididos entre produtos.
            var dir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: caminho, isDirectory: &dir), dir.boolValue,
                  pareceBundleID(nome) else { return nil }
            return nome
        case .conteineres:
            if pareceBundleID(nome) { return nome }
            return idDoMetadado(caminho)
        case .grupo:
            return bundleIDDeGrupo(nome)
        case .httpStorages:
            let c = nome.hasSuffix(".binarycookies") ? String(nome.dropLast(".binarycookies".count)) : nome
            return pareceBundleID(c) ? c : nil
        case .estadoSalvo:
            guard nome.hasSuffix(".savedState") else { return nil }
            let c = String(nome.dropLast(".savedState".count))
            return pareceBundleID(c) ? c : nil
        default:
            return nil
        }
    }

    /// Contêiner com nome de UUID: o dono está no metadado (só legível com Acesso Total ao Disco).
    static func idDoMetadado(_ caminho: String) -> String? {
        let url = URL(fileURLWithPath: caminho).appendingPathComponent(".com.apple.containermanagerd.metadata.plist")
        guard let d = try? Data(contentsOf: url),
              let o = try? PropertyListSerialization.propertyList(from: d, options: [], format: nil) as? [String: Any]
        else { return nil }
        if let info = o["MCMMetadataInfo"] as? [String: Any], let id = info["MCMMetadataIdentifier"] as? String, !id.isEmpty {
            return id
        }
        if let id = o["MCMMetadataIdentifier"] as? String, !id.isEmpty { return id }
        return nil
    }

    /// `<TIME>.<bundle id>`. O formato `group.<nome>` NÃO é tratado: é um nome de grupo que o
    /// app e as extensões dele dividem, não um bundle id — atribuir seria chute.
    static func bundleIDDeGrupo(_ nome: String) -> String? {
        guard let ponto = nome.firstIndex(of: "."), ehTime(String(nome[..<ponto])) else { return nil }
        let c = String(nome[nome.index(after: ponto)...])
        return pareceBundleID(c) ? c : nil
    }

    /// Identificador de time da Apple: 10 caracteres, maiúsculas e números.
    static func ehTime(_ s: String) -> Bool {
        s.count == 10 && s.allSatisfy { ($0.isUppercase && $0.isLetter) || $0.isNumber }
    }

    /// Cara de DNS reverso: 2+ partes, nenhuma vazia, começa com letra, não é UUID.
    static func pareceBundleID(_ s: String) -> Bool {
        guard UUID(uuidString: s) == nil else { return false }
        let p = s.split(separator: ".", omittingEmptySubsequences: false)
        guard p.count >= 2, p.allSatisfy({ !$0.isEmpty }), let f = s.first, f.isLetter else { return false }
        return true
    }

    /// Parado há `dias`? Data desconhecida = não está parado (fica quieto).
    static func parado(_ data: Date?, dias: Int = diasParado, agora: Date = Date()) -> Bool {
        guard let data, data > .distantPast else { return false }
        let s = agora.timeIntervalSince(data)
        return s >= 0 && s / 86_400 >= Double(dias)
    }

    /// Nome legível: o que o Finder mostra (resolvido do metadado do contêiner), senão o id.
    static func nomeAmigavel(bundleID: String, caminho: String) -> String {
        let url = URL(fileURLWithPath: caminho)
        if let n = try? url.resourceValues(forKeys: [.localizedNameKey]).localizedName,
           !n.isEmpty, n != url.lastPathComponent, UUID(uuidString: n) == nil {
            return (n as NSString).deletingPathExtension
        }
        return bundleID
    }
}
