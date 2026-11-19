import SwiftUI
import AppKit

// Homies: guarda a lista, cuida da pasta de cada um e abre conversa com eles pelo motor do Crew.
//
// Custo parado: zero (sem timer, sem observador). Só lê o `homies.json` ao iniciar.
// Um Homie só abre sessão no clique do Hugo ou por uma rotina que o Hugo configurou e ligou (a
// agenda é das Rotinas; aqui fica o que a sessão da rotina pode fazer e a página que ela entrega).

@MainActor
@Observable
final class HomiesServico {
    static let shared = HomiesServico()
    static let idModulo = "homies"

    private(set) var homies: [Homie] = []
    /// Homies com conversa abrindo agora.
    private(set) var abrindo: Set<UUID> = []
    /// Conversa aberta no tmux que ainda não deu sinal (Homie → session_id). É aqui que o Claude
    /// Code pergunta, na primeira vez, se confia na pasta: a página mostra o terminal dela.
    private(set) var esperando: [UUID: String] = [:]
    /// O último problema, para a página mostrar.
    var aviso: String?
    /// A página mais recente de cada rotina (rotina → página).
    private(set) var paginas: [UUID: PaginaGuardada] = [:]
    /// Rotinas com a sessão aberta agora, ainda sem página nova (rotina → session_id).
    private(set) var rotinasRodando: [UUID: String] = [:]
    /// Pedido para a tela mostrar a aba "Hoje" deste Homie (clique no aviso do notch).
    var mostrarHoje: UUID?

    /// Uma página como está guardada: o que o Homie escreveu, quando, e o que o Hugo já decidiu
    /// de cada ação ("feita" ou "dispensada").
    struct PaginaGuardada: Equatable {
        var pagina: PaginaHomie
        var quando: Date
        var resolvidas: [String: String] = [:]

        var pendentes: [PaginaHomie.Acao] { pagina.acoes.filter { resolvidas[$0.id] == nil } }
    }
    /// `homies.json` existe mas não deu para ler: nada é gravado por cima.
    private(set) var arquivoIlegivel = false

    @ObservationIgnored private var carregado = false
    @ObservationIgnored private let log = Log.de("homies")

    private static var suporte: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchBuddy")
    }
    static var arquivo: URL { suporte.appendingPathComponent("homies.json") }
    /// Onde moram as pastas dos Homies.
    static var base: URL { suporte.appendingPathComponent("Homies") }

    // MARK: Ciclo

    func iniciar() {
        // Modo de capturas não lê nem cria nada do Hugo
        guard !carregado, !CaptureTool.ativo else { return }
        carregado = true
        let fm = FileManager.default
        if fm.fileExists(atPath: Self.arquivo.path) {
            do {
                homies = try JSONDecoder().decode([Homie].self, from: Data(contentsOf: Self.arquivo))
            } catch {
                arquivoIlegivel = true
                log.error("não li homies.json: \(String(describing: error), privacy: .public)")
            }
        } else {
            // Primeira vez: nasce o assistente pessoal
            var h = PoliticaHomies.assistente
            h.pasta = Self.base.appendingPathComponent(PoliticaHomies.nomeDePasta(h.nome, ocupadas: [])).path
            homies = [h]
            prepararPasta(h)
            gravar()
        }
    }

    func homie(_ id: UUID) -> Homie? { homies.first { $0.id == id } }

    // MARK: Guardar

    /// Cria ou atualiza. Homie novo ganha a pasta dele; a de um existente não muda com o nome.
    func salvar(_ novo: Homie) {
        guard !arquivoIlegivel else { return }
        var h = novo
        h.nome = h.nome.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !h.nome.isEmpty else { return }
        // Coordenador que fecharia um círculo (ou que saiu da equipe) não vale
        if let c = h.chefe, homie(c) == nil || !PoliticaHomies.podeCoordenar(c, a: h.id, em: homies) { h.chefe = nil }
        if let i = homies.firstIndex(where: { $0.id == h.id }) {
            h.pasta = homies[i].pasta
            h.ultimaSessao = homies[i].ultimaSessao
            h.emConstrucao = homies[i].emConstrucao
            homies[i] = h
        } else {
            var ocupadas = Set(homies.map { URL(fileURLWithPath: $0.pasta).lastPathComponent })
            // Pasta que sobrou de um Homie tirado da lista não é reaproveitada
            if let nomes = try? FileManager.default.contentsOfDirectory(atPath: Self.base.path) { ocupadas.formUnion(nomes) }
            h.pasta = Self.base.appendingPathComponent(PoliticaHomies.nomeDePasta(h.nome, ocupadas: ocupadas)).path
            homies.append(h)
        }
        prepararPasta(h)
        gravarFicha(h)
        gravar()
    }

    // MARK: Ficha (homie.json na pasta dele)

    private func arquivoDaFicha(_ h: Homie) -> URL { URL(fileURLWithPath: h.pasta).appendingPathComponent("homie.json") }

    /// O que o Hugo mudou pelo formulário vai para a ficha: senão a ficha antiga desfaria a edição.
    private func gravarFicha(_ h: Homie) {
        let f = FichaHomie(nome: h.nome, funcao: h.funcao, instrucao: h.instrucao, modelo: h.modelo, pronto: !h.emConstrucao)
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try? e.encode(f).write(to: arquivoDaFicha(h), options: .atomic)
    }

    /// Lê a ficha da pasta e atualiza o Homie (nome, função, instrução, modelo, pronto). É assim
    /// que a montagem pelo Claude Code chega ao cartão. Sem ficha ou ilegível: nada muda.
    func lerFicha(_ id: UUID) {
        guard !arquivoIlegivel, let i = homies.firstIndex(where: { $0.id == id }),
              let d = try? Data(contentsOf: arquivoDaFicha(homies[i])),
              let f = try? JSONDecoder().decode(FichaHomie.self, from: d) else { return }
        let novo = PoliticaHomies.aplicar(f, a: homies[i])
        guard novo != homies[i] else { return }
        homies[i] = novo
        gravar()
    }

    // MARK: Montar pelo briefing

    /// Homie novo a partir do que o Hugo explicou: nasce a pasta, e uma conversa do Claude Code
    /// nela monta o resto com ele (guia, skills, MCPs, contexto e a ficha). Devolve o id dele.
    @discardableResult
    func montar(briefing: String, nome: String) -> UUID? {
        let texto = briefing.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !CaptureTool.ativo, !arquivoIlegivel, !texto.isEmpty else { return nil }
        if let m = MotorCrew.motivoIndisponivel { aviso = m; return nil }
        let apelido = nome.trimmingCharacters(in: .whitespacesAndNewlines)
        var h = Homie(nome: apelido.isEmpty ? "Novo Homie" : apelido, funcao: "", emConstrucao: true)
        var ocupadas = Set(homies.map { URL(fileURLWithPath: $0.pasta).lastPathComponent })
        if let nomes = try? FileManager.default.contentsOfDirectory(atPath: Self.base.path) { ocupadas.formUnion(nomes) }
        h.pasta = Self.base.appendingPathComponent(PoliticaHomies.nomeDePasta(h.nome, ocupadas: ocupadas)).path
        homies.append(h)
        // Sem o guia padrão: quem escreve o CLAUDE.md deste é a montagem
        prepararPasta(h, comGuia: false)
        gravar()
        let id = h.id
        abrindo.insert(id)
        aviso = nil
        let opcoes = MotorCrew.Opcoes(instrucao: PoliticaHomies.instrucaoDeMontagem, nome: "Montando \(h.nome)")
        Task {
            defer { abrindo.remove(id) }
            switch await MotorCrew.nova(pasta: h.pasta, pedido: PoliticaHomies.pedidoDeMontagem(briefing: texto, nome: apelido), opcoes: opcoes) {
            case .success(let sid):
                if let i = homies.firstIndex(where: { $0.id == id }) { homies[i].ultimaSessao = sid }
                gravar()
                await irPara(sid, de: id)
            case .failure(let f):
                aviso = "A montagem não abriu: \(f.mensagem.prefix(200))"
            }
        }
        return id
    }

    /// Tira da lista. A pasta dele (guia, notas, skills) fica no disco; as rotinas dele saem, e
    /// quem respondia a ele fica sem coordenador.
    func tirar(_ id: UUID) {
        guard !arquivoIlegivel else { return }
        homies.removeAll { $0.id == id }
        for i in homies.indices where homies[i].chefe == id { homies[i].chefe = nil }
        RotinasServico.shared.apagarDoHomie(id)
        gravar()
    }

    /// Garante a pasta e o guia. O CLAUDE.md só é escrito se não existir: depois é dele e do Hugo.
    private func prepararPasta(_ h: Homie, comGuia: Bool = true) {
        let fm = FileManager.default
        let pasta = URL(fileURLWithPath: h.pasta)
        do {
            try fm.createDirectory(at: pasta.appendingPathComponent("notas"), withIntermediateDirectories: true)
            try fm.createDirectory(at: pasta.appendingPathComponent(".claude/skills"), withIntermediateDirectories: true)
            let guia = pasta.appendingPathComponent("CLAUDE.md")
            if comGuia, !fm.fileExists(atPath: guia.path) {
                try PoliticaHomies.guia(h).write(to: guia, atomically: true, encoding: .utf8)
            }
        } catch {
            aviso = "Não consegui preparar a pasta de \(h.nome)."
            log.error("pasta do homie: \(String(describing: error), privacy: .public)")
        }
    }

    private func gravar() {
        guard !arquivoIlegivel else { return }
        do {
            let e = JSONEncoder()
            e.outputFormatting = [.prettyPrinted, .sortedKeys]
            try FileManager.default.createDirectory(at: Self.suporte, withIntermediateDirectories: true)
            try e.encode(homies).write(to: Self.arquivo, options: .atomic)
        } catch {
            aviso = "Não consegui gravar a lista de Homies."
            log.error("não gravou homies.json: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: Conversar

    private func opcoes(_ h: Homie, montagem: Bool = false) -> MotorCrew.Opcoes {
        if montagem { return MotorCrew.Opcoes(instrucao: PoliticaHomies.instrucaoDeMontagem, nome: "Montando \(h.nome)") }
        // Quem coordena enxerga a pasta de cada um do time (é de lá que o subagente trabalha).
        let time = PoliticaHomies.time(de: h.id, em: homies)
        let instrucao = PoliticaHomies.instrucaoDaSessao(h, time: time, chefe: h.chefe.flatMap { homie($0) })
        return MotorCrew.Opcoes(modelo: h.modelo, instrucao: instrucao, nome: h.nome, pastasExtras: time.map(\.pasta))
    }

    // MARK: Rotinas (a agenda mora em RotinasServico)

    /// Com que pasta, pedido e limites a sessão de uma rotina deste Homie abre. Ela roda sem o
    /// Hugo por perto: só lê, sem shell, sem MCP (ou só os da pasta dele, se o Hugo ligou), e
    /// escreve a página na pasta dele. nil = o Homie não está mais na equipe.
    func planoDaRotina(_ r: Rotina) -> (pasta: String, pedido: String, opcoes: MotorCrew.Opcoes)? {
        iniciar()
        guard let id = r.homie, let h = homie(id) else { return nil }
        prepararPasta(h)
        try? FileManager.default.createDirectory(at: URL(fileURLWithPath: h.pasta).appendingPathComponent("paginas"),
                                                 withIntermediateDirectories: true)
        var o = opcoes(h)
        o.nome = "\(h.nome) · \(r.nome)"
        // Edita só na pasta dele sem perguntar; o resto que pedir permissão para e espera o Hugo.
        o.modo = "acceptEdits"
        o.negadas = ["Bash"]
        o.somenteLeitura = o.pastasExtras
        // Só as ferramentas dele (as da aba Ferramentas e as do .mcp.json da pasta), e mais nenhuma.
        o.mcp = r.comMcps == true ? (FerramentasServico.shared.arquivoDaRotina(h).map { .so($0) } ?? .nenhum) : .nenhum
        let pedido = PoliticaHomies.pedidoDaRotina(nome: r.nome, entrega: r.pedido, rotina: r.id,
                                                   quando: FormatoRotina.quando(Date()), comTime: !o.pastasExtras.isEmpty)
        return (h.pasta, pedido, o)
    }

    private func arquivoDaPagina(_ h: Homie, _ rotina: UUID) -> URL {
        URL(fileURLWithPath: h.pasta).appendingPathComponent(PoliticaHomies.arquivoDaPagina(rotina))
    }

    private func arquivoDasDecisoes(_ h: Homie, _ rotina: UUID) -> URL {
        arquivoDaPagina(h, rotina).deletingPathExtension().appendingPathExtension("decisoes.json")
    }

    /// Lê do disco a página de cada rotina deste Homie (e o que o Hugo já decidiu nela).
    func carregarPaginas(_ id: UUID) {
        guard !CaptureTool.ativo, let h = homie(id) else { return }
        for r in RotinasServico.shared.doHomie(id) { lerPagina(h, r.id) }
    }

    /// Lê a página de uma rotina. As decisões guardadas só valem para a página em que foram
    /// tomadas: página nova começa com todas as ações em aberto.
    @discardableResult
    private func lerPagina(_ h: Homie, _ rotina: UUID) -> PaginaGuardada? {
        let url = arquivoDaPagina(h, rotina)
        guard let quando = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date,
              let d = try? Data(contentsOf: url), let p = PaginaHomie.ler(d) else { return nil }
        var g = PaginaGuardada(pagina: p, quando: quando)
        if let dd = try? Data(contentsOf: arquivoDasDecisoes(h, rotina)),
           let o = try? JSONSerialization.jsonObject(with: dd) as? [String: Any],
           let de = o["pagina"] as? Double, abs(de - quando.timeIntervalSince1970) < 1,
           let r = o["resolvidas"] as? [String: String] { g.resolvidas = r }
        if paginas[rotina] != g { paginas[rotina] = g }
        return g
    }

    /// A rotina abriu a sessão: espera a página nova, avisa no notch e fecha a sessão (a conversa
    /// fica guardada). Se a sessão parar numa pergunta, ela fica aberta esperando o Hugo.
    func rotinaAbriu(_ r: Rotina, sessao sid: String) {
        guard let id = r.homie, let h = homie(id) else { return }
        let rotina = r.id, nome = r.nome
        let inicio = Date().addingTimeInterval(-2)
        rotinasRodando[rotina] = sid
        Task {
            defer { if rotinasRodando[rotina] == sid { rotinasRodando[rotina] = nil } }
            // Até 40 minutos, olhando o arquivo a cada 3 s (só enquanto a rotina roda).
            for volta in 0..<800 {
                try? await Task.sleep(for: .seconds(3))
                guard rotinasRodando[rotina] == sid else { return }
                let url = arquivoDaPagina(h, rotina)
                if let m = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date, m >= inicio,
                   let g = lerPagina(h, rotina) {
                    log.info("página da rotina \(nome, privacy: .public) de \(h.nome, privacy: .public) chegou")
                    if !g.pagina.semNovidade { avisarPagina(h, g.pagina, rotina: nome) }
                    rotinasRodando[rotina] = nil
                    // Deixa ele terminar a última fala antes de fechar.
                    try? await Task.sleep(for: .seconds(25))
                    _ = await MotorCrew.encerrar(sid)
                    return
                }
                // A sessão foi fechada sem entregar: não há o que esperar.
                if volta % 10 == 9, !(await MotorCrew.ehDoCrew(sid)) { return }
            }
        }
    }

    private func avisarPagina(_ h: Homie, _ p: PaginaHomie, rotina: String) {
        let n = p.acoes.count
        let texto = "\(h.nome): \(p.titulo.isEmpty ? rotina : p.titulo)" + (n > 0 ? " · \(n) \(n == 1 ? "ação espera" : "ações esperam") você" : "")
        let id = h.id
        Arbitro.shared.publicar(Sinal(id: "homies.pagina", lugar: .barra, prioridade: .alerta, duracao: 12, clicavel: true,
                                      conteudo: AnyView(AvisoBarra(icone: "doc.text.fill", texto: String(texto.prefix(110)), cor: Tema.verde)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            Arbitro.shared.retirar("homies.pagina")
                                            HomiesServico.shared.mostrarHoje = id
                                            Central.abrir(modulo: HomiesServico.idModulo)
                                        })))
    }

    /// O Hugo decidiu uma ação da página: "feita" (mandou fazer) ou "dispensada". nil = volta a ficar em aberto.
    func decidir(_ homieId: UUID, rotina: UUID, acao: String, _ decisao: String?) {
        guard let h = homie(homieId), var g = paginas[rotina] else { return }
        g.resolvidas[acao] = decisao
        paginas[rotina] = g
        let o: [String: Any] = ["pagina": g.quando.timeIntervalSince1970, "resolvidas": g.resolvidas]
        if let d = try? JSONSerialization.data(withJSONObject: o, options: [.prettyPrinted, .sortedKeys]) {
            try? d.write(to: arquivoDasDecisoes(h, rotina), options: .atomic)
        }
    }

    /// Clique em "Fazer": o pedido da ação abre uma conversa com quem deve fazer (o Homie citado
    /// na ação; sem citar, o dono da página). Devolve com quem ficou.
    @discardableResult
    func fazer(_ homieId: UUID, rotina: UUID, acao: PaginaHomie.Acao) -> UUID? {
        guard !CaptureTool.ativo, homie(homieId) != nil else { return nil }
        let alvo = homies.first { !acao.quem.isEmpty && $0.nome.compare(acao.quem, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }?.id ?? homieId
        guard !abrindo.contains(alvo), MotorCrew.motivoIndisponivel == nil else {
            aviso = MotorCrew.motivoIndisponivel ?? "Ele já está abrindo uma conversa: espere e clique de novo."
            return nil
        }
        conversar(alvo, pedido: acao.pedido)
        decidir(homieId, rotina: rotina, acao: acao.id, "feita")
        return alvo
    }

    /// Abre uma conversa nova com o Homie, já com o pedido (vazio = em branco). Ela aparece na página dele.
    func conversar(_ id: UUID, pedido: String) {
        lerFicha(id)
        guard !CaptureTool.ativo, let h = homie(id), !abrindo.contains(id) else { return }
        if let m = MotorCrew.motivoIndisponivel { aviso = m; return }
        prepararPasta(h)
        abrindo.insert(id)
        aviso = nil
        Task {
            defer { abrindo.remove(id) }
            switch await MotorCrew.nova(pasta: h.pasta, pedido: pedido, opcoes: opcoes(h)) {
            case .success(let sid):
                if let i = homies.firstIndex(where: { $0.id == id }) { homies[i].ultimaSessao = sid }
                gravar()
                await irPara(sid, de: id)
            case .failure(let f):
                aviso = "Não abriu: \(f.mensagem.prefix(200))"
            }
        }
    }

    /// Volta à última conversa: se ainda está de pé, só vai até ela; senão, retoma de onde parou.
    func continuar(_ id: UUID) {
        guard !CaptureTool.ativo, let h = homie(id), let sid = h.ultimaSessao, !abrindo.contains(id) else { return }
        if let m = MotorCrew.motivoIndisponivel { aviso = m; return }
        abrindo.insert(id)
        aviso = nil
        Task {
            defer { abrindo.remove(id) }
            // Em construção, a última conversa é a da montagem
            switch await MotorCrew.retomar(sessionId: sid, pasta: h.pasta, opcoes: opcoes(h, montagem: h.emConstrucao)) {
            case .success: await irPara(sid, de: id)
            case .failure(let f): aviso = "Não retomou: \(f.mensagem.prefix(200))"
            }
        }
    }

    /// A conversa aparece na página quando o Claude Code der sinal. Enquanto não dá (pergunta de
    /// confiança na pasta, login), fica em `esperando` e a página mostra o terminal dela.
    /// Desiste de esperar em 10 minutos ou quando o Hugo dispensa.
    private func irPara(_ sid: String, de id: UUID) async {
        abrindo.remove(id)
        for volta in 0..<1200 {
            if AppState.shared.tasks.contains(where: { $0.sessionId == sid }) {
                esperando[id] = nil
                return
            }
            // Três segundos sem sinal: mostra o terminal
            if volta == 6 { esperando[id] = sid }
            if volta > 6, esperando[id] != sid { return }
            try? await Task.sleep(for: .milliseconds(500))
        }
        if esperando[id] == sid { esperando[id] = nil }
    }

    /// Para de esperar a conversa (ela continua de pé; "Continuar a última" volta a ela).
    func dispensarEspera(_ id: UUID) { esperando[id] = nil }

    /// O que há na pasta do Homie, para a página mostrar de relance.
    struct Bagagem: Equatable { var skills = 0; var mcps = 0; var notas = 0 }

    func bagagem(_ id: UUID) -> Bagagem {
        guard let h = homie(id) else { return Bagagem() }
        let fm = FileManager.default
        let pasta = URL(fileURLWithPath: h.pasta)
        func visiveis(_ sub: String) -> Int {
            ((try? fm.contentsOfDirectory(atPath: pasta.appendingPathComponent(sub).path)) ?? []).filter { !$0.hasPrefix(".") }.count
        }
        var b = Bagagem(skills: visiveis(".claude/skills"), notas: visiveis("notas"))
        if let d = try? Data(contentsOf: pasta.appendingPathComponent(".mcp.json")),
           let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
           let s = j["mcpServers"] as? [String: Any] { b.mcps = s.count }
        return b
    }

    func abrirPasta(_ id: UUID) {
        guard let h = homie(id) else { return }
        prepararPasta(h)
        NSWorkspace.shared.open(URL(fileURLWithPath: h.pasta))
    }
}
