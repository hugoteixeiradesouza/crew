import SwiftUI
import ServiceManagement
import AppKit

struct SettingsView: View {
    @ObservedObject private var state = AppState.shared
    @State private var apiKey: String = KeychainStore.shared.get("anthropic-api-key") ?? ""
    @State private var launchAtStartup: Bool = (SMAppService.mainApp.status == .enabled)
    @State private var statusMessage: String = ""

    // Integration keys
    @State private var resendKey: String    = KeychainStore.shared.get("resend-api-key")  ?? ""
    @State private var resendFrom: String   = KeychainStore.shared.get("resend-from")     ?? ""
    @State private var n8nUrl: String       = KeychainStore.shared.get("n8n-url")         ?? ""
    @State private var n8nKey: String       = KeychainStore.shared.get("n8n-api-key")     ?? ""
    @State private var vercelToken: String  = KeychainStore.shared.get("vercel-token")    ?? ""
    @State private var githubToken: String  = KeychainStore.shared.get("github-token")    ?? ""
    @State private var stripeKey: String    = KeychainStore.shared.get("stripe-api-key")  ?? ""
    @State private var calcomKey: String    = KeychainStore.shared.get("calcom-api-key")  ?? ""
    @State private var notionKey: String    = KeychainStore.shared.get("notion-api-key")  ?? ""

    // Vercel project filter
    @State private var vercelProjects: [String] = []
    @State private var loadingVercel: Bool = false

    // n8n workflow filter
    @State private var n8nWorkflows: [String] = []
    @State private var loadingN8n: Bool = false

    @AppStorage(Usuario.chave) private var nomeDoUsuario = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {

                // MARK: Cabeçalho
                CabecalhoPagina(icone: "gearshape", titulo: "Crew",
                                detalhe: "O que vale para tudo. O Homie e o notch ficam em Ilha; a janela de trabalho, em App; cada ferramenta tem a página dela.")

                // MARK: Você
                Secao("Você", "Como o Crew te chama: na saudação, na voz e nas instruções que ele passa às sessões e aos Homies. Vazio, vale o nome da conta do Mac.") {
                    HStack(spacing: 8) {
                        Text("Nome").frame(width: 70, alignment: .leading)
                        TextField(Usuario.nomeDaConta, text: $nomeDoUsuario).textFieldStyle(.roundedBorder).frame(maxWidth: 220)
                    }
                }

                // MARK: Início
                Secao("Início", nil) {
                    Toggle("Abrir o Crew ao ligar o Mac", isOn: $launchAtStartup)
                        .onChange(of: launchAtStartup) { _, on in toggleStartup(on) }
                }

                // MARK: Permissões
                Secao("Permissões do macOS", "O que o macOS já liberou para o Crew e qual ferramenta usa cada uma. O pedido só aparece no primeiro uso da ferramenta.") {
                    PermissoesDoMac()
                }

                // MARK: Atalhos globais
                Secao("Atalhos globais", "Funcionam com qualquer app na frente. Cada um se ajusta na página de quem é dono dele.") {
                    IndiceAtalhos()
                }

                // MARK: Integrations
                if AgentTask.integracoesLigadas {
                GroupBox("Integrações") {
                    VStack(alignment: .leading, spacing: 14) {

                        // Resend
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 6) {
                                Circle().fill(Color(hex: "#22C55E")).frame(width: 8, height: 8)
                                Text("Resend").font(.system(size: 12, weight: .semibold))
                            }
                            SecureField("Chave da API  (re_…)", text: $resendKey)
                                .textFieldStyle(.roundedBorder)
                            TextField("Remetente  (voce@seudominio.com)", text: $resendFrom)
                                .textFieldStyle(.roundedBorder)
                        }

                        // n8n
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 6) {
                                Circle().fill(Color(hex: "#F29B38")).frame(width: 8, height: 8)
                                Text("n8n").font(.system(size: 12, weight: .semibold))
                            }
                            TextField("Endereço da instância  (https://…)", text: $n8nUrl)
                                .textFieldStyle(.roundedBorder)
                            SecureField("Chave da API", text: $n8nKey)
                                .textFieldStyle(.roundedBorder)
                            IntegrationFilterRow(
                                label: "Workflows",
                                items: n8nWorkflows,
                                filter: $state.n8nWorkflowFilter,
                                loading: loadingN8n,
                                onLoad: loadN8nWorkflows
                            )
                        }

                        // Vercel
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 6) {
                                Circle().fill(Color(hex: "#7C5CFF")).frame(width: 8, height: 8)
                                Text("Vercel").font(.system(size: 12, weight: .semibold))
                            }
                            SecureField("Token", text: $vercelToken)
                                .textFieldStyle(.roundedBorder)
                            IntegrationFilterRow(
                                label: "Projetos",
                                items: vercelProjects,
                                filter: $state.vercelProjectFilter,
                                loading: loadingVercel,
                                onLoad: loadVercelProjects
                            )
                        }

                        // GitHub
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 6) {
                                Circle().fill(Color(hex: "#F4505E")).frame(width: 8, height: 8)
                                Text("GitHub").font(.system(size: 12, weight: .semibold))
                            }
                            SecureField("Personal Access Token", text: $githubToken)
                                .textFieldStyle(.roundedBorder)
                        }

                        // Stripe
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 6) {
                                Circle().fill(Color(hex: "#0570DE")).frame(width: 8, height: 8)
                                Text("Stripe").font(.system(size: 12, weight: .semibold))
                            }
                            SecureField("Chave secreta  (sk_live_… ou sk_test_…)", text: $stripeKey)
                                .textFieldStyle(.roundedBorder)
                        }

                        // Cal.com
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 6) {
                                Circle().fill(Color(hex: "#C9956A")).frame(width: 8, height: 8)
                                Text("Cal.com").font(.system(size: 12, weight: .semibold))
                            }
                            SecureField("Chave da API  (cal_live_…)", text: $calcomKey)
                                .textFieldStyle(.roundedBorder)
                        }

                        // Notion
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 6) {
                                Circle().fill(Color(hex: "#E8E8E8")).frame(width: 8, height: 8)
                                Text("Notion").font(.system(size: 12, weight: .semibold))
                            }
                            SecureField("Token da integração  (secret_…)", text: $notionKey)
                                .textFieldStyle(.roundedBorder)
                        }

                        Button("Salvar integrações") { saveIntegrations() }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(6)
                }
                }

                // MARK: Active pills
                if AgentTask.integracoesLigadas {
                GroupBox("Pílulas ativas na ilha") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Claude Code")
                                .font(.system(size: 12, weight: .semibold))
                            Circle().fill(Color(hex: "#F5F6F8")).frame(width: 8, height: 8)
                            Spacer()
                            Text("Sempre ativa")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }

                        Divider()

                        Text("\(state.activeIntegrations.count) de 4 lugares em uso")
                            .font(.system(size: 11))
                            .foregroundColor(state.activeIntegrations.count >= 4 ? .orange : .secondary)

                        ForEach(AgentTask.toggleableIntegrationIds, id: \.self) { id in
                            let task = AgentTask.integrationAgents.first { $0.id == id }!
                            let isOn = state.activeIntegrations.contains(id)
                            let atMax = state.activeIntegrations.count >= 4 && !isOn
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color(hex: task.color))
                                    .frame(width: 10, height: 10)
                                Text(task.name)
                                    .font(.system(size: 12))
                                    .foregroundColor(atMax ? .secondary : .primary)
                                Spacer()
                                Toggle("", isOn: Binding(
                                    get: { isOn },
                                    set: { _ in state.toggleIntegration(id) }
                                ))
                                .labelsHidden()
                                .disabled(atMax)
                            }
                        }
                    }
                    .padding(6)
                }
                }

                // MARK: API
                Secao("Contas e chaves", "Chave da API da Anthropic: usada só pelos recursos que conversam com o Claude direto do Crew. Fica no Keychain.") {
                    HStack(spacing: 8) {
                        SecureField("Chave da API (sk-ant-…)", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                        Button("Salvar") {
                            KeychainStore.shared.set("anthropic-api-key", value: apiKey)
                            statusMessage = "Chave salva."
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.system(size: 12))
                        .foregroundColor(statusMessage.hasPrefix("Erro") ? .red : .secondary)
                        .padding(.horizontal, 2)
                }

                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Actions

    private func toggleStartup(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() }
            else  { try SMAppService.mainApp.unregister() }
        } catch {
            statusMessage = "Erro ao mudar o início com o Mac: \(error.localizedDescription)"
            launchAtStartup = !on
        }
    }

    private func saveIntegrations() {
        saveKey("resend-api-key",  value: resendKey)
        saveKey("resend-from",     value: resendFrom)
        saveKey("n8n-url",         value: n8nUrl)
        saveKey("n8n-api-key",     value: n8nKey)
        saveKey("vercel-token",    value: vercelToken)
        saveKey("github-token",    value: githubToken)
        saveKey("stripe-api-key",  value: stripeKey)
        saveKey("calcom-api-key",  value: calcomKey)
        saveKey("notion-api-key",  value: notionKey)
        statusMessage = "Chaves das integrações salvas."
    }

    /// Saves non-empty value; removes only if key was previously set (explicit user clear).
    private func saveKey(_ key: String, value: String) {
        if value.isEmpty {
            KeychainStore.shared.remove(key)
        } else {
            KeychainStore.shared.set(key, value: value)
        }
    }

    // MARK: - Vercel project list

    private func loadVercelProjects() {
        guard let token = KeychainStore.shared.get("vercel-token") else {
            statusMessage = "Erro: salve o token do Vercel primeiro."
            return
        }
        loadingVercel = true
        guard let url = URL(string: "https://api.vercel.com/v9/projects?limit=100") else { return }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: req) { data, response, _ in
            let names: [String]
            if let data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let projects = json["projects"] as? [[String: Any]] {
                names = projects.compactMap { $0["name"] as? String }.sorted()
            } else {
                names = []
            }
            DispatchQueue.main.async {
                self.vercelProjects = names
                self.loadingVercel = false
                if names.isEmpty { self.statusMessage = "Erro: nenhum projeto do Vercel encontrado." }
            }
        }.resume()
    }

    // MARK: - n8n workflow list

    private func loadN8nWorkflows() {
        guard let apiKey  = KeychainStore.shared.get("n8n-api-key"),
              let rawBase = KeychainStore.shared.get("n8n-url") else {
            statusMessage = "Erro: salve o endereço e a chave do n8n primeiro."
            return
        }
        loadingN8n = true
        let base = rawBase.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let urls = ["\(base)/api/v1/workflows?limit=100", "\(base)/rest/workflows?limit=100"]
        fetchN8nWorkflows(urls: urls, apiKey: apiKey, idx: 0)
    }

    private func fetchN8nWorkflows(urls: [String], apiKey: String, idx: Int) {
        guard idx < urls.count, let url = URL(string: urls[idx]) else {
            DispatchQueue.main.async { self.loadingN8n = false; self.statusMessage = "Erro: nenhum workflow do n8n encontrado." }
            return
        }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue(apiKey, forHTTPHeaderField: "X-N8N-API-KEY")
        URLSession.shared.dataTask(with: req) { data, response, _ in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard let data, code == 200 else {
                self.fetchN8nWorkflows(urls: urls, apiKey: apiKey, idx: idx + 1)
                return
            }
            let items: [[String: Any]]
            if let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
               let arr = obj["data"] as? [[String: Any]] { items = arr }
            else if let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] { items = arr }
            else { items = [] }
            let names = items.compactMap { $0["name"] as? String }.sorted()
            DispatchQueue.main.async {
                self.n8nWorkflows = names
                self.loadingN8n = false
                if names.isEmpty { self.statusMessage = "Erro: nenhum workflow do n8n encontrado." }
            }
        }.resume()
    }
}

// MARK: - Integration filter row (reusable for Vercel / n8n)

struct IntegrationFilterRow: View {
    let label: String
    let items: [String]
    @Binding var filter: Set<String>
    let loading: Bool
    let onLoad: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                if loading {
                    ProgressView().scaleEffect(0.6)
                } else {
                    Button(items.isEmpty ? "Carregar lista" : "Atualizar") { onLoad() }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                }
                if !filter.isEmpty {
                    Button("Limpar") { filter = [] }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .foregroundColor(.secondary)
                }
            }
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(items, id: \.self) { item in
                        Toggle(item, isOn: Binding(
                            get: { filter.isEmpty || filter.contains(item) },
                            set: { on in
                                if on { filter.insert(item) }
                                else  {
                                    // First click on any item: switch from "all" to explicit set
                                    if filter.isEmpty { filter = Set(items).subtracting([item]) }
                                    else { filter.remove(item) }
                                    if filter.count == items.count { filter = [] } // all = empty
                                }
                            }
                        ))
                        .font(.system(size: 11))
                        .toggleStyle(.checkbox)
                    }
                }
                .padding(.leading, 4)
                if !filter.isEmpty {
                    Text("Acompanhando \(filter.count) de \(items.count)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - Shortcut recorder button

struct ShortcutRecorderButton: View {
    @Binding var flags: UInt
    @Binding var code: UInt16
    @State private var isRecording = false

    var body: some View {
        Button {
            guard !isRecording else { return }
            isRecording = true
            var token: Any?
            token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])
                guard !mods.isEmpty else { return event }
                DispatchQueue.main.async {
                    self.flags = mods.rawValue
                    self.code = event.keyCode
                    self.isRecording = false
                    if let t = token { NSEvent.removeMonitor(t) }
                }
                return nil
            }
        } label: {
            Text(isRecording ? "Aperte as teclas…" : shortcutLabel)
                .font(.system(size: 11, design: .monospaced))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(isRecording ? Color.accentColor.opacity(0.12) : Color(NSColor.controlBackgroundColor))
                .cornerRadius(5)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.gray.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var shortcutLabel: String {
        let f = NSEvent.ModifierFlags(rawValue: flags)
        var s = ""
        if f.contains(.control) { s += "⌃" }
        if f.contains(.option)  { s += "⌥" }
        if f.contains(.shift)   { s += "⇧" }
        if f.contains(.command) { s += "⌘" }
        s += keyChar(code)
        return s.isEmpty ? "Nenhum" : s
    }

    private func keyChar(_ c: UInt16) -> String {
        let map: [UInt16: String] = [
            0:"A", 1:"S", 2:"D", 3:"F", 4:"H", 5:"G", 6:"Z", 7:"X", 8:"C", 9:"V",
            11:"B", 12:"Q", 13:"W", 14:"E", 15:"R", 16:"Y", 17:"T", 31:"O", 32:"U",
            34:"I", 37:"L", 38:"J", 40:"K", 45:"N", 46:"M", 49:"Espaço", 50:"`", 27:"-"
        ]
        return map[c] ?? "·"
    }
}


// MARK: - Peças dos Ajustes

/// Bloco com título, explicação curta e conteúdo num cartão.
struct Secao<Conteudo: View>: View {
    let titulo: String
    let detalhe: String?
    @ViewBuilder let conteudo: Conteudo

    init(_ titulo: String, _ detalhe: String?, @ViewBuilder conteudo: () -> Conteudo) {
        self.titulo = titulo
        self.detalhe = detalhe
        self.conteudo = conteudo()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(titulo).font(.system(size: 13, weight: .semibold))
                if let detalhe {
                    Text(detalhe).font(.system(size: 11)).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(alignment: .leading, spacing: 10) { conteudo }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}

/// Linha de módulo: ícone, nome, o que faz e a chave.
struct LinhaModulo: View {
    let icone: String
    let titulo: String
    let detalhe: String
    @Binding var ligado: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icone)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(ligado ? .accentColor : .secondary)
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(titulo).font(.system(size: 13, weight: .medium))
                Text(detalhe).font(.system(size: 11)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: $ligado).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
    }
}


// MARK: - Personagem

/// Nome, cor, boné, fones e detalhes do personagem, com ele ao vivo ao lado.
struct PersonagemAjustes: View {
    @ObservedObject var state: AppState
    @State private var comFones = false

    static let coresCorpo: [(String, String)] = [
        ("", "Branco"), ("#F2D7B6", "Areia"), ("#BDEBD6", "Menta"), ("#BFDDF7", "Céu"),
        ("#D9CCF5", "Lavanda"), ("#F7C9B6", "Pêssego"), ("#F5E6A8", "Limão"), ("#9EA3AD", "Grafite"),
    ]
    static let coresBone: [(String, String)] = [
        ("#2B2E33", "Preto"), ("#F2F2F2", "Branco"), ("#C0392B", "Vermelho"), ("#1F4E8C", "Azul"),
        ("#2E7D4F", "Verde"), ("#E8A33D", "Mostarda"), ("#7A4FB5", "Roxo"), ("#E58FB1", "Rosa"),
    ]

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 6) {
                PersonagemPrevia(comFones: comFones)
                    .frame(width: 110, height: 110)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                Toggle("Com fones", isOn: $comFones).toggleStyle(.switch).controlSize(.mini)
                    .font(.system(size: 11))
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("Nome").frame(width: 70, alignment: .leading)
                    TextField("Homie", text: $state.nomePersonagem).textFieldStyle(.roundedBorder)
                }
                linha("Cor") { amostras(Self.coresCorpo, selecionada: $state.corPersonagem) }
                Divider()
                linha("Boné") { Toggle("", isOn: $state.bonePersonagem).labelsHidden().toggleStyle(.switch).controlSize(.small) }
                if state.bonePersonagem {
                    linha("Cor do boné") { amostras(Self.coresBone, selecionada: $state.corBone) }
                }
                Divider()
                linha("Fones") {
                    Picker("", selection: $state.fonesIntra) {
                        Text("AirPods Pro").tag(true); Text("AirPods Max").tag(false)
                    }.labelsHidden().pickerStyle(.segmented).frame(width: 200)
                }
                if !state.fonesIntra {
                    linha("Cor dos fones") {
                        Picker("", selection: $state.fonesPrata) {
                            Text("Cinza-espacial").tag(false); Text("Prata").tag(true)
                        }.labelsHidden().pickerStyle(.segmented).frame(width: 200)
                    }
                }
                Divider()
                linha("Detalhes") {
                    HStack(spacing: 14) {
                        Toggle("Sobrancelhas", isOn: $state.sobrancelhas)
                        Toggle("Contorno", isOn: $state.contornoPersonagem)
                    }
                    .toggleStyle(.checkbox).font(.system(size: 12))
                }
            }
        }
    }

    private func linha<C: View>(_ titulo: String, @ViewBuilder _ c: () -> C) -> some View {
        HStack(spacing: 8) {
            Text(titulo).font(.system(size: 12)).foregroundColor(.secondary).frame(width: 70, alignment: .leading)
            c()
            Spacer(minLength: 0)
        }
    }

    private func amostras(_ cores: [(String, String)], selecionada: Binding<String>) -> some View {
        HStack(spacing: 6) {
            ForEach(cores, id: \.0) { hex, nome in
                let cor = hex.isEmpty ? Color(red: 0.93, green: 0.93, blue: 0.94) : Color(hex: hex)
                Button { selecionada.wrappedValue = hex } label: {
                    Circle().fill(cor).frame(width: 18, height: 18)
                        .overlay(Circle().stroke(Color.primary.opacity(0.25), lineWidth: 0.5))
                        .overlay(Circle().stroke(Color.accentColor, lineWidth: 2).padding(-3)
                                    .opacity(selecionada.wrappedValue == hex ? 1 : 0))
                }
                .buttonStyle(.plain)
                .help(nome)
            }
        }
    }
}

/// O personagem de verdade (mesmo desenho da ilha), parado, para ver as escolhas.
struct PersonagemPrevia: View {
    let comFones: Bool
    @StateObject private var engine = BotEngine()

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                engine.headphonesOn = comFones
                engine.update(dt: 1.0 / 60)
                engine.drawHandsBehind(context: ctx, size: size)
                engine.draw(context: ctx, size: size)
                engine.drawHandsAndExtras(context: ctx, size: size)
            }
        }
        .onAppear { engine.setState(.idle, force: true) }
    }
}
