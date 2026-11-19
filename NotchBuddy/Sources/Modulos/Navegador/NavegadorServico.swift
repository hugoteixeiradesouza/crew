import SwiftUI
import AppKit
import WebKit
import Combine

// O navegador do Crew: páginas da web dentro do app, ao lado da sessão ou na janela inteira.
// As ideias vêm do Arc e do Zen — abas fixadas, um espaço por projeto, modo
// compacto, duas abas lado a lado, barra de endereço que também busca —, reimplementadas com
// o WebKit do macOS (WKWebView). Nenhum código deles; nenhuma dependência.
// O motor é o do Safari, não o Chromium: extensões do Chrome não existem aqui.
// Cookies e logins ficam no armazenamento do WebKit deste app, no Mac. Sem telemetria: a
// única rede é a das páginas que o Hugo abre, o ícone de cada site e — se ligadas — as buscas
// sugeridas do campo de endereço (`BuscasSugeridas`). O histórico fica só no Mac (`HistoricoNav`).

extension Notification.Name {
    /// Abrir um endereço no navegador do Crew (object: URL).
    static let abrirNoNavegador = Notification.Name("crew.abrirNoNavegador")
    /// Abrir o navegador ao lado de uma sessão (object: id da tarefa).
    static let navegadorDaSessao = Notification.Name("crew.navegadorDaSessao")
    /// O navegador da janela muda para um espaço (`object`: id do espaço).
    static let navegadorNoEspaco = Notification.Name("crew.navegadorNoEspaco")
    /// Abrir os arquivos do projeto ao lado de uma sessão (object: id da tarefa).
    static let arquivosDaSessao = Notification.Name("crew.arquivosDaSessao")
}

struct AbaNav: Identifiable, Codable, Hashable {
    var id = UUID().uuidString
    var url: String
    var titulo: String
    var fixada = false
}

extension EspacoNav {
    /// Espaço avulso de uma sessão (o navegador aberto ao lado dela).
    var daSessao: Bool { id.hasPrefix("sessao:") }
}

/// Um espaço: o "Geral" (o navegador da janela) ou o avulso de uma sessão. Espaços de projeto
/// de antes continuam guardados e alcançáveis pelo menu de abas.
struct EspacoNav: Identifiable, Codable, Hashable {
    /// Pasta raiz do projeto, ou "geral".
    var id: String
    var nome: String
    var cor: String
    var abas: [AbaNav] = []
    var ativa: String?
    /// Aba aberta ao lado da ativa (tela dividida).
    var lado: String?
    /// Armazenamento próprio do WebKit (id) — contas separadas das dos outros espaços. nil = o comum.
    var perfil: String?
    /// Perfil do Arc de onde o espaço veio ("Profile 2"), quando foi importado.
    var origem: String?
}

/// Uma aba carregada: a página de verdade (WKWebView) e o estado dela.
@MainActor
final class AbaViva: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    let id: String
    let web: WKWebView
    @Published var titulo = ""
    @Published var url: URL?
    @Published var progresso = 0.0
    @Published var carregando = false
    @Published var podeVoltar = false
    @Published var podeAvancar = false
    @Published var erro: String?
    private var vigias: Set<AnyCancellable> = []
    private var destinos: [ObjectIdentifier: URL] = [:]

    /// O mesmo que o Safari diz ser: sem isso muitos sites entregam a versão "navegador desconhecido".
    private static let agente = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    init(id: String, configuracao: WKWebViewConfiguration? = nil, armazem: WKWebsiteDataStore = .default()) {
        self.id = id
        let c = configuracao ?? {
            let c = WKWebViewConfiguration()
            c.websiteDataStore = armazem
            c.preferences.isElementFullscreenEnabled = true
            return c
        }()
        web = WebNav(frame: .zero, configuration: c)
        super.init()
        web.customUserAgent = Self.agente
        web.allowsBackForwardNavigationGestures = true
        web.allowsMagnification = true
        web.isInspectable = true
        web.underPageBackgroundColor = NSColor(Tema.fundo)
        web.navigationDelegate = self
        web.uiDelegate = self
        web.publisher(for: \.title).sink { [weak self] t in MainActor.assumeIsolated { self?.titulo = t ?? ""; self?.avisar() } }.store(in: &vigias)
        web.publisher(for: \.url).sink { [weak self] u in MainActor.assumeIsolated { self?.url = u; self?.avisar() } }.store(in: &vigias)
        web.publisher(for: \.estimatedProgress).sink { [weak self] p in MainActor.assumeIsolated { self?.progresso = p } }.store(in: &vigias)
        web.publisher(for: \.isLoading).sink { [weak self] v in MainActor.assumeIsolated { self?.carregando = v } }.store(in: &vigias)
        web.publisher(for: \.canGoBack).sink { [weak self] v in MainActor.assumeIsolated { self?.podeVoltar = v } }.store(in: &vigias)
        web.publisher(for: \.canGoForward).sink { [weak self] v in MainActor.assumeIsolated { self?.podeAvancar = v } }.store(in: &vigias)
    }

    /// O último endereço contado no histórico (para não contar duas vezes a mesma chegada).
    private var contado: String?

    private func avisar() {
        NavegadorServico.shared.atualizar(id, titulo: titulo, url: url?.absoluteString)
        guard let u = url?.absoluteString else { return }
        // Página que troca de endereço sem carregar de novo (apps de página única) também conta.
        if !web.isLoading, HistoricoRegras.normalizar(u) != contado { contar() }
        HistoricoNav.shared.intitulou(u, titulo: titulo)
    }

    private func contar() {
        guard let u = web.url?.absoluteString else { return }
        contado = HistoricoRegras.normalizar(u)
        HistoricoNav.shared.visitou(u, titulo: web.title ?? "")
    }

    // MARK: Navegação

    func webView(_ webView: WKWebView, decidePolicyFor acao: WKNavigationAction) async -> WKNavigationActionPolicy {
        if acao.shouldPerformDownload { return .download }
        guard let url = acao.request.url else { return .allow }
        // O que não é página (mailto:, tel:, link de app) vai para o macOS.
        let dePagina = ["http", "https", "about", "blob", "data", "file", "javascript"]
        if let esquema = url.scheme?.lowercased(), !dePagina.contains(esquema) {
            NSWorkspace.shared.open(url)
            return .cancel
        }
        // ⌘ clique num link: abre em aba nova, sem sair da atual.
        if acao.navigationType == .linkActivated, acao.modifierFlags.contains(.command) {
            NavegadorServico.shared.abrirEmAbaNova(url, juntoDe: id, emFoco: acao.modifierFlags.contains(.shift))
            return .cancel
        }
        return .allow
    }

    func webView(_ webView: WKWebView, decidePolicyFor resposta: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        resposta.canShowMIMEType ? .allow : .download
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { erro = nil }

    /// A página chegou (já depois dos redirecionamentos): entra no histórico.
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { contar() }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { falhou(error) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { falhou(error) }

    private func falhou(_ e: Error) {
        let ns = e as NSError
        // Cancelada pelo próprio Hugo, ou virou download: não é erro.
        if ns.code == NSURLErrorCancelled || (ns.domain == "WebKitErrorDomain" && ns.code == 102) { return }
        erro = ns.localizedDescription
    }

    // MARK: Downloads (para a pasta Downloads)

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { download.delegate = self }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { download.delegate = self }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
        let pasta = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let nome = suggestedFilename.isEmpty ? "download" : suggestedFilename
        var destino = pasta.appendingPathComponent(nome)
        var n = 2
        // Nunca escreve por cima de arquivo que já existe.
        while FileManager.default.fileExists(atPath: destino.path) {
            let base = (nome as NSString).deletingPathExtension, ext = (nome as NSString).pathExtension
            destino = pasta.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            n += 1
        }
        destinos[ObjectIdentifier(download)] = destino
        return destino
    }

    func downloadDidFinish(_ download: WKDownload) {
        if let d = destinos.removeValue(forKey: ObjectIdentifier(download)) {
            NavegadorServico.shared.baixou(d)
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        destinos[ObjectIdentifier(download)] = nil
        NavegadorServico.shared.aviso = AvisoNav(texto: "O download falhou: \(error.localizedDescription)", arquivo: nil)
    }

    // MARK: Janelas, diálogos e permissões da página

    /// Link que abriria janela nova (target=_blank, window.open): vira aba nova.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        NavegadorServico.shared.abaParaJanelaNova(configuration, juntoDe: id)
    }

    func webViewDidClose(_ webView: WKWebView) { NavegadorServico.shared.fechar(id) }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async {
        let a = NSAlert()
        a.messageText = frame.request.url?.host ?? "Página"
        a.informativeText = message
        a.runModal()
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async -> Bool {
        let a = NSAlert()
        a.messageText = frame.request.url?.host ?? "Página"
        a.informativeText = message
        a.addButton(withTitle: "OK")
        a.addButton(withTitle: "Cancelar")
        return a.runModal() == .alertFirstButtonReturn
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo) async -> [URL]? {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = parameters.allowsMultipleSelection
        p.canChooseDirectories = parameters.allowsDirectories
        return p.runModal() == .OK ? p.urls : nil
    }

    /// Câmera e microfone: o Crew pergunta uma vez por site e lembra a resposta. (Na primeira
    /// vez de todas o macOS também pergunta se o Crew pode usar a câmera / o microfone.)
    func webView(_ webView: WKWebView, decideMediaCapturePermissionsFor origin: WKSecurityOrigin,
                 initiatedBy frame: WKFrameInfo, type: WKMediaCaptureType) async -> WKPermissionDecision {
        let oQue: String
        switch type {
        case .camera: oQue = "camera"
        case .microphone: oQue = "microfone"
        default: oQue = "camera+microfone"
        }
        return PermissoesNav.pedir(oQue, site: origin.host) ? .grant : .deny
    }

    /// Localização. O WebKit do macOS não tem chamada pública para isso; esta é a interna que
    /// os navegadores feitos com WKWebView usam. Se uma versão do macOS deixar de chamá-la, o
    /// site só recebe "negado".
    @objc(_webView:requestGeolocationPermissionForFrame:decisionHandler:)
    func pedirLocalizacao(_ webView: WKWebView, frame: WKFrameInfo, decisionHandler: @escaping (Bool) -> Void) {
        decisionHandler(PermissoesNav.pedir("localizacao", site: frame.securityOrigin.host))
    }
}

/// O que cada site pode usar (câmera, microfone, localização): o Hugo responde uma vez por site
/// e o Crew lembra. Fica nos ajustes do app (`modulo.navegador.permissoes`).
@MainActor
enum PermissoesNav {
    private static let chave = "modulo.navegador.permissoes"
    private static var guardadas: [String: Bool] {
        get { (UserDefaults.standard.dictionary(forKey: chave) as? [String: Bool]) ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: chave) }
    }

    private static let nomes = ["camera": "a câmera", "microfone": "o microfone",
                                "camera+microfone": "a câmera e o microfone", "localizacao": "a sua localização"]

    /// A resposta guardada; sem resposta ainda, pergunta ao Hugo.
    static func pedir(_ oQue: String, site: String) -> Bool {
        let id = site + "|" + oQue
        if let r = guardadas[id] { return r }
        let a = NSAlert()
        a.messageText = "\(site) quer usar \(nomes[oQue] ?? oQue)"
        a.informativeText = "A resposta fica guardada para este site. Dá para esquecer depois, no “…” da barra do navegador."
        a.addButton(withTitle: "Permitir")
        a.addButton(withTitle: "Negar")
        let sim = a.runModal() == .alertFirstButtonReturn
        guardadas[id] = sim
        return sim
    }

    static func tem(_ site: String) -> Bool { guardadas.keys.contains { $0.hasPrefix(site + "|") } }

    static func esquecer(_ site: String) {
        guardadas = guardadas.filter { !$0.key.hasPrefix(site + "|") }
    }
}

/// Aviso passageiro do navegador (download pronto, falha).
struct AvisoNav: Equatable {
    var texto: String
    /// Arquivo para mostrar no Finder ao clicar.
    var arquivo: URL?
}

@MainActor
final class NavegadorServico: ObservableObject {
    static let shared = NavegadorServico()
    static let geral = "geral"

    @Published private(set) var espacos: [EspacoNav] = []
    @Published var aviso: AvisoNav?
    /// Muda → o campo de endereço ganha o cursor (⌘L, ⌘T).
    @Published var focarCampo = 0
    /// A folha "Importar do Arc" está aberta.
    @Published var importandoArc = false
    /// Busca na página aberta (⌘F).
    @Published var buscando = false
    /// O espaço que está na tela (é nele que os atalhos agem).
    var espacoEmFoco: String?
    /// Espaço que o navegador da janela deve mostrar ao aparecer (pedido de fora: "ir para a aba").
    var espacoPedido: String?

    /// Vai para uma aba já aberta: ela vira a ativa do espaço dela e o navegador mostra esse espaço.
    func irPara(aba: String, espaco: String) {
        ativar(aba)
        espacoPedido = espaco
        NotificationCenter.default.post(name: .navegadorNoEspaco, object: espaco)
    }
    /// O cursor está no campo de endereço ou na busca do navegador.
    var campoFocado = false

    private var vivas: [String: AbaViva] = [:]
    private var gravacao: DispatchWorkItem?
    private static var arquivo: URL { HookServer.supportDir.appendingPathComponent("navegador.json") }

    private init() {
        guard !CaptureTool.ativo, let data = try? Data(contentsOf: Self.arquivo) else { return }
        espacos = (try? JSONDecoder().decode([EspacoNav].self, from: data)) ?? []
    }

    /// Só nas capturas: o campo de endereço aparece como se o Hugo tivesse digitado isto.
    private(set) var digitandoNoExemplo: String?

    /// Abas de exemplo para as capturas (nada é carregado da rede).
    func exemploParaCaptura(digitando: String? = nil) {
        digitandoNoExemplo = digitando
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var crew = EspacoNav(id: Self.geral, nome: "Geral", cor: "#9398A1")
        crew.abas = [
            AbaNav(url: "https://github.com", titulo: "GitHub", fixada: true),
            AbaNav(url: "https://developer.apple.com/documentation/webkit", titulo: "WebKit | Apple Developer", fixada: true),
            AbaNav(url: "http://localhost:3000", titulo: "localhost:3000"),
            AbaNav(url: "https://docs.anthropic.com", titulo: "Claude Code — documentação"),
        ]
        crew.ativa = crew.abas[2].id
        espacos = [crew, EspacoNav(id: home + "/dev/crew", nome: "crew", cor: "#38BDF8"),
                   EspacoNav(id: home + "/dev/loja", nome: "loja", cor: "#FF7A59")]
    }

    // MARK: Espaços

    func espaco(_ id: String) -> EspacoNav? { espacos.first { $0.id == id } }

    /// Prefixo do id do espaço de uma sessão.
    static let prefixoSessao = "sessao:"

    /// O espaço avulso de uma sessão (cria na primeira vez): as abas do navegador aberto ao lado
    /// dela. É só dela — não aparece no navegador da janela, que fica sempre no "Geral".
    @discardableResult
    func garantir(sessao id: String, nome: String, cor: String?) -> String {
        let chave = Self.prefixoSessao + id
        if let i = espacos.firstIndex(where: { $0.id == chave }) {
            if espacos[i].nome != nome { espacos[i].nome = nome; gravar() }
        } else {
            espacos.append(EspacoNav(id: chave, nome: nome, cor: cor ?? "#9398A1"))
            gravar()
        }
        return chave
    }

    /// A sessão acabou: o espaço avulso dela vai junto.
    func apagarEspaco(daSessao id: String) { apagarEspaco(Self.prefixoSessao + id) }

    /// O espaço do projeto (cria na primeira vez). nil = "Geral".
    @discardableResult
    func garantir(projeto: String?) -> String {
        let id = projeto ?? Self.geral
        if espaco(id) == nil {
            espacos.append(EspacoNav(id: id,
                                     nome: projeto.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Geral",
                                     cor: projeto.flatMap { Projetos.cor(de: $0) } ?? "#9398A1"))
            gravar()
        }
        return id
    }

    private func mudar(_ id: String, _ f: (inout EspacoNav) -> Void) {
        guard let i = espacos.firstIndex(where: { $0.id == id }) else { return }
        f(&espacos[i])
        gravar()
    }

    private func onde(_ aba: String) -> (e: Int, a: Int)? {
        for (e, esp) in espacos.enumerated() {
            if let a = esp.abas.firstIndex(where: { $0.id == aba }) { return (e, a) }
        }
        return nil
    }

    /// Tira o espaço e as abas dele (as páginas fecham; logins continuam no WebKit).
    func apagarEspaco(_ id: String) {
        guard id != Self.geral, let e = espaco(id) else { return }
        e.abas.forEach { vivas[$0.id] = nil }
        espacos.removeAll { $0.id == id }
        gravar()
    }

    // MARK: Abas

    /// A página carregada da aba (carrega na primeira vez que é pedida).
    func viva(_ aba: AbaNav) -> AbaViva {
        if let v = vivas[aba.id] { return v }
        let v = AbaViva(id: aba.id, armazem: Self.armazem(onde(aba.id).flatMap { espacos[$0.e].perfil }))
        vivas[aba.id] = v
        if !CaptureTool.ativo, let u = URL(string: aba.url) { v.web.load(URLRequest(url: u)) }
        return v
    }

    func estaViva(_ id: String) -> Bool { vivas[id] != nil }

    /// O armazenamento (cookies, logins) de um perfil; nil = o comum do navegador do Crew.
    static func armazem(_ perfil: String?) -> WKWebsiteDataStore {
        guard let perfil, let id = UUID(uuidString: perfil) else { return .default() }
        return WKWebsiteDataStore(forIdentifier: id)
    }

    func acrescentar(_ e: EspacoNav) {
        guard espaco(e.id) == nil else { return }
        espacos.append(e)
        gravar()
    }

    /// Põe no espaço as abas que ainda não estão lá (pelo endereço). Devolve os ids das novas.
    func juntar(_ abas: [ArcLeitor.Aba], em espacoId: String) -> [String] {
        var novas: [String] = []
        mudar(espacoId) { e in
            for a in abas where !e.abas.contains(where: { $0.url == a.url }) {
                let nova = AbaNav(url: a.url, titulo: a.titulo, fixada: a.fixada)
                e.abas.append(nova)
                novas.append(nova.id)
            }
            e.abas = e.abas.filter(\.fixada) + e.abas.filter { !$0.fixada }
        }
        return novas
    }

    /// Tira a aba de vez (mesmo fixada).
    func tirarAba(_ aba: String) {
        guard let p = onde(aba) else { return }
        vivas[aba] = nil
        if espacos[p.e].ativa == aba { espacos[p.e].ativa = nil }
        if espacos[p.e].lado == aba { espacos[p.e].lado = nil }
        espacos[p.e].abas.remove(at: p.a)
        gravar()
    }

    /// O que o Hugo digitou vira endereço: URL inteira, domínio (ganha https://), localhost
    /// (http://) ou, se não parece endereço, uma busca.
    static func endereco(_ texto: String) -> URL? {
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        if t.contains("://") || t.hasPrefix("about:") || t.hasPrefix("file:") { return URL(string: t) }
        let semEspaco = !t.contains(" ")
        let hospedeiro = t.split(separator: "/").first.map(String.init) ?? t
        let nome = hospedeiro.split(separator: ":").first.map(String.init) ?? hospedeiro
        if semEspaco, nome == "localhost" || nome.range(of: #"^\d{1,3}(\.\d{1,3}){3}$"#, options: .regularExpression) != nil {
            return URL(string: "http://" + t)
        }
        if semEspaco, nome.contains("."), !nome.hasSuffix("."), let u = URL(string: "https://" + t) { return u }
        return busca(t)
    }

    /// A busca do texto no buscador do navegador (Google), mesmo que ele pareça endereço.
    static func busca(_ texto: String) -> URL? {
        var c = URLComponents(string: "https://www.google.com/search")
        c?.queryItems = [URLQueryItem(name: "q", value: texto)]
        return c?.url
    }

    /// Abre numa aba nova do espaço e a põe em foco.
    func abrir(_ url: URL, em espacoId: String, emFoco: Bool = true) {
        let aba = AbaNav(url: url.absoluteString, titulo: url.host ?? url.absoluteString)
        mudar(espacoId) { e in
            e.abas.append(aba)
            if emFoco || e.ativa == nil { e.ativa = aba.id }
        }
        if !emFoco { _ = viva(aba) }
    }

    /// Enter no campo de endereço: navega na aba ativa; sem aba, abre uma.
    func navegar(_ texto: String, em espacoId: String) {
        guard let url = Self.endereco(texto) else { return }
        navegar(para: url, em: espacoId)
    }

    func navegar(para url: URL, em espacoId: String) {
        if let e = espaco(espacoId), let aba = e.abas.first(where: { $0.id == e.ativa }) {
            viva(aba).web.load(URLRequest(url: url))
        } else {
            abrir(url, em: espacoId)
        }
    }

    /// Aba nova vazia: o campo de endereço ganha o cursor.
    func novaAba(_ espacoId: String) {
        mudar(espacoId) { $0.ativa = nil }
        focarCampo += 1
    }

    func abrirEmAbaNova(_ url: URL, juntoDe aba: String, emFoco: Bool) {
        guard let p = onde(aba) else { return }
        abrir(url, em: espacos[p.e].id, emFoco: emFoco)
    }

    /// A página pediu uma janela nova: nasce como aba, com a configuração que o WebKit exige.
    func abaParaJanelaNova(_ c: WKWebViewConfiguration, juntoDe aba: String) -> WKWebView? {
        guard let p = onde(aba) else { return nil }
        let nova = AbaNav(url: "about:blank", titulo: "Nova aba")
        let v = AbaViva(id: nova.id, configuracao: c)
        vivas[nova.id] = v
        espacos[p.e].abas.insert(nova, at: min(p.a + 1, espacos[p.e].abas.count))
        espacos[p.e].ativa = nova.id
        gravar()
        return v.web
    }

    func ativar(_ aba: String) {
        guard let p = onde(aba) else { return }
        if espacos[p.e].lado == aba { espacos[p.e].lado = nil }
        espacos[p.e].ativa = aba
        gravar()
    }

    /// Fecha a aba. Fixada não some: só é descarregada (como no Arc).
    func fechar(_ aba: String) {
        guard let p = onde(aba) else { return }
        vivas[aba]?.web.stopLoading()
        vivas[aba] = nil
        var e = espacos[p.e]
        if e.lado == aba { e.lado = nil }
        if !e.abas[p.a].fixada { e.abas.remove(at: p.a) }
        if e.ativa == aba {
            let soltas = e.abas.filter { !$0.fixada || vivas[$0.id] != nil }.filter { $0.id != aba }
            e.ativa = soltas.isEmpty ? nil : soltas[min(p.a, soltas.count - 1)].id
        }
        espacos[p.e] = e
        gravar()
    }

    func alternarFixada(_ aba: String) {
        guard let p = onde(aba) else { return }
        espacos[p.e].abas[p.a].fixada.toggle()
        // Fixadas ficam juntas, no começo.
        let a = espacos[p.e].abas
        espacos[p.e].abas = a.filter(\.fixada) + a.filter { !$0.fixada }
        gravar()
    }

    /// Põe a aba ao lado da ativa (ou tira, se já está).
    func alternarLado(_ aba: String) {
        guard let p = onde(aba) else { return }
        if espacos[p.e].lado == aba {
            espacos[p.e].lado = nil
        } else if espacos[p.e].ativa == aba {
            // A própria ativa: a vizinha vira a principal e esta vai para o lado.
            guard let outra = espacos[p.e].abas.first(where: { $0.id != aba }) else { return }
            espacos[p.e].ativa = outra.id
            espacos[p.e].lado = aba
        } else {
            espacos[p.e].lado = aba
        }
        gravar()
    }

    func mover(_ aba: String, passo: Int) {
        guard let p = onde(aba) else { return }
        let j = p.a + passo
        guard espacos[p.e].abas.indices.contains(j), espacos[p.e].abas[j].fixada == espacos[p.e].abas[p.a].fixada else { return }
        espacos[p.e].abas.swapAt(p.a, j)
        gravar()
    }

    /// A página mudou de título ou endereço: guarda para a aba voltar onde estava.
    func atualizar(_ aba: String, titulo: String, url: String?) {
        guard let p = onde(aba) else { return }
        var a = espacos[p.e].abas[p.a]
        // Fixada volta sempre para o endereço em que foi fixada.
        if let url, !url.isEmpty, url != "about:blank", !a.fixada { a.url = url }
        if !titulo.isEmpty { a.titulo = titulo }
        guard a != espacos[p.e].abas[p.a] else { return }
        espacos[p.e].abas[p.a] = a
        gravar()
    }

    /// Abre o painel de senhas do macOS sobre o campo da página (Touch ID e a escolha são do sistema).
    func preencherSenha(_ web: WKWebView) {
        Task {
            switch await SenhasNav.pedir(web) {
            case .abriu: break
            case .semCampo: aviso = AvisoNav(texto: "Clique no campo de usuário ou senha da página e tente de novo", arquivo: nil)
            case .indisponivel: aviso = AvisoNav(texto: "Este macOS não deixou abrir o painel de senhas aqui", arquivo: nil)
            }
        }
    }

    func baixou(_ arquivo: URL) {
        aviso = AvisoNav(texto: "Baixado: \(arquivo.lastPathComponent)", arquivo: arquivo)
    }

    // MARK: Guardar

    private func gravar() {
        guard !CaptureTool.ativo else { return }
        gravacao?.cancel()
        let w = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let data = try? JSONEncoder().encode(self.espacos) else { return }
                try? data.write(to: Self.arquivo, options: .atomic)
            }
        }
        gravacao = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: w)
    }

    // MARK: Atalhos

    private func ativaEmFoco() -> (espaco: EspacoNav, aba: AbaNav?)? {
        guard let id = espacoEmFoco, let e = espaco(id) else { return nil }
        return (e, e.abas.first { $0.id == e.ativa })
    }

    /// O cursor está numa página do navegador ou no campo dele.
    private func temFoco(_ janela: NSWindow?) -> Bool {
        if campoFocado { return true }
        var v = janela?.firstResponder as? NSView
        while let atual = v {
            if atual is WKWebView { return true }
            v = atual.superview
        }
        return false
    }

    /// Atalhos do navegador, só com o cursor nele. true = tratou a tecla.
    /// ⌘T nova aba · ⌘W fecha · ⌘L endereço · ⌘R recarrega · ⌘[ ⌘] volta/avança · ⌘F busca ·
    /// ⇧⌘C copia o endereço · ⇧⌘P senhas do macOS · ⌃Tab / ⌃⇧Tab troca de aba.
    func tecla(_ evento: NSEvent) -> Bool {
        guard temFoco(evento.window), let (e, aba) = ativaEmFoco() else { return false }
        let mods = evento.modifierFlags.intersection([.command, .control, .option, .shift])
        let web = aba.map { viva($0).web }
        switch (mods, evento.keyCode) {
        case (.command, 17):                                  // ⌘T
            novaAba(e.id)
        case (.command, 13):                                  // ⌘W
            guard let aba else { return false }
            fechar(aba.id)
        case (.command, 37): focarCampo += 1                  // ⌘L
        case (.command, 15): web?.reload()                    // ⌘R
        case (.command, 33): web?.goBack()                    // ⌘[
        case (.command, 30): web?.goForward()                 // ⌘]
        case (.command, 3): buscando = true                   // ⌘F
        case ([.command, .shift], 8):                         // ⇧⌘C
            guard let u = web?.url?.absoluteString else { return false }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(u, forType: .string)
            aviso = AvisoNav(texto: "Endereço copiado", arquivo: nil)
        case ([.command, .shift], 35):                        // ⇧⌘P
            guard let web else { return false }
            preencherSenha(web)
        case (.control, 48), ([.control, .shift], 48):        // ⌃Tab
            guard !e.abas.isEmpty else { return false }
            let i = e.abas.firstIndex { $0.id == e.ativa } ?? -1
            let n = e.abas.count
            ativar(e.abas[((i + (mods.contains(.shift) ? -1 : 1)) % n + n) % n].id)
        default: return false
        }
        return true
    }
}

/// O ícone do site (favicon), guardado na memória enquanto o app está aberto.
@MainActor
enum Favicons {
    private static var guardados: [String: NSImage] = [:]
    private static var semIcone: Set<String> = []

    static func de(_ hospedeiro: String) async -> NSImage? {
        if let i = guardados[hospedeiro] { return i }
        guard !semIcone.contains(hospedeiro), let u = URL(string: "https://\(hospedeiro)/favicon.ico") else { return nil }
        var pedido = URLRequest(url: u)
        pedido.timeoutInterval = 6
        guard let (data, _) = try? await URLSession.shared.data(for: pedido), let img = NSImage(data: data), img.isValid else {
            semIcone.insert(hospedeiro)
            return nil
        }
        guardados[hospedeiro] = img
        return img
    }
}
