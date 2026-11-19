import SwiftUI
import AppKit

// O navegador de arquivos da sessão: a pasta do projeto em árvore e o arquivo escolhido aberto
// num visor de texto de verdade (rola, seleciona, copia). Dois jeitos de usar, trocados no
// botão do cabeçalho:
// - coluna: ao lado da conversa, a árvore em cima e o arquivo embaixo;
// - principal: no lugar da conversa, a árvore à esquerda e o arquivo ocupando o resto.
// Tudo se redimensiona arrastando as divisórias (e a largura da coluna, a divisória da conversa).
// Dois cliques abrem no app padrão; o clique direito menciona o arquivo no chat (@caminho).
// Só lê o disco quando uma pasta é aberta (ou no botão de recarregar): nenhuma vigia, nenhum timer.

struct ArquivosProjeto: View {
    /// Pasta em que a sessão roda.
    let raiz: String
    /// Põe "@caminho" no campo do chat.
    let mencionar: (String) -> Void
    /// Está no lugar da conversa (visualização principal), e o botão que troca.
    var principal = false
    var alternarPrincipal: () -> Void = {}
    let aoFechar: () -> Void
    /// Fora de uma sessão (setor Mesa): sem fechar, sem trocar de lugar e sem mencionar no chat.
    var avulso = false

    /// Coluna: quanto da altura fica com a árvore. Principal: largura da árvore.
    @AppStorage("modulo.sessoes.arquivosFracaoArvore") private var fracaoArvore = 0.42
    @AppStorage("modulo.sessoes.arquivosLarguraArvore") private var larguraArvore = 280.0
    @State private var inicioArraste: Double?

    private struct No: Identifiable, Hashable {
        let caminho: String
        let nome: String
        let pasta: Bool
        let nivel: Int
        var id: String { caminho }
    }

    @State private var abertas: Set<String> = []
    @State private var filhos: [String: [No]] = [:]
    @State private var escolhido: String?
    @State private var previa: String?
    @State private var imagem: NSImage?
    @State private var busca = ""

    /// Tudo aparece, inclusive arquivos e pastas ocultos (.git, .env, .claude, node_modules…),
    /// em cinza mais apagado. Só o lixo do Finder fica de fora. Cada pasta é lida ao abrir.
    private static let ocultos: Set<String> = [".DS_Store"]

    private var linhas: [No] {
        var out: [No] = []
        func desce(_ pasta: String) {
            for n in filhos[pasta] ?? [] {
                out.append(n)
                if n.pasta, abertas.contains(n.caminho) { desce(n.caminho) }
            }
        }
        desce(raiz)
        let q = busca.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? out : out.filter { $0.nome.lowercased().contains(q) }
    }

    var body: some View {
        GeometryReader { geo in
            if principal {
                HStack(spacing: 0) {
                    arvore.frame(width: min(max(larguraArvore, 180), max(geo.size.width - 320, 180)))
                    divisoria(vertical: true) { delta, inicio in
                        larguraArvore = min(max(inicio + delta, 180), Double(geo.size.width) - 320)
                    } valor: { larguraArvore }
                    visor.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                VStack(spacing: 0) {
                    arvore.frame(height: escolhido == nil ? geo.size.height : max(140, geo.size.height * fracaoArvore))
                    if escolhido != nil {
                        divisoria(vertical: false) { delta, inicio in
                            fracaoArvore = min(max(inicio + delta / Double(max(geo.size.height, 1)), 0.15), 0.8)
                        } valor: { fracaoArvore }
                        visor.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .background(Tema.lateral)
        .task(id: raiz) { recarregar() }
    }

    /// Divisória arrastável entre a árvore e o arquivo.
    private func divisoria(vertical: Bool, mudar: @escaping (Double, Double) -> Void, valor: @escaping () -> Double) -> some View {
        Rectangle().fill(Tema.borda)
            .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
            .padding(vertical ? .horizontal : .vertical, 3)
            .contentShape(Rectangle())
            .onHover { dentro in
                if dentro { (vertical ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push() } else { NSCursor.pop() }
            }
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { g in
                    if inicioArraste == nil { inicioArraste = valor() }
                    mudar(Double(vertical ? g.translation.width : g.translation.height), inicioArraste ?? valor())
                }
                .onEnded { _ in inicioArraste = nil })
            .help("Arraste para mudar o tamanho")
    }

    private var arvore: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "folder.fill").font(.system(size: 11)).foregroundStyle(Tema.texto3)
                Text(URL(fileURLWithPath: raiz).lastPathComponent)
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Tema.texto2).lineLimit(1)
                    .help(raiz)
                Spacer()
                BotaoIcone(icone: "arrow.clockwise", ajuda: "Reler a pasta", lado: 24) { recarregar() }
                if !avulso {
                    BotaoIcone(icone: principal ? "sidebar.right" : "arrow.up.left.and.arrow.down.right",
                               ajuda: principal ? "Voltar para a coluna, ao lado da conversa" : "Abrir como visualização principal (no lugar da conversa)",
                               lado: 24, acao: alternarPrincipal)
                    BotaoIcone(icone: "xmark", ajuda: "Fechar os arquivos", lado: 24, acao: aoFechar)
                }
            }
            .padding(.leading, 14).padding(.trailing, 8)
            .frame(height: 46)
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").font(.system(size: 10.5, weight: .medium)).foregroundStyle(Tema.texto3)
                TextField("", text: $busca, prompt: Text("Filtrar o que está aberto").foregroundStyle(Tema.texto3))
                    .textFieldStyle(.plain).font(.system(size: 12)).foregroundStyle(Tema.texto)
            }
            .padding(.horizontal, 10).frame(height: 28)
            .background(Pilula().fill(Color.white.opacity(0.045)))
            .overlay(Pilula().strokeBorder(Tema.borda))
            .padding(.horizontal, 10).padding(.bottom, 8)
            Fio()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(linhas) { n in linha(n) }
                    if linhas.isEmpty {
                        Text(busca.isEmpty ? "Pasta vazia." : "Nada com esse filtro.")
                            .font(.system(size: 12)).foregroundStyle(Tema.texto3).padding(12)
                    }
                }
                .padding(.horizontal, 6).padding(.vertical, 6)
            }
        }
    }

    /// O arquivo escolhido (ou o convite a escolher um, na visualização principal).
    @ViewBuilder
    private var visor: some View {
        if let escolhido {
            painelPrevia(escolhido)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "doc.text").font(.system(size: 22, weight: .light)).foregroundStyle(Tema.texto3)
                Text("Escolha um arquivo na árvore.").font(.system(size: 12.5)).foregroundStyle(Tema.texto3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(hex: "#0D0D10"))
        }
    }

    private func linha(_ n: No) -> some View {
        LinhaArquivo(nome: n.nome, pasta: n.pasta, aberta: abertas.contains(n.caminho), nivel: n.nivel,
                     escolhida: escolhido == n.caminho) {
            if n.pasta { alternar(n.caminho) } else { escolher(n.caminho) }
        } abrir: {
            if !n.pasta { VisorCrew.abrir(URL(fileURLWithPath: n.caminho)) }
        }
        .menuContexto {
            (avulso ? [] : [.acao("Mencionar no chat", icone: "at") { mencionar(relativo(n.caminho)) }]) + [
                .acao("Ver em tela cheia", icone: "arrow.up.left.and.arrow.down.right") { VisorCrew.abrir(URL(fileURLWithPath: n.caminho)) },
                .acao("Abrir no app padrão", icone: "arrow.up.forward.app") { NSWorkspace.shared.open(URL(fileURLWithPath: n.caminho)) },
                .acao("Mostrar no Finder", icone: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: n.caminho)])
                },
                .acao("Copiar caminho", icone: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(n.caminho, forType: .string)
                },
            ]
        }
    }

    private func relativo(_ caminho: String) -> String {
        caminho.hasPrefix(raiz + "/") ? String(caminho.dropFirst(raiz.count + 1)) : caminho
    }

    private func painelPrevia(_ caminho: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(relativo(caminho)).font(.system(size: 11, design: .monospaced)).foregroundStyle(Tema.texto2)
                    .lineLimit(1).truncationMode(.head)
                Spacer()
                if !avulso {
                    BotaoIcone(icone: "at", ajuda: "Mencionar no chat", lado: 22) { mencionar(relativo(caminho)) }
                }
                BotaoIcone(icone: "arrow.up.forward.app", ajuda: "Abrir no app padrão", lado: 22) {
                    NSWorkspace.shared.open(URL(fileURLWithPath: caminho))
                }
                BotaoIcone(icone: "xmark", ajuda: "Fechar a prévia", lado: 22) { escolhido = nil }
            }
            .padding(.leading, 12).padding(.trailing, 6).frame(height: 30)
            Fio()
            if let imagem {
                ScrollView([.vertical, .horizontal]) {
                    Image(nsImage: imagem).resizable().scaledToFit()
                        .frame(maxWidth: min(imagem.size.width, 1400))
                        .padding(14)
                }
            } else if let previa {
                VisorDeTexto(texto: previa)
            } else {
                Text("Sem prévia para este tipo de arquivo.")
                    .font(.system(size: 12.5)).foregroundStyle(Tema.texto3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(hex: "#0D0D10"))
    }

    // MARK: Disco

    private func ler(_ pasta: String, nivel: Int) -> [No] {
        let fm = FileManager.default
        let nomes = (try? fm.contentsOfDirectory(atPath: pasta)) ?? []
        return nomes.filter { !Self.ocultos.contains($0) }.map { nome -> No in
            let c = pasta + "/" + nome
            var ehPasta: ObjCBool = false
            fm.fileExists(atPath: c, isDirectory: &ehPasta)
            return No(caminho: c, nome: nome, pasta: ehPasta.boolValue, nivel: nivel)
        }
        .sorted { $0.pasta != $1.pasta ? $0.pasta : $0.nome.localizedStandardCompare($1.nome) == .orderedAscending }
    }

    private func nivel(de pasta: String) -> Int {
        pasta == raiz ? 0 : relativo(pasta).split(separator: "/").count
    }

    private func recarregar() {
        var novo: [String: [No]] = [raiz: ler(raiz, nivel: 0)]
        for p in abertas where FileManager.default.fileExists(atPath: p) { novo[p] = ler(p, nivel: nivel(de: p)) }
        filhos = novo
    }

    private func alternar(_ pasta: String) {
        if abertas.contains(pasta) {
            abertas.remove(pasta)
        } else {
            filhos[pasta] = ler(pasta, nivel: nivel(de: pasta))
            abertas.insert(pasta)
        }
    }

    /// Abre o arquivo no visor: imagem, ou o texto inteiro (até 2 MB). Binário fica sem prévia.
    private func escolher(_ caminho: String) {
        escolhido = caminho
        previa = nil
        imagem = nil
        let url = URL(fileURLWithPath: caminho)
        if MarcasImagem.ehImagem(url) { imagem = NSImage(contentsOf: url); return }
        guard let fh = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? fh.close() }
        let limite = 2_000_000
        guard let data = try? fh.read(upToCount: limite), !data.prefix(8000).contains(0) else { return }
        // Cortado no meio de um caractere: tenta de novo sem os últimos bytes.
        guard let texto = String(data: data, encoding: .utf8) ?? String(data: data.dropLast(3), encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else { return }
        previa = texto + (data.count == limite ? "\n\n… (arquivo grande: só os primeiros 2 MB)" : "")
    }
}

/// O texto de um arquivo num campo de verdade: rola nos dois sentidos, seleciona e copia.
private struct VisorDeTexto: NSViewRepresentable {
    let texto: String

    func makeNSView(context: Context) -> NSScrollView {
        let rolagem = NSTextView.scrollableTextView()
        rolagem.drawsBackground = false
        rolagem.hasHorizontalScroller = true
        rolagem.scrollerStyle = .overlay
        if let v = rolagem.documentView as? NSTextView {
            v.isEditable = false
            v.isSelectable = true
            v.drawsBackground = false
            v.font = .monospacedSystemFont(ofSize: 12.5, weight: .regular)
            v.textColor = NSColor(Color(hex: "#C9CDD4"))
            v.textContainerInset = NSSize(width: 12, height: 12)
            v.selectedTextAttributes = [.backgroundColor: NSColor(Tema.azul).withAlphaComponent(0.35)]
            // Linha comprida não quebra: rola para o lado, como num editor.
            v.isHorizontallyResizable = true
            v.textContainer?.widthTracksTextView = false
            v.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            v.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            v.string = texto
        }
        return rolagem
    }

    func updateNSView(_ rolagem: NSScrollView, context: Context) {
        guard let v = rolagem.documentView as? NSTextView, v.string != texto else { return }
        v.string = texto
        v.scroll(.zero)
    }
}

private struct LinhaArquivo: View {
    let nome: String
    let pasta: Bool
    let aberta: Bool
    let nivel: Int
    let escolhida: Bool
    let tocar: () -> Void
    let abrir: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Tema.texto3)
                .rotationEffect(.degrees(aberta ? 90 : 0))
                .opacity(pasta ? 1 : 0)
                .frame(width: 10)
            Image(systemName: pasta ? "folder.fill" : "doc")
                .font(.system(size: 10.5))
                .foregroundStyle(pasta ? Tema.azul.opacity(0.8) : Tema.texto3)
                .frame(width: 14)
            Text(nome)
                .font(.system(size: 12.5))
                .foregroundStyle(nome.hasPrefix(".") ? Tema.texto3 : escolhida ? Tema.texto : Tema.texto2)
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.leading, 6 + CGFloat(nivel) * 14).padding(.trailing, 6)
        .frame(height: 26)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(escolhida ? Tema.selecao : hover ? Tema.hover : .clear))
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: abrir)
        .onTapGesture(perform: tocar)
        .onHover { hover = $0 }
    }
}
