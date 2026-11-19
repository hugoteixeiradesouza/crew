import SwiftUI
import Observation

// Dados do módulo Uso: quanto o Hugo gasta com o Claude Code, lido dos transcripts locais.
// Nada roda sozinho: lê quando a aba/página abre (se a última leitura for velha) ou quando o
// Hugo pede; com o alerta ligado, também quando o macOS avisa que um transcript cresceu
// (UsoVigia). Sempre fora da main, só o que é novo; o somado fica em
// ~/Library/Application Support/NotchBuddy/uso.json.

@Observable @MainActor
final class UsoServico {
    static let shared = UsoServico()

    private(set) var resumo = ResumoUso()
    private(set) var lendo = false
    private(set) var ultimaLeitura: Date?
    /// Duração da leitura completa (quando não havia nada em disco), para mostrar na Central.
    private(set) var leituraCompleta: (segundos: Double, bytes: UInt64, arquivos: Int)?
    private(set) var ultimaDuracao: Double?

    @ObservationIgnored private var estado: EstadoUso?
    @ObservationIgnored private var pendente = false
    @ObservationIgnored private let log = Log.de("uso")

    private init() {}

    /// Lê de novo se a última leitura tiver mais de `validade` segundos (ou nunca houve).
    func atualizarSeVelho(validade: TimeInterval = 30) {
        if let u = ultimaLeitura, Date().timeIntervalSince(u) < validade { return }
        atualizar()
    }

    func atualizar() {
        guard !lendo else { pendente = true; return }
        lendo = true
        let atual = estado
        Task {
            let r = await Task.detached(priority: .utility) { Self.ler(atual) }.value
            estado = r.leitura.estado
            ultimaDuracao = r.leitura.segundos
            if r.doZero {
                leituraCompleta = (r.leitura.segundos, r.leitura.bytesLidos, r.leitura.arquivosLidos)
            }
            resumo = Self.nomear(r.resumo)
            ultimaLeitura = Date()
            lendo = false
            log.info("leitura: \(r.leitura.arquivosLidos) arquivo(s), \(r.leitura.bytesLidos) bytes, \(r.leitura.mensagensNovas) mensagem(ns) nova(s) em \(r.leitura.segundos, format: .fixed(precision: 2)) s")
            UsoAlerta.conferir(resumo.hoje)
            await buscarTitulos()
            if pendente { pendente = false; atualizar() }
        }
    }

    private struct Leitura: Sendable {
        let leitura: LeitorTranscripts.Resultado
        let resumo: ResumoUso
        let doZero: Bool
    }

    nonisolated private static func ler(_ atual: EstadoUso?) -> Leitura {
        let base = atual ?? LeitorTranscripts.carregar()
        let doZero = base.arquivos.isEmpty
        let r = LeitorTranscripts.atualizar(base)
        if r.arquivosLidos > 0 || atual == nil { LeitorTranscripts.salvar(r.estado) }
        return Leitura(leitura: r, resumo: ResumoUso.bruto(r.estado, hoje: LeitorTranscripts.hoje()), doZero: doZero)
    }

    /// Troca cwd por projeto (raiz git, como as sessões da ilha) e junta os do mesmo projeto.
    private static func nomear(_ r: ResumoUso) -> ResumoUso {
        var r = r
        func juntar(_ linhas: [LinhaUso]) -> [LinhaUso] {
            var por: [String: LinhaUso] = [:]
            for l in linhas {
                let raiz = Projetos.raiz(de: l.id.isEmpty ? nil : l.id) ?? ""
                var x = por[raiz] ?? LinhaUso(id: raiz, nome: raiz.isEmpty ? "sem pasta" : (raiz as NSString).lastPathComponent,
                                              cor: raiz.isEmpty ? nil : Projetos.cor(de: raiz))
                x.valor = x.valor + l.valor
                por[raiz] = x
            }
            return por.values.sorted(by: ResumoUso.maisCaro)
        }
        r.projetosMes = juntar(r.projetosMes)
        r.projetosHoje = juntar(r.projetosHoje)
        r.sessoesSemana = r.sessoesSemana.map { s in
            var s = s
            s.projeto = Projetos.nome(de: s.cwd)
            s.cor = Projetos.cor(de: s.cwd)
            return s
        }
        return r
    }

    /// Título das sessões da semana (o do /rename, senão o automático), lido fora da main.
    private func buscarTitulos() async {
        let faltam = resumo.sessoesSemana.filter { $0.titulo == nil }.compactMap { s in s.caminho.map { (s.id, $0) } }
        guard !faltam.isEmpty else { return }
        let titulos = await Task.detached(priority: .utility) {
            var out: [String: String] = [:]
            for (id, caminho) in faltam { if let t = TranscriptReader.title(path: caminho) { out[id] = t } }
            return out
        }.value
        for i in resumo.sessoesSemana.indices {
            if let t = titulos[resumo.sessoesSemana[i].id] { resumo.sessoesSemana[i].titulo = t }
        }
    }

    /// O que cresceu no disco enquanto o alerta está ligado (chamado pela UsoVigia, na main).
    func transcriptCresceu() { atualizar() }

    /// Só para o modo de capturas: dados de exemplo, sem ler nada.
    func exemploParaCaptura() {
        let hoje = LeitorTranscripts.hoje()
        func v(_ custo: Double, _ tokens: Int64) -> ValorUso {
            ValorUso(tokens: Tokens(entrada: tokens / 200, saida: tokens / 300, escrita5m: tokens / 40,
                                    leituraCache: tokens - tokens / 200 - tokens / 300 - tokens / 40, mensagens: 100),
                     custo: custo)
        }
        let custos: [Double] = [42, 55, 18, 0, 61, 88, 73, 35, 12, 0, 0, 47, 66, 91, 120, 84, 58, 39, 77, 102,
                                131, 95, 64, 22, 351, 137, 146, 138, 36, 48]
        var r = ResumoUso()
        r.dias = custos.enumerated().map { i, c in DiaUso(dia: hoje - 29 + i, valor: v(c, Int64(c * 2_100_000))) }
        r.hoje = r.dias.last!.valor
        r.semana = r.ultimos7.reduce(ValorUso()) { $0 + $1.valor }
        r.mes = r.dias.reduce(ValorUso()) { $0 + $1.valor }
        r.projetosHoje = [LinhaUso(id: "/x/crew", nome: "crew", cor: "#FF7A59", valor: v(31.2, 64_000_000)),
                          LinhaUso(id: "/x/loja", nome: "loja", cor: "#38BDF8", valor: v(16.8, 35_000_000))]
        r.projetosMes = [LinhaUso(id: "/x/crew", nome: "crew", cor: "#FF7A59", valor: v(1210, 2_500_000_000)),
                         LinhaUso(id: "/x/loja", nome: "loja", cor: "#38BDF8", valor: v(690, 1_400_000_000)),
                         LinhaUso(id: "/x/v", nome: "vyramed", cor: "#A78BFA", valor: v(212, 450_000_000))]
        r.modelosMes = [LinhaUso(id: "claude-opus-5-5", nome: "Opus 5.5", valor: v(1320, 3_100_000_000)),
                        LinhaUso(id: "claude-fable-5-1", nome: "Fable 5.1", valor: v(790, 1_200_000_000))]
        r.sessoesSemana = [SessaoUso(id: "a", projeto: "crew", cor: "#FF7A59", titulo: "Módulo Uso — custo do Claude Code",
                                     ultima: Date(), valor: v(84.1, 160_000_000)),
                           SessaoUso(id: "b", projeto: "loja", cor: "#38BDF8", titulo: "Imprimir DANFE na impressora da casa",
                                     ultima: Date().addingTimeInterval(-86400), valor: v(51.7, 98_000_000))]
        resumo = r
        ultimaLeitura = Date()
        leituraCompleta = (2.8, 1_045_000_000, 608)
    }
}

@MainActor
enum FormatoUso {
    private static let numero: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.numberStyle = .decimal
        return f
    }()

    private static func n(_ v: Double, casas: Int) -> String {
        numero.minimumFractionDigits = casas
        numero.maximumFractionDigits = casas
        return numero.string(from: NSNumber(value: v)) ?? "\(v)"
    }

    /// "US$ 5,47"; acima de 100, sem centavos.
    static func custo(_ v: Double) -> String { "US$ " + n(v, casas: v >= 100 ? 0 : 2) }

    /// Custo, avisando quando parte dos tokens não tem preço.
    static func custo(_ v: ValorUso) -> String {
        if v.tokens.total > 0 && v.tokensSemPreco == v.tokens.total { return "sem preço" }
        return custo(v.custo) + (v.tokensSemPreco > 0 ? "+" : "")
    }

    /// "1,9 bi", "42,5 mi", "830 mil", "512".
    static func tokens(_ t: Int64) -> String {
        let d = Double(t)
        if d >= 1e9 { return n(d / 1e9, casas: 1) + " bi" }
        if d >= 1e6 { return n(d / 1e6, casas: d >= 1e8 ? 0 : 1) + " mi" }
        if d >= 1e3 { return n(d / 1e3, casas: 0) + " mil" }
        return "\(t)"
    }

    static func idade(_ d: Date?, agora: Date = Date()) -> String {
        guard let d else { return "—" }
        let s = max(0, agora.timeIntervalSince(d))
        if s < 60 { return "agora" }
        if s < 3600 { return "há \(Int(s / 60)) min" }
        if s < 86400 { return "há \(Int(s / 3600)) h" }
        let dias = Int(s / 86400)
        return dias == 1 ? "há 1 dia" : "há \(dias) dias"
    }

    /// Letra do dia da semana ("S", "T", "Q"…), domingo = "D".
    static func letraDia(_ d: DiaUso) -> String {
        ["D", "S", "T", "Q", "Q", "S", "S"][Calendar.current.component(.weekday, from: d.data) - 1]
    }

    static func data(_ d: DiaUso) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = "EEE, d 'de' MMM"
        return f.string(from: d.data)
    }

    static let cor = Color(hex: "#E8875B")
}
