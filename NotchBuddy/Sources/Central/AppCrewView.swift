import SwiftUI
import AppKit

// O app do Crew: o gerente das sessões do Claude Code. À esquerda a barra lateral (sessões,
// projetos, histórico); à direita o início — o Homie e o campo para pedir uma sessão nova —
// ou a sessão escolhida, com a conversa, a aprovação pendente e o campo para falar com ela.
// As telas moram em `Modulos/Sessoes/Central/`; o visual, em `TemaCrew.swift`.

/// Sessão que o Hugo acabou de pedir e ainda não chegou pelos hooks.
struct SessaoAbrindo: Equatable {
    /// session_id do Claude Code (motor do Crew) ou o id que o Xirp devolveu.
    var sessionId: String?
    var caminho: String
    var projeto: String
    /// Tarefas que já existiam na hora do pedido: a nova é a que não está aqui.
    var conhecidas: Set<String>
    /// Aberta pelo motor do Crew (tmux): dá para ver o terminal enquanto ela não chega.
    var doCrew: Bool
    /// Pedida com ⌘N de dentro da grade: entra no fim da grade, sem sair dela.
    var naGrade = false
}

/// Onde o Hugo está no app: aba da barra lateral e o que aparece à direita.
@MainActor
final class NavegacaoCrew: ObservableObject {
    enum Selecao: Equatable {
        case inicio
        case sessao(String)
        case guardada(SessaoGuardada)
        /// O navegador do Crew na janela inteira.
        case navegador
        /// O painel de um projeto (caminho da raiz).
        case projeto(String)
        /// A tela de trabalho de uma ferramenta de um setor (`Central/Setores/Setores.swift`).
        case ferramenta(String)
    }

    enum Aba: Hashable { case sessoes, projetos, historico }

    /// Montagem fixa de uma tela, para as capturas (`Crew --capturas`).
    struct Cena {
        var aba: Aba = .sessoes
        var selecao: Selecao? = nil
        /// A sessão aberta roda no motor do Crew e mostra o terminal.
        var terminal = false
        var abrindo: SessaoAbrindo? = nil
        /// Sessões lado a lado (tela dividida).
        var paineis: [String] = []
        /// Colunas da grade (0 = automático).
        var colunas = 0
        /// Barra lateral recolhida, aparecendo por cima (mouse na borda).
        var espiando = false
        /// A aba do painel do projeto que aparece aberta.
        var abaDoProjeto: PainelProjeto.Aba = .geral
        /// Sessão ao lado da tela de outro setor.
        var aoLado: String? = nil
    }

    /// O que está à direita. Na grade é o painel em foco; escolher uma sessão que não está
    /// na grade sai da vista de grade e mostra essa sessão inteira (⌘G a põe na grade).
    @Published var selecao: Selecao = .inicio {
        didSet {
            if emGrade, case .sessao(let id) = selecao, !paineis.contains(id) { emGrade = false }
            // Olhou a sessão: a ênfase dela some.
            if case .sessao(let id) = selecao, atencao.contains(id) { atencao.remove(id) }
            ultimaNoSetor[setor] = selecao
        }
    }
    /// O que estava aberto em cada setor: voltar a ele pela barra de setores retoma dali.
    var ultimaNoSetor: [Setor: Selecao] = [:]
    /// Sessões que estão na grade, na ordem do Hugo: da esquerda para a direita, de cima para baixo.
    @Published var paineis: [String] = []
    /// Colunas da grade: 0 = automático (o Crew escolhe pelo número de sessões); 1 a 4 = fixas.
    @Published var colunasGrade = UserDefaults.standard.integer(forKey: Ajustes.chave("sessoes", "gradeColunas")) {
        didSet { if cena == nil { Ajustes.definir("sessoes", "gradeColunas", colunasGrade) } }
    }
    /// Painel sendo arrastado para outro lugar da grade, e o painel em cima do qual ele está.
    @Published var arrastando: String?
    @Published var alvoArraste: String?
    /// Onde cada painel está na tela (no espaço "grade"); a grade atualiza a cada desenho.
    var quadrosGrade: [(id: String, quadro: CGRect)] = []

    /// Tamanhos que o Hugo deu arrastando as divisórias: peso de cada painel dentro da linha
    /// dele e peso de cada linha (1 = parte igual).
    @Published var pesoPainel: [String: CGFloat] = [:]
    @Published var pesoLinha: [Int: CGFloat] = [:]

    func igualarGrade() {
        pesoPainel = [:]
        pesoLinha = [:]
    }

    /// ⌘N na grade: abre uma sessão em branco no projeto e a põe no fim da grade, sem sair dela.
    func novaNaGrade(pasta: String, nome: String) {
        guard abrindo == nil else { return }
        let conhecidas = Set(AppState.shared.tasks.map(\.id))
        abrindo = SessaoAbrindo(sessionId: nil, caminho: pasta, projeto: nome, conhecidas: conhecidas, doCrew: true, naGrade: true)
        Task {
            switch await MotorCrew.nova(pasta: pasta, pedido: "") {
            case .success(let sid):
                abrindo?.sessionId = sid
                procurarNova(AppState.shared.tasks)
                // Não chegou em 30 s (o Claude Code parou em alguma pergunta): solta a espera,
                // senão o próximo ⌘N ficaria travado. A sessão aparece na lista quando começar.
                try? await Task.sleep(for: .seconds(30))
                if abrindo?.sessionId == sid { abrindo = nil }
            case .failure:
                // Não abriu: cai no caminho de sempre (o início, com o campo e o motivo).
                abrindo = nil
                novaSessao(em: pasta)
            }
        }
    }

    /// Quantas colunas a grade tem com `n` painéis.
    static func colunas(para n: Int, escolha: Int) -> Int {
        let n = max(n, 1)
        if escolha > 0 { return min(escolha, n, 4) }
        switch n {
        case ...4: return n          // até quatro, lado a lado
        case 5, 6, 9: return 3
        default: return 4
        }
    }

    /// Arrastando o cabeçalho de um painel: marca em cima de qual painel ele está.
    func arrastar(_ id: String, em ponto: CGPoint) {
        if arrastando != id { arrastando = id }
        let alvo = quadrosGrade.first { $0.quadro.contains(ponto) }?.id
        if alvo != alvoArraste { alvoArraste = alvo }
    }

    /// Soltou: o painel vai para o lugar do alvo (os outros se ajeitam).
    func soltar() {
        if let id = arrastando, let alvo = alvoArraste { mover(id, paraOLugarDe: alvo) }
        arrastando = nil
        alvoArraste = nil
    }

    func mover(_ id: String, paraOLugarDe alvo: String) {
        guard id != alvo, let de = paineis.firstIndex(of: id), let para = paineis.firstIndex(of: alvo) else { return }
        paineis.remove(at: de)
        paineis.insert(id, at: para)
    }

    /// Uma casa para trás ou para a frente na ordem da grade.
    func moverPainel(_ id: String, passo: Int) {
        guard let i = paineis.firstIndex(of: id) else { return }
        let j = min(max(i + passo, 0), paineis.count - 1)
        guard j != i else { return }
        paineis.swapAt(i, j)
    }
    /// A vista de grade está na tela (as sessões da grade lado a lado).
    @Published var emGrade = false
    /// Sessões que entregaram ou falharam e o Hugo ainda não olhou (ênfase discreta na lista).
    @Published var atencao: Set<String> = []
    /// Painel da grade ao lado do qual a sessão nova vai entrar (pedida com a grade na tela).
    var ladoDaNova: String?
    /// Sessão que acompanha o Hugo fora da tela dela: aparece ao lado do que estiver aberto
    /// (ferramenta de outro setor, navegador, projeto). Abrir a própria sessão a esconde; voltar
    /// para outra tela a mostra de novo, até ele fechar.
    @Published var sessaoAoLado: String?
    /// Sessões com o navegador aberto ao lado da conversa.
    @Published var navegadorCom: Set<String> = []

    /// Sessões com os arquivos do projeto abertos ao lado da conversa.
    @Published var arquivosCom: Set<String> = []

    /// Sessões com os arquivos como visualização principal (no lugar da conversa).
    @Published var arquivosPrincipal: Set<String> = []

    /// Abre os arquivos do projeto ao lado da sessão (sai da grade: lá não cabe).
    func abrirArquivos(_ taskId: String) {
        aba = .sessoes
        selecao = .sessao(taskId)
        emGrade = false
        navegadorCom.remove(taskId)
        arquivosCom.insert(taskId)
    }

    /// Abre o navegador ao lado da sessão (sai da grade: lá não cabe), já num endereço se vier.
    func abrirNavegador(_ taskId: String, url: URL? = nil) {
        aba = .sessoes
        selecao = .sessao(taskId)
        emGrade = false
        navegadorCom.insert(taskId)
        arquivosCom.remove(taskId)
        guard let url else { return }
        // No espaço avulso da sessão (o navegador da janela fica com o Geral).
        let t = AppState.shared.tasks.first { $0.id == taskId }
        let espaco = NavegadorServico.shared.garantir(sessao: taskId, nome: t?.displayTitle ?? "Sessão",
                                                      cor: Projetos.cor(de: t?.sessionCwd))
        NavegadorServico.shared.abrir(url, em: espaco)
    }

    /// O que estava na tela antes de o navegador tomar a janela inteira (⌘J volta para lá).
    private var antesDoNavegador: Selecao = .inicio

    /// ⌘J: abre ou recolhe o navegador. Numa sessão, é o navegador ao lado dela; fora de
    /// sessão (início, projeto, histórico), o navegador na janela inteira.
    func alternarNavegador() {
        switch selecao {
        case .sessao(let id):
            if navegadorCom.contains(id) { navegadorCom.remove(id) } else { abrirNavegador(id) }
        case .navegador:
            selecao = antesDoNavegador
        default:
            antesDoNavegador = selecao
            selecao = .navegador
        }
    }

    /// Sessão que o Hugo pediu para encerrar (⌘W, botão de parar): abre a confirmação.
    @Published var pedirEncerrar: String?

    /// ⌘← ⌘→ (e ⌘↑ ⌘↓, com o passo de uma linha) na grade: leva a atenção para o painel vizinho.
    func focarVizinho(_ passo: Int) {
        guard emGrade, case .sessao(let id) = selecao, let i = paineis.firstIndex(of: id) else { return }
        selecao = .sessao(paineis[min(max(i + passo, 0), paineis.count - 1)])
    }
    /// A grade vai até 4 × 4.
    static let maxPaineis = 16
    @Published var aba: Aba = .sessoes
    /// Projeto pré-escolhido no campo do início (caminho da pasta).
    @Published var projetoInicio: String?
    /// Muda quando o campo do início deve ganhar o foco.
    @Published var focoInicio = 0
    @Published var abrindo: SessaoAbrindo?
    /// O texto do último pedido que virou sessão: não pode reaparecer no campo do início.
    var pedidoEnviado: String?
    /// Sessão retomada pelo histórico (session_id): abre assim que chegar pelos hooks.
    var retomada: String?
    let cena: Cena?

    init(cena: Cena? = nil) {
        self.cena = cena
        if let cena {
            colunasGrade = cena.colunas
            aba = cena.aba
            abrindo = cena.abrindo
            if let s = cena.selecao { selecao = s }
            paineis = cena.paineis
            sessaoAoLado = cena.aoLado
            emGrade = !cena.paineis.isEmpty
        }
    }

    /// Volta ao início com o campo pronto para um pedido (⌘N, "Nova sessão", "+" do projeto).
    func novaSessao(em projeto: String? = nil) {
        if let projeto { projetoInicio = projeto }
        // Pedida de dentro da grade: a sessão nova entra ao lado do painel em foco.
        if emGrade, case .sessao(let id) = selecao, paineis.contains(id) { ladoDaNova = id } else { ladoDaNova = nil }
        selecao = .inicio
        focoInicio += 1
    }

    /// Abre o painel do projeto (clique na linha dele): visão geral e configuração.
    func abrirProjeto(_ caminho: String) {
        selecao = .projeto(caminho)
    }

    func abrir(_ taskId: String) {
        aba = .sessoes
        selecao = .sessao(taskId)
    }

    private func porNaGrade(_ id: String) {
        guard !paineis.contains(id) else { return }
        if paineis.count < Self.maxPaineis { paineis.append(id) } else { paineis[paineis.count - 1] = id }
    }

    /// ⌘G. Sessão fora da grade: entra nela e a grade aparece. Sessão da grade vista sozinha:
    /// volta para a grade. Já na grade: sai, mostrando inteira a sessão em foco.
    func alternarGrade() {
        guard case .sessao(let id) = selecao else { return }
        if emGrade, paineis.contains(id) { emGrade = false; return }
        porNaGrade(id)
        emGrade = true
    }

    /// Põe a sessão na grade, ao lado da que está na tela, e mostra a grade com ela em foco.
    func abrirAoLado(_ id: String) {
        aba = .sessoes
        if case .sessao(let atual) = selecao { porNaGrade(atual) }
        porNaGrade(id)
        emGrade = true
        selecao = .sessao(id)
    }

    /// Tira um painel da grade (a sessão continua rodando).
    func fecharPainel(_ id: String) {
        paineis.removeAll { $0 == id }
        if paineis.isEmpty { emGrade = false }
        else if selecao == .sessao(id) { selecao = .sessao(paineis[0]) }
    }

    /// A sessão pedida chega pelos hooks: pelo id (o motor do Crew escolhe o session_id) ou,
    /// no Xirp, pela pasta do projeto.
    func procurarNova(_ tasks: [AgentTask]) {
        guard let w = abrindo else { return }
        let novas = tasks.filter { !w.conhecidas.contains($0.id) && $0.sessionId != nil }
        let porId = novas.first { w.sessionId != nil && $0.sessionId == w.sessionId }
        let porPasta = w.doCrew ? nil : novas.first { ($0.sessionCwd ?? "").hasPrefix(w.caminho) }
        guard let achada = porId ?? porPasta else { return }
        abrindo = nil
        if w.naGrade {
            // Entra no fim da grade (cheia: toma o último lugar) e ganha o foco, sem sair dela.
            if !paineis.contains(achada.id) {
                if paineis.count < Self.maxPaineis { paineis.append(achada.id) } else { paineis[paineis.count - 1] = achada.id }
            }
            aba = .sessoes
            emGrade = true
            selecao = .sessao(achada.id)
            return
        }
        // Só pula para ela se o Hugo ainda está esperando no início.
        guard selecao == .inicio else { ladoDaNova = nil; return }
        if let lado = ladoDaNova, let i = paineis.firstIndex(of: lado) {
            // Entra na grade logo à direita do painel de onde foi pedida (cheia, sai a última).
            paineis.insert(achada.id, at: i + 1)
            if paineis.count > Self.maxPaineis {
                paineis.remove(at: paineis.last == achada.id ? paineis.count - 2 : paineis.count - 1)
            }
            emGrade = true
        }
        ladoDaNova = nil
        abrir(achada.id)
    }
}

struct AppCrewView: View {
    @StateObject private var nav: NavegacaoCrew
    @ObservedObject private var state = AppState.shared
    /// A janela está à vista (não minimizada nem coberta): só então há animação e releitura.
    @State private var visivel = true

    init(cena: NavegacaoCrew.Cena? = nil) {
        _nav = StateObject(wrappedValue: NavegacaoCrew(cena: cena))
    }

    private var sessoes: [AgentTask] { SessoesCrew.todas(state) }

    /// Barra lateral recolhida (lembrado entre aberturas).
    @AppStorage("modulo.sessoes.lateralRecolhida") private var lateralRecolhida = false

    /// Só a barra desliza, curta e sem mola. O resto da tela (conversa, grade) muda de tamanho
    /// de uma vez: texto se reorganizando no meio de uma animação parece defeito.
    private static let mola = Animation.easeOut(duration: 0.2)

    private func alternarLateral() {
        sairDeEspiar?.cancel()
        lateralRecolhida.toggle()
        espiando = false
    }

    /// Recolhida, a barra aparece por cima quando o mouse encosta na borda esquerda e some
    /// quando ele se afasta.
    @State private var espiando = false
    @State private var sairDeEspiar: Task<Void, Never>?

    private func mouse(_ fase: HoverPhase) {
        // O Homie da barra lateral acompanha o mouse (ele fica no canto de cima, à esquerda).
        if case .active(let p) = fase {
            OlharHomie.lateral.x = tanh((p.x - 31) / 320)
            OlharHomie.lateral.y = -tanh((p.y - 53) / 260)
        } else {
            OlharHomie.lateral.x = 0; OlharHomie.lateral.y = 0
        }
        guard lateralRecolhida, nav.cena == nil else { return }
        switch fase {
        case .active(let p):
            if !espiando {
                if p.x < 12 {
                    sairDeEspiar?.cancel()
                    withAnimation(Self.mola) { espiando = true }
                }
            } else if p.x > Tema.larguraLateral + 36 {
                esconderLogo()
            } else {
                sairDeEspiar?.cancel()
                sairDeEspiar = nil
            }
        case .ended:
            if espiando { esconderLogo() }
        }
    }

    /// ⌥M recolhe/mostra a barra lateral; ⌘G põe a sessão na grade / entra e sai da grade.
    /// (Vigia de teclado: ⌥ sozinho não vira atalho de menu, e ⌘G no campo seria "buscar próximo".)
    @State private var vigiaTeclas: Any?

    private func vigiarTeclas() {
        guard vigiaTeclas == nil, nav.cena == nil else { return }
        let nav = nav
        vigiaTeclas = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { evento in
            guard evento.window?.frameAutosaveName == "CrewSessoes" else { return evento }
            // ⌘J abre/recolhe o navegador de qualquer lugar, inclusive com o cursor dentro dele.
            if evento.modifierFlags.intersection([.command, .control, .option, .shift]) == .command, evento.keyCode == 38 {
                MainActor.assumeIsolated { nav.alternarNavegador() }
                return nil
            }
            // Com o cursor no navegador, os atalhos são dele (⌘W fecha a aba, não a sessão).
            if MainActor.assumeIsolated({ NavegadorServico.shared.tecla(evento) }) { return nil }
            let mods = evento.modifierFlags.intersection([.command, .control, .option, .shift])
            if mods == .option, evento.keyCode == 46 {          // ⌥M
                MainActor.assumeIsolated { alternarLateral() }
                return nil
            }
            if mods == .command, evento.keyCode == 5 {          // ⌘G
                MainActor.assumeIsolated { nav.alternarGrade() }
                return nil
            }
            let tecla = evento.keyCode
            let tratou: Bool = MainActor.assumeIsolated {
                // Confirmação de encerrar aberta: Enter confirma, Esc cancela.
                if let id = nav.pedirEncerrar {
                    if mods.isEmpty, tecla == 36 || tecla == 76 { encerrar(id); return true }
                    if mods.isEmpty, tecla == 53 { nav.pedirEncerrar = nil; return true }
                    return false
                }
                // ⌘N: sessão nova. Na grade, em branco e no fim dela; fora, o início com o campo.
                if mods == .command, tecla == 45 { novaPeloAtalho(); return true }
                // ⌘W fecha a sessão (com confirmação), nunca a janela.
                if mods == .command, tecla == 13 {
                    if case .sessao(let id) = nav.selecao { nav.pedirEncerrar = id }
                    return true
                }
                // ⌘← ⌘→ na grade: muda o painel em foco. Com mais de uma linha, ⌘↑ ⌘↓ também.
                if mods == .command, nav.emGrade, tecla == 123 || tecla == 124 {
                    nav.focarVizinho(tecla == 123 ? -1 : 1)
                    return true
                }
                let colunas = NavegacaoCrew.colunas(para: nav.paineis.count, escolha: nav.colunasGrade)
                if mods == .command, nav.emGrade, nav.paineis.count > colunas, tecla == 125 || tecla == 126 {
                    nav.focarVizinho(tecla == 126 ? -colunas : colunas)
                    return true
                }
                // ⌃⌘← ⌃⌘→ na grade: muda o painel em foco de lugar.
                if mods == [.command, .control], nav.emGrade, tecla == 123 || tecla == 124,
                   case .sessao(let id) = nav.selecao {
                    nav.moverPainel(id, passo: tecla == 123 ? -1 : 1)
                    return true
                }
                return false
            }
            return tratou ? nil : evento
        }
    }

    /// ⌘N (ou "Nova sessão" no menu). Com a grade na tela: uma sessão em branco no projeto do
    /// painel em foco, no fim da grade. Senão: o início, já no projeto da sessão aberta.
    private func novaPeloAtalho() {
        var projeto: String?
        if case .sessao(let id) = nav.selecao, let t = sessoes.first(where: { $0.id == id }) {
            projeto = Projetos.raiz(de: t.sessionCwd)
        }
        if nav.emGrade, let projeto, MotorCrew.disponivel {
            nav.novaNaGrade(pasta: projeto, nome: URL(fileURLWithPath: projeto).lastPathComponent)
        } else {
            nav.novaSessao(em: projeto)
        }
    }

    /// Encerra a sessão confirmada: sai da grade e o Claude Code dela para.
    private func encerrar(_ id: String) {
        nav.pedirEncerrar = nil
        nav.fecharPainel(id)
        NavegadorServico.shared.apagarEspaco(daSessao: id)
        state.encerrar(id)
    }

    /// Só tira a sessão do Crew (ela continua rodando onde está).
    private func tirar(_ id: String) {
        nav.pedirEncerrar = nil
        nav.fecharPainel(id)
        NavegadorServico.shared.apagarEspaco(daSessao: id)
        state.dispensar(id)
    }

    /// Some depois de um instante longe (voltar o mouse a tempo cancela).
    private func esconderLogo() {
        guard sairDeEspiar == nil else { return }
        sairDeEspiar = Task {
            try? await Task.sleep(for: .seconds(0.3))
            guard !Task.isCancelled else { return }
            sairDeEspiar = nil
            // Escrevendo na busca ou renomeando na barra: ela fica.
            if NSApp.keyWindow?.firstResponder is NSTextView, barraComCursor { return }
            withAnimation(Self.mola) { espiando = false }
        }
    }

    /// O cursor de texto está dentro da barra lateral (busca, renomear).
    private var barraComCursor: Bool {
        guard let v = NSApp.keyWindow?.firstResponder as? NSView, let janela = v.window else { return false }
        return v.convert(v.bounds, to: nil).midX < Tema.larguraLateral && janela.isKeyWindow
    }

    /// Imagem da conversa ampliada por cima da janela.
    @State private var imagemAmpliada: Data?

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                if !lateralRecolhida {
                    BarraLateralCrew(recolher: alternarLateral)
                        .frame(width: Tema.larguraLateral)
                        .transition(.move(edge: .leading))
                }
            }
            .animation(Self.mola, value: lateralRecolhida)
            conteudo
                .environment(\.recuoTitulo, lateralRecolhida ? 104 : 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Tema.fundo)
                .overlay(alignment: .topLeading) {
                    if lateralRecolhida {
                        BotaoIcone(icone: "sidebar.left", ajuda: "Fixar a barra lateral (⌥M)", lado: 28,
                                   acao: alternarLateral)
                            .padding(.leading, 76).padding(.top, 12)
                    }
                }
        }
        // Barra recolhida: desliza por cima da tela com o mouse na borda.
        .overlay(alignment: .leading) {
            if lateralRecolhida, espiando {
                BarraLateralCrew(recolher: alternarLateral, flutuando: true)
                    .frame(width: Tema.larguraLateral)
                    .shadow(color: .black.opacity(0.55), radius: 28, x: 10)
                    .transition(.move(edge: .leading))
            }
        }
        .onContinuousHover(coordinateSpace: .local) { mouse($0) }
        .clipped()
        .background(Tema.fundo)
        // Imagem da conversa abre aqui dentro, por cima da janela (clique fora, X ou Esc fecha).
        .environment(\.ampliarImagem) { imagemAmpliada = $0 }
        .overlay {
            if let d = imagemAmpliada {
                ImagemAmpliada(data: d) {
                    withAnimation(.easeOut(duration: 0.15)) { imagemAmpliada = nil }
                }
                .padding(.top, 28)   // deixa os botões da janela livres
            }
        }
        // Confirmação de encerrar a sessão (⌘W ou o botão de parar).
        .overlay {
            if let id = nav.pedirEncerrar, let t = sessoes.first(where: { $0.id == id }) {
                DialogoCrew(titulo: "Encerrar esta sessão?",
                            texto: "O Claude Code de “\(t.displayTitle)” para. A conversa fica guardada no Histórico e dá para retomar.",
                            perigo: "Só tirar do Crew", aoPerigo: { tirar(id) },
                            confirmar: "Encerrar sessão", aoConfirmar: { encerrar(id) },
                            aoCancelar: { nav.pedirEncerrar = nil })
            }
        }
        .animation(.easeOut(duration: 0.14), value: nav.pedirEncerrar)
        .ignoresSafeArea()
        .environmentObject(nav)
        .environment(\.telaVisivel, visivel)
        .environment(\.colorScheme, .dark)
        .tint(Tema.destaque)
        .background { if !CaptureTool.ativo { VigiaDaJanela(visivel: $visivel) } }
        .background { atalhos }
        // ⌘N com uma sessão na tela: sessão nova no projeto dela.
        .onReceive(NotificationCenter.default.publisher(for: .novaSessao)) { _ in novaPeloAtalho() }
        .onReceive(NotificationCenter.default.publisher(for: .sessaoPedeAtencao)) { n in
            // A que já está em foco na tela não precisa de ênfase: a resposta apareceu nela.
            guard let id = n.object as? String, nav.selecao != .sessao(id) else { return }
            withAnimation(.easeOut(duration: 0.3)) { _ = nav.atencao.insert(id) }
        }
        .modifier(AvisosDoNavegador(nav: nav))
        .modifier(AvisosDosSetores(nav: nav))
        .modifier(VisorDeArquivos())
        .onReceive(NotificationCenter.default.publisher(for: .abrirSessaoNoApp)) { n in
            if let id = n.object as? String { nav.abrir(id) }
        }
        .onAppear {
            vigiarTeclas()
            escolherInicial()
            if nav.cena?.espiando == true { espiando = true }
        }
        .onChange(of: state.tasks.map(\.id)) { _, _ in
            nav.procurarNova(state.tasks)
            abrirRetomada()
        }
        // Chegou aprovação/pergunta com o início parado na tela: mostra a que espera.
        .onChange(of: state.pendingApprovals.count) { antes, agora in
            if agora > antes, nav.selecao == .inicio, nav.abrindo == nil, !inicioEmUso {
                escolherInicial()
            }
        }
        .task { await ProjetosCrew.shared.recarregar() }
        // Sessão em pasta nova = projeto novo na lista.
        .onChange(of: Set(sessoes.compactMap(\.sessionCwd))) { _, _ in
            Task { await ProjetosCrew.shared.recarregar() }
        }
    }

    /// A sessão que acompanha o Hugo, quando há outra coisa na tela para dividir com ela.
    private var aoLado: String? {
        guard let id = nav.sessaoAoLado, sessoes.contains(where: { $0.id == id }) else { return nil }
        switch nav.selecao {
        case .ferramenta, .navegador, .projeto: return id
        default: return nil
        }
    }

    /// A tela do setor e, se o Hugo pediu, a sessão que o acompanha ao lado dela.
    private var conteudo: some View {
        DivisaoComSessao(sessao: aoLado, fechar: { nav.sessaoAoLado = nil }) { principal }
    }

    /// O Comando (sessões, projetos, histórico e as ferramentas dele) ou a tela de outro setor.
    @ViewBuilder
    private var principal: some View {
        if nav.setor == .comando { conteudoComando } else { TelaSetor(setor: nav.setor) }
    }

    @ViewBuilder
    private var conteudoComando: some View {
        switch nav.selecao {
        case .sessao(let id) where sessoes.contains(where: { $0.id == id }):
            // Tela dividida: só os painéis cujas sessões ainda existem.
            let vivos = nav.paineis.filter { p in sessoes.contains { $0.id == p } }
            if nav.emGrade, vivos.contains(id) {
                GradeSessoes(paineis: vivos, foco: id, recuoDoPrimeiro: lateralRecolhida ? 104 : 0)
            } else {
                ConversaCrew(taskId: id)
                    .id(id)
            }
        case .ferramenta(let id):
            if let f = Setores.ferramenta(id) { TelaFerramenta(ferramenta: f, noComando: true).id(id) }
        case .projeto(let caminho):
            PainelProjeto(caminho: caminho)
                .id(caminho)
        case .guardada(let g):
            ConversaGuardadaCrew(sessao: g) { cli in
                // Tirada do Crew antes: volta a ser aceita, senão os avisos dela seriam ignorados.
                state.readmitir(cli)
                nav.retomada = cli
                nav.aba = .sessoes
                nav.selecao = .inicio
                abrirRetomada()
            }
            .id(g.id)
        default:
            InicioCrew()
        }
    }

    /// O Hugo está escrevendo um pedido no início: nada o tira de lá.
    private var inicioEmUso: Bool {
        (NSApp.keyWindow?.firstResponder as? NSTextView)?.string.isEmpty == false
    }

    /// Ao abrir a janela: a sessão que espera resposta; sem nenhuma, o início.
    private func escolherInicial() {
        guard nav.cena == nil, nav.selecao == .inicio else { return }
        if let p = SessoesCrew.pendentes(state).first { nav.abrir(p.id) }
    }

    private func abrirRetomada() {
        guard let r = nav.retomada, let t = sessoes.first(where: { $0.sessionId == r }) else { return }
        nav.retomada = nil
        state.readmitir(r)
        nav.abrir(t.id)
    }

    // MARK: Atalhos de teclado

    /// ⌥⌘↓ / ⌥⌘↑: sessão seguinte / anterior, na ordem da barra lateral.
    private var atalhos: some View {
        Group {
            Button("") { andar(1) }.keyboardShortcut(.downArrow, modifiers: [.command, .option])
            Button("") { andar(-1) }.keyboardShortcut(.upArrow, modifiers: [.command, .option])
            // ⌃⌘S: recolhe/mostra a barra lateral (o atalho padrão do macOS).
            Button("") { alternarLateral() }.keyboardShortcut("s", modifiers: [.command, .control])
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func andar(_ passo: Int) {
        let ordem = GruposSessoes.montar(state: state, busca: "", mostrarParadas: false).flatMap(\.itens).map(\.id)
        guard !ordem.isEmpty else { return }
        var i = passo > 0 ? -1 : ordem.count
        if case .sessao(let id) = nav.selecao, let atual = ordem.firstIndex(of: id) { i = atual }
        nav.abrir(ordem[min(max(i + passo, 0), ordem.count - 1)])
    }
}

/// Pedidos de abrir o navegador (menu da sessão, ⌘ clique num link da conversa). À parte do
/// corpo do app: com mais modificadores lá o compilador não dá conta da expressão.
private struct AvisosDoNavegador: ViewModifier {
    let nav: NavegacaoCrew

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .navegadorDaSessao)) { n in
                if let id = n.object as? String { nav.abrirNavegador(id) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .arquivosDaSessao)) { n in
                if let id = n.object as? String { nav.abrirArquivos(id) }
            }
            // Pedido de fora (`defaults write … modulo.navegador.abrirImportacao`): ao abrir o
            // app, o navegador aparece já com a folha "Importar do Arc". Vale uma vez.
            .onAppear {
                let chave = "modulo.navegador.abrirImportacao"
                guard nav.cena == nil, UserDefaults.standard.bool(forKey: chave) else { return }
                UserDefaults.standard.removeObject(forKey: chave)
                nav.selecao = .navegador
                NavegadorServico.shared.importandoArc = true
            }
            // ⌘ clique num link da conversa: abre no navegador do Crew, ao lado da sessão.
            .onReceive(NotificationCenter.default.publisher(for: .abrirNoNavegador)) { n in
                guard let url = n.object as? URL else { return }
                if case .sessao(let id) = nav.selecao {
                    nav.abrirNavegador(id, url: url)
                } else {
                    NavegadorServico.shared.abrir(url, em: NavegadorServico.shared.garantir(projeto: nil))
                    nav.selecao = .navegador
                }
            }
    }
}
