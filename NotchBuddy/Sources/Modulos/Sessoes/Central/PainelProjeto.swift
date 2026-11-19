import SwiftUI
import AppKit

// O painel de um projeto, no lugar da conversa: abre ao clicar no projeto na barra lateral.
// Cinco abas — Visão geral (o que está acontecendo nele), Detalhes (como ele aparece),
// Sessões novas (com o que toda sessão nasce), Claude Code (CLAUDE.md, MCP, permissões,
// memórias) e Avisos. O que é do disco é lido fora da main, só com o painel na tela.

struct PainelProjeto: View {
    let caminho: String

    enum Aba: Hashable { case geral, detalhes, sessoes, claude, avisos }

    @ObservedObject private var projetos = ProjetosCrew.shared
    @ObservedObject private var config = ConfigProjetos.shared
    @EnvironmentObject private var nav: NavegacaoCrew
    @Environment(\.recuoTitulo) private var recuoTitulo

    @State private var aba: Aba = .geral
    @State private var git = GitDoProjeto()
    @State private var leuGit = false
    @State private var tamanho: Int64?
    @State private var medindo = true
    @State private var worktrees: [WorktreesAtivas.Worktree] = []

    private var projeto: ProjetoCrew {
        (projetos.lista + projetos.arquivados).first { $0.caminho == caminho }
            ?? ProjetoCrew(caminho: caminho, nome: config.de(caminho).nome ?? (caminho as NSString).lastPathComponent,
                           cor: Projetos.cor(de: caminho) ?? "#9398A1", adicionado: false)
    }
    private var arquivado: Bool { projetos.arquivados.contains { $0.caminho == caminho } }
    private var c: ConfigProjeto { config.de(caminho) }
    private var existe: Bool { FileManager.default.fileExists(atPath: caminho) }

    var body: some View {
        VStack(spacing: 0) {
            cabecalho
                .padding(.leading, recuoTitulo)
            AbasCrew(itens: [(.geral, "Visão geral"), (.detalhes, "Detalhes"), (.sessoes, "Sessões novas"),
                             (.claude, "Claude Code"), (.avisos, "Avisos")], selecao: $aba)
                .frame(maxWidth: 620)
                .padding(.horizontal, 28)
                .padding(.bottom, 14)
            Fio()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !existe {
                        AvisoPainel(texto: "A pasta não existe mais neste Mac: \(projeto.caminhoCurto)", cor: Tema.ambar)
                    }
                    switch aba {
                    case .geral:
                        ProjetoGeral(projeto: projeto, git: git, leuGit: leuGit, tamanho: tamanho, medindo: medindo,
                                     worktrees: worktrees, irPara: { aba = $0 })
                    case .detalhes:
                        ProjetoDetalhes(projeto: projeto, git: git)
                    case .sessoes:
                        ProjetoSessoesNovas(projeto: projeto)
                    case .claude:
                        ProjetoClaude(projeto: projeto)
                    case .avisos:
                        ProjetoAvisos(projeto: projeto, arquivado: arquivado)
                    }
                }
                .frame(maxWidth: 860, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.never)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tema.fundo)
        .onAppear { if let cena = nav.cena { aba = cena.abaDoProjeto } }
        .task(id: caminho) { await ler() }
    }

    private func ler() async {
        guard existe else { leuGit = true; medindo = false; return }
        async let g = LeitorProjeto.git(caminho)
        async let w = LeitorProjeto.worktrees(caminho)
        git = await g
        worktrees = await w
        leuGit = true
        tamanho = await LeitorProjeto.tamanho(caminho)
        medindo = false
    }

    // MARK: Cabeçalho

    private var cabecalho: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(hex: projeto.cor).opacity(0.16))
                .frame(width: 46, height: 46)
                .overlay {
                    Image(systemName: c.icone ?? "folder.fill")
                        .font(.system(size: 19))
                        .foregroundStyle(Color(hex: projeto.cor))
                }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(projeto.nome)
                        .font(Tema.titulo(22, .bold))
                        .foregroundStyle(Tema.texto)
                        .lineLimit(1)
                    if arquivado { PilulaEstado(texto: "arquivado", cor: Tema.cinza) }
                }
                Text(projeto.caminhoCurto)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Tema.texto3)
                    .lineLimit(1).truncationMode(.head)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 12)
            if let pagina = git.pagina {
                BotaoIcone(icone: "arrow.up.right.square", ajuda: "Abrir o repositório no navegador") { NSWorkspace.shared.open(pagina) }
            }
            BotaoIcone(icone: "terminal", ajuda: "Abrir a pasta no Terminal") { abrirNoTerminal() }
                .disabled(!existe)
            BotaoIcone(icone: "folder", ajuda: "Mostrar no Finder") {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: caminho)
            }
            .disabled(!existe)
            BotaoPilula(titulo: "Nova sessão", icone: "plus", estilo: .primario) { nav.novaSessao(em: caminho) }
                .disabled(!existe || arquivado)
                .help(arquivado ? "Desarquive o projeto (aba Avisos) para abrir sessões nele" : "Nova sessão neste projeto")
        }
        .padding(.horizontal, 28)
        .padding(.top, 22)
        .padding(.bottom, 16)
    }

    private func abrirNoTerminal() {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else { return }
        NSWorkspace.shared.open([URL(fileURLWithPath: caminho)], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }
}

// MARK: - Peças do painel

/// Um bloco do painel: título, uma ação opcional à direita e o conteúdo.
struct CartaoPainel<Conteudo: View>: View {
    let titulo: String
    var detalhe: String? = nil
    var acao: (titulo: String, fazer: () -> Void)? = nil
    @ViewBuilder let conteudo: Conteudo

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(titulo).font(.system(size: 13, weight: .semibold)).foregroundStyle(Tema.texto)
                if let detalhe {
                    Text(detalhe).font(.system(size: 11.5)).foregroundStyle(Tema.texto3)
                }
                Spacer(minLength: 8)
                if let acao {
                    Button(action: acao.fazer) {
                        Text(acao.titulo).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Tema.texto2)
                    }
                    .buttonStyle(.plain)
                }
            }
            conteudo
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Tema.painel))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Tema.borda))
    }
}

/// Uma linha de ajuste: o que é e o que faz à esquerda, o controle à direita.
struct LinhaAjuste<Controle: View>: View {
    let titulo: String
    var detalhe: String? = nil
    @ViewBuilder let controle: Controle

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(titulo).font(.system(size: 12.5)).foregroundStyle(Tema.texto)
                if let detalhe {
                    Text(detalhe).font(.system(size: 11.5)).foregroundStyle(Tema.texto3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            controle
        }
    }
}

/// Rótulo e valor em uma linha (dados só de leitura).
struct LinhaDado: View {
    let rotulo: String
    let valor: String
    var cor: Color = Tema.texto
    var mono = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(rotulo).font(.system(size: 12)).foregroundStyle(Tema.texto3)
                .frame(width: 120, alignment: .leading)
            Text(valor)
                .font(.system(size: 12.5, design: mono ? .monospaced : .default))
                .foregroundStyle(cor)
                .lineLimit(2)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }
}

struct AvisoPainel: View {
    let texto: String
    var cor: Color = Tema.texto2
    var icone = "exclamationmark.circle.fill"

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icone).font(.system(size: 11.5)).foregroundStyle(cor)
            Text(texto).font(.system(size: 12)).foregroundStyle(Tema.texto2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(cor.opacity(0.09)))
    }
}

/// Campo de uma linha no visual do app.
struct CampoPainel: View {
    let dica: String
    @Binding var texto: String
    var mono = false
    var largura: CGFloat? = 260

    var body: some View {
        TextField(dica, text: $texto)
            .textFieldStyle(.plain)
            .font(.system(size: 12.5, design: mono ? .monospaced : .default))
            .foregroundStyle(Tema.texto)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .frame(width: largura)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Tema.borda))
    }
}

/// Texto de várias linhas no visual do app.
struct TextoPainel: View {
    @Binding var texto: String
    var dica = ""
    var mono = false
    var altura: CGFloat = 90

    var body: some View {
        ZStack(alignment: .topLeading) {
            if texto.isEmpty {
                Text(dica).font(.system(size: 12.5)).foregroundStyle(Tema.texto3)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $texto)
                .font(.system(size: 12.5, design: mono ? .monospaced : .default))
                .foregroundStyle(Tema.texto)
                .scrollContentBackground(.hidden)
        }
        .padding(8)
        .frame(height: altura)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Tema.borda))
    }
}

struct ChavePainel: View {
    @Binding var ligada: Bool

    var body: some View {
        Toggle("", isOn: $ligada)
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
            .tint(Tema.verde)
    }
}

extension ConfigProjetos {
    /// Liga um campo da configuração do projeto a um controle.
    func campo<T>(_ raiz: String, _ kp: WritableKeyPath<ConfigProjeto, T>) -> Binding<T> {
        Binding(get: { self.de(raiz)[keyPath: kp] },
                set: { v in self.mudar(raiz) { $0[keyPath: kp] = v } })
    }

    /// Campo de texto opcional: vazio vira nil.
    func texto(_ raiz: String, _ kp: WritableKeyPath<ConfigProjeto, String?>) -> Binding<String> {
        Binding(get: { self.de(raiz)[keyPath: kp] ?? "" },
                set: { v in self.mudar(raiz) { $0[keyPath: kp] = v.isEmpty ? nil : v } })
    }
}
