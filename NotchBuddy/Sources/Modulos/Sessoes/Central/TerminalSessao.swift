import SwiftUI
import AppKit
@preconcurrency import SwiftTerm

// O terminal do app do Crew: um terminal de verdade (emulador SwiftTerm, MIT), em dois usos.
// - Com `pasta`: um shell novo na pasta da sessão, para o Hugo rodar os comandos dele — é o
//   botão "Terminal". Mora num tmux próprio (`crewsh-<id>`), então fechar o painel ou o Crew
//   não mata o que estiver rodando; some quando a sessão sai da lista.
// - Sem `pasta`: o terminal da própria sessão do motor do Crew (`tmux attach` em `crew-<id>`),
//   para o que o Claude Code pergunta só lá (confiar na pasta, login, menus de comando).
// Fechar o painel só solta este cliente do tmux.
// Nada de leitura periódica: o terminal só trabalha quando o tmux manda algo.

struct TerminalSessao: View {
    let sessionId: String
    /// Pasta do shell novo. nil = o terminal da própria sessão do Claude Code.
    var pasta: String? = nil

    /// Nome do tmux do shell do Hugo nesta sessão.
    static func nomeDoShell(_ sessionId: String) -> String { "crewsh-" + sessionId }

    /// A sessão saiu da lista: o shell dela fecha junto (sem deixar processo órfão).
    static func encerrarShell(_ sessionId: String) {
        guard let tmux = MotorCrew.tmux else { return }
        Task.detached { _ = await Processo.rodar(tmux, ["kill-session", "-t", nomeDoShell(sessionId)], tempoMax: 5) }
    }

    /// O tmux da sessão não responde mais (ela fechou).
    @State private var fechada = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Circle().fill(Color(hex: "#FF5F57")).frame(width: 8, height: 8)
                    Circle().fill(Color(hex: "#FEBC2E")).frame(width: 8, height: 8)
                    Circle().fill(Color(hex: "#28C840")).frame(width: 8, height: 8)
                }
                .opacity(0.55)
                Text(pasta.map { "Terminal · " + URL(fileURLWithPath: $0).lastPathComponent } ?? "Terminal da sessão")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Tema.texto2)
                Spacer()
                if !fechada {
                    HStack(spacing: 5) {
                        Circle().fill(Tema.verde).frame(width: 5, height: 5)
                        Text("ao vivo").font(.system(size: 11)).foregroundStyle(Tema.texto3)
                    }
                    .help(pasta != nil ? "Um shell seu, na pasta da sessão. A roda do mouse rola o histórico."
                          : "Clique no terminal e digite: é o Claude Code da sessão. A roda do mouse rola o histórico.")
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 34)
            Fio()
            conteudo
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(RoundedRectangle(cornerRadius: Tema.raioCartao, style: .continuous).fill(Color(hex: "#0D0D10")))
        .overlay(RoundedRectangle(cornerRadius: Tema.raioCartao, style: .continuous).strokeBorder(Tema.borda))
        .clipShape(RoundedRectangle(cornerRadius: Tema.raioCartao, style: .continuous))
    }

    @ViewBuilder
    private var conteudo: some View {
        if CaptureTool.ativo {
            // Capturas: nenhum processo é aberto; só a tela de exemplo.
            Text(Self.exemplo)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(Color(hex: "#C9CDD4"))
                .lineSpacing(2)
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if fechada {
            VStack(spacing: 4) {
                Text(pasta != nil ? "O terminal fechou." : "O terminal dessa sessão fechou.")
                    .font(.system(size: 12.5, weight: .medium)).foregroundStyle(Tema.texto2)
                if pasta != nil {
                    BotaoPilula(titulo: "Abrir de novo", icone: "arrow.clockwise", altura: 28) { fechada = false }
                        .padding(.top, 6)
                } else {
                    Text("A conversa continua salva e dá para retomar.").font(.system(size: 11.5)).foregroundStyle(Tema.texto3)
                }
            }
            .multilineTextAlignment(.center)
            .padding(20)
        } else {
            TerminalVivo(sessionId: sessionId, pasta: pasta) { fechada = true }
                .padding(.horizontal, 8).padding(.vertical, 6)
                .id(sessionId + (pasta ?? ""))
        }
    }

    /// Tela de exemplo das capturas: a pergunta que os hooks não avisam.
    static let exemplo = """
    ╭──────────────────────────────────────────────────────────────────────────────╮
    │ Accessing workspace:                                                         │
    │                                                                              │
    │ /Users/hugo/dev/motion                                                       │
    │                                                                              │
    │ Quick safety check: Is this a project you created or one you trust?          │
    │ Claude Code will be able to read, edit, and execute files here.              │
    │                                                                              │
    │ ❯ 1. Yes, I trust this folder                                                │
    │   2. No, exit                                                                │
    │                                                                              │
    │ Enter to confirm · Esc to cancel                                             │
    ╰──────────────────────────────────────────────────────────────────────────────╯
    """
}


/// O emulador de terminal, com um `tmux attach` na sessão por baixo.
private struct TerminalVivo: NSViewRepresentable {
    let sessionId: String
    var pasta: String? = nil
    let aoFechar: @MainActor () -> Void

    /// Recebe os avisos do terminal; o único que interessa é o processo ter acabado.
    final class Dono: LocalProcessTerminalViewDelegate {
        let aoFechar: @MainActor () -> Void
        let roda = RodaDoTerminal()
        init(aoFechar: @escaping @MainActor () -> Void) { self.aoFechar = aoFechar }

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func processTerminated(source: TerminalView, exitCode: Int32?) {
            let avisar = aoFechar
            Task { @MainActor in avisar() }
        }
    }

    func makeCoordinator() -> Dono { Dono(aoFechar: aoFechar) }

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let v = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 640, height: 400))
        v.processDelegate = context.coordinator
        v.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        v.nativeBackgroundColor = NSColor(Color(hex: "#0D0D10"))
        v.nativeForegroundColor = NSColor(Color(hex: "#D5D8DD"))
        v.caretColor = NSColor(Tema.azul)
        v.selectedTextBackgroundColor = NSColor(Tema.azul).withAlphaComponent(0.35)
        var ambiente = Terminal.getEnvironmentVariables(termName: "xterm-256color")
        ambiente.append("PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin")
        if let pasta {
            // Shell do Hugo na pasta da sessão. Com tmux: `new-session -A` cria ou volta ao mesmo
            // shell (o que estava rodando continua lá). Sem tmux: um zsh de login simples.
            if let tmux = MotorCrew.tmux {
                let nome = TerminalSessao.nomeDoShell(sessionId)
                v.startProcess(executable: tmux,
                               args: ["new-session", "-A", "-s", nome, "-c", pasta, ";",
                                      "set-option", "-t", nome, "status", "off", ";",
                                      "set-option", "-t", nome, "mouse", "on"],
                               environment: ambiente)
                context.coordinator.roda.vigiar(v)
            } else {
                v.startProcess(executable: "/bin/zsh", args: ["-l"], environment: ambiente, currentDirectory: pasta)
            }
            return v
        }
        guard let tmux = MotorCrew.tmux else { return v }
        // `set-option` não aceita o "=" de nome exato (responde "no such session" e derruba a
        // fila de comandos inteira); o nome completo, com o id da sessão, já é único.
        let nome = MotorCrew.nomeTmux(sessionId)
        let alvo = "=" + nome
        // Sem a barra verde do tmux e com a roda do mouse rolando o histórico — só nesta sessão
        // (opções da sessão do Crew; o tmux do Hugo fora dela não muda).
        v.startProcess(executable: tmux,
                       args: ["set-option", "-t", nome, "status", "off", ";",
                              "set-option", "-t", nome, "mouse", "on", ";",
                              "attach-session", "-t", alvo],
                       environment: ambiente)
        context.coordinator.roda.vigiar(v)
        return v
    }

    func updateNSView(_ v: LocalProcessTerminalView, context: Context) {}

    /// Saiu da tela: solta o cliente do tmux (a sessão continua).
    static func dismantleNSView(_ v: LocalProcessTerminalView, coordinator: Dono) {
        coordinator.roda.parar()
        v.terminate()
    }
}

/// A roda do mouse (e os dois dedos no trackpad) no terminal. O emulador só rola o histórico
/// dele, e com o tmux por baixo não há histórico ali: a tela é do tmux. Aqui a roda vira o
/// aviso de roda que o tmux entende (`mouse on`): ele rola o histórico da sessão para cima e,
/// de volta ao fim, sai sozinho da rolagem. Programa que usa o mouse (o próprio Claude Code em
/// tela cheia) recebe a roda do tmux.
@MainActor
final class RodaDoTerminal {
    private var vigia: Any?
    private var acumulado: CGFloat = 0

    nonisolated init() {}

    func vigiar(_ v: LocalProcessTerminalView) {
        guard vigia == nil else { return }
        vigia = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self, weak v] evento in
            let delta = evento.scrollingDeltaY, preciso = evento.hasPreciseScrollingDeltas
            let lugar = evento.locationInWindow
            let janela = evento.window
            let engoliu: Bool = MainActor.assumeIsolated {
                guard let self, let v, janela === v.window, delta != 0 else { return false }
                return self.rolar(v, delta: delta, preciso: preciso, lugar: lugar)
            }
            return engoliu ? nil : evento
        }
    }

    /// Manda a roda ao tmux. Devolve false se o mouse não está em cima do terminal.
    private func rolar(_ v: LocalProcessTerminalView, delta: CGFloat, preciso: Bool, lugar: NSPoint) -> Bool {
        let ponto = v.convert(lugar, from: nil)
        guard v.bounds.contains(ponto) else { return false }
        // Trackpad manda pontos; roda de mouse, estalos. Um passo do tmux são umas 5 linhas.
        acumulado += preciso ? delta / 28 : delta
        let passos = Int(acumulado)
        guard passos != 0 else { return true }
        acumulado -= CGFloat(passos)
        let t = v.getTerminal()
        let coluna = min(max(Int(ponto.x / max(v.bounds.width / CGFloat(max(t.cols, 1)), 1)) + 1, 1), max(t.cols, 1))
        let deCima = v.isFlipped ? ponto.y : v.bounds.height - ponto.y
        let linha = min(max(Int(deCima / max(v.bounds.height / CGFloat(max(t.rows, 1)), 1)) + 1, 1), max(t.rows, 1))
        // 64 = roda para cima, 65 = para baixo (aviso de mouse no formato SGR).
        let aviso = "\u{1b}[<\(passos > 0 ? 64 : 65);\(coluna);\(linha)M"
        for _ in 0..<min(abs(passos), 6) { v.send(txt: aviso) }
        return true
    }

    func parar() {
        if let vigia { NSEvent.removeMonitor(vigia) }
        vigia = nil
    }
}
