import Foundation
import CoreServices

// Fonte "WhatsApp" das Tasks: lê só as mensagens que o Hugo ENVIA, por evento (o arquivo do
// banco muda a cada mensagem → FSEvents só nos arquivos do banco; a primeira mudança agenda uma
// leitura 2 s depois e as seguintes entram nela — nunca adiam), nunca por polling. Começa das últimas 24 h quando é ligada. Só a frase de uma promessa chega a ser
// guardada (como pendência); o resto não fica em lugar nenhum.

@MainActor
final class FonteWhatsApp {
    static let shared = FonteWhatsApp()
    private var fluxo: FSEventStreamRef?
    private var pendente: DispatchWorkItem?
    private var lendo = false
    private let log = Log.de("diario")

    /// Último instante já lido (segundos desde 2001).
    private var ultimo: Double {
        get { Ajustes.double("diario", "whatsapp.ultimo", padrao: Date().addingTimeInterval(-24 * 3600).timeIntervalSinceReferenceDate) }
        set { Ajustes.definir("diario", "whatsapp.ultimo", newValue) }
    }

    var temAcesso: Bool { WhatsAppBanco.temAcesso() && WhatsAppBanco.bancoConversas() != nil }

    func ligar() {
        guard fluxo == nil, !CaptureTool.ativo, let banco = WhatsAppBanco.bancoConversas() else { return }
        let pasta = banco.deletingLastPathComponent().path as CFString
        var ctx = FSEventStreamContext(version: 0, info: nil, retain: nil, release: nil, copyDescription: nil)
        let cb = FonteWhatsApp.aoMudar
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        guard let f = FSEventStreamCreate(nil, cb, &ctx, [pasta] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                                          1, flags) else { return }
        FSEventStreamSetDispatchQueue(f, DispatchQueue.global(qos: .utility))
        FSEventStreamStart(f)
        fluxo = f
        mudou()   // lê o que chegou desde a última vez
    }

    /// Callback das FSEvents, montado fora do MainActor: roda numa fila de fundo. Só o banco das
    /// conversas (e o WAL dele) interessa; mídia, cache e o resto da pasta não.
    nonisolated static let aoMudar: FSEventStreamCallback = { _, _, n, caminhos, _, _ in
        let lista = unsafeBitCast(caminhos, to: NSArray.self)
        var doBanco = false
        for i in 0..<n where (lista[i] as? String)?.contains("ChatStorage.sqlite") == true { doBanco = true; break }
        guard doBanco else { return }
        DispatchQueue.main.async { MainActor.assumeIsolated { FonteWhatsApp.shared.mudou() } }
    }

    func desligar() {
        pendente?.cancel(); pendente = nil
        if let f = fluxo { FSEventStreamStop(f); FSEventStreamInvalidate(f); FSEventStreamRelease(f) }
        fluxo = nil
    }

    /// Esquece o ponto de leitura (ao desligar a fonte e apagar o que veio dela).
    func esquecer() { Ajustes.definir("diario", "whatsapp.ultimo", nil) }

    /// Uma leitura já agendada absorve as mudanças seguintes (antes, cada mudança adiava a
    /// leitura em 20 s — com conversa ativa a task demorava minutos para aparecer).
    private func mudou() {
        guard pendente == nil else { return }
        let item = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.pendente = nil; self?.ler() } }
        pendente = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: item)
    }

    /// Janela de conversa que a triagem lê: as últimas 3 h de cada conversa que mexeu.
    nonisolated static let janela: TimeInterval = 3 * 3600

    private func ler() {
        guard !lendo else { mudou(); return }
        lendo = true
        let desde = ultimo
        let comPendencia = DiarioServico.shared.conversasComPendencia
        Task.detached(priority: .utility) {
            let novas = WhatsAppBanco.novas(desde: desde)
            // Conversas que valem uma triagem: o Hugo falou de fazer algo; ou alguém respondeu
            // numa conversa que já tem pendência aberta; ou o outro propôs algo (hora, reunião)
            // numa conversa em que o Hugo falou nas últimas horas
            var porChat: [Int64: [MensagemWA]] = [:]
            for m in novas { porChat[m.chat, default: []].append(m) }
            var conversas: [[MensagemWA]] = []
            for (chat, ms) in porChat {
                guard let ultima = ms.last else { continue }
                let hugoPrometeu = ms.contains { $0.deMim && FonteWhatsApp.podeSerPromessa($0.texto) }
                let temPendencia = ultima.conversa.map { comPendencia.contains($0) } ?? false
                let outroPropos = !ultima.grupo && ms.contains { !$0.deMim && FonteWhatsApp.podeSerPromessa($0.texto) }
                guard hugoPrometeu || temPendencia || outroPropos else { continue }
                let janela = WhatsAppBanco.conversa(chat: chat, ate: ultima.data, janela: FonteWhatsApp.janela)
                guard janela.contains(where: \.deMim) else { continue }
                conversas.append(janela)
            }
            conversas.sort { ($0.last?.data ?? .distantPast) < ($1.last?.data ?? .distantPast) }
            let total = novas.count
            let ultimaData = novas.last?.data
            await MainActor.run {
                let fonte = FonteWhatsApp.shared
                fonte.log.info("whatsapp: \(total) mensagem(ns) nova(s), \(conversas.count) conversa(s) para triar")
                // Só marca como lido quando a triagem da última terminou: se o app fechar no meio,
                // a próxima abertura relê (a pendência do mesmo combinado é atualizada, não duplicada)
                let marcar = { @MainActor in
                    if let u = ultimaData?.timeIntervalSinceReferenceDate { fonte.ultimo = max(fonte.ultimo, u) }
                    fonte.lendo = false
                }
                guard !conversas.isEmpty else { marcar(); return }
                for (i, c) in conversas.enumerated() {
                    DiarioServico.shared.conversaWhatsApp(c, fim: i == conversas.count - 1 ? marcar : nil)
                }
            }
        }
    }

    /// Relê as mensagens dos últimos `minutos` (crew://diario/reler-whatsapp?minutos=N).
    func reler(minutos: Double) {
        ultimo = Date().addingTimeInterval(-minutos * 60).timeIntervalSinceReferenceDate
        guard !lendo else { return }
        pendente?.cancel(); pendente = nil
        ler()
    }

    /// Filtro barato antes do modelo: mensagem de chat quase nunca é promessa. Só vai à triagem
    /// a que fala de fazer algo ("te mando", "vou ver", "amanhã te passo", "às 15h").
    nonisolated static func podeSerPromessa(_ texto: String) -> Bool {
        let t = texto.lowercased()
        guard t.count >= 8 else { return false }
        let padrao = #"\b(te mando|te envio|te passo|te ligo|te falo|te aviso|te retorno|mando|envio|passo|ligo|vou|vamos|vejo|resolvo|confirmo|faço|levo|pago|reunião|reuniao|reunir|reunimos|call|marcar|marco|agendar|encontro|combinado|preciso|precisamos|amanhã|depois|mais tarde|já já|hoje|segunda|terça|quarta|quinta|sexta|sábado|domingo|às \d|as \d|\d+h)\b"#
        return t.range(of: padrao, options: .regularExpression) != nil
    }
}
