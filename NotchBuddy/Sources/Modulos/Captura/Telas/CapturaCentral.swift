import QuickLook
import SwiftUI

// Página da Captura nos Ajustes do Crew: capturar agora, o estado da permissão, as capturas
// recentes (com as mesmas ações da prévia e a Visualização Rápida) e os ajustes — atalhos, pasta,
// quantas guardar e o tempo da prévia.

struct CapturaCentral: View {
    private let s = CapturaServico.shared
    @ObservedObject private var estado = AppState.shared
    @State private var espiando: URL?
    @State private var retornos: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Secao("Capturar agora", "O mesmo que os atalhos. A seleção é a do macOS: Esc cancela.") {
                HStack(spacing: 8) {
                    ForEach(ModoCaptura.allCases) { modo in botaoModo(modo) }
                }
                if let m = s.emCurso {
                    linhaAviso("Escolha na tela (\(m.nome.lowercased())) — Esc cancela.", icone: "cursorarrow.rays", cor: .accentColor)
                } else if let a = s.aviso {
                    linhaAviso(a.texto, icone: a.erro ? "exclamationmark.triangle.fill" : "checkmark.circle", cor: a.erro ? .orange : .secondary)
                }
            }

            GravacaoGravar()

            Secao("Permissão", nil) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: s.permissao ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                        .font(.system(size: 20))
                        .foregroundColor(s.permissao ? Color(hex: "#34D399") : .orange)
                        .frame(width: 26)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(s.permissao ? "Gravação de Tela liberada para o Crew" : "Falta a permissão de Gravação de Tela")
                            .font(.system(size: 13, weight: .medium))
                        Text(s.permissao
                             ? "O Crew só fotografa ou grava quando você aperta um atalho ou clica. Imagens e vídeos ficam neste Mac."
                             : CapturaServico.explicacaoPermissao)
                            .font(.system(size: 11)).foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    if !s.permissao {
                        Button("Liberar…") { s.pedirPermissao() }
                    }
                }
            }

            Secao("Recentes", recentesDetalhe) {
                if s.recentes.isEmpty {
                    Text("Nenhuma captura ainda. Aperte \(s.rotuloAtalho(.area) ?? "o botão Área") e arraste sobre um pedaço da tela.")
                        .font(.system(size: 12)).foregroundColor(.secondary)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 158, maximum: 240), spacing: 12)], alignment: .leading, spacing: 14) {
                        ForEach(s.recentes) { c in celula(c) }
                    }
                }
            }

            GravacoesLista()
        }
        .onAppear { s.atualizar() }
        .quickLookPreview($espiando, in: s.recentes.map(\.url))
    }

    private var recentesDetalhe: String {
        let n = s.recentes.count
        let quantas = n == 1 ? "1 captura" : "\(n) capturas"
        return s.pastaEhDoCrew
            ? "\(quantas) na pasta do Crew. Passando de \(s.manter), as mais antigas vão para a Lixeira."
            : "\(quantas) em \(FormatoCaptura.curto(s.pasta)). Nesta pasta o Crew não apaga nada sozinho."
    }

    private func botaoModo(_ modo: ModoCaptura) -> some View {
        Button { s.capturar(modo) } label: {
            VStack(spacing: 5) {
                Image(systemName: modo.icone).font(.system(size: 18)).frame(height: 22)
                Text(modo.nome).font(.system(size: 12, weight: .medium))
                Text(s.rotuloAtalho(modo) ?? "sem atalho")
                    .font(.system(size: 10.5).monospaced())
                    .foregroundColor(s.recusados.contains(modo) ? .orange : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(s.emCurso != nil)
        .help(modo.explicacao)
    }

    private func linhaAviso(_ texto: String, icone: String, cor: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: icone).foregroundColor(cor)
            Text(texto).fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 11.5)).foregroundColor(.secondary)
    }

    private func celula(_ c: Captura) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { espiando = c.url } label: {
                MiniaturaCaptura(captura: c)
                    .aspectRatio(16 / 10, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .onDrag { NSItemProvider(contentsOf: c.url) ?? NSItemProvider() }
            .help("Clique para ver inteira (Visualização Rápida); arraste para soltar o arquivo em outro app")
            HStack(spacing: 5) {
                Text(retornos[c.id] ?? FormatoCaptura.quando(c.data))
                    .font(.system(size: 11, weight: retornos[c.id] == nil ? .regular : .medium)).monospacedDigit()
                    .foregroundColor(retornos[c.id] == nil ? .primary : .accentColor)
                    .lineLimit(1)
                if c.anotada, retornos[c.id] == nil {
                    Text("anotada").font(.system(size: 9.5, weight: .medium))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.18)).clipShape(Capsule())
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 0) {
                acao("eye", "Ver inteira (Visualização Rápida)") { espiando = c.url }
                acao("doc.on.doc", "Copiar a imagem") { dizer(c, s.copiarImagem(c) ? "Imagem copiada" : "Não copiou") }
                acao("text.viewfinder", "Copiar o texto da imagem") {
                    Task { dizer(c, await s.copiarTexto(de: c) ? "Texto copiado" : "Sem texto") }
                }
                acao("pencil.tip.crop.circle", "Anotar") { JanelaAnotar.shared.abrir(c) }
                let sessao = sessaoAlvo
                acao("paperplane", sessao.map { "Mandar para \($0.displayTitle)" } ?? "Sem sessão do Claude Code em foco") {
                    guard let sessao else { return }
                    dizer(c, "Mandando…")
                    Task {
                        let erro = await s.mandar(c, para: sessao)
                        dizer(c, erro.map { "Não foi: \($0)" } ?? "Enviada para \(sessao.displayTitle)")
                    }
                }
                .disabled(sessao == nil)
                acao("trash", "Mandar para a Lixeira") { s.apagar(c) }
            }
        }
        .menuContexto {
            [.acao("Mostrar no Finder", icone: "folder") { s.mostrarNoFinder(c) },
             .acao("Salvar como…", icone: "square.and.arrow.down") { s.salvarComo(c) },
             .divisor,
             .acao("Mandar para a Lixeira", icone: "trash", destrutivo: true) { s.apagar(c) }]
        }
    }

    private var sessaoAlvo: AgentTask? {
        _ = estado.focusId
        return s.sessaoAlvo
    }

    private func dizer(_ c: Captura, _ texto: String) {
        retornos[c.id] = texto
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            if retornos[c.id] == texto { retornos[c.id] = nil }
        }
    }

    private func acao(_ icone: String, _ ajuda: String, _ f: @escaping () -> Void) -> some View {
        Button(action: f) {
            Image(systemName: icone).font(.system(size: 12)).frame(maxWidth: .infinity, minHeight: 22).contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(ajuda)
        .accessibilityLabel(ajuda)
    }
}

/// Ajustes da Captura: atalhos (cada um com a sua combinação e a sua chave), pasta, limite e prévia.
struct CapturaAjustes: View {
    @Bindable private var s = CapturaServico.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Atalhos").font(.system(size: 12, weight: .semibold))
            VStack(alignment: .leading, spacing: 6) {
                ForEach(ModoCaptura.allCases) { modo in linhaAtalho(modo) }
            }
            Text("Valem em qualquer app. Clique na combinação e aperte a nova (com ⌃, ⌥ ou ⌘); Esc deixa como estava. Não precisa de Acessibilidade: o macOS só avisa o Crew quando a combinação exata é apertada.")
                .font(.system(size: 11)).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider().padding(.vertical, 2)
            Text("Pasta").font(.system(size: 12, weight: .semibold))
            HStack(spacing: 8) {
                Image(systemName: "folder").foregroundColor(.secondary)
                Text(FormatoCaptura.curto(s.pastaMostrada)).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 8)
                Button("Abrir") { s.abrirPasta() }
                Button("Escolher…") { s.escolherPasta() }
                if !s.pastaEhDoCrew {
                    Button("Voltar para a do Crew") { s.usarPastaDoCrew() }
                }
            }
            .controlSize(.small)
            HStack(spacing: 8) {
                Stepper(value: $s.manter, in: 10...500, step: 10) {
                    Text("Guardar as \(s.manter) mais novas").font(.system(size: 12)).monospacedDigit()
                }
                .controlSize(.small)
                .disabled(!s.pastaEhDoCrew)
                Spacer(minLength: 0)
            }
            Text(s.pastaEhDoCrew
                 ? "Na pasta do Crew, passando do limite as mais antigas vão para a Lixeira (as fixadas na prévia ficam)."
                 : "Numa pasta sua o Crew nunca apaga nada sozinho: o limite não vale aqui.")
                .font(.system(size: 11)).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider().padding(.vertical, 2)
            Text("Prévia flutuante").font(.system(size: 12, weight: .semibold))
            Toggle("Mostrar a prévia no canto da tela depois de capturar", isOn: $s.mostrarPrevia)
                .toggleStyle(.switch).controlSize(.small)
            HStack(spacing: 8) {
                Text("Some sozinha em").font(.system(size: 12))
                SeletorCrew(selecao: $s.tempoPrevia,
                            opcoes: [4.0, 6, 10, 20, 60].map { (valor: $0, titulo: "\(Int($0)) s") }
                                + [(valor: 0.0, titulo: "não some")],
                            largura: 110)
                Spacer(minLength: 0)
            }
            .disabled(!s.mostrarPrevia)
            Text("Com o mouse em cima ou fixada, ela espera. Sair da prévia não apaga o arquivo.")
                .font(.system(size: 11)).foregroundColor(.secondary)

            Divider().padding(.vertical, 2)
            Text("Mandar para a sessão").font(.system(size: 12, weight: .semibold))
            TextField("Só a imagem, sem texto", text: $s.mensagemSessao)
                .textFieldStyle(.roundedBorder).controlSize(.small)
            Text("O que vai escrito junto com a imagem. O botão entrega e envia na hora para a sessão do Claude Code em foco (o nome dela está no botão) — nunca sem o seu clique.")
                .font(.system(size: 11)).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            GravacaoAjustes()
        }
        .onDisappear { s.cancelarGravacao() }
    }

    private func linhaAtalho(_ modo: ModoCaptura) -> some View {
        let ligado = s.atalhoLigado[modo] == true
        let gravando = s.gravando == modo
        return HStack(spacing: 8) {
            Toggle("", isOn: Binding(get: { ligado }, set: { s.ligarAtalho(modo, $0) }))
                .toggleStyle(.switch).controlSize(.mini).labelsHidden()
            Image(systemName: modo.icone).frame(width: 18).foregroundColor(.secondary)
            Text(modo.nome).font(.system(size: 12)).frame(width: 92, alignment: .leading)
            Button { gravando ? s.cancelarGravacao() : s.gravarAtalho(modo) } label: {
                Text(gravando ? "aperte a combinação…" : (s.combinacoes[modo]?.rotulo ?? "—"))
                    .font(gravando ? .system(size: 11) : .system(size: 12, weight: .medium).monospaced())
                    .foregroundColor(gravando ? .accentColor : .primary)
                    .padding(.horizontal, 9)
                    .frame(minWidth: 74, minHeight: 22)
                    .background(Color.primary.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor, lineWidth: gravando ? 1.5 : 0))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Clique e aperte a combinação nova")
            if !s.atalhoEhPadrao(modo) {
                Button("Padrão") { s.definirAtalho(modo, .padrao(modo)) }
                    .buttonStyle(.link).font(.system(size: 11))
            }
            if s.recusados.contains(modo) {
                Label("não registrou: outro app (ou outro atalho) já usa esta combinação", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10.5)).foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .opacity(ligado ? 1 : 0.55)
    }
}

enum FormatoCaptura {
    private static let pt = Locale(identifier: "pt_BR")

    static func quando(_ d: Date) -> String {
        let hora = d.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(pt))
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "hoje \(hora)" }
        if cal.isDateInYesterday(d) { return "ontem \(hora)" }
        return d.formatted(Date.FormatStyle().day(.twoDigits).month(.twoDigits).locale(pt)) + " \(hora)"
    }

    static func curto(_ u: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return u.path.hasPrefix(home) ? "~" + u.path.dropFirst(home.count) : u.path
    }
}
