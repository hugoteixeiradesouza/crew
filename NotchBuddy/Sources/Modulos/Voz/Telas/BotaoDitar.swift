import SwiftUI

// Peças prontas para qualquer tela do Crew:
//
//   BotaoDitar(texto: $texto)      microfone: clique começa a ouvir, outro clique para. O que
//                                  foi dito entra no fim do texto (o parcial vai sendo trocado
//                                  até o final chegar).
//   BotaoOuvir(texto: resposta)    alto-falante: lê o texto em voz alta; clique de novo para.
//
// As duas se viram sozinhas (permissão explicada antes do primeiro uso, erro em balão) e não
// fazem nada com o módulo Voz desligado — nesse caso somem.

enum EstiloBotaoVoz {
    /// Ícone de 15 pt numa área de 26 pt (barra de composição).
    case normal
    /// Ícone de 12 pt numa área de 20 pt (linhas apertadas, ilha).
    case compacto

    var icone: CGFloat { self == .normal ? 15 : 12 }
    var lado: CGFloat { self == .normal ? 26 : 20 }
}

struct BotaoDitar: View {
    @Binding var texto: String
    var estilo: EstiloBotaoVoz = .normal

    private let s = VozServico.shared
    @ObservedObject private var registro = Registro.shared
    /// Cada botão é um dono: só o que começou o ditado recebe o texto.
    @State private var meuId = "botao." + UUID().uuidString
    /// O texto do campo no momento em que o ditado começou.
    @State private var base = ""
    @State private var explicando = false
    @State private var mostrandoErro = false

    init(texto: Binding<String>, estilo: EstiloBotaoVoz = .normal) {
        _texto = texto
        self.estilo = estilo
    }

    private var meu: Bool { s.dono == meuId }
    private var ouvindo: Bool { meu && s.estado == .ouvindo }
    private var esperando: Bool { meu && (s.estado == .finalizando || s.estado == .pedindoPermissao) }
    private var erro: String? {
        if meu, case .erro(let m) = s.estado { return m }
        return nil
    }

    var body: some View {
        if registro.estaLigado(VozServico.modulo) {
            Button(action: clicou) {
                ZStack {
                    if ouvindo {
                        // Halo discreto que acompanha o volume da voz
                        Circle().fill(Color.red.opacity(0.18))
                            .scaleEffect(0.7 + 0.5 * CGFloat(s.nivel))
                            .animation(.easeOut(duration: 0.12), value: s.nivel)
                    }
                    Image(systemName: icone)
                        .font(.system(size: estilo.icone, weight: .medium))
                        .foregroundColor(cor)
                        .opacity(esperando ? 0.5 : 1)
                }
                .frame(width: estilo.lado, height: estilo.lado)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(s.ocupado && !meu)
            .help(ajuda)
            .onChange(of: s.texto) { _, novo in
                // Parcial e final do MEU ditado: sempre o texto de antes + o que foi dito
                if meu, s.estado != .pedindoPermissao { texto = Self.juntar(base, novo) }
            }
            .onChange(of: erro) { _, novo in mostrandoErro = novo != nil }
            .onDisappear { if meu, s.ocupado { s.cancelarDitado() } }
            .popover(isPresented: $explicando, arrowEdge: .bottom) { explicacao }
            .popover(isPresented: $mostrandoErro, arrowEdge: .bottom) { balaoErro }
        }
    }

    private var icone: String {
        if erro != nil { return "mic.slash" }
        return ouvindo ? "mic.fill" : "mic"
    }

    private var cor: Color {
        if ouvindo { return .red }
        return erro != nil ? .orange : .secondary
    }

    private var ajuda: String {
        if ouvindo { return "Parar de ouvir" }
        if s.ocupado && !meu { return "Outro ditado está em curso" }
        return "Ditar (o áudio é processado neste Mac)"
    }

    private func clicou() {
        if meu, s.ocupado {
            s.pararDitado()
            return
        }
        s.limparErro()
        s.atualizarPermissoes()
        if s.permissao == .naoPerguntada {
            explicando = true
            return
        }
        comecar(consentido: false)
    }

    private func comecar(consentido: Bool) {
        base = texto
        if !s.ditar(dono: meuId, consentido: consentido), case .erro = s.estado { mostrandoErro = true }
    }

    /// Texto de antes + ditado, com um espaço entre os dois quando precisa.
    static func juntar(_ base: String, _ dito: String) -> String {
        guard !dito.isEmpty else { return base }
        guard let ultimo = base.last else { return dito }
        return base + (ultimo.isWhitespace ? "" : " ") + dito
    }

    private var explicacao: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Ditado no Crew", systemImage: "mic")
                .font(.system(size: 13, weight: .semibold))
            Text("O macOS vai pedir duas permissões: Microfone e Reconhecimento de Fala. O Crew só ouve enquanto o microfone estiver vermelho, transforma a fala em texto neste Mac e não grava nada.")
                .font(.system(size: 12)).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Agora não") { explicando = false }
                Button("Continuar") {
                    explicando = false
                    comecar(consentido: true)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 320)
    }

    private var balaoErro: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("O ditado não começou", systemImage: "mic.slash")
                .font(.system(size: 13, weight: .semibold))
            Text(erro ?? "").font(.system(size: 12)).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                if s.permissao == .negada {
                    Button("Abrir Ajustes do Sistema") {
                        NSWorkspace.shared.open(s.microfone == .negada ? PermissaoVoz.urlMicrofone : PermissaoVoz.urlFala)
                    }
                }
                Button("Ajustes da Voz") { Central.abrir(modulo: VozServico.modulo) }
                Button("Fechar") { s.limparErro() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 360)
    }
}

/// Lê o texto em voz alta; enquanto lê, o mesmo botão para.
struct BotaoOuvir: View {
    let texto: String
    var estilo: EstiloBotaoVoz = .normal

    private let s = VozServico.shared
    @ObservedObject private var registro = Registro.shared

    init(texto: String, estilo: EstiloBotaoVoz = .normal) {
        self.texto = texto
        self.estilo = estilo
    }

    private var lendo: Bool { s.falandoTexto == texto }

    var body: some View {
        if registro.estaLigado(VozServico.modulo) {
            Button {
                if lendo { s.parar() } else { s.falar(texto) }
            } label: {
                Image(systemName: lendo ? "stop.circle.fill" : "speaker.wave.2")
                    .font(.system(size: estilo.icone, weight: .medium))
                    .foregroundColor(lendo ? .accentColor : .secondary)
                    .frame(width: estilo.lado, height: estilo.lado)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || s.ocupado)
            .help(lendo ? "Parar a leitura" : "Ouvir em voz alta")
        }
    }
}

/// Medidor pequeno do volume da voz: quatro barras que sobem com o nível (0…1).
struct MedidorVoz: View {
    let nivel: Float
    var cor: Color = .red

    private static let pesos: [CGFloat] = [0.55, 1, 0.8, 0.45]

    var body: some View {
        GeometryReader { g in
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<Self.pesos.count, id: \.self) { i in
                    Capsule().fill(cor)
                        .frame(height: max(2.5, g.size.height * CGFloat(nivel) * Self.pesos[i]))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeOut(duration: 0.12), value: nivel)
        }
    }
}
