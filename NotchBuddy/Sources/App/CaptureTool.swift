import AppKit
import SwiftUI

// MARK: - Modo de captura (`Crew --capturas <pasta>`)
// Monta a ilha de verdade em cada estado, com dados de exemplo, fotografa e sai.
// Não liga o servidor de hooks nem os pollers: não interfere no Crew que estiver rodando.
// Serve para regenerar design/captures e as imagens do site, e para prévias visuais.

@MainActor
enum CaptureTool {
    /// Ligado durante as capturas: telas pulam consultas externas (Xirp, terminal).
    static var ativo = false

    static var requested: String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--capturas"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    /// `--so <texto>`: só as cenas/páginas cujo arquivo contém o texto (ex.: `--so diario`).
    static var filtro: String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--so"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    struct Scene {
        let file: String
        let height: CGFloat
        var wait: TimeInterval = 1.6
        let setup: (AppState) -> Void
    }

    static func run(into dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        // As cenas mexem no AppState, que grava nos ajustes de verdade (sons, modo…). Guarda
        // os ajustes do Hugo antes e devolve intactos no fim.
        let dominio = Bundle.main.bundleIdentifier ?? "fr.louisraille.NotchBuddy"
        let ajustesAntes = UserDefaults.standard.persistentDomain(forName: dominio)
        let s = AppState.shared
        s.soundEnabled = false
        ativo = true
        for scene in scenes() where filtro.map({ scene.file.contains($0) }) ?? true {
            reset(s)
            scene.setup(s)
            shoot(scene, into: dir)
        }
        // Diário na Central: o dia de hoje de verdade (só lê) e um dia de exemplo
        DiarioServico.shared.carregarParaCaptura()
        fotografar(PaginaModulo(modulo: DiarioModulo.shared), tamanho: NSSize(width: 760, height: 1500),
                   espera: 2, arquivo: dir + "/35_central_diario_real.png")
        DiarioServico.shared.exemploParaCaptura()
        fotografar(PaginaModulo(modulo: DiarioModulo.shared), tamanho: NSSize(width: 760, height: 1500),
                   espera: 2, arquivo: dir + "/35b_central_diario_exemplo.png")
        // Página do Sistema na Central (janela de gestão)
        fotografar(PaginaModulo(modulo: SistemaModulo.shared), tamanho: NSSize(width: 760, height: 1500),
                   espera: 5, arquivo: dir + "/19_central_sistema.png")
        // Página dos Modelos na Central (dados de exemplo, ligados pela cena 21)
        fotografar(PaginaModulo(modulo: ModelosModulo.shared), tamanho: NSSize(width: 760, height: 760),
                   espera: 2, arquivo: dir + "/22_central_modelos.png")
        ModelosLigado.restaurar()
        // Página dos Agentes na Central (worktrees de verdade deste Mac, só leitura)
        fotografar(PaginaModulo(modulo: AgentesModulo.shared), tamanho: NSSize(width: 760, height: 980),
                   espera: 6, arquivo: dir + "/24_central_agentes.png")
        // Página do Áudio na Central (dispositivos de verdade deste Mac)
        fotografar(PaginaModulo(modulo: AudioModulo.shared), tamanho: NSSize(width: 760, height: 1700),
                   espera: 2, arquivo: dir + "/24_central_audio.png")
        // Página do Disco na Central, com dados de exemplo (não varre nem move nada)
        DiscoServico.shared.exemploParaCaptura(confirmar: false)
        fotografar(PaginaModulo(modulo: DiscoModulo.shared), tamanho: NSSize(width: 760, height: 1300),
                   espera: 3, arquivo: dir + "/28_central_disco.png")
        // Disco inteiro: projetos parados, simuladores, arquivos grandes e duplicados (exemplo)
        fotografar(PaginaModulo(modulo: DiscoModulo.shared), tamanho: NSSize(width: 760, height: 3000),
                   espera: 3, arquivo: dir + "/28b_central_disco_inteiro.png")
        // Confirmação dos projetos parados e dos simuladores (exemplo; nada é movido)
        ProjetosServico.shared.confirmacao = Array(ProjetosServico.shared.projetos.prefix(2))
        SimuladoresServico.shared.confirmacao = Array((SimuladoresServico.shared.lista ?? []).prefix(1))
        fotografar(PaginaModulo(modulo: DiscoModulo.shared), tamanho: NSSize(width: 760, height: 2400),
                   espera: 3, arquivo: dir + "/28c_central_disco_confirmar.png")
        // App do Crew (a janela das sessões), com sessões de exemplo: uma tela por cena
        appDoCrew(s, dir)
        reset(s)
        // Central: página Geral e a do Claude Code (hooks)
        fotografar(SettingsView(), tamanho: NSSize(width: 760, height: 900), espera: 2,
                   arquivo: dir + "/29_ajustes_crew.png")
        // Ajustes por superfície: a janela inteira (barra lateral), Ilha e App
        fotografar(CentralView(pagina: .geral), tamanho: NSSize(width: 1000, height: 700), espera: 2,
                   arquivo: dir + "/29a_ajustes_janela.png")
        fotografar(PaginaIlha(), tamanho: NSSize(width: 760, height: 1250), espera: 2,
                   arquivo: dir + "/29b_ajustes_ilha.png")
        fotografar(PaginaApp(), tamanho: NSSize(width: 760, height: 760), espera: 2,
                   arquivo: dir + "/29c_ajustes_app.png")
        fotografar(PaginaModulo(modulo: AudioModulo.shared), tamanho: NSSize(width: 760, height: 900), espera: 2,
                   arquivo: dir + "/29d_ajustes_ferramenta.png")
        fotografar(PaginaModulo(modulo: SessoesModulo.shared), tamanho: NSSize(width: 640, height: 360), espera: 2,
                   arquivo: dir + "/30_central_claude_code.png")
        // Página do Uso na Central: transcripts de verdade deste Mac (só lê)
        fotografar(PaginaModulo(modulo: UsoModulo.shared), tamanho: NSSize(width: 760, height: 1760),
                   espera: 8, arquivo: dir + "/32_central_uso.png")
        // Página do Apps na Central, com dados de exemplo (não lê sobras nem move nada)
        AppsServico.shared.exemploParaCaptura(confirmar: false)
        fotografar(PaginaModulo(modulo: AppsModulo.shared), tamanho: NSSize(width: 760, height: 1500),
                   espera: 2, arquivo: dir + "/33_central_apps.png")
        AppsServico.shared.exemploParaCaptura(confirmar: true)
        fotografar(PaginaModulo(modulo: AppsModulo.shared), tamanho: NSSize(width: 760, height: 700),
                   espera: 2, arquivo: dir + "/33b_central_apps_confirmar.png")
        // Página das Rotinas na Central, com rotinas de exemplo (nada é gravado nem executado), e o editor
        RotinasServico.shared.exemploParaCaptura()
        fotografar(PaginaModulo(modulo: RotinasModulo.shared), tamanho: NSSize(width: 760, height: 640),
                   espera: 2, arquivo: dir + "/41_central_rotinas.png")
        if let exemplo = RotinasServico.shared.rotinas.first {
            fotografar(RotinaEditor(rotina: exemplo, nova: false, salvar: { _ in }, cancelar: {}),
                       tamanho: NSSize(width: 540, height: 640), espera: 2, arquivo: dir + "/41b_rotinas_editor.png")
        }
        // Página da Voz na Central: permissões e um ditado de exemplo (não abre o microfone)
        VozServico.shared.exemploParaCaptura()
        fotografar(PaginaModulo(modulo: VozModulo.shared), tamanho: NSSize(width: 760, height: 1240),
                   espera: 2, arquivo: dir + "/41_central_voz.png")
        // Voz do computador: a seção com o motor de voz humanizada instalado (vozes de exemplo) e sem ele
        FalaServico.shared.exemploParaCaptura()
        fotografar(FalaCentral().padding(20).frame(width: 760, alignment: .leading), tamanho: NSSize(width: 760, height: 1120),
                   espera: 2, arquivo: dir + "/41c_voz_do_computador.png")
        FalaServico.shared.exemploParaCaptura(instalado: false)
        fotografar(FalaCentral().padding(20).frame(width: 760, alignment: .leading), tamanho: NSSize(width: 760, height: 720),
                   espera: 2, arquivo: dir + "/41d_voz_do_computador_sem_motor.png")
        // Captura: página do módulo, a pilha de prévias e o anotador — imagens desenhadas em código
        // (nada da tela do Hugo é fotografado; os atalhos não são registrados)
        reset(s)
        s.tasks = crew
        s.focusId = crew[0].id
        CapturaServico.shared.exemploParaCaptura()
        fotografar(PaginaModulo(modulo: CapturaModulo.shared), tamanho: NSSize(width: 760, height: 1330), espera: 2.5,
                   arquivo: dir + "/42_central_captura.png")
        // Vídeo: página do módulo com o motor instalado (projetos, renderização, prontos) e sem ele
        VideoServico.shared.exemploParaCaptura()
        fotografar(PaginaModulo(modulo: VideoModulo.shared), tamanho: NSSize(width: 760, height: 1180), espera: 2,
                   arquivo: dir + "/44_central_video.png")
        VideoServico.shared.exemploParaCaptura(instalado: false)
        fotografar(PaginaModulo(modulo: VideoModulo.shared), tamanho: NSSize(width: 760, height: 520), espera: 2,
                   arquivo: dir + "/44b_central_video_sem_motor.png")
        // Comando universal: o painel com resultados de exemplo de cada fonte, e a página dele
        for cena in ComandoExemplo.cenas where filtro.map({ cena.arquivo.contains($0) }) ?? true {
            cena.preparar()
            fotografar(ComandoExemplo.palco, tamanho: NSSize(width: 760, height: cena.altura), espera: 1.2,
                       arquivo: dir + "/" + cena.arquivo)
        }
        fotografar(PaginaModulo(modulo: ComandoModulo.shared), tamanho: NSSize(width: 760, height: 1180), espera: 1.5,
                   arquivo: dir + "/45_central_comando.png")
        PilhaPrevias.shared.exemploParaCaptura(Array(CapturaServico.shared.recentes.prefix(3).reversed()))
        fotografar(ZStack(alignment: .bottomTrailing) {
            LinearGradient(colors: [Color(red: 0.20, green: 0.24, blue: 0.38), Color(red: 0.10, green: 0.11, blue: 0.16)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            PilhaView().padding(8)
        }, tamanho: NSSize(width: 460, height: 460), espera: 2.5, arquivo: dir + "/42b_captura_previa.png")
        if let alvo = CapturaServico.shared.recentes.last(where: { !$0.anotada && $0.url.lastPathComponent.contains("Captura") }),
           let img = CapturaExemplo.imagem(.recado) {
            fotografar(AnotarView(estado: EstadoAnotar(captura: alvo, imagem: img, anotacoes: CapturaExemplo.anotacoes(para: img))),
                       tamanho: NSSize(width: 932, height: 540), espera: 1.5, arquivo: dir + "/42c_captura_anotar.png")
        }
        CapturaServico.shared.exemploParaCaptura(comProblemas: true)
        fotografar(PaginaModulo(modulo: CapturaModulo.shared), tamanho: NSSize(width: 760, height: 1330), espera: 2.5,
                   arquivo: dir + "/42d_central_captura_problemas.png")
        // Gravação de tela: a página com a lista de exemplo, gravando, e a prévia do vídeo (nada é gravado)
        CapturaServico.shared.exemploParaCaptura()
        GravacaoServico.shared.exemploParaCaptura()
        fotografar(PaginaModulo(modulo: CapturaModulo.shared), tamanho: NSSize(width: 760, height: 2250), espera: 2.5,
                   arquivo: dir + "/42f_central_gravacao.png")
        GravacaoServico.shared.exemploParaCaptura(gravando: true)
        fotografar(GravacaoGravar().padding(20), tamanho: NSSize(width: 760, height: 200), espera: 1.5,
                   arquivo: dir + "/42g_gravacao_gravando.png")
        if let g = GravacaoServico.shared.gravacoes.first {
            PreviaGravacao.shared.exemploParaCaptura(g)
            fotografar(PreviaGravacaoView().background(Color(red: 0.14, green: 0.16, blue: 0.24)),
                       tamanho: NSSize(width: 300, height: 300), espera: 1.5, arquivo: dir + "/42h_gravacao_previa.png")
        }
        // Editar uma gravação: o menu que pergunta de qual projeto é o vídeo (projetos de exemplo)
        ProjetosCrew.shared.exemploParaCaptura()
        fotografar(MenuCrew.vistaParaCaptura(EscolhaProjetoVideo.itens { _ in }).padding(24)
                    .background(Color(red: 0.14, green: 0.16, blue: 0.24)),
                   tamanho: NSSize(width: 420, height: 330), espera: 1, arquivo: dir + "/42j_gravacao_editar_projeto.png")
        reset(s)
        if let ajustesAntes { UserDefaults.standard.setPersistentDomain(ajustesAntes, forName: dominio) }
        UserDefaults.standard.synchronize()
        NSApp.terminate(nil)
    }

    // MARK: App do Crew

    /// As telas do app do Crew (`AppCrewView`): início, vazio, aprovação, conversa, pergunta,
    /// projetos, histórico, terminal e "abrindo". Nada consulta Xirp nem tmux.
    private static func appDoCrew(_ s: AppState, _ dir: String) {
        let tamanho = NSSize(width: 1180, height: 760)
        func foto(_ arquivo: String, _ cena: NavegacaoCrew.Cena, _ t: NSSize? = nil) {
            fotografar(AppCrewView(cena: cena), tamanho: t ?? tamanho, espera: 3, arquivo: dir + "/" + arquivo)
        }
        func exemplo() -> [AgentTask] {
            var e = crew
            e[0].transcriptPath = transcript()
            e[0].lastEvent = Date().addingTimeInterval(-40)
            e[1].lastEvent = Date().addingTimeInterval(-600)
            e[2].lastEvent = Date().addingTimeInterval(-90)
            e[3].parada = true
            return e
        }
        let aprovacao = ApprovalInfo(sessionId: "exemplo1", tool: "Bash", command: "scripts/instalar.sh",
                                     purpose: "Compilar e instalar o Crew para você testar no notch")

        // Sem sessão nenhuma: só o Homie e o campo
        reset(s)
        foto("40_app_vazio.png", .init())

        // Início com sessões abertas, uma pedindo resposta (vira atalho embaixo do campo)
        reset(s)
        s.tasks = exemplo(); s.focusId = s.tasks[0].id
        s.pendingApprovals["exemplo1"] = aprovacao
        foto("40a_app_inicio.png", .init())

        // Sessão pedindo permissão: o cartão preso acima do campo
        foto("40b_app_aprovacao.png", .init(selecao: .sessao(s.tasks[0].id)))
        // As mesmas duas telas no menor tamanho da janela (900×600): nada pode cortar
        let minimo = NSSize(width: 900, height: 600)
        foto("40i_app_minimo_inicio.png", .init(), minimo)
        foto("40j_app_minimo_aprovacao.png", .init(selecao: .sessao(s.tasks[0].id)), minimo)

        // Conversa, sem pendência
        s.pendingApprovals = [:]
        foto("40c_app_conversa.png", .init(selecao: .sessao(s.tasks[0].id)))
        // Conversa fiel ao terminal: a mensagem com texto colado e imagens (a que sumia), os passos
        // das ferramentas com o turno em andamento e, se pedido, um transcript de verdade
        // (CREW_CAPTURA_TRANSCRIPT=<arquivo.jsonl>, só leitura).
        let alta = NSSize(width: 1180, height: 1180)
        s.tasks[0].state = .idle
        s.tasks[0].transcriptPath = ConversaExemplo.colada()
        foto("40p_app_conversa_colada.png", .init(selecao: .sessao(s.tasks[0].id)), alta)
        s.tasks[0].state = .working
        s.tasks[0].transcriptPath = ConversaExemplo.passos()
        foto("40q_app_conversa_passos.png", .init(selecao: .sessao(s.tasks[0].id)), alta)
        if let real = ProcessInfo.processInfo.environment["CREW_CAPTURA_TRANSCRIPT"], FileManager.default.fileExists(atPath: real) {
            s.tasks[0].state = .idle
            s.tasks[0].transcriptPath = real
            foto("40r_app_conversa_real.png", .init(selecao: .sessao(s.tasks[0].id)), NSSize(width: 1180, height: 1500))
        }
        // Entregáveis de uma resposta (`--so entregavel`): tabela com coluna de lista, tabela de
        // números, tabela larga, blocos de código com caminhos e resposta longa com títulos.
        entregaveis(s, dir, tamanho: tamanho, foto)
        s.tasks[0].state = .working
        s.tasks[0].transcriptPath = transcript()
        // Tela dividida: duas e três sessões lado a lado
        let ids = SessoesCrew.todas(s).map(\.id)
        if ids.count >= 2 {
            foto("40k_app_dividido.png", .init(selecao: .sessao(ids[0]), paineis: Array(ids.prefix(2))))
            foto("40l_app_dividido3.png", .init(selecao: .sessao(ids[1]), paineis: Array(ids.prefix(3))))
            // Grade em duas colunas: quatro sessões em 2 × 2
            foto("40n_app_grade.png", .init(selecao: .sessao(ids[0]), paineis: Array(ids.prefix(4)), colunas: 2))
        }
        // Navegador do Crew na janela inteira (abas de exemplo; nenhuma página é carregada)
        NavegadorServico.shared.exemploParaCaptura()
        foto("40o_app_navegador.png", .init(selecao: .navegador))
        // O campo de endereço sugerindo: "git" completado e a lista (histórico de exemplo, nada da rede)
        NavegadorServico.shared.exemploParaCaptura(digitando: "git")
        foto("40p_app_navegador_sugestoes.png", .init(selecao: .navegador))
        NavegadorServico.shared.exemploParaCaptura()
        // Barra lateral recolhida, aparecendo por cima
        // (a preferência de verdade do Hugo volta ao que era depois da foto)
        let recolhidaAntes = UserDefaults.standard.object(forKey: "modulo.sessoes.lateralRecolhida")
        UserDefaults.standard.set(true, forKey: "modulo.sessoes.lateralRecolhida")
        foto("40m_app_lateral_espiando.png", .init(selecao: .sessao(s.tasks[0].id), espiando: true))
        UserDefaults.standard.set(recolhidaAntes, forKey: "modulo.sessoes.lateralRecolhida")

        // Pergunta com opções
        var pergunta = ApprovalInfo(sessionId: "exemplo1", tool: "AskUserQuestion", command: "Pergunta")
        pergunta.questions = [QuestionInfo(question: "Onde o aviso de sessão esperando deve aparecer?", header: "Aviso",
                                           options: ["Só na ilha", "Na ilha e no app do Crew", "Só no app do Crew"],
                                           multiSelect: false)]
        s.pendingApprovals["exemplo1"] = pergunta
        s.tasks[0].state = .question
        foto("40d_app_pergunta.png", .init(selecao: .sessao(s.tasks[0].id)))
        s.pendingApprovals = [:]
        s.tasks[0].state = .working

        // Aba Projetos (o início fica à direita, pronto para o projeto escolhido)
        foto("40e_app_projetos.png", .init(aba: .projetos))

        // Painel do projeto (clique na linha do projeto): uma foto por aba. Lê a pasta do Crew de
        // verdade (git, CLAUDE.md, MCP, memórias), só leitura.
        let raizCrew = FileManager.default.homeDirectoryForCurrentUser.path + "/dev/crew"
        let alto = NSSize(width: 1180, height: 1100)
        foto("43_projeto_geral.png", .init(aba: .projetos, selecao: .projeto(raizCrew)), alto)
        foto("43b_projeto_detalhes.png", .init(aba: .projetos, selecao: .projeto(raizCrew), abaDoProjeto: .detalhes), alto)
        foto("43c_projeto_sessoes.png", .init(aba: .projetos, selecao: .projeto(raizCrew), abaDoProjeto: .sessoes), alto)
        foto("43d_projeto_claude.png", .init(aba: .projetos, selecao: .projeto(raizCrew), abaDoProjeto: .claude), alto)
        foto("43e_projeto_avisos.png", .init(aba: .projetos, selecao: .projeto(raizCrew), abaDoProjeto: .avisos), alto)

        // Aba Histórico, com uma conversa guardada aberta
        foto("40f_app_historico.png", .init(aba: .historico, selecao: .guardada(SessaoGuardada.exemplos[0])))

        // Sessão do motor do Crew ainda sem conversa: o terminal aparece sozinho
        s.tasks[2].steps = []
        s.tasks[2].state = .idle
        foto("40g_app_terminal.png", .init(selecao: .sessao(s.tasks[2].id), terminal: true))

        // Sessão recém-pedida, ainda não chegou pelos hooks
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        foto("40h_app_abrindo.png", .init(abrindo: SessaoAbrindo(
            sessionId: "captura", caminho: home + "/dev/crew", projeto: "crew",
            conhecidas: Set(s.tasks.map(\.id)), doCrew: true)))

        // Setores (`--so setor`): a barra de setores com o Comando na tela e uma tela por setor,
        // com dados de exemplo (nada é gravado, lido de fora nem executado)
        s.pendingApprovals["exemplo1"] = aprovacao
        // (com a barra lateral à vista; a preferência do Hugo volta ao que era depois das fotos)
        UserDefaults.standard.set(false, forKey: "modulo.sessoes.lateralRecolhida")
        foto("45_setor_comando.png", .init())
        RotinasServico.shared.exemploParaCaptura()
        foto("45a_setor_comando_rotinas.png", .init(selecao: .ferramenta(RotinasModulo.shared.id)))
        foto("45b_setor_mesa_navegador.png", .init(selecao: .navegador))
        foto("45c_setor_mesa_arquivos.png", .init(selecao: .ferramenta(Setores.arquivos)))
        VideoServico.shared.exemploParaCaptura()
        foto("45d_setor_estudio.png", .init(selecao: .ferramenta(VideoModulo.shared.id)))
        foto("45e_setor_maquina.png", .init(selecao: .ferramenta(SistemaModulo.shared.id)))
        DiarioServico.shared.exemploParaCaptura()
        foto("45f_setor_dia.png", .init(selecao: .ferramenta(DiarioModulo.shared.id)))
        foto("45g_setor_conexoes.png", .init(selecao: .ferramenta(AutomacaoModulo.shared.id)))
        foto("45h_setor_minimo.png", .init(selecao: .ferramenta(DiscoModulo.shared.id)), minimo)
        // A sessão que acompanha o Hugo, ao lado da tela de outro setor
        foto("45j_setor_sessao_ao_lado.png", .init(selecao: .ferramenta(VideoModulo.shared.id), aoLado: s.tasks[0].id))
        // Arquivo aberto de dentro do Crew: por cima da janela, não em outro app
        fotografar(VisorArquivo(url: URL(fileURLWithPath: dir + "/45_setor_comando.png")) {}.background(Tema.fundo).environment(\.colorScheme, .dark),
                   tamanho: NSSize(width: 1180, height: 760), espera: 2, arquivo: dir + "/45m_setor_visor_arquivo.png")
        // Barra recolhida: a tela inteira para o setor, e a barra aparecendo por cima
        UserDefaults.standard.set(true, forKey: "modulo.sessoes.lateralRecolhida")
        foto("45k_setor_lateral_recolhida.png", .init(selecao: .ferramenta(SistemaModulo.shared.id)))
        foto("45l_setor_lateral_espiando.png", .init(selecao: .ferramenta(SistemaModulo.shared.id), espiando: true))
        UserDefaults.standard.set(recolhidaAntes, forKey: "modulo.sessoes.lateralRecolhida")
        fotografar(CentralView(pagina: .modulo(SistemaModulo.shared.id)), tamanho: NSSize(width: 1000, height: 700), espera: 2,
                   arquivo: dir + "/45i_setor_ajustes.png")
        reset(s)
    }

    // MARK: Dados de exemplo

    private static func session(_ n: Int, _ title: String, project: String, color: String, state: BotState,
                                steps: [String] = [], delivery: String? = nil, prompt: String? = nil) -> AgentTask {
        var t = AgentTask(id: "sessao_exemplo\(n)", name: project, color: color, state: state, steps: steps, source: .claudeCode)
        t.sessionId = "exemplo\(n)"
        // Pasta do projeto: as sessões se agrupam por ela, como as de verdade
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        t.sessionCwd = ["crew": home + "/dev/crew", "loja": home + "/dev/loja"][project] ?? home + "/dev"
        t.title = title
        t.delivery = delivery
        t.lastPrompt = prompt
        t.stepIndex = max(0, steps.count - 1)
        return t
    }

    private static func entregaveis(_ s: AppState, _ dir: String, tamanho: NSSize, _ foto: (String, NavegacaoCrew.Cena, NSSize?) -> Void) {
        let cwd = s.tasks[0].sessionCwd
        s.tasks[0].state = .idle
        s.tasks[0].sessionCwd = ConversaExemplo.pastaExemplo()
        let cena = NavegacaoCrew.Cena(selecao: .sessao(s.tasks[0].id))
        s.tasks[0].transcriptPath = ConversaExemplo.tabelaLista()
        foto("40s_app_entregavel_tabela.png", cena, NSSize(width: 1180, height: 1500))
        s.tasks[0].transcriptPath = ConversaExemplo.tabelaNumeros()
        foto("40t_app_entregavel_numeros.png", cena, NSSize(width: 1180, height: 900))
        s.tasks[0].transcriptPath = ConversaExemplo.codigo()
        foto("40u_app_entregavel_codigo.png", cena, NSSize(width: 1180, height: 1000))
        s.tasks[0].transcriptPath = ConversaExemplo.longa()
        foto("40v_app_entregavel_longa.png", cena, NSSize(width: 1180, height: 1200))
        s.tasks[0].transcriptPath = ConversaExemplo.tabelaLarga()
        foto("40w_app_entregavel_larga.png", cena, NSSize(width: 1180, height: 1100))
        // Cabeçalho preso: a mesma tabela de 17 linhas com a conversa rolada até o meio dela.
        VistaTabela.rolarNaCaptura = 620
        s.tasks[0].transcriptPath = ConversaExemplo.tabelaLista()
        foto("40y_app_entregavel_cabecalho_preso.png", cena, NSSize(width: 1180, height: 760))
        VistaTabela.rolarNaCaptura = nil
        // Na grade (painel estreito): a barra de ações vira só ícones e a tabela rola para o lado.
        let ids = s.tasks.filter { !$0.isIntegration }.map(\.id)
        if ids.count >= 2 {
            s.tasks[0].transcriptPath = ConversaExemplo.tabelaLarga()
            foto("40z_app_entregavel_grade.png", .init(selecao: .sessao(ids[0]), paineis: Array(ids.prefix(2))), NSSize(width: 1180, height: 760))
        }
        // A tabela ampliada para a janela inteira (o mesmo conteúdo da janela filha).
        if case .tabela(let t)? = BlocosResposta.ler(ConversaExemplo.textoTabelaLarga).first(where: { if case .tabela = $0 { return true } else { return false } }) {
            fotografar(TabelaAmpliadaView(tabela: t, titulo: "Estoque completo", fechar: {}), tamanho: tamanho, espera: 1.5,
                       arquivo: dir + "/40x_app_entregavel_ampliada.png")
        }
        if ProcessInfo.processInfo.environment["CREW_MEDIR"] != nil { medirEntregaveis() }
        s.tasks[0].sessionCwd = cwd
    }

    /// Tempo de montar uma resposta com tabela grande, na largura da conversa: ler o markdown,
    /// montar e medir o texto corrido e montar e medir a tabela (tudo o que acontece antes de desenhar).
    private static func medirEntregaveis() {
        for n in [17, 100, 300] {
            let texto = ConversaExemplo.textoTabelaGrande(linhas: n)
            var tempos: [Double] = []
            for _ in 0..<5 {
                let t0 = CFAbsoluteTimeGetCurrent()
                for bloco in BlocosResposta.ler(texto) {
                    if case .tabela(let t) = bloco {
                        let vista = VistaTabela()
                        let modelo = ModeloTabela(t, tamanho: 13, pasta: nil)
                        vista.definir(modelo, linhas: modelo.linhas(filtro: "", ordenacao: nil), ordenacao: nil)
                        vista.preparar(disponivel: 736)
                    } else {
                        let v = VistaTexto.nova()
                        v.mostrar(TextoRico.montar([bloco], tamanho: 14, cor: .white, entrelinha: 4, pasta: nil))
                        _ = v.altura(para: 736)
                    }
                }
                tempos.append((CFAbsoluteTimeGetCurrent() - t0) * 1000)
            }
            print(String(format: "MEDIDA depois · tabela de %d linhas × 6 colunas: %.1f ms (mediana de 5)", n, tempos.sorted()[2]))
        }
    }

    private static var crew: [AgentTask] {
        [
            session(1, "Integração do notch com Claude Code", project: "crew", color: "#FF7A59", state: .working,
                    steps: ["Lendo HookServer.swift", "Editando IslandViewContent.swift", "Compila e instala o app"]),
            session(2, "Validação de fechamentos", project: "loja", color: "#34D399", state: .idle,
                    delivery: "Fechamentos de setembro conferidos: 3 fornecedores com diferença."),
            session(3, "Motion analysis", project: "dev", color: "#A78BFA", state: .working),
            session(4, "Automação de reposição", project: "loja", color: "#34D399", state: .idle),
        ]
    }

    private static func reset(_ s: AppState) {
        s.tasks = []
        s.focusId = nil
        s.pendingApprovals = [:]
        s.stateOverride = nil
        s.view = .overview
        s.mode = .expanded
        s.chatSelection = nil
        s.chatSelectionSet = false
        s.chatHeight = AppState.chatMinHeight
        s.searchResult = nil
        s.droppedFile = nil
        s.promptContext = nil
        MediaService.shared.simular(nil, capa: nil)
        Arbitro.shared.limparTudo()
    }

    /// Conversa de exemplo (JSONL no formato do Claude Code), para as telas que leem transcript.
    static func transcript() -> String {
        let path = NSTemporaryDirectory() + "crew-captura.jsonl"
        let linhas: [[String: Any]] = [
            ["type": "user", "message": ["role": "user", "content": "separa as sessões no notch, uma por sessão"]],
            ["type": "assistant", "message": ["role": "assistant", "content": [["type": "text", "text": "Vou ver como o HookServer trata os eventos."]]]],
            ["type": "assistant", "message": ["role": "assistant", "content": [["type": "text", "text":
                "Pronto. Cada sessão virou um **Homie** próprio:\n\n| Sessão | Estado |\n|---|---|\n| Integração do notch | trabalhando |\n| Validação de fechamentos | entregou |\n\nAprovações e perguntas aparecem por sessão."]]]],
            ["type": "user", "message": ["role": "user", "content": "e se eu tiver mais de uma esperando?"]],
            ["type": "assistant", "message": ["role": "assistant", "content": [["type": "text", "text":
                "Cada uma espera na sua pílula. Ao responder uma, a ilha pula para a próxima."]]]],
        ]
        let txt = linhas.compactMap { try? JSONSerialization.data(withJSONObject: $0) }
            .compactMap { String(data: $0, encoding: .utf8) }.joined(separator: "\n")
        try? txt.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    private static func capa() -> NSImage {
        let img = NSImage(size: NSSize(width: 300, height: 300))
        img.lockFocus()
        NSGradient(colors: [NSColor(red: 0.23, green: 0.18, blue: 0.36, alpha: 1), NSColor(red: 0.76, green: 0.25, blue: 0.05, alpha: 1)])!
            .draw(in: NSRect(x: 0, y: 0, width: 300, height: 300), angle: -45)
        img.unlockFocus()
        return img
    }

    // MARK: Cenas

    private static func scenes() -> [Scene] {
        let base: CGFloat = 214
        return [
            Scene(file: "01_peek", height: 60) { s in
                s.mode = .compact
                MediaService.shared.simular(NowPlaying(player: .spotify, title: "Apaga a Luz", artist: "Nicolas Candido", album: "",
                                                       isPlaying: true, duration: 216, position: 30, positionAt: .now, artworkURL: nil), capa: capa())
            },
            Scene(file: "02_compact", height: 60) { s in
                s.tasks = crew; s.focusId = crew[0].id; s.mode = .compact
            },
            Scene(file: "03_overview", height: base) { s in
                s.tasks = crew; s.focusId = crew[0].id; s.view = .overview
            },
            // Ilha fechada com música tocando e o indicador de CPU lado a lado
            Scene(file: "35_compacta_musica_cpu", height: 60, wait: 4) { s in
                s.tasks = crew; s.focusId = crew[0].id; s.mode = .compact
                SistemaServico.shared.assinar("captura", [.rapido])
                Arbitro.shared.publicar(Sinal(id: "sistema.indicador", lugar: .canto, prioridade: .indicador,
                                              conteudo: AnyView(IndicadorCanto(tipo: .cpu))))
                MediaService.shared.simular(NowPlaying(player: .spotify, title: "Lama No Copo", artist: "Matuê", album: "",
                                                       isPlaying: true, duration: 251, position: 172, positionAt: .now, artworkURL: nil), capa: capa())
            },
            // Fila de atenção: uma pedindo Bash, uma que entregou, uma trabalhando, duas paradas
            Scene(file: "34_fila", height: base) { s in
                var t = crew
                t[1].pillBadge = .finished; t[1].lastEvent = Date().addingTimeInterval(-120)
                t[2].steps = ["Editando TapApp.swift"]; t[2].stepIndex = 0; t[2].lastEvent = Date().addingTimeInterval(-720)
                t[3].state = .approval; t[3].lastEvent = Date().addingTimeInterval(-180)
                var p1 = session(5, "Lista de insumos", project: "loja", color: "#34D399", state: .idle); p1.parada = true
                var p2 = session(6, "Site do Crew", project: "crew", color: "#FF7A59", state: .idle); p2.parada = true
                s.tasks = t + [p1, p2]; s.focusId = t[0].id; s.view = .overview
                var a = ApprovalInfo(sessionId: t[3].sessionId!, tool: "Bash", command: "npm run build")
                a.purpose = "Compilar"
                s.pendingApprovals = [t[3].sessionId!: a]
                AudioServico.shared.iniciar()
                MediaService.shared.simular(NowPlaying(player: .spotify, title: "Lama No Copo", artist: "Matuê", album: "",
                                                       isPlaying: true, duration: 251, position: 172, positionAt: .now, artworkURL: nil), capa: capa())
            },
            Scene(file: "04_approval", height: base) { s in
                var t = crew; t[1].state = .approval; s.tasks = t; s.focusId = t[1].id
                var a = ApprovalInfo(sessionId: "exemplo2", tool: "Bash", command: "psql -v ON_ERROR_STOP=1 -1 < migrations/042_leitura.sql")
                a.purpose = "Aplicar a migration de leitura no banco"
                s.pendingApprovals = ["exemplo2": a]; s.view = .approval
            },
            Scene(file: "05_question", height: base) { s in
                var t = crew; t[2].state = .question; s.tasks = t; s.focusId = t[2].id
                var a = ApprovalInfo(sessionId: "exemplo3", tool: "AskUserQuestion", command: "Pergunta")
                a.questions = [QuestionInfo(question: "Qual cor de boné para o Homie?", header: "Boné",
                                            options: ["Grafite", "Cinza médio", "Vermelho"], multiSelect: false)]
                s.pendingApprovals = ["exemplo3": a]; s.view = .question
            },
            Scene(file: "06_error", height: base) { s in
                var t = crew; t[0].state = .error; t[0].delivery = "O build falhou: 2 erros em IslandViewContent.swift."
                s.tasks = t; s.focusId = t[0].id; s.view = .error
            },
            Scene(file: "07_finished", height: base) { s in
                var t = crew; t[1].state = .finished; s.tasks = t; s.focusId = t[1].id; s.view = .finished
            },
            Scene(file: "08_confused", height: base) { s in
                s.tasks = crew; s.focusId = crew[0].id; s.stateOverride = .dizzy; s.view = .confused
            },
            Scene(file: "09_upload_drag_over", height: base) { s in
                s.tasks = crew; s.focusId = crew[0].id; s.view = .upload; s.fileDragOver = true
            },
            Scene(file: "10_uploading", height: base) { s in
                s.tasks = crew; s.focusId = crew[0].id
                s.droppedFile = DroppedFile(url: URL(fileURLWithPath: "/tmp/fechamento-setembro.pdf"), name: "fechamento-setembro.pdf")
                s.uploadProgress = 0.55; s.view = .uploading
            },
            Scene(file: "11_choose", height: 230) { s in
                s.tasks = crew; s.focusId = crew[0].id
                s.droppedFile = DroppedFile(url: URL(fileURLWithPath: "/tmp/fechamento-setembro.pdf"), name: "fechamento-setembro.pdf")
                s.view = .choose
            },
            Scene(file: "12_mail", height: 290) { s in
                s.tasks = crew; s.focusId = crew[0].id
                s.droppedFile = DroppedFile(url: URL(fileURLWithPath: "/tmp/fechamento-setembro.pdf"), name: "fechamento-setembro.pdf")
                s.view = .mail
            },
            Scene(file: "14_searching", height: base) { s in
                s.tasks = crew; s.focusId = crew[0].id; s.stateOverride = .searching; s.view = .searching
            },
            Scene(file: "15_result", height: base) { s in
                s.tasks = crew; s.focusId = crew[0].id
                s.searchResult = SearchResult(title: "Churrascarias perto daqui", items: [
                    ResultItem(label: "Churrascaria do Centro", detail: "Centro · aberto até 23h", url: nil),
                    ResultItem(label: "Grelha da Vila", detail: "Vila Nova · aberto até 22h", url: nil),
                ], note: nil)
                s.view = .result
            },
            Scene(file: "13_prompt_window_attached", height: 440, wait: 7) { s in
                var t = crew; t[0].transcriptPath = transcript(); t[0].state = .idle
                s.tasks = t; s.focusId = t[0].id; s.openChat(t[0].id); s.chatHeight = 380
            },
            Scene(file: "16_empty", height: base, wait: 4) { s in
                s.view = .empty
            },
            Scene(file: "17_media", height: base, wait: 4) { s in
                s.tasks = crew; s.focusId = crew[0].id
                MediaService.shared.simular(NowPlaying(player: .spotify, title: "Apaga a Luz", artist: "Nicolas Candido", album: "Single",
                                                       isPlaying: true, duration: 216, position: 30, positionAt: .now, artworkURL: nil), capa: capa())
                s.view = .media
            },
            // Ilha fechada com sinais do árbitro: barra (volume, aviso) e canto (indicador)
            Scene(file: "20_barra_volume", height: 110) { s in
                s.tasks = crew; s.focusId = crew[0].id; s.mode = .compact
                let n = NivelService.Nivel(tipo: .volume, valor: 0.62)
                Arbitro.shared.publicar(Sinal(id: "nivel", lugar: .barra, prioridade: .hud, homie: .fones(0.62),
                                              conteudo: AnyView(NivelBarra(nivel: n, compacta: false))))
            },
            Scene(file: "21_barra_aviso_bateria", height: 110) { s in
                s.tasks = crew; s.focusId = crew[0].id; s.mode = .compact
                Arbitro.shared.publicar(Sinal(id: "sistema.alerta", lugar: .barra, prioridade: .alerta,
                                              conteudo: AnyView(AvisoBarra(icone: "battery.25percent", texto: "Bateria em 9% — ligue na tomada (24 min)",
                                                                           cor: Color(hex: "#F4505E")))))
            },
            // Texto da tela (OCR) copiado: aviso passageiro da Captura na barra
            Scene(file: "42e_barra_captura_texto", height: 110) { s in
                s.tasks = crew; s.focusId = crew[0].id; s.mode = .compact
                Arbitro.shared.publicar(Sinal(id: "captura.aviso", lugar: .barra, prioridade: .hud,
                                              conteudo: AnyView(AvisoCaptura(icone: "text.viewfinder", texto: "Texto copiado: Reunião de quinta Levar o…",
                                                                             cor: Color(hex: "#34D399"), abre: false))))
            },
            Scene(file: "42i_barra_gravando", height: 110) { s in
                s.tasks = crew; s.focusId = crew[0].id; s.mode = .compact
                Arbitro.shared.publicar(Sinal(id: GravacaoServico.sinal, lugar: .barra, prioridade: .alerta, clicavel: true,
                                              conteudo: AnyView(SinalGravando(desde: Date().addingTimeInterval(-83)))))
            },
            Scene(file: "22_canto_indicador_cpu", height: 60, wait: 4) { s in
                s.tasks = crew; s.focusId = crew[0].id; s.mode = .compact
                SistemaServico.shared.assinar("captura", [.rapido])
                Arbitro.shared.publicar(Sinal(id: "sistema.indicador", lugar: .canto, prioridade: .indicador,
                                              conteudo: AnyView(IndicadorCanto(tipo: .cpu))))
            },
            // Grade de módulos (botão de grade no cabeçalho, ao lado da câmera)
            Scene(file: "33_grade_modulos", height: base) { s in
                s.tasks = crew; s.focusId = crew[0].id
                s.view = .modulos
            },
            // Módulo Sistema: leituras de verdade deste Mac
            Scene(file: "18_sistema", height: base, wait: 5) { s in
                s.tasks = crew; s.focusId = crew[0].id
                s.moduloAberto = SistemaModulo.shared.id
                s.view = .modulo
            },
            // Monitor de atividade na ilha expandida (botão do canto da aba Sistema): cada aba,
            // e o detalhe com confirmação (Finder, nada é encerrado) e um processo do sistema
            Scene(file: "18m1_monitor_cpu", height: 480, wait: 6) { s in
                s.tasks = crew; s.focusId = crew[0].id
                MonitorAtividade.captura = (.cpu, nil, nil)
                s.moduloAberto = SistemaModulo.shared.id
                s.view = .modulo
                s.alturaAba = SistemaAba.alturaMonitor
            },
            Scene(file: "18m2_monitor_memoria", height: 480, wait: 6) { s in
                s.tasks = crew; s.focusId = crew[0].id
                MonitorAtividade.captura = (.memoria, nil, nil)
                s.moduloAberto = SistemaModulo.shared.id
                s.view = .modulo
                s.alturaAba = SistemaAba.alturaMonitor
            },
            Scene(file: "18m3_monitor_energia", height: 480, wait: 6) { s in
                s.tasks = crew; s.focusId = crew[0].id
                MonitorAtividade.captura = (.energia, nil, nil)
                s.moduloAberto = SistemaModulo.shared.id
                s.view = .modulo
                s.alturaAba = SistemaAba.alturaMonitor
            },
            Scene(file: "18m4_monitor_disco", height: 480, wait: 6) { s in
                s.tasks = crew; s.focusId = crew[0].id
                MonitorAtividade.captura = (.disco, nil, nil)
                s.moduloAberto = SistemaModulo.shared.id
                s.view = .modulo
                s.alturaAba = SistemaAba.alturaMonitor
            },
            Scene(file: "18m5_monitor_rede", height: 480, wait: 6) { s in
                s.tasks = crew; s.focusId = crew[0].id
                MonitorAtividade.captura = (.rede, nil, nil)
                s.moduloAberto = SistemaModulo.shared.id
                s.view = .modulo
                s.alturaAba = SistemaAba.alturaMonitor
            },
            Scene(file: "18m6_monitor_confirmar", height: 480, wait: 6) { s in
                s.tasks = crew; s.focusId = crew[0].id
                let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first?.processIdentifier
                MonitorAtividade.captura = (.cpu, finder, false)
                s.moduloAberto = SistemaModulo.shared.id
                s.view = .modulo
                s.alturaAba = SistemaAba.alturaMonitor
            },
            Scene(file: "18m7_monitor_sistema", height: 480, wait: 6) { s in
                s.tasks = crew; s.focusId = crew[0].id
                MonitorAtividade.captura = (.memoria, LeitorMonitor.pid(chamado: "WindowServer"), nil)
                s.moduloAberto = SistemaModulo.shared.id
                s.view = .modulo
                s.alturaAba = SistemaAba.alturaMonitor
            },
            // Módulo Modelos: este Mac de verdade (vazio aqui), depois com dados de exemplo
            Scene(file: "20_modelos_este_mac", height: base, wait: 4) { s in
                s.tasks = crew; s.focusId = crew[0].id
                ModelosLigado.ligar()
                s.moduloAberto = ModelosModulo.shared.id
                s.view = .modulo
            },
            Scene(file: "21_modelos", height: base, wait: 3) { s in
                s.tasks = crew; s.focusId = crew[0].id
                ModelosLigado.ligar()
                ModelosServico.shared.simular(modelosExemplo, carregados: [
                    ModeloCarregado(nome: "qwen2.5-coder:14b", memoria: 10_900_000_000, memoriaGPU: 10_900_000_000,
                                    expiraEm: Date().addingTimeInterval(240)),
                ])
                s.moduloAberto = ModelosModulo.shared.id
                s.view = .modulo
            },
            // Módulo Áudio: dispositivos de verdade deste Mac (só lê; não troca nada)
            Scene(file: "23_audio", height: base, wait: 3) { s in
                s.tasks = crew; s.focusId = crew[0].id
                AudioServico.shared.iniciar()
                s.moduloAberto = AudioModulo.shared.id
                s.view = .modulo
            },
            // Módulo Agentes: worktrees de verdade deste Mac (só leitura)
            Scene(file: "23_agentes", height: base, wait: 5) { s in
                s.tasks = crew; s.focusId = crew[0].id
                s.moduloAberto = AgentesModulo.shared.id
                s.view = .modulo
            },
            // Módulo Uso: transcripts de verdade deste Mac (só lê)
            Scene(file: "31_uso", height: base, wait: 8) { s in
                s.tasks = crew; s.focusId = crew[0].id
                s.moduloAberto = UsoModulo.shared.id
                s.view = .modulo
            },
            Scene(file: "31b_barra_aviso_uso", height: 110) { s in
                s.tasks = crew; s.focusId = crew[0].id; s.mode = .compact
                Arbitro.shared.publicar(Sinal(id: "uso.alerta", lugar: .barra, prioridade: .alerta,
                                              conteudo: AnyView(AvisoUso(texto: "Claude Code hoje: US$ 52,10 · limite US$ 50,00"))))
            },
            Scene(file: "27_disco", height: base, wait: 2) { s in
                s.tasks = crew; s.focusId = crew[0].id
                DiscoServico.shared.exemploParaCaptura(confirmar: false)
                s.moduloAberto = DiscoModulo.shared.id
                s.view = .modulo
            },
            Scene(file: "27b_disco_confirmar", height: base, wait: 2) { s in
                s.tasks = crew; s.focusId = crew[0].id
                DiscoServico.shared.exemploParaCaptura(confirmar: true)
                s.moduloAberto = DiscoModulo.shared.id
                s.view = .modulo
            },
            // Volume por app: aba com apps de exemplo e o HUD na ilha fechada (não cria tap)
            Scene(file: "29_audio_apps", height: base, wait: 3) { s in
                s.tasks = crew; s.focusId = crew[0].id
                VolumePorApp.shared.exemploParaCaptura()
                s.moduloAberto = AudioModulo.shared.id
                s.view = .modulo
            },
            Scene(file: "30_barra_volume_app", height: 110) { s in
                s.tasks = crew; s.focusId = crew[0].id; s.mode = .compact
                let v = VolumePorApp.shared
                Arbitro.shared.publicar(Sinal(id: "audio.app", lugar: .barra, prioridade: .hud, homie: .fones(1),
                                              conteudo: AnyView(HUDVolumeApp(icone: v.icone("com.google.Chrome"), nome: "Google Chrome",
                                                                             volume: 1.6, mudo: false))))
            },
            // Segurar para falar: o texto chegando na barra da ilha fechada (exemplo, sem microfone)
            Scene(file: "41a_barra_voz", height: 110) { s in
                s.tasks = crew; s.focusId = crew[0].id; s.mode = .compact
                VozServico.shared.exemploParaCaptura()
                Arbitro.shared.publicar(Sinal(id: VozGlobal.sinal, lugar: .barra, prioridade: .hud, homie: .fones(0.7),
                                              conteudo: AnyView(BarraOuvindo())))
            },
            // Aviso de app apagado na ilha fechada (exemplo)
            Scene(file: "33a_barra_app_apagado", height: 110) { s in
                s.tasks = crew; s.focusId = crew[0].id; s.mode = .compact
                Arbitro.shared.publicar(Sinal(id: "apps.apagado", lugar: .barra, prioridade: .alerta,
                                              conteudo: AnyView(AvisoApagado(texto: "Notion foi apagado — 452 MB de sobras"))))
            },
            // Saída por app: aviso quando a saída fixa de um app desconecta
            Scene(file: "31_barra_saida_app", height: 110) { s in
                s.tasks = crew; s.focusId = crew[0].id; s.mode = .compact
                Arbitro.shared.publicar(Sinal(id: "audio.app.saida", lugar: .barra, prioridade: .alerta,
                                              conteudo: AnyView(AvisoSaidaApp(icone: VolumePorApp.shared.icone("com.spotify.client"),
                                                                              texto: "Spotify → MacBook Air (AirPods Pro desconectou)",
                                                                              cor: Color(hex: "#F5A524")))))
            },
            // Diário: o dia de hoje de verdade (só lê), um dia de exemplo e o aviso de pendência
            Scene(file: "34_diario_real", height: base, wait: 2) { s in
                s.tasks = crew; s.focusId = crew[0].id
                DiarioServico.shared.carregarParaCaptura()
                s.moduloAberto = DiarioModulo.shared.id
                s.view = .modulo
            },
            Scene(file: "34b_diario_exemplo", height: base, wait: 2) { s in
                s.tasks = crew; s.focusId = crew[0].id
                DiarioServico.shared.exemploParaCaptura()
                s.moduloAberto = DiarioModulo.shared.id
                s.view = .modulo
            },
            Scene(file: "34b2_tasks_hoje", height: base, wait: 2) { s in
                s.tasks = crew; s.focusId = crew[0].id
                DiarioServico.shared.exemploParaCaptura()
                DiarioServico.shared.segmento = .hoje
                s.moduloAberto = DiarioModulo.shared.id
                s.view = .modulo
            },
            Scene(file: "34b3_tasks_resumo", height: base, wait: 2) { s in
                s.tasks = crew; s.focusId = crew[0].id
                DiarioServico.shared.exemploParaCaptura()
                DiarioServico.shared.segmento = .resumo
                s.moduloAberto = DiarioModulo.shared.id
                s.view = .modulo
            },
            // Diário inteiro na ilha expandida: cada segmento (exemplo)
            Scene(file: "34x1_diario_expandido_pendencias", height: 480, wait: 2) { s in
                s.tasks = crew; s.focusId = crew[0].id
                DiarioServico.shared.exemploParaCaptura()
                DiarioServico.shared.segmento = .pendencias
                DiarioServico.shared.detalhe = nil
                s.moduloAberto = DiarioModulo.shared.id
                s.view = .modulo
                s.alturaAba = DiarioServico.alturaExpandida
            },
            Scene(file: "34x2_diario_expandido_hoje", height: 480, wait: 2) { s in
                s.tasks = crew; s.focusId = crew[0].id
                DiarioServico.shared.exemploParaCaptura()
                DiarioServico.shared.segmento = .hoje
                DiarioServico.shared.entradaAberta = DiarioServico.shared.hoje.entradas.first { $0.tipo == .nota }?.id
                s.moduloAberto = DiarioModulo.shared.id
                s.view = .modulo
                s.alturaAba = DiarioServico.alturaExpandida
            },
            Scene(file: "34x3_diario_expandido_resumo", height: 480, wait: 2) { s in
                s.tasks = crew; s.focusId = crew[0].id
                DiarioServico.shared.exemploParaCaptura()
                DiarioServico.shared.segmento = .resumo
                s.moduloAberto = DiarioModulo.shared.id
                s.view = .modulo
                s.alturaAba = DiarioServico.alturaExpandida
            },
            Scene(file: "34x4_diario_expandido_real", height: 480, wait: 2) { s in
                s.tasks = crew; s.focusId = crew[0].id
                DiarioServico.shared.carregarParaCaptura()
                DiarioServico.shared.segmento = .hoje
                DiarioServico.shared.entradaAberta = nil
                s.moduloAberto = DiarioModulo.shared.id
                s.view = .modulo
                s.alturaAba = DiarioServico.alturaExpandida
            },
            Scene(file: "34e_diario_detalhe", height: base, wait: 2) { s in
                s.tasks = crew; s.focusId = crew[0].id
                DiarioServico.shared.exemploParaCaptura()
                DiarioServico.shared.detalhe = DiarioServico.shared.abertas.first?.id
                s.moduloAberto = DiarioModulo.shared.id
                s.view = .modulo
            },
            Scene(file: "34c_barra_aviso_diario", height: 110) { s in
                s.tasks = crew; s.focusId = crew[0].id; s.mode = .compact
                Arbitro.shared.publicar(Sinal(id: "diario.aviso", lugar: .barra, prioridade: .alerta,
                                              conteudo: AnyView(AvisoDiario(acao: "planilha pro Rafa", quando: "12:00 · em 15 min",
                                                                            origem: "você anotou às 11:40", cor: Color(hex: "#F5A524")))))
            },
            Scene(file: "34d_barra_resumo_diario", height: 110) { s in
                s.tasks = crew; s.focusId = crew[0].id; s.mode = .compact
                Arbitro.shared.publicar(Sinal(id: "diario.resumo", lugar: .barra, prioridade: .alerta,
                                              conteudo: AnyView(AvisoResumoPronto())))
            },
            // Aviso do Áudio na ilha fechada (exemplo: fone conectou)
            Scene(file: "25_barra_aviso_audio", height: 110) { s in
                s.tasks = crew; s.focusId = crew[0].id; s.mode = .compact
                Arbitro.shared.publicar(Sinal(id: "audio.aviso", lugar: .barra, prioridade: .alerta,
                                              conteudo: AnyView(AvisoAudio(icone: "airpodspro", texto: "AirPods Pro conectou",
                                                                           cor: Color(hex: "#34D399")))))
            },
        ]
    }

    /// Liga o módulo Modelos só durante as capturas e devolve o ajuste como estava (o Crew
    /// de verdade lê o mesmo UserDefaults).
    @MainActor private enum ModelosLigado {
        static let chave = Ajustes.chave(ModelosModulo.shared.id, "ligado")
        static var antes: Any??
        static func ligar() {
            if antes == nil { antes = .some(UserDefaults.standard.object(forKey: chave)) }
            Registro.shared.ligar(ModelosModulo.shared.id, true)
        }
        static func restaurar() {
            guard let a = antes else { return }
            Registro.shared.ligar(ModelosModulo.shared.id, false)
            UserDefaults.standard.set(a, forKey: chave)
        }
    }

    private static var modelosExemplo: VarreduraModelos {
        let dia: TimeInterval = 86400
        func m(_ n: String, _ o: PoliticaModelos.Origem, _ t: Int64, _ r: Int64, _ d: Double) -> ModeloLocal {
            ModeloLocal(id: n, nome: n, origem: o, tamanho: t, recuperavel: r, modificado: Date().addingTimeInterval(-d * dia), arquivos: [])
        }
        var v = VarreduraModelos()
        v.modelos = [
            m("qwen2.5-coder:14b", .ollama, 8_990_000_000, 8_990_000_000, 3),
            m("lmstudio-community/gemma-3-12b-it-GGUF", .lmStudio, 8_150_000_000, 8_150_000_000, 21),
            m("llama3.1:8b", .ollama, 4_920_000_000, 0, 40),
            m("llama3.1:latest", .ollama, 4_920_000_000, 0, 40),
            m("nomic-embed-text:latest", .ollama, 274_000_000, 274_000_000, 95),
        ]
        v.totalDisco = 8_990_000_000 + 8_150_000_000 + 4_920_000_000 + 274_000_000
        v.pastas = PoliticaModelos.raizes()
        v.binarioOllama = "/opt/homebrew/bin/ollama"
        return v
    }

    // MARK: Foto

    private static func fotografar<V: View>(_ view: V, tamanho: NSSize, espera: TimeInterval, arquivo: String) {
        if let f = filtro, !(arquivo as NSString).lastPathComponent.contains(f) { return }
        let host = NSHostingView(rootView: view.frame(width: tamanho.width, height: tamanho.height)
            .background(Color(nsColor: .windowBackgroundColor)))
        host.frame = NSRect(origin: .zero, size: tamanho)
        let win = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        win.contentView = host
        win.isReleasedWhenClosed = false
        win.alphaValue = 0.01
        // Fora da área visível: a captura não pode aparecer na tela do Hugo
        win.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        win.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(espera))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: arquivo))
        win.orderOut(nil)
    }

    private static func shoot(_ scene: Scene, into dir: String) {
        let size = NSSize(width: 720, height: scene.height)
        let root = ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.16, green: 0.14, blue: 0.27), Color(red: 0.07, green: 0.07, blue: 0.10)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            IslandRootView().environmentObject(AppState.shared)
        }
        .frame(width: size.width, height: size.height)
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(origin: .zero, size: size)
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
                           styleMask: [.borderless], backing: .buffered, defer: false)
        win.contentView = host
        win.isReleasedWhenClosed = false
        win.alphaValue = 0.01
        // Fora da área visível: a captura não pode aparecer na tela do Hugo
        win.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        win.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(scene.wait))   // molas, animações e leituras assentam
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: dir + "/" + scene.file + ".png"))
        }
        win.orderOut(nil)
    }
}
