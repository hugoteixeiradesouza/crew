import Foundation

// Envio para a Lixeira de projetos parados, arquivos grandes e duplicados. Cada caminho passa
// pela checagem da sua seção imediatamente antes de sair; sempre `trashItem`, nunca `removeItem`.

struct AlvoLixeira: Sendable, Hashable {
    let nome: String
    let caminho: String
    let bytes: Int64
}

struct ResultadoMover: Sendable {
    let movidos: [AlvoLixeira]
    let falhas: [Retirado]
    let quando: Date
    var bytes: Int64 { movidos.reduce(0) { $0 + $1.bytes } }
}

enum LixeiraCaminhos {
    /// `checar` devolve o motivo para NÃO mover (nil = pode).
    static func mover(_ alvos: [AlvoLixeira], checar: (AlvoLixeira) -> String?) -> ResultadoMover {
        var movidos: [AlvoLixeira] = []
        var falhas: [Retirado] = []
        for a in alvos {
            if let m = checar(a) {
                falhas.append(Retirado(nome: a.nome, motivo: m))
                continue
            }
            do {
                try FileManager.default.trashItem(at: URL(fileURLWithPath: a.caminho), resultingItemURL: nil)
                movidos.append(a)
            } catch {
                falhas.append(Retirado(nome: a.nome, motivo: error.localizedDescription))
            }
        }
        return ResultadoMover(movidos: movidos, falhas: falhas, quando: Date())
    }
}
