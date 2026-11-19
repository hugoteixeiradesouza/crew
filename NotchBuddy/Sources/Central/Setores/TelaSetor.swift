import SwiftUI
import AppKit

// A tela de um setor (todos menos o Comando, que é a tela das sessões): a tela de trabalho da
// ferramenta escolhida na barra lateral. Só a ferramenta à vista fica montada: as outras não
// leem nada. Não há abas aqui: um lugar só para trocar de ferramenta, a barra lateral.

struct TelaSetor: View {
    let setor: Setor
    @EnvironmentObject private var nav: NavegacaoCrew
    @Environment(\.recuoTitulo) private var recuoTitulo

    private var atual: FerramentaSetor? { Setores.ferramentas(setor).first { $0.selecao == nav.selecao } }

    var body: some View {
        VStack(spacing: 0) {
            // Só os arquivos têm topo próprio (de qual projeto são). Trocar de ferramenta e de
            // setor é na barra lateral, e só nela.
            let comTopo = atual?.id == Setores.arquivos
            if comTopo {
                HStack {
                    Spacer(minLength: 0)
                    EscolhaProjetoMesa()
                }
                .padding(.leading, 22 + recuoTitulo)
                .padding(.trailing, 14)
                .frame(height: 48)
                Fio()
            }
            Group {
                if let f = atual {
                    TelaFerramenta(ferramenta: f, noComando: true)
                        .id(f.id)
                        // Com topo, ele já desviou dos botões da janela.
                        .environment(\.recuoTitulo, comTopo ? 0 : recuoTitulo)
                } else {
                    VaziaLateral(icone: setor.icone, texto: "Este setor ainda não tem ferramenta com tela.")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Tema.fundo)
    }
}

/// A tela de trabalho de uma ferramenta, seja ela módulo ou não.
struct TelaFerramenta: View {
    let ferramenta: FerramentaSetor
    /// Sem o topo do setor por cima (barra lateral à vista): a página traz o próprio "Ajustes".
    var noComando = false

    var body: some View {
        if let m = ferramenta.modulo, m.telaCheia, Registro.shared.estaLigado(m.id), let tela = m.central() {
            tela.tint(Tema.azul).background(Tema.fundo)
        } else if let m = ferramenta.modulo {
            PaginaFerramenta(modulo: m, noComando: noComando)
        } else if ferramenta.id == Setores.navegador {
            NavegadorView(projeto: nil)
        } else {
            ArquivosMesa()
        }
    }
}

/// A tela de trabalho de um módulo: o título, o que ele faz e a tela dele (`Modulo.central()`).
/// Configuração não mora aqui: o botão "Ajustes" leva à página do módulo.
struct PaginaFerramenta: View {
    let modulo: any Modulo
    var noComando = false
    @ObservedObject private var registro = Registro.shared

    var body: some View {
        let ligado = registro.estaLigado(modulo.id)
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: modulo.icone)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Tema.texto)
                        .frame(width: 40, height: 40)
                        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.white.opacity(0.06)))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(modulo.nome)
                            .font(Tema.titulo(20, .bold))
                            .foregroundStyle(Tema.texto)
                        Text(modulo.resumo)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Tema.texto2)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: 620, alignment: .leading)
                    }
                    Spacer(minLength: 8)
                    if noComando {
                        BotaoPilula(titulo: "Ajustes", icone: "gearshape", estilo: .discreto, altura: 30) {
                            Central.ajustes(modulo: modulo.id)
                        }
                        .help("Configuração de \(modulo.nome), nos Ajustes")
                    }
                }
                if ligado {
                    if let tela = modulo.central() {
                        tela
                            // As telas dos módulos usam os controles do sistema: com o destaque
                            // branco do app, botão em destaque ficaria branco sobre branco.
                            .tint(Tema.azul)
                    }
                } else {
                    desligada
                }
            }
            .padding(.horizontal, 30)
            // No Comando não há topo de setor: o título começa abaixo dos botões da janela.
            .padding(.top, noComando ? 44 : 24)
            .padding(.bottom, 30)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Tema.fundo)
    }

    private var desligada: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(modulo.nome) está desligada")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Tema.texto)
                Text("Desligada, não aparece em lugar nenhum e não gasta nada.")
                    .font(.system(size: 12)).foregroundStyle(Tema.texto2)
            }
            Spacer(minLength: 8)
            BotaoPilula(titulo: "Ligar", estilo: .primario, altura: 30) { registro.ligar(modulo.id, true) }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: Tema.raioCartao, style: .continuous).fill(Tema.painel))
        .overlay(RoundedRectangle(cornerRadius: Tema.raioCartao, style: .continuous).strokeBorder(Tema.borda))
    }
}

// MARK: - Mesa: arquivos

/// O projeto cujos arquivos a Mesa mostra (caminho da raiz), lembrado entre aberturas.
private let chaveProjetoMesa = "modulo.mesa.arquivosProjeto"

@MainActor
private func projetoDaMesa(_ escolhido: String, _ lista: [ProjetoCrew]) -> ProjetoCrew? {
    lista.first { $0.caminho == escolhido } ?? lista.first
}

/// Os arquivos de um projeto na janela inteira: a mesma árvore que abre ao lado da sessão.
struct ArquivosMesa: View {
    @ObservedObject private var projetos = ProjetosCrew.shared
    @AppStorage(chaveProjetoMesa) private var escolhido = ""

    var body: some View {
        if let p = projetoDaMesa(escolhido, projetos.lista) {
            ArquivosProjeto(raiz: p.caminho, mencionar: { _ in }, principal: true, aoFechar: {}, avulso: true)
                .id(p.caminho)
        } else {
            VaziaLateral(icone: "folder",
                         texto: "Nenhum projeto ainda. Adicione a pasta de um projeto no Squad (aba Projetos) para ver os arquivos dela aqui.")
        }
    }
}

/// Chip no topo da Mesa: de qual projeto são os arquivos.
private struct EscolhaProjetoMesa: View {
    @ObservedObject private var projetos = ProjetosCrew.shared
    @AppStorage(chaveProjetoMesa) private var escolhido = ""

    var body: some View {
        if let atual = projetoDaMesa(escolhido, projetos.lista) {
            MenuChip(ponto: Color(hex: atual.cor), texto: atual.nome, forte: true, ajuda: "De qual projeto são os arquivos") {
                projetos.lista.map { p in
                    .acao(p.nome, ponto: Color(hex: p.cor), detalhe: p.caminhoCurto, marcado: p.caminho == atual.caminho) {
                        escolhido = p.caminho
                    }
                }
            }
        }
    }
}

// MARK: - Comando: as ferramentas na barra lateral

/// As ferramentas do Comando além das sessões (agentes, rotinas, modelos, uso), no pé da barra
/// lateral: um clique abre a tela de trabalho no lugar da conversa.
struct FerramentasComando: View {
    @EnvironmentObject private var nav: NavegacaoCrew
    @ObservedObject private var registro = Registro.shared

    var body: some View {
        let lista = Setores.ferramentas(.comando)
        if !lista.isEmpty {
            VStack(spacing: 0) {
                Fio()
                // Até cinco cabem numa fileira só (sem uma ferramenta sozinha na de baixo); com mais, quatro por fileira.
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: lista.count <= 5 ? lista.count : 4), spacing: 4) {
                    ForEach(lista) { f in
                        AzulejoFerramenta(ferramenta: f, escolhida: nav.selecao == f.selecao,
                                          apagada: f.modulo.map { !registro.estaLigado($0.id) } ?? false) {
                            nav.selecao = f.selecao
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
        }
    }
}

private struct AzulejoFerramenta: View {
    let ferramenta: FerramentaSetor
    let escolhida: Bool
    let apagada: Bool
    let acao: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: acao) {
            VStack(spacing: 5) {
                Image(systemName: ferramenta.icone).font(.system(size: 13, weight: .medium)).frame(height: 16)
                Text(ferramenta.nome).font(.system(size: 10.5, weight: escolhida ? .semibold : .medium)).lineLimit(1).minimumScaleFactor(0.85)
            }
            .foregroundStyle(escolhida || hover ? Tema.texto : Tema.texto2)
            .opacity(apagada ? 0.5 : 1)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(RoundedRectangle(cornerRadius: Tema.raioLinha, style: .continuous)
                .fill(escolhida ? Tema.selecao : hover ? Tema.hover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(apagada ? "\(ferramenta.nome) (desligada)" : ferramenta.resumo)
    }
}
