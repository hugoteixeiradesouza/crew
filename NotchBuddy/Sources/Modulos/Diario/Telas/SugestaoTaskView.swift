import SwiftUI

/// "Vira task?" — o Homie pergunta, no mesmo formato da pergunta de uma sessão. O que veio
/// sozinho (WhatsApp, sessões) só vira task com o Sim do Hugo; cada resposta ensina a triagem.
///   • Sim — com o prazo que o Homie entendeu, ou trocando o prazo num clique;
///   • Não é task — some e entra no critério (parecidas deixam de ser perguntadas);
///   • Depois — fecha; ela fica "a confirmar" na aba Tasks.
struct SugestaoTaskView: View {
    @ObservedObject private var ilha = AppState.shared
    private let s = DiarioServico.shared

    var body: some View {
        ZStack {
            CardBackground(wash: .indigo)
            if let p = s.perguntando {
                // Aberto ou fechado, é o mesmo cartão: o topo fica onde está e o detalhe cresce embaixo
                VStack(alignment: .leading, spacing: 6) {
                    topo(p, aberto: ilha.alturaAba != nil)
                    VStack(alignment: .leading, spacing: 1) {
                        TituloRenomeavel(texto: p.acao) { s.renomearSugestao(p.id, $0) }
                        if let a = p.assunto ?? p.porque {
                            Text(a).font(.system(size: 11.5)).foregroundColor(Color(hex: "#9398A1"))
                                .lineLimit(1).truncationMode(.tail)
                        }
                    }
                    botoes(p)
                    if ilha.alturaAba != nil {
                        Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1).padding(.top, 4)
                        DetalheSugestao(p: p)
                    }
                }
                .padding(.leading, 116)
                .padding(.trailing, 16)
                .padding(.top, 8).padding(.bottom, ilha.alturaAba != nil ? 12 : 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .id(p.id)
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: s.perguntando?.id)
        .onChange(of: s.perguntando?.id) { _, novo in
            // Respondeu a última: volta para onde estava
            if novo == nil { s.perguntarDepois() }
        }
    }

    private func topo(_ p: Pendencia, aberto: Bool) -> some View {
        HStack(spacing: 6) {
            Text("Vira task?").font(.system(size: 12, weight: .semibold)).foregroundColor(Color(hex: "#C4B5FD"))
            etiqueta(origem(p), icone: icone(p))
            etiqueta(FormatoDiario.hora(p.criadaEm), icone: nil)
            let outras = s.sugeridas.count - 1
            if outras > 0 {
                Text("+\(outras) para confirmar").font(.system(size: 11)).foregroundColor(Color(hex: "#A78BFA"))
            }
        }
    }

    private func botoes(_ p: Pendencia) -> some View {
        HStack(spacing: 6) {
            PrimaryButton(p.prazo.map { "Sim · \(FormatoDiario.quando($0))" } ?? "Sim") { s.confirmar(p.id) }
            chip("+1 h") { s.confirmar(p.id, prazo: .some(Date().addingTimeInterval(3600))) }
            chip("18h") { s.confirmar(p.id, prazo: .some(hojeAs(18))) }
            chip("amanhã 9h") { s.confirmar(p.id, prazo: .some(amanhaAs(9))) }
            SecondaryButton("Não é task") { s.recusar(p.id) }
            Button("Depois") { s.perguntarDepois() }
                .buttonStyle(.plain)
                .font(.system(size: 11)).foregroundColor(Color(hex: "#7C818A"))
        }
    }

    private func origem(_ p: Pendencia) -> String {
        switch p.origem {
        case .whatsapp: return p.pessoa.flatMap { $0.split(separator: " ").first.map(String.init) } ?? p.sessao ?? "WhatsApp"
        case .pedido, .entrega: return p.sessao ?? p.projeto ?? "sessão"
        case .nota: return "nota"
        }
    }

    private func icone(_ p: Pendencia) -> String {
        switch p.origem {
        case .whatsapp: return "message.fill"
        case .pedido, .entrega: return "text.bubble"
        case .nota: return "pencil"
        }
    }

    private func etiqueta(_ t: String, icone: String?) -> some View {
        HStack(spacing: 3) {
            if let icone { Image(systemName: icone).font(.system(size: 7.5, weight: .bold)) }
            Text(t).font(.system(size: 9.5, weight: .medium)).lineLimit(1)
        }
        .foregroundColor(Color(hex: "#8E939C"))
        .padding(.horizontal, 6).frame(height: 16)
        .background(Capsule().fill(Color.white.opacity(0.07)))
        .fixedSize()
    }

    private func chip(_ t: String, _ acao: @escaping () -> Void) -> some View {
        Button(action: acao) {
            Text(t).font(.system(size: 11)).foregroundColor(Color(hex: "#C9CDD3"))
                .padding(.horizontal, 8).frame(height: 24)
                .background(Capsule().fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .help("Sim, com este prazo")
    }

    private func hojeAs(_ h: Int) -> Date {
        Calendar.current.date(bySettingHour: h, minute: 0, second: 0, of: Date()) ?? Date()
    }
    private func amanhaAs(_ h: Int) -> Date {
        let d = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return Calendar.current.date(bySettingHour: h, minute: 0, second: 0, of: d) ?? d
    }
}

/// O "Vira task?" aberto: título editável, por que o Homie acha que é task, o que você escreveu e
/// o trecho da conversa daquele momento (WhatsApp: lido na hora, não fica guardado).
struct DetalheSugestao: View {
    let p: Pendencia
    @State private var trecho: [MensagemWA] = []
    @State private var carregando = false

    private let cinza = Color(hex: "#8E939C")
    private let claro = Color(hex: "#ECEDEF")

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 10) {
                if let q = p.porque { campo("POR QUE O HOMIE ACHA QUE É TASK", q) }
                if let a = p.assunto { campo("ASSUNTO", a) }
                campo(p.origem == .whatsapp ? "MENSAGEM DE ORIGEM" : "DE ONDE VEIO", "\u{201C}\(p.textoOrigem)\u{201D}")
                if p.origem == .whatsapp { conversa }
                if let pz = p.prazo { campo("PRAZO QUE ELE ENTENDEU", FormatoDiario.quando(pz)) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
        .rolagemDaIlha()
        .onAppear(perform: carregar)
    }

    private func campo(_ rotulo: String, _ texto: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(rotulo).font(.system(size: 9.5, weight: .semibold)).tracking(0.6).foregroundColor(Color(hex: "#A78BFA"))
            Text(texto).font(.system(size: 12)).foregroundColor(claro)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder private var conversa: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("A CONVERSA NAQUELE MOMENTO").font(.system(size: 9.5, weight: .semibold)).tracking(0.6)
                .foregroundColor(Color(hex: "#A78BFA"))
            if carregando {
                ProgressView().controlSize(.small)
            } else if trecho.isEmpty {
                Text("Não deu para ler a conversa agora.").font(.system(size: 11.5)).foregroundColor(cinza)
            }
            ForEach(trecho, id: \.id) { m in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(FormatoDiario.hora(m.data)).font(.system(size: 10)).foregroundColor(cinza).monospacedDigit()
                    Text(m.deMim ? "Você" : quem)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(m.deMim ? Color(hex: "#25D366") : Color(hex: "#DADDE2"))
                        .lineLimit(1).fixedSize()
                    Text(m.texto).font(.system(size: 12)).foregroundColor(claro)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                .padding(.vertical, 1)
                .background(Calendar.current.isDate(m.data, equalTo: p.criadaEm, toGranularity: .minute) && m.deMim
                            ? Color.white.opacity(0.05) : Color.clear)
            }
        }
    }

    private var quem: String {
        let n = p.sessao?.trimmingCharacters(in: CharacterSet(charactersIn: "\u{202A}\u{202C} ")) ?? "Contato"
        return n.filter(\.isNumber).count >= 7 ? "Contato" : (n.split(separator: " ").first.map(String.init) ?? n)
    }

    private func carregar() {
        guard p.origem == .whatsapp, let nome = p.sessao else { return }
        carregando = true
        let momento = p.criadaEm
        Task.detached(priority: .userInitiated) {
            let t = WhatsAppBanco.trecho(nome: nome, momento: momento)
            await MainActor.run { trecho = t; carregando = false }
        }
    }
}

/// Título que se renomeia com dois cliques: vira campo, Enter ou clicar fora salva, Esc desiste.
/// Usado no "Vira task?" e nas linhas de pendência.
struct TituloRenomeavel: View {
    let texto: String
    var tamanho: CGFloat = 14
    var cor = Color(hex: "#F5F6F8")
    let salvar: (String) -> Void
    @State private var editando = false
    @State private var rascunho = ""
    @FocusState private var foco: Bool

    var body: some View {
        if editando {
            TextField("Título", text: $rascunho)
                .textFieldStyle(.plain)
                .font(.system(size: tamanho, weight: .semibold)).foregroundColor(cor)
                .padding(.horizontal, 4).padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.white.opacity(0.08)))
                .focused($foco)
                .onSubmit(concluir)
                .onExitCommand { editando = false }
                .onChange(of: foco) { _, f in if !f && editando { concluir() } }
                .onAppear {
                    NSApp.windows.first { $0 is IslandPanel }?.makeKey()
                    DispatchQueue.main.async { foco = true }
                }
        } else {
            Text(texto)
                .font(.system(size: tamanho, weight: .semibold)).foregroundColor(cor)
                .lineLimit(1).truncationMode(.tail)
                .highPriorityGesture(TapGesture(count: 2).onEnded {
                    rascunho = texto
                    editando = true
                })
                .help("Dois cliques para renomear")
        }
    }

    private func concluir() {
        let t = rascunho.trimmingCharacters(in: .whitespacesAndNewlines)
        editando = false
        if !t.isEmpty, t != texto { salvar(t) }
    }
}
