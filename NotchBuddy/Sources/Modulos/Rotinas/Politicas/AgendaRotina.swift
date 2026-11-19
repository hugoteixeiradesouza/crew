import Foundation

// Agenda de uma rotina — regra pura (só Foundation), sem relógio próprio: quem chama passa o
// "agora" e o calendário. Conferida por um script à parte (ver docs/ARQUITETURA.md, Rotinas).
//
// Horário de verão: os horários de calendário usam `Calendar.nextDate` com `.nextTime` (hora que
// não existe no dia vira a primeira hora válida depois dela) e `.first` (hora que acontece duas
// vezes roda uma vez só). "A cada N" é tempo corrido a partir de uma âncora, não muda com o fuso.

struct AgendaRotina: Codable, Equatable, Sendable {
    enum Tipo: String, Codable, CaseIterable, Sendable {
        case manual, diaria, semanal, intervalo, umaVez
    }

    var tipo: Tipo = .manual
    /// Hora e minuto locais (diária e semanal).
    var hora = 9
    var minuto = 0
    /// Dias da semana do calendário: 1 = domingo … 7 = sábado (semanal).
    var dias: [Int] = [2, 3, 4, 5, 6]
    /// De quantos em quantos minutos (intervalo). Nunca menos que `PoliticaRotinas.intervaloMinimo`.
    var intervaloMin = 60
    /// Quando (uma vez).
    var data: Date?

    static let manual = AgendaRotina()

    /// Dá para agendar com isto? (manual é válida: só não tem próxima.)
    var valida: Bool {
        switch tipo {
        case .manual: return true
        case .diaria: return horaValida
        case .semanal: return horaValida && !dias.isEmpty && dias.allSatisfy { (1...7).contains($0) }
        case .intervalo: return intervaloMin >= PoliticaRotinas.intervaloMinimo
        case .umaVez: return data != nil
        }
    }

    private var horaValida: Bool { (0...23).contains(hora) && (0...59).contains(minuto) }

    /// A próxima execução estritamente depois de `depois`; nil = não há (manual, uma vez que já
    /// passou, agenda inválida). `ancora` só vale para o intervalo: a grade é âncora + k·N.
    func proxima(depois: Date, ancora: Date? = nil, calendario: Calendar = .current) -> Date? {
        guard valida else { return nil }
        switch tipo {
        case .manual:
            return nil
        case .diaria:
            return calendario.nextDate(after: depois, matching: DateComponents(hour: hora, minute: minuto, second: 0),
                                       matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)
        case .semanal:
            return Set(dias).compactMap { dia in
                calendario.nextDate(after: depois,
                                    matching: DateComponents(hour: hora, minute: minuto, second: 0, weekday: dia),
                                    matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)
            }.min()
        case .intervalo:
            let passo = Double(max(intervaloMin, PoliticaRotinas.intervaloMinimo)) * 60
            guard let ancora, ancora <= depois else { return (ancora ?? depois.addingTimeInterval(passo)) }
            let k = floor(depois.timeIntervalSince(ancora) / passo) + 1
            return ancora.addingTimeInterval(k * passo)
        case .umaVez:
            guard let data, data > depois else { return nil }
            return data
        }
    }
}

enum PoliticaRotinas {
    /// Intervalo mínimo de "a cada N", em minutos.
    static let intervaloMinimo = 15
    /// Atraso que ainda conta como "na hora" (timer com folga, Mac acordando).
    static let tolerancia: TimeInterval = 120
    /// Quantas execuções ficam no histórico de cada rotina.
    static let maxHistorico = 20

    enum Vencida: Equatable {
        /// Chegou a hora: roda.
        case naHora
        /// Passou da hora (Mac dormindo ou Crew fechado) e a rotina pede para recuperar: roda UMA vez.
        case recuperar
        /// Passou da hora e não recupera: só anota e agenda a próxima.
        case perdida
    }

    /// O que fazer com uma execução marcada para `agendada`, vista em `agora` (agendada <= agora).
    /// Nunca há fila: quem chama agenda a próxima a partir de `agora`, então várias perdidas
    /// viram no máximo uma recuperação.
    static func vencida(agendada: Date, agora: Date, recuperar: Bool) -> Vencida {
        if agora.timeIntervalSince(agendada) <= tolerancia { return .naHora }
        return recuperar ? .recuperar : .perdida
    }
}

/// Textos da agenda em português corrido.
enum FormatoRotina {
    static let diasCurtos = ["dom", "seg", "ter", "qua", "qui", "sex", "sáb"]
    static let diasInteiros = ["domingo", "segunda", "terça", "quarta", "quinta", "sexta", "sábado"]

    static func hora(_ h: Int, _ m: Int) -> String {
        "\(h < 10 ? "0" : "")\(h):\(m < 10 ? "0" : "")\(m)"
    }

    /// "hoje às 18:00", "amanhã às 09:00", "sexta às 09:00", "12/11 às 09:00", "ontem às 18:00".
    static func quando(_ d: Date, agora: Date = Date(), calendario: Calendar = .current) -> String {
        let c = calendario.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: d)
        let h = "às " + hora(c.hour ?? 0, c.minute ?? 0)
        let dias = calendario.dateComponents([.day], from: calendario.startOfDay(for: agora),
                                             to: calendario.startOfDay(for: d)).day ?? 0
        switch dias {
        case 0: return "hoje \(h)"
        case 1: return "amanhã \(h)"
        case -1: return "ontem \(h)"
        case 2...6: return "\(diasInteiros[((c.weekday ?? 1) - 1) % 7]) \(h)"
        default:
            let dia = c.day ?? 0, mes = c.month ?? 0
            var t = "\(dia < 10 ? "0" : "")\(dia)/\(mes < 10 ? "0" : "")\(mes)"
            if c.year != calendario.component(.year, from: agora), let a = c.year { t += "/\(a)" }
            return "\(t) \(h)"
        }
    }

    /// "Todo dia às 09:00", "Dias úteis às 09:00", "Seg, qua e sex às 09:00", "A cada 2 h"…
    static func descricao(_ a: AgendaRotina, agora: Date = Date(), calendario: Calendar = .current) -> String {
        let h = "às " + hora(a.hora, a.minuto)
        switch a.tipo {
        case .manual:
            return "Só à mão"
        case .diaria:
            return "Todo dia \(h)"
        case .semanal:
            let d = Array(Set(a.dias)).filter { (1...7).contains($0) }.sorted()
            if d.isEmpty { return "Nenhum dia escolhido" }
            if d.count == 7 { return "Todo dia \(h)" }
            if d == [2, 3, 4, 5, 6] { return "Dias úteis \(h)" }
            if d == [1, 7] { return "Fins de semana \(h)" }
            let nomes = d.map { diasCurtos[$0 - 1] }
            let lista = nomes.count == 1 ? nomes[0]
                : nomes.dropLast().joined(separator: ", ") + " e " + (nomes.last ?? "")
            return lista.prefix(1).uppercased() + lista.dropFirst() + " \(h)"
        case .intervalo:
            let n = max(a.intervaloMin, PoliticaRotinas.intervaloMinimo)
            if n % 60 == 0 { return n == 60 ? "A cada hora" : "A cada \(n / 60) h" }
            return "A cada \(n) min"
        case .umaVez:
            guard let data = a.data else { return "Uma vez (sem data)" }
            return "Uma vez, " + quando(data, agora: agora, calendario: calendario)
        }
    }
}
