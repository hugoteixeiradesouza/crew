import AppKit
import SwiftUI

// Seção "Projetos parados" da página do Disco na Central.

struct ProjetosCentral: View {
    private let s = ProjetosServico.shared
    @State private var abertos: Set<String> = []

    var body: some View {
        if let lista = s.confirmacao {
            confirmacao(lista)
        } else {
            Secao("Projetos parados",
                  "Dependências e builds (node_modules, target, .venv, .build, .next, Pods…) de projetos sem nenhum sinal de uso há mais do que o tempo escolhido — nem commit, nem arquivo mexido. Nunca aparece: projeto com um programa aberto dentro, com o git trabalhando, com mudança não commitada ou dentro de uma sessão do Crew. Vai para a Lixeira; cada linha diz como trazer de volta.") {
                HStack(spacing: 8) {
                    Text("Parado há mais de").font(.system(size: 12))
                    SeletorCrew(selecao: Binding(get: { s.meses }, set: { s.meses = $0 }),
                                opcoes: ProjetosServico.opcoesMeses.map { m in
                                    (valor: m, titulo: m == 1 ? "1 mês" : "\(m) meses")
                                },
                                largura: 110)
                    if case .pronto = s.estado, s.meses != s.mesesDaLista {
                        Text("procure de novo para aplicar").font(.system(size: 11)).foregroundColor(.orange)
                    }
                    Spacer()
                }
                BarraBusca(estado: s.estado,
                           resumo: "\(s.projetos.count) \(s.projetos.count == 1 ? "projeto" : "projetos") · \(DiscoFormato.bytes(s.total))",
                           botao: "Procurar", desabilitado: s.movendo) { s.procurar() }

                if let r = s.ultimo { ResultadoLixeira(r: r) }

                ForEach(s.projetos) { linha($0) }

                if case .pronto = s.estado {
                    if s.escondidos.total > 0 {
                        Text(textoEscondidos).font(.system(size: 11)).foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if s.projetos.isEmpty {
                        Text("Nenhum projeto parado há mais de \(s.mesesDaLista == 1 ? "1 mês" : "\(s.mesesDaLista) meses").")
                            .font(.system(size: 12)).foregroundColor(.secondary)
                    } else {
                        Divider()
                        HStack {
                            Text("Selecionado: \(s.quantosSelecionados) · \(DiscoFormato.bytes(s.totalSelecionado))")
                                .font(.system(size: 12, weight: .medium)).monospacedDigit()
                            Spacer()
                            if s.preparando { ProgressView().controlSize(.small) }
                            Button("Mover para a Lixeira…") { s.prepararConfirmacao() }
                                .disabled(s.quantosSelecionados == 0 || s.preparando || s.movendo)
                        }
                    }
                }
            }
        }
    }

    private var textoEscondidos: String {
        let e = s.escondidos
        var partes: [String] = []
        if e.recentes > 0 { partes.append("\(e.recentes) com uso recente") }
        if e.comMudancas > 0 { partes.append("\(e.comMudancas) com mudança não commitada") }
        if e.emUso > 0 { partes.append("\(e.emUso) em uso agora") }
        if e.semConferir > 0 { partes.append("\(e.semConferir) sem como conferir o git") }
        return "Escondidos: " + partes.joined(separator: ", ") + "."
    }

    private func linha(_ p: ProjetoParado) -> some View {
        let ids = Set(p.artefatos.map(\.id))
        let marcados = ids.intersection(s.selecionados).count
        let aberto = abertos.contains(p.id)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Toggle("", isOn: Binding(get: { marcados == ids.count && !ids.isEmpty }, set: { _ in s.alternarProjeto(p) }))
                    .toggleStyle(.checkbox).labelsHidden()
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(p.nome).font(.system(size: 12.5, weight: .medium))
                        Text(p.ecossistemas.joined(separator: " · ")).font(.system(size: 10.5)).foregroundColor(.secondary)
                        if marcados > 0 && marcados < ids.count {
                            Text("\(marcados) de \(ids.count)").font(.system(size: 10.5)).foregroundColor(.secondary)
                        }
                    }
                    Text("\(DiscoFormato.curto(p.raiz))\(p.ultimoSinal.map { " · último sinal de uso \(DiscoFormato.idade($0))" } ?? "")")
                        .font(.system(size: 10.5)).foregroundColor(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 8)
                Text(DiscoFormato.bytes(p.bytes)).font(.system(size: 12)).monospacedDigit()
                Button { if aberto { abertos.remove(p.id) } else { abertos.insert(p.id) } } label: {
                    Image(systemName: aberto ? "chevron.up" : "chevron.down").font(.system(size: 10))
                }
                .buttonStyle(.borderless)
                Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p.raiz)]) } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless).help("Mostrar no Finder")
            }
            if aberto || p.artefatos.count == 1 {
                ForEach(p.artefatos) { artefato($0) }
                    .padding(.leading, 26)
            }
        }
    }

    private func artefato(_ a: ArtefatoProjeto) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Toggle("", isOn: Binding(get: { s.selecionados.contains(a.id) }, set: { _ in s.alternar(a.id) }))
                .toggleStyle(.checkbox).labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(a.pastaRelativa).font(.system(size: 12, design: .monospaced))
                    Text(a.tipo).font(.system(size: 10.5)).foregroundColor(.secondary)
                    if a.reinstalacao == .semLockfile { etiqueta("sem lockfile") }
                    if a.nivel == .conferir { etiqueta("conferir") }
                }
                HStack(spacing: 4) {
                    Image(systemName: "arrow.uturn.backward").font(.system(size: 9)).foregroundColor(.secondary)
                    Text(a.comando).font(.system(size: 10.5, design: .monospaced)).foregroundColor(.secondary)
                        .textSelection(.enabled).lineLimit(2).truncationMode(.middle)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(a.comando, forType: .string)
                    } label: { Image(systemName: "doc.on.doc").font(.system(size: 9.5)) }
                    .buttonStyle(.borderless).help("Copiar o comando")
                }
                if a.reinstalacao == .semLockfile {
                    Text("Sem lockfile: volta, mas as versões podem não ser as mesmas. Por isso vem desmarcado.")
                        .font(.system(size: 10.5)).foregroundColor(.orange)
                }
            }
            Spacer(minLength: 8)
            Text(DiscoFormato.bytes(a.bytes)).font(.system(size: 11.5)).foregroundColor(.secondary).monospacedDigit()
        }
    }

    private func etiqueta(_ t: String) -> some View {
        Text(t).font(.system(size: 9.5, weight: .medium))
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Color.orange.opacity(0.18)).foregroundColor(.orange)
            .clipShape(Capsule())
    }

    private func confirmacao(_ lista: [ProjetoParado]) -> some View {
        let arts = lista.flatMap { p in p.artefatos.map { (p, $0) } }
        let total = arts.reduce(Int64(0)) { $0 + $1.1.bytes }
        return Secao("Confirmar: mover para a Lixeira — projetos parados",
                     "Conferido de novo agora: nenhum destes projetos tem programa aberto dentro, git trabalhando ou mudança não commitada. Fica tudo na Lixeira até você esvaziá-la; o comando ao lado de cada um traz de volta.") {
            ForEach(arts, id: \.1.id) { p, a in
                LinhaConfirmacao(nome: "\(p.nome)/\(a.pastaRelativa)", detalhe: a.comando, bytes: a.bytes)
            }
            ListaRetirados(titulo: "Saíram da lista:", itens: s.retirados)
            RodapeConfirmacao(total: "Total: \(arts.count) \(arts.count == 1 ? "pasta" : "pastas") · \(DiscoFormato.bytes(total))",
                              botao: "Mover para a Lixeira", ocupado: s.movendo,
                              cancelar: { s.cancelarConfirmacao() }, confirmar: { s.confirmarMover() })
        }
    }
}
