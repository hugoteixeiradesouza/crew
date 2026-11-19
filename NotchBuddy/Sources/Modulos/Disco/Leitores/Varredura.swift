import Foundation

// Varredura sob demanda (botão "Procurar"): acha os caches oferecíveis, passa cada um pela
// política e mede com `du`. Roda fora da main (chamada por Task.detached no serviço).

struct ItemLimpeza: Identifiable, Sendable, Hashable {
    let id: String
    let grupo: GrupoLimpeza
    let nome: String
    let explicacao: String
    let nivel: NivelRotulo
    var caminhos: [String]
    var bytes: Int64
}

enum Varredura {
    /// Abaixo disto não vale uma linha na lista.
    static let minimoBytes: Int64 = 1_000_000

    static func executar(acesso: AcessoVarredura, etapa: @Sendable (String) async -> Void) async -> [ItemLimpeza] {
        let fm = FileManager.default
        let homeURL = fm.homeDirectoryForCurrentUser
        let home = PoliticaSeguranca.home
        var itens: [ItemLimpeza] = []
        var vistos = CatalogoCaches.caminhosDev(home: home)

        await etapa("Procurando caches de desenvolvimento…")
        for d in CatalogoCaches.desenvolvimento {
            let existentes = d.caminhos.map { "\(home)/\($0)" }.filter { oferecivel(URL(fileURLWithPath: $0), acesso: acesso) }
            guard !existentes.isEmpty else { continue }
            itens.append(ItemLimpeza(id: "dev:" + d.nome, grupo: .desenvolvimento, nome: d.nome, explicacao: d.explicacao,
                                     nivel: d.nivel, caminhos: existentes, bytes: 0))
        }

        await etapa("Procurando caches de apps…")
        var porRotulo: [String: ItemLimpeza] = [:]
        func addApp(_ url: URL, nomePasta: String) {
            let c = url.standardizedFileURL.path
            guard !vistos.contains(c), let r = Rotulos.seguro(nomePasta), oferecivel(url, acesso: acesso) else { return }
            vistos.insert(c)
            let id = "app:" + r.chave
            if porRotulo[id] == nil {
                porRotulo[id] = ItemLimpeza(id: id, grupo: .apps, nome: r.nome, explicacao: Rotulos.explicacao(tipo: r.tipo),
                                            nivel: .seguro, caminhos: [], bytes: 0)
            }
            porRotulo[id]?.caminhos.append(c)
        }

        // ~/Library/Caches/<pasta>
        let caches = homeURL.appendingPathComponent("Library/Caches", isDirectory: true)
        for d in (try? fm.contentsOfDirectory(at: caches, includingPropertiesForKeys: [.isDirectoryKey],
                                              options: [.skipsHiddenFiles])) ?? [] {
            if Task.isCancelled { return [] }
            addApp(d, nomePasta: d.lastPathComponent)
        }
        // ~/Library/Application Support/<app>/{Cache, Code Cache, GPUCache…}
        let appSupport = homeURL.appendingPathComponent("Library/Application Support", isDirectory: true)
        for app in (try? fm.contentsOfDirectory(at: appSupport, includingPropertiesForKeys: [.isDirectoryKey],
                                                options: [.skipsHiddenFiles])) ?? [] {
            if Task.isCancelled { return [] }
            guard !CatalogoCaches.raizesAppSupportExcluidas.contains(app.lastPathComponent) else { continue }
            for c in CatalogoCaches.cachesAppSupport(em: app, acesso: acesso) { addApp(c, nomePasta: app.lastPathComponent) }
        }
        for a in CatalogoCaches.adobe {
            addApp(appSupport.appendingPathComponent(a.relativo, isDirectory: true), nomePasta: a.chave)
        }
        // Contêineres de apps: sem Acesso Total ao Disco o macOS pergunta por cada um — fica de fora.
        if acesso == .total {
            for c in CatalogoCaches.cachesDeConteineres(home: homeURL) {
                if Task.isCancelled { return [] }
                let partes = c.pathComponents
                let id = partes.firstIndex(of: "Containers").flatMap { $0 + 1 < partes.count ? partes[$0 + 1] : nil }
                let nome = c.lastPathComponent == "Caches" ? (id ?? "") : c.lastPathComponent
                if Rotulos.seguro(nome) != nil { addApp(c, nomePasta: nome) } else if let id { addApp(c, nomePasta: id) }
            }
        }
        itens += porRotulo.values

        // Registros: ~/Library/Logs (só o conteúdo sai; a pasta fica).
        let logs = homeURL.appendingPathComponent("Library/Logs", isDirectory: true)
        if oferecivel(logs, acesso: acesso), let r = Rotulos.seguro("applogs") {
            itens.append(ItemLimpeza(id: "sis:logs", grupo: .registros, nome: r.nome,
                                     explicacao: "Registros antigos e relatórios de travamento dos apps. A pasta fica; só o conteúdo sai.",
                                     nivel: .seguro, caminhos: [logs.standardizedFileURL.path], bytes: 0))
        }

        await etapa("Medindo…")
        let tamanhos = await Tamanhos.medir(itens.flatMap { $0.caminhos.map { URL(fileURLWithPath: $0) } })
        if Task.isCancelled { return [] }
        for i in itens.indices {
            itens[i].bytes = itens[i].caminhos.reduce(0) { $0 + (tamanhos[$1] ?? 0) }
        }
        return itens.filter { $0.bytes >= minimoBytes }.sorted { $0.bytes > $1.bytes }
    }

    /// Existe, não é link simbólico, dá para ler sem pedir permissão e a política permite.
    /// A ordem importa: a checagem de leitura vem antes de qualquer acesso que siga link.
    static func oferecivel(_ url: URL, acesso: AcessoVarredura) -> Bool {
        guard LocaisProtegidos.podeLer(url, acesso: acesso) else { return false }
        guard let atrib = try? FileManager.default.attributesOfItem(atPath: url.path),
              let tipo = atrib[.type] as? FileAttributeType, tipo != .typeSymbolicLink else { return false }
        return PoliticaSeguranca.podeOferecer(url)
    }
}
