import SwiftUI
import AppKit
import AVFoundation
import Speech

// As páginas "Ilha" e "App" dos Ajustes e as peças da página "Crew" (permissões e índice de
// atalhos). A separação é por superfície — docs/ARQUITETURA.md §1: a ilha é atalho para a
// rotina (segundos); o app é onde se trabalha (horas).

/// Título de página dos Ajustes: ícone, nome e uma frase dizendo o que mora ali.
struct CabecalhoPagina: View {
    let icone: String
    let titulo: String
    let detalhe: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icone).font(.system(size: 22)).frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(titulo).font(.system(size: 18, weight: .semibold))
                Text(detalhe).font(.system(size: 12)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Ilha

/// Tudo que é do notch: o Homie, quando a ilha abre e some, e o que aparece nela.
struct PaginaIlha: View {
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var registro = Registro.shared
    @State private var hotkeyFlags: UInt = AppState.shared.hotkeyFlags
    @State private var hotkeyCode: UInt16 = AppState.shared.hotkeyCode

    private var minutosParada: Binding<Double> {
        Binding(get: { state.absenceInterval / 60 }, set: { state.absenceInterval = max(1, $0) * 60 })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                CabecalhoPagina(icone: Superficie.ilha.icone, titulo: "Ilha",
                                detalhe: "O notch é o atalho para a rotina: olhar e agir em segundos. Aqui fica o \(state.nomeDoPersonagem), quando a ilha abre e some, e o que aparece nela.")

                Secao("Personagem", "Como ele se chama e como ele é. Muda na hora, na ilha também.") {
                    PersonagemAjustes(state: state)
                }

                Secao("Sons", nil) {
                    LinhaModulo(icone: "speaker.fill", titulo: "Sons do \(state.nomeDoPersonagem)",
                                detalhe: "Avisos sonoros de aprovação, pergunta e fim de tarefa.",
                                ligado: $state.soundEnabled)
                    if state.soundEnabled {
                        HStack(spacing: 10) {
                            Text("Volume dos sons").font(.system(size: 12)).foregroundColor(.secondary)
                            Slider(value: $state.soundVolume, in: 0...0.2)
                            Text("\(Int(state.soundVolume / 0.2 * 100))%")
                                .font(.system(size: 12)).monospacedDigit()
                                .frame(width: 38, alignment: .trailing)
                        }
                        .padding(.leading, 34)
                    }
                }

                Secao("Abrir e fechar", "Com sessão trabalhando, aprovação esperando ou música tocando, a ilha não some.") {
                    HStack(spacing: 8) {
                        Text("Fechar a ilha aberta depois de")
                        TextField("15", value: $state.autoCloseInterval, format: .number)
                            .textFieldStyle(.roundedBorder).frame(width: 52)
                        Text("s sem uso")
                    }
                    HStack(spacing: 8) {
                        Text("Esconder a ilha compacta depois de")
                        TextField("3", value: minutosParada, format: .number)
                            .textFieldStyle(.roundedBorder).frame(width: 52)
                        Text("min parada")
                    }
                    Divider()
                    LinhaModulo(icone: "option", titulo: "Option duas vezes",
                                detalhe: "Abre e fixa a ilha na última aba usada; de novo, recolhe.",
                                ligado: $state.moduloOptionDuplo)
                    Divider()
                    Toggle("Abrir a ilha com um atalho", isOn: $state.hotkeyEnabled)
                    if state.hotkeyEnabled {
                        HStack(spacing: 8) {
                            Text("Atalho")
                            ShortcutRecorderButton(flags: $hotkeyFlags, code: $hotkeyCode)
                                .onChange(of: hotkeyFlags) { _, v in state.hotkeyFlags = v }
                                .onChange(of: hotkeyCode) { _, v in state.hotkeyCode = v }
                        }
                    }
                }

                Secao("O que aparece na ilha", "Ao lado da câmera cabem 2 atalhos de ferramenta; todas ficam sempre na grade (botão de grade no topo da ilha). A home mostra até \(Registro.maxBlocos) blocos.") {
                    let lista = registro.modulos.filter { registro.estaLigado($0.id) && ($0.temAba || $0.temBloco) }
                    HStack {
                        Text("Ferramenta").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Atalho no topo").frame(width: 100)
                        Text("Bloco na home").frame(width: 100)
                    }
                    .font(.system(size: 11, weight: .medium)).foregroundColor(.secondary)
                    ForEach(lista, id: \.id) { m in
                        Divider()
                        HStack {
                            Button { irPara(.modulo(m.id)) } label: {
                                Label(m.nome, systemImage: m.icone).font(.system(size: 13))
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Group {
                                if m.temAba {
                                    Toggle("", isOn: Binding(get: { registro.abaNaIlha(m.id) },
                                                             set: { registro.definirAbaNaIlha(m.id, $0) }))
                                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                                } else { Text("—").foregroundColor(.secondary) }
                            }
                            .frame(width: 100)
                            Group {
                                if m.temBloco {
                                    Toggle("", isOn: Binding(get: { registro.naHome(m) },
                                                             set: { registro.definirNaHome(m.id, $0) }))
                                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                                } else { Text("—").foregroundColor(.secondary) }
                            }
                            .frame(width: 100)
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - App

/// A janela de trabalho: sessões, navegador e os atalhos dela.
struct PaginaApp: View {
    @AppStorage("modulo.sessoes.sugestao") private var sugestao = true

    /// Os atalhos da janela das sessões (a fonte é `Central/Atalhos.swift` e `AppCrewView.vigiarTeclas`).
    private static let atalhos: [(String, String)] = [
        ("⌘1 … ⌘\(Setor.allCases.count)", "Ir para o setor: " + Setor.allCases.map(\.nome).joined(separator: ", ")),
        ("⌘N", "Sessão nova (na grade: em branco, no fim dela)"),
        ("⌘W", "Encerrar a sessão em foco, com confirmação"),
        ("⌘G", "Ligar e desligar a grade de sessões"),
        ("⌘← ⌘→ ⌘↑ ⌘↓", "Na grade: mudar o painel em foco"),
        ("⌃⌘← ⌃⌘→", "Na grade: mudar o painel em foco de lugar"),
        ("⌥⌘↑ ⌥⌘↓", "Sessão anterior e próxima"),
        ("⌥M ou ⌃⌘S", "Mostrar e recolher a barra lateral"),
        ("⌘F", "Buscar na barra lateral"),
        ("⌘J", "Abrir e recolher o navegador (ao lado da sessão; fora de sessão, na janela inteira, em \(Setor.mesa.nome))"),
        ("⌘T ⌘W ⌘L ⌘R ⌘[ ⌘]", "No navegador: aba nova, fechar, endereço, recarregar, voltar, avançar"),
        ("⌘,", "Abrir estes Ajustes"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                CabecalhoPagina(icone: Superficie.app.icone, titulo: "App",
                                detalhe: "A janela do Crew é onde você trabalha, em seis setores: " + Setor.allCases.map(\.nome).joined(separator: ", ") + ". Aberta, o Crew vira app de Dock; fechada, volta a morar só no notch.")

                Secao("Janela", nil) {
                    Button("Abrir o app do Crew") { Central.abrirSessoes() }
                }

                Secao("Sessões", "Modelo, esforço, permissões e instrução fixa das sessões novas são por projeto: no app, clique no projeto na barra lateral e abra \"Sessões novas\".") {
                    Toggle("Sugerir a próxima mensagem no chat (modelo local, nada sai do Mac)", isOn: $sugestao)
                    Button("Hooks do Claude Code…") { irPara(.modulo(SessoesModulo.shared.id)) }
                }

                Secao("Atalhos do app", "Valem com a janela do Crew na frente. Os globais estão na página Crew.") {
                    ForEach(Self.atalhos, id: \.0) { a in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(a.0).font(.system(size: 12, design: .monospaced))
                                .frame(width: 150, alignment: .leading)
                            Text(a.1).font(.system(size: 12)).foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Peças da página Crew

@MainActor
private func irPara(_ pagina: PaginaCentral) {
    NotificationCenter.default.post(name: .irParaPagina, object: pagina)
}

/// As permissões do macOS que o Crew usa: estado de cada uma, quem pede e o caminho para mudar.
/// Só lê o estado — nenhuma dessas leituras faz o macOS perguntar nada.
struct PermissoesDoMac: View {
    private struct Linha: Identifiable {
        let id: String
        let nome: String
        let quemUsa: String
        let estado: Estado
        /// Painel de Privacidade e Segurança dos Ajustes do Sistema.
        let painel: String
    }
    private enum Estado { case liberada, negada, naoPedida }

    @State private var linhas: [Linha] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(linhas) { l in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: icone(l.estado))
                        .foregroundColor(cor(l.estado))
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(l.nome).font(.system(size: 13, weight: .medium))
                        Text("\(texto(l.estado)) · usada por \(l.quemUsa)")
                            .font(.system(size: 11)).foregroundColor(.secondary)
                    }
                    Spacer(minLength: 8)
                    Button("Abrir no macOS") {
                        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(l.painel)") {
                            NSWorkspace.shared.open(u)
                        }
                    }
                    .controlSize(.small)
                }
            }
        }
        .onAppear(perform: ler)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in ler() }
    }

    private func ler() {
        func deStatus(_ autorizado: Bool, _ naoDeterminado: Bool) -> Estado {
            autorizado ? .liberada : (naoDeterminado ? .naoPedida : .negada)
        }
        let mic = AVCaptureDevice.authorizationStatus(for: .audio)
        let fala = SFSpeechRecognizer.authorizationStatus()
        linhas = [
            Linha(id: "acessibilidade", nome: "Acessibilidade", quemUsa: "Brilho e volume (teclas de brilho e volume)",
                  estado: AXIsProcessTrusted() ? .liberada : .negada, painel: "Privacy_Accessibility"),
            Linha(id: "tela", nome: "Gravação de tela", quemUsa: "Captura (foto e gravação de tela)",
                  estado: CGPreflightScreenCaptureAccess() ? .liberada : .negada, painel: "Privacy_ScreenCapture"),
            Linha(id: "microfone", nome: "Microfone", quemUsa: "Voz (ditado) e Captura (gravação de tela)",
                  estado: deStatus(mic == .authorized, mic == .notDetermined), painel: "Privacy_Microphone"),
            Linha(id: "fala", nome: "Reconhecimento de fala", quemUsa: "Voz (ditado)",
                  estado: deStatus(fala == .authorized, fala == .notDetermined), painel: "Privacy_SpeechRecognition"),
        ]
    }

    private func icone(_ e: Estado) -> String {
        switch e {
        case .liberada: "checkmark.circle.fill"
        case .negada: "xmark.circle"
        case .naoPedida: "questionmark.circle"
        }
    }
    private func cor(_ e: Estado) -> Color {
        switch e {
        case .liberada: .green
        case .negada: .orange
        case .naoPedida: .secondary
        }
    }
    private func texto(_ e: Estado) -> String {
        switch e {
        case .liberada: "Liberada"
        case .negada: "Não liberada"
        case .naoPedida: "Ainda não pedida"
        }
    }
}

/// Índice dos atalhos globais: o que cada um faz e em que página se ajusta.
struct IndiceAtalhos: View {
    private static let itens: [(icone: String, nome: String, dono: String, pagina: PaginaCentral)] = [
        ("rectangle.topthird.inset.filled", "Abrir a ilha (atalho ou Option duas vezes)", "Ilha", .ilha),
        ("mic", "Segurar para falar", "Voz", .modulo(VozModulo.shared.id)),
        ("camera.viewfinder", "Capturar área, janela, tela e texto da tela; gravar a tela", "Captura", .modulo(CapturaModulo.shared.id)),
        ("hifispeaker.2", "Volume do app em foco", "Áudio", .modulo(AudioModulo.shared.id)),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Self.itens, id: \.nome) { i in
                HStack(spacing: 12) {
                    Image(systemName: i.icone).frame(width: 22).foregroundColor(.secondary)
                    Text(i.nome).font(.system(size: 13))
                    Spacer(minLength: 8)
                    Button("Ajustar em \(i.dono)") { irPara(i.pagina) }.controlSize(.small)
                }
            }
        }
    }
}
