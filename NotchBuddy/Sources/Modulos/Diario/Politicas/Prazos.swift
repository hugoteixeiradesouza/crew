import Foundation

// Prazo em português → data e hora absolutas, contra a hora em que a frase foi escrita.
// Regra pura (sem modelo): o modelo local só aponta o trecho; quem calcula a hora é aqui, para
// "meio-dia" ser sempre 12:00 e "amanhã cedo" sempre 9:00 do dia seguinte.
//
//   "até meio-dia"          → hoje 12:00 (se já passou: amanhã)
//   "às 15h", "15:30"       → hoje nessa hora (se já passou: amanhã); "às 3" → 15:00
//   "daqui 30 min", "em 2 horas", "daqui meia hora", "daqui a pouco" → agora + isso
//   "amanhã cedo/de manhã/à tarde/à noite" → dia seguinte 9:00 / 9:00 / 14:00 / 19:00
//   "amanhã", "sexta", "10/10" → esse dia 9:00 (com "até": 18:00)
//   "hoje", "fim do dia"    → hoje 18:00
//   "semana que vem"        → próxima segunda 9:00
//   "quando der", sem prazo → nil

enum Prazos {
    static func resolver(_ texto: String, desde ref: Date, calendario: Calendar = .current) -> Date? {
        let t = normalizar(texto)
        guard !t.isEmpty else { return nil }
        let cal = calendario

        // 1. Relativo: daqui X min/horas
        if let d = relativo(t) { return ref.addingTimeInterval(d) }

        // 2. Dia
        var diaOffset: Int? = nil
        var diaAbsoluto: Date? = nil
        if t.contains("depois de amanha") { diaOffset = 2 }
        else if t.contains("amanha") { diaOffset = 1 }
        else if t.contains("hoje") || t.contains("fim do dia") || t.contains("final do dia")
                    || t.contains("fim da tarde") || t.contains("hoje a noite") { diaOffset = 0 }
        if diaOffset == nil, t.contains("semana que vem") || t.contains("proxima semana") {
            let wd = cal.component(.weekday, from: ref)          // 1 = domingo, 2 = segunda
            diaOffset = ((2 - wd) + 7) % 7 == 0 ? 7 : ((2 - wd) + 7) % 7
        }
        var porDiaDaSemana = false
        if diaOffset == nil, let wd = diaDaSemana(t) {
            let hoje = cal.component(.weekday, from: ref)
            diaOffset = (wd - hoje + 7) % 7                       // mesmo dia = hoje (se a hora não passou)
            porDiaDaSemana = true
        }
        if diaOffset == nil, let d = dataDDMM(t, ref: ref, cal: cal) { diaAbsoluto = d }

        // 3. Hora
        var hora: (h: Int, m: Int)? = horaExplicita(t)
        if hora == nil {
            if t.contains("meio-dia") || t.contains("meio dia") || t.contains("almoco") { hora = (12, 0) }
            else if t.contains("meia-noite") || t.contains("meia noite") { hora = (23, 59) }
        }
        var periodo: (h: Int, m: Int)? = nil
        if t.contains("fim da tarde") || t.contains("final da tarde") {
            periodo = (17, 0)
        } else if t.contains("fim do dia") || t.contains("final do dia") {
            periodo = (18, 0)
        } else if t.contains("cedo") || t.contains("de manha") || t.contains("pela manha") {
            periodo = (9, 0)
        } else if t.contains(" a tarde") || t.contains("de tarde") || t.contains("pela tarde") || t.hasPrefix("a tarde") {
            periodo = (14, 0)
        } else if t.contains("a noite") || t.contains("de noite") {
            periodo = (19, 0)
        }

        guard diaOffset != nil || diaAbsoluto != nil || hora != nil || periodo != nil else { return nil }

        let inicioHoje = cal.startOfDay(for: ref)
        let dia: Date = diaAbsoluto
            ?? cal.date(byAdding: .day, value: diaOffset ?? 0, to: inicioHoje) ?? inicioHoje
        let ate = t.contains("ate ") || t.hasPrefix("ate")
        let (h, m): (Int, Int) = hora ?? periodo ?? {
            // Só o dia: hoje = fim do expediente; outro dia = começo dele (ou fim, com "até")
            if (diaOffset ?? 1) == 0 && diaAbsoluto == nil { return (18, 0) }
            return ate ? (18, 0) : (9, 0)
        }()
        guard var resultado = cal.date(bySettingHour: h, minute: m, second: 0, of: dia) else { return nil }
        // Só a hora, e ela já passou hoje: é amanhã
        if diaOffset == nil && diaAbsoluto == nil && resultado <= ref {
            resultado = cal.date(byAdding: .day, value: 1, to: resultado) ?? resultado
        }
        // "segunda às 10h" dito na segunda às 11h: é a próxima segunda
        if porDiaDaSemana && resultado <= ref {
            resultado = cal.date(byAdding: .day, value: 7, to: resultado) ?? resultado
        }
        return resultado
    }

    /// Minúsculas, sem acento, espaços simples.
    static func normalizar(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private static func relativo(_ t: String) -> TimeInterval? {
        if t.contains("daqui a pouco") || t.contains("daqui pouco") { return 30 * 60 }
        if t.contains("meia hora") && (t.contains("daqui") || t.contains("em meia") || t.contains("dentro de")) {
            return 30 * 60
        }
        let padrao = #"(?:daqui|dentro de|em)\s+(?:a\s+)?(\d+|uma|um|duas|dois|tres)\s*(min|minuto|minutos|h|hr|hrs|hora|horas)\b"#
        guard let re = try? NSRegularExpression(pattern: padrao),
              let m = re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)),
              let rn = Range(m.range(at: 1), in: t), let ru = Range(m.range(at: 2), in: t) else { return nil }
        let palavras = ["um": 1.0, "uma": 1, "dois": 2, "duas": 2, "tres": 3]
        let n = Double(t[rn]) ?? palavras[String(t[rn])] ?? 1
        return n * (t[ru].hasPrefix("m") ? 60 : 3600)
    }

    /// "às 15h", "15h30", "15:30", "até as 3", "lá pelas 16".
    private static func horaExplicita(_ t: String) -> (h: Int, m: Int)? {
        if let r = t.range(of: #"\b(\d{1,2})\s*(?:h|:)\s*(\d{2})?\b"#, options: .regularExpression) {
            let s = String(t[r])
            let nums = s.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
            if let h = nums.first, h < 24 {
                let m = nums.count > 1 ? nums[1] : 0
                return (h, m < 60 ? m : 0)
            }
        }
        if let r = t.range(of: #"\b(?:as|ate as|ate|pelas|antes das|depois das)\s+(\d{1,2})\b(?!\s*/)"#, options: .regularExpression) {
            let s = String(t[r])
            if let h = s.split(whereSeparator: { !$0.isNumber }).compactMap({ Int($0) }).first, h < 24 {
                return (h <= 7 ? h + 12 : h, 0)           // "às 3" no expediente = 15:00
            }
        }
        return nil
    }

    private static func diaDaSemana(_ t: String) -> Int? {
        let dias: [(String, Int)] = [("domingo", 1), ("segunda", 2), ("terca", 3), ("quarta", 4),
                                     ("quinta", 5), ("sexta", 6), ("sabado", 7)]
        for (nome, n) in dias where t.range(of: "\\b\(nome)\\b", options: .regularExpression) != nil { return n }
        return nil
    }

    /// "10/10", "10/10/2026" → esse dia (no ano que vem, se já passou).
    private static func dataDDMM(_ t: String, ref: Date, cal: Calendar) -> Date? {
        guard let r = t.range(of: #"\b(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?\b"#, options: .regularExpression) else { return nil }
        let n = String(t[r]).split(separator: "/").compactMap { Int($0) }
        guard n.count >= 2, (1...31).contains(n[0]), (1...12).contains(n[1]) else { return nil }
        var c = DateComponents()
        c.day = n[0]; c.month = n[1]
        c.year = n.count > 2 ? (n[2] < 100 ? 2000 + n[2] : n[2]) : cal.component(.year, from: ref)
        guard var d = cal.date(from: c) else { return nil }
        if n.count == 2, d < cal.startOfDay(for: ref) { d = cal.date(byAdding: .year, value: 1, to: d) ?? d }
        return d
    }
}
