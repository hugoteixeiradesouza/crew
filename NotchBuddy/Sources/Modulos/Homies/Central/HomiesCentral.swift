import SwiftUI

// A tela dos Homies: a equipe à esquerda, a conversa com o escolhido à direita.
// Sem conversa aberta, o Homie recebe o pedido num campo grande; aberta, ela aparece aqui mesmo
// (a mesma conversa das sessões). Enquanto o Claude Code ainda não começou — na primeira vez
// ele pergunta se confia na pasta —, o terminal dela fica à vista para o Hugo responder.
// Além da conversa, cada Homie tem "Hoje" (as páginas das rotinas dele, com as ações esperando
// o clique) e "Rotinas" (o que ele entrega sozinho e quando) — ver `HomieRotinas.swift`.
// A equipe aparece em árvore: quem coordena, e embaixo quem responde a ele.

struct HomiesCentral: View {
    private let s = HomiesServico.shared
    @ObservedObject private var state = AppState.shared
    @Environment(\.recuoTitulo) private var recuoTitulo

    @State private var escolhido: UUID?
    @State private var pedidos: [UUID: String] = [:]
    /// Homies em que o Hugo pediu "nova conversa": o campo volta, mesmo com uma aberta.
    @State private var compondo: Set<UUID> = []
    @State private var editando: Homie?
    /// A folha do briefing de um Homie novo.
    @State private var briefing = false
    @State private var tirando: Homie?
    @State private var bagagem = HomiesServico.Bagagem()
    /// A aba aberta de cada Homie (sem escolha = conversa).
    @State private var abas: [UUID: Aba] = [:]
    /// A página de ferramentas do módulo no lugar do painel do Homie.
    @State private var verFerramentas = false

    enum Aba: String, CaseIterable { case conversa = "Conversa", hoje = "Hoje", rotinas = "Rotinas", ferramentas = "Ferramentas" }
    @FocusState private var foco: Bool

    private var atual: Homie? { s.homies.first { $0.id == escolhido } ?? s.homies.first }

    /// A conversa do Homie na lista de sessões (nil = nenhuma aberta).
    private func conversa(_ h: Homie) -> AgentTask? {
        guard let sid = h.ultimaSessao else { return nil }
        return state.tasks.first { $0.sessionId == sid }
    }

    var body: some View {
        HStack(spacing: 0) {
            equipe
                .frame(width: 236)
                .background(Tema.lateral)
            Rectangle().fill(Tema.borda).frame(width: 1)
            Group {
                if verFerramentas { FerramentasDoModulo() } else if let h = atual { painel(h) } else { vazio }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Tema.fundo)
        .onAppear {
            s.iniciar()
            if let h = atual { bagagem = s.bagagem(h.id); s.carregarPaginas(h.id) }
            atenderPedidoDeTela()
        }
        .onChange(of: atual?.id) { _, id in
            if let id { s.lerFicha(id); bagagem = s.bagagem(id); s.carregarPaginas(id) }
        }
        // Clique no aviso do notch: vai para a página daquele Homie.
        .onChange(of: s.mostrarHoje) { _, _ in atenderPedidoDeTela() }
        // A conversa andou: a montagem pode ter escrito a ficha, uma skill, um MCP, uma nota.
        .onChange(of: atual.flatMap { conversa($0)?.lastEvent }) { _, _ in
            if let id = atual?.id { s.lerFicha(id); bagagem = s.bagagem(id) }
        }
        .sheet(isPresented: $briefing) {
            BriefingHomie(montar: { texto, nome in
                briefing = false
                if let id = s.montar(briefing: texto, nome: nome) { escolhido = id }
            }, aMao: {
                briefing = false
                editando = Homie()
            }, cancelar: { briefing = false })
        }
        .sheet(item: $editando) { h in
            HomieEditor(homie: h, novo: s.homie(h.id) == nil,
                        coordenadores: s.homies.filter { PoliticaHomies.podeCoordenar($0.id, a: h.id, em: s.homies) && !$0.emConstrucao },
                        salvar: { s.salvar($0); escolhido = $0.id; editando = nil },
                        cancelar: { editando = nil })
        }
        .alert(tirando.map { "Tirar \($0.nome) da equipe?" } ?? "",
               isPresented: Binding(get: { tirando != nil }, set: { if !$0 { tirando = nil } }),
               presenting: tirando) { h in
            Button("Tirar", role: .destructive) { s.tirar(h.id); escolhido = nil }
            Button("Cancelar", role: .cancel) {}
        } message: { _ in
            Text("Ele sai da equipe. A pasta dele (guia, notas, skills) e as conversas continuam no disco.")
        }
    }

    // MARK: Equipe (coluna da esquerda)

    private var equipe: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Homies").font(Tema.titulo(16, .bold)).foregroundStyle(Tema.texto)
                Spacer()
                BotaoIcone(icone: "plus", ajuda: "Novo Homie: você explica o que quer e o Claude Code monta com você", lado: 26) { briefing = true }
                    .disabled(s.arquivoIlegivel)
            }
            .padding(.leading, 16 + recuoTitulo).padding(.trailing, 10)
            .frame(height: 52)

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(PoliticaHomies.equipe(s.homies), id: \.homie.id) { item in
                        let h = item.homie
                        LinhaHomie(homie: h, escolhido: !verFerramentas && atual?.id == h.id, estado: estado(h), pendentes: pendentes(h),
                                   coordena: s.homies.contains { $0.chefe == h.id }) { escolhido = h.id; verFerramentas = false }
                            .padding(.leading, CGFloat(item.nivel) * 14)
                    }
                }
                .padding(.horizontal, 8)
            }
            .scrollIndicators(.never)

            Fio()
            Button { verFerramentas = true } label: {
                HStack(spacing: 9) {
                    Image(systemName: "puzzlepiece.extension").font(.system(size: 12.5)).frame(width: 20)
                    Text("Ferramentas").font(.system(size: 12.5, weight: .medium))
                    Spacer()
                }
                .foregroundStyle(verFerramentas ? Tema.texto : Tema.texto2)
                .padding(.horizontal, 10).frame(height: 32)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(verFerramentas ? Tema.selecao : .clear))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Conectar ferramentas uma vez; em cada Homie você ativa as que quer")
            .padding(8)

            if s.arquivoIlegivel {
                Text("Não consegui ler o homies.json. Ele ficou como está e nada é gravado por cima.")
                    .font(.system(size: 11)).foregroundStyle(Tema.ambar)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
            }
        }
    }

    /// Ações de páginas dele que ainda esperam o clique.
    private func pendentes(_ h: Homie) -> Int {
        RotinasServico.shared.doHomie(h.id).reduce(0) { $0 + (s.paginas[$1.id]?.pendentes.count ?? 0) }
    }

    private func atenderPedidoDeTela() {
        guard let id = s.mostrarHoje, s.homie(id) != nil else { return }
        s.mostrarHoje = nil
        escolhido = id
        verFerramentas = false
        abas[id] = .hoje
        s.carregarPaginas(id)
    }

    private func estado(_ h: Homie) -> LinhaHomie.Estado {
        if s.abrindo.contains(h.id) || s.esperando[h.id] != nil { return .abrindo }
        guard let t = conversa(h) else { return .livre }
        return SessoesCrew.esperando(t, state) ? .esperaVoce : .conversando
    }

    // MARK: Painel do Homie (direita)

    private func painel(_ h: Homie) -> some View {
        let aberta = compondo.contains(h.id) ? nil : conversa(h)
        let aba = abas[h.id] ?? .conversa
        let esperam = pendentes(h)
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                HomieVivo(tamanho: 34, quadro: 1.0 / 24.0).frame(width: 34, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(h.nome).font(.system(size: 14, weight: .semibold)).foregroundStyle(Tema.texto).lineLimit(1)
                    Text(h.emConstrucao ? "em montagem: esta é a conversa com o montador" : h.funcao.isEmpty ? "Homie" : h.funcao)
                        .font(.system(size: 11.5)).foregroundStyle(h.emConstrucao ? Tema.azul : Tema.texto3).lineLimit(1)
                }
                Spacer(minLength: 8)
                HStack(spacing: 2) {
                    ForEach(Aba.allCases, id: \.self) { a in
                        Button { abas[h.id] = a } label: {
                            Text(a == .hoje && esperam > 0 ? "Hoje · \(esperam)" : a.rawValue)
                                .font(.system(size: 12, weight: aba == a ? .semibold : .medium))
                                .foregroundStyle(aba == a ? Tema.texto : a == .hoje && esperam > 0 ? Tema.ambar : Tema.texto3)
                                .padding(.horizontal, 11).frame(height: 26)
                                .background(Capsule().fill(aba == a ? Tema.selecao : .clear))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(Capsule().fill(Color.white.opacity(0.04)))
                .opacity(h.emConstrucao ? 0 : 1).disabled(h.emConstrucao)
                Spacer(minLength: 8)
                if aberta != nil, aba == .conversa {
                    BotaoPilula(titulo: "Nova conversa", icone: "plus.bubble", estilo: .discreto, altura: 28) {
                        compondo.insert(h.id)
                        foco = true
                    }
                    .help("Começa outra conversa com ele. A atual continua nas sessões.")
                }
                BotaoIcone(icone: "folder", ajuda: "A pasta dele: o guia (CLAUDE.md), os MCPs (.mcp.json), as skills (.claude/skills) e as notas") {
                    s.abrirPasta(h.id)
                }
                BotaoIcone(icone: "slider.horizontal.3", ajuda: "Nome, função, instrução, modelo e a quem ele responde") { editando = h }
                BotaoIcone(icone: "trash", ajuda: "Tirar da equipe") { tirando = h }
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            Fio()

            Group {
                if aba == .hoje, !h.emConstrucao {
                    HojeHomie(homie: h, foiPara: { alvo in
                        compondo.remove(alvo); abas[alvo] = .conversa; escolhido = alvo
                    }, irParaRotinas: { abas[h.id] = .rotinas })
                    .id(h.id)
                } else if aba == .rotinas, !h.emConstrucao {
                    RotinasDoHomie(homie: h, irParaHoje: { abas[h.id] = .hoje })
                        .id(h.id)
                } else if aba == .ferramentas, !h.emConstrucao {
                    FerramentasDoHomie(homie: h, abrirModulo: { verFerramentas = true })
                        .id(h.id)
                } else if let sid = s.esperando[h.id] {
                    espera(h, sid)
                } else if let t = aberta {
                    ConversaCrew(taskId: t.id, compacto: true, emFoco: true)
                        .id(t.id)
                        .environment(\.recuoTitulo, 0)
                } else {
                    entrada(h)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Sem conversa na tela: o Homie, o campo do pedido e o que ele tem.
    private func entrada(_ h: Homie) -> some View {
        let ocupado = s.abrindo.contains(h.id)
        let pedido = Binding(get: { pedidos[h.id] ?? "" }, set: { pedidos[h.id] = $0 })
        let anterior = conversa(h)
        return VStack(spacing: 18) {
            Spacer(minLength: 0)
            HomieVivo(estado: ocupado ? .working : .idle, tamanho: 120).frame(width: 120, height: 96)
            VStack(spacing: 5) {
                Text("Fala com \(h.nome)").font(Tema.titulo(22, .bold)).foregroundStyle(Tema.texto)
                if !h.funcao.isEmpty {
                    Text(h.funcao).font(.system(size: 13)).foregroundStyle(Tema.texto2)
                }
            }

            HStack(alignment: .bottom, spacing: 8) {
                TextField("Peça algo a \(h.nome)…", text: pedido, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundStyle(Tema.texto)
                    .lineLimit(1...8)
                    .focused($foco)
                    .onSubmit { conversar(h) }
                    .padding(.vertical, 6)
                BotaoPilula(titulo: "Conversar", icone: "arrow.up", estilo: .ambar, altura: 32, ocupado: ocupado) { conversar(h) }
                    .disabled(ocupado || MotorCrew.motivoIndisponivel != nil)
            }
            .padding(.leading, 16).padding(.trailing, 8).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: Tema.raioCartao, style: .continuous).fill(Tema.painel))
            .overlay(RoundedRectangle(cornerRadius: Tema.raioCartao, style: .continuous).strokeBorder(Tema.borda))
            .frame(maxWidth: 640)

            HStack(spacing: 8) {
                if compondo.contains(h.id), anterior != nil {
                    BotaoPilula(titulo: "Voltar à conversa", icone: "arrow.uturn.backward", estilo: .discreto, altura: 28) {
                        compondo.remove(h.id)
                    }
                } else if anterior == nil, h.ultimaSessao != nil {
                    BotaoPilula(titulo: "Continuar a última", icone: "arrow.uturn.backward", estilo: .discreto, altura: 28) {
                        s.continuar(h.id)
                    }
                    .help("Retoma a última conversa com ele, de onde parou")
                    .disabled(ocupado)
                }
                etiqueta("\(bagagem.skills) skill\(bagagem.skills == 1 ? "" : "s")", "sparkles")
                etiqueta("\(bagagem.mcps) MCP\(bagagem.mcps == 1 ? "" : "s")", "puzzlepiece.extension")
                etiqueta("\(bagagem.notas) nota\(bagagem.notas == 1 ? "" : "s")", "note.text")
            }

            if let m = MotorCrew.motivoIndisponivel {
                Text("Sem motor de sessões neste Mac: \(m)").font(.system(size: 11.5)).foregroundStyle(Tema.ambar)
            }
            if let a = s.aviso {
                Text(a).font(.system(size: 11.5)).foregroundStyle(Tema.ambar).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 640)
            }
            Spacer(minLength: 0)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { foco = true }
    }

    private func etiqueta(_ texto: String, _ icone: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icone).font(.system(size: 10, weight: .medium))
            Text(texto).font(.system(size: 11.5, weight: .medium))
        }
        .foregroundStyle(Tema.texto3)
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(Capsule().fill(Color.white.opacity(0.04)))
        .help("O que há na pasta dele. Para mudar, abra a pasta.")
    }

    /// A conversa abriu no terminal mas o Claude Code ainda não começou: quase sempre é ele
    /// perguntando se confia na pasta (só na primeira vez). O Hugo responde aqui mesmo.
    private func espera(_ h: Homie, _ sid: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Abrindo a conversa com \(h.nome)…")
                    .font(Tema.titulo(17)).foregroundStyle(Tema.texto)
                Text("Se o Claude Code perguntar algo antes de começar (na primeira vez, se confia na pasta dele), responda aqui no terminal. A conversa aparece em seguida.")
                    .font(.system(size: 12.5)).foregroundStyle(Tema.texto2).fixedSize(horizontal: false, vertical: true)
            }
            TerminalSessao(sessionId: sid)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .frame(maxHeight: 380)
            HStack(spacing: 8) {
                BotaoPilula(titulo: "Abrir no Terminal", icone: "macwindow", altura: 30) {
                    Task { await MotorCrew.abrirNoTerminal(sid) }
                }
                Spacer()
                BotaoPilula(titulo: "Fechar", estilo: .discreto, altura: 30) { s.dispensarEspera(h.id) }
                    .help("Esconde o terminal. A conversa continua aberta: \"Continuar a última\" volta a ela.")
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: 860, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity)
    }

    private var vazio: some View {
        VStack(spacing: 12) {
            Text("Nenhum Homie na equipe").font(Tema.titulo(17)).foregroundStyle(Tema.texto)
            BotaoPilula(titulo: "Novo Homie", icone: "plus", estilo: .ambar) { briefing = true }
                .disabled(s.arquivoIlegivel)
        }
    }

    private func conversar(_ h: Homie) {
        let texto = (pedidos[h.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        pedidos[h.id] = ""
        compondo.remove(h.id)
        s.conversar(h.id, pedido: texto)
    }
}

// MARK: - Linha da equipe

private struct LinhaHomie: View {
    enum Estado { case livre, abrindo, conversando, esperaVoce }

    let homie: Homie
    let escolhido: Bool
    let estado: Estado
    /// Ações de páginas dele esperando o clique do Hugo.
    var pendentes = 0
    /// Tem gente respondendo a ele.
    var coordena = false
    let acao: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: acao) {
            HStack(spacing: 10) {
                HomieVivo(estado: estado == .abrindo ? .working : .idle, tamanho: 30, quadro: 1.0 / 12.0)
                    .frame(width: 30, height: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(homie.nome).font(.system(size: 13, weight: escolhido ? .semibold : .medium))
                        .foregroundStyle(Tema.texto).lineLimit(1)
                    Text(legenda).font(.system(size: 11)).foregroundStyle(estado == .esperaVoce ? Tema.ambar : Tema.texto3).lineLimit(1)
                }
                Spacer(minLength: 4)
                if pendentes > 0 {
                    Text("\(pendentes)").font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Tema.sobreDestaque)
                        .padding(.horizontal, 5).frame(minWidth: 17, minHeight: 17)
                        .background(Capsule().fill(Tema.ambar))
                        .help("\(pendentes) \(pendentes == 1 ? "ação espera" : "ações esperam") o seu clique na aba Hoje")
                }
                if let cor { Circle().fill(cor).frame(width: 7, height: 7) }
            }
            .padding(.horizontal, 8).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Tema.raioLinha, style: .continuous)
                .fill(escolhido ? Tema.selecao : hover ? Tema.hover : .clear))
            .contentShape(RoundedRectangle(cornerRadius: Tema.raioLinha))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }

    private var legenda: String {
        switch estado {
        case .abrindo: "abrindo a conversa…"
        case .esperaVoce: "esperando você"
        case .conversando, .livre:
            homie.emConstrucao ? "em montagem" : homie.funcao.isEmpty ? (coordena ? "coordena o time" : "Homie") : homie.funcao
        }
    }

    private var cor: Color? {
        switch estado {
        case .livre: nil
        case .abrindo: Tema.azul
        case .conversando: Tema.verde
        case .esperaVoce: Tema.ambar
        }
    }
}

// MARK: - Briefing

/// Homie novo: o Hugo explica o que quer e o Claude Code monta com ele (guia, skills, MCPs,
/// contexto). Quem prefere preencher os campos tem o formulário.
struct BriefingHomie: View {
    let montar: (_ briefing: String, _ nome: String) -> Void
    let aMao: () -> Void
    let cancelar: () -> Void

    @State private var texto = ""
    @State private var nome = ""
    @FocusState private var foco: Bool

    private var vazio: Bool { texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Novo Homie").font(.system(size: 16, weight: .semibold))
                Text("Explique do seu jeito o que você quer que ele faça por você: a função, o que entrega, com o que trabalha, o que não pode fazer sem pedir. O Claude Code abre uma conversa, pergunta o que faltar e monta o Homie com você: guia, skills, MCPs e contexto, tudo na pasta dele.")
                    .font(.system(size: 12)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            ZStack(alignment: .topLeading) {
                TextEditor(text: $texto)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .focused($foco)
                    .padding(8)
                if texto.isEmpty {
                    Text("Ex.: quero um Homie que cuide das minhas cobranças. Toda manhã ele confere quem está devendo, me mostra a lista e redige a mensagem para cada um, mas só envia quando eu aprovar…")
                        .font(.system(size: 13)).foregroundColor(.secondary.opacity(0.7))
                        .padding(.horizontal, 13).padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 190)
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 5) {
                Text("Nome (opcional)").font(.system(size: 11, weight: .medium)).foregroundColor(.secondary)
                TextField("Se deixar em branco, o nome sai da conversa", text: $nome).textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("Preencher à mão", action: aMao)
                    .buttonStyle(.link)
                    .help("O formulário: nome, função, instrução e modelo, sem conversa")
                Spacer()
                Button("Cancelar", action: cancelar).keyboardShortcut(.cancelAction)
                Button("Montar com o Claude") { montar(texto, nome) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(vazio || MotorCrew.motivoIndisponivel != nil)
                    .help("Abre a conversa de montagem (⌘↩)")
            }
        }
        .padding(20)
        .frame(width: 540)
        .onAppear { foco = true }
    }
}

// MARK: - Editor

/// Criar/editar um Homie: nome, função, instrução e modelo.
struct HomieEditor: View {
    @State var homie: Homie
    let novo: Bool
    /// Quem pode coordenar este Homie (os outros, menos quem já responde a ele).
    var coordenadores: [Homie] = []
    let salvar: (Homie) -> Void
    let cancelar: () -> Void

    private static let modelos: [(valor: String?, titulo: String)] = [
        (nil, "Padrão"), ("fable", "Fable"), ("opus", "Opus"), ("sonnet", "Sonnet"), ("haiku", "Haiku"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(novo ? "Novo Homie" : "Editar \(homie.nome)").font(.system(size: 15, weight: .semibold))

            campo("Nome") {
                TextField("Homie", text: $homie.nome).textFieldStyle(.roundedBorder)
            }
            campo("Função") {
                TextField("Assistente pessoal", text: $homie.funcao).textFieldStyle(.roundedBorder)
            }
            campo("Instrução") {
                TextEditor(text: $homie.instrucao)
                    .font(.system(size: 12.5))
                    .frame(height: 120)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Text("Vai em toda conversa com ele, junto do guia (CLAUDE.md) da pasta dele.")
                    .font(.system(size: 10.5)).foregroundColor(.secondary)
            }
            campo("Modelo") {
                SeletorCrew(selecao: $homie.modelo, opcoes: Self.modelos)
            }
            if !coordenadores.isEmpty {
                campo("Responde a") {
                    SeletorCrew(selecao: $homie.chefe,
                                opcoes: [(valor: UUID?.none, titulo: "Ninguém")] + coordenadores.map { (valor: UUID?.some($0.id), titulo: $0.nome) })
                    Text(homie.chefe == nil
                         ? "Escolha um Homie para coordenar este: ele passa trabalho a quem responde a ele e junta os resultados numa resposta só."
                         : "O coordenador enxerga a pasta deste Homie e pode passar a ele a parte que for da função dele.")
                        .font(.system(size: 10.5)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            if novo {
                Text("Ao salvar, ele ganha uma pasta própria. MCPs e skills dele entram por lá.")
                    .font(.system(size: 10.5)).foregroundColor(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancelar", action: cancelar).keyboardShortcut(.cancelAction)
                Button("Salvar") { salvar(homie) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(homie.nome.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func campo<C: View>(_ titulo: String, @ViewBuilder _ conteudo: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(titulo).font(.system(size: 11, weight: .medium)).foregroundColor(.secondary)
            conteudo()
        }
    }
}
