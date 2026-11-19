import SwiftUI

// Página das Rotinas: a lista (próxima execução, último resultado, chave e "Rodar agora"),
// o histórico de cada uma, criar/editar e apagar com confirmação.

struct RotinasCentral: View {
    private let s = RotinasServico.shared
    @State private var editando: Rotina?
    @State private var apagando: Rotina?
    @State private var confirmandoLigar: UUID?
    @State private var historicoAberto: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let copia = s.arquivoIlegivel { avisoIlegivel(copia) }
            if let id = s.pedidoDeFora, let r = s.rotina(id) { pedido(r) }

            Secao("Rotinas", "Cada rotina abre uma sessão nova do Claude Code na pasta do projeto, já com o pedido. Pela agenda, só roda a que estiver com a chave ligada.") {
                HStack(spacing: 10) {
                    Toggle("Pausar todas", isOn: Binding(get: { s.pausadas }, set: { s.pausadas = $0 }))
                        .toggleStyle(.switch).controlSize(.small)
                        .help("Com a pausa, nenhuma rotina roda pela agenda. \"Rodar agora\" continua valendo.")
                    if s.pausadas {
                        Text("Nada roda sozinho enquanto estiver pausado.").font(.system(size: 11)).foregroundColor(.secondary)
                    }
                    Spacer()
                    Button { editando = Rotina() } label: { Label("Nova rotina", systemImage: "plus") }
                        .disabled(s.arquivoIlegivel != nil)
                }
                if let m = MotorCrew.motivoIndisponivel {
                    Label("Sem motor de sessões neste Mac: \(m) As rotinas não rodam até resolver.", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11.5)).foregroundColor(FormatoRotinaUI.corFalha)
                }
                if s.rotinas.isEmpty {
                    Text("Nenhuma rotina ainda. Crie uma com um pedido que você repete: revisar os commits de ontem, conferir dependências, resumir os erros do dia.")
                        .font(.system(size: 12)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(s.rotinas) { r in
                        Divider()
                        linha(r)
                        if historicoAberto == r.id { historico(r) }
                    }
                }
            }
        }
        .sheet(item: $editando) { r in
            RotinaEditor(rotina: r, nova: s.rotina(r.id) == nil, salvar: { s.salvar($0); editando = nil }, cancelar: { editando = nil })
        }
        .alert("Ligar a agenda desta rotina?",
               isPresented: Binding(get: { confirmandoLigar != nil }, set: { if !$0 { confirmandoLigar = nil } }),
               presenting: confirmandoLigar) { id in
            Button("Ligar") { s.confirmarConsentimento(); s.ligar(id, true) }
            Button("Cancelar", role: .cancel) {}
        } message: { _ in
            Text("Com a chave ligada, o Crew abre sessões do Claude Code sozinho, na hora marcada, sem você clicar — e cada sessão gasta o seu uso do Claude Code.\n\nVocê pode desligar cada rotina ou pausar todas quando quiser. Esta pergunta aparece só desta vez.")
        }
        .alert(apagando.map { "Apagar a rotina \($0.nome)?" } ?? "",
               isPresented: Binding(get: { apagando != nil }, set: { if !$0 { apagando = nil } }),
               presenting: apagando) { r in
            Button("Apagar", role: .destructive) { s.apagar(r.id) }
            Button("Cancelar", role: .cancel) {}
        } message: { _ in
            Text("Sai o pedido, a agenda e o histórico desta rotina. As sessões que ela abriu continuam onde estão. Não dá para desfazer.")
        }
    }

    // MARK: Linha

    private func linha(_ r: Rotina) -> some View {
        let destaque = s.pedidoDeFora == r.id
        return HStack(alignment: .center, spacing: 10) {
            Group {
                if r.agenda.tipo == .manual {
                    Image(systemName: "hand.tap").foregroundColor(.secondary).help("Só roda quando você manda")
                } else {
                    Toggle("", isOn: Binding(get: { r.ligada }, set: { ligar(r, $0) }))
                        .toggleStyle(.switch).controlSize(.small).labelsHidden()
                        .help(r.ligada ? "Roda sozinha pela agenda" : "Agenda desligada: só roda quando você manda")
                }
            }
            .frame(width: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(r.nome).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                Text("\(r.nomeProjeto) · \(FormatoRotina.descricao(r.agenda))\(extras(r))")
                    .font(.system(size: 11)).foregroundColor(.secondary).lineLimit(1).truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 2) {
                Text(proxima(r)).font(.system(size: 11.5, weight: .medium)).monospacedDigit()
                    .foregroundColor(r.ligada && !s.pausadas ? .primary : .secondary)
                ultimo(r)
            }
            .frame(width: 250, alignment: .trailing)

            HStack(spacing: 2) {
                if s.rodando.contains(r.id) {
                    ProgressView().controlSize(.small).frame(width: 26)
                } else {
                    Button { s.rodarAgora(r.id) } label: { Image(systemName: "play.fill") }
                        .help("Rodar agora: abre uma sessão com este pedido")
                }
                Button { historicoAberto = historicoAberto == r.id ? nil : r.id } label: {
                    Image(systemName: historicoAberto == r.id ? "chevron.up" : "list.bullet")
                }
                .help("Histórico das execuções")
                Button { editando = r } label: { Image(systemName: "pencil") }.help("Editar")
                Button { apagando = r } label: { Image(systemName: "trash") }.help("Apagar esta rotina")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, destaque ? 6 : 0)
        .background(destaque ? FormatoRotinaUI.corPedido.opacity(0.12) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func extras(_ r: Rotina) -> String {
        var p: [String] = []
        if let m = RotinaEditor.modelos.first(where: { $0.valor == r.modelo && $0.valor != nil }) { p.append(m.nome) }
        if let m = RotinaEditor.modos.first(where: { $0.valor == r.modo && $0.valor != nil }) { p.append(m.nome.lowercased()) }
        return p.isEmpty ? "" : " · " + p.joined(separator: " · ")
    }

    private func proxima(_ r: Rotina) -> String {
        if r.agenda.tipo == .manual { return "à mão" }
        if !r.ligada { return "agenda desligada" }
        if s.pausadas { return "pausada" }
        guard let p = r.proximaExecucao else { return "sem próxima" }
        return "próxima: " + FormatoRotina.quando(p)
    }

    @ViewBuilder private func ultimo(_ r: Rotina) -> some View {
        if let e = r.historico.first {
            HStack(spacing: 4) {
                Circle().fill(e.ok ? FormatoRotinaUI.corOk : FormatoRotinaUI.corFalha).frame(width: 6, height: 6)
                Text("\(FormatoRotina.quando(e.quando)) · \(e.ok ? "abriu sessão" : "não rodou")")
                    .font(.system(size: 10.5)).foregroundColor(.secondary).lineLimit(1)
            }
            .help(e.ok ? "Abriu a sessão \(e.sessao ?? "")" : "Não rodou: \(e.motivo ?? "")")
        } else {
            Text("nunca rodou").font(.system(size: 10.5)).foregroundColor(.secondary)
        }
    }

    private func ligar(_ r: Rotina, _ ligada: Bool) {
        if ligada && !s.consentiu { confirmandoLigar = r.id } else { s.ligar(r.id, ligada) }
    }

    // MARK: Histórico

    private func historico(_ r: Rotina) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(r.pedido).font(.system(size: 11)).foregroundColor(.secondary).lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            if r.historico.isEmpty {
                Text("Ainda não rodou.").font(.system(size: 11)).foregroundColor(.secondary)
            }
            ForEach(r.historico) { e in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: e.ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundColor(e.ok ? FormatoRotinaUI.corOk : FormatoRotinaUI.corFalha)
                    Text(FormatoRotina.quando(e.quando)).frame(width: 120, alignment: .leading).monospacedDigit()
                    Text(e.origem.texto).foregroundColor(.secondary).frame(width: 70, alignment: .leading)
                    if e.ok, let sid = e.sessao {
                        Text("abriu a sessão \(sid.prefix(8))").textSelection(.enabled)
                        Spacer(minLength: 0)
                        Button("Abrir no app") { abrir(sid) }.buttonStyle(.link).font(.system(size: 11))
                    } else {
                        Text("não rodou: \(e.motivo ?? "motivo desconhecido")").foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
                .font(.system(size: 11))
            }
        }
        .padding(.leading, 46)
        .padding(.bottom, 4)
    }

    /// Abre o app do Crew na sessão, se ela ainda está na lista; senão, só o app.
    private func abrir(_ sessionId: String) {
        Central.abrirSessoes()
        if let t = AppState.shared.tasks.first(where: { $0.sessionId == sessionId }) {
            NotificationCenter.default.post(name: .abrirSessaoNoApp, object: t.id)
        }
    }

    // MARK: Avisos no topo

    private func pedido(_ r: Rotina) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.badge.questionmark").font(.system(size: 16)).foregroundColor(FormatoRotinaUI.corPedido)
            VStack(alignment: .leading, spacing: 1) {
                Text("Pediram para rodar \(r.nome)").font(.system(size: 12.5, weight: .semibold))
                Text("O pedido veio de fora (crew://), não de você. Rodar abre uma sessão do Claude Code em \(r.nomeProjeto) e gasta uso.")
                    .font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Dispensar") { s.dispensarPedido() }
            Button("Rodar agora") { s.rodarAgora(r.id) }.keyboardShortcut(.defaultAction)
        }
        .padding(12)
        .background(FormatoRotinaUI.corPedido.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func avisoIlegivel(_ copia: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 16)).foregroundColor(FormatoRotinaUI.corFalha)
            VStack(alignment: .leading, spacing: 1) {
                Text("Não consegui ler o arquivo das rotinas").font(.system(size: 12.5, weight: .semibold))
                Text("O rotinas.json ficou como está e nada será gravado por cima. Cópia guardada em \(copia.replacingOccurrences(of: NSHomeDirectory(), with: "~")).")
                    .font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            Spacer()
            Button("Começar do zero") { s.comecarDoZero() }
                .help("Passa a gravar uma lista nova. O arquivo antigo continua na cópia.")
        }
        .padding(12)
        .background(FormatoRotinaUI.corFalha.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
