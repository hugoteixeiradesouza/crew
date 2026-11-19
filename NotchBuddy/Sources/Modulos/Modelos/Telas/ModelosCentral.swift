import SwiftUI

// Página dos Modelos na Central: a lista completa, o que está carregado e a remoção
// (sempre com confirmação dizendo o que sai, quanto libera e se é definitivo).

struct ModelosCentral: View {
    private let s = ModelosServico.shared
    @State private var pedido: ModelosServico.Plano?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Secao("Em disco", "Tamanho real: blobs que dois modelos do Ollama dividem contam uma vez só.") {
                HStack(alignment: .top, spacing: 22) {
                    par("Total", s.varredura.map { FormatoModelos.bytes($0.totalDisco) } ?? "—")
                    par("Modelos", s.varredura.map { "\($0.modelos.count)" } ?? "—")
                    par("Servidor do Ollama", s.servidorAtivo ? "rodando" : "parado")
                    Spacer()
                    Button(s.varrendo ? "Lendo…" : "Atualizar") { s.atualizar() }.disabled(s.varrendo)
                }
                if let v = s.varredura {
                    Text(v.pastas.isEmpty
                         ? "Nenhuma pasta de modelos neste Mac (procurei em \(FormatoModelos.pastasProcuradas))."
                         : "Pastas lidas: " + v.pastas.map { FormatoModelos.curto($0) }.joined(separator: ", "))
                        .font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }

            if let c = s.carregados, !c.isEmpty {
                Secao("Carregados agora", "Na memória do Ollama. Saem sozinhos quando o Ollama descarrega.") {
                    ForEach(c) { m in
                        HStack {
                            Circle().fill(FormatoModelos.corAtivo).frame(width: 7, height: 7)
                            Text(m.nome).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            if m.memoriaGPU > 0 {
                                Text("GPU \(FormatoModelos.bytes(m.memoriaGPU))").foregroundColor(.secondary)
                            }
                            Text(FormatoModelos.bytes(m.memoria)).frame(width: 80, alignment: .trailing)
                            if let e = m.expiraEm {
                                Text("até \(FormatoModelos.hora(e))").foregroundColor(.secondary).frame(width: 80, alignment: .trailing)
                            }
                        }
                        .font(.system(size: 12)).monospacedDigit()
                    }
                }
            }

            Secao("Modelos", "\"Libera\" é o que sai do disco removendo só aquele modelo.") {
                if let v = s.varredura {
                    if v.modelos.isEmpty {
                        Text("Nenhum modelo baixado. Quando você baixar um pelo Ollama ou pelo LM Studio, ele aparece aqui.")
                            .font(.system(size: 12)).foregroundColor(.secondary)
                    } else {
                        cabecalho
                        ForEach(v.modelos) { m in linha(m) }
                    }
                } else {
                    Text("Lendo…").font(.system(size: 12)).foregroundColor(.secondary)
                }
                if let a = s.aviso {
                    Text(a).font(.system(size: 11.5)).foregroundColor(.secondary)
                }
            }
        }
        .onAppear { s.assinar("central") }
        .onDisappear { s.soltar("central") }
        .alert(pedido.map { "Remover \($0.modelo.nome)?" } ?? "",
               isPresented: Binding(get: { pedido != nil }, set: { if !$0 { pedido = nil } }),
               presenting: pedido) { p in
            if p.modo != .impossivel {
                Button("Remover", role: .destructive) { s.executar(p) }
            }
            Button("Cancelar", role: .cancel) {}
        } message: { p in
            Text(FormatoModelos.explicar(p))
        }
    }

    private var cabecalho: some View {
        HStack {
            Text("Nome").frame(maxWidth: .infinity, alignment: .leading)
            Text("Tamanho").frame(width: 76, alignment: .trailing)
            Text("Libera").frame(width: 76, alignment: .trailing)
            Text("Modificado").frame(width: 92, alignment: .trailing)
            Color.clear.frame(width: 28)
        }
        .font(.system(size: 10.5)).foregroundColor(.secondary)
    }

    private func linha(_ m: ModeloLocal) -> some View {
        let carregado = s.carregados?.contains { $0.nome == m.nome } == true
        return HStack {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    if carregado { Circle().fill(FormatoModelos.corAtivo).frame(width: 6, height: 6) }
                    Text(m.nome).font(.system(size: 12.5, weight: .medium)).lineLimit(1).truncationMode(.middle)
                }
                Text(m.origem.nome).font(.system(size: 10.5)).foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(FormatoModelos.bytes(m.tamanho)).frame(width: 76, alignment: .trailing)
            Text(m.recuperavel > 0 ? FormatoModelos.bytes(m.recuperavel) : "—")
                .foregroundColor(m.recuperavel < m.tamanho ? .secondary : .primary)
                .frame(width: 76, alignment: .trailing)
            Text(FormatoModelos.data(m.modificado)).foregroundColor(.secondary).frame(width: 92, alignment: .trailing)
            Group {
                if s.removendo == m.id {
                    ProgressView().controlSize(.small)
                } else {
                    Button { pedido = s.plano(m) } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                        .disabled(s.removendo != nil)
                        .help("Remover este modelo")
                }
            }
            .frame(width: 28)
        }
        .font(.system(size: 12)).monospacedDigit()
    }

    private func par(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(k).font(.system(size: 10.5)).foregroundColor(.secondary)
            Text(v).font(.system(size: 13, weight: .medium)).monospacedDigit()
        }
    }
}

enum FormatoModelos {
    static let rotulo = Color(hex: "#9398A1")
    static let apagado = Color(hex: "#5F646D")
    static let corAtivo = Color(hex: "#34D399")

    static func bytes(_ b: Int64) -> String { ByteCountFormatter.string(fromByteCount: b, countStyle: .file) }

    static func contagem(_ v: VarreduraModelos) -> String {
        let n = v.modelos.count
        let origens = PoliticaModelos.Origem.allCases.filter { o in v.modelos.contains { $0.origem == o } }.map(\.nome)
        return "\(n) \(n == 1 ? "modelo" : "modelos") · " + origens.joined(separator: ", ")
    }

    private static let pt = Locale(identifier: "pt_BR")
    static func data(_ d: Date) -> String {
        d == .distantPast ? "—" : d.formatted(Date.FormatStyle(date: .numeric, time: .omitted).locale(pt))
    }
    static func hora(_ d: Date) -> String { d.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(pt)) }

    static func curto(_ u: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return u.path.hasPrefix(home) ? "~" + u.path.dropFirst(home.count) : u.path
    }

    static var pastasProcuradas: String { PoliticaModelos.raizes().map { curto($0) }.joined(separator: ", ") }

    /// Texto da confirmação: o que sai, quanto libera e se dá para desfazer.
    static func explicar(_ p: ModelosServico.Plano) -> String {
        let m = p.modelo
        let libera = m.recuperavel > 0
            ? "Libera \(bytes(m.recuperavel))."
            : "Libera quase nada: os pesos são divididos com outro modelo, que continua usando."
        let dividido = m.recuperavel > 0 && m.recuperavel < m.tamanho
            ? " (\(bytes(m.tamanho - m.recuperavel)) ficam, porque outro modelo usa.)" : ""
        switch p.modo {
        case .ollamaRm:
            return "\(libera)\(dividido)\n\nSai pelo próprio Ollama (ollama rm). É definitivo: não passa pela Lixeira. Para ter de volta, só baixando de novo."
        case .lixeira(let arquivos):
            let qtd = arquivos.count == 1 ? "1 item" : "\(arquivos.count) itens"
            return "\(libera)\(dividido)\n\nVão para a Lixeira \(qtd) de \(m.origem.nome). Dá para desfazer pela Lixeira enquanto ela não for esvaziada."
        case .impossivel:
            return "Nada deste modelo está numa pasta que o Crew possa mexer com segurança. Remova pelo \(m.origem.nome)."
        }
    }
}
