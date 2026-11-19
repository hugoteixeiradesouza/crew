import SwiftUI
import AppKit

// Os setores dentro da barra lateral do Crew. Uma barra só, em qualquer setor: no topo a
// fileira que troca de setor (⌘1 … ⌘6); embaixo, o que é do setor — no Comando, as sessões,
// projetos e histórico (`BarraLateralCrew`); nos outros, as ferramentas do setor e as sessões
// que estão rodando, que acompanham o Hugo aonde ele for.

/// A fileira de setores: um botão por setor, o escolhido com a pílula.
struct TrocaSetores: View {
    @EnvironmentObject private var nav: NavegacaoCrew
    @ObservedObject private var state = AppState.shared

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Setor.allCases) { s in
                BotaoSetor(setor: s, escolhido: nav.setor == s,
                           // Sessão esperando resposta: o Comando avisa de qualquer setor.
                           aviso: s == .comando && nav.setor != .comando && !state.pendingApprovals.isEmpty) {
                    nav.irPara(s)
                }
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.white.opacity(0.035)))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Tema.borda))
    }
}

private struct BotaoSetor: View {
    let setor: Setor
    let escolhido: Bool
    let aviso: Bool
    let acao: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: acao) {
            Image(systemName: setor.icone)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(escolhido ? Tema.texto : hover ? Tema.texto2 : Tema.texto3)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(escolhido ? Color.white.opacity(0.1) : hover ? Tema.hover : .clear))
                .overlay(alignment: .topTrailing) {
                    if aviso { Circle().fill(Tema.ambar).frame(width: 7, height: 7).offset(x: -5, y: 4) }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("\(setor.nome): \(setor.problema.prefix(1).lowercased() + setor.problema.dropFirst()) (⌘\(setor.numero))")
    }
}

/// O corpo da barra lateral fora do Comando: as ferramentas do setor e as sessões rodando.
struct LateralSetor: View {
    let setor: Setor
    @EnvironmentObject private var nav: NavegacaoCrew
    @ObservedObject private var registro = Registro.shared
    @ObservedObject private var state = AppState.shared

    /// As sessões que acompanham: as que esperam o Hugo primeiro, depois as que trabalham.
    private var sessoes: [AgentTask] {
        GruposSessoes.montar(state: state, busca: "", mostrarParadas: false).flatMap(\.itens)
    }

    var body: some View {
        let ferramentas = Setores.ferramentas(setor)
        let rodando = sessoes
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                Text(setor.problema)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Tema.texto3)
                    .lineLimit(2)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                ForEach(ferramentas) { f in
                    LinhaFerramenta(ferramenta: f, escolhida: nav.selecao == f.selecao,
                                    apagada: f.modulo.map { !registro.estaLigado($0.id) } ?? false) {
                        nav.selecao = f.selecao
                    }
                }
                if !rodando.isEmpty {
                    HStack(spacing: 7) {
                        Text("Sessões")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(Tema.texto2)
                        Text("\(rodando.count)")
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .foregroundStyle(Tema.texto3)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .padding(.top, 16)
                    ForEach(rodando) { t in
                        LinhaSessaoQueSegue(task: t, esperando: SessoesCrew.esperando(t, state),
                                            aoLado: nav.sessaoAoLado == t.id,
                                            atencao: nav.atencao.contains(t.id),
                                            abrir: { nav.selecao = .sessao(t.id) },
                                            dividir: { nav.sessaoAoLado = nav.sessaoAoLado == t.id ? nil : t.id })
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.never)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Uma ferramenta do setor na barra lateral: ícone e nome; a que está na tela ganha o fundo.
private struct LinhaFerramenta: View {
    let ferramenta: FerramentaSetor
    let escolhida: Bool
    let apagada: Bool
    let acao: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: acao) {
            HStack(spacing: 10) {
                Image(systemName: ferramenta.icone)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(escolhida ? Tema.texto : Tema.texto2)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(0.06)))
                Text(ferramenta.nome)
                    .font(.system(size: 13, weight: escolhida ? .semibold : .medium))
                    .foregroundStyle(Tema.texto)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if apagada {
                    Text("desligada").font(.system(size: 10.5)).foregroundStyle(Tema.texto3)
                }
            }
            .opacity(apagada ? 0.55 : 1)
            .padding(.horizontal, 8).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Tema.raioLinha, style: .continuous)
                .fill(escolhida ? Tema.selecao : hover ? Tema.hover : .clear))
            .contentShape(RoundedRectangle(cornerRadius: Tema.raioLinha))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(ferramenta.resumo)
    }
}

/// Uma sessão rodando, vista de outro setor: clicar abre a sessão; o botão que aparece com o
/// mouse a põe ao lado da tela em que o Hugo está.
private struct LinhaSessaoQueSegue: View {
    let task: AgentTask
    let esperando: Bool
    let aoLado: Bool
    let atencao: Bool
    let abrir: () -> Void
    let dividir: () -> Void

    @State private var hover = false

    var body: some View {
        LinhaSessaoCrew(task: task, esperando: esperando, escolhida: aoLado, atencao: atencao,
                        renomeando: false, acao: abrir, renomear: { _ in })
            .overlay(alignment: .topTrailing) {
                if hover || aoLado {
                    BotaoIcone(icone: "rectangle.split.2x1",
                               ajuda: aoLado ? "Tirar do lado" : "Abrir ao lado desta tela", lado: 24,
                               ativo: aoLado, acao: dividir)
                        .background(Circle().fill(Tema.lateral))
                        .padding(.top, 4).padding(.trailing, 5)
                }
            }
            .onHover { hover = $0 }
            .menuContexto {
                [.acao(aoLado ? "Tirar do lado" : "Abrir ao lado desta tela", icone: "rectangle.split.2x1") { dividir() },
                 .acao("Abrir a sessão", icone: "bubble.left") { abrir() }]
            }
    }
}

/// A tela do setor com a sessão que acompanha o Hugo ao lado, quando ele pediu. A divisória
/// arrasta; a largura fica lembrada.
struct DivisaoComSessao<Principal: View>: View {
    /// A sessão ao lado (nil: só a tela principal).
    let sessao: String?
    let fechar: () -> Void
    @ViewBuilder var principal: Principal

    @AppStorage("modulo.sessoes.fracaoAoLado") private var fracao = 0.4
    @State private var arrastandoDe: Double?

    var body: some View {
        GeometryReader { geo in
            let largura = max(geo.size.width, 1)
            HStack(spacing: 0) {
                principal
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if let sessao {
                    Rectangle().fill(Tema.borda).frame(width: 1)
                        .overlay {
                            // Faixa larga e invisível para pegar a divisória.
                            Color.clear.frame(width: 9).contentShape(Rectangle())
                                .onHover { dentro in
                                    if dentro { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                                }
                                .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                                    .onChanged { g in
                                        let de = arrastandoDe ?? fracao
                                        arrastandoDe = de
                                        fracao = min(max(de - g.translation.width / largura, 0.25), 0.65)
                                    }
                                    .onEnded { _ in arrastandoDe = nil })
                        }
                        .zIndex(1)
                    ConversaCrew(taskId: sessao, compacto: true, emFoco: true, aoFechar: fechar)
                        .id(sessao)
                        .environment(\.recuoTitulo, 0)
                        .frame(width: max(320, largura * fracao))
                }
            }
        }
    }
}
