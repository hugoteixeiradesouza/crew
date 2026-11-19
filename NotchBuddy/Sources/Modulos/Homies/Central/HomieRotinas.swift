import SwiftUI

// As duas abas do Homie além da conversa:
//  - Hoje: a página que cada rotina dele entregou, com as ações que ele propõe. Cada ação só
//    acontece no clique do Hugo ("Fazer" abre a conversa com quem vai fazer, já com o pedido).
//  - Rotinas: o que ele entrega sozinho e quando. Quem configura é o Hugo; a agenda é a das
//    Rotinas do Crew (mesma chave, mesma pausa, mesmo histórico).

// MARK: - Hoje

struct HojeHomie: View {
    let homie: Homie
    /// "Fazer" abriu conversa com este Homie: a tela vai até ela.
    let foiPara: (UUID) -> Void
    let irParaRotinas: () -> Void

    private let s = HomiesServico.shared
    private let rotinas = RotinasServico.shared

    var body: some View {
        let lista = rotinas.doHomie(homie.id)
        let comPagina = lista.compactMap { r in s.paginas[r.id].map { (r, $0) } }.sorted { $0.1.quando > $1.1.quando }
        let rodando = lista.filter { s.rotinasRodando[$0.id] != nil }
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(rodando) { r in emAndamento(r) }
                if comPagina.isEmpty, rodando.isEmpty { vazio(temRotina: !lista.isEmpty) }
                ForEach(comPagina, id: \.0.id) { r, g in cartao(r, g) }
                if let a = s.aviso {
                    Text(a).font(.system(size: 11.5)).foregroundStyle(Tema.ambar).textSelection(.enabled)
                }
            }
            .padding(24)
            .frame(maxWidth: Tema.larguraConversa, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .onAppear { s.carregarPaginas(homie.id) }
    }

    private func vazio(temRotina: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(temRotina ? "Nenhuma página ainda" : "\(homie.nome) ainda não tem rotina")
                .font(Tema.titulo(17)).foregroundStyle(Tema.texto)
            Text(temRotina
                 ? "A página aparece aqui quando uma rotina dele rodar: pela agenda ou no \"Rodar agora\"."
                 : "Uma rotina é o que ele entrega sozinho, na hora que você marcar: uma página com o que você pediu e as ações que ele propõe. Você decide cada uma no clique.")
                .font(.system(size: 12.5)).foregroundStyle(Tema.texto2).fixedSize(horizontal: false, vertical: true)
            BotaoPilula(titulo: temRotina ? "Ver as rotinas" : "Criar a primeira rotina", icone: "clock", altura: 30, acao: irParaRotinas)
        }
        .frame(maxWidth: 520, alignment: .leading)
    }

    private func emAndamento(_ r: Rotina) -> some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("\(r.nome): \(homie.nome) está montando a página").font(.system(size: 12.5)).foregroundStyle(Tema.texto2)
            Spacer(minLength: 8)
            if let sid = s.rotinasRodando[r.id] {
                BotaoPilula(titulo: "Ver no Terminal", icone: "macwindow", estilo: .discreto, altura: 26) {
                    Task { await MotorCrew.abrirNoTerminal(sid) }
                }
                .help("Se ele parou numa pergunta (confiar na pasta, permissão de um MCP), é lá que você responde")
            }
        }
        .padding(.horizontal, 14).frame(height: 44)
        .background(RoundedRectangle(cornerRadius: Tema.raioLinha + 2).fill(Color.white.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: Tema.raioLinha + 2).strokeBorder(Tema.borda))
    }

    private func cartao(_ r: Rotina, _ g: HomiesServico.PaginaGuardada) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text").font(.system(size: 10.5, weight: .medium))
                    Text("\(r.nome) · \(FormatoRotina.quando(g.quando))").font(.system(size: 11.5, weight: .medium))
                    if g.pagina.semNovidade { Text("· sem novidade").font(.system(size: 11.5)) }
                }
                .foregroundStyle(Tema.texto3)
                if !g.pagina.titulo.isEmpty {
                    Text(g.pagina.titulo).font(Tema.titulo(18, .bold)).foregroundStyle(Tema.texto)
                }
            }
            if !g.pagina.resumo.isEmpty {
                TextoConversa(texto: g.pagina.resumo, tamanho: 13.5)
            }
            if !g.pagina.acoes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("O que ele propõe (nada foi feito)").font(.system(size: 11.5, weight: .medium)).foregroundStyle(Tema.texto3)
                    ForEach(g.pagina.acoes) { a in acao(r, a, g.resolvidas[a.id]) }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Tema.raioCartao, style: .continuous).fill(Tema.painel))
        .overlay(RoundedRectangle(cornerRadius: Tema.raioCartao, style: .continuous).strokeBorder(Tema.borda))
    }

    private func acao(_ r: Rotina, _ a: PaginaHomie.Acao, _ decisao: String?) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: decisao == "feita" ? "checkmark.circle.fill" : decisao == nil ? "circle.dashed" : "minus.circle")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(decisao == "feita" ? Tema.verde.opacity(0.8) : Tema.texto3)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(a.titulo).font(.system(size: 13, weight: .medium))
                    .foregroundStyle(decisao == nil ? Tema.texto : Tema.texto3)
                    .strikethrough(decisao == "dispensada", color: Tema.texto3)
                    .fixedSize(horizontal: false, vertical: true)
                Text(legenda(a, decisao)).font(.system(size: 11)).foregroundStyle(Tema.texto3).lineLimit(1)
            }
            .help(a.pedido)
            Spacer(minLength: 8)
            if decisao == nil {
                BotaoPilula(titulo: "Dispensar", estilo: .discreto, altura: 28) {
                    s.decidir(homie.id, rotina: r.id, acao: a.id, "dispensada")
                }
                BotaoPilula(titulo: "Fazer", icone: "arrow.up", estilo: .ambar, altura: 28) {
                    if let alvo = s.fazer(homie.id, rotina: r.id, acao: a) { foiPara(alvo) }
                }
                .help("Abre a conversa com quem vai fazer, já com este pedido:\n\(a.pedido)")
            } else {
                BotaoPilula(titulo: "Desfazer", estilo: .discreto, altura: 26) {
                    s.decidir(homie.id, rotina: r.id, acao: a.id, nil)
                }
                .help(decisao == "feita" ? "Volta a ação para a lista. A conversa que você abriu continua onde está." : "Volta a ação para a lista")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: Tema.raioLinha).fill(Color.white.opacity(decisao == nil ? 0.04 : 0.015)))
    }

    private func legenda(_ a: PaginaHomie.Acao, _ decisao: String?) -> String {
        let quem = a.quem.isEmpty ? homie.nome : a.quem
        switch decisao {
        case "feita": return "pedido enviado a \(quem)"
        case "dispensada": return "dispensada"
        default: return "quem faz: \(quem)"
        }
    }
}

// MARK: - Rotinas

struct RotinasDoHomie: View {
    let homie: Homie
    let irParaHoje: () -> Void

    private let s = RotinasServico.shared
    private let homies = HomiesServico.shared
    @State private var editando: Rotina?
    @State private var apagando: Rotina?
    @State private var confirmandoLigar: UUID?

    var body: some View {
        let lista = s.doHomie(homie.id)
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Rotinas de \(homie.nome)").font(Tema.titulo(17)).foregroundStyle(Tema.texto)
                        Text("O que ele entrega sozinho e quando. Nessas horas ele só lê e escreve a página; as ações que propõe esperam o seu clique na aba Hoje.")
                            .font(.system(size: 12.5)).foregroundStyle(Tema.texto2).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    BotaoPilula(titulo: "Nova rotina", icone: "plus", estilo: .ambar, altura: 30) {
                        editando = Rotina(pasta: homie.pasta, agenda: AgendaRotina(tipo: .semanal, hora: 7, minuto: 30),
                                          recuperarPerdida: true, homie: homie.id)
                    }
                }
                if lista.contains(where: \.ligada), !s.agendaValendo {
                    aviso(s.pausadas ? "As rotinas do Crew estão pausadas (Squad › Rotinas): nenhuma roda pela agenda até tirar a pausa."
                                     : "A agenda está parada: a ferramenta Rotinas está desligada nos Ajustes. \"Rodar agora\" continua valendo.")
                }
                if let m = MotorCrew.motivoIndisponivel { aviso("Sem motor de sessões neste Mac: \(m)") }
                if lista.isEmpty {
                    Text("Nenhuma rotina ainda. Exemplo: toda manhã às 7h30, o que mudou desde ontem e os três movimentos do dia.")
                        .font(.system(size: 12.5)).foregroundStyle(Tema.texto3).fixedSize(horizontal: false, vertical: true)
                }
                ForEach(lista) { r in linha(r) }
            }
            .padding(24)
            .frame(maxWidth: Tema.larguraConversa, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .sheet(item: $editando) { r in
            RotinaEditor(rotina: r, nova: s.rotina(r.id) == nil, doHomie: homie.nome,
                         salvar: { var n = $0; n.pasta = homie.pasta; n.homie = homie.id; s.salvar(n); editando = nil },
                         cancelar: { editando = nil })
        }
        .alert("Ligar a agenda desta rotina?",
               isPresented: Binding(get: { confirmandoLigar != nil }, set: { if !$0 { confirmandoLigar = nil } }),
               presenting: confirmandoLigar) { id in
            Button("Ligar") { s.confirmarConsentimento(); s.ligar(id, true) }
            Button("Cancelar", role: .cancel) {}
        } message: { _ in
            Text("Com a chave ligada, o Crew abre sessões do Claude Code sozinho, na hora marcada, sem você clicar — e cada sessão gasta o seu uso do Claude Code.\n\nVocê pode desligar cada rotina ou pausar todas quando quiser. Esta pergunta aparece só desta vez.")
        }
        .alert(apagando.map { "Apagar a rotina \($0.nome)?" } ?? "",
               isPresented: Binding(get: { apagando != nil }, set: { if !$0 { apagando = nil } }),
               presenting: apagando) { r in
            Button("Apagar", role: .destructive) { s.apagar(r.id) }
            Button("Cancelar", role: .cancel) {}
        } message: { _ in
            Text("Sai o pedido, a agenda e o histórico. A última página dela continua na pasta do Homie.")
        }
    }

    private func aviso(_ texto: String) -> some View {
        Label(texto, systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 11.5)).foregroundStyle(Tema.ambar).fixedSize(horizontal: false, vertical: true)
    }

    private func linha(_ r: Rotina) -> some View {
        let rodando = s.rodando.contains(r.id) || homies.rotinasRodando[r.id] != nil
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                if r.agenda.tipo == .manual {
                    Image(systemName: "hand.tap").foregroundStyle(Tema.texto3).frame(width: 38)
                        .help("Só roda quando você manda")
                } else {
                    Toggle("", isOn: Binding(get: { r.ligada }, set: { ligar(r, $0) }))
                        .toggleStyle(.switch).controlSize(.small).labelsHidden().frame(width: 38)
                        .help(r.ligada ? "Roda sozinha pela agenda" : "Agenda desligada: só roda quando você manda")
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.nome).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Tema.texto).lineLimit(1)
                    Text(FormatoRotina.descricao(r.agenda) + (r.comMcps == true ? " · com os MCPs dele" : ""))
                        .font(.system(size: 11.5)).foregroundStyle(Tema.texto3).lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(situacao(r)).font(.system(size: 11.5)).foregroundStyle(falhou(r) ? Tema.ambar : Tema.texto3)
                    .lineLimit(2).multilineTextAlignment(.trailing).frame(maxWidth: 260, alignment: .trailing)
            }
            Text(r.pedido).font(.system(size: 12.5)).foregroundStyle(Tema.texto2).lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                BotaoPilula(titulo: rodando ? "Rodando…" : "Rodar agora", icone: "play.fill", altura: 28, ocupado: rodando) {
                    s.rodarAgora(r.id)
                    irParaHoje()
                }
                .disabled(rodando || MotorCrew.motivoIndisponivel != nil)
                .help("Abre agora a sessão desta rotina; a página chega na aba Hoje")
                BotaoPilula(titulo: "Editar", icone: "pencil", estilo: .discreto, altura: 28) { editando = r }
                Spacer()
                BotaoIcone(icone: "trash", ajuda: "Apagar esta rotina") { apagando = r }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Tema.raioCartao, style: .continuous).fill(Tema.painel))
        .overlay(RoundedRectangle(cornerRadius: Tema.raioCartao, style: .continuous).strokeBorder(Tema.borda))
    }

    private func falhou(_ r: Rotina) -> Bool { r.historico.first.map { !$0.ok } ?? false }

    /// "próxima: amanhã às 07:30" e como foi a última tentativa.
    private func situacao(_ r: Rotina) -> String {
        var partes: [String] = []
        if r.ligada, let p = r.proximaExecucao { partes.append("próxima: " + FormatoRotina.quando(p)) }
        if let u = r.historico.first {
            partes.append(u.ok ? "última: " + FormatoRotina.quando(u.quando) : "não rodou: " + (u.motivo ?? "motivo desconhecido"))
        }
        return partes.joined(separator: "\n")
    }

    private func ligar(_ r: Rotina, _ ligada: Bool) {
        if ligada, !s.consentiu { confirmandoLigar = r.id } else { s.ligar(r.id, ligada) }
    }
}
