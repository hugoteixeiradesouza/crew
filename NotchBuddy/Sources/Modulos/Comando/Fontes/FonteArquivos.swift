import AppKit

// Arquivos e pastas pelo índice do macOS (o mesmo do Spotlight), com `NSMetadataQuery`.
// A consulta só existe enquanto o painel está aberto: `parar()` solta tudo, e depois de
// juntar os resultados ela para sozinha (não fica vigiando o disco). Só nomes: o conteúdo dos
// arquivos não é lido, e nada sai do Mac.

struct ArquivoAchado: Equatable, Sendable {
    let caminho: String
    let nome: String
    let ehPasta: Bool
    let ultimoUso: Date?
}

@MainActor
final class FonteArquivos {
    /// Chamado quando a consulta do texto termina (com o texto que foi pedido).
    var chegou: ((_ texto: String, _ achados: [ArquivoAchado]) -> Void)?

    private var consulta: NSMetadataQuery?
    private var observador: NSObjectProtocol?
    private var textoAtual = ""
    private var espera: DispatchWorkItem?

    static let maximo = 40

    /// Procura por nome, depois de uma pausa curta (digitação rápida não dispara uma por letra).
    func procurar(_ texto: String) {
        espera?.cancel()
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 2 else { soltar(); return }
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.comecar(t) }
        }
        espera = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: item)
    }

    /// Painel fechou: nada mais roda.
    func parar() {
        espera?.cancel()
        espera = nil
        soltar()
    }

    private func soltar() {
        if let observador { NotificationCenter.default.removeObserver(observador) }
        observador = nil
        consulta?.stop()
        consulta = nil
    }

    private func comecar(_ texto: String) {
        soltar()
        textoAtual = texto
        let q = NSMetadataQuery()
        // Cada palavra digitada tem de estar no nome (em qualquer ordem), sem ligar para acento
        // ou maiúscula. Apps ficam de fora: têm fonte própria.
        let palavras = texto.split(separator: " ").map(String.init)
        var partes = palavras.map { NSPredicate(format: "kMDItemDisplayName CONTAINS[cd] %@", $0) }
        partes.append(NSPredicate(format: "kMDItemContentType != 'com.apple.application-bundle'"))
        q.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: partes)
        // Só a pasta do usuário (o iCloud Drive mora dentro dela). Misturar com os escopos do
        // iCloud não é aceito pelo NSMetadataQuery: lança exceção.
        q.searchScopes = [NSMetadataQueryUserHomeScope]
        q.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemLastUsedDateKey as String, ascending: false)]
        q.notificationBatchingInterval = 0.2
        observador = NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: q,
                                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.terminou() }
        }
        consulta = q
        q.start()
    }

    private func terminou() {
        guard let q = consulta else { return }
        q.disableUpdates()
        let casa = NSHomeDirectory()
        var achados: [ArquivoAchado] = []
        for i in 0..<min(q.resultCount, 400) {
            guard let item = q.result(at: i) as? NSMetadataItem,
                  let caminho = item.value(forAttribute: NSMetadataItemPathKey as String) as? String else { continue }
            // Fora o que ninguém procura pelo nome: a Biblioteca, pastas ocultas, dependências.
            let relativo = caminho.hasPrefix(casa) ? String(caminho.dropFirst(casa.count)) : caminho
            let noICloud = relativo.hasPrefix("/Library/Mobile Documents/")
            if (relativo.hasPrefix("/Library/") && !noICloud) || relativo.contains("/.") || relativo.contains("/node_modules/")
                || relativo.contains("/DerivedData/") { continue }
            let nome = (item.value(forAttribute: NSMetadataItemDisplayNameKey as String) as? String)
                ?? (caminho as NSString).lastPathComponent
            let tipo = item.value(forAttribute: NSMetadataItemContentTypeKey as String) as? String
            let uso = item.value(forAttribute: NSMetadataItemLastUsedDateKey as String) as? Date
            achados.append(ArquivoAchado(caminho: caminho, nome: nome, ehPasta: tipo == "public.folder", ultimoUso: uso))
            if achados.count >= Self.maximo { break }
        }
        let texto = textoAtual
        // Juntou: a consulta sai. Sem vigia, sem custo com o painel parado na tela.
        soltar()
        chegou?(texto, achados)
    }
}
