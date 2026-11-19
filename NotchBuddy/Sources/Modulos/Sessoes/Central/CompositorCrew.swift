import SwiftUI
import AppKit
import UniformTypeIdentifiers

// O campo de escrever do app do Crew, em pílula: texto que cresce com as linhas, anexos
// (clipe ou arrastando o arquivo para cima) e enviar. Grande no início, com os chips da
// sessão nova na linha de baixo; enxuto, numa linha só, dentro de uma sessão.
// Enter envia; ⇧Enter e ⌥Enter quebram a linha.

/// As marcas de imagem do campo: cada imagem anexada entra no texto como "[Image #N]", no
/// ponto em que o cursor está (como no Xirp), em vez de virar etiqueta no topo do campo.
/// Apagar a marca tira a imagem. Na hora de enviar, cada marca vira a imagem naquele ponto.
@MainActor
enum MarcasImagem {
    private static var numeros: [URL: Int] = [:]

    static func numero(de u: URL) -> Int? { numeros[u] }
    static func marca(_ n: Int) -> String { "[Image #\(n)]" }

    static func ehImagem(_ u: URL) -> Bool {
        UTType(filenameExtension: u.pathExtension)?.conforms(to: .image) ?? false
    }

    /// Recebe arquivos novos (colados, arrastados, escolhidos): imagem vira marca no texto —
    /// no cursor, se o campo está com ele — e o resto vira etiqueta de anexo.
    static func entrar(_ urls: [URL], texto: Binding<String>, anexos: Binding<[URL]>, noCursor: Bool) {
        for u in urls where u.isFileURL && !anexos.wrappedValue.contains(u) {
            guard ehImagem(u) else { anexos.wrappedValue.append(u); continue }
            let n = (anexos.wrappedValue.compactMap { numeros[$0] }.max() ?? 0) + 1
            numeros[u] = n
            anexos.wrappedValue.append(u)
            if noCursor, let editor = NSApp.keyWindow?.firstResponder as? NSTextView {
                editor.insertText(marca(n) + " ", replacementRange: editor.selectedRange())
            } else {
                let t = texto.wrappedValue
                texto.wrappedValue = t + (t.isEmpty || t.hasSuffix(" ") || t.hasSuffix("\n") ? "" : " ") + marca(n) + " "
            }
        }
    }

    /// Tira as imagens cuja marca o Hugo apagou do texto.
    static func sincronizar(texto: String, anexos: Binding<[URL]>) {
        let sumiram = anexos.wrappedValue.filter { u in numeros[u].map { !texto.contains(marca($0)) } ?? false }
        guard !sumiram.isEmpty else { return }
        sumiram.forEach { numeros[$0] = nil }
        anexos.wrappedValue.removeAll { sumiram.contains($0) }
    }

    /// O pedido em peças, na ordem de entrega: os arquivos sem marca primeiro, depois o texto
    /// com cada marca trocada pela imagem dela.
    static func pecas(_ texto: String, anexos: [URL]) -> [PecaEnvio] {
        var out: [PecaEnvio] = []
        func texto_(_ s: String) {
            guard !s.isEmpty else { return }
            if case .texto(let t)? = out.last { out[out.count - 1] = .texto(t + s) } else { out.append(.texto(s)) }
        }
        let soltos = anexos.filter { numeros[$0] == nil }
        soltos.forEach { out.append(.arquivo($0)) }
        if !soltos.isEmpty { texto_(" ") }
        let porMarca = Dictionary(anexos.compactMap { u in numeros[u].map { (marca($0), u) } }, uniquingKeysWith: { a, _ in a })
        var resto = Substring(texto)
        while let r = resto.range(of: #"\[Image #\d+\]"#, options: .regularExpression) {
            texto_(String(resto[..<r.lowerBound]))
            if let u = porMarca[String(resto[r])] { out.append(.arquivo(u)) } else { texto_(String(resto[r])) }
            resto = resto[r.upperBound...]
        }
        texto_(String(resto))
        return out
    }

    /// Para sessão nova (o pedido é um texto só): cada marca vira o caminho da imagem e os
    /// arquivos sem marca vão no fim.
    static func textoComCaminhos(_ texto: String, anexos: [URL]) -> String {
        var t = texto
        for u in anexos { if let n = numeros[u] { t = t.replacingOccurrences(of: marca(n), with: u.path) } }
        let soltos = anexos.filter { numeros[$0] == nil }
        if !soltos.isEmpty { t += (t.isEmpty ? "" : "\n\n") + soltos.map(\.path).joined(separator: "\n") }
        return t
    }

    /// O pedido foi entregue: as marcas desses anexos não valem mais.
    static func esquecer(_ urls: [URL]) { urls.forEach { numeros[$0] = nil } }
}

struct CompositorCrew<Acessorios: View>: View {
    @Binding var texto: String
    @Binding var anexos: [URL]
    var placeholder: String
    var habilitado = true
    var enviando = false
    /// Início: mais alto, com a linha de chips embaixo.
    var grande = false
    /// Muda → o campo ganha o foco.
    var foco = 0
    /// Comandos sugeridos ao digitar "/" (vazio = sem sugestão).
    var comandos: [(nome: String, descricao: String)] = []
    let aoEnviar: () -> Void
    @ViewBuilder var acessorios: () -> Acessorios

    @FocusState private var focado: Bool
    @State private var soltando = false
    /// Identifica este campo na fila do ⌘V (só enquanto está com o cursor).
    @State private var donoColar = UUID()
    /// Qual comando sugerido está marcado (↑ ↓ andam; Enter envia; Tab completa).
    @State private var marcada = 0

    private var temConteudo: Bool {
        !texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !anexos.isEmpty
    }

    /// Anexos que aparecem como etiqueta (as imagens ficam no texto, como marca).
    private var etiquetas: [URL] { anexos.filter { MarcasImagem.numero(de: $0) == nil } }

    /// Digitando um comando ("/mod"): os que começam assim.
    private var sugestoes: [(nome: String, descricao: String)] {
        guard !comandos.isEmpty, texto.hasPrefix("/"), !texto.contains(" "), !texto.contains("\n") else { return [] }
        let q = texto.dropFirst().lowercased()
        let achados = comandos.filter { $0.nome.hasPrefix(q) }
        // Já escreveu o comando inteiro: não há o que sugerir.
        return achados.count == 1 && achados[0].nome == q ? [] : Array(achados.prefix(7))
    }

    private var marcadaValida: Int { min(max(marcada, 0), max(sugestoes.count - 1, 0)) }

    private var listaSugestoes: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(sugestoes.enumerated()), id: \.element.nome) { i, c in
                Button {
                    texto = "/" + c.nome
                    aoEnviar()
                } label: {
                    HStack(spacing: 10) {
                        Text("/" + c.nome)
                            .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(Tema.texto)
                        Text(c.descricao).font(.system(size: 12)).foregroundStyle(Tema.texto3).lineLimit(1)
                        Spacer(minLength: 0)
                        if i == marcadaValida { Text("↑↓  Enter").font(.system(size: 10.5, weight: .medium)).foregroundStyle(Tema.texto3) }
                    }
                    .padding(.horizontal, 10).frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(i == marcadaValida ? Tema.selecao : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 2).padding(.top, 2)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: grande ? 12 : 8) {
            if !sugestoes.isEmpty { listaSugestoes }
            if !etiquetas.isEmpty { listaAnexos }
            if grande {
                campo
                    .padding(.horizontal, 6).padding(.top, 4)
                HStack(spacing: 6) {
                    botaoAnexar
                    acessorios()
                    Spacer(minLength: 6)
                    botaoEnviar
                }
            } else {
                HStack(alignment: .bottom, spacing: 8) {
                    botaoAnexar
                    campo.padding(.vertical, 6)
                    botaoEnviar
                }
            }
        }
        .padding(grande ? 12 : 8)
        .background(FormaCampo(raio: grande ? 26 : 24).fill(Tema.painel))
        .overlay(FormaCampo(raio: grande ? 26 : 24)
            .strokeBorder(soltando ? Tema.destaque.opacity(0.6) : focado ? Tema.bordaForte : Tema.borda,
                          lineWidth: soltando ? 1.5 : 1))
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
        .contentShape(FormaCampo(raio: grande ? 26 : 24))
        .onTapGesture { focado = true }
        .dropDestination(for: URL.self) { urls, _ in
            guard habilitado else { return false }
            MarcasImagem.entrar(urls, texto: $texto, anexos: $anexos, noCursor: focado)
            return true
        } isTargeted: { soltando = $0 && habilitado }
        .onChange(of: foco) { _, _ in focar(sempre: true) }
        // Voltou a aceitar texto (achou a sessão, terminou de enviar): pronto para escrever.
        .onChange(of: habilitado) { _, h in if h { focar(sempre: false) } }
        .onAppear { focar(sempre: false); RolagemDoCampo.ligar() }
        // ⌘V com arquivo ou imagem copiados vira anexo; texto cola normal.
        .onChange(of: focado) { _, f in f ? vigiarColar() : soltarColar() }
        // Apagou a marca de uma imagem no texto: a imagem sai junto.
        .onChange(of: texto) { _, t in MarcasImagem.sincronizar(texto: t, anexos: $anexos) }
        .onDisappear { soltarColar() }
    }

    /// Com o cursor aqui, o ⌘V passa primeiro por este campo (`Atalhos`): arquivo ou imagem
    /// copiados viram anexo; texto cola normal.
    private func vigiarColar() {
        let anexos = $anexos, texto = $texto
        Atalhos.assumirColar(donoColar) {
            guard let novos = FileDropHandler.anexosDaAreaDeTransferencia() else { return false }
            MarcasImagem.entrar(novos, texto: texto, anexos: anexos, noCursor: true)
            return true
        }
    }

    private func soltarColar() { Atalhos.soltarColar(donoColar) }

    /// Põe o cursor no campo. Sem `sempre`, respeita quem já está escrevendo em outro lugar
    /// (a busca, o nome da sessão).
    private func focar(sempre: Bool) {
        DispatchQueue.main.async {
            if !sempre, NSApp.keyWindow?.firstResponder is NSTextView { return }
            focado = true
        }
    }

    private var campo: some View {
        TextField("", text: $texto, prompt: Text(placeholder).foregroundStyle(Tema.texto3), axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: grande ? 15 : 14))
            .foregroundStyle(Tema.texto)
            .lineLimit(grande ? 2...12 : 1...10)
            .focused($focado)
            .onKeyPress(.return, phases: .down) { tecla in
                // ⌥Enter já quebra a linha sozinho; ⇧Enter pede o mesmo ao editor (no cursor).
                if tecla.modifiers.contains(.option) { return .ignored }
                if tecla.modifiers.contains(.shift) {
                    NSApp.sendAction(#selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)), to: nil, from: nil)
                    return .handled
                }
                // Com a lista de comandos aberta, Enter envia o que está marcado.
                if !sugestoes.isEmpty { texto = "/" + sugestoes[marcadaValida].nome }
                if habilitado, !enviando, temConteudo { aoEnviar() }
                return .handled
            }
            // Tab completa o primeiro comando sugerido.
            .onKeyPress(.tab) {
                guard !sugestoes.isEmpty else { return .ignored }
                texto = "/" + sugestoes[marcadaValida].nome
                return .handled
            }
            // ↑ ↓ andam pela lista de comandos (sem lista, movem o cursor no texto, como sempre).
            .onKeyPress(.downArrow) {
                guard !sugestoes.isEmpty else { return .ignored }
                marcada = (marcadaValida + 1) % sugestoes.count
                return .handled
            }
            .onKeyPress(.upArrow) {
                guard !sugestoes.isEmpty else { return .ignored }
                marcada = (marcadaValida - 1 + sugestoes.count) % sugestoes.count
                return .handled
            }
            .onChange(of: texto) { _, _ in marcada = 0 }
            // Delete com o campo vazio tira o último anexo.
            .onKeyPress(.delete) {
                guard texto.isEmpty, let ultimo = etiquetas.last else { return .ignored }
                anexos.removeAll { $0 == ultimo }
                return .handled
            }
            .disabled(!habilitado)
    }

    private var botaoAnexar: some View {
        HStack(spacing: 2) {
            BotaoIcone(icone: "paperclip", ajuda: "Anexar arquivo (ou arraste para cá)", lado: 30) { escolherAnexo() }
            // Ditado (módulo Voz): some sozinho com o módulo desligado.
            BotaoDitar(texto: $texto)
        }
        .disabled(!habilitado)
    }

    private var botaoEnviar: some View {
        let pode = habilitado && !enviando && temConteudo
        return Button(action: aoEnviar) {
            ZStack {
                Circle().fill(pode || enviando ? Tema.destaque : Color.white.opacity(0.1))
                if enviando {
                    ProgressView().controlSize(.small).scaleEffect(0.65).colorScheme(.light)
                } else {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(pode ? Tema.sobreDestaque : Tema.texto3)
                }
            }
            .frame(width: 32, height: 32)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!pode)
        .help("Enviar (Enter)")
    }

    private var listaAnexos: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(etiquetas, id: \.self) { a in
                    HStack(spacing: 5) {
                        Image(systemName: Self.icone(de: a)).font(.system(size: 10.5))
                        Text(a.lastPathComponent).font(.system(size: 11.5)).lineLimit(1)
                        Button { anexos.removeAll { $0 == a } } label: {
                            Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Tema.texto3)
                    }
                    .foregroundStyle(Tema.texto2)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(Pilula().fill(Color.white.opacity(0.07)))
                    .help(a.path)
                }
            }
            .padding(.horizontal, grande ? 4 : 2).padding(.top, 2)
        }
    }

    private static func icone(de url: URL) -> String {
        guard let tipo = UTType(filenameExtension: url.pathExtension) else { return "doc" }
        if tipo.conforms(to: .image) { return "photo" }
        if tipo.conforms(to: .pdf) { return "doc.richtext" }
        if tipo.conforms(to: .sourceCode) || tipo.conforms(to: .text) { return "doc.text" }
        return "doc"
    }

    private func escolherAnexo() {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = true
        p.canChooseDirectories = false
        if p.runModal() == .OK { MarcasImagem.entrar(p.urls, texto: $texto, anexos: $anexos, noCursor: false) }
    }
}

extension CompositorCrew where Acessorios == EmptyView {
    init(texto: Binding<String>, anexos: Binding<[URL]>, placeholder: String, habilitado: Bool = true,
         enviando: Bool = false, foco: Int = 0, comandos: [(nome: String, descricao: String)] = [],
         aoEnviar: @escaping () -> Void) {
        self.init(texto: texto, anexos: anexos, placeholder: placeholder, habilitado: habilitado,
                  enviando: enviando, grande: false, foco: foco, comandos: comandos, aoEnviar: aoEnviar) { EmptyView() }
    }
}

/// A roda do mouse (e o trackpad) no campo de escrever. O campo de várias linhas do SwiftUI
/// cresce até o limite e depois só anda com as setas: a roda passava direto para a conversa.
/// Aqui, com o mouse em cima de um campo que tem mais texto do que mostra, a roda rola o texto.
@MainActor
enum RolagemDoCampo {
    private static var vigia: Any?

    static func ligar() {
        guard vigia == nil, !CaptureTool.ativo else { return }
        vigia = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { evento in
            let delta = evento.hasPreciseScrollingDeltas ? evento.scrollingDeltaY : evento.scrollingDeltaY * 16
            let lugar = evento.locationInWindow
            let janela = evento.window
            let engoliu: Bool = MainActor.assumeIsolated { rolar(delta: delta, lugar: lugar, janela: janela) }
            return engoliu ? nil : evento
        }
    }

    /// Rola o campo em edição, se o mouse está sobre ele e há texto escondido.
    private static func rolar(delta: CGFloat, lugar: NSPoint, janela: NSWindow?) -> Bool {
        guard delta != 0, let janela, let editor = janela.firstResponder as? NSTextView, editor.isFieldEditor,
              let recorte = editor.superview as? NSClipView else { return false }
        let ponto = recorte.convert(lugar, from: nil)
        guard recorte.bounds.insetBy(dx: -40, dy: -12).contains(ponto) else { return false }
        let sobra = editor.frame.height - recorte.bounds.height
        guard sobra > 1 else { return false }
        var origem = recorte.bounds.origin
        let antes = origem.y
        origem.y = min(max(origem.y + (recorte.isFlipped ? -delta : delta), 0), sobra)
        // No fim (ou no começo) do texto a roda segue para a conversa.
        guard abs(origem.y - antes) > 0.01 else { return false }
        recorte.setBoundsOrigin(origem)
        return true
    }
}
