import Foundation

// Revalidação e envio para a Lixeira.
// Sempre `trashItem`, nunca `removeItem`. Cada caminho passa de novo pela política
// imediatamente antes de sair.

struct AmostraVolume: Sendable, Equatable {
    let total: Int64
    let livre: Int64
    var usado: Int64 { max(0, total - livre) }
}

enum LeitorVolume {
    /// Volume da home. `livre` é o número que o Finder mostra (inclui o que o macOS libera sozinho).
    static func ler() -> AmostraVolume? {
        let url = FileManager.default.homeDirectoryForCurrentUser
        guard let v = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]),
              let t = v.volumeTotalCapacity, let l = v.volumeAvailableCapacityForImportantUsage else { return nil }
        return AmostraVolume(total: Int64(t), livre: l)
    }
}

struct Retirado: Sendable, Hashable {
    let nome: String
    let motivo: String
}

struct ResultadoLimpeza: Sendable {
    let movidos: [ItemLimpeza]
    let falhas: [Retirado]
    let retirados: [Retirado]
    let antes: AmostraVolume?
    let depois: AmostraVolume?
    let quando: Date

    var bytesMovidos: Int64 { movidos.reduce(0) { $0 + $1.bytes } }

    /// Só o delta medido do volume pode ser chamado de "voltou". Mover para a Lixeira não
    /// libera nada até a Lixeira ser esvaziada; abaixo de 64 MB é ruído de outros processos.
    var bytesVoltaram: Int64? {
        guard let antes, let depois else { return nil }
        let d = depois.livre - antes.livre
        return d >= 64 * 1024 * 1024 ? d : nil
    }
}

enum Lixeira {
    /// Confere cada item de novo (existe, não virou link, a política ainda permite).
    /// O que mudou desde a varredura sai da lista.
    static func revalidar(_ itens: [ItemLimpeza], acesso: AcessoVarredura) -> (validos: [ItemLimpeza], retirados: [Retirado]) {
        var validos: [ItemLimpeza] = []
        var retirados: [Retirado] = []
        for var item in itens {
            let ok = item.caminhos.filter { Varredura.oferecivel(URL(fileURLWithPath: $0), acesso: acesso) }
            if ok.isEmpty {
                retirados.append(Retirado(nome: item.nome, motivo: "Mudou desde a varredura (sumiu ou deixou de ser permitido)."))
                continue
            }
            if ok.count != item.caminhos.count {
                // Parte dos caminhos saiu: o tamanho guardado não vale mais por inteiro.
                let fracao = Double(ok.count) / Double(item.caminhos.count)
                item.bytes = Int64(Double(item.bytes) * fracao)
                item.caminhos = ok
            }
            validos.append(item)
        }
        return (validos, retirados)
    }

    static func mover(_ itens: [ItemLimpeza], acesso: AcessoVarredura) -> ResultadoLimpeza {
        let antes = LeitorVolume.ler()
        var movidos: [ItemLimpeza] = []
        var falhas: [Retirado] = []
        var retirados: [Retirado] = []
        for item in itens {
            var algum = false
            for c in item.caminhos {
                let url = URL(fileURLWithPath: c)
                // Última checagem, imediatamente antes de mover.
                guard Varredura.oferecivel(url, acesso: acesso) else {
                    retirados.append(Retirado(nome: item.nome, motivo: "Mudou desde a confirmação."))
                    continue
                }
                if PoliticaSeguranca.deveSoEsvaziar(url) {
                    let (moveu, erro) = esvaziar(url)
                    if moveu { algum = true }
                    if let erro { falhas.append(Retirado(nome: item.nome, motivo: erro)) }
                } else {
                    do {
                        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                        algum = true
                    } catch {
                        falhas.append(Retirado(nome: item.nome, motivo: error.localizedDescription))
                    }
                }
            }
            if algum { movidos.append(item) }
        }
        return ResultadoLimpeza(movidos: movidos, falhas: falhas, retirados: retirados,
                                antes: antes, depois: LeitorVolume.ler(), quando: Date())
    }

    /// Move o conteúdo e deixa a pasta. Subpasta que também é "só esvaziar" é esvaziada, não movida.
    private static func esvaziar(_ dir: URL) -> (Bool, String?) {
        guard let filhos = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil,
                                                                        options: [.skipsHiddenFiles]) else {
            return (false, "Não deu para ler a pasta.")
        }
        var moveu = false
        var erro: String?
        for f in filhos {
            if PoliticaSeguranca.deveSoEsvaziar(f) {
                let (m, e) = esvaziar(f)
                moveu = moveu || m
                erro = erro ?? e
                continue
            }
            guard PoliticaSeguranca.podeOferecer(f) else { continue }
            do {
                try FileManager.default.trashItem(at: f, resultingItemURL: nil)
                moveu = true
            } catch {
                erro = erro ?? error.localizedDescription
            }
        }
        return (moveu, erro)
    }
}
