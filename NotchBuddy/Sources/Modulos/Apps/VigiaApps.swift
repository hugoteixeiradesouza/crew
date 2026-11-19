import SwiftUI
import CoreServices

// Aviso de app apagado. Com o ajuste ligado (padrão), um FSEventStream do macOS em
// /Applications e ~/Applications — no próprio Crew, sem LaunchAgent. É evento do kernel, sem
// timer: sem nada mudando nas pastas de apps, nada roda. O macOS junta os avisos (no máximo um a
// cada 2 s); mudança no miolo de um pacote (atualização, abertura) é ignorada sem ler o disco.
//
// Quando um .app some: espera 10 s e confere se o mesmo bundle id voltou ou se há outra cópia
// viva (atualização, troca de lugar). Se sumiu mesmo e deixou sobras, publica na barra da ilha
// "<App> foi apagado — <X> de sobras" (some em 10 s) e guarda em "apagados recentemente".

@MainActor
final class VigiaApps {
    static let shared = VigiaApps()

    static var ligada: Bool {
        get { Ajustes.bool("apps", "vigia", padrao: true) }
        set { Ajustes.definir("apps", "vigia", newValue); aplicar() }
    }

    /// Liga/desliga conforme o ajuste e o módulo.
    static func aplicar(moduloLigado: Bool = true) {
        if moduloLigado && ligada { shared.ligar() } else { shared.desligar() }
    }

    private var stream: FSEventStreamRef?
    private let fila = DispatchQueue(label: "crew.apps.vigia", qos: .utility)
    private var indice: [String: AlvoApp] = [:]
    private var pronto = false
    private var lendo = false
    private var deNovo = false
    /// Bundle ids (minúsculos) que o próprio Crew acabou de desinstalar: não avisa.
    private var peloCrew: [String: Date] = [:]
    private let log = Log.de("apps")

    func ligar() {
        guard stream == nil else { return }
        let raizes = PoliticaDesinstalar.raizesApps().filter { FileManager.default.fileExists(atPath: $0) }
        guard !raizes.isEmpty else { return }
        var ctx = FSEventStreamContext(version: 0, info: nil, retain: nil, release: nil, copyDescription: nil)
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes)
        guard let s = FSEventStreamCreate(kCFAllocatorDefault, VigiaApps.aviso, &ctx, raizes as CFArray,
                                          FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 2, flags) else { return }
        FSEventStreamSetDispatchQueue(s, fila)
        FSEventStreamStart(s)
        stream = s
        pronto = false
        reindexar()
        log.info("vigia de apps ligada: \(raizes.joined(separator: ", "), privacy: .public)")
    }

    func desligar() {
        guard let s = stream else { return }
        FSEventStreamStop(s)
        FSEventStreamInvalidate(s)
        FSEventStreamRelease(s)
        stream = nil
        indice = [:]
        pronto = false
        Arbitro.shared.retirar("apps.apagado")
    }

    func removidoPeloCrew(_ bundleID: String) {
        peloCrew[bundleID.lowercased()] = Date()
    }

    /// Roda na fila da vigia (fora da main): filtra o caminho e só então passa o recado.
    nonisolated private static let aviso: FSEventStreamCallback = { _, _, n, caminhos, _, _ in
        let lista = Unmanaged<CFArray>.fromOpaque(caminhos).takeUnretainedValue() as? [String] ?? []
        let raizes = PoliticaDesinstalar.raizesApps()
        guard lista.prefix(n).contains(where: { PoliticaApagado.relevante($0, raizes: raizes) }) else { return }
        DispatchQueue.main.async { MainActor.assumeIsolated { VigiaApps.shared.reindexar() } }
    }

    private func reindexar() {
        if lendo { deNovo = true; return }
        lendo = true
        Task.detached(priority: .utility) {
            let (apps, ok) = LeitorApps.indice()
            await MainActor.run { VigiaApps.shared.indexado(apps, legivel: ok) }
        }
    }

    private func indexado(_ novo: [String: AlvoApp], legivel: Bool) {
        lendo = false
        guard stream != nil else { return }
        // Leitura capenga (volume fora, sem permissão) não vale como "sumiu".
        if legivel {
            if pronto {
                for app in PoliticaApagado.sumiram(antes: indice, agora: novo) where app.bundleID != nil {
                    log.info("sumiu: \(app.caminho, privacy: .public); confere em \(Int(PoliticaApagado.espera)) s")
                    DispatchQueue.main.asyncAfter(deadline: .now() + PoliticaApagado.espera) {
                        MainActor.assumeIsolated { VigiaApps.shared.conferir(app) }
                    }
                }
            }
            indice = novo
            pronto = true
        }
        if deNovo { deNovo = false; reindexar() }
    }

    /// Depois da espera: voltou? outra cópia? Se não, procura as sobras e avisa.
    private func conferir(_ app: AlvoApp) {
        guard stream != nil else { return }
        let id = (app.bundleID ?? "").lowercased()
        peloCrew = peloCrew.filter { Date().timeIntervalSince($0.value) < 300 }
        let peloCrew = self.peloCrew[id] != nil
        let acesso = AcessoVarredura.atual()
        Task.detached(priority: .utility) {
            let (apps, ok) = LeitorApps.indice()
            let ids = Set(apps.values.compactMap { $0.bundleID?.lowercased() })
            let outra = PoliticaApagado.outraCopia(app)
            guard ok, PoliticaApagado.deveAvisar(app, idsInstalados: ids, outraCopia: outra, removidoPeloCrew: peloCrew) else {
                await MainActor.run { VigiaApps.shared.log.info("não avisa: \(app.caminho, privacy: .public) (voltou, outra cópia ou removido pelo Crew)") }
                return
            }
            let sobras = await LeitorSobras.medir(LeitorSobras.doApp(app, instalados: Array(apps.values), acesso: acesso, incluirPacote: false))
            await MainActor.run { VigiaApps.shared.avisar(app, sobras) }
        }
    }

    private func avisar(_ app: AlvoApp, _ sobras: [Sobra]) {
        guard stream != nil, let id = app.bundleID else { return }
        // Sem sobras não há o que revisar: não interrompe.
        guard !sobras.isEmpty else {
            log.info("apagado sem sobras: \(app.nome, privacy: .public)")
            return
        }
        AppsServico.shared.registrar(Apagado(nome: app.nome, bundleID: id, caminho: app.caminho, quando: Date()), sobras: sobras)
        let total = sobras.reduce(Int64(0)) { $0 + ($1.bytes ?? 0) }
        let texto = "\(app.nome) foi apagado — \(FormatoApps.bytes(total)) de sobras"
        log.info("\(texto, privacy: .public)")
        Arbitro.shared.publicar(Sinal(id: "apps.apagado", lugar: .barra, prioridade: .alerta, duracao: 10,
                                      clicavel: true, conteudo: AnyView(AvisoApagado(texto: texto))))
        NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.surprised)
    }
}

/// A linha do aviso na barra da ilha fechada. Clique abre a página do módulo na Central.
struct AvisoApagado: View {
    let texto: String

    var body: some View {
        AvisoBarra(icone: "trash", texto: texto, cor: Color(hex: "#F5A524"))
            .contentShape(Rectangle())
            .onTapGesture { Central.abrir(modulo: "apps") }
    }
}

enum FormatoApps {
    static func bytes(_ b: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: b, countStyle: .file)
    }

    static func data(_ d: Date?) -> String {
        guard let d else { return "—" }
        let dias = Int(Date().timeIntervalSince(d) / 86_400)
        if dias < 1 { return "hoje" }
        if dias == 1 { return "ontem" }
        if dias < 60 { return "há \(dias) dias" }
        if dias < 730 { return "há \(dias / 30) meses" }
        return "há \(dias / 365) anos"
    }

    static func ha(_ d: Date) -> String {
        let s = Int(Date().timeIntervalSince(d))
        if s < 60 { return "agora" }
        if s < 3600 { return "há \(s / 60) min" }
        if s < 86_400 { return "há \(s / 3600) h" }
        return "há \(s / 86_400) dias"
    }
}
