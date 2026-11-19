import AVFoundation
import SwiftUI

// A gravação de tela na página da Captura: começar e parar, o que entra (microfone, som, câmera),
// a lista de gravações e os ajustes. E a linha que fica na barra da ilha enquanto grava.

/// "Gravar a tela": os três alvos, ou o tempo correndo e o botão de parar.
struct GravacaoGravar: View {
    @Bindable private var g = GravacaoServico.shared

    var body: some View {
        Secao("Gravar a tela", "Começa e para pelo mesmo atalho\(g.rotuloAtalho.map { " (\($0))" } ?? ""). O vídeo fica neste Mac.") {
            switch g.fase {
            case .gravando(let desde):
                HStack(spacing: 10) {
                    Circle().fill(Color(hex: "#F4505E")).frame(width: 10, height: 10)
                    Text("Gravando").font(.system(size: 13, weight: .medium))
                    Text(desde, style: .timer).font(.system(size: 13).monospacedDigit()).foregroundColor(.secondary)
                    Spacer(minLength: 8)
                    Button { g.pararGravacao() } label: { Label("Parar e guardar", systemImage: "stop.fill") }
                        .keyboardShortcut(.defaultAction)
                }
            case .escolhendo(let alvo):
                linha("Escolha na tela (\(alvo.nome.lowercased())) — Esc cancela.", "cursorarrow.rays", .accentColor, cancelar: true)
            case .contagem(let n):
                linha("Gravando em \(n)…", "timer", .accentColor, cancelar: true)
            case .iniciando:
                linha("Começando…", "hourglass", .secondary, cancelar: false)
            case .finalizando:
                linha("Guardando o vídeo…", "hourglass", .secondary, cancelar: false)
            case .parado:
                HStack(spacing: 8) {
                    ForEach(AlvoGravacao.allCases) { alvo in botaoAlvo(alvo) }
                }
            }

            HStack(spacing: 14) {
                Toggle(isOn: $g.microfone) { Label("Microfone", systemImage: "mic") }
                Toggle(isOn: $g.somDoSistema) { Label("Som do Mac", systemImage: "speaker.wave.2") }
                Toggle(isOn: $g.camera) { Label("Câmera", systemImage: "web.camera") }
                Toggle(isOn: $g.ilhaNoVideo) { Label("Ilha do Crew", systemImage: "rectangle.topthird.inset.filled") }
                    .help("Ligado, o Homie e o que a ilha mostrar aparecem no vídeo. Desligado, a ilha fica fora da gravação.")
                Spacer(minLength: 0)
            }
            .toggleStyle(.checkbox).font(.system(size: 12))
            .disabled(g.ocupado)

            if g.microfone, g.permissaoMicrofone != .authorized {
                faltaPermissao("Sem a permissão do microfone, a gravação sai sem a sua voz.", "mic.slash", .audio)
            }
            if g.camera, g.permissaoCamera != .authorized {
                faltaPermissao("Sem a permissão da câmera, a bolha não aparece.", "video.slash", .video)
            }
            if let a = g.aviso, g.fase == .parado {
                linha(a.texto, a.erro ? "exclamationmark.triangle.fill" : "checkmark.circle", a.erro ? .orange : .secondary, cancelar: false)
            }
        }
        .onAppear { g.atualizar() }
    }

    private func botaoAlvo(_ alvo: AlvoGravacao) -> some View {
        Button { g.comecar(alvo) } label: {
            VStack(spacing: 5) {
                ZStack(alignment: .bottomTrailing) {
                    Image(systemName: alvo.icone).font(.system(size: 18)).frame(width: 30, height: 22)
                    Circle().fill(Color(hex: "#F4505E")).frame(width: 8, height: 8).offset(x: 3, y: 1)
                }
                Text(alvo.nome).font(.system(size: 12, weight: .medium))
                Text(alvo == g.alvoPadrao ? (g.rotuloAtalho ?? "sem atalho") : " ")
                    .font(.system(size: 10.5).monospaced())
                    .foregroundColor(g.atalhoRecusado ? .orange : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(alvo.explicacao)
    }

    private func linha(_ texto: String, _ icone: String, _ cor: Color, cancelar: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: icone).foregroundColor(cor)
            Text(texto).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if cancelar { Button("Cancelar") { g.cancelar() }.controlSize(.small) }
        }
        .font(.system(size: 11.5)).foregroundColor(.secondary)
    }

    private func faltaPermissao(_ texto: String, _ icone: String, _ tipo: AVMediaType) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icone).foregroundColor(.orange)
            Text(texto).font(.system(size: 11.5)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button("Liberar…") { g.pedirPermissao(tipo) }.controlSize(.small)
        }
    }
}

/// A lista de gravações: primeiro quadro, duração, tamanho e o que fazer com cada uma.
struct GravacoesLista: View {
    private let g = GravacaoServico.shared
    @ObservedObject private var estado = AppState.shared
    @State private var retornos: [String: String] = [:]

    var body: some View {
        Secao("Gravações", detalhe) {
            if g.gravacoes.isEmpty {
                Text("Nenhuma gravação ainda. Aperte \(g.rotuloAtalho ?? "um dos botões de gravar") para começar, e de novo para parar.")
                    .font(.system(size: 12)).foregroundColor(.secondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(g.gravacoes) { item in linha(item) }
                }
            }
        }
    }

    private var detalhe: String {
        let n = g.gravacoes.count
        guard n > 0 else { return "Ficam em \(FormatoCaptura.curto(g.pastaMostrada))." }
        return "\(n == 1 ? "1 gravação" : "\(n) gravações"), \(PoliticaGravacao.tamanho(g.totalEmDisco)) em \(FormatoCaptura.curto(g.pastaMostrada)). O Crew nunca apaga gravação sozinho."
    }

    private func linha(_ item: Gravacao) -> some View {
        HStack(spacing: 12) {
            Button { g.tocar(item) } label: { MiniaturaGravacao(gravacao: item).frame(width: 128, height: 78) }
                .buttonStyle(.plain)
                .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
                .help("Clique para tocar no app padrão; arraste para soltar o arquivo em outro app")
            VStack(alignment: .leading, spacing: 3) {
                Text(FormatoCaptura.quando(item.data)).font(.system(size: 12.5, weight: .medium)).monospacedDigit()
                Text(retornos[item.id] ?? resumo(item))
                    .font(.system(size: 11)).monospacedDigit().lineLimit(2)
                    .foregroundColor(retornos[item.id] == nil ? .secondary : .accentColor)
                HStack(spacing: 2) {
                    acao("play.fill", "Tocar no app padrão") { g.tocar(item) }
                    acao("folder", "Mostrar no Finder") { g.mostrarNoFinder(item) }
                    acao("doc.on.clipboard", "Copiar o caminho do arquivo") {
                        g.copiarCaminho(item)
                        dizer(item, "Caminho copiado")
                    }
                    let sessao = sessaoAlvo
                    acao("paperplane", sessao.map { "Mandar para \($0.displayTitle)" } ?? "Sem sessão do Claude Code em foco") {
                        guard let sessao else { return }
                        dizer(item, "Mandando…")
                        Task {
                            let erro = await g.mandar(item, para: sessao)
                            dizer(item, erro.map { "Não foi: \($0)" } ?? "Enviada para \(sessao.displayTitle)")
                        }
                    }
                    .disabled(sessao == nil)
                    acao("film", "Editar: escolha de qual projeto é o vídeo; vira um projeto de vídeo e a sessão do Claude Code edita com o contexto dele") { editar(item) }
                    acao("trash", "Mandar para a Lixeira") { g.apagar(item) }
                }
            }
            Spacer(minLength: 0)
        }
        .menuContexto {
            [.acao("Tocar", icone: "play") { g.tocar(item) },
             .acao("Mostrar no Finder", icone: "folder") { g.mostrarNoFinder(item) },
             .acao("Copiar o caminho", icone: "doc.on.clipboard") { g.copiarCaminho(item) },
             .acao("Editar com o Claude Code", icone: "film") { editar(item) },
             .divisor,
             .acao("Mandar para a Lixeira", icone: "trash", destrutivo: true) { g.apagar(item) }]
        }
    }

    /// A gravação vira um projeto do módulo Vídeo (Remotion) e a sessão que edita abre no app,
    /// enxergando o projeto que o Hugo escolher no menu (ou nenhum).
    private func editar(_ item: Gravacao) {
        EscolhaProjetoVideo.perguntar { contexto in
            dizer(item, "Criando o projeto de vídeo e transcrevendo a fala…", segundos: 120)
            Task {
                switch await VideoServico.shared.editarGravacao(item.url, projeto: contexto) {
                case .success(let p): dizer(item, "Projeto \(p.nome) criado: a sessão vai propor a edição", segundos: 6)
                case .failure(let f): dizer(item, f.texto, segundos: 6)
                }
            }
        }
    }

    private func resumo(_ item: Gravacao) -> String {
        let tamanho = PoliticaGravacao.tamanho(item.bytes)
        return g.duracoes[item.id].map { "\(PoliticaGravacao.duracao($0)) · \(tamanho)" } ?? tamanho
    }

    private var sessaoAlvo: AgentTask? {
        _ = estado.focusId
        return CapturaServico.shared.sessaoAlvo
    }

    private func dizer(_ item: Gravacao, _ texto: String, segundos: Double = 3) {
        retornos[item.id] = texto
        DispatchQueue.main.asyncAfter(deadline: .now() + segundos) {
            if retornos[item.id] == texto { retornos[item.id] = nil }
        }
    }

    private func acao(_ icone: String, _ ajuda: String, _ f: @escaping () -> Void) -> some View {
        Button(action: f) {
            Image(systemName: icone).font(.system(size: 12)).frame(width: 30, height: 22).contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(ajuda)
        .accessibilityLabel(ajuda)
    }
}

/// Primeiro quadro de uma gravação com a duração por cima (carrega fora da main, uma vez).
struct MiniaturaGravacao: View {
    let gravacao: Gravacao
    private let g = GravacaoServico.shared

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
            if let img = g.miniaturas[gravacao.id] {
                Image(nsImage: img).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "film").font(.system(size: 18)).foregroundColor(.white.opacity(0.3))
            }
            Image(systemName: "play.circle.fill").font(.system(size: 24))
                .foregroundStyle(.white, Color.black.opacity(0.45))
        }
        .overlay(alignment: .bottomTrailing) {
            if let d = g.duracoes[gravacao.id] {
                Text(PoliticaGravacao.duracao(d))
                    .font(.system(size: 10, weight: .medium)).monospacedDigit().foregroundColor(.white)
                    .padding(.horizontal, 5).padding(.vertical, 1.5)
                    .background(Color.black.opacity(0.65)).clipShape(Capsule())
                    .padding(5)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
        .task(id: gravacao.id) { await g.carregarDetalhes(gravacao) }
    }
}

/// Ajustes da gravação (dentro dos ajustes da Captura).
struct GravacaoAjustes: View {
    @Bindable private var g = GravacaoServico.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider().padding(.vertical, 2)
            Text("Gravação de tela").font(.system(size: 12, weight: .semibold))
            linhaAtalho
            HStack(spacing: 8) {
                Text("O atalho grava").font(.system(size: 12))
                SeletorCrew(selecao: $g.alvoPadrao, opcoes: AlvoGravacao.allCases.map { (valor: $0, titulo: $0.nome) }, largura: 130)
                Spacer(minLength: 0)
            }
            Group {
                Toggle("Gravar o microfone", isOn: $g.microfone)
                Toggle("Gravar o som do Mac (os sons do Crew ficam de fora)", isOn: $g.somDoSistema)
                Toggle("Mostrar a bolha da câmera durante a gravação", isOn: $g.camera)
                Toggle("Contagem de 3 segundos antes de começar", isOn: $g.contagem)
                Toggle("Mostrar o cursor do mouse no vídeo", isOn: $g.cursor)
                Toggle("Mostrar a ilha do Crew no vídeo (o Homie e o aviso de gravação)", isOn: $g.ilhaNoVideo)
            }
            .toggleStyle(.switch).controlSize(.small)
            HStack(spacing: 8) {
                Text("Microfone").font(.system(size: 12))
                SeletorCrew(selecao: $g.microfoneId, opcoes: aparelhos(g.microfones), largura: 200, vazio: "Desconectado (vale o padrão)")
                Text("Câmera").font(.system(size: 12)).padding(.leading, 10)
                SeletorCrew(selecao: $g.cameraId, opcoes: aparelhos(g.cameras), largura: 200, vazio: "Desconectada (vale a padrão)")
                Spacer(minLength: 0)
            }
            .disabled(g.ocupado)
            Toggle("Guardar o rastro do mouse para a edição (posição e cliques; nenhuma tecla)", isOn: $g.rastroDoMouse)
                .toggleStyle(.switch).controlSize(.small)
            HStack(spacing: 8) {
                Text("Quadros por segundo").font(.system(size: 12))
                SeletorCrew(selecao: $g.quadros, opcoes: [(valor: 30, titulo: "30"), (valor: 60, titulo: "60")], largura: 70)
                Text("Qualidade").font(.system(size: 12)).padding(.leading, 10)
                SeletorCrew(selecao: $g.leve, opcoes: [(valor: false, titulo: "Nítida (resolução da tela)"), (valor: true, titulo: "Leve (metade dos pixels)")],
                            largura: 200)
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                Text("Bolha da câmera").font(.system(size: 12))
                SeletorCrew(selecao: $g.ladoBolha, opcoes: [(valor: 140.0, titulo: "Pequena"), (valor: 200, titulo: "Média"), (valor: 280, titulo: "Grande")],
                            largura: 110)
                Button(BolhaCamera.shared.naTela ? "Esconder" : "Ver a câmera agora") { g.alternarBolha() }
                    .controlSize(.small).disabled(g.ocupado)
                Spacer(minLength: 0)
            }
            Text("Vídeo MP4 (H.264), em \(FormatoCaptura.curto(g.pastaMostrada)). A ilha e as prévias do Crew ficam fora do vídeo; a bolha da câmera entra por estar na tela (arraste para mudar de lugar) — menos na gravação de uma janela, que leva só a janela. Microfone e som do Mac vão em trilhas separadas do arquivo.")
                .font(.system(size: 11)).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { g.atualizarAparelhos() }
        .onDisappear { g.cancelarGravadorDeAtalho() }
    }

    private func aparelhos(_ lista: [AparelhoGravacao]) -> [(valor: String, titulo: String)] {
        [(valor: "", titulo: "Padrão do macOS")] + lista.map { (valor: $0.id, titulo: $0.nome) }
    }

    private var linhaAtalho: some View {
        let gravando = g.gravandoAtalho
        return HStack(spacing: 8) {
            Toggle("", isOn: Binding(get: { g.atalhoLigado }, set: { g.ligarAtalho($0) }))
                .toggleStyle(.switch).controlSize(.mini).labelsHidden()
            Image(systemName: "record.circle").frame(width: 18).foregroundColor(.secondary)
            Text("Gravar / parar").font(.system(size: 12)).frame(width: 92, alignment: .leading)
            Button { gravando ? g.cancelarGravadorDeAtalho() : g.gravarAtalho() } label: {
                Text(gravando ? "aperte a combinação…" : g.combinacao.rotulo)
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
            if !g.atalhoEhPadrao {
                Button("Padrão") { g.definirAtalho(.padraoGravar) }.buttonStyle(.link).font(.system(size: 11))
            }
            if g.atalhoRecusado {
                Label("não registrou: outro app (ou outro atalho) já usa esta combinação", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10.5)).foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .opacity(g.atalhoLigado ? 1 : 0.55)
    }
}

/// A linha da gravação na barra da ilha fechada: ponto vermelho, tempo correndo e o botão de
/// parar. O tempo é um texto de relógio do sistema (um redesenho por segundo, só enquanto grava).
struct SinalGravando: View {
    let desde: Date

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(Color(hex: "#F4505E")).frame(width: 9, height: 9)
                .overlay(Circle().stroke(Color(hex: "#F4505E").opacity(0.35), lineWidth: 3))
            Text("Gravando").font(.system(size: 12, weight: .medium)).foregroundColor(Color(hex: "#DADDE2"))
            Text(desde, style: .timer)
                .font(.system(size: 12, weight: .medium).monospacedDigit()).foregroundColor(Color(hex: "#9398A1"))
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                Image(systemName: "stop.fill").font(.system(size: 9, weight: .bold))
                Text("Parar").font(.system(size: 11.5, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 10).frame(height: 24)
            .background(Color(hex: "#F4505E"))
            .clipShape(Capsule())
            .contentShape(Capsule())
            .onTapGesture { GravacaoServico.shared.pararGravacao() }
            .help("Parar e guardar a gravação")
            .accessibilityLabel("Parar a gravação")
        }
    }
}
