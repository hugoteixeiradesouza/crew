import SwiftUI

// Página da Voz na Central: permissões (com o porquê antes do pedido), caixa para testar o
// ditado e teste da leitura em voz alta. Os ajustes ficam em `VozAjustes`, logo abaixo.

struct VozCentral: View {
    private let s = VozServico.shared
    @State private var rascunho = ""
    @State private var amostra = "Terminei a **migração**. Rodei os testes com `swift test` e os 42 passaram; o resumo está em [docs/ARQUITETURA.md](docs/ARQUITETURA.md)."

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Secao("Permissões", "O ditado precisa das duas. O Crew só ouve enquanto você dita, transforma a fala em texto neste Mac e não grava nada. Ler em voz alta não pede permissão.") {
                linhaPermissao("mic", "Microfone", s.microfone, PermissaoVoz.urlMicrofone)
                linhaPermissao("waveform", "Reconhecimento de Fala", s.fala, PermissaoVoz.urlFala)
                if s.permissao == .naoPerguntada {
                    HStack(spacing: 8) {
                        Button("Permitir…") { Task { await s.pedirPermissoes() } }
                        Text("O macOS mostra os dois pedidos, um depois do outro.")
                            .font(.system(size: 11)).foregroundColor(.secondary)
                    }
                }
                Divider()
                linhaNoMac
            }

            Secao("Testar o ditado", "Clique no microfone, fale e clique de novo. O texto entra no fim da caixa.") {
                HStack(alignment: .top, spacing: 8) {
                    TextField("O que você disser aparece aqui…", text: $rascunho, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .lineLimit(3...8)
                        .padding(8)
                        .background(Color.primary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    VStack(spacing: 6) {
                        BotaoDitar(texto: $rascunho)
                        BotaoOuvir(texto: rascunho)
                    }
                }
                HStack(spacing: 8) {
                    MedidorVoz(nivel: s.ouvindo ? s.nivel : 0, cor: s.ouvindo ? .red : .secondary)
                        .frame(width: 22, height: 14)
                    Text(estado).font(.system(size: 11)).foregroundColor(corEstado)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    if !rascunho.isEmpty {
                        Button("Limpar") { rascunho = "" }.controlSize(.small)
                    }
                }
            }

            Secao("Ler em voz alta", "A voz lê sem o markdown: bloco de código vira \"trecho de código\" e link é lido pelo texto.") {
                TextField("Texto para ler", text: $amostra, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .lineLimit(2...6)
                    .padding(8)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                HStack(spacing: 8) {
                    Button {
                        if s.falando { s.parar() } else { s.falar(amostra) }
                    } label: {
                        Label(s.falando ? "Parar" : "Ouvir", systemImage: s.falando ? "stop.fill" : "play.fill")
                    }
                    .disabled(s.ocupado)
                    Text("Vai ser lido: \(TextoFalavel.limpar(amostra))")
                        .font(.system(size: 11)).foregroundColor(.secondary).lineLimit(2)
                }
            }

            // A voz do computador: motor de fala, vozes humanizadas e quando o Crew fala (Fala/Telas)
            FalaCentral()
        }
        .onAppear { s.atualizarPermissoes() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            s.atualizarPermissoes()   // voltou dos Ajustes do Sistema
        }
    }

    private func linhaPermissao(_ icone: String, _ nome: String, _ p: PermissaoVoz, _ url: URL) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icone).font(.system(size: 13)).foregroundColor(.secondary).frame(width: 20)
            Text(nome).font(.system(size: 12, weight: .medium))
            Spacer()
            switch p {
            case .concedida:
                Label("Permitido", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12)).foregroundColor(.green)
            case .negada:
                Label("Negado", systemImage: "xmark.circle.fill")
                    .font(.system(size: 12)).foregroundColor(.orange)
                Button("Abrir Ajustes do Sistema") { NSWorkspace.shared.open(url) }.controlSize(.small)
            case .naoPerguntada:
                Text("Ainda não pedido").font(.system(size: 12)).foregroundColor(.secondary)
            }
        }
    }

    private var linhaNoMac: some View {
        let noMac = s.reconheceNoMac()
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: noMac == true ? "lock.laptopcomputer" : "exclamationmark.triangle")
                .font(.system(size: 13)).foregroundColor(noMac == true ? .secondary : .orange).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                switch noMac {
                case true?:
                    Text("Reconhecimento de \(s.idioma) feito neste Mac").font(.system(size: 12, weight: .medium))
                    Text("O áudio não sai do Mac.").font(.system(size: 11)).foregroundColor(.secondary)
                case false?:
                    Text("Este Mac não reconhece \(s.idioma) sem rede").font(.system(size: 12, weight: .medium))
                    Text(s.permitirRede
                         ? "Você permitiu o reconhecimento pela Apple: enquanto dita, o áudio vai para os servidores dela."
                         : "O ditado fica parado até você baixar o idioma (Ajustes do Sistema › Teclado › Ditado) ou permitir o reconhecimento pela Apple nos ajustes abaixo. O Crew não manda áudio para a rede sem isso.")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                case nil:
                    Text("O macOS não tem reconhecimento de fala para \(s.idioma)").font(.system(size: 12, weight: .medium))
                }
            }
        }
    }

    private var estado: String {
        switch s.estado {
        case .parado: s.textoFinal.isEmpty ? "Parado. Nada ligado: nem microfone, nem reconhecedor." : "Parado. Último ditado: \(s.textoFinal.count) caracteres."
        case .pedindoPermissao: "Esperando a sua resposta ao pedido do macOS…"
        case .ouvindo: "Ouvindo…"
        case .finalizando: "Fechando o texto…"
        case .erro(let m): m
        }
    }

    private var corEstado: Color {
        switch s.estado {
        case .erro: .orange
        case .ouvindo: .red
        default: .secondary
        }
    }
}

/// Ajustes da Voz: idioma e rede do ditado, segurar para falar, voz e velocidade da leitura.
struct VozAjustes: View {
    @Bindable private var s = VozServico.shared
    @State private var idiomas: [(id: String, nome: String)] = []
    @State private var vozes: [VozServico.VozInstalada] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            titulo("Ditado")
            HStack(spacing: 8) {
                Text("Idioma").font(.system(size: 12))
                SeletorCrew(selecao: $s.idioma,
                            opcoes: idiomas.map { (valor: $0.id, titulo: "\($0.nome) (\($0.id))") }
                                + (idiomas.contains(where: { $0.id == s.idioma }) ? [] : [(valor: s.idioma, titulo: s.idioma)]))
                    .frame(maxWidth: 300, alignment: .leading)
            }
            Toggle("Permitir reconhecimento pela Apple (rede)", isOn: $s.permitirRede)
                .toggleStyle(.switch).controlSize(.small)
            nota("Desligado, o ditado só funciona quando o Mac reconhece o idioma sozinho. Ligado, vale apenas para idioma que o Mac não reconhece sem rede: aí o áudio do ditado vai para a Apple. Idioma reconhecido no Mac continua no Mac.")

            Divider()
            titulo("Formatar o que você fala")
            HStack(spacing: 8) {
                Text("Texto").font(.system(size: 12))
                SeletorCrew(selecao: $s.lapidacao,
                            opcoes: VozServico.Lapidacao.allCases.map { (valor: $0, titulo: $0.rotulo) })
                    .frame(maxWidth: 320, alignment: .leading)
            }
            if !IAdoMac.disponivel && s.lapidacao != .literal {
                Label("O modelo local do Mac (Apple Intelligence) não está disponível: valem o dicionário, as muletas e as correções, sem pontuação nem lista.", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11)).foregroundColor(.orange)
            }
            nota("Vale para o segurar para falar (Fn e atalho). Literal entrega o texto como o macOS transcreveu. Nos outros dois, o Crew aplica o seu dicionário, tira muletas (\"né\", \"hã\", \"tipo assim\") e fica com a versão final quando você se corrige com número, horário ou \"aliás\", \"quer dizer\", \"não, pera\": isso é regra fixa, não depende de modelo. O modelo local do Mac só empresta pontuação, maiúsculas e, no modo formatar, a quebra em lista. As palavras são sempre as suas: se a resposta dele troca, corta, inventa ou responde ao que você falou, ela é descartada e o texto sai sem a pontuação dele. Nada sai do Mac.")
            nota("Medido em 2026-11-13 com falas digitadas, ainda não com o microfone: 15 de 17 falas novas certas na régua dura (o método anterior acertava 4). Espera ao soltar a tecla: cerca de 1 s; 3 a 5 s em fala de um minuto. O que ainda erra: enumeração sem deixa (\"o seguinte\", \"primeiro, segundo\") fica em frase corrida, fala longa leva ponto ou vírgula fora do lugar, e quando ele mexe nas suas palavras o texto sai cru, sem pontuação. O padrão continua Literal até você testar falando.")
            HStack(alignment: .top, spacing: 8) {
                Text("Seu dicionário").font(.system(size: 12)).padding(.top, 4)
                TextField("cru -> Crew; romi, rômi -> Homie; uórquitri -> worktree; Itapeva", text: $s.vocabulario, axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(2...8).font(.system(size: 12))
            }
            nota("Como o Mac escreve o que você fala -> como deve sair. Entradas separadas por ponto e vírgula (ou uma por linha, com ⌥Return); várias formas faladas da mesma palavra, por vírgula. Entrada sem seta só acerta a maiúscula (Itapeva). A troca é feita pelo Crew, sempre, sem modelo. Cuidado com palavra comum: \"cru -> Crew\" também troca em \"peixe cru\" (só escapa depois de \"tava\", \"é\", \"muito\").")

            Divider()
            titulo("Segurar para falar")
            HStack(spacing: 8) {
                Toggle("Atalho global", isOn: $s.atalhoLigado)
                    .toggleStyle(.switch).controlSize(.small)
                SeletorCrew(selecao: $s.combinacao,
                            opcoes: AtalhoFalar.Combinacao.allCases.map { (valor: $0, titulo: $0.rotulo) },
                            largura: 140)
                    .disabled(!s.atalhoLigado)
            }
            if s.atalhoRecusado {
                Label("O macOS recusou essa combinação (outro app usa). Escolha outra.", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11)).foregroundColor(.orange)
            }
            nota("Segure a combinação em qualquer app e fale; ao soltar, o texto aparece na ilha e é colado ou copiado (ajuste abaixo). O macOS só avisa o Crew dessa combinação exata; nada mais do teclado é lido.")
            Toggle("Segurar a tecla Fn (Globo)", isOn: $s.teclaFnLigada)
                .toggleStyle(.switch).controlSize(.small)
            nota("Segure Fn em qualquer app e fale; ao soltar, o texto entra onde o cursor está. Fn com outra tecla (Fn+seta, Fn+F5) ou um toque rápido não começa ditado. Para isso o Crew escuta só a tecla Fn e o fato de outra tecla ter sido apertada junto: nada do que você digita é lido nem guardado. Usa a permissão de Acessibilidade.")
            if s.fnSemPermissao {
                HStack(spacing: 8) {
                    Label("Falta a permissão de Acessibilidade para escutar a tecla Fn.", systemImage: "exclamationmark.triangle")
                        .font(.system(size: 11)).foregroundColor(.orange)
                    Button("Abrir no macOS") {
                        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(u)
                        }
                    }.controlSize(.small)
                    Button("Tentar de novo") { s.tentarTeclaFn() }.controlSize(.small)
                }
            }
            if s.teclaFnLigada, AcaoDoGlobo.livre == false {
                HStack(spacing: 8) {
                    Label("O macOS também faz algo quando você aperta Fn (emoji, trocar teclado ou o ditado dele). Em Teclado, ponha \"Pressionar a tecla Globo\" em \"Não fazer nada\".",
                          systemImage: "exclamationmark.triangle")
                        .font(.system(size: 11)).foregroundColor(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Abrir Teclado") { AcaoDoGlobo.abrirAjustesDoTeclado() }.controlSize(.small)
                }
            }
            Toggle("Colar no app em foco ao soltar", isOn: $s.colarNoApp)
                .toggleStyle(.switch).controlSize(.small).disabled(!s.atalhoLigado && !s.teclaFnLigada)
            nota("Ligado, o texto é colado onde o cursor está e a área de transferência volta ao que tinha antes. Em campo de senha, ou sem Acessibilidade, o texto só fica copiado e a ilha avisa. Desligado, o texto só é copiado.")
            Toggle("Mandar para a sessão em foco", isOn: $s.mandarParaSessao)
                .toggleStyle(.switch).controlSize(.small).disabled(!s.atalhoLigado && !s.teclaFnLigada)
            nota("Ligado, o que você falar segurando o atalho é enviado como pedido à sessão do Claude Code em foco na ilha (e fica copiado), no lugar de ser colado. Sessão pedindo permissão ou perguntando algo nunca recebe: o texto só fica copiado.")

            Divider()
            titulo("Ler em voz alta")
            HStack(spacing: 8) {
                Text("Voz").font(.system(size: 12))
                SeletorCrew(selecao: Binding(get: { s.vozId ?? "" }, set: { s.vozId = $0.isEmpty ? nil : $0 }),
                            opcoes: [(valor: "", titulo: "Padrão do macOS")] + vozes.map { (valor: $0.id, titulo: $0.nome) })
                    .frame(maxWidth: 260, alignment: .leading)
                Button("Testar") { s.falar("Oi, eu sou a voz do Crew.") }.controlSize(.small)
            }
            HStack(spacing: 8) {
                Text("Velocidade").font(.system(size: 12))
                Image(systemName: "tortoise").font(.system(size: 11)).foregroundColor(.secondary)
                Slider(value: $s.velocidade, in: VozServico.velocidades).frame(width: 180)
                Image(systemName: "hare").font(.system(size: 11)).foregroundColor(.secondary)
            }
            nota("Vozes melhores (aprimorada, premium) se baixam em Ajustes do Sistema › Acessibilidade › Conteúdo Falado › Voz do Sistema.")
            Toggle("Ler a entrega quando a sessão termina", isOn: $s.lerEntrega)
                .toggleStyle(.switch).controlSize(.small)
            nota("Só o primeiro parágrafo da resposta, sem markdown. Por evento das sessões: nada fica rodando à espera.")
        }
        .onAppear {
            if idiomas.isEmpty { idiomas = s.idiomas() }
            if vozes.isEmpty { vozes = s.vozes() }
        }
    }

    private func titulo(_ t: String) -> some View {
        Text(t).font(.system(size: 12, weight: .semibold))
    }

    private func nota(_ t: String) -> some View {
        Text(t).font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}
