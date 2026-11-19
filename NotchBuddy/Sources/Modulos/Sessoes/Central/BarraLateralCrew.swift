import SwiftUI
import AppKit

// Barra lateral do app do Crew: o Homie e o nome, "Nova sessão", a busca e três abas —
// Sessões (por projeto, com as que pedem resposta no topo), Projetos e Histórico.

/// Um grupo da lista de sessões: "Pedem sua resposta" ou um projeto.
struct GrupoSessoes: Identifiable {
    let id: String
    let titulo: String
    let cor: Color
    /// Pasta do projeto (nil no grupo das pendentes).
    let caminho: String?
    let pendentes: Bool
    let itens: [AgentTask]
}

@MainActor
enum GruposSessoes {
    /// Esperando o Hugo primeiro; depois por projeto (o de atividade mais recente em cima).
    static func montar(state: AppState, busca: String, mostrarParadas: Bool) -> [GrupoSessoes] {
        let q = busca.trimmingCharacters(in: .whitespaces).lowercased()
        let visiveis = SessoesCrew.todas(state).filter { t in
            (mostrarParadas || t.ativa || SessoesCrew.esperando(t, state))
                && (q.isEmpty || [t.displayTitle, t.name, t.sessionCwd ?? "", t.lastPrompt ?? ""]
                        .contains { $0.lowercased().contains(q) })
        }
        var out: [GrupoSessoes] = []
        let pendentes = visiveis.filter { SessoesCrew.esperando($0, state) }.sorted { $0.lastEvent > $1.lastEvent }
        if !pendentes.isEmpty {
            out.append(GrupoSessoes(id: "pendentes", titulo: "Pedem sua resposta", cor: Tema.ambar,
                                    caminho: nil, pendentes: true, itens: pendentes))
        }
        let resto = visiveis.filter { !SessoesCrew.esperando($0, state) }
        let porProjeto = Dictionary(grouping: resto) { Projetos.raiz(de: $0.sessionCwd) ?? "sem-pasta:" + $0.name }
        for (chave, itens) in porProjeto.sorted(by: {
            ($0.value.map(\.lastEvent).max() ?? .distantPast) > ($1.value.map(\.lastEvent).max() ?? .distantPast)
        }) {
            let cwd = itens.first?.sessionCwd
            out.append(GrupoSessoes(id: chave,
                                    titulo: Projetos.nome(de: cwd) ?? itens.first?.name ?? "—",
                                    cor: Color(hex: Projetos.cor(de: cwd) ?? "#9398A1"),
                                    caminho: Projetos.raiz(de: cwd), pendentes: false,
                                    itens: itens.sorted { $0.lastEvent > $1.lastEvent }))
        }
        return out
    }
}

struct BarraLateralCrew: View {
    /// Recolhe a barra (o botão no cabeçalho).
    var recolher: () -> Void = {}
    /// A barra está solta por cima da tela (apareceu com o mouse na borda): o botão a fixa.
    var flutuando = false
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var projetos = ProjetosCrew.shared
    @ObservedObject private var config = ConfigProjetos.shared
    @EnvironmentObject private var nav: NavegacaoCrew

    @State private var busca = ""
    @State private var mostrarParadas = false
    @State private var mostrarArquivados = false
    /// Sessão com o nome em edição na lista (dois cliques no título).
    @State private var renomeando: String?
    @FocusState private var buscaFocada: Bool

    private var sessoes: [AgentTask] { SessoesCrew.todas(state) }
    private var grupos: [GrupoSessoes] {
        GruposSessoes.montar(state: state, busca: busca, mostrarParadas: mostrarParadas)
    }
    private var escondidas: Int {
        sessoes.filter { !$0.ativa && !SessoesCrew.esperando($0, state) }.count
    }

    /// O Homie do topo espelha a equipe: alguém pede resposta, alguém trabalha, ou sossego.
    private var estadoGeral: BotState {
        if let p = SessoesCrew.pendentes(state).first {
            return state.pendingApprovals[p.sessionId ?? ""]?.questions.isEmpty == false ? .question : .approval
        }
        if sessoes.contains(where: { $0.ativa && [.working, .thinking, .searching].contains($0.state) }) { return .working }
        return .idle
    }

    var body: some View {
        VStack(spacing: 0) {
            cabecalho
            TrocaSetores()
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            if nav.setor == .comando { corpoComando } else { LateralSetor(setor: nav.setor) }
            Fio()
            rodape
        }
        .background(Tema.lateral)
        .overlay(alignment: .trailing) { Rectangle().fill(Tema.borda).frame(width: 1) }
        .background {
            // ⌘F: vai para a busca.
            Button("") { buscaFocada = true }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0).allowsHitTesting(false).accessibilityHidden(true)
        }
    }

    /// O Comando: nova sessão, busca e as três listas (sessões, projetos, histórico).
    private var corpoComando: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    botaoNova
                    campoBusca
                }
                AbasCrew(itens: [(.sessoes, "Sessões"), (.projetos, "Projetos"), (.historico, "Histórico")],
                         selecao: $nav.aba)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)

            Group {
                switch nav.aba {
                case .sessoes: listaSessoes
                case .projetos: listaProjetos
                case .historico:
                    ListaHistorico(busca: busca, selecionada: Binding(
                        get: { if case .guardada(let g) = nav.selecao { return g } else { return nil } },
                        set: { nav.selecao = $0.map { .guardada($0) } ?? .inicio }))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // As outras ferramentas do Comando (agentes, rotinas, modelos, uso).
            FerramentasComando()
        }
    }

    // MARK: Topo

    private var cabecalho: some View {
        HStack(spacing: 8) {
            // O nome do setor em que o Hugo está (a fileira logo abaixo troca de setor).
            Text(nav.setor.nome)
                .font(Tema.titulo(18, .bold))
                .foregroundStyle(Tema.texto)
            Spacer()
            BotaoIcone(icone: "sidebar.left",
                       ajuda: flutuando ? "Fixar a barra lateral (⌥M)" : "Recolher a barra lateral (⌥M) — ela volta quando o mouse encosta na borda",
                       lado: 28, acao: recolher)
        }
        // Os botões da janela (fechar, minimizar) ficam por cima do canto: o topo começa abaixo deles.
        .padding(.top, 38)
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }

    private var botaoNova: some View {
        BotaoNovaSessao { nav.novaSessao() }
    }

    private var campoBusca: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Tema.texto3)
            TextField("", text: $busca, prompt: Text("Buscar").foregroundStyle(Tema.texto3))
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .foregroundStyle(Tema.texto)
                .focused($buscaFocada)
                .onExitCommand { busca = ""; buscaFocada = false }
            if !busca.isEmpty {
                Button { busca = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundStyle(Tema.texto3)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 32)
        .background(Pilula().fill(Color.white.opacity(0.045)))
        .overlay(Pilula().strokeBorder(buscaFocada ? Tema.bordaForte : Tema.borda))
    }

    // MARK: Sessões

    @ViewBuilder
    private var listaSessoes: some View {
        let g = grupos
        if g.isEmpty {
            VaziaLateral(icone: sessoes.isEmpty ? "bubble.left.and.bubble.right" : "magnifyingglass",
                         texto: sessoes.isEmpty ? "Nenhuma sessão do Claude Code agora."
                            : busca.isEmpty ? "As sessões estão paradas ou ocultas." : "Nada com esse filtro.")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(g) { grupo in
                        CabecalhoGrupo(grupo: grupo) {
                            if let c = grupo.caminho { nav.novaSessao(em: c) }
                        }
                        .padding(.top, grupo.id == g.first?.id ? 2 : 12)
                        ForEach(grupo.itens) { t in
                            LinhaSessaoCrew(task: t, esperando: grupo.pendentes,
                                            escolhida: nav.selecao == .sessao(t.id),
                                            aoLado: nav.paineis.contains(t.id),
                                            atencao: nav.atencao.contains(t.id),
                                            renomeando: renomeando == t.id,
                                            acao: {
                                                // ⌥ clique: abre ao lado da sessão que está na tela.
                                                if NSEvent.modifierFlags.contains(.option) { nav.abrirAoLado(t.id) }
                                                else { nav.selecao = .sessao(t.id) }
                                            },
                                            renomear: { renomeando = $0 ? t.id : nil })
                            .menuContexto {
                                [.acao(nav.paineis.contains(t.id) ? "Ver na grade" : "Pôr na grade", icone: "rectangle.split.2x1") { nav.abrirAoLado(t.id) },
                                 .acao("Renomear", icone: "pencil") { renomeando = t.id },
                                 .divisor] + MenuSessao.itens(t)
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.never)
            .focusable()
            .focusEffectDisabled()
            .onMoveCommand { direcao in
                switch direcao {
                case .down: andar(1, em: g)
                case .up: andar(-1, em: g)
                default: break
                }
            }
        }
    }

    /// Setas com a lista em foco: sessão de baixo / de cima.
    private func andar(_ passo: Int, em grupos: [GrupoSessoes]) {
        let ordem = grupos.flatMap(\.itens).map(\.id)
        guard !ordem.isEmpty else { return }
        var i = passo > 0 ? -1 : ordem.count
        if case .sessao(let id) = nav.selecao, let atual = ordem.firstIndex(of: id) { i = atual }
        nav.selecao = .sessao(ordem[min(max(i + passo, 0), ordem.count - 1)])
    }

    // MARK: Projetos

    private func filtrados(_ l: [ProjetoCrew]) -> [ProjetoCrew] {
        let q = busca.trimmingCharacters(in: .whitespaces).lowercased()
        return l.filter { q.isEmpty || $0.nome.lowercased().contains(q) || $0.caminho.lowercased().contains(q) }
    }
    private var projetosVisiveis: [ProjetoCrew] { filtrados(projetos.lista) }
    private var arquivadosVisiveis: [ProjetoCrew] { filtrados(projetos.arquivados) }

    /// Ações de um projeto: no "…" da linha e no clique direito.
    private func menuProjeto(_ p: ProjetoCrew, arquivado: Bool) -> [ItemMenu] {
        var itens: [ItemMenu] = [.acao("Abrir o projeto", icone: "slider.horizontal.3", detalhe: "visão geral e configuração") {
            nav.abrirProjeto(p.caminho)
        }]
        if !arquivado {
            let fixado = config.de(p.caminho).fixado
            let visiveis = projetos.lista.map(\.caminho)
            itens += [
                .acao("Nova sessão aqui", icone: "plus") { nav.novaSessao(em: p.caminho) },
                .divisor,
                .acao(fixado ? "Soltar do topo" : "Fixar no topo", icone: fixado ? "pin.slash" : "pin") {
                    config.mudar(p.caminho) { $0.fixado.toggle() }
                    Task { await projetos.recarregar() }
                },
                .acao("Mover para cima", icone: "arrow.up", desabilitado: visiveis.first == p.caminho) {
                    config.mover(p.caminho, passo: -1, visiveis: visiveis)
                    Task { await projetos.recarregar() }
                },
                .acao("Mover para baixo", icone: "arrow.down", desabilitado: visiveis.last == p.caminho) {
                    config.mover(p.caminho, passo: 1, visiveis: visiveis)
                    Task { await projetos.recarregar() }
                },
                .divisor,
            ]
        }
        itens += [
            .acao("Mostrar no Finder", icone: "folder") {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: p.caminho)
            },
            .acao("Copiar caminho", icone: "doc.on.doc") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(p.caminho, forType: .string)
            },
            .divisor,
            arquivado
                ? .acao("Desarquivar", icone: "tray.and.arrow.up") { Task { await projetos.desarquivar(p.caminho) } }
                : .acao("Arquivar", icone: "archivebox", detalhe: "sai da lista e fica em Arquivados") {
                    if nav.projetoInicio == p.caminho { nav.projetoInicio = nil }
                    if nav.selecao == .projeto(p.caminho) { nav.selecao = .inicio }
                    Task { await projetos.arquivar(p.caminho) }
                },
            .acao("Excluir da lista", icone: "trash", detalhe: "a pasta não é apagada", destrutivo: true) {
                if nav.projetoInicio == p.caminho { nav.projetoInicio = nil }
                if nav.selecao == .projeto(p.caminho) { nav.selecao = .inicio }
                Task { await projetos.excluir(p.caminho) }
            },
        ]
        return itens
    }

    private func sessoesDe(_ p: ProjetoCrew) -> Int {
        sessoes.filter { Projetos.raiz(de: $0.sessionCwd) == p.caminho }.count
    }

    private var listaProjetos: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text(projetos.lista.count == 1 ? "1 pasta" : "\(projetos.lista.count) pastas")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Tema.texto3)
                Spacer()
                BotaoIcone(icone: "plus", ajuda: "Adicionar uma pasta de projeto", lado: 22) { adicionarPasta() }
            }
            .padding(.leading, 18).padding(.trailing, 12)
            .frame(height: 26)

            if projetosVisiveis.isEmpty && arquivadosVisiveis.isEmpty {
                VaziaLateral(icone: "folder",
                             texto: projetos.lista.isEmpty ? "Adicione a pasta de um projeto para abrir sessões nela."
                                : "Nada com esse filtro.",
                             acao: projetos.lista.isEmpty ? ("Adicionar pasta", { adicionarPasta() }) : nil)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(projetosVisiveis) { p in
                            LinhaProjetoCrew(projeto: p, sessoes: sessoesDe(p),
                                             escolhido: nav.selecao == .projeto(p.caminho),
                                             config: config.de(p.caminho),
                                             menu: { menuProjeto(p, arquivado: false) }) {
                                nav.abrirProjeto(p.caminho)
                            }
                            .menuContexto { menuProjeto(p, arquivado: false) }
                        }
                        if !arquivadosVisiveis.isEmpty {
                            Button { mostrarArquivados.toggle() } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 8.5, weight: .bold))
                                        .rotationEffect(.degrees(mostrarArquivados ? 90 : 0))
                                    Text("Arquivados · \(arquivadosVisiveis.count)")
                                        .font(.system(size: 11, weight: .semibold))
                                    Spacer()
                                }
                                .foregroundStyle(Tema.texto3)
                                .padding(.horizontal, 10)
                                .frame(height: 26)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 10)
                            if mostrarArquivados {
                                ForEach(arquivadosVisiveis) { p in
                                    LinhaProjetoCrew(projeto: p, sessoes: 0,
                                                     escolhido: nav.selecao == .projeto(p.caminho), apagado: true,
                                                     config: config.de(p.caminho),
                                                     menu: { menuProjeto(p, arquivado: true) }) {
                                        nav.abrirProjeto(p.caminho)
                                    }
                                    .menuContexto { menuProjeto(p, arquivado: true) }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 12)
                }
                .scrollIndicators(.never)
            }
        }
    }

    private func adicionarPasta() {
        Task {
            if let p = await projetos.adicionarPerguntando() { nav.novaSessao(em: p.caminho) }
        }
    }

    // MARK: Rodapé

    private var rodape: some View {
        HStack(spacing: 8) {
            let ativas = sessoes.filter(\.ativa).count
            HStack(spacing: 6) {
                Circle().fill(ativas > 0 ? Tema.verde : Tema.texto3).frame(width: 6, height: 6)
                Text(ativas == 1 ? "1 ativa" : "\(ativas) ativas")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Tema.texto2)
            }
            Spacer()
            if nav.setor == .comando, nav.aba == .sessoes {
                AlternadorParadas(ligado: $mostrarParadas, quantas: escondidas)
            }
            BotaoIcone(icone: "gearshape", ajuda: "Ajustes (⌘,)", lado: 28) { JanelaAjustes.shared.abrir() }
        }
        .padding(.leading, 18).padding(.trailing, 10)
        .frame(height: 44)
    }
}

// MARK: - Peças

/// "Nova sessão": o "+" redondo ao lado da busca.
private struct BotaoNovaSessao: View {
    let acao: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: acao) {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Tema.sobreDestaque)
                .frame(width: 32, height: 32)
                .background(Circle().fill(hover ? Color.white : Tema.destaque))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("Nova sessão (⌘N)")
    }
}

/// Título de um grupo: cor e nome do projeto, quantas sessões e o "+" que aparece ao passar o mouse.
private struct CabecalhoGrupo: View {
    let grupo: GrupoSessoes
    let nova: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 7) {
            if grupo.pendentes {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(Tema.ambar)
            } else {
                Circle().fill(grupo.cor).frame(width: 7, height: 7)
            }
            Text(grupo.titulo)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(grupo.pendentes ? Tema.ambar : Tema.texto2)
                .lineLimit(1)
            Text("\(grupo.itens.count)")
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(grupo.pendentes ? Tema.ambar.opacity(0.7) : Tema.texto3)
            Spacer(minLength: 4)
            if grupo.caminho != nil {
                BotaoIcone(icone: "plus", ajuda: "Nova sessão em \(grupo.titulo)", lado: 20, acao: nova)
                    .opacity(hover ? 1 : 0)
            }
        }
        .padding(.leading, 10).padding(.trailing, 4)
        .frame(height: 24)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }
}

/// Uma sessão na barra lateral: estado, título, há quanto tempo e a última frase.
struct LinhaSessaoCrew: View {
    let task: AgentTask
    let esperando: Bool
    let escolhida: Bool
    /// Está num dos painéis da tela dividida.
    var aoLado = false
    /// Entregou ou falhou e o Hugo ainda não olhou: ponto pulsando e um fundo leve na cor do estado.
    var atencao = false
    @State private var pulso = false
    let renomeando: Bool
    let acao: () -> Void
    /// true = começar a renomear; false = acabou.
    let renomear: (Bool) -> Void
    @State private var hover = false
    @State private var novoNome = ""
    @FocusState private var nomeFocado: Bool
    @ObservedObject private var modelos = ModelosSessoes.shared

    private var cor: Color { CorDoEstado.de(task.state, esperando: esperando) }

    private var campoNome: some View {
        TextField("", text: $novoNome, prompt: Text("Nome da sessão").foregroundStyle(Tema.texto3))
            .textFieldStyle(.plain)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Tema.texto)
            .focused($nomeFocado)
            .onSubmit { AppState.shared.renomear(task.id, para: novoNome); renomear(false) }
            .onExitCommand { renomear(false) }
            .onChange(of: nomeFocado) { _, f in if !f { renomear(false) } }
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Tema.bordaForte))
            .padding(.leading, -6)
            .onAppear {
                novoNome = task.displayTitle
                DispatchQueue.main.async { nomeFocado = true }
            }
    }

    var body: some View {
        linha
            .contentShape(RoundedRectangle(cornerRadius: Tema.raioLinha))
            .onTapGesture { if !renomeando { acao() } }
            // Dois cliques no título: renomear ali mesmo.
            .simultaneousGesture(TapGesture(count: 2).onEnded { if !renomeando { renomear(true) } })
            .onHover { hover = $0 }
            .task(id: task.lastEvent) { await modelos.atualizar(task.transcriptPath) }
            .help(renomeando ? "" : "Dois cliques para renomear · ⌥ clique põe na grade")
    }

    private var linha: some View {
        Group {
            HStack(alignment: .top, spacing: 9) {
                Circle().fill(atencao ? corAtencao : cor)
                    .frame(width: 7, height: 7)
                    .background {
                        if atencao {
                            Circle().stroke(corAtencao.opacity(pulso ? 0 : 0.7), lineWidth: 1.5)
                                .frame(width: 7, height: 7)
                                .scaleEffect(pulso ? 2.6 : 1)
                                .animation(.easeOut(duration: 1.4).repeatForever(autoreverses: false), value: pulso)
                                .onAppear { pulso = true }
                                .onDisappear { pulso = false }
                        }
                    }
                    .padding(.top, 5)
                VStack(alignment: .leading, spacing: 2.5) {
                    HStack(spacing: 6) {
                        if renomeando {
                            campoNome
                        } else {
                            Text(task.displayTitle)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Tema.texto)
                                .lineLimit(1)
                        }
                        if aoLado {
                            Image(systemName: "rectangle.split.2x1")
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(Tema.texto3)
                        }
                        Spacer(minLength: 2)
                        TimelineView(.periodic(from: .now, by: 30)) { _ in
                            Text(SessoesCrew.haQuanto(task.lastEvent))
                                .font(.system(size: 10.5))
                                .foregroundStyle(Tema.texto3)
                        }
                    }
                    HStack(spacing: 4) {
                        Text(SessoesCrew.rotulo(task, esperando: esperando)).foregroundStyle(cor)
                        // Qual modelo de IA a sessão usa.
                        if let m = modelos.nome(de: task) {
                            Text("· \(m)").foregroundStyle(Tema.texto2).layoutPriority(1)
                        }
                        if let b = Projetos.branch(de: task.sessionCwd) {
                            Text("· \(b)").foregroundStyle(Tema.texto3).truncationMode(.middle)
                        }
                        if task.oculta { Text("· oculta").foregroundStyle(Tema.texto3) }
                        else if task.parada { Text("· parada").foregroundStyle(Tema.texto3) }
                    }
                    .font(.system(size: 11))
                    .lineLimit(1)
                    if let brief = task.brief, !brief.isEmpty {
                        Text(brief)
                            .font(.system(size: 11))
                            .foregroundStyle(Tema.texto3)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Tema.raioLinha, style: .continuous).fill(fundo))
            .overlay {
                if esperando {
                    RoundedRectangle(cornerRadius: Tema.raioLinha, style: .continuous)
                        .strokeBorder(Tema.ambar.opacity(escolhida ? 0.55 : 0.28))
                }
            }
            .opacity(task.ativa || esperando ? 1 : 0.55)
        }
    }

    private var corAtencao: Color { task.state == .error ? Tema.vermelho : Tema.verde }

    private var fundo: Color {
        if atencao, !escolhida { return corAtencao.opacity(hover ? 0.12 : 0.08) }
        if esperando { return Tema.ambar.opacity(escolhida ? 0.16 : hover ? 0.12 : 0.08) }
        return escolhida ? Tema.selecao : hover ? Tema.hover : .clear
    }
}

/// Um projeto: cor, nome, pasta e quantas sessões abertas. Clicar abre o painel dele.
private struct LinhaProjetoCrew: View {
    let projeto: ProjetoCrew
    let sessoes: Int
    let escolhido: Bool
    /// Arquivado: mais apagado, e clicar o traz de volta.
    var apagado = false
    var config = ConfigProjeto()
    /// Ações do "…" que aparece ao passar o mouse.
    let menu: @MainActor () -> [ItemMenu]
    let acao: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: acao) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color(hex: projeto.cor).opacity(0.16))
                    .frame(width: 28, height: 28)
                    .overlay {
                        Image(systemName: config.icone ?? "folder.fill")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Color(hex: projeto.cor))
                    }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(projeto.nome)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Tema.texto)
                            .lineLimit(1)
                        if config.fixado {
                            Image(systemName: "pin.fill").font(.system(size: 8)).foregroundStyle(Tema.texto3)
                        }
                    }
                    Text(projeto.caminhoCurto)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Tema.texto3)
                        .lineLimit(1).truncationMode(.head)
                }
                Spacer(minLength: 4)
                if hover {
                    // Lugar do "…" (vem por cima, fora do botão da linha).
                    Color.clear.frame(width: 28, height: 18)
                } else if sessoes > 0 {
                    Text("\(sessoes)")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(Tema.texto2)
                        .padding(.horizontal, 6)
                        .frame(minWidth: 20, minHeight: 18)
                        .background(Pilula().fill(Color.white.opacity(0.07)))
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Tema.raioLinha, style: .continuous)
                .fill(escolhido ? Tema.selecao : hover ? Tema.hover : .clear))
            .contentShape(RoundedRectangle(cornerRadius: Tema.raioLinha))
            .opacity(apagado ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .help(apagado ? "Arquivado — clique para abrir o painel; o menu traz de volta"
              : sessoes == 0 ? "Abrir \(projeto.nome)"
              : "Abrir \(projeto.nome) (\(sessoes) sess\(sessoes == 1 ? "ão aberta" : "ões abertas"))")
        .overlay(alignment: .trailing) {
            if hover {
                BotaoIconeMenu(icone: "ellipsis", ajuda: "Nova sessão, fixar, arquivar…", itens: menu)
                    .padding(.trailing, 4)
            }
        }
        .onHover { hover = $0 }
    }
}

/// "Paradas e ocultas": mostra também as sessões que saíram da frente.
private struct AlternadorParadas: View {
    @Binding var ligado: Bool
    let quantas: Int
    @State private var hover = false

    var body: some View {
        Button { ligado.toggle() } label: {
            HStack(spacing: 5) {
                Image(systemName: ligado ? "eye.fill" : "eye.slash")
                    .font(.system(size: 10, weight: .medium))
                Text(quantas == 0 ? "Paradas e ocultas" : "Paradas e ocultas · \(quantas)")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(ligado || hover ? Tema.texto : Tema.texto3)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(Pilula().fill(ligado ? Tema.selecao : hover ? Tema.hover : .clear))
            .contentShape(Pilula())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(ligado ? "Esconder as sessões paradas e ocultas" : "Mostrar também as sessões paradas e ocultas")
    }
}

/// Lista vazia da barra lateral: um ícone apagado, uma frase e, se couber, uma ação.
struct VaziaLateral: View {
    let icone: String
    let texto: String
    var acao: (titulo: String, fazer: () -> Void)? = nil

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icone)
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(Tema.texto3)
            Text(texto)
                .font(.system(size: 12))
                .foregroundStyle(Tema.texto3)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let acao {
                BotaoPilula(titulo: acao.titulo, icone: "plus", altura: 28, acao: acao.fazer)
            }
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
