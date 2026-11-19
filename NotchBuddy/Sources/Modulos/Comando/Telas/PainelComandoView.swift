import SwiftUI
import AppKit
import Translation

// O desenho do comando universal: o campo, a lista e o rodapé com o que o teclado faz.
// Mesma cara do app do Crew (Tema): escuro, calmo, um destaque só. Sem lista nem campo com a
// cara padrão do sistema. As teclas são da janela (PainelComando); aqui só se desenha e clica.

struct PainelComandoView: View {
    @ObservedObject private var s = ComandoServico.shared
    @FocusState private var noCampo: Bool

    var body: some View {
        VStack(spacing: 0) {
            campo
            if !s.resultados.isEmpty {
                Fio()
                lista
            }
            Fio()
            rodape
        }
        // Atrás de tudo, a alça: arrastar por qualquer ponto livre do cartão move o painel.
        .background(AlcaDoPainel())
        .background(Tema.painel)
        // O painel sabe a altura do cartão: clique fora dele fecha.
        .background(GeometryReader { g in
            Color.clear
                .onAppear { PainelComando.shared.alturaCartao = g.size.height }
                .onChange(of: g.size.height) { _, h in PainelComando.shared.alturaCartao = h }
        })
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Tema.bordaForte, lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 28, y: 14)
        .padding(.horizontal, 30)
        .padding(.top, 8)
        .padding(.bottom, 48)
        .frame(maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .environment(\.telaVisivel, s.aberto)
        .tint(Tema.destaque)
        .modifier(TraducaoPelaTela(tradutor: s.tradutor))
        .onChange(of: s.aberto) { _, aberto in if aberto { noCampo = true } }
        .onAppear { noCampo = true }
    }

    // MARK: Campo

    private var campo: some View {
        HStack(spacing: 12) {
            ZStack {
                if s.aberto {
                    // Vivo: segue o mouse com os olhos, pensa enquanto o Hugo digita e procura
                    // enquanto a busca roda.
                    HomieVivo(estado: ocupado ? .searching : s.texto.isEmpty ? .idle : .thinking,
                              tamanho: 42, olhar: PainelComando.olhar)
                }
            }
            .frame(width: 42, height: 42)
            TextField("", text: $s.texto, prompt: Text("Abrir, achar, calcular, traduzir, pedir…").foregroundColor(Tema.texto3))
                .textFieldStyle(.plain)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(Tema.texto)
                .focused($noCampo)
                .autocorrectionDisabled()
            if s.procurandoArquivos {
                ProgressView().controlSize(.small).opacity(0.6)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 58)
    }

    private var ocupado: Bool {
        if s.procurandoArquivos { return true }
        if case .traduzindo = s.tradutor.estado { return true }
        return false
    }

    // MARK: Lista

    private var lista: some View {
        ScrollViewReader { rolagem in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(s.resultados.enumerated()), id: \.element.id) { i, r in
                        if let titulo = r.grupo.titulo, i == 0 || s.resultados[i - 1].grupo != r.grupo {
                            Text(titulo.uppercased())
                                .font(.system(size: 10, weight: .semibold)).kerning(0.6)
                                .foregroundStyle(Tema.texto3)
                                .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 2)
                        } else if i > 0, s.resultados[i - 1].grupo != r.grupo, r.grupo == .adiante {
                            Fio().padding(.horizontal, 10).padding(.vertical, 4)
                        }
                        LinhaComando(resultado: r, selecionada: r.id == s.selecao)
                            .id(r.id)
                            .onTapGesture { s.executar(r) }
                    }
                }
                .padding(8)
            }
            .scrollIndicators(.never)
            .frame(maxHeight: 468)
            .fixedSize(horizontal: false, vertical: true)
            .onChange(of: s.selecao) { _, id in
                if let id { rolagem.scrollTo(id) }
            }
        }
    }

    // MARK: Rodapé

    private var rodape: some View {
        HStack(spacing: 14) {
            if let aviso = s.aviso {
                Label(aviso, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11)).foregroundStyle(Tema.ambar).lineLimit(2)
            } else if s.resultados.isEmpty, !s.texto.isEmpty {
                Text("Nada com esse nome").font(.system(size: 11)).foregroundStyle(Tema.texto3)
            }
            Spacer(minLength: 0)
            if let r = s.selecionado {
                Tecla(sinal: "↩", texto: r.rotuloEnter)
                if let outro = r.rotuloSecundario { Tecla(sinal: "⌘↩", texto: outro) }
            }
            Tecla(sinal: "esc", texto: s.texto.isEmpty ? "Fechar" : "Limpar")
        }
        .padding(.horizontal, 16)
        .frame(height: 36)
        .background(Tema.lateral)
    }
}

/// Uma tecla e o que ela faz, no rodapé.
private struct Tecla: View {
    let sinal: String
    let texto: String

    var body: some View {
        HStack(spacing: 6) {
            Text(sinal)
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(Tema.texto2)
                .padding(.horizontal, 5).frame(minWidth: 20, minHeight: 18)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Tema.elevado))
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Tema.borda, lineWidth: 1))
            Text(texto).font(.system(size: 11)).foregroundStyle(Tema.texto3)
        }
        .fixedSize()
    }
}

/// Uma linha de resultado. Com `destaque` (conta, tradução), o valor vem grande e a linha é mais alta.
private struct LinhaComando: View {
    let resultado: ResultadoComando
    let selecionada: Bool
    @State private var hover = false

    var body: some View {
        HStack(spacing: 12) {
            IconeDoResultado(icone: resultado.icone, grande: resultado.destaque != nil)
            VStack(alignment: .leading, spacing: 2) {
                if let valor = resultado.destaque {
                    Text(valor)
                        .font(Tema.titulo(22, .semibold))
                        .foregroundStyle(Tema.texto)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.disabled)
                    Text(resultado.titulo).font(.system(size: 11.5)).foregroundStyle(Tema.texto3).lineLimit(1)
                } else {
                    Text(resultado.titulo)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(resultado.inerte ? Tema.texto2 : Tema.texto)
                        .lineLimit(1)
                    if !resultado.subtitulo.isEmpty {
                        Text(resultado.subtitulo)
                            .font(.system(size: 11.5)).foregroundStyle(Tema.texto3)
                            .lineLimit(resultado.grupo == .resposta ? 2 : 1).truncationMode(.middle)
                    }
                }
            }
            Spacer(minLength: 8)
            Text(resultado.tipo)
                .font(.system(size: 11))
                .foregroundStyle(selecionada ? Tema.texto2 : Tema.texto3)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, resultado.destaque != nil ? 10 : 6)
        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Tema.raioLinha, style: .continuous)
            .fill(selecionada ? Tema.selecao : hover && !resultado.inerte ? Tema.hover : .clear))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }
}

private struct IconeDoResultado: View {
    let icone: IconeComando
    let grande: Bool

    private var lado: CGFloat { grande ? 34 : 28 }

    var body: some View {
        Group {
            switch icone {
            case .simbolo(let nome):
                Image(systemName: nome)
                    .font(.system(size: lado * 0.5, weight: .medium))
                    .foregroundStyle(Tema.texto2)
                    .frame(width: lado, height: lado)
                    .background(RoundedRectangle(cornerRadius: lado * 0.28, style: .continuous).fill(Tema.elevado))
            case .arquivo(let caminho):
                Image(nsImage: IconesDeArquivo.de(caminho))
                    .resizable().interpolation(.high)
                    .frame(width: lado, height: lado)
            case .cor(let hex):
                Circle().fill(Color(hex: hex))
                    .frame(width: 10, height: 10)
                    .frame(width: lado, height: lado)
                    .background(RoundedRectangle(cornerRadius: lado * 0.28, style: .continuous).fill(Tema.elevado))
            }
        }
        .frame(width: 34)
    }
}

/// Ícones do Finder, guardados enquanto o app roda (pedir de novo a cada tecla custa).
@MainActor
private enum IconesDeArquivo {
    private static let guardados = NSCache<NSString, NSImage>()

    static func de(_ caminho: String) -> NSImage {
        if let ja = guardados.object(forKey: caminho as NSString) { return ja }
        let icone = NSWorkspace.shared.icon(forFile: caminho)
        guardados.countLimit = 300
        guardados.setObject(icone, forKey: caminho as NSString)
        return icone
    }
}

/// macOS 15: a sessão de tradução só nasce de dentro de uma tela (`.translationTask`). Nos mais
/// novos o Tradutor cria a sessão sozinho e este modificador não faz nada.
private struct TraducaoPelaTela: ViewModifier {
    @ObservedObject var tradutor: Tradutor
    @State private var configuracao: TranslationSession.Configuration?

    func body(content: Content) -> some View {
        content
            .onChange(of: tradutor.pedidoParaTela) { _, pedido in
                guard let pedido else { configuracao = nil; return }
                let nova = TranslationSession.Configuration(source: Locale.Language(identifier: pedido.de),
                                                            target: Locale.Language(identifier: pedido.para))
                // Mesmo par de idiomas com outro texto: a configuração não muda, então pede de novo.
                if configuracao == nova { configuracao?.invalidate() } else { configuracao = nova }
            }
            .translationTask(configuracao) { sessao in
                guard let pedido = tradutor.pedidoParaTela else { return }
                // A sessão é do macOS e só é usada aqui, uma vez: o compilador não tem como saber.
                nonisolated(unsafe) let unica = sessao
                let traduzido = try? await unica.translate(pedido.texto).targetText
                tradutor.entregar(traduzido, pedido: pedido)
            }
    }
}

/// A alça do painel: fica atrás do cartão. O que não é campo, linha ou botão cai nela, e
/// arrastar dali move o painel pela tela. Dois cliques o devolvem ao lugar de sempre.
private struct AlcaDoPainel: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Alca() }
    func updateNSView(_ v: NSView, context: Context) {}

    final class Alca: NSView {
        override func mouseDown(with evento: NSEvent) {
            if evento.clickCount == 2 {
                PainelComando.shared.voltarAoLugar()
            } else {
                PainelComando.shared.arrastando = true
                window?.performDrag(with: evento)
            }
        }
    }
}
