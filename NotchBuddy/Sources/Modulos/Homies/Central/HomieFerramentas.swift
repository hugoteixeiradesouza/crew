import SwiftUI

// Ferramentas dos Homies, em dois lugares:
//  - no módulo (FerramentasDoModulo): conectar uma vez — catálogo curto, qualquer outro endereço
//    e o login. Fica numa pasta neutra do Crew, que nenhum Homie usa.
//  - em cada Homie (FerramentasDoHomie): só a chave de ativar/desativar o que já está conectado. Quem liga, entra e
// tira é o Claude Code (`claude mcp add/login/remove`, escopo local): o Crew não guarda
// credencial nenhuma e o login acontece no navegador.

@MainActor @Observable
final class FerramentasServico {
    static let shared = FerramentasServico()

    private(set) var ligadas: [UUID: [FerramentaLigada]] = [:]
    /// "homie/nome" → o que está acontecendo com ela agora.
    private(set) var ocupadas: [String: String] = [:]
    /// "homie/nome" → como ficou na última conferência.
    private(set) var situacoes: [String: FerramentasHomie.Situacao] = [:]
    var aviso: String?

    /// A pasta neutra onde o módulo guarda o que está conectado (e onde o login acontece).
    /// Não é um Homie: só empresta a forma para reusar as mesmas chamadas.
    let central: Homie = {
        var h = Homie()
        h.id = UUID(uuidString: "00000000-0000-0000-0000-00000000F001")!
        h.nome = "Crew"
        h.pasta = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchBuddy/ferramentas").path
        return h
    }()

    /// O que está conectado no módulo.
    var conectadas: [FerramentaLigada] { (ligadas[central.id] ?? []).filter { $0.origem == .crew } }

    /// Ativa no Homie uma ferramenta já conectada no módulo (ou desativa).
    func ativar(_ h: Homie, _ f: FerramentaLigada, _ ativa: Bool) async {
        if ativa { await ligar(h, nome: f.nome, servidor: f.servidor, entra: false) } else { await tirar(h, f.nome) }
    }

    /// Tira do módulo e de todos os Homies que a tinham ativa.
    func desconectar(_ nome: String, de homies: [Homie]) async {
        for h in homies {
            recarregar(h)
            if (ligadas[h.id] ?? []).contains(where: { $0.nome == nome && $0.origem == .crew }) { await tirar(h, nome) }
        }
        await tirar(central, nome)
    }

    private static let caminho = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:"
        + FileManager.default.homeDirectoryForCurrentUser.path + "/.local/bin"

    func chave(_ h: Homie, _ nome: String) -> String { h.id.uuidString + "/" + nome }

    private func pastas(_ h: Homie) -> [String] {
        let resolvida = URL(fileURLWithPath: h.pasta).resolvingSymlinksInPath().path
        return resolvida == h.pasta ? [h.pasta] : [h.pasta, resolvida]
    }

    private func dados(_ h: Homie) -> (claude: Data?, mcp: Data?) {
        let casa = FileManager.default.homeDirectoryForCurrentUser
        return (try? Data(contentsOf: casa.appendingPathComponent(".claude.json")),
                try? Data(contentsOf: URL(fileURLWithPath: h.pasta).appendingPathComponent(".mcp.json")))
    }

    func recarregar(_ h: Homie) {
        let d = dados(h)
        ligadas[h.id] = FerramentasHomie.ligadas(claudeJson: d.claude, mcpJson: d.mcp, pastas: pastas(h))
    }

    /// O arquivo de MCPs para a rotina deste Homie (só os dele). nil = nenhum.
    func arquivoDaRotina(_ h: Homie) -> String? {
        let d = dados(h)
        guard let json = FerramentasHomie.configDaRotina(claudeJson: d.claude, mcpJson: d.mcp, pastas: pastas(h)) else { return nil }
        let arq = URL(fileURLWithPath: h.pasta).appendingPathComponent("paginas/.ferramentas.json")
        do {
            try FileManager.default.createDirectory(at: arq.deletingLastPathComponent(), withIntermediateDirectories: true)
            try json.write(to: arq, options: .atomic)
            return arq.path
        } catch { return nil }
    }

    private func claude(_ h: Homie, _ argumentos: [String], tempoMax: TimeInterval) async -> Processo.Resultado? {
        guard let bin = MotorCrew.claude else { aviso = "Claude Code (CLI) não encontrado neste Mac."; return nil }
        try? FileManager.default.createDirectory(atPath: h.pasta, withIntermediateDirectories: true)
        // `env -C` não existe no macOS: um sh curto troca de pasta e passa os argumentos intactos.
        return await Processo.rodar("/usr/bin/env", ["PATH=" + Self.caminho, "/bin/sh", "-c", "cd \"$0\" && exec \"$@\"", h.pasta, bin] + argumentos,
                                    tempoMax: tempoMax)
    }

    private func erro(_ r: Processo.Resultado) -> String {
        let t = (r.erro.isEmpty ? r.saida : r.erro).split(whereSeparator: \.isNewline).suffix(2).joined(separator: " ")
        return r.estourouTempo ? "demorou demais e foi interrompido" : t.isEmpty ? "o Claude Code recusou" : t
    }

    func ligar(_ h: Homie, nome: String, servidor: FerramentaCatalogo.Servidor, entra: Bool) async {
        let k = chave(h, nome)
        guard ocupadas[k] == nil else { return }
        ocupadas[k] = "Conectando…"
        defer { ocupadas[k] = nil }
        aviso = nil
        guard let r = await claude(h, FerramentasHomie.argumentosLigar(nome, servidor), tempoMax: 30) else { return }
        guard r.ok else { aviso = "Não conectei \(nome): \(erro(r))"; return }
        recarregar(h)
        if entra { await entrarSemTrava(h, nome) } else { await conferirSemTrava(h, nome) }
    }

    func entrar(_ h: Homie, _ nome: String) async {
        let k = chave(h, nome)
        guard ocupadas[k] == nil else { return }
        defer { ocupadas[k] = nil }
        await entrarSemTrava(h, nome)
    }

    func conferir(_ h: Homie, _ nome: String) async {
        let k = chave(h, nome)
        guard ocupadas[k] == nil else { return }
        defer { ocupadas[k] = nil }
        await conferirSemTrava(h, nome)
    }

    func tirar(_ h: Homie, _ nome: String) async {
        let k = chave(h, nome)
        guard ocupadas[k] == nil else { return }
        ocupadas[k] = "Tirando…"
        defer { ocupadas[k] = nil }
        aviso = nil
        guard let r = await claude(h, FerramentasHomie.argumentosTirar(nome), tempoMax: 30) else { return }
        if !r.ok { aviso = "Não tirei \(nome): \(erro(r))" }
        situacoes[k] = nil
        recarregar(h)
    }

    /// O login abre no navegador e o Claude Code espera a volta (até 5 minutos).
    private func entrarSemTrava(_ h: Homie, _ nome: String) async {
        let k = chave(h, nome)
        ocupadas[k] = "Esperando o login no navegador…"
        aviso = nil
        guard let r = await claude(h, ["mcp", "login", nome], tempoMax: 300) else { return }
        if !r.ok { aviso = "O login de \(nome) não fechou: \(erro(r))" }
        await conferirSemTrava(h, nome)
    }

    private func conferirSemTrava(_ h: Homie, _ nome: String) async {
        let k = chave(h, nome)
        ocupadas[k] = "Conferindo…"
        guard let r = await claude(h, ["mcp", "get", nome], tempoMax: 60) else { return }
        situacoes[k] = FerramentasHomie.situacao(r.saida)
    }
}

struct FerramentasDoModulo: View {
    private var homie: Homie { FerramentasServico.shared.central }

    private let s = FerramentasServico.shared
    @State private var nomeNovo = ""
    @State private var enderecoNovo = ""
    @State private var tirando: FerramentaLigada?

    var body: some View {
        let ligadas = s.ligadas[homie.id] ?? []
        let nomes = Set(ligadas.map(\.nome))
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ferramentas").font(Tema.titulo(17)).foregroundStyle(Tema.texto)
                    Text("Conecte aqui uma vez; em cada Homie você ativa só o que quer que ele enxergue. O login acontece no navegador, pelo Claude Code: o Crew não guarda senha nem chave.")
                        .font(.system(size: 12.5)).foregroundStyle(Tema.texto2).fixedSize(horizontal: false, vertical: true)
                }
                if let a = s.aviso {
                    Label(a, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11.5)).foregroundStyle(Tema.ambar).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if MotorCrew.claude == nil {
                    Text("Claude Code (CLI) não encontrado neste Mac: sem ele não há como conectar.")
                        .font(.system(size: 11.5)).foregroundStyle(Tema.ambar)
                }

                if !ligadas.isEmpty {
                    secao("Conectadas")
                    cartao { ForEach(Array(ligadas.enumerated()), id: \.element.id) { i, f in
                        if i > 0 { Fio() }
                        linhaLigada(f)
                    } }
                }

                secao("Conectar")
                cartao {
                    let itens = FerramentasHomie.catalogo
                    ForEach(Array(itens.enumerated()), id: \.element.id) { i, item in
                        if i > 0 { Fio() }
                        linhaCatalogo(item, ligada: nomes.contains(item.id))
                    }
                }
                Text("Gmail, Google Agenda e Drive entram pela sua conta Claude (conectores do claude.ai): ligados lá, aparecem em todas as conversas, sem passar por terceiro. Nas rotinas só valem as ferramentas ativadas no Homie.")
                    .font(.system(size: 11.5)).foregroundStyle(Tema.texto3).fixedSize(horizontal: false, vertical: true)

                secao("Outra ferramenta")
                outra(nomes)
            }
            .padding(24)
            .frame(maxWidth: Tema.larguraConversa, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .onAppear { s.recarregar(homie) }
        .alert(tirando.map { "Desconectar \($0.nome)?" } ?? "",
               isPresented: Binding(get: { tirando != nil }, set: { if !$0 { tirando = nil } }),
               presenting: tirando) { f in
            Button("Desconectar", role: .destructive) { Task { await s.desconectar(f.nome, de: HomiesServico.shared.homies) } }
            Button("Cancelar", role: .cancel) {}
        } message: { _ in
            Text("Sai daqui e de todos os Homies que a tinham ativa. A sua conta nela continua como está.")
        }
    }

    private func secao(_ titulo: String) -> some View {
        Text(titulo.uppercased()).font(.system(size: 10.5, weight: .semibold)).tracking(0.6)
            .foregroundStyle(Tema.texto3).padding(.top, 6)
    }

    private func cartao<C: View>(@ViewBuilder _ conteudo: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0, content: conteudo)
            .background(RoundedRectangle(cornerRadius: Tema.raioCartao, style: .continuous).fill(Tema.painel))
            .overlay(RoundedRectangle(cornerRadius: Tema.raioCartao, style: .continuous).strokeBorder(Tema.borda))
    }

    private func linhaLigada(_ f: FerramentaLigada) -> some View {
        let k = s.chave(homie, f.nome)
        let ocupada = s.ocupadas[k]
        let item = FerramentasHomie.catalogo.first { $0.id == f.nome }
        return HStack(spacing: 12) {
            Image(systemName: item?.icone ?? "puzzlepiece.extension").font(.system(size: 14))
                .foregroundStyle(Tema.texto2).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(item?.nome ?? f.nome).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Tema.texto).lineLimit(1)
                Text(ocupada ?? situacao(f, k)).font(.system(size: 11.5))
                    .foregroundStyle(cor(k, ocupada != nil)).lineLimit(2).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if ocupada != nil {
                ProgressView().controlSize(.small)
            } else if f.origem == .crew {
                if f.http, s.situacoes[k] != .conectada {
                    BotaoPilula(titulo: "Entrar", icone: "person.badge.key", altura: 28) { Task { await s.entrar(homie, f.nome) } }
                        .help("Abre o login desta ferramenta no navegador")
                }
                BotaoPilula(titulo: "Conferir", estilo: .discreto, altura: 28) { Task { await s.conferir(homie, f.nome) } }
                    .help("Pergunta ao Claude Code se ela está respondendo")
                BotaoIcone(icone: "trash", ajuda: "Desconectar: sai daqui e de todos os Homies") { tirando = f }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private func situacao(_ f: FerramentaLigada, _ k: String) -> String {
                switch s.situacoes[k] {
        case .conectada: return "conectada"
        case .faltaEntrar: return "falta entrar"
        case .falhou(let m): return "não respondeu: " + m
        case nil: return f.destino
        }
    }

    private func cor(_ k: String, _ ocupada: Bool) -> Color {
        if ocupada { return Tema.azul }
        switch s.situacoes[k] {
        case .conectada: return Tema.verde
        case .faltaEntrar, .falhou: return Tema.ambar
        case nil: return Tema.texto3
        }
    }

    private func linhaCatalogo(_ item: FerramentaCatalogo, ligada: Bool) -> some View {
        let ocupada = s.ocupadas[s.chave(homie, item.id)] != nil
        return HStack(alignment: .center, spacing: 12) {
            Image(systemName: item.icone).font(.system(size: 14)).foregroundStyle(Tema.texto2).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.nome).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Tema.texto)
                Text(item.resumo).font(.system(size: 11.5)).foregroundStyle(Tema.texto3).fixedSize(horizontal: false, vertical: true)
                if let a = item.aviso {
                    Text(a).font(.system(size: 11)).foregroundStyle(Tema.ambar.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if ligada {
                Label("Conectada", systemImage: "checkmark").font(.system(size: 11.5, weight: .medium)).foregroundStyle(Tema.texto3)
            } else {
                BotaoPilula(titulo: "Conectar", icone: "plus", altura: 28, ocupado: ocupada) {
                    Task { await s.ligar(homie, nome: item.id, servidor: item.servidor, entra: item.entrada == .navegador) }
                }
                .disabled(ocupada || MotorCrew.claude == nil)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private func outra(_ nomes: Set<String>) -> some View {
        let nome = FerramentasHomie.nome(nomeNovo)
        let erroEndereco = enderecoNovo.isEmpty ? nil : FerramentasHomie.erroDoEndereco(enderecoNovo)
        let repetido = nome.map(nomes.contains) ?? false
        let pronto = nome != nil && !repetido && !enderecoNovo.isEmpty && erroEndereco == nil
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("Nome", text: $nomeNovo).textFieldStyle(.roundedBorder).frame(width: 150)
                TextField("https://… (endereço do servidor MCP)", text: $enderecoNovo).textFieldStyle(.roundedBorder)
                BotaoPilula(titulo: "Conectar", icone: "plus", altura: 28) {
                    guard let nome else { return }
                    let url = enderecoNovo.trimmingCharacters(in: .whitespacesAndNewlines)
                    nomeNovo = ""; enderecoNovo = ""
                    Task { await s.ligar(homie, nome: nome, servidor: .http(url), entra: false) }
                }
                .disabled(!pronto || MotorCrew.claude == nil)
            }
            Text(repetido ? "Já existe uma ferramenta com este nome."
                 : erroEndereco ?? "Qualquer servidor MCP por endereço. Se ele pedir login, use \"Entrar\" depois de conectar. Servidor com chave digitada ainda não entra por aqui.")
                .font(.system(size: 11.5)).foregroundStyle(repetido || erroEndereco != nil ? Tema.ambar : Tema.texto3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A aba do Homie: o que está conectado no módulo, com uma chave por ferramenta.
struct FerramentasDoHomie: View {
    let homie: Homie
    let abrirModulo: () -> Void

    private let s = FerramentasServico.shared

    var body: some View {
        let dele = s.ligadas[homie.id] ?? []
        let conectadas = s.conectadas
        // Ativas nele que não estão (mais) no módulo: continuam aparecendo, para dar para desligar.
        let soltas = dele.filter { f in f.origem == .crew && !conectadas.contains { $0.nome == f.nome } }
        let daPasta = dele.filter { $0.origem == .pasta }
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ferramentas de \(homie.nome)").font(Tema.titulo(17)).foregroundStyle(Tema.texto)
                    Text("Ative só o que ele deve enxergar. Vale a partir da próxima conversa dele; nas rotinas, só com a chave de MCPs da rotina ligada.")
                        .font(.system(size: 12.5)).foregroundStyle(Tema.texto2).fixedSize(horizontal: false, vertical: true)
                }
                if let a = s.aviso {
                    Label(a, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11.5)).foregroundStyle(Tema.ambar).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if conectadas.isEmpty, soltas.isEmpty {
                    Text("Nenhuma ferramenta conectada ainda. Conecte uma vez nas Ferramentas do módulo e ative aqui.")
                        .font(.system(size: 12.5)).foregroundStyle(Tema.texto3).fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array((conectadas + soltas).enumerated()), id: \.element.id) { i, f in
                            if i > 0 { Fio() }
                            linha(f, ativa: dele.contains { $0.nome == f.nome && $0.origem == .crew })
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: Tema.raioCartao, style: .continuous).fill(Tema.painel))
                    .overlay(RoundedRectangle(cornerRadius: Tema.raioCartao, style: .continuous).strokeBorder(Tema.borda))
                }
                if !daPasta.isEmpty {
                    Text("Escritas à mão no .mcp.json da pasta dele (o Claude Code pede aprovação na conversa): " + daPasta.map(\.nome).joined(separator: ", "))
                        .font(.system(size: 11.5)).foregroundStyle(Tema.texto3).fixedSize(horizontal: false, vertical: true)
                }
                BotaoPilula(titulo: "Conectar outra ferramenta", icone: "plus", estilo: .discreto, altura: 28, acao: abrirModulo)
            }
            .padding(24)
            .frame(maxWidth: Tema.larguraConversa, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .onAppear { s.recarregar(s.central); s.recarregar(homie) }
    }

    private func linha(_ f: FerramentaLigada, ativa: Bool) -> some View {
        let k = s.chave(homie, f.nome)
        let ocupada = s.ocupadas[k]
        let item = FerramentasHomie.catalogo.first { $0.id == f.nome }
        return HStack(spacing: 12) {
            Image(systemName: item?.icone ?? "puzzlepiece.extension").font(.system(size: 14))
                .foregroundStyle(ativa ? Tema.texto2 : Tema.texto3).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(item?.nome ?? f.nome).font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(ativa ? Tema.texto : Tema.texto2).lineLimit(1)
                Text(ocupada ?? situacao(k, ativa, item?.resumo ?? f.destino)).font(.system(size: 11.5))
                    .foregroundStyle(cor(k, ativa, ocupada != nil)).lineLimit(2).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if ocupada != nil {
                ProgressView().controlSize(.small)
            } else if ativa, f.http, s.situacoes[k] == .faltaEntrar {
                BotaoPilula(titulo: "Entrar", icone: "person.badge.key", altura: 28) { Task { await s.entrar(homie, f.nome) } }
                    .help("O Claude Code pediu o login de novo para este Homie: abre no navegador")
            }
            Toggle("", isOn: Binding(get: { ativa }, set: { v in Task { await s.ativar(homie, f, v) } }))
                .toggleStyle(.switch).controlSize(.small).labelsHidden()
                .disabled(ocupada != nil || MotorCrew.claude == nil)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private func situacao(_ k: String, _ ativa: Bool, _ padrao: String) -> String {
        guard ativa else { return padrao }
        switch s.situacoes[k] {
        case .conectada: return "ativa e respondendo"
        case .faltaEntrar: return "ativa, mas falta entrar"
        case .falhou(let m): return "ativa, mas não respondeu: " + m
        case nil: return "ativa"
        }
    }

    private func cor(_ k: String, _ ativa: Bool, _ ocupada: Bool) -> Color {
        if ocupada { return Tema.azul }
        guard ativa else { return Tema.texto3 }
        switch s.situacoes[k] {
        case .faltaEntrar, .falhou: return Tema.ambar
        default: return Tema.verde
        }
    }
}
