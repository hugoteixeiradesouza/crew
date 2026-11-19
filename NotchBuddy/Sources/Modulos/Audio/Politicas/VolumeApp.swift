import Foundation

// Regras puras do volume por app: escala do volume, quando um app precisa de tap, qual app os
// atalhos controlam e quem é ignorado por padrão.

/// O que o Hugo escolheu para um app. Volume em fração de 0 a 4 (0 %–400 %).
struct AjusteApp: Equatable, Sendable, Codable {
    var volume: Double = 1
    var mudo = false
    /// Saída fixa (UID do dispositivo); nil = segue a saída padrão do Mac.
    var saidaUID: String? = nil

    static let maximo = 4.0
    /// 100 %, sem mudo e seguindo a padrão = o app como o macOS toca: nenhum tap.
    var neutro: Bool { !mudo && abs(volume - 1) < 0.005 && saidaUID == nil }

    /// Ganho aplicado às amostras. Até 100 % segue uma curva (volume²), que soa mais natural
    /// que a linear; acima, o reforço é linear até 4× (+12 dB), com o limitador segurando os picos.
    var ganho: Float {
        if mudo { return 0 }
        let v = min(max(volume, 0), Self.maximo)
        return Float(v <= 1 ? v * v : v)
    }
}

enum EscalaVolume {
    /// O slider dá 3/4 do curso para 0–100 % (onde se mexe quase sempre) e o último 1/4 para o
    /// reforço até 400 %.
    static let marcaCem = 0.75

    static func posicao(_ volume: Double) -> Double {
        volume <= 1 ? volume * marcaCem : marcaCem + (volume - 1) / (AjusteApp.maximo - 1) * (1 - marcaCem)
    }

    static func volume(_ posicao: Double) -> Double {
        let p = min(max(posicao, 0), 1)
        // Gruda em 100 % perto da marca (±1,5 % do curso): fácil voltar ao normal arrastando.
        if abs(p - marcaCem) < 0.015 { return 1 }
        let v = p <= marcaCem ? p / marcaCem : 1 + (p - marcaCem) / (1 - marcaCem) * (AjusteApp.maximo - 1)
        return (v * 100).rounded() / 100
    }

    /// Passo dos atalhos: 10 pontos; ao cruzar 100 %, para nele.
    static func passo(_ volume: Double, subir: Bool) -> Double {
        let n = subir ? volume + 0.1 : volume - 0.1
        if (volume < 1 && n > 1) || (volume > 1 && n < 1) { return 1 }
        return min(max((n * 10).rounded() / 10, 0), AjusteApp.maximo)
    }
}

enum EscolhaSaida {
    /// Para onde o som do app vai agora. Saída fixa presente → ela; ausente (desconectou) → a
    /// padrão, marcando `reserva` (nunca fica mudo esperando o dispositivo voltar).
    static func efetiva(fixa: String?, presentes: [String], padrao: String?) -> (uid: String?, reserva: Bool) {
        guard let fixa else { return (padrao, false) }
        return presentes.contains(fixa) ? (fixa, false) : (padrao, true)
    }

    /// Compensação de deriva do tap: precisa quando o app toca num relógio (a padrão) e o Crew
    /// devolve noutro (a fixa). Na mesma saída Bluetooth ela dá estalo ritmado: desliga.
    static func deriva(saidaUID: String, padraoUID: String?, bluetooth: Bool) -> Bool {
        saidaUID != padraoUID || !bluetooth
    }
}

enum AlvoAtalho {
    /// O app que os atalhos controlam: o da frente, se estiver tocando; senão o último mexido
    /// (se ainda estiver aberto); senão o primeiro tocando.
    static func escolher(tocando: [String], abertos: Set<String>, frente: String?, ultimoMexido: String?) -> String? {
        if let f = frente, tocando.contains(f) { return f }
        if let u = ultimoMexido, abertos.contains(u) { return u }
        return tocando.first
    }
}

enum IgnoradosPadrao {
    /// Apps de chamada: o tap quebra o cancelamento de eco deles (o outro lado ouve a si mesmo).
    static let bundles: [String] = [
        "com.apple.FaceTime",
        "us.zoom.xos",
        "com.microsoft.teams2",
        "com.microsoft.teams",
        "net.whatsapp.WhatsApp",
        "desktop.WhatsApp",
    ]

    /// Nome para mostrar quando o app não está instalado neste Mac.
    static let nomes: [String: String] = [
        "com.apple.FaceTime": "FaceTime",
        "us.zoom.xos": "Zoom",
        "com.microsoft.teams2": "Microsoft Teams",
        "com.microsoft.teams": "Microsoft Teams (clássico)",
        "net.whatsapp.WhatsApp": "WhatsApp",
        "desktop.WhatsApp": "WhatsApp (antigo)",
    ]
}
