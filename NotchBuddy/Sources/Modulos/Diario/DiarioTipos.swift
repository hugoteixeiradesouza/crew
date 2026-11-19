import Foundation

// O que o Diário guarda: um JSON por dia em
// ~/Library/Application Support/NotchBuddy/diario/AAAA-MM-DD.json.

enum TipoEntrada: String, Codable, CaseIterable, Identifiable, Sendable {
    case pedido, entrega, nota, whatsapp
    var id: String { rawValue }

    var nome: String {
        switch self {
        case .pedido: return "Pedidos"
        case .entrega: return "Entregas"
        case .nota: return "Notas"
        case .whatsapp: return "WhatsApp"
        }
    }

    var icone: String {
        switch self {
        case .pedido: return "arrow.up.right"
        case .entrega: return "checkmark"
        case .nota: return "pencil"
        case .whatsapp: return "message.fill"
        }
    }

    /// Fonte que o Hugo liga/desliga (e cujo desligar apaga o guardado).
    var fonte: FonteDiario {
        switch self {
        case .nota: return .notas
        case .whatsapp: return .whatsapp
        default: return .sessoes
        }
    }
}

enum FonteDiario: String, CaseIterable, Identifiable, Sendable {
    case sessoes, apps, notas, commits, whatsapp
    var id: String { rawValue }

    var nome: String {
        switch self {
        case .sessoes: return "Sessões do Claude Code"
        case .apps: return "App em foco"
        case .notas: return "Notas rápidas"
        case .commits: return "Commits do dia"
        case .whatsapp: return "WhatsApp"
        }
    }

    var detalhe: String {
        switch self {
        case .sessoes: return "Seus pedidos e as entregas de cada sessão (título, projeto, primeira frase da resposta)."
        case .apps: return "Quanto tempo cada app ficou na frente. Pausa com a tela apagada ou bloqueada."
        case .notas: return "O que você anota na ilha ou por crew://diario/nota."
        case .commits: return "Seus commits do dia nos projetos que apareceram, lidos só na hora do resumo (git log local)."
        case .whatsapp: return "Só as mensagens que VOCÊ envia, lidas no próprio Mac (precisa do Acesso Total ao Disco). Só a frase de uma promessa vira pendência; o resto não é guardado. Nada sai do Mac."
        }
    }
}

struct EntradaDiario: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var hora: Date
    var tipo: TipoEntrada
    var texto: String
    var projeto: String?
    /// Raiz do projeto (para os commits do dia).
    var raiz: String?
    var cor: String?
    /// Título da sessão.
    var sessao: String?
    var sessaoId: String?
}

struct TempoApp: Codable, Equatable, Sendable {
    var nome: String
    var segundos: Double
}

struct CommitDiario: Codable, Identifiable, Equatable, Sendable {
    var id: String { hash }
    var hash: String
    var hora: Date
    var titulo: String
    var projeto: String
}

struct Pendencia: Codable, Identifiable, Equatable, Sendable {
    /// sugerida = o Homie acha que é task e está perguntando ao Hugo (ainda não cobra nem avisa).
    enum Estado: String, Codable, Sendable { case aberta, feita, adiada, ignorada, sugerida }

    var id = UUID()
    var criadaEm: Date
    /// Dia (AAAA-MM-DD) em cujo arquivo a pendência mora.
    var dia: String
    var origem: TipoEntrada
    var entradaId: UUID?
    /// O texto de onde veio (curto), para o aviso dizer de onde veio.
    var textoOrigem: String
    var acao: String
    /// Até ~5 palavras, para a barra da ilha (opcional: arquivos antigos não têm).
    var curta: String?
    var pessoa: String?
    /// O tema, para a linha mostrar do que se trata (opcional: arquivos antigos não têm).
    var assunto: String?
    /// Por que o Homie achou que era task (só sugestões; mostrado no "Vira task?").
    var porque: String?
    var prazo: Date?
    var urgencia: Urgencia
    var estado: Estado = .aberta
    var adiadaAte: Date?
    var resolvidaEm: Date?
    /// Por que fechou sozinha ("você respondeu à sessão às 14:05").
    var motivo: String?
    var sessaoId: String?
    var sessao: String?
    var projeto: String?
    var comIA: Bool
    /// O Hugo mesmo transformou a entrada em pendência (a limpeza automática não mexe nela).
    var manual: Bool?
    /// Avisos já dados ("antes", "prazo", "agora", "volta-<timestamp>").
    var avisos: [String] = []

    var acaoCurta: String { (curta?.isEmpty == false ? curta : nil) ?? TriagemIA.curtaValida("", acao: acao) }
    var aberta: Bool { estado == .aberta || estado == .adiada }
    /// Quando ela precisa de atenção (para ordenar): adiada → quando volta; com prazo → o prazo.
    var vence: Date? { estado == .adiada ? adiadaAte : prazo }
}

struct ResumoDiario: Codable, Equatable, Sendable {
    var geradoEm: Date
    var feito: [String]
    var aberto: [String]
    var prometido: [String]
    var comIA: Bool
}

struct DiaDiario: Codable, Equatable, Sendable {
    var dia: String
    var entradas: [EntradaDiario] = []
    /// Tempo por app (bundle id → nome e segundos).
    var apps: [String: TempoApp] = [:]
    var pendencias: [Pendencia] = []
    var commits: [CommitDiario]?
    var commitsLidosEm: Date?
    var resumo: ResumoDiario?

    func contagem(_ t: TipoEntrada) -> Int { entradas.filter { $0.tipo == t }.count }
}

enum FormatoDiario {
    static let chaveDia: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func dia(_ d: Date) -> String { chaveDia.string(from: d) }
    static func data(_ dia: String) -> Date? { chaveDia.date(from: dia) }

    private static let horaF: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = "HH:mm"
        return f
    }()

    static func hora(_ d: Date) -> String { horaF.string(from: d) }

    /// "12:00", "amanhã 9:00", "sex 18:00", "10/10 9:00".
    static func quando(_ d: Date, agora: Date = Date()) -> String {
        let cal = Calendar.current
        if cal.isDate(d, inSameDayAs: agora) { return hora(d) }
        if let amanha = cal.date(byAdding: .day, value: 1, to: agora), cal.isDate(d, inSameDayAs: amanha) {
            return "amanhã \(hora(d))"
        }
        let dias = cal.dateComponents([.day], from: cal.startOfDay(for: agora), to: cal.startOfDay(for: d)).day ?? 0
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = (0..<7).contains(dias) ? "EEE" : "dd/MM"
        let p = f.string(from: d).replacingOccurrences(of: ".", with: "")
        if dias < 0, let ontem = cal.date(byAdding: .day, value: -1, to: agora), cal.isDate(d, inSameDayAs: ontem) {
            return "ontem \(hora(d))"
        }
        return "\(p) \(hora(d))"
    }

    /// "Segunda, 5 de outubro".
    static func diaLongo(_ dia: String) -> String {
        guard let d = data(dia) else { return dia }
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Hoje" }
        if cal.isDateInYesterday(d) { return "Ontem" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = "EEEE, d 'de' MMMM"
        return f.string(from: d).capitalized(with: Locale(identifier: "pt_BR"))
    }

    static func duracao(_ s: Double) -> String {
        let min = Int(s / 60)
        if min < 1 { return "<1 min" }
        if min < 60 { return "\(min) min" }
        let h = min / 60, m = min % 60
        return m == 0 ? "\(h) h" : "\(h) h \(m)"
    }
}
