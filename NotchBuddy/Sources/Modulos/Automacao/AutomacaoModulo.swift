import SwiftUI

// Automação: o Crew controlável de fora — endereços crew:// e servidor MCP para o Claude Code.

@MainActor
final class AutomacaoModulo: Modulo {
    static let shared = AutomacaoModulo()

    let id = "automacao"
    let nome = "Automação"
    let icone = "point.3.connected.trianglepath.dotted"
    let pilar = Pilar.ia
    let superficies: [Superficie] = [.claude]
    let resumo = "Endereços crew:// e o servidor MCP: o Claude Code consulta o Mac, avisa você no notch e abre telas do Crew."

    func iniciar() { ServidorMCP.instalarScript() }
    func central() -> AnyView? { AnyView(AutomacaoCentral()) }
}

struct AutomacaoCentral: View {
    @State private var registrado: Bool?
    @State private var confirmando = false
    @State private var mensagem = ""
    @State private var trabalhando = false

    private var claude: String? {
        ["/opt/homebrew/bin/claude", "/usr/local/bin/claude",
         FileManager.default.homeDirectoryForCurrentUser.path + "/.local/bin/claude",
         FileManager.default.homeDirectoryForCurrentUser.path + "/.claude/local/claude"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private var comando: String { "claude mcp add --scope user crew -- /usr/bin/python3 \"\(ServidorMCP.caminho)\"" }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Secao("Servidor MCP para o Claude Code",
                  "Com ele, qualquer sessão do Claude Code pode ver o estado do Mac, as sessões abertas no Crew, avisar você no notch e abrir telas do Crew. Nada que apague ou mude arquivos.") {
                HStack(spacing: 8) {
                    Circle().fill(registrado == true ? Color.green : Color.secondary.opacity(0.4)).frame(width: 8, height: 8)
                    Text(registrado == nil ? "Conferindo…" : registrado! ? "Registrado no Claude Code (todas as sessões novas)" : "Não registrado")
                        .font(.system(size: 12))
                }
                Text("Ferramentas: estado_do_mac · sessoes_abertas · avisar_no_notch · abrir_no_crew · videos · video_criar · video_renderizar")
                    .font(.system(size: 11)).foregroundColor(.secondary)
                if claude == nil {
                    Text("Não achei o comando `claude` neste Mac.").font(.system(size: 11)).foregroundColor(.orange)
                } else if registrado == false {
                    Button("Registrar no Claude Code…") { confirmando = true }.disabled(trabalhando)
                } else if registrado == true {
                    Button("Remover do Claude Code") { remover() }.disabled(trabalhando)
                }
                if confirmando {
                    Text("Isto roda o comando abaixo, que acrescenta o servidor \"crew\" na sua configuração do Claude Code (~/.claude.json). Para desfazer: o botão Remover.")
                        .font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                    Text(comando).font(.system(size: 10.5, design: .monospaced)).textSelection(.enabled)
                        .padding(8).background(Color.primary.opacity(0.05)).cornerRadius(6)
                    HStack {
                        Button("Confirmar e registrar") { registrar() }.buttonStyle(.borderedProminent)
                        Button("Cancelar") { confirmando = false }
                    }
                }
                if !mensagem.isEmpty {
                    Text(mensagem).font(.system(size: 11)).foregroundColor(mensagem.hasPrefix("Erro") ? .red : .secondary)
                }
            }
            Secao("Endereços crew://", "Para Atalhos do macOS, scripts e o terminal (`open \"crew://…\"`). Nada destrutivo por endereço.") {
                ForEach(["crew://ilha  ·  crew://ilha/sistema", "crew://central  ·  crew://central/disco",
                         "crew://sistema/indicador?tipo=cpu|memoria|temperatura|nenhum"], id: \.self) {
                    Text($0).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                }
            }
        }
        .task { await conferir() }
    }

    private func conferir() async {
        guard let claude else { registrado = false; return }
        let r = await Processo.rodar(claude, ["mcp", "get", "crew"], tempoMax: 20)
        registrado = r.ok
    }

    private func registrar() {
        guard let claude else { return }
        trabalhando = true; confirmando = false
        ServidorMCP.instalarScript()
        Task {
            let r = await Processo.rodar(claude, ["mcp", "add", "--scope", "user", "crew", "--", "/usr/bin/python3", ServidorMCP.caminho], tempoMax: 30)
            mensagem = r.ok ? "Registrado. Vale para as sessões do Claude Code abertas daqui em diante." : "Erro: \(r.erro.isEmpty ? r.saida : r.erro)"
            trabalhando = false
            await conferir()
        }
    }

    private func remover() {
        guard let claude else { return }
        trabalhando = true
        Task {
            let r = await Processo.rodar(claude, ["mcp", "remove", "--scope", "user", "crew"], tempoMax: 30)
            mensagem = r.ok ? "Removido." : "Erro: \(r.erro.isEmpty ? r.saida : r.erro)"
            trabalhando = false
            await conferir()
        }
    }
}
