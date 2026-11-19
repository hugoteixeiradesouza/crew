import SwiftUI
import CoreServices

// Alerta opcional (desligado por padrão): aviso na barra da ilha fechada quando o custo estimado
// do dia passa do limite que o Hugo define. Uma vez por dia.
//
// Custo de vigiar: com o alerta ligado, um único FSEventStream do macOS em ~/.claude/projects
// (evento do kernel, sem timer; o macOS junta os avisos e entrega no máximo um a cada 60 s).
// Cada aviso dispara uma leitura incremental (só o que cresceu desde a última). Sem Claude Code
// rodando, nada acontece. Alerta desligado = nenhuma vigia.

@MainActor
enum UsoAlerta {
    static var ligado: Bool {
        get { Ajustes.bool("uso", "alerta", padrao: false) }
        set { Ajustes.definir("uso", "alerta", newValue); aplicar() }
    }

    /// Limite do dia, em US$ (custo estimado pelos preços de referência).
    static var limite: Double {
        get { Ajustes.double("uso", "limite", padrao: 50) }
        set { Ajustes.definir("uso", "limite", newValue); diaAvisado = nil }
    }

    /// Dia (local, dias desde 1970) em que o aviso já saiu.
    private static var diaAvisado: Int? {
        get { UserDefaults.standard.object(forKey: Ajustes.chave("uso", "alertaDia")) as? Int }
        set { Ajustes.definir("uso", "alertaDia", newValue) }
    }

    /// Liga/desliga a vigia conforme o ajuste (e o módulo ligado).
    static func aplicar(moduloLigado: Bool = true) {
        if moduloLigado && ligado {
            UsoVigia.shared.ligar()
            UsoServico.shared.atualizarSeVelho(validade: 60)
        } else {
            UsoVigia.shared.desligar()
            Arbitro.shared.retirar("uso.alerta")
        }
    }

    /// Chamado depois de cada leitura.
    static func conferir(_ hoje: ValorUso) {
        guard ligado, limite > 0, hoje.custo >= limite else { return }
        let dia = LeitorTranscripts.hoje()
        guard diaAvisado != dia else { return }
        diaAvisado = dia
        let texto = "Claude Code hoje: \(FormatoUso.custo(hoje.custo)) · limite \(FormatoUso.custo(limite))"
        Arbitro.shared.publicar(Sinal(id: "uso.alerta", lugar: .barra, prioridade: .alerta, duracao: 8,
                                      conteudo: AnyView(AvisoUso(texto: texto))))
        NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.surprised)
    }
}

/// A linha do aviso na barra da ilha fechada.
struct AvisoUso: View {
    let texto: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "dollarsign.circle.fill").font(.system(size: 13, weight: .semibold))
                .foregroundColor(FormatoUso.cor)
            Text(texto).font(.system(size: 12, weight: .medium)).foregroundColor(Color(hex: "#DADDE2"))
                .lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
    }
}

/// Um FSEventStream em ~/.claude/projects, só enquanto o alerta está ligado.
@MainActor
final class UsoVigia {
    static let shared = UsoVigia()
    private var stream: FSEventStreamRef?
    private let fila = DispatchQueue(label: "crew.uso.vigia", qos: .utility)

    func ligar() {
        guard stream == nil else { return }
        let caminho = LeitorTranscripts.raizPadrao.path as CFString
        var ctx = FSEventStreamContext(version: 0, info: nil, retain: nil, release: nil, copyDescription: nil)
        guard let s = FSEventStreamCreate(kCFAllocatorDefault, UsoVigia.aviso, &ctx, [caminho] as CFArray,
                                          FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 60,
                                          FSEventStreamCreateFlags(kFSEventStreamCreateFlagNone)) else { return }
        FSEventStreamSetDispatchQueue(s, fila)
        FSEventStreamStart(s)
        stream = s
    }

    func desligar() {
        guard let s = stream else { return }
        FSEventStreamStop(s)
        FSEventStreamInvalidate(s)
        FSEventStreamRelease(s)
        stream = nil
    }

    /// Roda na fila da vigia (fora da main): só passa o recado.
    nonisolated private static let aviso: FSEventStreamCallback = { _, _, _, _, _, _ in
        DispatchQueue.main.async { MainActor.assumeIsolated { UsoServico.shared.transcriptCresceu() } }
    }
}
