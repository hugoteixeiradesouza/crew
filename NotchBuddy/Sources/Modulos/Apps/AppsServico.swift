import Foundation
import Observation

// Dados do módulo Apps. Nada roda sozinho: a lista de apps é lida quando a página abre, as
// sobras quando o Hugo escolhe um app, as órfãs no botão. Tudo fora da main; mover para a
// Lixeira só com o clique de confirmação.

/// App que sumiu de /Applications (visto pela vigia) e deixou sobras.
struct Apagado: Codable, Sendable, Hashable, Identifiable {
    let nome: String
    let bundleID: String
    let caminho: String
    let quando: Date
    var id: String { bundleID + "|" + caminho }
    var alvo: AlvoApp { AlvoApp(nome: nome, bundleID: bundleID, caminho: caminho) }
}

@Observable @MainActor
final class AppsServico {
    static let shared = AppsServico()

    enum Estado: Equatable { case nunca, lendo, pronto(Date) }
    enum Ordem: String, CaseIterable { case nome = "Nome", tamanho = "Tamanho", uso = "Último uso" }
    enum Contexto: Equatable {
        case app(AppInstalado)
        case apagado(String)
        case orfas
    }
    struct Confirmacao {
        let contexto: Contexto
        let titulo: String
        let itens: [Sobra]
        let appAberto: Bool
        var total: Int64 { itens.reduce(0) { $0 + ($1.bytes ?? 0) } }
    }

    var acesso: AcessoVarredura = .limitado

    // Instalados
    var apps: [AppInstalado] = []
    var estadoLista: Estado = .nunca
    var filtro = ""
    var ordem: Ordem = .nome

    // App escolhido
    var escolhido: AppInstalado?
    var sobras: [Sobra] = []
    var lendoSobras = false

    /// Marcação, por caminho (vale para as três listas).
    var marcados: Set<String> = []

    // Apagados recentemente (vigia)
    var apagados: [Apagado] = []
    var sobrasApagado: [String: [Sobra]] = [:]
    var lendoApagados = false

    // Órfãs
    var orfas: [Sobra] = []
    var estadoOrfas: Estado = .nunca

    // Confirmação e resultado
    var confirmacao: Confirmacao?
    var foraNaRevalidacao: [Ficou] = []
    var preparando = false
    var removendo = false
    var etapa: String?
    var ultimo: ResultadoRemocao?

    @ObservationIgnored private var tarefaSobras: Task<Void, Never>?
    @ObservationIgnored private var exemplo = false

    private init() {
        apagados = Self.carregarApagados()
    }

    // MARK: Página

    /// A página da Central abriu: lê o que estiver velho.
    func paginaAbriu() {
        guard !exemplo else { return }
        acesso = AcessoVarredura.atual()
        if case .pronto(let q) = estadoLista, Date().timeIntervalSince(q) < 120 {} else if estadoLista != .lendo {
            listarApps()
        }
        let semSobras = apagados.filter { sobrasApagado[$0.id] == nil }
        if !semSobras.isEmpty { lerApagados(semSobras) }
    }

    var appsVisiveis: [AppInstalado] {
        let f = filtro.trimmingCharacters(in: .whitespaces)
        let lista = f.isEmpty ? apps : apps.filter { $0.nome.localizedCaseInsensitiveContains(f) || ($0.bundleID ?? "").localizedCaseInsensitiveContains(f) }
        switch ordem {
        case .nome: return lista
        case .tamanho: return lista.sorted { ($0.bytes ?? 0) > ($1.bytes ?? 0) }
        case .uso: return lista.sorted { ($0.ultimoUso ?? .distantPast) > ($1.ultimoUso ?? .distantPast) }
        }
    }

    func listarApps() {
        estadoLista = .lendo
        Task.detached(priority: .userInitiated) {
            let lista = LeitorApps.listar()
            await MainActor.run {
                let s = AppsServico.shared
                s.apps = lista
                s.estadoLista = .pronto(Date())
            }
            // Sem tamanho no Spotlight: `du` (fora da main, poucos ao mesmo tempo).
            let faltam = lista.filter { $0.bytes == nil }.map { URL(fileURLWithPath: $0.caminho) }
            guard !faltam.isEmpty else { return }
            let t = await Tamanhos.medir(faltam)
            await MainActor.run {
                let s = AppsServico.shared
                s.apps = s.apps.map { a in
                    var b = a
                    if b.bytes == nil { b.bytes = t[URL(fileURLWithPath: a.caminho).standardizedFileURL.path] }
                    return b
                }
            }
        }
    }

    // MARK: Desinstalar

    func escolher(_ app: AppInstalado?) {
        tarefaSobras?.cancel()
        confirmacao = nil
        escolhido = app
        sobras = []
        guard let app else { lendoSobras = false; return }
        lendoSobras = true
        let acesso = self.acesso
        tarefaSobras = Task.detached(priority: .userInitiated) {
            let outros = Array(LeitorApps.indice().apps.values)
            var achadas = LeitorSobras.doApp(app.alvo, instalados: outros, acesso: acesso, incluirPacote: true)
            achadas = await LeitorSobras.medir(achadas)
            if let i = achadas.firstIndex(where: { $0.categoria == .app }), achadas[i].bytes == nil {
                achadas[i].bytes = app.bytes
            }
            let final = achadas
            await MainActor.run {
                let s = AppsServico.shared
                guard s.escolhido?.id == app.id, !Task.isCancelled else { return }
                s.sobras = final
                s.lendoSobras = false
                s.marcarPadrao(final)
            }
        }
    }

    /// Bundle id e grupo marcados; por nome, e o que é do administrador, desmarcados.
    private func marcarPadrao(_ l: [Sobra]) {
        for s in l {
            if s.motivo.marcadoPorPadrao && !s.precisaAdmin { marcados.insert(s.id) } else { marcados.remove(s.id) }
        }
    }

    func alternar(_ id: String) {
        if marcados.contains(id) { marcados.remove(id) } else { marcados.insert(id) }
    }

    private func itens(_ c: Contexto) -> [Sobra] {
        switch c {
        case .app: return sobras
        case .apagado(let id): return sobrasApagado[id] ?? []
        case .orfas: return orfas
        }
    }

    func marcadas(_ c: Contexto) -> [Sobra] { itens(c).filter { marcados.contains($0.id) } }

    /// O pacote do app escolhido é do administrador: o Crew não consegue tirar.
    var pacoteBloqueado: Bool { sobras.first { $0.categoria == .app }?.precisaAdmin ?? false }

    /// Abre a confirmação: confere tudo de novo (fora da main) e mostra só o que ainda vale.
    func prepararConfirmacao(_ c: Contexto) {
        guard !preparando, !removendo else { return }
        var alvo = marcadas(c)
        // Desinstalar sempre leva o pacote (sem ele, só as sobras sairiam com o app instalado).
        if case .app = c {
            guard let p = sobras.first(where: { $0.categoria == .app }), !p.precisaAdmin else { return }
            if !alvo.contains(p) { alvo.insert(p, at: 0) }
        }
        guard !alvo.isEmpty else { return }
        preparando = true
        Task.detached(priority: .userInitiated) {
            let r = Remocao.revalidar(alvo)
            await MainActor.run {
                let s = AppsServico.shared
                s.preparando = false
                s.foraNaRevalidacao = r.fora
                guard !r.validos.isEmpty else { s.confirmacao = nil; return }
                var titulo = "Sobras"
                var aberto = false
                switch c {
                case .app(let a):
                    titulo = "Desinstalar \(a.nome)"
                    aberto = Remocao.aberto(a.alvo)
                case .apagado(let id):
                    titulo = "Sobras de " + (s.apagados.first { $0.id == id }?.nome ?? "app apagado")
                case .orfas:
                    titulo = "Sobras de apps já apagados"
                }
                s.confirmacao = Confirmacao(contexto: c, titulo: titulo, itens: r.validos, appAberto: aberto)
            }
        }
    }

    func cancelarConfirmacao() {
        confirmacao = nil
        foraNaRevalidacao = []
    }

    /// Clique explícito do Hugo em "Mover para a Lixeira".
    func confirmar() {
        guard let conf = confirmacao, !removendo else { return }
        removendo = true
        Task { @MainActor in
            if case .app(let a) = conf.contexto {
                if Remocao.aberto(a.alvo) {
                    etapa = "Pedindo para \(a.nome) fechar…"
                    let fechou = await Remocao.fechar(a.alvo)
                    if !fechou {
                        etapa = nil
                        removendo = false
                        confirmacao = nil
                        ultimo = ResultadoRemocao(titulo: conf.titulo, movidos: [],
                                                  ficaram: [Ficou(caminho: a.caminho, motivo: "\(a.nome) não fechou em 3 s (pode ter um documento sem salvar). Nada foi removido: feche o app e tente de novo.")],
                                                  quando: Date())
                        return
                    }
                }
                if let id = a.bundleID { VigiaApps.shared.removidoPeloCrew(id) }
            }
            etapa = "Movendo para a Lixeira…"
            let itens = conf.itens, titulo = conf.titulo
            let r = await Task.detached(priority: .userInitiated) { Remocao.mover(itens, titulo: titulo) }.value
            depoisDeMover(r, conf.contexto)
        }
    }

    private func depoisDeMover(_ r: ResultadoRemocao, _ c: Contexto) {
        etapa = nil
        removendo = false
        confirmacao = nil
        ultimo = r
        let foram = Set(r.movidos.map(\.id))
        marcados.subtract(foram)
        sobras.removeAll { foram.contains($0.id) }
        orfas.removeAll { foram.contains($0.id) }
        for (k, v) in sobrasApagado { sobrasApagado[k] = v.filter { !foram.contains($0.id) } }
        switch c {
        case .app(let a):
            if foram.contains(a.caminho) {
                apps.removeAll { $0.id == a.id }
                escolhido = nil
                sobras = []
            }
        case .apagado(let id):
            if sobrasApagado[id]?.isEmpty ?? true { esquecer(id) }
        case .orfas: break
        }
        Log.de("apps").info("Lixeira: \(r.movidos.count) itens, \(r.bytes) bytes; ficaram \(r.ficaram.count)")
    }

    // MARK: Órfãs

    func procurarOrfas() {
        guard estadoOrfas != .lendo else { return }
        acesso = AcessoVarredura.atual()
        let acesso = self.acesso
        estadoOrfas = .lendo
        Task.detached(priority: .utility) {
            let achadas = await LeitorSobras.medir(LeitorSobras.orfas(acesso: acesso))
                .sorted { ($0.bytes ?? 0) > ($1.bytes ?? 0) }
            await MainActor.run {
                let s = AppsServico.shared
                s.orfas = achadas
                s.estadoOrfas = .pronto(Date())
                // App data que não volta: o Hugo marca uma por uma.
                for o in achadas { s.marcados.remove(o.id) }
            }
        }
    }

    // MARK: Apagados recentemente

    /// A vigia achou um app apagado com sobras.
    func registrar(_ a: Apagado, sobras: [Sobra]) {
        apagados.removeAll { $0.id == a.id }
        apagados.insert(a, at: 0)
        apagados = Array(apagados.prefix(PoliticaApagado.maxRecentes))
        sobrasApagado[a.id] = sobras
        marcarPadrao(sobras)
        salvarApagados()
    }

    func esquecer(_ id: String) {
        apagados.removeAll { $0.id == id }
        sobrasApagado[id] = nil
        salvarApagados()
    }

    /// Relê as sobras dos apagados guardados (ao abrir a página). Se o app voltou, sai da lista.
    private func lerApagados(_ lista: [Apagado]) {
        guard !lendoApagados else { return }
        lendoApagados = true
        let acesso = self.acesso
        Task.detached(priority: .utility) {
            let instalados = Array(LeitorApps.indice().apps.values)
            let ids = Set(instalados.compactMap { $0.bundleID?.lowercased() })
            var res: [String: [Sobra]] = [:]
            var voltaram: [String] = []
            for a in lista {
                if ids.contains(a.bundleID.lowercased()) { voltaram.append(a.id); continue }
                res[a.id] = await LeitorSobras.medir(LeitorSobras.doApp(a.alvo, instalados: instalados, acesso: acesso, incluirPacote: false))
            }
            let final = res, foram = voltaram
            await MainActor.run {
                let s = AppsServico.shared
                s.lendoApagados = false
                for id in foram { s.esquecer(id) }
                for (k, v) in final {
                    s.sobrasApagado[k] = v
                    s.marcarPadrao(v)
                    if v.isEmpty { s.esquecer(k) }
                }
            }
        }
    }

    private static let chaveApagados = Ajustes.chave("apps", "apagados")

    private static func carregarApagados() -> [Apagado] {
        guard let d = UserDefaults.standard.data(forKey: chaveApagados),
              let l = try? JSONDecoder().decode([Apagado].self, from: d) else { return [] }
        return l.filter { Date().timeIntervalSince($0.quando) < PoliticaApagado.validade }
    }

    private func salvarApagados() {
        guard !exemplo else { return }
        if let d = try? JSONEncoder().encode(apagados) { Gravar.padrao.set(d, forKey: Self.chaveApagados) }
    }

    // MARK: Capturas

    /// Só para o modo de capturas: dados de exemplo, nada lido nem movido.
    func exemploParaCaptura(confirmar: Bool) {
        exemplo = true
        let h = PoliticaDesinstalar.home
        let mb: Int64 = 1_000_000
        acesso = .limitado
        apps = [
            AppInstalado(nome: "Figma", caminho: "/Applications/Figma.app", bundleID: "com.figma.Desktop", bytes: 512 * mb, ultimoUso: Date().addingTimeInterval(-86_400 * 3)),
            AppInstalado(nome: "Raycast", caminho: "/Applications/Raycast.app", bundleID: "com.raycast.macos", bytes: 310 * mb, ultimoUso: Date().addingTimeInterval(-3600)),
            AppInstalado(nome: "Zoom", caminho: "/Applications/zoom.us.app", bundleID: "us.zoom.xos", bytes: 280 * mb, ultimoUso: Date().addingTimeInterval(-86_400 * 61)),
        ]
        estadoLista = .pronto(Date())
        let z = apps[2]
        escolhido = z
        sobras = [
            Sobra(caminho: z.caminho, categoria: .app, motivo: .pacote, bytes: z.bytes, precisaAdmin: false),
            Sobra(caminho: "\(h)/Library/Application Support/zoom.us", categoria: .applicationSupport, motivo: .nome, bytes: 96 * mb, precisaAdmin: false),
            Sobra(caminho: "\(h)/Library/Caches/us.zoom.xos", categoria: .caches, motivo: .bundleID, bytes: 41 * mb, precisaAdmin: false),
            Sobra(caminho: "\(h)/Library/Preferences/us.zoom.xos.plist", categoria: .preferencias, motivo: .bundleID, bytes: 12_000, precisaAdmin: false),
            Sobra(caminho: "\(h)/Library/HTTPStorages/us.zoom.xos", categoria: .httpStorages, motivo: .bundleID, bytes: 220_000, precisaAdmin: false),
            Sobra(caminho: "/Library/LaunchDaemons/us.zoom.ZoomDaemon.plist", categoria: .launchDaemons, motivo: .bundleID, bytes: 4_000, precisaAdmin: true),
        ]
        marcados = []
        marcarPadrao(sobras)
        let ap = Apagado(nome: "Notion", bundleID: "notion.id", caminho: "/Applications/Notion.app", quando: Date().addingTimeInterval(-1800))
        apagados = [ap]
        sobrasApagado[ap.id] = [
            Sobra(caminho: "\(h)/Library/Application Support/Notion", categoria: .applicationSupport, motivo: .nome, bytes: 388 * mb, precisaAdmin: false),
            Sobra(caminho: "\(h)/Library/Caches/notion.id", categoria: .caches, motivo: .bundleID, bytes: 64 * mb, precisaAdmin: false),
        ]
        marcarPadrao(sobrasApagado[ap.id] ?? [])
        orfas = []
        estadoOrfas = .nunca
        confirmacao = confirmar ? Confirmacao(contexto: .app(z), titulo: "Desinstalar Zoom", itens: sobras.filter { marcados.contains($0.id) }, appAberto: true) : nil
    }
}
