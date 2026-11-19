import SwiftUI
import AppKit

// Aba "Visão geral" do painel do projeto: o que está acontecendo nele agora — sessões, gasto,
// repositório, rotinas e disco. Só leitura; cada bloco leva a quem cuida do assunto.

struct ProjetoGeral: View {
    let projeto: ProjetoCrew
    let git: GitDoProjeto
    let leuGit: Bool
    let tamanho: Int64?
    let medindo: Bool
    let worktrees: [WorktreesAtivas.Worktree]
    let irPara: (PainelProjeto.Aba) -> Void

    @ObservedObject private var state = AppState.shared
    @ObservedObject private var historico = HistoricoCrew.shared
    @ObservedObject private var config = ConfigProjetos.shared
    @EnvironmentObject private var nav: NavegacaoCrew
    private var uso: UsoServico { UsoServico.shared }
    private var rotinasServico: RotinasServico { RotinasServico.shared }

    private var abertas: [AgentTask] {
        SessoesCrew.todas(state).filter { Projetos.raiz(de: $0.sessionCwd) == projeto.caminho }
            .sorted { $0.lastEvent > $1.lastEvent }
    }
    private var esperando: Int { abertas.filter { SessoesCrew.esperando($0, state) }.count }
    private var guardadas: [SessaoEncerrada] {
        let vivas = Set(state.tasks.compactMap(\.sessionId))
        return historico.lista.filter { Projetos.raiz(de: $0.pasta) == projeto.caminho && !vivas.contains($0.sessionId) }
    }
    private var rotinas: [Rotina] {
        rotinasServico.rotinas.filter { Projetos.raiz(de: $0.pasta) == projeto.caminho }
    }
    private func gasto(_ linhas: [LinhaUso]) -> ValorUso {
        linhas.first { $0.id == projeto.caminho }?.valor ?? ValorUso()
    }
    /// O sinal de uso mais novo que o Crew conhece: sessão aberta, conversa guardada ou commit.
    private var ultimoUso: Date? {
        [abertas.first?.lastEvent, guardadas.first?.quando, git.quandoCommit].compactMap { $0 }.max()
    }

    var body: some View {
        let nota = config.de(projeto.caminho).nota.trimmingCharacters(in: .whitespacesAndNewlines)
        VStack(alignment: .leading, spacing: 14) {
            if !nota.isEmpty {
                AvisoPainel(texto: nota, cor: Color(hex: projeto.cor), icone: "note.text")
            }
            numeros
            sessoes
            if !guardadas.isEmpty { conversas }
            repositorio
            rotinasBloco
            disco
        }
        .onAppear { if !CaptureTool.ativo { uso.atualizarSeVelho() } }
    }

    // MARK: Números

    private var numeros: some View {
        HStack(spacing: 10) {
            Numero(rotulo: "Sessões abertas", valor: "\(abertas.count)",
                   detalhe: esperando == 0 ? nil : esperando == 1 ? "1 pede resposta" : "\(esperando) pedem resposta",
                   cor: esperando > 0 ? Tema.ambar : Tema.texto)
            Numero(rotulo: "Gasto hoje", valor: FormatoUso.custo(gasto(uso.resumo.projetosHoje)), detalhe: "estimado")
            Numero(rotulo: "Gasto em 30 dias", valor: FormatoUso.custo(gasto(uso.resumo.projetosMes)), detalhe: "estimado")
            Numero(rotulo: "Último uso", valor: ultimoUso.map { SessoesCrew.haQuanto($0) } ?? "—",
                   detalhe: ultimoUso.map { $0.formatted(date: .abbreviated, time: .omitted) })
        }
    }

    // MARK: Sessões

    private var sessoes: some View {
        CartaoPainel(titulo: "Sessões abertas", detalhe: abertas.isEmpty ? nil : "\(abertas.count)") {
            if abertas.isEmpty {
                HStack {
                    Text("Nenhuma sessão aberta neste projeto.").font(.system(size: 12.5)).foregroundStyle(Tema.texto3)
                    Spacer()
                    BotaoPilula(titulo: "Nova sessão", icone: "plus", altura: 28) { nav.novaSessao(em: projeto.caminho) }
                }
            } else {
                VStack(spacing: 2) {
                    ForEach(abertas) { t in
                        let pede = SessoesCrew.esperando(t, state)
                        LinhaClicavel(ponto: CorDoEstado.de(t.state, esperando: pede), titulo: t.displayTitle,
                                      detalhe: SessoesCrew.rotulo(t, esperando: pede)
                                        + (Projetos.branch(de: t.sessionCwd).map { "  ·  " + $0 } ?? ""),
                                      direita: SessoesCrew.haQuanto(t.lastEvent)) { nav.abrir(t.id) }
                    }
                }
            }
        }
    }

    private var conversas: some View {
        CartaoPainel(titulo: "Últimas conversas", detalhe: "\(guardadas.count) guardada\(guardadas.count == 1 ? "" : "s")") {
            VStack(spacing: 2) {
                ForEach(guardadas.prefix(5), id: \.sessionId) { e in
                    LinhaClicavel(ponto: Tema.cinza, titulo: e.nome, detalhe: e.branch ?? "sem branch",
                                  direita: SessoesCrew.haQuanto(e.quando)) {
                        nav.aba = .historico
                        nav.selecao = .guardada(SessaoGuardada(e))
                    }
                }
            }
        }
    }

    // MARK: Repositório

    private var repositorio: some View {
        CartaoPainel(titulo: "Repositório") {
            if !leuGit {
                Text("Lendo…").font(.system(size: 12.5)).foregroundStyle(Tema.texto3)
            } else if !git.ehRepositorio {
                Text("Esta pasta não é um repositório git.").font(.system(size: 12.5)).foregroundStyle(Tema.texto3)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    LinhaDado(rotulo: "Branch", valor: git.branch ?? "HEAD destacado", mono: true)
                    LinhaDado(rotulo: "Mudanças",
                              valor: git.mudancas == 0 ? "nada por commitar"
                                : git.mudancas == 1 ? "1 arquivo não commitado" : "\(git.mudancas) arquivos não commitados",
                              cor: git.mudancas == 0 ? Tema.texto : Tema.ambar)
                    if git.aFrente > 0 || git.atras > 0 {
                        LinhaDado(rotulo: "Com o remoto",
                                  valor: [git.aFrente > 0 ? "\(git.aFrente) para enviar" : nil,
                                          git.atras > 0 ? "\(git.atras) para puxar" : nil].compactMap { $0 }.joined(separator: "  ·  "))
                    }
                    if let m = git.ultimoCommit, let q = git.quandoCommit {
                        LinhaDado(rotulo: "Último commit", valor: "\(m)  ·  há \(SessoesCrew.haQuanto(q))")
                    }
                    LinhaDado(rotulo: "Remoto", valor: git.remoto ?? "nenhum (só neste Mac)", mono: git.remoto != nil)
                    if !worktrees.isEmpty {
                        Fio().padding(.vertical, 2)
                        Text("Worktrees ligadas · \(worktrees.count)")
                            .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Tema.texto3)
                        ForEach(worktrees.prefix(8)) { w in
                            HStack(spacing: 8) {
                                Circle().fill(w.pastaSumiu ? Tema.vermelho : w.emUso ? Tema.azul : Tema.cinza)
                                    .frame(width: 6, height: 6)
                                Text(w.nome).font(.system(size: 12.5)).foregroundStyle(Tema.texto).lineLimit(1)
                                Text(w.branch ?? w.commit ?? "").font(.system(size: 11.5, design: .monospaced))
                                    .foregroundStyle(Tema.texto3).lineLimit(1)
                                Spacer(minLength: 8)
                                Text(w.pastaSumiu ? "pasta sumiu" : w.emUso ? "em uso"
                                     : w.ultimaMudanca.map { "há " + SessoesCrew.haQuanto($0) } ?? "")
                                    .font(.system(size: 11.5)).foregroundStyle(Tema.texto3)
                            }
                        }
                        if worktrees.count > 8 {
                            Text("e mais \(worktrees.count - 8)").font(.system(size: 11.5)).foregroundStyle(Tema.texto3)
                        }
                    }
                }
            }
        }
    }

    // MARK: Rotinas e disco

    private var rotinasBloco: some View {
        CartaoPainel(titulo: "Rotinas", detalhe: rotinas.isEmpty ? nil : "\(rotinas.count)",
                     acao: ("Abrir Rotinas", { Central.abrir(modulo: RotinasServico.idModulo) })) {
            if rotinas.isEmpty {
                Text("Nenhum pedido agendado abre sessão neste projeto.")
                    .font(.system(size: 12.5)).foregroundStyle(Tema.texto3)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(rotinas) { r in
                        HStack(spacing: 8) {
                            Circle().fill(r.ligada ? Tema.verde : Tema.cinza).frame(width: 6, height: 6)
                            Text(r.nome.isEmpty ? "Sem nome" : r.nome).font(.system(size: 12.5)).foregroundStyle(Tema.texto)
                            Spacer(minLength: 8)
                            Text(!r.ligada ? "só à mão"
                                 : r.proximaExecucao.map { "próxima: " + $0.formatted(date: .abbreviated, time: .shortened) } ?? "sem próxima")
                                .font(.system(size: 11.5)).foregroundStyle(Tema.texto3)
                        }
                    }
                }
            }
        }
    }

    private var disco: some View {
        CartaoPainel(titulo: "Disco", acao: ("Ver o que dá para limpar", { Central.abrir(modulo: "disco") })) {
            LinhaDado(rotulo: "Tamanho da pasta",
                      valor: medindo ? "medindo…"
                        : tamanho.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "não deu para medir")
        }
    }
}

/// Um número grande com o rótulo em cima.
private struct Numero: View {
    let rotulo: String
    let valor: String
    var detalhe: String? = nil
    var cor: Color = Tema.texto

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(rotulo).font(.system(size: 11.5)).foregroundStyle(Tema.texto3).lineLimit(1)
            Text(valor).font(Tema.titulo(20, .bold)).foregroundStyle(cor).lineLimit(1).minimumScaleFactor(0.7)
            Text(detalhe ?? " ").font(.system(size: 11)).foregroundStyle(Tema.texto3).lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Tema.painel))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Tema.borda))
    }
}

/// Linha de lista do painel que leva a algum lugar.
struct LinhaClicavel: View {
    let ponto: Color
    let titulo: String
    var detalhe: String? = nil
    var direita: String? = nil
    let acao: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: acao) {
            HStack(spacing: 10) {
                Circle().fill(ponto).frame(width: 7, height: 7)
                VStack(alignment: .leading, spacing: 1) {
                    Text(titulo).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Tema.texto).lineLimit(1)
                    if let detalhe {
                        Text(detalhe).font(.system(size: 11.5)).foregroundStyle(Tema.texto3).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if let direita {
                    Text(direita).font(.system(size: 11.5)).foregroundStyle(Tema.texto3)
                }
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Tema.texto3).opacity(hover ? 1 : 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: Tema.raioLinha, style: .continuous).fill(hover ? Tema.hover : .clear))
            .contentShape(RoundedRectangle(cornerRadius: Tema.raioLinha))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
