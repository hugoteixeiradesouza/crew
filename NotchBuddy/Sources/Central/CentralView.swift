import SwiftUI

// A janela de Ajustes do Crew: só configuração — docs/ARQUITETURA.md §1:
//   Crew         o que vale para tudo: início, permissões do macOS, atalhos globais, contas e chaves
//   Ilha         o Homie e o notch: aparência, tempos, o que aparece nele
//   App          a janela onde se trabalha: sessões, navegador, atalhos dela
//   e uma página por módulo, agrupadas pelos seis setores do app (Comando, Mesa, Estúdio,
//   Máquina, Dia, Conexões), todas no mesmo formato.
// As telas de trabalho (sessões e a tela de cada ferramenta) moram no app do Crew
// (`AppCrewView`, `Central/Setores/`), não aqui.

enum PaginaCentral: Hashable {
    /// A página "Crew" (o nome do caso é o antigo, "Geral").
    case geral
    case ilha
    case app
    case modulo(String)
}

extension Notification.Name {
    /// Abre a Central. `object`: id do módulo (String) para abrir direto na página dele.
    static let abrirCentral = Notification.Name("crew.abrirCentral")
}

@MainActor
enum Central {
    /// Abre um módulo: a tela de trabalho dele, no setor dele do app; se ele não tem tela (ou
    /// sem módulo), a janela de Ajustes. Só a configuração: `Central.ajustes(modulo:)`.
    static func abrir(modulo: String? = nil) {
        NotificationCenter.default.post(name: .abrirCentral, object: modulo)
    }
    /// Abre o app do Crew na página de Sessões.
    static func abrirSessoes() { JanelaCrew.shared.abrir() }
}

struct CentralView: View {
    @ObservedObject private var registro = Registro.shared
    @ObservedObject private var state = AppState.shared
    @State private var pagina: PaginaCentral?

    init(pagina inicial: PaginaCentral = .geral) {
        _pagina = State(initialValue: inicial)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $pagina) {
                Section("Crew") {
                    Label("Crew", systemImage: "gearshape").tag(PaginaCentral.geral)
                    Label("Ilha", systemImage: Superficie.ilha.icone).tag(PaginaCentral.ilha)
                    Label("App", systemImage: Superficie.app.icone).tag(PaginaCentral.app)
                }
                ForEach(Setor.allCases) { setor in
                    let lista = registro.doSetor(setor)
                    if !lista.isEmpty {
                        Section(setor.nome) {
                            ForEach(lista, id: \.id) { m in
                                Label(m.nome, systemImage: m.icone)
                                    .foregroundStyle(registro.estaLigado(m.id) ? .primary : .secondary)
                                    .tag(PaginaCentral.modulo(m.id))
                            }
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
        } detail: {
            switch pagina {
            case .modulo(let id):
                if let m = registro.modulo(id) { PaginaModulo(modulo: m, soAjustes: true) }
            case .ilha:
                PaginaIlha()
            case .app:
                PaginaApp()
            default:
                SettingsView()
            }
        }
        .frame(minWidth: 860, minHeight: 560)
        .onReceive(NotificationCenter.default.publisher(for: .abrirCentral)) { n in
            // Módulo com tela de trabalho abre no app (AppDelegate), não aqui.
            if let id = n.object as? String, !Setores.temTela(id) { pagina = .modulo(id) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .irParaPagina)) { n in
            if let p = n.object as? PaginaCentral { pagina = p }
        }
    }
}

/// Página de um módulo: cabeçalho com liga/desliga, a tela dele e os ajustes.
struct PaginaModulo: View {
    let modulo: any Modulo
    /// Na janela de Ajustes: sem a tela de trabalho (ela mora no setor do módulo, no app) e com
    /// o caminho para ela. As capturas e prévias usam a página inteira.
    var soAjustes = false
    @ObservedObject private var registro = Registro.shared

    var body: some View {
        let ligado = registro.estaLigado(modulo.id)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: modulo.icone)
                        .font(.system(size: 22))
                        .frame(width: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(modulo.nome).font(.system(size: 18, weight: .semibold))
                        Text(modulo.resumo).font(.system(size: 12)).foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    if modulo.podeDesligar {
                        Toggle("", isOn: Binding(get: { ligado }, set: { registro.ligar(modulo.id, $0) }))
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                }
                // Quem tem tela de trabalho num setor aparece no app, mesmo sem ter declarado.
                OndeAparece(superficies: modulo.superficies + (Setores.temTela(modulo.id) && !modulo.superficies.contains(.app) ? [.app] : []))
                if ligado && (modulo.temAba || modulo.temBloco) {
                    Secao("Na ilha", "Ao lado da câmera cabem 2 atalhos de ferramenta; todas ficam sempre na grade (botão de grade no topo da ilha). A home mostra até \(Registro.maxBlocos) blocos.") {
                        if modulo.temAba {
                            Toggle("Atalho no topo da ilha", isOn: Binding(get: { registro.abaNaIlha(modulo.id) },
                                                                            set: { registro.definirAbaNaIlha(modulo.id, $0) }))
                                .toggleStyle(.switch).controlSize(.small)
                        }
                        if modulo.temBloco {
                            Toggle("Bloco na home da ilha", isOn: Binding(get: { registro.naHome(modulo) },
                                                                          set: { registro.definirNaHome(modulo.id, $0) }))
                                .toggleStyle(.switch).controlSize(.small)
                        }
                    }
                }
                if soAjustes, Setores.temTela(modulo.id) {
                    Secao("Tela de trabalho", "Esta página é só configuração. O que a ferramenta mostra e faz fica no app do Crew, no setor \(modulo.setor.nome).") {
                        Button("Abrir \(modulo.nome) em \(modulo.setor.nome)") { Central.abrir(modulo: modulo.id) }
                    }
                }
                if ligado {
                    if !soAjustes, let tela = modulo.central() { tela }
                    if let aj = modulo.ajustes() {
                        Secao("Ajustes", nil) { aj }
                    }
                } else {
                    Text("Desligada: não aparece em lugar nenhum e não gasta nada.")
                        .font(.system(size: 12)).foregroundColor(.secondary)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .id(modulo.id)
    }
}

/// A linha "Onde aparece" de uma ferramenta: as quatro superfícies, acesas as que ela usa.
struct OndeAparece: View {
    let superficies: [Superficie]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Onde aparece").font(.system(size: 12, weight: .semibold))
                ForEach(Superficie.allCases) { s in
                    let usa = superficies.contains(s)
                    Label(s.rawValue, systemImage: s.icone)
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .foregroundStyle(usa ? Color.accentColor : Color.secondary.opacity(0.6))
                        .background((usa ? Color.accentColor : Color.primary).opacity(usa ? 0.12 : 0.04))
                        .clipShape(Capsule())
                        .help(usa ? s.explicacao : "Esta ferramenta não usa: \(s.rawValue).")
                }
            }
            Text(superficies.isEmpty
                 ? "Sem lugar na ilha: é gestão eventual, pela tela dela no app ou só por estes Ajustes."
                 : superficies.map(\.explicacao).joined(separator: " "))
                .font(.system(size: 11)).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
