import AppKit
import Carbon.HIToolbox
import Combine

// O comando universal do Crew: um campo que acha e faz. Apps, arquivos, contas e ajustes do
// sistema (o que o Spotlight faz), mais tradutor, navegador do Crew e o próprio Crew (sessões,
// projetos, ações e páginas de ajuste). O que não casa com nada pode virar pesquisa na web ou
// pedido ao Claude Code — sempre como item que ele escolhe.
//
// Regras:
// - Fechado, nada roda: sem timer, sem consulta de arquivos, sem tradutor. Só o atalho global
//   fica registrado (o macOS avisa quando a combinação é apertada; o Crew não lê o teclado).
// - Nada sai do Mac, a não ser a página que ele mandar abrir.
// - Nenhuma ação destrutiva por aqui.
// - O que ele escolhe sobe (AprendizadoComando), guardado só nos ajustes locais.

@MainActor
final class ComandoServico: ObservableObject {
    static let shared = ComandoServico()
    static let modulo = "comando"

    /// O que está digitado. Mudar o texto remonta a lista.
    @Published var texto = "" {
        didSet { if texto != oldValue, aberto, !exemplo { aviso = nil; montar(digitando: true) } }
    }
    @Published private(set) var resultados: [ResultadoComando] = []
    @Published private(set) var selecao: String?
    @Published private(set) var aberto = false
    /// Recado curto no rodapé (ex.: por que a sessão não abriu).
    @Published private(set) var aviso: String?
    /// A consulta de arquivos ainda está juntando.
    @Published private(set) var procurandoArquivos = false

    let tradutor = Tradutor()
    private let arquivos = FonteArquivos()
    private var apps: [AppDoComando] = []
    private var achados: [ArquivoAchado] = []
    private var aprendizado = AprendizadoComando()
    private var pedidoTraducao: EntradaComando.PedidoTraducao?
    private var mexeuNaSelecao = false
    private var vigias: Set<AnyCancellable> = []
    private var exemplo = false

    // Atalho global
    @Published private(set) var combinacao = ComandoServico.atalhoPadrao
    @Published private(set) var atalhoLigado = true
    @Published private(set) var atalhoRecusado = false
    @Published private(set) var gravandoAtalho = false
    private lazy var atalho = AtalhoComando { [weak self] in self?.alternar() }
    private var monitorGravador: Any?
    private var iniciado = false

    static let atalhoPadrao = Combinacao(tecla: UInt32(kVK_Space), modificadores: UInt32(optionKey), nomeTecla: "Espaço")
    static let maxMelhores = 6
    static let maxArquivos = 5

    private init() {
        arquivos.chegou = { [weak self] texto, achados in self?.chegaram(texto, achados) }
        // O tradutor responde depois: a linha dele é refeita no lugar, sem mexer no resto.
        tradutor.$estado.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] _ in
            guard let self, self.aberto, !self.exemplo else { return }
            self.montar(digitando: false)
        }.store(in: &vigias)
    }

    // MARK: Ligar / desligar (módulo)

    func iniciar() {
        guard !CaptureTool.ativo, !iniciado else { return }
        iniciado = true
        lerAjustes()
        aplicarAtalho()
    }

    func parar() {
        iniciado = false
        cancelarGravacao()
        atalho.desligar()
        fechar()
    }

    // MARK: Ajustes

    func fonteLigada(_ nome: String) -> Bool { Ajustes.bool(Self.modulo, "fonte." + nome, padrao: true) }

    func ligarFonte(_ nome: String, _ v: Bool) {
        Ajustes.definir(Self.modulo, "fonte." + nome, v)
        objectWillChange.send()
    }

    private func lerAjustes() {
        atalhoLigado = Ajustes.bool(Self.modulo, "atalhoLigado", padrao: true)
        let d = UserDefaults.standard
        if let nome = Ajustes.string(Self.modulo, "atalhoNome"),
           d.object(forKey: Ajustes.chave(Self.modulo, "atalhoTecla")) != nil {
            combinacao = Combinacao(tecla: UInt32(d.integer(forKey: Ajustes.chave(Self.modulo, "atalhoTecla"))),
                                    modificadores: UInt32(d.integer(forKey: Ajustes.chave(Self.modulo, "atalhoMods"))),
                                    nomeTecla: nome)
        }
        if let dados = d.data(forKey: Ajustes.chave(Self.modulo, "aprendizado")),
           let a = try? JSONDecoder().decode(AprendizadoComando.self, from: dados) {
            aprendizado = a
        }
    }

    var quantoAprendeu: Int { aprendizado.usos.count }

    func esquecerAprendizado() {
        aprendizado = AprendizadoComando()
        Gravar.padrao.removeObject(forKey: Ajustes.chave(Self.modulo, "aprendizado"))
        objectWillChange.send()
    }

    private func gravarAprendizado() {
        guard let dados = try? JSONEncoder().encode(aprendizado) else { return }
        Ajustes.definir(Self.modulo, "aprendizado", dados)
    }

    // MARK: Atalho

    var atalhoEhPadrao: Bool { combinacao == Self.atalhoPadrao }

    func ligarAtalho(_ v: Bool) {
        atalhoLigado = v
        Ajustes.definir(Self.modulo, "atalhoLigado", v)
        aplicarAtalho()
    }

    func definirAtalho(_ c: Combinacao) {
        combinacao = c
        Ajustes.definir(Self.modulo, "atalhoTecla", Int(c.tecla))
        Ajustes.definir(Self.modulo, "atalhoMods", Int(c.modificadores))
        Ajustes.definir(Self.modulo, "atalhoNome", c.nomeTecla)
        aplicarAtalho()
    }

    private func aplicarAtalho() {
        guard iniciado, atalhoLigado else { atalho.desligar(); atalhoRecusado = false; return }
        atalhoRecusado = !atalho.ligar(combinacao)
    }

    /// Espera a próxima combinação apertada na janela de Ajustes (não escuta o teclado fora dela).
    /// Enquanto grava, o atalho fica solto — senão a combinação atual abriria o painel.
    func gravarAtalho() {
        pararGravador(reaplicar: false)
        atalho.desligar()
        gravandoAtalho = true
        monitorGravador = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] evento in
            MainActor.assumeIsolated {
                guard let self, self.gravandoAtalho else { return }
                if evento.keyCode == 53, evento.modifierFlags.intersection([.command, .control, .option]).isEmpty {
                    self.pararGravador(reaplicar: true)   // Esc: fica como estava
                } else if let c = Combinacao.de(evento) {
                    self.pararGravador(reaplicar: false)
                    self.definirAtalho(c)
                } else {
                    NSSound.beep()   // sem ⌃, ⌥ ou ⌘ não serve: continua esperando
                }
            }
            return nil
        }
    }

    func cancelarGravacao() { pararGravador(reaplicar: true) }

    private func pararGravador(reaplicar: Bool) {
        if let m = monitorGravador { NSEvent.removeMonitor(m) }
        monitorGravador = nil
        let estava = gravandoAtalho
        gravandoAtalho = false
        if reaplicar, estava { aplicarAtalho() }
    }

    // MARK: Abrir / fechar

    func alternar() { aberto ? fechar() : abrir() }

    func abrir(texto inicial: String = "", aviso recado: String? = nil) {
        guard Registro.shared.estaLigado(Self.modulo) else { return }
        achados = []
        mexeuNaSelecao = false
        // O texto entra antes de abrir (não dispara a montagem duas vezes nem apaga o recado).
        aberto = false
        texto = inicial
        aberto = true
        aviso = recado
        montar(digitando: true)
        PainelComando.shared.mostrar()
        Task {
            // Apps do disco e projetos: lidos agora, fora da thread principal; a lista se refaz.
            async let lidos = FonteApps.ler()
            await ProjetosCrew.shared.recarregar()
            apps = await lidos
            if aberto { montar(digitando: false) }
        }
    }

    func fechar() {
        guard aberto else { return }
        aberto = false
        arquivos.parar()
        tradutor.parar()
        pedidoTraducao = nil
        procurandoArquivos = false
        achados = []
        resultados = []
        selecao = nil
        aviso = nil
        texto = ""
        PainelComando.shared.esconder()
    }

    // MARK: Teclado

    private var escolhiveis: [String] { resultados.filter { !$0.inerte }.map(\.id) }

    func andar(_ passo: Int) {
        mexeuNaSelecao = true
        selecao = ListaComando.andar(de: selecao, passo: passo, em: escolhiveis)
    }

    func selecionar(_ id: String) {
        guard escolhiveis.contains(id) else { return }
        mexeuNaSelecao = true
        selecao = id
    }

    var selecionado: ResultadoComando? { resultados.first { $0.id == selecao } }

    /// Enter (ou ⌘Enter, com `secundaria`) no item selecionado.
    func executar(secundaria: Bool = false) {
        guard let r = selecionado else { return }
        executar(r, secundaria: secundaria)
    }

    func executar(_ r: ResultadoComando, secundaria: Bool = false) {
        guard !r.inerte else { return }
        let acao = secundaria ? r.secundaria : r.acao
        guard let acao else { return }
        if r.aprende, !exemplo {
            aprendizado.registrar(consulta: texto, id: r.id, agora: Date())
            gravarAprendizado()
        }
        // Fecha antes de agir: quem vem depois (a captura, o app aberto) não encontra o painel na frente.
        fechar()
        DispatchQueue.main.async { acao() }
    }

    // MARK: Montar a lista

    private func chegaram(_ textoDaBusca: String, _ novos: [ArquivoAchado]) {
        guard aberto, textoDaBusca == texto.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
        procurandoArquivos = false
        achados = novos
        montar(digitando: false)
    }

    /// Refaz a lista. `digitando`: o texto mudou (a seleção volta ao começo e as fontes que
    /// demoram são pedidas de novo); senão, só chegou resposta de uma fonte (a seleção fica).
    private func montar(digitando: Bool) {
        let digitando = digitando && !exemplo   // no modo de capturas nenhuma fonte é chamada
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        if digitando { mexeuNaSelecao = false }
        guard !t.isEmpty else {
            if digitando { arquivos.parar(); tradutor.parar(); pedidoTraducao = nil; achados = []; procurandoArquivos = false }
            publicar(semTexto())
            return
        }

        var lista: [ResultadoComando] = []
        let agora = Date()

        // 1. Resposta direta: conta, tradução, endereço, ação com texto.
        let conta = Calculadora.calcular(t)
        if let c = conta {
            lista.append(ResultadoComando(id: "conta", titulo: c.detalhe, icone: .simbolo("equal.circle"), tipo: "Conta",
                                          grupo: .resposta, destaque: c.texto, rotuloEnter: "Copiar", aprende: false,
                                          acao: { NSPasteboard.copiar(c.copia) }))
        }

        var pedido: EntradaComando.PedidoTraducao?
        if conta == nil, fonteLigada("tradutor") {
            pedido = EntradaComando.traducao(t)
            if pedido == nil, EntradaComando.endereco(t) == nil, Tradutor.pareceEstrangeiro(t) {
                pedido = .init(texto: t, destino: "pt")
            }
        }
        if digitando, pedido != pedidoTraducao {
            pedidoTraducao = pedido
            if let p = pedido { tradutor.traduzir(p.texto, destino: p.destino) } else { tradutor.parar() }
        }
        if let p = pedido, let linha = linhaDaTraducao(p) { lista.append(linha) }

        let url = EntradaComando.endereco(t)
        if let url, fonteLigada("web") {
            lista.append(ResultadoComando(id: "endereco", titulo: "Abrir \(url.host() ?? t)", subtitulo: url.absoluteString,
                                          icone: .simbolo("globe"), tipo: "Navegador do Crew", grupo: .resposta,
                                          rotuloSecundario: "No navegador padrão", aprende: false,
                                          acao: { Self.abrirNoNavegadorDoCrew(url) },
                                          secundaria: { NSWorkspace.shared.open(url) }))
        }

        // O site que ele mais visita e que começa com o que foi digitado (como o campo de
        // endereço do navegador completa): "insta" já oferece instagram.com.
        if url == nil, fonteLigada("web"),
           let c = SugestoesEndereco.completar(t, visitas: HistoricoNav.shared.visitas, agora: agora),
           let destino = URL(string: c.destino.contains("://") ? c.destino : "https://" + c.destino) {
            lista.append(ResultadoComando(id: "site:" + c.mostrado, titulo: c.mostrado, subtitulo: "Site que você visita",
                                          icone: .simbolo("globe"), tipo: "Navegador do Crew", grupo: .resposta,
                                          rotuloSecundario: "No navegador padrão", aprende: false,
                                          acao: { Self.abrirNoNavegadorDoCrew(destino) },
                                          secundaria: { NSWorkspace.shared.open(destino) }))
        }

        for a in AcoesComando.comTexto {
            guard let resto = EntradaComando.textoDepois(de: a.gatilhos, em: t), let destino = a.url(resto) else { continue }
            lista.append(ResultadoComando(id: "acao:" + a.id, titulo: a.titulo(resto), subtitulo: a.detalhe,
                                          icone: .simbolo(a.icone), tipo: "Ação", grupo: .resposta,
                                          rotuloEnter: "Fazer", acao: { Automacao.abrir(destino) }))
        }

        // 2. Melhores: tudo o que tem nome e casa com o texto, numa lista só.
        var melhores: [ResultadoComando] = []
        for c in candidatos() {
            let p = Casamento.pontos(t, titulo: c.resultado.titulo, extras: c.extras)
            // Uma letra só: vale começo de nome. Letras soltas na ordem: só para app e ação.
            guard p > 0, t.count > 1 || p >= 0.68, p >= 0.45 || c.aceitaVago else { continue }
            var r = c.resultado
            r.pontos = p * c.peso + aprendizado.bonus(consulta: t, id: r.id, agora: agora)
            melhores.append(r)
        }
        lista += ListaComando.ordenar(melhores) { $0.pontos }.prefix(Self.maxMelhores)

        // 3. Arquivos: chegam depois, num bloco próprio embaixo — o que está em cima não sai do lugar.
        if fonteLigada("arquivos") {
            if digitando {
                // Enquanto a consulta nova não volta, ficam os que ainda casam com o texto.
                achados = achados.filter { Casamento.pontos(t, em: $0.nome) > 0 }
                arquivos.procurar(t)
                procurandoArquivos = t.count >= 2
            }
            let pontuados = achados.map { a -> ResultadoComando in
                var r = Self.resultado(doArquivo: a)
                let recente = a.ultimoUso.map { max(0, 0.08 - agora.timeIntervalSince($0) / 86400 / 30 * 0.08) } ?? 0
                r.pontos = Casamento.pontos(t, em: a.nome) + recente + aprendizado.bonus(consulta: t, id: r.id, agora: agora)
                return r
            }
            lista += ListaComando.ordenar(pontuados) { $0.pontos }.prefix(Self.maxArquivos)
        } else if digitando {
            arquivos.parar()
            achados = []
        }

        // 4. Adiante: pesquisar na web e perguntar. Nunca automático; sempre escolha dele.
        var adiante: [ResultadoComando] = []
        if fonteLigada("web"), conta == nil, let busca = Self.busca(t) {
            adiante.append(ResultadoComando(id: "web", titulo: "Pesquisar na web", subtitulo: t, icone: .simbolo("magnifyingglass"),
                                            tipo: "Navegador do Crew", grupo: .adiante, rotuloEnter: "Pesquisar",
                                            rotuloSecundario: "No navegador padrão", aprende: false,
                                            acao: { Self.abrirNoNavegadorDoCrew(busca) },
                                            secundaria: { NSWorkspace.shared.open(busca) }))
        }
        if fonteLigada("perguntar"), conta == nil, url == nil, Registro.shared.estaLigado("sessoes") {
            let projeto = Self.projetoDaPergunta()
            let onde = projeto.map { "Sessão nova em \($0.nome)" } ?? "Abre o Crew com o texto copiado, para você escolher o projeto"
            adiante.append(ResultadoComando(id: "perguntar", titulo: "Perguntar ao Claude Code", subtitulo: onde,
                                            icone: .simbolo("sparkles"), tipo: "Claude Code", grupo: .adiante,
                                            rotuloEnter: "Perguntar", aprende: false,
                                            acao: { [weak self] in self?.perguntar(t) }))
        }
        // Frase com cara de pergunta: perguntar vem antes de pesquisar.
        if EntradaComando.parecePergunta(t) { adiante.reverse() }
        lista += adiante

        publicar(lista)
    }

    private func publicar(_ lista: [ResultadoComando]) {
        resultados = lista
        let ids = lista.filter { !$0.inerte }.map(\.id)
        // Sem ele ter andado na lista, vale sempre o primeiro; se andou, fica onde ele pôs.
        selecao = mexeuNaSelecao ? ListaComando.selecao(antes: selecao, depois: ids) : ids.first
    }

    /// Sem nada digitado: o que ele mais usa; sobrando lugar, o que o comando sabe fazer.
    private func semTexto() -> [ResultadoComando] {
        let todos = candidatos()
        var porId: [String: ResultadoComando] = [:]
        for c in todos { porId[c.resultado.id] = c.resultado }
        var lista: [ResultadoComando] = []
        for id in aprendizado.maisUsados(6, agora: Date()) {
            if let r = porId[id] {
                lista.append(r)
            } else if id.hasPrefix("arq:") {
                let caminho = String(id.dropFirst(4))
                var pasta: ObjCBool = false
                guard FileManager.default.fileExists(atPath: caminho, isDirectory: &pasta) else { continue }
                lista.append(Self.resultado(doArquivo: ArquivoAchado(caminho: caminho, nome: FileManager.default.displayName(atPath: caminho),
                                                                      ehPasta: pasta.boolValue, ultimoUso: nil)))
            }
        }
        for sugestao in ["crew:nova-sessao", "crew://captura/area", "crew://voz/ditar", "crew://diario/expandir", "crew:app", "crew:ajustes"]
        where lista.count < 6 {
            if let r = porId["acao:" + sugestao], !lista.contains(where: { $0.id == r.id }) { lista.append(r) }
        }
        return lista
    }

    private func linhaDaTraducao(_ p: EntradaComando.PedidoTraducao) -> ResultadoComando? {
        guard let estado = tradutor.estado else { return nil }
        func par(_ de: String, _ para: String) -> String {
            "\(EntradaComando.nomeDoIdioma(de)) → \(EntradaComando.nomeDoIdioma(para))"
        }
        var r = ResultadoComando(id: "traducao", titulo: "", icone: .simbolo("character.bubble"), tipo: "Tradução",
                                 grupo: .resposta, aprende: false, inerte: true)
        switch estado {
        case .traduzindo(let de, let para):
            r.titulo = "Traduzindo…"
            r.subtitulo = par(de, para)
        case .pronto(let traduzido, let de, let para):
            r.titulo = "\(par(de, para)) · \(p.texto)"
            r.destaque = traduzido
            r.rotuloEnter = "Copiar"
            r.inerte = false
            r.acao = { NSPasteboard.copiar(traduzido) }
        case .semPacote(let de, let para):
            r.titulo = "Falta baixar o idioma (\(par(de, para)))"
            r.subtitulo = "Enter abre Idioma e Região; o download fica em Idiomas de Tradução. Depois de baixar, traduz sem internet."
            r.icone = .simbolo("arrow.down.circle")
            r.rotuloEnter = "Abrir ajustes"
            r.inerte = false
            r.acao = {
                if let u = URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension") { NSWorkspace.shared.open(u) }
            }
        case .semSuporte(let de, let para):
            r.titulo = "O macOS não traduz de \(EntradaComando.nomeDoIdioma(de)) para \(EntradaComando.nomeDoIdioma(para))"
            r.icone = .simbolo("exclamationmark.bubble")
        case .naoIdentificou:
            r.titulo = "Não reconheci o idioma do texto"
            r.subtitulo = "Escreva um pouco mais, ou diga o destino: “… em inglês”."
            r.icone = .simbolo("questionmark.bubble")
        case .mesmoIdioma(let codigo):
            r.titulo = "O texto já está em \(EntradaComando.nomeDoIdioma(codigo))"
            r.subtitulo = "Diga outro destino: “… em espanhol”."
        case .falhou(let motivo):
            r.titulo = "Não traduziu"
            r.subtitulo = motivo
            r.icone = .simbolo("exclamationmark.bubble")
        }
        return r
    }

    // MARK: Candidatos (o que tem nome)

    private struct Candidato {
        var resultado: ResultadoComando
        var extras: [String] = []
        /// Quanto vale esta fonte diante das outras, com o mesmo casamento de nome.
        var peso = 1.0
        /// Aceita casamento vago (letras na ordem)?
        var aceitaVago = false
    }

    private func candidatos() -> [Candidato] {
        var c: [Candidato] = []

        for app in apps {
            let url = URL(fileURLWithPath: app.caminho)
            c.append(Candidato(resultado: ResultadoComando(
                id: "app:" + app.caminho, titulo: app.nome, icone: .arquivo(app.caminho), tipo: "App",
                rotuloSecundario: "Mostrar no Finder",
                acao: { NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) },
                secundaria: { NSWorkspace.shared.activateFileViewerSelecting([url]) }),
                extras: app.nomeNoDisco == app.nome ? [] : [app.nomeNoDisco], peso: 1, aceitaVago: true))
        }

        for a in AcoesComando.disponiveis {
            c.append(Candidato(resultado: ResultadoComando(
                id: "acao:" + a.id, titulo: a.titulo, subtitulo: a.detalhe, icone: .simbolo(a.icone), tipo: "Ação",
                rotuloEnter: "Fazer", acao: a.executar), extras: a.palavras, peso: 0.97, aceitaVago: true))
        }

        if Registro.shared.estaLigado("sessoes") {
            for t in AppState.shared.tasks where !t.isIntegration && t.source == .claudeCode {
                let projeto = Projetos.raiz(de: t.sessionCwd).map { URL(fileURLWithPath: $0).lastPathComponent } ?? t.name
                let id = t.id
                c.append(Candidato(resultado: ResultadoComando(
                    id: "sessao:" + id, titulo: t.displayTitle, subtitulo: "\(projeto) · \(t.stateLabel)",
                    icone: .cor(t.color), tipo: "Sessão", rotuloEnter: "Ir",
                    acao: { Self.abrirSessao(id) }), extras: [projeto, t.name, "sessao"], peso: 0.95))
            }
            for p in ProjetosCrew.shared.lista {
                let url = URL(fileURLWithPath: p.caminho)
                c.append(Candidato(resultado: ResultadoComando(
                    id: "projeto:" + p.caminho, titulo: p.nome, subtitulo: "Sessão nova em \(p.caminhoCurto)",
                    icone: .cor(p.cor), tipo: "Projeto", rotuloEnter: "Nova sessão", rotuloSecundario: "Mostrar no Finder",
                    acao: { [weak self] in self?.sessaoNova(em: p.caminho, pedido: "") },
                    secundaria: { NSWorkspace.shared.activateFileViewerSelecting([url]) }),
                    extras: ["projeto"], peso: 0.9))
            }
        }

        for m in Registro.shared.modulos {
            let id = m.id
            c.append(Candidato(resultado: ResultadoComando(
                id: "pagina:" + id, titulo: m.nome, icone: .simbolo(m.icone),
                tipo: "Ajustes do Crew", acao: { Central.abrir(modulo: id) }),
                extras: ["ajustes \(m.nome)", id], peso: 0.86))
        }

        for a in AjusteDoSistema.todos {
            guard let url = a.url else { continue }
            c.append(Candidato(resultado: ResultadoComando(
                id: "sistema:" + a.id, titulo: a.nome, icone: .simbolo(a.icone),
                tipo: "Ajustes do Sistema", acao: { NSWorkspace.shared.open(url) }),
                extras: a.palavras + ["ajustes \(a.nome)"], peso: 0.88))
        }

        if fonteLigada("web") {
            // Só as abas do navegador da janela: as do espaço avulso de uma sessão são dela.
            for espaco in NavegadorServico.shared.espacos where !espaco.daSessao {
                for aba in espaco.abas {
                    guard let url = URL(string: aba.url), url.scheme?.hasPrefix("http") == true else { continue }
                    let host = url.host() ?? aba.url
                    c.append(Candidato(resultado: ResultadoComando(
                        id: "aba:" + aba.url, titulo: aba.titulo.isEmpty ? host : aba.titulo,
                        subtitulo: "\(host) · \(espaco.nome)", icone: .simbolo(aba.fixada ? "pin" : "globe"),
                        tipo: aba.fixada ? "Aba fixada" : "Aba aberta", rotuloEnter: "Ir para a aba",
                        rotuloSecundario: "No navegador padrão",
                        acao: { Self.irParaAba(aba.id, espaco: espaco.id) }, secundaria: { NSWorkspace.shared.open(url) }),
                        extras: [host], peso: 0.85))
                }
            }
        }
        // Páginas do histórico do navegador do Crew (as 300 que mais pesam; aba aberta ganha no empate de id).
        if fonteLigada("web") {
            let agora = Date()
            let abertas = Set(c.map(\.resultado.id))
            let paginas = HistoricoNav.shared.visitas
                .sorted { SugestoesEndereco.peso($0, agora: agora) > SugestoesEndereco.peso($1, agora: agora) }
                .prefix(300)
            for v in paginas where !abertas.contains("aba:" + v.url) {
                guard let url = URL(string: v.url) else { continue }
                let host = SugestoesEndereco.dominio(v.url) ?? v.url
                c.append(Candidato(resultado: ResultadoComando(
                    id: "pagina:" + v.url, titulo: v.titulo.isEmpty ? host : v.titulo,
                    subtitulo: SugestoesEndereco.digitavel(v.url), icone: .simbolo("clock.arrow.circlepath"),
                    tipo: "Histórico", rotuloSecundario: "No navegador padrão",
                    acao: { Self.abrirNoNavegadorDoCrew(url) }, secundaria: { NSWorkspace.shared.open(url) }),
                    extras: [host], peso: 0.8))
            }
        }
        // A mesma página aberta em dois espaços aparece uma vez.
        var vistos = Set<String>()
        return c.filter { vistos.insert($0.resultado.id).inserted }
    }

    private static func resultado(doArquivo a: ArquivoAchado) -> ResultadoComando {
        let url = URL(fileURLWithPath: a.caminho)
        let casa = NSHomeDirectory()
        let pasta = url.deletingLastPathComponent().path
        let curto = pasta.hasPrefix(casa) ? "~" + pasta.dropFirst(casa.count) : pasta
        return ResultadoComando(id: "arq:" + a.caminho, titulo: a.nome, subtitulo: curto, icone: .arquivo(a.caminho),
                                tipo: a.ehPasta ? "Pasta" : "Arquivo", grupo: .arquivos, rotuloSecundario: "Mostrar no Finder",
                                acao: { NSWorkspace.shared.open(url) },
                                secundaria: { NSWorkspace.shared.activateFileViewerSelecting([url]) })
    }

    // MARK: Agir

    /// A busca na web com o mesmo mecanismo do navegador do Crew (`NavegadorServico.endereco`
    /// cai na busca quando o texto não é endereço; aqui o texto vai sempre como busca).
    static func busca(_ texto: String) -> URL? {
        var c = URLComponents(string: "https://www.google.com/search")
        c?.queryItems = [URLQueryItem(name: "q", value: texto)]
        return c?.url
    }

    /// Aba que já está aberta: mostra o navegador do Crew nela, sem abrir outra.
    static func irParaAba(_ aba: String, espaco: String) {
        let jaAberta = JanelaCrew.shared.aberta
        JanelaCrew.shared.abrir(ferramenta: Setores.navegador)
        DispatchQueue.main.asyncAfter(deadline: .now() + (jaAberta ? 0.05 : 0.45)) {
            NavegadorServico.shared.irPara(aba: aba, espaco: espaco)
        }
    }

    static func abrirNoNavegadorDoCrew(_ url: URL) {
        let jaAberta = JanelaCrew.shared.aberta
        Central.abrirSessoes()
        // A janela do app pode estar nascendo agora: o pedido chega depois de ela montar.
        DispatchQueue.main.asyncAfter(deadline: .now() + (jaAberta ? 0.05 : 0.45)) {
            NotificationCenter.default.post(name: .abrirNoNavegador, object: url)
        }
    }

    static func abrirSessao(_ id: String) {
        let jaAberta = JanelaCrew.shared.aberta
        Central.abrirSessoes()
        DispatchQueue.main.asyncAfter(deadline: .now() + (jaAberta ? 0.05 : 0.45)) {
            NotificationCenter.default.post(name: .abrirSessaoNoApp, object: id)
        }
    }

    /// O projeto onde a pergunta abre: o último em que ele abriu sessão; sem isso, o primeiro da lista.
    private static func projetoDaPergunta() -> ProjetoCrew? {
        let p = ProjetosCrew.shared
        return p.lista.first { $0.caminho == p.ultimo } ?? p.lista.first
    }

    private func perguntar(_ pedido: String) {
        guard let projeto = Self.projetoDaPergunta() else {
            NSPasteboard.copiar(pedido)
            Central.abrirSessoes()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                NotificationCenter.default.post(name: .novaSessao, object: nil)
            }
            return
        }
        sessaoNova(em: projeto.caminho, pedido: pedido)
    }

    /// Abre uma sessão do Claude Code no projeto, com os padrões dele (modelo, modo, isolamento),
    /// do mesmo jeito que a tela de início do app. Não abriu: o painel volta com o texto e o motivo.
    private func sessaoNova(em raiz: String, pedido: String) {
        guard MotorCrew.disponivel else {
            abrir(texto: pedido, aviso: MotorCrew.motivoIndisponivel ?? "O motor de sessões do Crew não está disponível.")
            return
        }
        let c = ConfigProjetos.shared.de(raiz)
        let opcoes = MotorCrew.Opcoes(modelo: c.modelo, modo: c.modo, esforco: c.esforco, instrucao: c.instrucao)
        Task {
            var pasta = raiz
            if c.isolamentoPronto {
                switch await IsolamentoProjeto.preparar(raiz: raiz, config: c, pedido: pedido) {
                case .success(let propria): pasta = propria
                case .failure(let f):
                    abrir(texto: pedido, aviso: "Não abriu: \(f.mensagem.prefix(160))")
                    return
                }
            }
            switch await MotorCrew.nova(pasta: pasta, pedido: pedido, opcoes: opcoes) {
            case .success(let sid):
                ProjetosCrew.shared.ultimo = raiz
                Central.abrirSessoes()
                // A sessão aparece na lista quando o Claude Code der sinal: aí o app vai até ela.
                for _ in 0..<40 {
                    try? await Task.sleep(for: .milliseconds(300))
                    if let t = AppState.shared.tasks.first(where: { $0.sessionId == sid }) {
                        NotificationCenter.default.post(name: .abrirSessaoNoApp, object: t.id)
                        break
                    }
                }
            case .failure(let f):
                abrir(texto: pedido, aviso: "Não abriu: \(f.mensagem.prefix(160))")
            }
        }
    }

    // MARK: Exemplo (modo de capturas do app)

    /// Monta a lista de verdade (mesma ordenação do uso) com dados de exemplo no lugar das
    /// fontes: nada do Hugo é lido, nada é gravado, nem arquivos nem tradutor são chamados.
    func exemploParaCaptura(texto t: String, apps exemploApps: [AppDoComando] = [], arquivos exemploArquivos: [ArquivoAchado] = [],
                            traducao: Tradutor.Estado? = nil, aviso recado: String? = nil) {
        exemplo = true
        aberto = true
        aprendizado = AprendizadoComando()
        apps = exemploApps
        achados = exemploArquivos
        procurandoArquivos = false
        aviso = recado
        texto = t
        pedidoTraducao = nil
        if let traducao { tradutor.exemploParaCaptura(t, traducao) } else { tradutor.parar() }
        mexeuNaSelecao = false
        montar(digitando: false)
    }
}
