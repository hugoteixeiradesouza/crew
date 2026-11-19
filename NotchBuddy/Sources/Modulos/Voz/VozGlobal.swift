import AppKit
import SwiftUI

// Segurar para falar, de qualquer lugar do Mac: segura o atalho = ouve; solta = para.
// O texto aparece na barra da ilha fechada (sinal passageiro, Homie de fones) e vai para a
// área de transferência. Só é mandado para a sessão em foco se o Hugo ligou o ajuste
// "mandar para a sessão em foco" — e nunca para uma sessão que está pedindo permissão ou
// perguntando algo (o texto cairia em cima do pedido).
//
// O mesmo caminho serve ao endereço crew://voz/ditar (alterna começar/parar).

@MainActor
enum VozGlobal {
    static let dono = "global"
    static let sinal = "voz.ditado"
    private static let log = Log.de("voz")

    static func apertou() {
        let s = VozServico.shared
        guard !s.ocupado else { return }
        s.atualizarPermissoes()
        // O pedido do macOS nunca sai de um atalho: a explicação e o clique ficam na página da Voz
        guard s.permissao == .concedida else {
            aviso("mic.slash.fill", "Voz: falta permitir o microfone — clique para abrir", cor: "#F5A524",
                  duracao: 6, clique: { Central.abrir(modulo: VozServico.modulo) })
            return
        }
        let comecou = s.ditar(dono: dono) { texto in terminou(texto) }
        guard comecou else {
            if case .erro(let motivo) = s.estado { aviso("exclamationmark.triangle.fill", motivo, cor: "#F4505E", duracao: 6) }
            return
        }
        // Enquanto o Hugo fala, o modelo que pontua o ditado já vai carregando
        if s.lapidacao != .literal { IAdoMac.aquecerDitado(formatar: s.lapidacao == .formatar) }
        Arbitro.shared.publicar(Sinal(id: sinal, lugar: .barra, prioridade: .hud, homie: .fones(0.7),
                                      conteudo: AnyView(BarraOuvindo())))
    }

    static func soltou() {
        let s = VozServico.shared
        if s.dono == dono, s.ouvindo { s.pararDitado() }
    }

    /// Fn com outra tecla, ou um esbarrão no Fn: larga o ditado sem aproveitar o texto.
    static func cancelou() {
        let s = VozServico.shared
        guard s.dono == dono, s.ocupado else { return }
        s.cancelarDitado()
        Arbitro.shared.retirar(sinal)
    }

    /// crew://voz/ditar: começa; chamado de novo, para.
    static func alternar() {
        let s = VozServico.shared
        if s.ocupado { soltou() } else { apertou() }
    }

    private static func terminou(_ texto: String?) {
        guard let texto else {
            if case .erro(let motivo) = VozServico.shared.estado {
                aviso("exclamationmark.triangle.fill", motivo, cor: "#F4505E", duracao: 6)
            } else {
                Arbitro.shared.retirar(sinal)
            }
            return
        }
        guard !texto.isEmpty else {
            aviso("mic.slash", "Não ouvi nada", cor: "#8E939C", duracao: 1.8)
            return
        }
        // Lapidar (nada sai do Mac): dicionário, muletas e correções são regra em código; o
        // modelo local só empresta pontuação e lista, e o `LapidarDitado` confere a resposta
        // palavra a palavra. Sem modelo, com demora ou com resposta que não bate, o texto sai com
        // as palavras da fala.
        let voz = VozServico.shared
        guard voz.lapidacao != .literal else {
            entregar(texto)
            return
        }
        let formatar = voz.lapidacao == .formatar
        let dicionario = voz.vocabulario
        let comModelo = IAdoMac.disponivel
        if comModelo { aviso("wand.and.stars", "Formatando… \(texto)", cor: "#8E939C", duracao: 12) }
        let pontuar: @Sendable (String, Bool) async -> String? = { fala, formatar in
            await IAdoMac.pontuarDitado(fala, formatar: formatar)
        }
        Task {
            let r = await LapidarDitado.lapidar(texto, formatar: formatar, dicionario: dicionario,
                                                modelo: comModelo ? pontuar : nil)
            if let motivo = r.motivo { log.info("ditado sem o modelo: \(motivo, privacy: .public)") }
            entregar(r.texto)
        }
    }

    /// Entrega o texto pronto: manda para a sessão, cola no app em foco ou só copia.
    private static func entregar(_ texto: String) {
        if VozServico.shared.mandarParaSessao {
            let area = NSPasteboard.general
            area.clearContents()
            area.setString(texto, forType: .string)
            Task { await mandar(texto) }
            return
        }
        guard VozServico.shared.colarNoApp else {
            let area = NSPasteboard.general
            area.clearContents()
            area.setString(texto, forType: .string)
            copiado(texto, porque: nil)
            return
        }
        // Colar no app em foco, devolvendo depois o que estava na área de transferência
        switch ColarTexto.colar(texto) {
        case .colou:
            aviso("text.cursor", texto, cor: "#4ADE80", duracao: 2.5)
        case .soCopiou(let motivo):
            copiado(texto, porque: motivo)
        }
    }

    /// Manda para a sessão em foco pelo mesmo caminho da conversa do app (Xirp, tmux, Terminal, iTerm).
    private static func mandar(_ texto: String) async {
        let estado = AppState.shared
        guard let t = estado.focusTask, t.source == .claudeCode, let sid = t.sessionId else {
            copiado(texto, porque: "nenhuma sessão em foco")
            return
        }
        // Sessão esperando um sim/não: texto digitado ali responderia ao pedido. Nunca.
        if t.state == .approval || t.state == .question || estado.pendingApprovals[sid] != nil {
            copiado(texto, porque: "\(t.displayTitle) espera sua resposta")
            return
        }
        let xid = await Xirp.sessionId(forClaudeSession: sid)
        let canal = await TerminalBridge.channel(claudePid: t.claudePid, bundleId: t.sessionAppBundleId, xirpId: xid)
        if case .none(let app) = canal {
            copiado(texto, porque: "a sessão roda no \(app)")
            return
        }
        // O pedido pode ter aparecido enquanto o canal era procurado
        if AppState.shared.pendingApprovals[sid] != nil {
            copiado(texto, porque: "\(t.displayTitle) espera sua resposta")
            return
        }
        if let erro = await TerminalBridge.send(texto, via: canal) {
            copiado(texto, porque: "não foi: \(erro.prefix(60))")
        } else {
            aviso("paperplane.fill", "Enviado para \(t.displayTitle): \(texto)", cor: "#4ADE80", duracao: 4)
            NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.proud)
        }
    }

    private static func copiado(_ texto: String, porque: String?) {
        let rotulo = porque.map { "Copiado (\($0))" } ?? "Copiado, é só colar"
        aviso("doc.on.clipboard.fill", "\(rotulo): \(texto)", cor: "#DADDE2", duracao: 4.5)
        NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
    }

    private static func aviso(_ icone: String, _ texto: String, cor: String, duracao: TimeInterval,
                              clique: (() -> Void)? = nil) {
        Arbitro.shared.publicar(Sinal(id: sinal, lugar: .barra, prioridade: .hud, duracao: duracao,
                                      clicavel: clique != nil,
                                      conteudo: AnyView(BarraVoz(icone: icone, texto: texto, cor: Color(hex: cor), clique: clique))))
    }
}

/// A barra enquanto o Hugo segura o atalho: medidor e o texto chegando (o fim sempre à vista).
struct BarraOuvindo: View {
    private let s = VozServico.shared

    var body: some View {
        HStack(spacing: 8) {
            MedidorVoz(nivel: s.nivel, cor: Color(hex: "#F4505E"))
                .frame(width: 18, height: 14)
            Text(texto)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color(hex: s.textoParcial.isEmpty ? "#8E939C" : "#DADDE2"))
                .lineLimit(1).truncationMode(.head)
            Spacer(minLength: 0)
        }
    }

    private var texto: String {
        if s.estado == .finalizando { return s.textoParcial.isEmpty ? "Fechando…" : s.textoParcial }
        return s.textoParcial.isEmpty ? "Ouvindo… solte para parar" : s.textoParcial
    }
}

/// Aviso de uma linha na barra (copiado, enviado, erro).
struct BarraVoz: View {
    let icone: String
    let texto: String
    let cor: Color
    var clique: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icone).font(.system(size: 13, weight: .semibold)).foregroundColor(cor)
            Text(texto).font(.system(size: 12, weight: .medium)).foregroundColor(Color(hex: "#DADDE2"))
                .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { clique?() }
    }
}
