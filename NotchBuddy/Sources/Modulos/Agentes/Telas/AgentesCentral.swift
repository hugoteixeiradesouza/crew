import SwiftUI

// Página dos Agentes na Central: órfãs (marcar e mover para a Lixeira, com confirmação) e as
// worktrees ativas por repositório (só leitura). Varre ao abrir.

struct AgentesCentral: View {
    private let s = AgentesServico.shared
    @State private var marcadas: Set<String> = []
    @State private var confirmando = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Button { s.varrer() } label: {
                    Label(s.varrendo ? "Varrendo…" : "Varrer agora", systemImage: "arrow.clockwise")
                }
                .disabled(s.varrendo || s.movendo)
                if let u = s.ultimaVarredura {
                    Text("Última varredura: \(FormatoAgentes.idade(u))")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
                Spacer()
            }

            Secao("Órfãs", "Worktrees que o repositório dono não lista mais, sem processo usando, sem lock e fora de janelas do Cursor. As do .coucou-sessoes (sessões do Crew) nunca entram.") {
                if s.orfas.isEmpty {
                    Text(s.ultimaVarredura == nil ? "Lendo…" : "Nenhuma worktree órfã.")
                        .font(.system(size: 12)).foregroundColor(.secondary)
                } else {
                    ForEach(s.orfas) { o in linhaOrfa(o) }
                    Divider()
                    HStack {
                        Button(marcadas.count == s.orfas.count ? "Desmarcar todas" : "Marcar todas") {
                            marcadas = marcadas.count == s.orfas.count ? [] : Set(s.orfas.map(\.caminho))
                        }
                        Spacer()
                        Button(selecionadas.isEmpty ? "Mover para a Lixeira" : "Mover para a Lixeira (\(selecionadas.count) · \(FormatoAgentes.bytes(totalSelecionado)))") {
                            confirmando = true
                        }
                        .disabled(selecionadas.isEmpty || s.movendo)
                    }
                }
                if let r = s.ultimoResultado {
                    Text(r).font(.system(size: 11)).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Secao("Ativas por projeto", "Worktrees que o git ainda lista, nos projetos do Claude Code. Só leitura.") {
                if s.ativas.isEmpty {
                    Text(s.ultimaVarredura == nil ? "Lendo…" : "Nenhuma worktree ativa.")
                        .font(.system(size: 12)).foregroundColor(.secondary)
                }
                ForEach(s.ativas) { r in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            Text(r.nome).font(.system(size: 12.5, weight: .semibold))
                            Text(FormatoAgentes.curto(r.caminho)).font(.system(size: 11)).foregroundColor(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        ForEach(r.worktrees) { w in linhaAtiva(w) }
                    }
                    .padding(.bottom, 4)
                }
            }
        }
        .onAppear { s.varrerSeVelho(validade: 15) }
        .onChange(of: s.orfas) { _, novas in marcadas.formIntersection(novas.map(\.caminho)) }
        .alert("Mover \(selecionadas.count) worktree(s) para a Lixeira?", isPresented: $confirmando) {
            Button("Mover para a Lixeira", role: .destructive) {
                s.moverParaLixeira(selecionadas.map(\.caminho))
                marcadas = []
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text(mensagemConfirmacao)
        }
    }

    private var selecionadas: [PoliticaWorktrees.Orfa] { s.orfas.filter { marcadas.contains($0.caminho) } }
    private var totalSelecionado: Int64 { selecionadas.reduce(0) { $0 + (s.tamanhos[$1.caminho] ?? 0) } }

    private var mensagemConfirmacao: String {
        let linhas = selecionadas.prefix(12).map { o in
            "• \(FormatoAgentes.curto(o.caminho)) — \(s.tamanhos[o.caminho].map(FormatoAgentes.bytes) ?? "tamanho ?")"
        }
        let resto = selecionadas.count > 12 ? ["… e mais \(selecionadas.count - 12)"] : []
        return (linhas + resto).joined(separator: "\n")
            + "\n\nTotal: \(FormatoAgentes.bytes(totalSelecionado)). Vai para a Lixeira (dá para recuperar). Alterações não commitadas nessas pastas vão junto; os commits continuam no repositório."
    }

    private func linhaOrfa(_ o: PoliticaWorktrees.Orfa) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("", isOn: Binding(get: { marcadas.contains(o.caminho) },
                                     set: { if $0 { marcadas.insert(o.caminho) } else { marcadas.remove(o.caminho) } }))
                .toggleStyle(.checkbox).labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                Text(FormatoAgentes.curto(o.caminho)).font(.system(size: 12, weight: .medium))
                    .lineLimit(1).truncationMode(.middle)
                Text("\(o.ferramenta) · \(FormatoAgentes.curto(o.projeto))").font(.system(size: 11)).foregroundColor(.secondary)
                Text(o.motivo.rawValue).font(.system(size: 11)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Text(s.tamanhos[o.caminho].map(FormatoAgentes.bytes) ?? "medindo…")
                .font(.system(size: 12)).monospacedDigit().foregroundColor(.secondary)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: o.caminho)])
            } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.borderless).help("Mostrar no Finder")
        }
    }

    private func linhaAtiva(_ w: WorktreesAtivas.Worktree) -> some View {
        HStack(spacing: 8) {
            Circle().fill(w.emUso ? Color.green : Color.secondary.opacity(0.3)).frame(width: 7, height: 7)
            Text(w.nome).font(.system(size: 12)).lineLimit(1).frame(width: 190, alignment: .leading)
            Text(w.branch ?? (w.commit.map { "destacado em \($0)" } ?? "—"))
                .font(.system(size: 11.5, design: .monospaced)).foregroundColor(.secondary)
                .lineLimit(1).truncationMode(.middle)
            Spacer()
            if w.sessaoCrew { selo("sessão do Crew") }
            if w.travada { selo("travada") }
            if w.pastaSumiu { selo("pasta sumiu") }
            if w.emUso { selo("em uso") }
            Text(FormatoAgentes.idade(w.ultimaMudanca)).font(.system(size: 11)).foregroundColor(.secondary)
                .monospacedDigit().frame(width: 74, alignment: .trailing)
        }
    }

    private func selo(_ t: String) -> some View {
        Text(t).font(.system(size: 10)).padding(.horizontal, 6).padding(.vertical, 1)
            .background(Color.primary.opacity(0.07)).clipShape(Capsule())
    }
}
