import SwiftUI
import AppKit

// As abas de configuração do painel do projeto: Detalhes, Sessões novas, Claude Code e Avisos.
// Tudo grava na hora em `ConfigProjetos` — menos o CLAUDE.md, que é arquivo do repositório e
// só muda no "Salvar", depois de dizer quantas linhas saem e entram.

// MARK: - Detalhes

struct ProjetoDetalhes: View {
    let projeto: ProjetoCrew
    let git: GitDoProjeto
    @ObservedObject private var config = ConfigProjetos.shared
    @ObservedObject private var projetos = ProjetosCrew.shared

    private var raiz: String { projeto.caminho }
    private var pasta: String { (raiz as NSString).lastPathComponent }

    var body: some View {
        CartaoPainel(titulo: "Como aparece") {
            LinhaAjuste(titulo: "Nome", detalhe: "Vale na lista, na ilha e nas sessões. Vazio = o nome da pasta (\(pasta)).") {
                CampoPainel(dica: pasta, texto: config.texto(raiz, \.nome))
            }
            Fio()
            LinhaAjuste(titulo: "Cor", detalhe: "A mesma cor marca as sessões dele na ilha.") {
                HStack(spacing: 6) {
                    ForEach(Projetos.cores, id: \.self) { hex in
                        Button {
                            Projetos.definirCor(raiz, hex)
                            Task { await projetos.recarregar() }
                        } label: {
                            Circle().fill(Color(hex: hex)).frame(width: 18, height: 18)
                                .overlay(Circle().strokeBorder(Color.white, lineWidth: projeto.cor.caseInsensitiveCompare(hex) == .orderedSame ? 2 : 0))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Fio()
            LinhaAjuste(titulo: "Ícone") {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: 4), count: 8), spacing: 4) {
                    ForEach(OpcoesSessao.icones, id: \.self) { nome in
                        let escolhido = (config.de(raiz).icone ?? "folder.fill") == nome
                        Button {
                            config.mudar(raiz) { $0.icone = nome == "folder.fill" ? nil : nome }
                        } label: {
                            Image(systemName: nome).font(.system(size: 12))
                                .foregroundStyle(escolhido ? Color(hex: projeto.cor) : Tema.texto2)
                                .frame(width: 28, height: 28)
                                .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(escolhido ? Color(hex: projeto.cor).opacity(0.16) : Color.white.opacity(0.04)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(width: 252)
            }
            Fio()
            LinhaAjuste(titulo: "Fixar no topo da lista", detalhe: "A ordem entre os projetos muda no menu “…” de cada um.") {
                ChavePainel(ligada: Binding(get: { config.de(raiz).fixado }, set: { v in
                    config.mudar(raiz) { $0.fixado = v }
                    Task { await projetos.recarregar() }
                }))
            }
        }
        .onChange(of: config.de(raiz).nome) { _, _ in Task { await projetos.recarregar() } }

        CartaoPainel(titulo: "Nota", detalhe: "aparece no topo da Visão geral") {
            TextoPainel(texto: config.campo(raiz, \.nota),
                        dica: "De quem é, para que serve, o que não pode tocar…", altura: 96)
        }

        CartaoPainel(titulo: "Onde mora") {
            VStack(alignment: .leading, spacing: 8) {
                LinhaDado(rotulo: "Pasta", valor: raiz, mono: true)
                LinhaDado(rotulo: "Remoto", valor: git.remoto ?? (git.ehRepositorio ? "nenhum (só neste Mac)" : "não é um repositório git"),
                          mono: git.remoto != nil)
                LinhaDado(rotulo: "Na lista porque", valor: projeto.adicionado ? "você adicionou a pasta" : "tem sessão aberta nela")
            }
        }
    }
}

// MARK: - Sessões novas

struct ProjetoSessoesNovas: View {
    let projeto: ProjetoCrew
    @ObservedObject private var config = ConfigProjetos.shared
    private var raiz: String { projeto.caminho }
    private var c: ConfigProjeto { config.de(raiz) }

    var body: some View {
        CartaoPainel(titulo: "Toda sessão nova neste projeto nasce com",
                     detalhe: "dá para trocar na hora, no campo do pedido") {
            LinhaAjuste(titulo: "Modelo") {
                SeletorCrew(selecao: config.campo(raiz, \.modelo),
                            opcoes: OpcoesSessao.modelos.map { ($0.valor, $0.nome) }, largura: 180)
            }
            Fio()
            LinhaAjuste(titulo: "Esforço", detalhe: "Quanto o Claude Code pensa antes de responder.") {
                SeletorCrew(selecao: config.campo(raiz, \.esforco),
                            opcoes: OpcoesSessao.esforcos.map { ($0.valor, $0.nome) }, largura: 180)
            }
            Fio()
            LinhaAjuste(titulo: "Permissões",
                        detalhe: OpcoesSessao.modos.first { $0.valor == c.modo }?.detalhe) {
                SeletorCrew(selecao: config.campo(raiz, \.modo),
                            opcoes: OpcoesSessao.modos.map { ($0.valor, $0.nome) }, largura: 180)
            }
        }

        CartaoPainel(titulo: "Instrução fixa", detalhe: "vai junto das instruções do Claude Code em toda sessão aberta pelo Crew") {
            TextoPainel(texto: config.campo(raiz, \.instrucao),
                        dica: "Ex.: responda sempre em português; nunca edite a raiz do repositório.", altura: 110)
            Text("Só vale para sessões abertas pelo Crew. O que deve valer em qualquer lugar mora no CLAUDE.md (aba Claude Code).")
                .font(.system(size: 11.5)).foregroundStyle(Tema.texto3)
        }

        CartaoPainel(titulo: "Isolamento") {
            LinhaAjuste(titulo: "Cada sessão numa pasta própria",
                        detalhe: "Antes de abrir, o Crew roda o comando do projeto que cria a pasta (uma worktree, por exemplo) e abre a sessão nela.") {
                ChavePainel(ligada: config.campo(raiz, \.isolar))
            }
            if c.isolar {
                Fio()
                LinhaAjuste(titulo: "Comando", detalhe: "Roda na raiz do projeto. {nome} vira o nome da sessão.") {
                    CampoPainel(dica: "scripts/sessao.sh {nome}", texto: config.campo(raiz, \.comandoIsolar), mono: true, largura: 300)
                }
                Fio()
                LinhaAjuste(titulo: "Pasta que ele cria", detalhe: "A partir da raiz. É onde a sessão abre.") {
                    CampoPainel(dica: ".coucou-sessoes/{nome}", texto: config.campo(raiz, \.pastaIsolar), mono: true, largura: 300)
                }
                if c.isolamentoPronto {
                    let nome = IsolamentoProjeto.nome(doPedido: "arrumar o botão de salvar")
                    AvisoPainel(texto: "Exemplo: o pedido “arrumar o botão de salvar” roda `\(c.comandoIsolar.replacingOccurrences(of: "{nome}", with: nome))` e abre em \(c.pastaIsolar.replacingOccurrences(of: "{nome}", with: nome)). Se o comando falhar, a sessão não abre e o erro aparece no campo.",
                                cor: Tema.azul, icone: "info.circle.fill")
                } else {
                    AvisoPainel(texto: "Preencha o comando e a pasta: enquanto faltar um dos dois, a sessão abre na raiz, como sempre.", cor: Tema.ambar)
                }
            }
        }
    }
}

// MARK: - Claude Code

struct ProjetoClaude: View {
    let projeto: ProjetoCrew
    private var raiz: String { projeto.caminho }

    @State private var original: String?
    @State private var texto = ""
    @State private var leu = false
    @State private var confirmando = false
    @State private var salvando = false
    @State private var erro: String?
    @State private var claude = ClaudeDoProjeto()
    @State private var memorias: [MemoriaDoProjeto] = []

    private var mudou: Bool { leu && texto != (original ?? "") }
    private var caminhoMd: String { LeitorProjeto.caminhoClaudeMd(raiz) }

    var body: some View {
        claudeMd
        servidores
        permissoes
        memoriasBloco
            .task(id: raiz) {
                async let md = LeitorProjeto.lerClaudeMd(raiz)
                async let cl = LeitorProjeto.claude(raiz)
                async let me = LeitorProjeto.memorias(raiz)
                original = await md
                texto = original ?? ""
                leu = true
                claude = await cl
                memorias = await me
            }
    }

    private var claudeMd: some View {
        CartaoPainel(titulo: "CLAUDE.md", detalhe: original == nil && leu ? "ainda não existe" : String(caminhoMd.dropFirst(raiz.count + 1))) {
            TextoPainel(texto: $texto, dica: "As instruções que o Claude Code lê toda vez que abre este projeto.",
                        mono: true, altura: 340)
            if let erro { AvisoPainel(texto: "Não salvou: \(erro)", cor: Tema.vermelho) }
            if confirmando {
                let d = LeitorProjeto.diferenca(de: original ?? "", para: texto)
                AvisoPainel(texto: (original == nil ? "Cria o arquivo com \(d.entram) linha\(d.entram == 1 ? "" : "s")."
                                    : "\(d.saem) linha\(d.saem == 1 ? " sai" : "s saem") e \(d.entram) entra\(d.entram == 1 ? "" : "m").")
                            + " É arquivo do repositório: vira mudança não commitada. A versão de antes fica guardada na pasta do Crew.",
                            cor: Tema.ambar)
            }
            HStack(spacing: 8) {
                Text(mudou ? "Mudanças não salvas" : "Igual ao arquivo")
                    .font(.system(size: 11.5)).foregroundStyle(mudou ? Tema.ambar : Tema.texto3)
                Spacer()
                if mudou {
                    BotaoPilula(titulo: "Desfazer", estilo: .discreto, altura: 28) {
                        texto = original ?? ""; confirmando = false; erro = nil
                    }
                }
                if confirmando {
                    BotaoPilula(titulo: "Gravar no arquivo", estilo: .ambar, altura: 28, ocupado: salvando) { salvar() }
                } else {
                    BotaoPilula(titulo: "Salvar…", estilo: .primario, altura: 28) { confirmando = true }
                        .disabled(!mudou)
                }
            }
        }
        .onChange(of: texto) { _, _ in if !mudou { confirmando = false } }
    }

    private func salvar() {
        salvando = true
        erro = nil
        let novo = texto
        Task {
            erro = await LeitorProjeto.salvarClaudeMd(raiz, texto: novo)
            if erro == nil { original = novo }
            salvando = false
            confirmando = false
        }
    }

    private var servidores: some View {
        CartaoPainel(titulo: "Servidores MCP", detalhe: claude.servidores.isEmpty ? nil : "\(claude.servidores.count)") {
            if claude.servidores.isEmpty {
                Text("Nenhum servidor MCP configurado para este projeto.").font(.system(size: 12.5)).foregroundStyle(Tema.texto3)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(claude.servidores) { s in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle().fill(s.negado ? Tema.vermelho : Tema.verde).frame(width: 6, height: 6)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(s.nome).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Tema.texto)
                                if !s.alvo.isEmpty {
                                    Text(s.alvo).font(.system(size: 11, design: .monospaced)).foregroundStyle(Tema.texto3)
                                        .lineLimit(1).truncationMode(.middle)
                                }
                            }
                            Spacer(minLength: 8)
                            Text(s.negado ? "negado aqui" : s.origem.rawValue)
                                .font(.system(size: 11.5)).foregroundStyle(s.negado ? Tema.vermelho : Tema.texto3)
                        }
                    }
                }
            }
            Text("Só leitura por enquanto: ligar e negar servidor continua no Claude Code (/mcp).")
                .font(.system(size: 11.5)).foregroundStyle(Tema.texto3)
        }
    }

    private var permissoes: some View {
        CartaoPainel(titulo: "Permissões do projeto",
                     detalhe: claude.arquivos.isEmpty ? nil : claude.arquivos.joined(separator: " + ")) {
            if claude.permitidas.isEmpty && claude.negadas.isEmpty && claude.perguntar.isEmpty {
                Text("O projeto não tem permissões próprias: valem as suas, de todos os projetos.")
                    .font(.system(size: 12.5)).foregroundStyle(Tema.texto3)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    regras("Negadas", claude.negadas, Tema.vermelho)
                    regras("Sempre perguntar", claude.perguntar, Tema.ambar)
                    regras("Permitidas sem perguntar", claude.permitidas, Tema.verde)
                }
            }
        }
    }

    @ViewBuilder
    private func regras(_ titulo: String, _ lista: [String], _ cor: Color) -> some View {
        if !lista.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle().fill(cor).frame(width: 6, height: 6)
                    Text("\(titulo) · \(lista.count)").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Tema.texto2)
                }
                ForEach(Array(lista.prefix(12).enumerated()), id: \.offset) { _, r in
                    Text(r).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(Tema.texto2)
                        .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                }
                if lista.count > 12 {
                    Text("e mais \(lista.count - 12)").font(.system(size: 11.5)).foregroundStyle(Tema.texto3)
                }
            }
        }
    }

    private var memoriasBloco: some View {
        CartaoPainel(titulo: "Memórias", detalhe: memorias.isEmpty ? nil : "\(memorias.count)",
                     acao: memorias.isEmpty ? nil : ("Mostrar a pasta", {
                         NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: LeitorProjeto.pastaDoClaude(raiz) + "/memory")
                     })) {
            if memorias.isEmpty {
                Text("O Claude Code ainda não guardou nada sobre este projeto.").font(.system(size: 12.5)).foregroundStyle(Tema.texto3)
            } else {
                VStack(spacing: 2) {
                    ForEach(memorias) { m in
                        LinhaClicavel(ponto: Tema.cinza, titulo: m.nome, detalhe: m.descricao.isEmpty ? nil : m.descricao,
                                      direita: m.tipo.isEmpty ? nil : m.tipo) {
                            NSWorkspace.shared.open(URL(fileURLWithPath: m.caminho))
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Avisos

struct ProjetoAvisos: View {
    let projeto: ProjetoCrew
    let arquivado: Bool
    @ObservedObject private var config = ConfigProjetos.shared
    @ObservedObject private var projetos = ProjetosCrew.shared
    @EnvironmentObject private var nav: NavegacaoCrew
    @State private var confirmarExcluir = false
    private var raiz: String { projeto.caminho }

    var body: some View {
        CartaoPainel(titulo: "Avisos") {
            LinhaAjuste(titulo: "Som das sessões deste projeto",
                        detalhe: "Desligado, as sessões dele continuam avisando na ilha (cor, Homie, pedido de resposta), só sem som.") {
                ChavePainel(ligada: Binding(get: { !config.de(raiz).semSom },
                                            set: { v in config.mudar(raiz) { $0.semSom = !v } }))
            }
        }

        CartaoPainel(titulo: "Na lista do Crew", detalhe: "nada aqui toca a pasta") {
            LinhaAjuste(titulo: arquivado ? "Desarquivar" : "Arquivar",
                        detalhe: arquivado ? "Volta para a lista de projetos." : "Sai da lista e fica em “Arquivados”, de onde volta.") {
                BotaoPilula(titulo: arquivado ? "Desarquivar" : "Arquivar", icone: arquivado ? "tray.and.arrow.up" : "archivebox", altura: 28) {
                    Task {
                        if arquivado { await projetos.desarquivar(raiz) } else { await projetos.arquivar(raiz) }
                    }
                }
            }
            Fio()
            LinhaAjuste(titulo: "Excluir da lista",
                        detalhe: "Some do Crew até você adicionar a pasta de novo. A configuração deste painel fica guardada.") {
                if confirmarExcluir {
                    HStack(spacing: 6) {
                        BotaoPilula(titulo: "Cancelar", estilo: .discreto, altura: 28) { confirmarExcluir = false }
                        BotaoPilula(titulo: "Excluir mesmo", estilo: .perigo, altura: 28) {
                            if nav.projetoInicio == raiz { nav.projetoInicio = nil }
                            nav.selecao = .inicio
                            Task { await projetos.excluir(raiz) }
                        }
                    }
                } else {
                    BotaoPilula(titulo: "Excluir da lista", icone: "trash", estilo: .perigo, altura: 28) { confirmarExcluir = true }
                }
            }
        }
    }
}
