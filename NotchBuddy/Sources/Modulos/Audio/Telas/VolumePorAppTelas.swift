import SwiftUI

// Telas do volume por app: a linha da ilha (ícone, nome, slider, %, mudo), o HUD da ilha fechada
// e as seções da Central (lista completa, ignorados, permissão, atalhos).

/// Slider de volume da ilha: 3/4 do curso até 100 % (marquinha), o resto é reforço até 400 %.
struct SliderVolume: View {
    let volume: Double
    let mudo: Bool
    var desligado = false
    var altura: CGFloat = 4
    /// Na Central (fundo claro/escuro do sistema) em vez da ilha (sempre escura).
    var naCentral = false
    let mudou: (Double) -> Void
    @State private var hover = false
    @State private var arrasto: Double?

    var body: some View {
        GeometryReader { g in
            let pos = arrasto ?? EscalaVolume.posicao(volume)
            let ativo = (hover || arrasto != nil) && !desligado
            ZStack(alignment: .leading) {
                Capsule().fill(naCentral ? Color.secondary.opacity(0.25) : Color.white.opacity(0.10)).frame(height: ativo ? altura + 1 : altura)
                Capsule().fill(cor(pos))
                    .frame(width: max(0, g.size.width * pos), height: ativo ? altura + 1 : altura)
                // 100 %
                Rectangle().fill(naCentral ? Color.secondary.opacity(0.6) : Color.white.opacity(0.35))
                    .frame(width: 1, height: altura + 5)
                    .offset(x: g.size.width * EscalaVolume.marcaCem)
                if ativo {
                    Circle().fill(naCentral ? Color.accentColor : Color.white).frame(width: 10, height: 10)
                        .offset(x: g.size.width * pos - 5)
                }
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        guard !desligado else { return }
                        let p = min(max(0, v.location.x / g.size.width), 1)
                        arrasto = EscalaVolume.posicao(EscalaVolume.volume(p))
                        mudou(EscalaVolume.volume(p))
                    }
                    .onEnded { _ in arrasto = nil }
            )
            .onHover { hover = $0 }
        }
        .opacity(desligado ? 0.35 : mudo ? 0.45 : 1)
        .animation(.easeOut(duration: 0.12), value: hover)
    }

    private func cor(_ pos: Double) -> Color {
        if pos > EscalaVolume.marcaCem + 0.002 { return Color(hex: "#F5A524") }
        return naCentral ? Color.accentColor : Color(hex: "#E8E9EC")
    }
}

enum TextoVolume {
    static func pct(_ a: AjusteApp) -> String { "\(Int((a.volume * 100).rounded()))%" }
}

/// Uma linha da aba da ilha.
struct LinhaVolumeApp: View {
    let app: AppAudio
    private let s = VolumePorApp.shared
    @State private var escolhendoSaida = false

    var body: some View {
        let a = s.ajuste(app.id)
        HStack(spacing: 8) {
            Image(nsImage: s.icone(app.id)).resizable().frame(width: 18, height: 18)
                .opacity(app.tocando ? 1 : 0.5)
            Text(app.nome)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(Color(hex: app.tocando ? "#E8E9EC" : "#8E939C"))
                .lineLimit(1).truncationMode(.tail)
                .frame(width: 96, alignment: .leading)
            BotaoSaidaApp(bundle: app.id, aberto: escolhendoSaida) { escolhendoSaida.toggle() }
            if escolhendoSaida {
                // Fileira de saídas no lugar do slider: um clique escolhe e fecha.
                SeletorSaidaApp(bundle: app.id) { escolhendoSaida = false }
            } else {
                linhaVolume(a)
            }
        }
        .help(ajudaEstado)
    }

    @ViewBuilder private func linhaVolume(_ a: AjusteApp) -> some View {
            SliderVolume(volume: a.volume, mudo: a.mudo) { s.definirVolume(app.id, $0) }
                .frame(height: 16)
            Text(a.mudo ? "mudo" : TextoVolume.pct(a))
                .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                .foregroundColor(Color(hex: a.volume > 1 && !a.mudo ? "#F5A524" : "#8E939C"))
                .frame(width: 38, alignment: .trailing)
            Button { s.alternarMudo(app.id) } label: {
                Image(systemName: a.mudo ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 10.5))
                    .foregroundColor(Color(hex: a.mudo ? "#F4505E" : "#8E939C"))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(a.mudo ? "Tirar do mudo" : "Deixar mudo")
    }

    private var ajudaEstado: String {
        switch s.estados[app.id] {
        case .falhou(let m)?: "Não deu para ajustar: \(m). O app segue com o som normal."
        case .semPermissao?: "Falta a permissão de Gravação de Áudio do Sistema."
        default: app.nome
        }
    }
}

/// Ícone redondo da saída de um app (o mesmo desenho das colunas de dispositivos). Seguindo a
/// padrão: contorno tracejado discreto. Saída fixa: preenchido. Fixa desconectada (tocando na
/// padrão por enquanto): contorno laranja.
struct BotaoSaidaApp: View {
    let bundle: String
    var aberto = false
    let acao: () -> Void
    private let v = VolumePorApp.shared
    private let a = AudioServico.shared

    var body: some View {
        let fixa = v.ajuste(bundle).saidaUID
        let reserva = v.naReserva.contains(bundle)
        let d = fixa.flatMap { u in a.saidas.first { $0.uid == u } } ?? a.saidaAtual
        Button(action: acao) {
            Image(systemName: aberto ? "xmark" : (d?.icone(entrada: false) ?? "speaker.wave.2"))
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundColor(fixa != nil && !reserva ? Color(hex: "#0B0C0E") : Color(hex: "#DADDE2"))
                .frame(width: 22, height: 22)
                .background(Circle().fill(fixa != nil && !reserva ? Color(hex: "#F5F6F8") : Color.white.opacity(0.09)))
                .overlay(Circle().strokeBorder(reserva ? Color(hex: "#F5A524")
                                               : Color.white.opacity(fixa == nil ? 0.28 : 0),
                                               style: StrokeStyle(lineWidth: 1, dash: fixa == nil ? [2, 2] : [])))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(ajuda(fixa: fixa, reserva: reserva, d: d))
    }

    private func ajuda(fixa: String?, reserva: Bool, d: DispositivoAudio?) -> String {
        let nome = d.map { ColunaDispositivos.nomeCurto($0.nome) } ?? "?"
        if reserva { return "A saída escolhida desconectou: tocando em \(nome) até ela voltar. Clique para escolher." }
        return fixa == nil ? "Segue a saída padrão (\(nome)). Clique para escolher outra." : "Sempre em \(nome). Clique para escolher."
    }
}

/// A fileira inline de saídas de um app: "Padrão" e cada saída conectada.
struct SeletorSaidaApp: View {
    let bundle: String
    let fechar: () -> Void
    private let v = VolumePorApp.shared
    private let a = AudioServico.shared
    @State private var sobre: String?

    var body: some View {
        let fixa = v.ajuste(bundle).saidaUID
        HStack(spacing: 6) {
            opcao(id: "", icone: "arrow.triangle.branch", nome: "Seguir a padrão", ativo: fixa == nil) {
                v.definirSaida(bundle, nil)
            }
            ForEach(a.saidas) { d in
                opcao(id: d.uid, icone: d.icone(entrada: false), nome: ColunaDispositivos.nomeCurto(d.nome),
                      ativo: fixa == d.uid) { v.definirSaida(bundle, d.uid) }
            }
            Text(legenda(fixa))
                .font(.system(size: 10.5, weight: .medium))
                .foregroundColor(Color(hex: "#9398A1"))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private func legenda(_ fixa: String?) -> String {
        if let s = sobre { return s.isEmpty ? "Seguir a padrão" : a.saidas.first { $0.uid == s }.map { ColunaDispositivos.nomeCurto($0.nome) } ?? "" }
        if let fixa, let d = a.saidas.first(where: { $0.uid == fixa }) { return ColunaDispositivos.nomeCurto(d.nome) }
        return fixa == nil ? "Segue a padrão" : "Desconectada"
    }

    private func opcao(id: String, icone: String, nome: String, ativo: Bool, acao: @escaping () -> Void) -> some View {
        Button { acao(); fechar() } label: {
            Image(systemName: icone)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundColor(ativo ? Color(hex: "#0B0C0E") : Color(hex: "#DADDE2"))
                .frame(width: 22, height: 22)
                .background(Circle().fill(ativo ? Color(hex: "#F5F6F8") : Color.white.opacity(sobre == id ? 0.16 : 0.09)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(nome)
        .onHover { sobre = $0 ? id : (sobre == id ? nil : sobre) }
    }
}

/// Aviso na barra: app trocou de saída porque a dele desconectou (ou voltou).
struct AvisoSaidaApp: View {
    let icone: NSImage
    let texto: String
    let cor: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: icone).resizable().frame(width: 16, height: 16)
            Circle().fill(cor).frame(width: 6, height: 6)
            Text(texto).font(.system(size: 12, weight: .medium)).foregroundColor(Color(hex: "#DADDE2"))
                .lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
    }
}

/// Os apps da aba da ilha (até 3), ou o aviso do que falta.
struct VolumeAppsIlha: View {
    private let s = VolumePorApp.shared

    var body: some View {
        let lista = linhas
        VStack(alignment: .leading, spacing: 6) {
            if lista.isEmpty {
                Text("Nenhum app tocando agora")
                    .font(.system(size: 12, weight: .medium)).foregroundColor(Color(hex: "#8E939C"))
                Text("Quando algum app tocar, o volume dele aparece aqui.")
                    .font(.system(size: 10.5)).foregroundColor(Color(hex: "#5F646D"))
            }
            ForEach(lista.prefix(3)) { app in LinhaVolumeApp(app: app) }
            if let aviso { aviso }
        }
    }

    /// Tocando (fora os ignorados) primeiro; depois os ajustados que estão abertos.
    private var linhas: [AppAudio] {
        let ok = s.apps.filter { !s.ignorado($0.id) }
        return ok.filter(\.tocando) + ok.filter { !$0.tocando && s.ajustes[$0.id] != nil }
    }

    private var aviso: AnyView? {
        let n = linhas.count
        let texto: String
        switch s.permissao {
        case .negada: texto = "Sem permissão de Gravação de Áudio do Sistema: volume por app desligado"
        case .naoPerguntada where n < 3: texto = "Na 1ª vez, o macOS pede “Gravação de Áudio do Sistema”. O Crew não grava nada."
        default:
            guard n > 3 else { return nil }
            return AnyView(Button { Central.abrir(modulo: AudioModulo.shared.id) } label: {
                Text("+\(n - 3) nos Ajustes").font(.system(size: 10.5)).foregroundColor(Color(hex: "#8E939C"))
            }.buttonStyle(.plain))
        }
        return AnyView(Text(texto).font(.system(size: 10)).foregroundColor(Color(hex: "#8E939C")).lineLimit(1)
            .minimumScaleFactor(0.85))
    }
}

/// HUD na ilha fechada: ícone do app, barra e %.
struct HUDVolumeApp: View {
    let icone: NSImage
    let nome: String
    let volume: Double
    let mudo: Bool

    var body: some View {
        let pos = mudo ? 0 : EscalaVolume.posicao(volume)
        HStack(spacing: 10) {
            Image(nsImage: icone).resizable().frame(width: 18, height: 18)
                .help(nome)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.14))
                    Capsule().fill(volume > 1 && !mudo ? Color(hex: "#F5A524") : Color.white)
                        .frame(width: max(6, g.size.width * pos))
                    Rectangle().fill(Color.white.opacity(0.4)).frame(width: 1, height: 10)
                        .offset(x: g.size.width * EscalaVolume.marcaCem)
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 6)
            .animation(.spring(response: 0.25, dampingFraction: 0.85), value: pos)
            if mudo {
                Image(systemName: "speaker.slash.fill").font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: "#F4505E")).frame(width: 34, alignment: .trailing)
            } else {
                Text("\(Int((volume * 100).rounded()))")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundColor(Color(hex: volume > 1 ? "#F5A524" : "#8E939C"))
                    .frame(width: 34, alignment: .trailing)
            }
        }
    }
}

// MARK: - Central

struct VolumePorAppCentral: View {
    private let s = VolumePorApp.shared

    var body: some View {
        Secao("Volume e saída por app", "Arraste para mudar o volume de um app só (até 400%) e escolha por onde ele sai (ex.: Spotify nos AirPods, Arc no Mac). 100%, sem mudo e saída padrão devolve o app ao som normal do macOS. O ajuste fica guardado e volta quando o app tocar de novo; se a saída escolhida desconectar, o app toca na padrão até ela voltar.") {
            permissao
            let todos = lista
            if todos.isEmpty {
                Text("Nenhum app com áudio aberto agora.").font(.system(size: 12)).foregroundColor(.secondary)
            }
            ForEach(todos, id: \.self) { b in linha(b) }
        }
    }

    /// Apps com áudio aberto + os que têm ajuste guardado (mesmo fechados).
    private var lista: [String] {
        var ids = s.apps.map(\.id)
        for b in s.ajustes.keys.sorted() where !ids.contains(b) { ids.append(b) }
        return ids
    }

    @ViewBuilder private var permissao: some View {
        switch s.permissao {
        case .concedida:
            Label("Permissão de Gravação de Áudio do Sistema concedida", systemImage: "checkmark.circle.fill")
                .font(.system(size: 11)).foregroundColor(.secondary)
        case .negada:
            HStack(spacing: 8) {
                Label("Sem permissão de Gravação de Áudio do Sistema — o volume por app fica desligado e os apps tocam normal.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11)).foregroundColor(.orange)
                Button("Abrir Ajustes") { NSWorkspace.shared.open(PermissaoCaptura.urlAjustes) }.controlSize(.small)
            }
        case .naoPerguntada, .desconhecida:
            Text("Na primeira vez que você mudar o volume de um app, o macOS pede “Gravação de Áudio do Sistema”. É o que deixa o Crew pegar o som do app, mudar o volume e tocar de volta — nada é gravado nem sai do Mac.")
                .font(.system(size: 11)).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func linha(_ b: String) -> some View {
        let a = s.ajuste(b)
        let app = s.apps.first { $0.id == b }
        let ign = s.ignorado(b)
        return HStack(spacing: 10) {
            Image(nsImage: s.icone(b)).resizable().frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(s.nome(b)).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                Text(estado(b, app: app, ign: ign)).font(.system(size: 10.5)).foregroundColor(.secondary).lineLimit(1)
            }
            .frame(width: 170, alignment: .leading)
            seletorSaida(b, a: a, ign: ign)
            SliderVolume(volume: a.volume, mudo: a.mudo, desligado: ign, naCentral: true) { s.definirVolume(b, $0) }
                .frame(height: 16)
            Text(a.mudo ? "mudo" : TextoVolume.pct(a))
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundColor(a.volume > 1 && !a.mudo ? .orange : .secondary)
                .frame(width: 40, alignment: .trailing)
            Button { s.alternarMudo(b) } label: {
                Image(systemName: a.mudo ? "speaker.slash.fill" : "speaker.wave.2")
                    .foregroundColor(a.mudo ? .red : .secondary).frame(width: 18)
            }
            .buttonStyle(.plain).disabled(ign).help(a.mudo ? "Tirar do mudo" : "Deixar mudo")
            Button { s.restaurar(b) } label: { Image(systemName: "arrow.uturn.backward").frame(width: 18) }
                .buttonStyle(.plain).foregroundColor(.secondary)
                .disabled(a.neutro).opacity(a.neutro ? 0.3 : 1)
                .help("Voltar ao normal (100%, sem mudo)")
            Button { s.ignorar(b, !ign) } label: {
                Image(systemName: ign ? "eye.slash" : "eye").frame(width: 18)
            }
            .buttonStyle(.plain).foregroundColor(ign ? .orange : .secondary)
            .help(ign ? "Ignorado: o Crew não mexe neste app. Clique para voltar a controlar." : "Ignorar este app (o Crew não mexe no som dele)")
        }
        .padding(.vertical, 3)
    }

    /// Coluna "Saída": seguir a padrão ou um dispositivo fixo (a fixa desconectada continua na
    /// lista, marcada, para não perder a escolha).
    private func seletorSaida(_ b: String, a: AjusteApp, ign: Bool) -> some View {
        let audio = AudioServico.shared
        let padrao = audio.saidaAtual.map { ColunaDispositivos.nomeCurto($0.nome) } ?? "—"
        var opcoes: [(valor: String, titulo: String)] = [(valor: "", titulo: "Padrão (\(padrao))")]
        opcoes += audio.saidas.map { (valor: $0.uid, titulo: ColunaDispositivos.nomeCurto($0.nome)) }
        if let u = a.saidaUID, !audio.saidas.contains(where: { $0.uid == u }) {
            opcoes.append((valor: u, titulo: "Escolhida (desconectada)"))
        }
        return SeletorCrew(selecao: Binding(get: { a.saidaUID ?? "" }, set: { s.definirSaida(b, $0.isEmpty ? nil : $0) }),
                           opcoes: opcoes, largura: 150)
        .disabled(ign)
        .help("Saída deste app. Se a escolhida desconectar, ele toca na padrão até ela voltar.")
    }

    private func estado(_ b: String, app: AppAudio?, ign: Bool) -> String {
        if ign { return "ignorado — o Crew não mexe no som" }
        var partes: [String] = []
        if let app { partes.append(app.tocando ? "tocando" : "aberto, sem tocar") } else { partes.append("fechado") }
        switch s.estados[b] {
        case .ativo?: partes.append(s.naReserva.contains(b) ? "saída desconectada: na padrão" : "ajuste ligado")
        case .montando?: partes.append("ligando…")
        case .esperando?: partes.append("volta ao tocar")
        case .falhou(let m)?: partes.append("não ajustou: \(m)")
        case .semPermissao?: partes.append("sem permissão")
        case .ignorado?, nil: break
        }
        return partes.joined(separator: " · ")
    }
}

/// Ignorados e atalhos (nos ajustes do módulo).
struct VolumePorAppAjustes: View {
    @Bindable private var s = VolumePorApp.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider().padding(.vertical, 2)
            Text("Volume por app").font(.system(size: 12, weight: .semibold))
            Toggle("Atalhos do app tocando agora", isOn: $s.atalhosLigados)
                .toggleStyle(.switch).controlSize(.small)
            VStack(alignment: .leading, spacing: 3) {
                ForEach(AtalhosVolume.Acao.allCases, id: \.self) { a in
                    HStack(spacing: 6) {
                        Text(a.rotulo).font(.system(size: 11).monospaced())
                        if s.atalhosRecusados.contains(a) {
                            Text("outro app já usa esta combinação").font(.system(size: 10.5)).foregroundColor(.orange)
                        }
                    }
                }
                Text("O app é o da frente, se estiver tocando; senão o último que você mexeu; senão o primeiro tocando. A ilha mostra o volume dele.")
                    .font(.system(size: 11)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .opacity(s.atalhosLigados ? 1 : 0.5)

            Text("Ignorados").font(.system(size: 12, weight: .medium)).padding(.top, 4)
            Text("O Crew não mexe no som destes apps. Apps de chamada vêm ignorados: o ajuste por app quebra o cancelamento de eco (o outro lado ouve a própria voz).")
                .font(.system(size: 11)).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(s.ignorados, id: \.self) { b in
                HStack(spacing: 8) {
                    Image(nsImage: s.icone(b)).resizable().frame(width: 16, height: 16)
                    Text(s.nome(b)).font(.system(size: 12))
                    Text(NSWorkspace.shared.urlForApplication(withBundleIdentifier: b) == nil ? "não instalado" : b)
                        .font(.system(size: 10.5)).foregroundColor(.secondary)
                    Spacer()
                    Button("Tirar") { s.ignorar(b, false) }.controlSize(.small)
                }
            }
            let candidatos = s.apps.filter { !s.ignorado($0.id) }
            if !candidatos.isEmpty {
                BotaoMenu(itens: {
                    candidatos.map { a in ItemMenu.acao(a.nome) { s.ignorar(a.id, true) } }
                }) {
                    // Mesma cara de botão pequeno que o menu do sistema tinha
                    HStack(spacing: 6) {
                        Text("Ignorar um app aberto…").font(.system(size: 11))
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 20)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.primary.opacity(0.1)))
                    .contentShape(RoundedRectangle(cornerRadius: 5))
                }
                .fixedSize()
            }
            Button("Voltar à lista padrão") { s.ignorados = IgnoradosPadrao.bundles }
                .controlSize(.small)
                .disabled(s.ignorados == IgnoradosPadrao.bundles)
        }
    }
}
