import Darwin
import Foundation

// Arquivos grandes e duplicados: arquivos PESSOAIS, por isso fora da política de caches.
//
// Diferenças (sempre recusando mais): sem Acesso Total ao Disco, Mesa/Documentos/Downloads ficam
// de fora (abrir dispara o pedido do macOS); a pasta da Música e da TV da Apple, inteiras, ficam
// de fora; arquivo que está só no iCloud (sem os dados no Mac) nunca é lido nem oferecido.

enum PoliticaArquivos {
    static let pastasRaiz = ["Documents", "Desktop", "Downloads", "Movies", "Music", "Pictures"]

    /// As pastas onde procurar, conforme o acesso. Sem Acesso Total: só Filmes, Música e Imagens
    /// (o macOS não pede permissão por elas; as bibliotecas gerenciadas ficam de fora abaixo).
    static func raizes(acesso: AcessoVarredura) -> [URL] {
        let home = URL(fileURLWithPath: PoliticaSeguranca.home, isDirectory: true)
        return pastasRaiz.map { home.appendingPathComponent($0, isDirectory: true) }
            .filter { LocaisProtegidos.podeLer($0, acesso: acesso) }
    }

    /// Bibliotecas gerenciadas e pacotes: nunca entra nem oferece.
    static let pastasExcluidas: Set<String> = [
        "Photos Library.photoslibrary", "Photo Booth Library", "iMovie Library.imovielibrary",
        "iMovie Theater.theater", "TV Library.tvlibrary", "Music Library.musiclibrary", "GarageBand",
        "Final Cut Backups.localized", "Motion Templates.localized", "Audio Music Apps",
    ]
    static let extensoesExcluidas: Set<String> = [
        "app", "photoslibrary", "imovielibrary", "tvlibrary", "musiclibrary", "theater", "bundle",
        "fcpbundle", "logicx", "band", "photolibrary", "aplibrary", "migratedphotolibrary", "dvdmedia",
    ]
    /// Caminhos relativos à home que são de um app (biblioteca da Música/TV): fora inteiros.
    static let relativosExcluidos = ["Music/Music", "Music/iTunes", "Movies/TV", "Pictures/Photo Booth Library"]

    /// Dependência e build: pertencem a um projeto (a seção Projetos parados cuida).
    static let pastasDeProjeto: Set<String> = [
        "node_modules", "bower_components", "Pods", "Carthage", "DerivedData", "vendor", "venv",
        "__pycache__", "site-packages", "target", "build", "Build", "SourcePackages", "intermediates", "dist", "out",
    ]

    static func pastaExcluida(_ url: URL) -> Bool {
        let n = url.lastPathComponent
        if n.hasPrefix(".") || pastasExcluidas.contains(n) || pastasDeProjeto.contains(n) { return true }
        if extensoesExcluidas.contains(url.pathExtension.lowercased()) { return true }
        let home = PoliticaSeguranca.home
        return relativosExcluidos.contains { url.path == "\(home)/\($0)" }
    }

    /// Algum componente (abaixo da home) é excluído?
    static func dentroDeExcluida(_ url: URL) -> Bool {
        let home = PoliticaSeguranca.home
        let c = url.standardizedFileURL.path
        guard c.hasPrefix(home + "/") else { return true }
        var atual = URL(fileURLWithPath: home, isDirectory: true)
        for p in c.dropFirst(home.count + 1).split(separator: "/").dropLast() {
            atual.appendPathComponent(String(p))
            if pastaExcluida(atual) { return true }
        }
        return false
    }

    /// Só no iCloud (o Mac tem só o "fantasma"): ler baixaria o arquivo.
    static func semDadosLocais(_ caminho: String) -> Bool {
        var st = stat()
        guard lstat(caminho, &st) == 0 else { return true }
        return st.st_flags & UInt32(SF_DATALESS) != 0
    }

    /// O sistema recusaria tirar (trava do arquivo ou da pasta).
    static func travado(_ caminho: String) -> Bool {
        var st = stat()
        guard lstat(caminho, &st) == 0 else { return true }
        let travas = UInt32(UF_IMMUTABLE | SF_IMMUTABLE | UF_APPEND | SF_APPEND)
        if st.st_flags & travas != 0 { return true }
        var sp = stat()
        let mae = (caminho as NSString).deletingLastPathComponent
        guard lstat(mae, &sp) == 0 else { return true }
        return sp.st_flags & travas != 0 || access(mae, W_OK) != 0
    }

    /// Pode ir para a Lixeira? Arquivo comum (não link, não pasta), dentro de uma das raízes
    /// permitidas para este acesso, fora de biblioteca/pacote/projeto, com dados no Mac e sem trava.
    /// Chamada na varredura, na confirmação e de novo imediatamente antes de mover.
    static func motivoRecusa(_ url: URL, acesso: AcessoVarredura) -> String? {
        let u = url.standardizedFileURL
        let c = u.path
        guard raizes(acesso: acesso).contains(where: { c.hasPrefix($0.path + "/") }) else {
            let home = PoliticaSeguranca.home
            if pastasRaiz.contains(where: { c.hasPrefix("\(home)/\($0)/") }) {
                return "Pede permissão do macOS (sem Acesso Total ao Disco)."
            }
            return "Fora das pastas permitidas (Documentos, Mesa, Downloads, Filmes, Música, Imagens)."
        }
        if c.contains("/Library/") { return "Dentro de uma Library." }
        if dentroDeExcluida(u) { return "Dentro de biblioteca, pacote ou pasta de projeto." }
        guard LocaisProtegidos.podeLer(u, acesso: acesso) else { return "Pede permissão do macOS." }
        guard let a = try? FileManager.default.attributesOfItem(atPath: c),
              let tipo = a[.type] as? FileAttributeType else { return "Não existe mais." }
        guard tipo == .typeRegular else { return "Não é um arquivo comum." }
        if semDadosLocais(c) { return "Está só no iCloud." }
        if travado(c) { return "Travado pelo sistema." }
        return nil
    }
}
