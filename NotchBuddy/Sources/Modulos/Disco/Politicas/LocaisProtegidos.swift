import Foundation

// Sem Acesso Total ao Disco, o macOS protege algumas pastas com um pedido de permissão:
// mexer em Mesa, Documentos ou Downloads pergunta "o Crew quer acessar…", abrir o
// contêiner de outro app pergunta sobre "dados de outros apps". A varredura limitada fica
// fora de todas elas, para nunca disparar um pedido.

enum AcessoVarredura: Sendable, Equatable {
    case limitado
    case total

    /// Lê o disco: chamar uma vez por varredura, não por caminho.
    static func atual() -> AcessoVarredura { temAcessoTotalAoDisco() ? .total : .limitado }

    /// O banco do TCC do sistema só abre com Acesso Total ao Disco, e a recusa é silenciosa
    /// (não aparece pedido). Não lista `~/Library/Containers` para testar:
    /// isso pode disparar o pedido de "dados de outros apps".
    static func temAcessoTotalAoDisco() -> Bool {
        let fd = open("/Library/Application Support/com.apple.TCC/TCC.db", O_RDONLY)
        if fd >= 0 { close(fd); return true }
        return false
    }
}

/// As pastas que a varredura limitada não toca.
enum LocaisProtegidos {
    /// Relativas à home. As três primeiras pedem permissão por pasta; contêineres e iCloud
    /// pedem ou travam em provedores de arquivo; Safari, Mail e Mensagens são recusados em
    /// silêncio; os caches de mídia pedem "Mídia e Apple Music".
    static let raizesRelativas: [String] = [
        "Desktop",
        "Documents",
        "Downloads",
        "Library/Containers",
        "Library/Group Containers",
        "Library/Mobile Documents",
        "Library/CloudStorage",
        "Library/Safari",
        "Library/Mail",
        "Library/Messages",
    ] + raizesMidia

    /// Caches de música e TV da Apple: medir `~/Library/Caches` sem FDA fez o macOS pedir
    /// "Mídia e Apple Music". Ficam de fora na varredura limitada.
    static let raizesMidia: [String] = [
        "Library/Caches/com.apple.Music",
        "Library/Caches/com.apple.iTunes",
        "Library/Caches/com.apple.TV",
        "Library/Caches/com.apple.podcasts",
        "Library/Caches/com.apple.watchlistd",
        "Library/Caches/com.apple.AMPLibraryAgent",
        "Library/Caches/com.apple.AMPArtworkAgent",
        "Library/Caches/com.apple.AMPDevicesAgent",
    ]

    static let maxSaltosLink = 8

    static func raizes(home: String = PoliticaSeguranca.home) -> [String] {
        raizesRelativas.map { "\(home)/\($0)" }
    }

    /// Se a varredura pode ler `url`. Anda componente a componente e lê cada link simbólico
    /// com `destinationOfSymbolicLink` (que lê o link, nunca o destino), checando as raízes
    /// antes. `fileExists`/`standardizedFileURL` seguiriam o link — é esse acesso que pede.
    static func podeLer(_ url: URL, acesso: AcessoVarredura) -> Bool {
        guard acesso == .limitado else { return true }
        return caminhoReal(de: url.path) != nil
    }

    /// Caminho real com os links resolvidos, ou nil se algum salto cair numa raiz protegida.
    static func caminhoReal(de caminho: String) -> String? {
        let rz = raizesResolvidas()
        return resolvendoLinks(caminho) { dentro($0, de: rz) }
    }

    private static func raizesResolvidas() -> [String] {
        let r = raizes()
        guard let homeReal = resolvendoLinks(PoliticaSeguranca.home, parar: { _ in false }) else { return r }
        let resolvidas = raizesRelativas.map { "\(homeReal)/\($0)" }
        return resolvidas == r ? r : r + resolvidas
    }

    /// Comparação sem maiúsculas: o APFS padrão e o TCC também ignoram.
    static func dentro(_ caminho: String, de raizes: [String]) -> Bool {
        let c = caminho.lowercased()
        return raizes.contains { r in
            let r = r.lowercased()
            return c == r || c.hasPrefix(r + "/")
        }
    }

    private static func resolvendoLinks(_ caminho: String, parar: (String) -> Bool) -> String? {
        let fm = FileManager.default
        var restante = componentes(caminho)
        var resolvido: [String] = []
        var saltos = 0
        while !restante.isEmpty {
            let c = restante.removeFirst()
            if c == ".." {
                if !resolvido.isEmpty { resolvido.removeLast() }
                continue
            }
            let prox = resolvido + [c]
            let proxCaminho = "/" + prox.joined(separator: "/")
            if parar(proxCaminho) { return nil }
            guard let destino = try? fm.destinationOfSymbolicLink(atPath: proxCaminho) else {
                resolvido = prox
                continue
            }
            saltos += 1
            guard saltos <= maxSaltosLink else { return nil }
            if destino.hasPrefix("/") { resolvido = [] }
            restante = componentes(destino) + restante
        }
        let final = "/" + resolvido.joined(separator: "/")
        return parar(final) ? nil : final
    }

    private static func componentes(_ caminho: String) -> [String] {
        caminho.split(separator: "/", omittingEmptySubsequences: true).map(String.init).filter { $0 != "." }
    }
}
