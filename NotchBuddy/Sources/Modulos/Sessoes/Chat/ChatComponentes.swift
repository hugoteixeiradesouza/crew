import SwiftUI

/// Quem mostra a imagem ampliada dentro da ilha (o chat define; sem ele, abre no Preview).
private struct AmpliarImagemKey: EnvironmentKey {
    static let defaultValue: (@MainActor @Sendable (Data) -> Void)? = nil
}

extension EnvironmentValues {
    var ampliarImagem: (@MainActor @Sendable (Data) -> Void)? {
        get { self[AmpliarImagemKey.self] }
        set { self[AmpliarImagemKey.self] = newValue }
    }
}

/// Miniatura de imagem anexada à conversa; clicar amplia sem sair da ilha.
struct AttachedImage: View {
    let data: Data
    @Environment(\.ampliarImagem) private var ampliar

    var body: some View {
        if let img = NSImage(data: data) {
            Button(action: open) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 220, maxHeight: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1)))
            }
            .buttonStyle(.plain)
            .help("Ampliar imagem")
        }
    }

    private func open() {
        if let ampliar {
            withAnimation(.easeOut(duration: 0.18)) { ampliar(data) }
            return
        }
        AttachedImage.abrirNoPreview(data)
    }

    static func abrirNoPreview(_ data: Data) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("coucou-\(abs(data.hashValue)).png")
        try? data.write(to: url)
        NSWorkspace.shared.open(url)
    }
}

/// Imagem ampliada por cima da conversa. Clique fora ou no X fecha; Esc também.
struct ImagemAmpliada: View {
    let data: Data
    let fechar: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.82)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .onTapGesture(perform: fechar)
            if let img = NSImage(data: data) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onTapGesture(perform: fechar)
            }
            HStack(spacing: 6) {
                botao("arrow.up.forward.square", ajuda: "Abrir no Preview") {
                    AttachedImage.abrirNoPreview(data)
                }
                botao("xmark", ajuda: "Fechar", acao: fechar)
            }
            .padding(10)
        }
        .onExitCommand(perform: fechar)
        .transition(.opacity)
    }

    private func botao(_ icone: String, ajuda: String, acao: @escaping () -> Void) -> some View {
        Button(action: acao) {
            Image(systemName: icone)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Color(hex: "#DADDE2"))
                .frame(width: 22, height: 22)
                .background(Color.white.opacity(0.12))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .help(ajuda)
    }
}

struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top) {
            if message.role == .user {
                Spacer(minLength: 32)
                MarkdownText(text: message.content)
                    .font(.system(size: 12.5))
                    .foregroundColor(Color(hex: "#F1F2F4"))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.white.opacity(0.13))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                MarkdownText(text: message.content)
                    .font(.system(size: 12.5))
                    .foregroundColor(Color(hex: "#B0B5BE"))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                Spacer(minLength: 8)
            }
        }
    }
}

/// Markdown das respostas do Claude: títulos, listas, blocos de código, tabelas e
/// negrito/itálico/código em linha. Sem dependência externa.
/// Um turno da conversa: o pedido do Hugo, o que o Claude disse no caminho e a resposta final.
struct ChatTurn: Identifiable {
    let id: Int
    var user: SessionMessage?
    var steps: [SessionMessage] = []
    var answer: SessionMessage?
    /// O contexto foi resumido antes deste turno (o app mostra um divisor discreto).
    var resumo = false

    static func group(_ messages: [SessionMessage]) -> [ChatTurn] {
        var turns: [ChatTurn] = []
        for m in messages {
            if m.resumo {
                turns.append(ChatTurn(id: m.id, resumo: true))
                continue
            }
            if m.fromUser || turns.isEmpty {
                turns.append(ChatTurn(id: m.id, user: m.fromUser ? m : nil))
                if m.fromUser { continue }
            }
            // A última fala do Claude no turno é a resposta; as anteriores, o caminho.
            if let a = turns[turns.count - 1].answer { turns[turns.count - 1].steps.append(a) }
            turns[turns.count - 1].answer = m
        }
        return turns
    }
}

struct ChatTurnView: View {
    let turn: ChatTurn
    @State private var showSteps = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let u = turn.user {
                VStack(alignment: .trailing, spacing: 4) {
                    images(u, trailing: true)
                    if !u.text.isEmpty {
                        ChatBubble(message: ChatMessage(role: .user, content: u.text))
                            .opacity(u.naFila ? 0.55 : 1)
                    }
                    if u.naFila {
                        // Mandada com o Claude ocupado: ele lê quando terminar o passo atual
                        HStack(spacing: 4) {
                            Image(systemName: "clock").font(.system(size: 9, weight: .semibold))
                            Text("Na fila — o Claude lê em seguida").font(.system(size: 10.5))
                        }
                        .foregroundColor(Color(hex: "#6B7079"))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            if !turn.steps.isEmpty {
                // Falas do caminho ("vou conferir…"): recolhidas, numa linha discreta
                Button(action: { withAnimation(.easeOut(duration: 0.2)) { showSteps.toggle() } }) {
                    HStack(spacing: 5) {
                        Image(systemName: showSteps ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                        Text(turn.steps.count == 1 ? "1 mensagem no caminho" : "\(turn.steps.count) mensagens no caminho")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(Color(hex: "#6B7079"))
                }
                .buttonStyle(.plain)
                if showSteps {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(turn.steps) { st in
                            MarkdownText(text: st.text)
                                .font(.system(size: 11.5))
                                .foregroundColor(Color(hex: "#8E939C"))
                        }
                    }
                    .padding(.leading, 10)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(Color.white.opacity(0.08)).frame(width: 2)
                    }
                }
            }
            if let a = turn.answer {
                VStack(alignment: .leading, spacing: 6) {
                    images(a, trailing: false)
                    if !a.text.isEmpty {
                        // Resposta: cartão próprio, texto claro e com respiro
                        MarkdownText(text: a.text, lineSpacing: 3)
                            .font(.system(size: 13))
                            .foregroundColor(Color(hex: "#DADDE2"))
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.white.opacity(0.045))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func images(_ m: SessionMessage, trailing: Bool) -> some View {
        if !m.images.isEmpty {
            HStack(spacing: 6) {
                if trailing { Spacer(minLength: 32) }
                ForEach(Array(m.images.enumerated()), id: \.offset) { _, data in AttachedImage(data: data) }
                if !trailing { Spacer(minLength: 8) }
            }
        }
    }
}
