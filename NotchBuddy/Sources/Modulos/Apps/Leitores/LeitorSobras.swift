import Foundation

// Só lista filhos diretos das raízes (nunca desce). Sem Acesso Total ao Disco, não abre
// Contêineres nem Contêineres de grupo (o macOS pediria permissão) — mesma regra do Disco
// (`LocaisProtegidos`). Tudo fora da main.

enum LeitorSobras {
    /// O pacote (se `incluirPacote`) e as sobras do app, sem medir.
    static func doApp(_ app: AlvoApp, instalados: [AlvoApp], acesso: AcessoVarredura, incluirPacote: Bool) -> [Sobra] {
        let fm = FileManager.default
        var res: [Sobra] = []
        var vistos = Set<String>()
        if incluirPacote, PoliticaDesinstalar.podeSair(app.caminho) {
            vistos.insert(app.caminho)
            res.append(Sobra(caminho: app.caminho, categoria: .app, motivo: .pacote, bytes: nil,
                             precisaAdmin: PoliticaDesinstalar.precisaAdmin(app.caminho)))
        }
        for raiz in PoliticaDesinstalar.raizesSobras() {
            if Task.isCancelled { break }
            guard LocaisProtegidos.podeLer(URL(fileURLWithPath: raiz.caminho), acesso: acesso),
                  let nomes = try? fm.contentsOfDirectory(atPath: raiz.caminho) else { continue }
            for nome in nomes where !nome.hasPrefix(".") {
                guard let m = PoliticaDesinstalar.motivo(nome: nome, categoria: raiz.categoria, app: app) else { continue }
                let c = raiz.caminho + "/" + nome
                guard !vistos.contains(c), PoliticaDesinstalar.podeSair(c) else { continue }
                // Dividida com outro app que fica: não sai.
                if PoliticaDesinstalar.outroDono(nome: nome, categoria: raiz.categoria, app: app, instalados: instalados) != nil {
                    continue
                }
                vistos.insert(c)
                res.append(Sobra(caminho: c, categoria: raiz.categoria, motivo: m, bytes: nil,
                                 precisaAdmin: PoliticaDesinstalar.precisaAdmin(c)))
            }
        }
        return res
    }

    /// Sobras de apps que não estão mais instalados. Vazio se a visão do que está instalado
    /// parecer quebrada (volume fora, /Applications sem leitura).
    static func orfas(acesso: AcessoVarredura, agora: Date = Date()) -> [Sobra] {
        let (apps, legiveis) = LeitorApps.indice()
        let ids = Set(apps.values.compactMap { $0.bundleID?.lowercased() })
        let indice = PoliticaOrfas.Indice(ids: ids, raizesLegiveis: legiveis)
        guard indice.completo else { return [] }
        let fm = FileManager.default
        var res: [Sobra] = []
        for raiz in PoliticaOrfas.raizes() {
            if Task.isCancelled { break }
            guard LocaisProtegidos.podeLer(URL(fileURLWithPath: raiz.caminho), acesso: acesso),
                  let nomes = try? fm.contentsOfDirectory(atPath: raiz.caminho) else { continue }
            for nome in nomes where !nome.hasPrefix(".") {
                let c = raiz.caminho + "/" + nome
                guard let id = PoliticaOrfas.bundleID(nome: nome, categoria: raiz.categoria, caminho: c),
                      PoliticaOrfas.orfa(bundleID: id, indice: indice) else { continue }
                let mod = (try? URL(fileURLWithPath: c).resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                guard PoliticaOrfas.parado(mod, agora: agora), PoliticaDesinstalar.podeSair(c) else { continue }
                res.append(Sobra(caminho: c, categoria: raiz.categoria, motivo: .bundleID, bytes: nil,
                                 precisaAdmin: PoliticaDesinstalar.precisaAdmin(c),
                                 dono: PoliticaOrfas.nomeAmigavel(bundleID: id, caminho: c)))
            }
        }
        return res
    }

    /// Mede com `du` (lotes, fora da main). O que não deu para ler fica sem tamanho.
    static func medir(_ s: [Sobra]) async -> [Sobra] {
        let t = await Tamanhos.medir(s.map { URL(fileURLWithPath: $0.caminho) })
        return s.map { var x = $0; x.bytes = t[URL(fileURLWithPath: $0.caminho).standardizedFileURL.path]; return x }
    }
}
