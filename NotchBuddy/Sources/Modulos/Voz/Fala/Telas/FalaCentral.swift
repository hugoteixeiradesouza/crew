import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

// A voz do computador na página da Voz: escolher quem fala (voz do macOS ou voz humanizada),
// testar com um texto, instalar/remover o motor de voz humanizada, criar e escolher vozes, e
// decidir quando o Crew fala sozinho. Mesma cara do motor de vídeo.

struct FalaCentral: View {
    @Bindable private var s = FalaServico.shared
    private let voz = VozServico.shared
    @State private var texto = "Terminei a tarefa. Os testes passaram e só falta você aprovar a instalação."
    @State private var desenho = DesenhoDeVoz()
    @State private var nomeNovo = ""
    @State private var confirmandoRemover = false
    @State private var clone: URL?
    @State private var nomeClone = ""
    @State private var transcricao = ""
    @State private var vozesDoMac: [VozServico.VozInstalada] = []
    @State private var vozPessoal = AVSpeechSynthesizer.personalVoiceAuthorizationStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            quemFala
            motor
            if s.instalado {
                vozes
                novaVoz
            }
            if let a = s.aviso { linhaAviso(a) }
            quandoFala
        }
        .onAppear {
            s.atualizar()
            vozesDoMac = voz.vozes()
            // Página aberta com a voz humanizada em uso: o motor já vai ligando para o "Ouvir"
            s.aquecer()
        }
    }

    // MARK: Quem fala

    private var quemFala: some View {
        Secao("Voz do computador", "Quem fala quando o Crew lê uma resposta, dá um aviso ou uma sessão do Claude Code pede para falar. Tudo neste Mac: nenhum texto vai para a rede.") {
            HStack(spacing: 8) {
                Text("Quem fala").font(.system(size: 12))
                SeletorCrew(selecao: $s.motor, opcoes: FalaServico.Motor.allCases.map { (valor: $0, titulo: $0.rotulo) })
                    .frame(maxWidth: 320, alignment: .leading)
            }
            switch s.motor {
            case .macos:
                nota("Fala na hora e não ocupa memória. Voz em uso: \(nomeDaVozDoMac). A voz e a velocidade se escolhem nos ajustes abaixo (\"Ler em voz alta\").")
                if !temVozBoaNoMac {
                    HStack(spacing: 8) {
                        Label("Este Mac só tem as vozes básicas em português. As vozes Aprimorada e Premium soam bem melhor e são gratuitas.",
                              systemImage: "arrow.down.circle")
                            .font(.system(size: 11)).foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Baixar no macOS…") { Self.abrirVozesDoSistema() }.controlSize(.small)
                    }
                }
                if vozPessoal == .notDetermined {
                    HStack(spacing: 8) {
                        Text("Se você criou uma Voz Pessoal no macOS, o Crew pode usá-la.")
                            .font(.system(size: 11)).foregroundColor(.secondary)
                        Button("Permitir a Voz Pessoal…") {
                            AVSpeechSynthesizer.requestPersonalVoiceAuthorization { status in
                                Task { @MainActor in
                                    vozPessoal = status
                                    vozesDoMac = voz.vozes()
                                }
                            }
                        }.controlSize(.small)
                    }
                }
            case .omnivoice:
                if s.instalado {
                    nota("Voz em uso: \(s.vozPadrao?.nome ?? "a voz do motor (sem identidade fixa: crie uma voz abaixo)"). Soa como gente, mas uma frase nova leva segundos para ser gerada antes de tocar\(s.aceitaVelocidade ? "" : " (de 6 a 11 com o motor ligado, medido num M2)"). Frase que já foi dita toca na hora, e os avisos das sessões abertas ficam prontos antes. Se o motor falhar, a fala sai pela voz do macOS.")
                    ritmo
                } else {
                    Label("O motor de voz humanizada ainda não está instalado: por enquanto quem fala é a voz do macOS.", systemImage: "exclamationmark.triangle")
                        .font(.system(size: 11)).foregroundColor(.orange)
                }
            }
            Divider()
            TextField("Texto para testar a voz", text: $texto, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .lineLimit(2...5)
                .padding(8)
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            HStack(spacing: 8) {
                Button {
                    if voz.falando { voz.parar() } else { voz.falar(texto) }
                } label: {
                    Label(voz.falando ? "Parar" : "Ouvir", systemImage: voz.falando ? "stop.fill" : "play.fill")
                }
                .disabled(voz.ocupado || texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if s.ocupada { ProgressView().controlSize(.small).opacity(s.estado == .falando ? 0 : 1) }
                Text(estado).font(.system(size: 11)).foregroundColor(.secondary)
                Spacer(minLength: 0)
            }
        }
    }

    private var estado: String {
        switch s.estado {
        case .ligando: "Ligando o motor de voz (alguns segundos na primeira fala)…"
        case .gerando: "Gerando a fala…"
        case .falando: "Falando."
        case .parada: voz.falando ? "Falando." : (s.aquecendo ? "Ligando o motor de voz para a próxima fala…" : "")
        }
    }

    // MARK: Ritmo da voz humanizada

    /// Velocidade da geração, por quanto tempo o motor fica ligado e as falas guardadas.
    @ViewBuilder private var ritmo: some View {
        if s.aceitaVelocidade {
            HStack(spacing: 8) {
                Text("Velocidade").font(.system(size: 12))
                SeletorCrew(selecao: $s.velocidade, opcoes: FalaServico.Velocidade.allCases.map { (valor: $0, titulo: $0.rotulo) })
                Text(notaDaVelocidade).font(.system(size: 11)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        } else if s.instalando == nil {
            HStack(alignment: .top, spacing: 8) {
                Label("O motor instalado gera sempre no capricho máximo, o mais demorado. Atualizar compila o motor de novo (cerca de um minuto, baixa só o código) e libera a escolha entre Mais rápida, Equilibrada e Melhor.",
                      systemImage: "hare")
                    .font(.system(size: 11)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("Atualizar o motor") { s.atualizarMotor() }.controlSize(.small)
                    .disabled(MotorOmniVoice.motivoIndisponivel != nil)
            }
        }
        HStack(spacing: 8) {
            Text("Manter o motor ligado por").font(.system(size: 12))
            SeletorCrew(selecao: $s.manterLigado, opcoes: FalaServico.temposLigado.map { (valor: $0, titulo: $0 == 60 ? "1 hora" : "\($0) minutos") })
            Text("depois da última fala. Ligado, a fala não espera o motor subir; custa 1 GB de memória e nada de processador.")
                .font(.system(size: 11)).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        if s.falasGuardadas > 0 {
            HStack(spacing: 8) {
                Text("\(s.falasGuardadas) \(s.falasGuardadas == 1 ? "fala guardada" : "falas guardadas") (\(Self.tamanho(s.bytesDasFalas))): repetem na hora, sem gerar de novo.")
                    .font(.system(size: 11)).foregroundColor(.secondary)
                Button("Limpar") { s.limparFalas() }.controlSize(.small)
                Spacer(minLength: 0)
            }
        }
    }

    private var notaDaVelocidade: String {
        switch s.velocidade {
        case .rapida: "Um quarto do tempo da Melhor; a voz pode perder nitidez."
        case .equilibrada: "Metade do tempo da Melhor."
        case .melhor: "O capricho máximo, o mais demorado."
        }
    }

    private var nomeDaVozDoMac: String {
        if let id = voz.vozId, let v = vozesDoMac.first(where: { $0.id == id }) { return v.nome }
        return "a padrão do macOS para português"
    }

    private var temVozBoaNoMac: Bool {
        vozesDoMac.contains { $0.nome.contains("(premium)") || $0.nome.contains("(aprimorada)") || $0.nome.contains("(Voz Pessoal)") }
    }

    private static func abrirVozesDoSistema() {
        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.universalaccess?SpokenContent") {
            NSWorkspace.shared.open(u)
        }
    }

    // MARK: Motor

    private var motor: some View {
        Secao("Motor de voz humanizada", "O OmniVoice roda como um programa à parte, compilado para este Mac. Liga quando há o que falar (ou ao abrir esta página) e desliga sozinho depois de \(s.manterLigado == 60 ? "1 hora" : "\(s.manterLigado) minutos") parado, ou antes se a memória do Mac apertar.") {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: s.instalado ? "checkmark.seal.fill" : "shippingbox")
                    .font(.system(size: 20))
                    .foregroundColor(s.instalado ? Color(hex: "#34D399") : .secondary)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 3) {
                    Text(s.instalado ? "OmniVoice instalado" : "Motor ainda não instalado")
                        .font(.system(size: 13, weight: .medium))
                    Text(s.instalado
                         ? "Ocupa \(Self.tamanho(s.tamanhoMotor)) em disco. \(s.servidorLigado ? "Ligado agora: usa cerca de 1 GB de memória até desligar." : "Desligado agora: não usa memória.")"
                         : "Instalar baixa o código do motor, compila neste Mac (cerca de um minuto) e baixa a voz (\(Self.tamanho(MotorOmniVoice.bytesDosPesos))). Precisa de internet só agora.")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            if let linha = s.instalando {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(linha.isEmpty ? "Instalando…" : linha).font(.system(size: 11))
                        .foregroundColor(.secondary).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 0)
                    Button("Cancelar") { s.cancelarInstalacao() }.controlSize(.small)
                }
            } else if !s.instalado {
                if let motivo = MotorOmniVoice.motivoIndisponivel {
                    Text(motivo).font(.system(size: 11)).foregroundColor(.orange)
                } else {
                    Button("Instalar o motor de voz humanizada") { s.instalar() }.buttonStyle(.borderedProminent)
                }
            } else {
                HStack(spacing: 8) {
                    if s.servidorLigado {
                        Button("Desligar agora") { s.desligarServidor() }
                    }
                    Button("Abrir a pasta das vozes") { NSWorkspace.shared.open(MotorOmniVoice.vozes) }
                    Spacer(minLength: 0)
                    if confirmandoRemover {
                        Text("As vozes que você criou ficam.").font(.system(size: 11)).foregroundColor(.secondary)
                        Button("Remover") { s.removerMotor(); confirmandoRemover = false }
                        Button("Cancelar") { confirmandoRemover = false }
                    } else {
                        Button("Remover o motor…") { confirmandoRemover = true }
                    }
                }
                .controlSize(.small)
            }
            Text("Licenças: o programa (omnivoice.cpp) é MIT. O modelo de voz (OmniVoice) é CC BY-NC 4.0: uso pessoal e não comercial — não serve para áudio de propaganda ou de cliente.")
                .font(.system(size: 10.5)).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Vozes

    private var vozes: some View {
        Secao("Vozes humanizadas", s.vozes.isEmpty ? nil : "A voz padrão é a que fala quando ninguém escolhe outra. As sessões podem pedir uma voz pelo nome.") {
            if s.vozes.isEmpty {
                Text("Nenhuma voz guardada ainda. Sem uma, o motor fala com uma voz feminina que pode variar um pouco de uma fala para a outra. Crie a sua abaixo.")
                    .font(.system(size: 12)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(s.vozes) { v in
                HStack(spacing: 8) {
                    Image(systemName: v.origem == .clonada ? "person.wave.2" : "waveform")
                        .foregroundColor(.secondary).frame(width: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(v.nome).font(.system(size: 13, weight: .medium))
                            if v.id == s.vozId {
                                Text("padrão").font(.system(size: 10, weight: .medium))
                                    .padding(.horizontal, 6).padding(.vertical, 1)
                                    .background(Color.accentColor.opacity(0.18))
                                    .clipShape(Capsule())
                            }
                        }
                        Text(v.descricao).font(.system(size: 11)).foregroundColor(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Button("Ouvir") { s.ouvir(v) }.disabled(voz.ocupado)
                    if v.id != s.vozId { Button("Usar como padrão") { s.vozId = v.id } }
                    Button { s.remover(v) } label: { Image(systemName: "trash") }
                        .help("Apagar esta voz")
                }
                .controlSize(.small)
                if v.id != s.vozes.last?.id { Divider() }
            }
        }
    }

    private var novaVoz: some View {
        Secao("Nova voz", "Desenhe uma voz pelos atributos (cada amostra sai diferente: gere até gostar e guarde) ou clone a partir de uma gravação sua.") {
            HStack(spacing: 8) {
                SeletorCrew(selecao: $desenho.genero, opcoes: DesenhoDeVoz.Genero.allCases.map { (valor: $0, titulo: $0.rotulo) })
                SeletorCrew(selecao: $desenho.idade, opcoes: DesenhoDeVoz.Idade.allCases.map { (valor: $0, titulo: $0.rotulo) })
                SeletorCrew(selecao: $desenho.tom, opcoes: DesenhoDeVoz.Tom.allCases.map { (valor: $0, titulo: "Tom " + $0.rotulo.lowercased()) })
                Spacer(minLength: 0)
                if s.gerandoAmostra { ProgressView().controlSize(.small) }
                Button(s.amostra == nil ? "Gerar amostra" : "Gerar outra") { s.gerarAmostra(desenho) }
                    .disabled(s.gerandoAmostra || voz.ocupado)
            }
            if let a = s.amostra {
                HStack(spacing: 8) {
                    Image(systemName: "waveform").foregroundColor(.accentColor)
                    Text("Amostra: \(a.desenho.descricao.lowercased())").font(.system(size: 12))
                    Button("Ouvir de novo") { s.ouvirAmostra() }.controlSize(.small)
                    Spacer(minLength: 0)
                }
                HStack(spacing: 8) {
                    TextField("Nome da voz (ex.: Clara)", text: $nomeNovo).textFieldStyle(.roundedBorder).frame(maxWidth: 220)
                    Button("Guardar esta voz") { s.guardarAmostra(nome: nomeNovo); nomeNovo = "" }
                        .buttonStyle(.borderedProminent)
                        .disabled(nomeNovo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Descartar") { s.descartarAmostra() }
                    Spacer(minLength: 0)
                }
            }
            Divider()
            if let arquivo = clone {
                HStack(spacing: 8) {
                    Image(systemName: "person.wave.2").foregroundColor(.secondary)
                    Text(arquivo.lastPathComponent).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 0)
                    Button("Trocar…") { escolherGravacao() }.controlSize(.small)
                }
                TextField("Nome da voz (ex.: \(Usuario.nome))", text: $nomeClone).textFieldStyle(.roundedBorder).frame(maxWidth: 220)
                TextField("O que é dito na gravação, palavra por palavra", text: $transcricao, axis: .vertical)
                    .lineLimit(2...4).textFieldStyle(.roundedBorder)
                HStack(spacing: 8) {
                    Button("Criar a voz") {
                        s.clonar(nome: nomeClone, arquivo: arquivo, transcricao: transcricao)
                        clone = nil; nomeClone = ""; transcricao = ""
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(s.clonando || nomeClone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || transcricao.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Cancelar") { clone = nil }
                }
            } else {
                HStack(spacing: 8) {
                    Button("Clonar de uma gravação…") { escolherGravacao() }
                    if s.clonando { ProgressView().controlSize(.small) }
                    Text("De 5 a 15 segundos de fala limpa, e o texto exato do que é dito. Só voz sua ou de quem deixou.")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func escolherGravacao() {
        let painel = NSOpenPanel()
        painel.allowedContentTypes = [.audio]
        painel.allowsMultipleSelection = false
        painel.canChooseDirectories = false
        painel.message = "Escolha uma gravação de 5 a 15 segundos"
        painel.prompt = "Escolher"
        if painel.runModal() == .OK { clone = painel.url }
    }

    // MARK: Quando o Crew fala

    private var quandoFala: some View {
        Secao("Quando o Crew fala", "O Crew só fala sozinho no que você ligar aqui. Com o microfone aberto (ditado), ele nunca fala.") {
            Toggle("As sessões do Claude Code podem falar", isOn: $s.sessoesFalam)
                .toggleStyle(.switch).controlSize(.small)
            nota("Ligado, uma sessão pode falar um texto curto quando você pedir (\"me avisa por voz quando terminar\"), pela ferramenta falar do Crew. Desligado, a ferramenta recusa.")
            Toggle("Avisar por voz quando uma sessão precisa de você", isOn: $s.avisarPendencia)
                .toggleStyle(.switch).controlSize(.small)
            nota("Diz o nome do projeto quando uma sessão pede aprovação ou faz uma pergunta. Desligado por padrão. Para ouvir o resultado quando a sessão termina, ligue \"Ler a entrega quando a sessão termina\" nos ajustes abaixo.")
            if s.avisarPendencia, s.humanizadaEmUso {
                Toggle("Aviso na hora, mesmo sem a voz humanizada pronta", isOn: $s.avisoNaHora)
                    .toggleStyle(.switch).controlSize(.small)
                nota("Os avisos das sessões abertas são gerados antes e saem na hora na voz humanizada. Ligado, um aviso que ainda não ficou pronto sai pela voz do macOS em vez de atrasar alguns segundos. Desligado, ele espera a voz humanizada.")
            }
        }
    }

    // MARK: Peças

    private func linhaAviso(_ a: FalaServico.Aviso) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: a.erro ? "exclamationmark.triangle.fill" : "checkmark.circle")
                .foregroundColor(a.erro ? .orange : .secondary)
            Text(a.texto).font(.system(size: a.erro ? 11 : 12, design: a.erro ? .monospaced : .default))
                .foregroundColor(.secondary).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button { s.aviso = nil } label: { Image(systemName: "xmark") }.buttonStyle(.borderless).controlSize(.small)
        }
    }

    private func nota(_ t: String) -> some View {
        Text(t).font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    private static func tamanho(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
