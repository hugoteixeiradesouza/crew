import SwiftUI
import AppKit

// Monitor de atividade: todos os processos do Mac, em cinco abas como o do macOS (CPU,
// Memória, Energia, Disco, Rede). Uma tela só, usada na ilha expandida (escura, compacta) e na
// página do Sistema na Central. Lê só enquanto está na tela (parte `.monitor` do serviço).

enum AbaMonitor: String, CaseIterable, Identifiable {
    case cpu = "CPU", memoria = "Memória", energia = "Energia", disco = "Disco", rede = "Rede"
    var id: String { rawValue }

    var colunas: [ColunaMonitor] {
        switch self {
        case .cpu:     return [.cpu, .tempo, .threads, .despertares]
        case .memoria: return [.memoria, .residente, .threads]
        case .energia: return [.energia, .cpu, .despertares, .repouso]
        case .disco:   return [.escritosSeg, .lidosSeg, .escritos, .lidos]
        case .rede:    return [.conexoes, .cpu]
        }
    }
}

enum ColunaMonitor: String, Identifiable {
    case nome, cpu, tempo, threads, despertares, memoria, residente, energia, repouso
    case escritosSeg, lidosSeg, escritos, lidos, conexoes
    var id: String { rawValue }

    var titulo: String {
        switch self {
        case .nome: return "Processo"
        case .cpu: return "% CPU"
        case .tempo: return "Tempo"
        case .threads: return "Threads"
        case .despertares: return "Despert."
        case .memoria: return "Memória"
        case .residente: return "Residente"
        case .energia: return "Energia"
        case .repouso: return "Repouso"
        case .escritosSeg: return "Escrita/s"
        case .lidosSeg: return "Leitura/s"
        case .escritos: return "Escritos"
        case .lidos: return "Lidos"
        case .conexoes: return "Sockets"
        }
    }

    var ajuda: String {
        switch self {
        case .nome: return "Nome do app ou do processo"
        case .cpu: return "Uso de CPU nos últimos 2 s (100 % = um núcleo inteiro)"
        case .tempo: return "Tempo de CPU somado desde que o processo abriu"
        case .threads: return "Linhas de execução do processo"
        case .despertares: return "Vezes por segundo que o processo acorda a CPU"
        case .memoria: return "Memória que o processo ocupa (pegada física; nos do sistema, a residente)"
        case .residente: return "Memória residente na RAM agora"
        case .energia: return "Energia gasta nos últimos 2 s, estimativa do próprio macOS (mW)"
        case .repouso: return "Pediu ao macOS para o Mac ou a tela não dormirem"
        case .escritosSeg: return "Bytes gravados no disco por segundo"
        case .lidosSeg: return "Bytes lidos do disco por segundo"
        case .escritos: return "Bytes gravados desde que o processo abriu"
        case .lidos: return "Bytes lidos desde que o processo abriu"
        case .conexoes: return "Conexões de rede (sockets) abertas agora"
        }
    }

    var largura: CGFloat {
        switch self {
        case .nome: return 0
        case .repouso: return 70
        case .threads, .cpu, .despertares, .conexoes: return 60
        default: return 74
        }
    }

    /// Valor para ordenar (nil = sem leitura, fica no fim).
    func valor(_ p: ProcessoMonitor) -> Double? {
        switch self {
        case .nome: return nil
        case .cpu: return p.tempoCPU == nil ? nil : p.cpu
        case .tempo: return p.tempoCPU
        case .threads: return p.threads.map { Double($0) }
        case .despertares: return p.despertares
        case .memoria: return p.memoria.map { Double($0) }
        case .residente: return p.residente.map { Double($0) }
        case .energia: return p.energia
        case .repouso: return p.impedeRepouso ? 1 : 0
        case .escritosSeg: return p.escritosSeg
        case .lidosSeg: return p.lidosSeg
        case .escritos: return p.escritos.map { Double($0) }
        case .lidos: return p.lidos.map { Double($0) }
        case .conexoes: return p.conexoes.map { Double($0) }
        }
    }

    func texto(_ p: ProcessoMonitor) -> String {
        guard let v = valor(p) else { return "—" }
        switch self {
        case .nome: return ""
        case .cpu: return String(format: v < 0.1 && v > 0 ? "%.1f" : "%.0f", v * 100)
        case .tempo: return FormatoMonitor.tempo(v)
        case .threads, .conexoes: return "\(Int(v))"
        case .despertares: return "\(Int(v.rounded()))"
        case .memoria, .residente, .escritos, .lidos: return FormatoMonitor.bytes(v)
        case .energia: return v * 1000 < 0.05 ? "0" : String(format: v * 1000 < 10 ? "%.1f" : "%.0f", v * 1000)
        case .repouso: return v > 0 ? "impede" : ""
        case .escritosSeg, .lidosSeg: return v < 1 ? "0" : FormatoMonitor.bytes(v)
        }
    }
}

enum FormatoMonitor {
    static func bytes(_ v: Double) -> String { ByteCountFormatter.string(fromByteCount: Int64(v), countStyle: .memory) }
    static func tempo(_ s: Double) -> String {
        let t = Int(s)
        if t >= 3600 { return String(format: "%d:%02d:%02d", t / 3600, t % 3600 / 60, t % 60) }
        return String(format: "%d:%02d,%02d", t / 60, t % 60, Int((s - Double(t)) * 100))
    }
    static let data: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "pt_BR"); f.dateFormat = "d MMM, HH:mm:ss"; return f
    }()
}

/// Ícone de cada processo: o do app aberto; o do pacote .app em que o executável mora
/// (helpers); senão o de executável. Guardado por caminho — só as linhas visíveis pedem.
@MainActor
enum IconeProcesso {
    private static var cache: [String: NSImage] = [:]
    private static let generico = NSWorkspace.shared.icon(for: .unixExecutable)

    static func de(_ p: ProcessoMonitor, app: NSRunningApplication?) -> NSImage {
        if let i = app?.icon { return i }
        guard let r = p.caminho.range(of: ".app/") else { return generico }
        let pacote = String(p.caminho[..<r.lowerBound]) + ".app"
        if let i = cache[pacote] { return i }
        let i = NSWorkspace.shared.icon(forFile: pacote)
        cache[pacote] = i
        return i
    }
}

struct MonitorAtividade: View {
    /// true = na ilha (fundo preto, letras claras, compacto); false = na Central.
    let naIlha: Bool
    var recolher: (() -> Void)?
    // Estado inicial (capturas)
    var abaInicial: AbaMonitor = .cpu
    var selecionadoInicial: pid_t?
    var confirmarInicial: Bool?
    /// Só no modo de capturas: aba, processo escolhido e confirmação na tela.
    static var captura: (aba: AbaMonitor, pid: pid_t?, confirmar: Bool?)?

    @Environment(\.telaVisivel) private var telaVisivel
    private let s = SistemaServico.shared
    @State private var aba: AbaMonitor = .cpu
    @State private var ordem: ColunaMonitor = .cpu
    @State private var crescente = false
    @State private var busca = ""
    @State private var selecionado: pid_t?
    /// nil = sem confirmação; false = encerrar; true = forçar.
    @State private var confirmar: Bool?
    @State private var aviso: String?
    @State private var iniciou = false
    @FocusState private var buscando: Bool

    private var quem: String { naIlha ? "monitor.ilha" : "monitor.central" }

    // Paleta: a ilha é sempre escura; a Central segue o sistema.
    private var claro: Color { naIlha ? Color(hex: "#F5F6F8") : .primary }
    private var cinza: Color { naIlha ? Color(hex: "#9398A1") : .secondary }
    private var apagado: Color { naIlha ? Color(hex: "#5F646D") : Color.secondary.opacity(0.6) }
    private var fundoCampo: Color { naIlha ? Color.white.opacity(0.07) : Color.primary.opacity(0.05) }
    private var linhaSel: Color { naIlha ? Color.white.opacity(0.11) : Color.accentColor.opacity(0.18) }
    private var fonte: CGFloat { naIlha ? 11 : 12 }
    private var alturaLinha: CGFloat { naIlha ? 20 : 22 }

    var body: some View {
        VStack(spacing: naIlha ? 6 : 8) {
            topo
            cabecalho
            lista
            rodape
        }
        .foregroundColor(claro)
        .onAppear {
            if !iniciou {
                iniciou = true
                trocar(para: abaInicial)
                selecionado = selecionadoInicial
                confirmar = confirmarInicial
            }
            if telaVisivel || !naIlha { assinar(true) }
        }
        .onChange(of: telaVisivel) { _, v in if naIlha { assinar(v) } }
        .onDisappear { assinar(false) }
    }

    private func assinar(_ sim: Bool) {
        let partes: Set<SistemaServico.Parte> = [.monitor, .rapido, .lento]
        if sim {
            s.assinar(quem, partes)
            s.monitorContaConexoes(aba == .rede)
        } else {
            s.soltar(quem, partes)
            s.monitorContaConexoes(false)
        }
    }

    private func trocar(para a: AbaMonitor) {
        aba = a
        ordem = a.colunas[0]
        crescente = false
        s.monitorContaConexoes(a == .rede)
    }

    // MARK: Topo: abas, busca, recolher

    private var topo: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                ForEach(AbaMonitor.allCases) { a in
                    Button { trocar(para: a) } label: {
                        Text(a.rawValue)
                            .font(.system(size: fonte, weight: aba == a ? .semibold : .regular))
                            .foregroundColor(aba == a ? (naIlha ? Color(hex: "#0B0C0E") : Color.white) : cinza)
                            .padding(.horizontal, naIlha ? 9 : 11)
                            .frame(height: naIlha ? 22 : 24)
                            .background(aba == a ? (naIlha ? Color(hex: "#F5F6F8") : Color.accentColor) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
            .background(fundoCampo)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Spacer(minLength: 6)

            Text("\(visiveis.count) processos").font(.system(size: fonte - 1)).foregroundColor(apagado).monospacedDigit()

            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass").font(.system(size: fonte - 1)).foregroundColor(cinza)
                TextField("Buscar", text: $busca)
                    .textFieldStyle(.plain)
                    .font(.system(size: fonte))
                    .focused($buscando)
                if !busca.isEmpty {
                    Button { busca = "" } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: fonte - 1)).foregroundColor(cinza)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .frame(width: naIlha ? 150 : 200, height: naIlha ? 24 : 26)
            .background(fundoCampo)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded {
                // A ilha não vira janela-chave sozinha: o campo precisa dela para digitar
                if naIlha { NSApp.windows.first { $0 is IslandPanel }?.makeKey() }
                buscando = true
            })

            if let recolher {
                Button(action: recolher) {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(cinza)
                        .frame(width: 26, height: 24)
                        .background(fundoCampo)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Recolher o monitor")
            }
        }
        // Na ilha, o monitor fica embaixo do resumo (o mesmo cartão crescendo): sem recuo
    }

    // MARK: Tabela

    private var cabecalho: some View {
        HStack(spacing: 0) {
            titulo(.nome).frame(maxWidth: .infinity, alignment: .leading).padding(.leading, naIlha ? 24 : 26)
            ForEach(aba.colunas) { c in titulo(c).frame(width: c.largura, alignment: .trailing) }
        }
        .padding(.horizontal, 8)
    }

    private func titulo(_ c: ColunaMonitor) -> some View {
        Button {
            if ordem == c { crescente.toggle() } else { ordem = c; crescente = c == .nome }
        } label: {
            HStack(spacing: 2) {
                Text(c.titulo.uppercased())
                if ordem == c {
                    Image(systemName: crescente ? "chevron.up" : "chevron.down").font(.system(size: 7, weight: .bold))
                }
            }
            .font(.system(size: naIlha ? 9.5 : 10, weight: .semibold))
            .tracking(0.4)
            .foregroundColor(ordem == c ? claro : apagado)
            .lineLimit(1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(c.ajuda)
    }

    private var visiveis: [ProcessoMonitor] {
        let termo = busca.trimmingCharacters(in: .whitespaces).lowercased()
        var l = s.monitor.processos
        if !termo.isEmpty {
            l = l.filter { p in
                nome(p).lowercased().contains(termo) || "\(p.pid)" == termo || p.nome.lowercased().contains(termo)
                    || s.nomeUsuario(p.uid).lowercased() == termo
            }
        }
        if ordem == .nome {
            return l.sorted { a, b in
                let r = nome(a).localizedCaseInsensitiveCompare(nome(b))
                return crescente ? r == .orderedAscending : r == .orderedDescending
            }
        }
        let c = ordem, asc = crescente
        return l.sorted { a, b in
            let va = c.valor(a), vb = c.valor(b)
            switch (va, vb) {
            case let (x?, y?): return x == y ? a.pid < b.pid : (asc ? x < y : x > y)
            case (.some, nil): return true
            case (nil, .some): return false
            default: return a.pid < b.pid
            }
        }
    }

    private func nome(_ p: ProcessoMonitor) -> String { s.apps[p.pid]?.localizedName ?? p.nome }

    private var lista: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if !s.monitor.lida && s.monitor.processos.isEmpty {
                    Text("Lendo…").font(.system(size: fonte)).foregroundColor(apagado).padding(.top, 12)
                }
                ForEach(visiveis) { p in linha(p) }
            }
        }
        .scrollIndicators(.automatic)
        .modifier(SoNaIlha(naIlha: naIlha))
        .background(naIlha ? Color.white.opacity(0.03) : Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func linha(_ p: ProcessoMonitor) -> some View {
        let sel = selecionado == p.pid
        return HStack(spacing: 0) {
            Image(nsImage: IconeProcesso.de(p, app: s.apps[p.pid]))
                .resizable().interpolation(.high)
                .frame(width: naIlha ? 15 : 17, height: naIlha ? 15 : 17)
                .padding(.trailing, naIlha ? 7 : 8)
            Text(nome(p)).lineLimit(1).truncationMode(.middle)
                .foregroundColor(p.proprio || p.tempoCPU != nil ? claro : cinza)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(aba.colunas) { c in
                Text(c.texto(p))
                    .foregroundColor(c.valor(p) == nil ? apagado : cinza)
                    .frame(width: c.largura, alignment: .trailing)
            }
        }
        .font(.system(size: fonte)).monospacedDigit()
        .padding(.horizontal, 8)
        .frame(height: alturaLinha)
        .background(sel ? linhaSel : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            selecionado = sel ? nil : p.pid
            confirmar = nil
            aviso = nil
        }
    }

    // MARK: Rodapé: detalhe do processo escolhido, ou os totais da aba

    @ViewBuilder private var rodape: some View {
        if let pid = selecionado, let p = s.monitor.processos.first(where: { $0.pid == pid }) {
            detalhe(p)
        } else if let aviso {
            HStack {
                Image(systemName: "info.circle").foregroundColor(cinza)
                Text(aviso).font(.system(size: fonte)).foregroundColor(cinza)
                Spacer()
                Button("OK") { self.aviso = nil }.buttonStyle(.plain).font(.system(size: fonte, weight: .semibold))
            }
            .padding(10).frame(height: alturaRodape).background(fundoCampo)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        } else {
            totais
        }
    }

    private var alturaRodape: CGFloat { naIlha ? 62 : 76 }

    private func detalhe(_ p: ProcessoMonitor) -> some View {
        let bloqueio = EncerrarProcesso.motivoBloqueio(p)
        return HStack(alignment: .top, spacing: 10) {
            Image(nsImage: IconeProcesso.de(p, app: s.apps[p.pid]))
                .resizable().frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(nome(p)).font(.system(size: fonte + 1, weight: .semibold)).lineLimit(1)
                    Text("pid \(p.pid) · \(s.nomeUsuario(p.uid)) · desde \(FormatoMonitor.data.string(from: p.inicio))")
                        .font(.system(size: fonte - 1)).foregroundColor(cinza).lineLimit(1)
                }
                Text(p.caminho.isEmpty ? "caminho indisponível" : p.caminho)
                    .font(.system(size: fonte - 1)).foregroundColor(apagado)
                    .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    .help(p.caminho)
                if let confirmar {
                    Text(confirmar
                         ? "Forçar fecha \(nome(p)) na hora. O que não foi salvo se perde."
                         : "Encerrar pede a \(nome(p)) para fechar; ele pode salvar ou perguntar antes.")
                        .font(.system(size: fonte - 1)).foregroundColor(Color(hex: "#F5A524")).lineLimit(1)
                } else if let bloqueio {
                    Label(bloqueio, systemImage: "lock.fill").font(.system(size: fonte - 1)).foregroundColor(cinza).lineLimit(1)
                } else if !p.proprio {
                    Text("Números lidos pelo ps (sem pegada de memória, disco e energia).")
                        .font(.system(size: fonte - 1)).foregroundColor(apagado).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 6) {
                    if let forcar = confirmar {
                        botao("Cancelar", destaque: false) { confirmar = nil }
                        botao(forcar ? "Forçar agora" : "Encerrar", destaque: true, perigo: forcar) {
                            let erro = EncerrarProcesso.enviar(p, forcar: forcar)
                            confirmar = nil
                            selecionado = nil
                            aviso = erro ?? (forcar ? "\(nome(p)) foi forçado a fechar."
                                                    : "Pedido de fechar enviado a \(nome(p)).")
                        }
                    } else {
                        botao("Encerrar", destaque: false) { confirmar = false }.disabled(bloqueio != nil)
                        botao("Forçar", destaque: false, perigo: true) { confirmar = true }.disabled(bloqueio != nil)
                    }
                    Button { selecionado = nil; confirmar = nil } label: {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundColor(cinza)
                            .frame(width: 20, height: 20).contentShape(Rectangle())
                    }.buttonStyle(.plain).help("Fechar o detalhe")
                }
                .opacity(bloqueio != nil ? 0.45 : 1)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(height: alturaRodape)
        .background(fundoCampo)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func botao(_ t: String, destaque: Bool, perigo: Bool = false, acao: @escaping () -> Void) -> some View {
        Button(action: acao) {
            Text(t)
                .font(.system(size: fonte, weight: .semibold))
                .foregroundColor(destaque ? .white : (perigo ? Color(hex: "#F4505E") : claro))
                .padding(.horizontal, 10).frame(height: naIlha ? 22 : 24)
                .background(destaque ? (perigo ? Color(hex: "#F4505E") : Color.accentColor)
                                     : (naIlha ? Color.white.opacity(0.09) : Color.primary.opacity(0.07)))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Totais da aba (como o rodapé do Monitor de Atividade)

    private var totais: some View {
        let t = s.monitor.totais
        return HStack(alignment: .center, spacing: naIlha ? 14 : 20) {
            switch aba {
            case .cpu:
                par("Sistema", FormatoSistema.pct(s.cpu.sistema))
                par("Usuário", FormatoSistema.pct(s.cpu.usuario))
                par("Ociosa", FormatoSistema.pct(max(0, 1 - s.cpu.total)))
                par("Threads", "\(t.threads)")
                par("Processos", "\(t.processos)")
                par("Carga", String(format: "%.2f · %.2f · %.2f", s.carga.um, s.carga.cinco, s.carga.quinze))
                Spacer(minLength: 0)
                GraficoHistorico(pontos: s.historicoCPU, total: SistemaServico.pontosHistorico, cor: FormatoSistema.corCPU)
                    .frame(width: naIlha ? 110 : 160, height: naIlha ? 34 : 44)
                    .background(naIlha ? Color.white.opacity(0.04) : Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            case .memoria:
                VStack(alignment: .leading, spacing: 3) {
                    Text("PRESSÃO").font(.system(size: 9.5, weight: .semibold)).tracking(0.4).foregroundColor(apagado)
                    Capsule().fill(FormatoSistema.corPressao(s.memoria.pressao))
                        .frame(width: naIlha ? 70 : 100, height: 8)
                    Text(s.memoria.pressao >= 4 ? "crítica" : s.memoria.pressao >= 2 ? "atenção" : "normal")
                        .font(.system(size: fonte - 1)).foregroundColor(cinza)
                }
                par("Física", FormatoSistema.bytes(s.memoria.total))
                par("Em uso", FormatoSistema.bytes(s.memoria.usada))
                par("Apps", FormatoSistema.bytes(s.memoria.app))
                par("Fixa", FormatoSistema.bytes(s.memoria.fixa))
                par("Comprimida", FormatoSistema.bytes(s.memoria.comprimida))
                par("Swap", FormatoSistema.bytes(s.memoria.swapUsado))
                Spacer(minLength: 0)
            case .energia:
                if let b = s.bateria {
                    par("Bateria", FormatoSistema.pct(b.nivel))
                    par("Fonte", b.carregando ? "carregando" : b.naTomada ? "na tomada" : "bateria")
                    if let m = b.minutosRestantes { par(b.carregando ? "Até encher" : "Restante", FormatoSistema.duracao(Double(m * 60))) }
                    if let sa = b.saude { par("Saúde", FormatoSistema.pct(sa)) }
                } else {
                    par("Fonte", "na tomada (sem bateria)")
                }
                par("Seus processos", String(format: "%.2f W", t.energia))
                par("Impedem repouso", "\(s.monitor.processos.filter(\.impedeRepouso).count)")
                Spacer(minLength: 0)
            case .disco:
                par("Leituras/s", "\(Int(t.discoLeiturasSeg.rounded()))")
                par("Escritas/s", "\(Int(t.discoEscritasSeg.rounded()))")
                par("Lidos/s", FormatoSistema.taxa(t.discoLidoSeg))
                par("Escritos/s", FormatoSistema.taxa(t.discoEscritoSeg))
                par("Lidos", FormatoMonitor.bytes(Double(t.discoLido)))
                par("Escritos", FormatoMonitor.bytes(Double(t.discoEscrito)))
                Spacer(minLength: 0)
            case .rede:
                par("Pacotes rec./s", "\(Int(s.rede.pacotesEntrada.rounded()))")
                par("Pacotes env./s", "\(Int(s.rede.pacotesSaida.rounded()))")
                par("Recebendo", FormatoSistema.taxa(s.rede.entrada))
                par("Enviando", FormatoSistema.taxa(s.rede.saida))
                par("Recebido", FormatoMonitor.bytes(Double(s.rede.totalEntrada)))
                par("Enviado", FormatoMonitor.bytes(Double(s.rede.totalSaida)))
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: alturaRodape)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(fundoCampo)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .help(aba == .rede ? "Bytes por processo ficam de fora: o macOS só os entrega ao nettop, que exigiria um programa externo a cada leitura."
              : t.alheios > 0 && !s.monitor.comPS ? "Processos do sistema sem números: o ps não respondeu." : "")
    }

    private func par(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(k.uppercased()).font(.system(size: naIlha ? 9 : 9.5, weight: .semibold)).tracking(0.4).foregroundColor(apagado)
                .lineLimit(1)
            Text(v).font(.system(size: naIlha ? 12 : 13, weight: .medium)).monospacedDigit().lineLimit(1)
        }
        .fixedSize()
    }
}

/// Na ilha, a lista avisa quando chegou ao fim (rolar para cima recolhe, como o chat).
private struct SoNaIlha: ViewModifier {
    let naIlha: Bool
    func body(content: Content) -> some View {
        if naIlha { content.rolagemDaIlha() } else { content }
    }
}
