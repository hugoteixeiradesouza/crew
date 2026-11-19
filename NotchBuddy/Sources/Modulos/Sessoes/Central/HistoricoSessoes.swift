import SwiftUI
import AppKit

// Histórico do app do Crew: as sessões que saíram da lista — as que o próprio Crew guardou
// (`HistoricoCrew`: motor do Crew, terminal, qualquer origem) mais as que o Xirp guarda —,
// a conversa delas só para leitura e "Retomar": as do Xirp reabrem lá (`session:resume`, o
// mesmo pedido que a janela do Xirp faz); as outras, no motor do Crew (`claude --resume`).

struct SessaoGuardada: Identifiable, Hashable {
    let id: String              // id no Xirp
    let cliSessionId: String    // session_id do Claude Code
    let nome: String
    let projectId: String?
    let pasta: String?
    let branch: String?
    let status: String
    let ultimaAtividade: Date?
    /// Guardada pelo Crew (não está no Xirp): retoma no motor do Crew.
    var doCrew = false
    /// Caminho do transcript, quando já se sabe.
    var caminhoTranscript: String? = nil

    init(id: String, cliSessionId: String, nome: String, projectId: String?, pasta: String?, branch: String?,
         status: String, ultimaAtividade: Date?, doCrew: Bool = false, caminhoTranscript: String? = nil) {
        self.id = id; self.cliSessionId = cliSessionId; self.nome = nome; self.projectId = projectId
        self.pasta = pasta; self.branch = branch; self.status = status; self.ultimaAtividade = ultimaAtividade
        self.doCrew = doCrew; self.caminhoTranscript = caminhoTranscript
    }

    init(_ e: SessaoEncerrada) {
        self.init(id: "crew:" + e.sessionId, cliSessionId: e.sessionId, nome: e.nome, projectId: nil,
                  pasta: e.pasta, branch: e.branch, status: "completed", ultimaAtividade: e.quando,
                  doCrew: true, caminhoTranscript: e.transcript)
    }

    var statusLegivel: String {
        switch status {
        case "completed": return "encerrada"
        case "failed": return "falhou"
        case "paused": return "pausada"
        case "idle": return "parada"
        case "running": return "rodando"
        case "waiting": return "esperando"
        default: return status
        }
    }

    /// Transcript do Claude Code: ~/.claude/projects/<pasta com "/" e "." virando "-">/<id>.jsonl.
    var transcript: String? {
        if let c = caminhoTranscript, FileManager.default.fileExists(atPath: c) { return c }
        let base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
        if let pasta {
            let chave = pasta.replacingOccurrences(of: "[^A-Za-z0-9]", with: "-", options: .regularExpression)
            let p = base.appendingPathComponent(chave).appendingPathComponent(cliSessionId + ".jsonl").path
            if FileManager.default.fileExists(atPath: p) { return p }
        }
        // Reserva: procura o arquivo em todas as pastas de projeto.
        let dirs = (try? FileManager.default.contentsOfDirectory(atPath: base.path)) ?? []
        return dirs.lazy.map { base.appendingPathComponent($0).appendingPathComponent(cliSessionId + ".jsonl").path }
            .first { FileManager.default.fileExists(atPath: $0) }
    }
}

extension Xirp {
    /// Sessões guardadas no Xirp, da mais recente para a mais antiga.
    static func historico(limite: Int = 300) async -> [SessaoGuardada] {
        let (out, code) = await run(["session", "list", "--all", "--limit", String(limite), "--json"])
        guard code == 0, let lista = try? JSONSerialization.jsonObject(with: Data(out.utf8)) as? [[String: Any]] else { return [] }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return lista.compactMap { s in
            guard let id = s["id"] as? String, let cli = s["cliSessionId"] as? String else { return nil }
            return SessaoGuardada(
                id: id, cliSessionId: cli,
                nome: (s["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Sem nome",
                projectId: s["projectId"] as? String,
                pasta: s["worktreePath"] as? String,
                branch: s["branch"] as? String,
                status: s["status"] as? String ?? "",
                ultimaAtividade: (s["lastActivityAt"] as? String).flatMap { iso.date(from: $0) })
        }
        .sorted { ($0.ultimaAtividade ?? .distantPast) > ($1.ultimaAtividade ?? .distantPast) }
    }

    /// Reabre a sessão no Xirp, na mesma conversa. nil = ok; senão, o erro.
    static func retomar(_ s: SessaoGuardada) async -> String? {
        var args = ["api", "send", "session:resume", "--param", "sessionId=\(s.id)",
                    "--param", "cliSessionId=\(s.cliSessionId)", "--timeout", "30000"]
        if let p = s.projectId { args += ["--param", "projectId=\(p)"] }
        if let w = s.pasta { args += ["--param", "worktreePath=\(w)"] }
        let (out, code) = await run(args)
        return code == 0 ? nil : out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension SessaoGuardada {
    /// Sessões de exemplo das capturas (`Crew --capturas`): nada é lido do Xirp.
    static var exemplos: [SessaoGuardada] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        func s(_ n: Int, _ nome: String, _ pasta: String, _ branch: String?, _ status: String, _ horas: Double) -> SessaoGuardada {
            SessaoGuardada(id: "guardada\(n)", cliSessionId: "guardada-cli\(n)", nome: nome, projectId: nil,
                           pasta: home + pasta, branch: branch, status: status,
                           ultimaAtividade: Date().addingTimeInterval(-horas * 3600))
        }
        return [
            s(1, "Sessões separadas no notch", "/dev/crew", "feat/sessoes", "completed", 3),
            s(2, "Aviso de bateria na ilha", "/dev/crew", "feat/bateria", "completed", 26),
            s(3, "Conferência de notas de entrada", "/dev/loja", "main", "idle", 30),
            s(4, "Relatório de vendas por produto", "/dev/loja", "main", "failed", 52),
            s(5, "Limpeza de worktrees antigas", "/dev", nil, "completed", 120),
        ]
    }
}

/// Lista do histórico (barra lateral, aba "Histórico").
struct ListaHistorico: View {
    let busca: String
    @Binding var selecionada: SessaoGuardada?
    /// As que o Xirp guarda.
    @State private var sessoes: [SessaoGuardada] = []
    @State private var carregando = true
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var proprio = HistoricoCrew.shared

    /// Xirp + as que o Crew guardou (sem repetir a mesma conversa), da mais recente para a mais antiga.
    private var todas: [SessaoGuardada] {
        if CaptureTool.ativo { return sessoes }
        let noXirp = Set(sessoes.map(\.cliSessionId))
        let doCrew = proprio.lista.filter { !noXirp.contains($0.sessionId) }.map(SessaoGuardada.init)
        return (sessoes + doCrew).sorted { ($0.ultimaAtividade ?? .distantPast) > ($1.ultimaAtividade ?? .distantPast) }
    }

    /// As que estão vivas aparecem em "Sessões"; aqui ficam as guardadas.
    private var visiveis: [SessaoGuardada] {
        let vivas = Set(state.tasks.compactMap(\.sessionId))
        let q = busca.trimmingCharacters(in: .whitespaces).lowercased()
        return todas.filter { s in
            !vivas.contains(s.cliSessionId)
                && (q.isEmpty || [s.nome, s.pasta ?? "", s.branch ?? ""].contains { $0.lowercased().contains(q) })
        }
    }

    var body: some View {
        Group {
            if carregando && todas.isEmpty {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if visiveis.isEmpty {
                VaziaLateral(icone: busca.isEmpty ? "clock.arrow.circlepath" : "magnifyingglass",
                             texto: busca.isEmpty ? "Nenhuma sessão guardada." : "Nada com esse filtro.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(visiveis) { s in
                            LinhaGuardada(sessao: s, escolhida: selecionada?.id == s.id) { selecionada = s }
                                .menuContexto { menu(s) }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 2).padding(.bottom, 12)
                }
                .scrollIndicators(.never)
            }
        }
        // Sessão encerrada com o histórico na tela: a lista do Xirp é relida.
        .task(id: state.tasks.count) { await carregar() }
    }

    private func menu(_ s: SessaoGuardada) -> [ItemMenu] {
        var itens: [ItemMenu] = []
        if let t = s.transcript {
            itens.append(.acao("Mostrar o transcript", icone: "doc.text") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: t)])
            })
        }
        itens.append(.acao("Copiar comando para retomar", icone: "terminal") {
            let cmd = "cd \(MenuSessao.aspas(s.pasta ?? "~")) && claude --resume \(s.cliSessionId)"
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(cmd, forType: .string)
        })
        if s.doCrew {
            itens += [.divisor, .acao("Tirar do histórico", icone: "minus.circle", detalhe: "a conversa continua no disco",
                                      destrutivo: true) {
                if selecionada?.id == s.id { selecionada = nil }
                HistoricoCrew.shared.tirar(s.cliSessionId)
            }]
        }
        return itens
    }

    private func carregar() async {
        if CaptureTool.ativo {
            sessoes = SessaoGuardada.exemplos
            carregando = false
            return
        }
        guard Xirp.available else { carregando = false; return }
        if sessoes.isEmpty { carregando = true }
        sessoes = await Xirp.historico()
        carregando = false
    }
}

/// Uma sessão guardada na barra lateral: nome, quando, projeto, branch e como terminou.
private struct LinhaGuardada: View {
    let sessao: SessaoGuardada
    let escolhida: Bool
    let acao: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: acao) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(sessao.nome)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Tema.texto)
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    if let d = sessao.ultimaAtividade {
                        Text(SessoesCrew.haQuanto(d)).font(.system(size: 10.5)).foregroundStyle(Tema.texto3)
                    }
                }
                HStack(spacing: 5) {
                    Circle().fill(Color(hex: Projetos.cor(de: sessao.pasta) ?? "#9398A1")).frame(width: 6, height: 6)
                    Text(Projetos.nome(de: sessao.pasta) ?? "—").foregroundStyle(Tema.texto2)
                    if let b = sessao.branch { Text("· \(b)").truncationMode(.middle) }
                    Text("· \(sessao.statusLegivel)")
                        .foregroundStyle(sessao.status == "failed" ? Tema.vermelho.opacity(0.85) : Tema.texto3)
                }
                .font(.system(size: 11))
                .foregroundStyle(Tema.texto3)
                .lineLimit(1)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Tema.raioLinha, style: .continuous)
                .fill(escolhida ? Tema.selecao : hover ? Tema.hover : .clear))
            .contentShape(RoundedRectangle(cornerRadius: Tema.raioLinha))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// Uma sessão guardada: a conversa (só leitura) e "Retomar".
struct ConversaGuardadaCrew: View {
    @Environment(\.recuoTitulo) private var recuoTitulo
    let sessao: SessaoGuardada
    /// Retomou: a barra volta para "Sessões" e abre a sessão quando ela chegar pelos hooks.
    let aoRetomar: (String) -> Void
    @State private var mensagens: [SessionMessage] = []
    @State private var leu = false
    @State private var caminho: String?
    @State private var retomando = false
    @State private var erro: String?

    var body: some View {
        VStack(spacing: 0) {
            cabecalho.padding(.leading, recuoTitulo)
            Fio()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 26) {
                    if mensagens.isEmpty, leu {
                        Text(caminho == nil ? "Transcript não encontrado neste Mac." : "Sem conversa para mostrar.")
                            .font(.system(size: 13))
                            .foregroundStyle(Tema.texto3)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 80)
                    }
                    ForEach(TurnoConversa.agrupar(mensagens)) { TurnoCrew(turno: $0) }
                }
                .padding(.horizontal, 12).padding(.vertical, 26)
                .frame(maxWidth: Tema.larguraConversa)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.bottom)
            .defaultScrollAnchor(.top, for: .alignment)
            .safeAreaInset(edge: .bottom, spacing: 0) { rodape }
        }
        .task(id: sessao.id) {
            let c = CaptureTool.ativo ? CaptureTool.transcript() : sessao.transcript
            caminho = c
            mensagens = await Task.detached { TranscriptReader.ler(path: c, limit: 200).mensagens }.value
            leu = true
        }
    }

    private var cabecalho: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(sessao.nome)
                    .font(Tema.titulo(15))
                    .foregroundStyle(Tema.texto)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Circle().fill(Color(hex: Projetos.cor(de: sessao.pasta) ?? "#9398A1")).frame(width: 6, height: 6)
                    Text(Projetos.nome(de: sessao.pasta) ?? "—")
                    if let b = sessao.branch {
                        Text("·").foregroundStyle(Tema.texto3)
                        Image(systemName: "arrow.triangle.branch").font(.system(size: 9))
                        Text(b).truncationMode(.middle)
                    }
                    if let d = sessao.ultimaAtividade {
                        Text("·").foregroundStyle(Tema.texto3)
                        Text(d.formatted(.dateTime.day().month().hour().minute().locale(Locale(identifier: "pt_BR"))))
                    }
                }
                .font(.system(size: 11.5))
                .foregroundStyle(Tema.texto2)
                .lineLimit(1)
                .help(sessao.pasta?.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~") ?? "")
            }
            Spacer(minLength: 12)
            PilulaEstado(texto: sessao.statusLegivel, cor: sessao.status == "failed" ? Tema.vermelho : Tema.cinza)
            if let caminho {
                BotaoIcone(icone: "doc.text", ajuda: "Mostrar o transcript no Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: caminho)])
                }
            }
        }
        .padding(.leading, 24).padding(.trailing, 14)
        .frame(height: 60)
    }

    /// Conversa guardada não aceita texto: o que dá para fazer é retomar.
    private var rodape: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Tema.texto2)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.white.opacity(0.06)))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Conversa guardada")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(Tema.texto)
                    Text("Retomar reabre o mesmo Claude Code \(peloCrew ? "no Crew" : "no Xirp"), nesta conversa e nesta pasta.")
                        .font(.system(size: 11.5)).foregroundStyle(Tema.texto3).lineLimit(1)
                }
                Spacer(minLength: 8)
                BotaoPilula(titulo: "Retomar", icone: "play.fill", estilo: .primario, altura: 34, ocupado: retomando) {
                    retomar()
                }
                .disabled(retomando)
            }
            .padding(.leading, 10).padding(.trailing, 10).padding(.vertical, 9)
            .background(FormaCampo().fill(Tema.painel))
            .overlay(FormaCampo().strokeBorder(Tema.borda))
            .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
            if let erro {
                Text(erro)
                    .font(.system(size: 11.5)).foregroundStyle(Tema.ambar).lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
            }
        }
        .frame(maxWidth: Tema.larguraConversa)
        .padding(.horizontal, 24).padding(.top, 10).padding(.bottom, 18)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(stops: [.init(color: Tema.fundo.opacity(0), location: 0),
                                   .init(color: Tema.fundo.opacity(0.94), location: 0.22),
                                   .init(color: Tema.fundo, location: 1)],
                           startPoint: .top, endPoint: .bottom)
        )
    }

    /// Retoma no motor do Crew: as que o Crew guardou, e qualquer uma quando não há Xirp.
    private var peloCrew: Bool { sessao.doCrew || !Xirp.available }

    private func retomar() {
        guard !CaptureTool.ativo else { return }
        retomando = true
        erro = nil
        Task {
            var falha: String?
            if peloCrew {
                if let pasta = sessao.pasta {
                    if case .failure(let f) = await MotorCrew.retomar(sessionId: sessao.cliSessionId, pasta: pasta) {
                        falha = f.mensagem
                    }
                } else {
                    falha = "não sei em que pasta essa sessão rodava"
                }
            } else {
                falha = await Xirp.retomar(sessao)
            }
            if let falha {
                erro = "Não foi: \(falha.prefix(200))"
            } else {
                aoRetomar(sessao.cliSessionId)
            }
            retomando = false
        }
    }
}
