import SwiftUI

// Sessões do Claude Code: o coração do Crew (aprovações, perguntas, chat). Sempre ligado.
// A aba (visão geral e chat) continua fixa no cabeçalho da ilha.

@MainActor
final class SessoesModulo: Modulo {
    static let shared = SessoesModulo()

    let id = "sessoes"
    let nome = "Claude Code"
    let icone = "terminal"
    let pilar = Pilar.ia
    let superficies: [Superficie] = [.ilha, .app]
    let resumo = "As sessões do Claude Code na ilha: o que cada uma está fazendo, aprovações, perguntas e chat."
    var podeDesligar: Bool { false }

    func ajustes() -> AnyView? { AnyView(HooksAjustes()) }
}

/// Instalar/atualizar/remover os hooks no ~/.claude/settings.json — sempre mostrando o que muda
/// e gravando só depois da confirmação (veio dos Ajustes gerais).
struct HooksAjustes: View {
    @State private var precisaAtualizar = HookServer.hooksNeedUpdate()
    @State private var mostrandoDiff = false
    @State private var jsonPendente = ""
    @State private var mensagem = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Hooks que ligam as sessões ao Crew. Só mexem no ~/.claude/settings.json depois de você confirmar.")
                .font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            if precisaAtualizar {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                    Text("Hook desatualizado — atualize para as aprovações funcionarem")
                        .font(.system(size: 11)).foregroundColor(.orange)
                }
                Button("Atualizar hooks") { preparar() }
            }
            Text("nb-hook : \(HookServer.hookScriptPath)")
                .font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary)
            HStack(spacing: 10) {
                Button("Instalar hooks") { preparar() }.buttonStyle(.borderedProminent)
                Button("Remover") { remover() }.buttonStyle(.bordered)
            }
            if mostrandoDiff {
                ScrollView {
                    Text(jsonPendente)
                        .font(.system(size: 10, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 140)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)
                HStack {
                    Button("Confirmar e gravar") { gravar() }.buttonStyle(.borderedProminent)
                    Button("Cancelar") { mostrandoDiff = false; jsonPendente = "" }.buttonStyle(.bordered)
                }
            }
            if !mensagem.isEmpty {
                Text(mensagem).font(.system(size: 11))
                    .foregroundColor(mensagem.hasPrefix("Erro") ? .red : .secondary)
            }
        }
    }

    private func preparar() {
        do {
            jsonPendente = try HookServer.shared.previewClaudeHooks()
            mostrandoDiff = true
            mensagem = "Confira o JSON abaixo antes de confirmar."
        } catch { mensagem = "Erro: \(error.localizedDescription)" }
    }

    private func gravar() {
        do {
            try HookServer.shared.writeClaudeHooks()
            mostrandoDiff = false
            jsonPendente = ""
            precisaAtualizar = false
            mensagem = "Hooks instalados no ~/.claude/settings.json."
        } catch { mensagem = "Erro ao gravar: \(error.localizedDescription)" }
    }

    private func remover() {
        do {
            try HookServer.shared.uninstallClaudeHooks()
            mensagem = "Hooks removidos."
        } catch { mensagem = "Erro: \(error.localizedDescription)" }
    }
}
