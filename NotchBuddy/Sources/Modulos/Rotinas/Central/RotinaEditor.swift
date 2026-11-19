import SwiftUI
import AppKit

// Criar/editar uma rotina: nome, projeto, pedido, modelo, modo de permissão e agenda.
// A chave de "rodar sozinha" não mora aqui: fica na lista, com a confirmação da primeira vez.

struct RotinaEditor: View {
    struct Opcao: Identifiable {
        let nome: String
        let valor: String?
        var id: String { valor ?? "" }
    }

    static let modelos = [Opcao(nome: "Padrão", valor: nil), Opcao(nome: "Fable", valor: "fable"), Opcao(nome: "Opus", valor: "opus"),
                          Opcao(nome: "Sonnet", valor: "sonnet"), Opcao(nome: "Haiku", valor: "haiku")]
    static let modos = [Opcao(nome: "Padrão", valor: nil), Opcao(nome: "Aceitar edições", valor: "acceptEdits"),
                        Opcao(nome: "Planejar", valor: "plan"), Opcao(nome: "Automático", valor: "auto")]

    @State var rotina: Rotina
    let nova: Bool
    /// Rotina de um Homie (o nome dele): sem projeto, modelo nem permissões — a sessão abre na
    /// pasta dele, só lendo, e entrega uma página.
    var doHomie: String? = nil
    let salvar: (Rotina) -> Void
    let cancelar: () -> Void

    @ObservedObject private var projetos = ProjetosCrew.shared
    /// Intervalo mostrado em horas (senão, minutos).
    @State private var emHoras: Bool

    init(rotina: Rotina, nova: Bool, doHomie: String? = nil, salvar: @escaping (Rotina) -> Void, cancelar: @escaping () -> Void) {
        _rotina = State(initialValue: rotina)
        _emHoras = State(initialValue: rotina.agenda.intervaloMin % 60 == 0)
        self.nova = nova
        self.doHomie = doHomie
        self.salvar = salvar
        self.cancelar = cancelar
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(doHomie.map { nova ? "Nova rotina de \($0)" : "Rotina de \($0)" } ?? (nova ? "Nova rotina" : "Editar rotina"))
                .font(.system(size: 15, weight: .semibold))

            campo("Nome") {
                TextField(doHomie == nil ? "Revisão da manhã" : "Página da manhã", text: $rotina.nome).textFieldStyle(.roundedBorder)
            }
            if let doHomie {
                campo("O que ele entrega") {
                    TextEditor(text: $rotina.pedido)
                        .font(.system(size: 12.5))
                        .frame(height: 130)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .background(Color.primary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Text("Diga o que você quer ler na página e que tipo de movimento ele deve propor. \(doHomie) roda sem ninguém por perto: só lê, escreve a página na pasta dele e propõe as ações. Nada é feito sem o seu clique.")
                        .font(.system(size: 10.5)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Toggle("Pode consultar os MCPs dele", isOn: Binding(get: { rotina.comMcps == true }, set: { rotina.comMcps = $0 }))
                    .toggleStyle(.switch).controlSize(.small)
                Text(rotina.comMcps == true
                     ? "Enxerga só os servidores do .mcp.json da pasta dele. Cada uso ainda pede a sua permissão: a execução para e espera você."
                     : "Sem nenhum MCP: trabalha só com os arquivos que alcança.")
                    .font(.system(size: 10.5)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
            campo("Projeto") {
                HStack(spacing: 8) {
                    SeletorCrew(selecao: $rotina.pasta,
                                opcoes: (rotina.pasta.isEmpty ? [(valor: "", titulo: "Escolha um projeto")] : [])
                                    + pastas.map { (valor: $0.caminho, titulo: $0.nome) })
                    Button("Escolher pasta…") { escolherPasta() }
                    Spacer(minLength: 0)
                }
                if !rotina.pasta.isEmpty {
                    Text(rotina.pasta.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(.system(size: 10.5)).foregroundColor(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }
            campo("Pedido") {
                TextEditor(text: $rotina.pedido)
                    .font(.system(size: 12.5))
                    .frame(height: 110)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Text("É o que a sessão recebe ao abrir, como se você tivesse digitado.")
                    .font(.system(size: 10.5)).foregroundColor(.secondary)
            }
            HStack(alignment: .top, spacing: 16) {
                campo("Modelo") {
                    SeletorCrew(selecao: $rotina.modelo,
                                opcoes: Self.modelos.map { (valor: $0.valor, titulo: $0.nome) })
                }
                campo("Permissões") {
                    SeletorCrew(selecao: $rotina.modo,
                                opcoes: Self.modos.map { (valor: $0.valor, titulo: $0.nome) })
                }
                Spacer(minLength: 0)
            }
            if rotina.modo == "auto" || rotina.modo == "acceptEdits" {
                Text(rotina.modo == "auto"
                     ? "Automático: a sessão decide sozinha o que pode fazer, sem pedir aprovação a cada passo."
                     : "Aceitar edições: a sessão altera arquivos do projeto sem pedir aprovação.")
                    .font(.system(size: 10.5)).foregroundColor(FormatoRotinaUI.corFalha).fixedSize(horizontal: false, vertical: true)
            }
            }

            Divider()
            agenda

            HStack {
                Spacer()
                Button("Cancelar", role: .cancel) { cancelar() }.keyboardShortcut(.cancelAction)
                Button(nova ? "Criar" : "Salvar") { salvar(rotina) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!rotina.completa)
            }
        }
        .padding(20)
        .frame(width: 540)
        .task { if !CaptureTool.ativo { await projetos.recarregar() } }
    }

    // MARK: Agenda

    @ViewBuilder private var agenda: some View {
        campo("Quando") {
            Picker("", selection: $rotina.agenda.tipo) {
                Text("Só à mão").tag(AgendaRotina.Tipo.manual)
                Text("Todo dia").tag(AgendaRotina.Tipo.diaria)
                Text("Dias da semana").tag(AgendaRotina.Tipo.semanal)
                Text("A cada…").tag(AgendaRotina.Tipo.intervalo)
                Text("Uma vez").tag(AgendaRotina.Tipo.umaVez)
            }
            .pickerStyle(.segmented).labelsHidden()
            .onChange(of: rotina.agenda.tipo) { _, tipo in
                if tipo == .umaVez && rotina.agenda.data == nil {
                    rotina.agenda.data = Calendar.current.date(byAdding: .day, value: 1, to: Date())
                }
            }

            switch rotina.agenda.tipo {
            case .manual:
                EmptyView()
            case .diaria:
                HStack { Text("às"); horario; Spacer() }
            case .semanal:
                HStack(spacing: 5) {
                    // Segunda primeiro, domingo no fim
                    ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { dia in
                        let marcado = rotina.agenda.dias.contains(dia)
                        Button { alternar(dia) } label: {
                            Text(FormatoRotina.diasCurtos[dia - 1]).font(.system(size: 11.5, weight: .medium))
                                .frame(width: 38, height: 24)
                                .background(marcado ? Color.accentColor.opacity(0.85) : Color.primary.opacity(0.07))
                                .foregroundColor(marcado ? .white : .primary)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                    Text("às").padding(.leading, 6)
                    horario
                    Spacer(minLength: 0)
                }
            case .intervalo:
                HStack(spacing: 8) {
                    Text("a cada")
                    TextField("", value: intervalo, format: .number).textFieldStyle(.roundedBorder).frame(width: 56)
                        .multilineTextAlignment(.trailing)
                    SeletorCrew(selecao: $emHoras,
                                opcoes: [(valor: false, titulo: "minutos"), (valor: true, titulo: "horas")])
                    .onChange(of: emHoras) { _, horas in
                        // Mantém o número que está no campo, trocando só a unidade
                        let n = horas ? max(1, rotina.agenda.intervaloMin) : max(1, rotina.agenda.intervaloMin / 60)
                        rotina.agenda.intervaloMin = horas ? n * 60 : n
                    }
                    Spacer()
                }
                if rotina.agenda.intervaloMin < PoliticaRotinas.intervaloMinimo {
                    Text("O mínimo é \(PoliticaRotinas.intervaloMinimo) minutos.").font(.system(size: 10.5)).foregroundColor(FormatoRotinaUI.corFalha)
                }
            case .umaVez:
                HStack {
                    DatePicker("", selection: Binding(get: { rotina.agenda.data ?? Date() }, set: { rotina.agenda.data = $0 }),
                               displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden().environment(\.locale, Locale(identifier: "pt_BR"))
                    Spacer()
                }
            }

            if rotina.agenda.tipo != .manual {
                Toggle("Recuperar execução perdida", isOn: $rotina.recuperarPerdida)
                    .toggleStyle(.switch).controlSize(.small)
                Text(rotina.recuperarPerdida
                     ? "Se a hora passar com o Mac dormindo ou o Crew fechado, roda uma vez ao voltar (nunca mais de uma)."
                     : "Se a hora passar com o Mac dormindo ou o Crew fechado, não roda: espera a próxima.")
                    .font(.system(size: 10.5)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                Text(previa).font(.system(size: 11.5, weight: .medium))
            } else {
                Text("Roda só quando você clicar em \"Rodar agora\".").font(.system(size: 10.5)).foregroundColor(.secondary)
            }
        }
    }

    private var previa: String {
        guard rotina.agenda.valida else { return "Agenda incompleta." }
        guard let p = rotina.agenda.proxima(depois: Date(), ancora: Date()) else { return "Essa data já passou: não vai rodar." }
        let ligada = rotina.ligada ? "" : " (depois de ligar a chave na lista)"
        return "\(FormatoRotina.descricao(rotina.agenda)) — a próxima seria \(FormatoRotina.quando(p))\(ligada)"
    }

    private var horario: some View {
        DatePicker("", selection: Binding(
            get: { Calendar.current.date(bySettingHour: rotina.agenda.hora, minute: rotina.agenda.minuto, second: 0, of: Date()) ?? Date() },
            set: { d in
                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                rotina.agenda.hora = c.hour ?? 9
                rotina.agenda.minuto = c.minute ?? 0
            }), displayedComponents: .hourAndMinute)
            .labelsHidden().environment(\.locale, Locale(identifier: "pt_BR")).frame(width: 80)
    }

    private var intervalo: Binding<Int> {
        Binding(get: { emHoras ? rotina.agenda.intervaloMin / 60 : rotina.agenda.intervaloMin },
                set: { rotina.agenda.intervaloMin = max(1, $0) * (emHoras ? 60 : 1) })
    }

    private func alternar(_ dia: Int) {
        if let i = rotina.agenda.dias.firstIndex(of: dia) { rotina.agenda.dias.remove(at: i) } else { rotina.agenda.dias.append(dia) }
    }

    // MARK: Projeto

    /// Os projetos do Crew, mais a pasta atual da rotina se ela não estiver entre eles.
    private var pastas: [(caminho: String, nome: String)] {
        var l = projetos.lista.map { (caminho: $0.caminho, nome: $0.nome) }
        if !rotina.pasta.isEmpty, !l.contains(where: { $0.caminho == rotina.pasta }) {
            l.append((caminho: rotina.pasta, nome: URL(fileURLWithPath: rotina.pasta).lastPathComponent))
        }
        return l
    }

    private func escolherPasta() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.allowsMultipleSelection = false
        p.prompt = "Escolher"
        p.message = "Escolha a pasta onde a rotina abre a sessão"
        if p.runModal() == .OK, let url = p.url { rotina.pasta = url.path }
    }

    private func campo<C: View>(_ titulo: String, @ViewBuilder _ conteudo: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(titulo).font(.system(size: 11, weight: .medium)).foregroundColor(.secondary)
            conteudo()
        }
    }
}
