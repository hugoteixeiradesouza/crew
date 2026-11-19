import SwiftUI
import AppKit
import UniformTypeIdentifiers

// Uma tabela da resposta como entregável: a barra de ações (quantas linhas, filtrar, copiar
// para planilha, copiar como Markdown, salvar CSV, ampliar) e a tabela desenhada (`VistaTabela`).
// Na conversa ela tem o tamanho do conteúdo; ampliada, ocupa a janela do Crew inteira.
// Clique numa célula copia o valor; clique num título ordena; clique direito copia célula,
// linha ou coluna. Copiar e exportar levam o que está na tela (filtro e ordem valem).

struct TabelaConversa: View {
    let tabela: TabelaResposta
    var titulo: String? = nil
    var tamanho: CGFloat = 13
    /// Ocupando a janela inteira (`TabelaAmpliada`): rola nos dois sentidos e tem o botão de fechar.
    var fechar: (() -> Void)? = nil

    @Environment(\.pastaDaSessao) private var pasta
    @State private var filtro = ""
    @State private var ordenacao: OrdenacaoTabela?
    @State private var aviso: String?
    @State private var avisoN = 0
    @FocusState private var filtrando: Bool

    private var ampliada: Bool { fechar != nil }
    /// Filtro só aparece em tabela que não se lê de uma olhada.
    private var temFiltro: Bool { tabela.linhas.count >= 8 }

    var body: some View {
        let modelo = ModeloTabela.de(tabela, tamanho: tamanho, pasta: pasta)
        let linhas = modelo.linhas(filtro: filtro, ordenacao: ordenacao)
        let vista = TabelaRolavel(modelo: modelo, linhas: linhas, ordenacao: ordenacao, vertical: ampliada,
                                  esticarAte: ampliada ? 0 : temFiltro ? 570 : 410,
                                  aoOrdenar: { ordenar($0, modelo) },
                                  aoCopiar: { avisar("Copiado: " + $0) },
                                  menu: { linha, coluna in menu(modelo, linhas, linha, coluna) })
        if ampliada {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Text(titulo ?? "Tabela")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Tema.texto)
                        .lineLimit(1)
                    barra(modelo, linhas, rotulos: true)
                    BotaoIcone(icone: "xmark", ajuda: "Fechar (Esc)", lado: 26) { fechar?() }
                }
                .padding(.leading, 16).padding(.trailing, 10)
                .frame(height: 46)
                vista
            }
        } else {
            TabelaComBarra {
                ViewThatFits(in: .horizontal) {
                    barra(modelo, linhas, rotulos: true)
                    barra(modelo, linhas, rotulos: false)
                }
                vista
            }
        }
    }

    // MARK: Barra

    private func barra(_ modelo: ModeloTabela, _ linhas: [Int], rotulos: Bool) -> some View {
        HStack(spacing: 2) {
            Group {
                if let aviso {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                        Text(aviso).lineLimit(1).truncationMode(.tail)
                    }
                    .foregroundStyle(Tema.verde)
                } else {
                    Text(contagem(linhas.count)).foregroundStyle(Tema.texto3).lineLimit(1)
                }
            }
            .font(.system(size: 11.5))
            .frame(minWidth: 70, maxWidth: rotulos ? 260 : 150, alignment: .leading)
            .layoutPriority(-1)
            Spacer(minLength: 10)
            if temFiltro {
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass").font(.system(size: 10, weight: .medium)).foregroundStyle(Tema.texto3)
                    TextField("Filtrar", text: $filtro)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Tema.texto)
                        .focused($filtrando)
                        .onExitCommand { filtro = ""; filtrando = false }
                    if !filtro.isEmpty {
                        Button { filtro = "" } label: {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 10)).foregroundStyle(Tema.texto3)
                        }
                        .buttonStyle(.plain)
                        .help("Limpar o filtro")
                    }
                }
                .padding(.horizontal, 8)
                .frame(width: rotulos ? 150 : 112, height: 24)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(filtrando ? 0.08 : 0.045)))
                .padding(.trailing, 4)
            }
            BotaoTabela(icone: "doc.on.doc", rotulo: rotulos ? "Copiar" : nil, ajuda: "Copiar a tabela — cola em planilha, e-mail ou documento já em colunas") {
                AcoesTabela.copiar(modelo, linhas)
                avisar("Tabela copiada")
            }
            BotaoTabela(icone: "number", rotulo: rotulos ? "Markdown" : nil, ajuda: "Copiar como Markdown (para colar em outra conversa)") {
                AcoesTabela.copiarMarkdown(modelo, linhas)
                avisar("Markdown copiado")
            }
            BotaoTabela(icone: "square.and.arrow.down", rotulo: rotulos ? "CSV" : nil, ajuda: "Salvar como CSV (abre no Excel e no Numbers)") {
                AcoesTabela.salvarCSV(modelo, linhas, nome: titulo) { avisar("Salvo: " + $0) }
            }
            if !ampliada {
                BotaoTabela(icone: "arrow.up.left.and.arrow.down.right", rotulo: rotulos ? "Ampliar" : nil, ajuda: "Ver a tabela na janela inteira") {
                    TabelaAmpliada.abrir(tabela, titulo: titulo, pasta: pasta)
                }
            }
        }
        .frame(height: 26)
    }

    private func contagem(_ visiveis: Int) -> String {
        let total = tabela.linhas.count
        let colunas = tabela.colunas == 1 ? "1 coluna" : "\(tabela.colunas) colunas"
        if visiveis != total { return "\(visiveis) de \(total) linhas" }
        return (total == 1 ? "1 linha" : "\(total) linhas") + " · " + colunas
    }

    private func avisar(_ texto: String) {
        avisoN += 1
        let meu = avisoN
        aviso = texto.count > 46 ? String(texto.prefix(45)) + "…" : texto
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            if avisoN == meu { withAnimation(.easeOut(duration: 0.2)) { aviso = nil } }
        }
    }

    /// Primeiro clique ordena (número: do maior para o menor; texto: de A a Z), o segundo
    /// inverte e o terceiro volta à ordem original.
    private func ordenar(_ coluna: Int, _ modelo: ModeloTabela) {
        let primeiro = !modelo.colunas[coluna].numerica
        if let o = ordenacao, o.coluna == coluna {
            ordenacao = o.crescente == primeiro ? OrdenacaoTabela(coluna: coluna, crescente: !primeiro) : nil
        } else {
            ordenacao = OrdenacaoTabela(coluna: coluna, crescente: primeiro)
        }
    }

    private func menu(_ modelo: ModeloTabela, _ linhas: [Int], _ linha: Int?, _ coluna: Int?) -> [ItemMenu] {
        var itens: [ItemMenu] = []
        if let linha, let coluna {
            let valor = modelo.celulas[linha][coluna].limpo
            if !valor.isEmpty {
                itens.append(.acao("Copiar célula", icone: "doc.on.doc", detalhe: valor.count > 40 ? String(valor.prefix(39)) + "…" : valor) {
                    VistaTexto.copiar(valor)
                    avisar("Copiado: " + valor)
                })
            }
            if let link = modelo.celulas[linha][coluna].link {
                itens.append(.acao(link.isFileURL ? "Abrir o arquivo" : "Abrir o endereço", icone: "arrow.up.forward", detalhe: "⌘ clique") { TextoRico.abrir(link) })
            }
            itens.append(.acao("Copiar linha", icone: "arrow.left.and.right") {
                VistaTexto.copiar(modelo.celulas[linha].map(\.limpo).joined(separator: "\t"))
                avisar("Linha copiada")
            })
            let nome = modelo.colunas[coluna].nome
            itens.append(.acao(nome.isEmpty ? "Copiar coluna" : "Copiar coluna “\(nome)”", icone: "arrow.up.and.down") {
                VistaTexto.copiar(linhas.map { modelo.celulas[$0][coluna].limpo }.joined(separator: "\n"))
                avisar("Coluna copiada")
            })
            itens.append(.divisor)
        }
        itens.append(.acao("Copiar tabela", icone: "tablecells", detalhe: "Cola em planilha já em colunas") {
            AcoesTabela.copiar(modelo, linhas)
            avisar("Tabela copiada")
        })
        itens.append(.acao("Copiar como Markdown", icone: "number") {
            AcoesTabela.copiarMarkdown(modelo, linhas)
            avisar("Markdown copiado")
        })
        itens.append(.acao("Salvar CSV…", icone: "square.and.arrow.down") {
            AcoesTabela.salvarCSV(modelo, linhas, nome: titulo) { avisar("Salvo: " + $0) }
        })
        if !ampliada {
            itens.append(.acao("Ampliar", icone: "arrow.up.left.and.arrow.down.right") {
                TabelaAmpliada.abrir(tabela, titulo: titulo, pasta: pasta)
            })
        }
        return itens
    }
}

/// Botão da barra da tabela: ícone e, cabendo, o nome. Apagado até o mouse chegar.
private struct BotaoTabela: View {
    let icone: String
    var rotulo: String?
    let ajuda: String
    let acao: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: acao) {
            HStack(spacing: 5) {
                Image(systemName: icone).font(.system(size: 10.5, weight: .medium))
                if let rotulo { Text(rotulo).font(.system(size: 11.5, weight: .medium)).fixedSize() }
            }
            .foregroundStyle(hover ? Tema.texto : Tema.texto2)
            .padding(.horizontal, rotulo == nil ? 7 : 8)
            .frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(hover ? Color.white.opacity(0.08) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(ajuda)
    }
}

/// A barra em cima e a tabela embaixo, as duas com a mesma largura: a da tabela, ou a da barra
/// quando a tabela é mais estreita que ela — nunca mais que o espaço da conversa.
private struct TabelaComBarra: Layout {
    private let entre: CGFloat = 5

    private func medidas(_ proposal: ProposedViewSize, _ subviews: Subviews) -> (largura: CGFloat, barra: CGSize, tabela: CGSize) {
        guard subviews.count == 2 else { return (0, .zero, .zero) }
        var espaco = proposal.width ?? 600
        if !espaco.isFinite || espaco <= 0 { espaco = 600 }
        let tabela = subviews[1].sizeThatFits(ProposedViewSize(width: espaco, height: nil))
        let barraIdeal = subviews[0].sizeThatFits(.unspecified).width
        let largura = min(espaco, max(tabela.width, min(barraIdeal, 600)))
        let barra = subviews[0].sizeThatFits(ProposedViewSize(width: largura, height: nil))
        return (largura, barra, tabela)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let m = medidas(proposal, subviews)
        return CGSize(width: m.largura, height: m.barra.height + entre + m.tabela.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let m = medidas(ProposedViewSize(width: bounds.width, height: nil), subviews)
        guard subviews.count == 2 else { return }
        subviews[0].place(at: bounds.origin, proposal: ProposedViewSize(width: m.largura, height: m.barra.height))
        subviews[1].place(at: CGPoint(x: bounds.minX, y: bounds.minY + m.barra.height + entre),
                          proposal: ProposedViewSize(width: m.tabela.width, height: m.tabela.height))
    }
}

// MARK: - Ações

@MainActor
enum AcoesTabela {
    private static func dados(_ modelo: ModeloTabela, _ linhas: [Int]) -> (cabecalho: [String], linhas: [[String]]) {
        (modelo.tabela.cabecalho, linhas.map { modelo.tabela.linhas[$0] })
    }

    /// Copia para colar em qualquer lugar: texto tabulado (planilha) e tabela em HTML (e-mail,
    /// Notas, documento), os dois na mesma cópia — quem recebe escolhe o que entende.
    static func copiar(_ modelo: ModeloTabela, _ linhas: [Int]) {
        let d = dados(modelo, linhas)
        let tsv = RegrasTabela.tsv(cabecalho: d.cabecalho, linhas: d.linhas)
        let area = NSPasteboard.general
        area.clearContents()
        area.setString(tsv, forType: .string)
        area.setString(tsv, forType: .tabularText)
        area.setString(RegrasTabela.html(cabecalho: d.cabecalho, linhas: d.linhas, direita: modelo.direita), forType: .html)
    }

    static func copiarMarkdown(_ modelo: ModeloTabela, _ linhas: [Int]) {
        let d = dados(modelo, linhas)
        VistaTexto.copiar(RegrasTabela.markdown(cabecalho: d.cabecalho, linhas: d.linhas, direita: modelo.direita))
    }

    /// Nome de arquivo a partir do título da seção ("Resumo do semestre" → "resumo-do-semestre").
    static func nomeDeArquivo(_ titulo: String?) -> String {
        let base = (titulo ?? "").folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
        let limpo = base.map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
            .split(separator: "-").joined(separator: "-")
        return limpo.isEmpty ? "tabela" : String(limpo.prefix(60))
    }

    /// Pergunta onde salvar (começa em Downloads) e grava o CSV com ponto e vírgula e a marca
    /// de UTF-8, que é como o Excel em português abre certo, com acento e em colunas.
    static func salvarCSV(_ modelo: ModeloTabela, _ linhas: [Int], nome: String?, salvo: @escaping @MainActor (String) -> Void) {
        let d = dados(modelo, linhas)
        let painel = NSSavePanel()
        painel.title = "Salvar a tabela"
        painel.nameFieldStringValue = nomeDeArquivo(nome) + ".csv"
        painel.allowedContentTypes = [.commaSeparatedText]
        painel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        painel.begin { resposta in
            guard resposta == .OK, let url = painel.url else { return }
            let texto = "\u{FEFF}" + RegrasTabela.csv(cabecalho: d.cabecalho, linhas: d.linhas)
            do {
                try texto.write(to: url, atomically: true, encoding: .utf8)
                salvo(url.lastPathComponent)
            } catch {
                NSSound.beep()
            }
        }
    }
}

// MARK: - Ampliada

/// A tabela ocupando a janela do Crew inteira, por cima de tudo (uma janela filha, presa à do
/// Crew: anda e muda de tamanho com ela). Esc, o X ou clique fora fecha.
@MainActor
enum TabelaAmpliada {
    private final class Painel: NSPanel {
        override var canBecomeKey: Bool { true }
    }

    private static var painel: Painel?
    private static var vigias: [NSObjectProtocol] = []
    private static var vigiaEsc: Any?

    static func abrir(_ tabela: TabelaResposta, titulo: String?, pasta: String?) {
        fechar()
        guard let mae = NSApp.mainWindow ?? NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }) else { return }
        let p = Painel(contentRect: mae.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.isReleasedWhenClosed = false
        p.contentView = NSHostingView(rootView: TabelaAmpliadaView(tabela: tabela, titulo: titulo, fechar: { fechar() })
            .environment(\.pastaDaSessao, pasta))
        mae.addChildWindow(p, ordered: .above)
        p.setFrame(mae.frame, display: true)
        p.makeKeyAndOrderFront(nil)
        painel = p
        let centro = NotificationCenter.default
        vigias = [
            centro.addObserver(forName: NSWindow.didResizeNotification, object: mae, queue: .main) { [weak mae] _ in
                MainActor.assumeIsolated { if let mae { painel?.setFrame(mae.frame, display: true) } }
            },
            centro.addObserver(forName: NSWindow.willCloseNotification, object: mae, queue: .main) { _ in
                MainActor.assumeIsolated { fechar() }
            },
        ]
        vigiaEsc = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { evento in
            guard evento.keyCode == 53, MainActor.assumeIsolated({ painel?.isKeyWindow == true }) else { return evento }
            MainActor.assumeIsolated { fechar() }
            return nil
        }
    }

    static func fechar() {
        for v in vigias { NotificationCenter.default.removeObserver(v) }
        vigias = []
        if let v = vigiaEsc { NSEvent.removeMonitor(v) }
        vigiaEsc = nil
        guard let p = painel else { return }
        painel = nil
        p.parent?.removeChildWindow(p)
        p.orderOut(nil)
    }
}

/// O que a janela ampliada mostra: o fundo escurecido e o cartão com a tabela.
struct TabelaAmpliadaView: View {
    let tabela: TabelaResposta
    let titulo: String?
    let fechar: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.82)
                .onTapGesture(perform: fechar)
            TabelaConversa(tabela: tabela, titulo: titulo, tamanho: 13.5, fechar: fechar)
                .background(Tema.painel)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Tema.bordaForte))
                .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
                .padding(.horizontal, 36)
                .padding(.top, 44)      // os botões da janela ficam livres
                .padding(.bottom, 30)
        }
    }
}
