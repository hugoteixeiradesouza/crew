import Foundation

// O que as telas do Uso mostram, montado a partir dos baldes (dia × sessão × modelo).
// A soma roda fora da main; o nome do projeto (raiz git do cwd) é resolvido depois, na main,
// por `Projetos` — o mesmo critério do resto do Crew.

/// Tokens e custo estimado de um recorte. `tokensSemPreco` = tokens de modelos fora da tabela de preços.
struct ValorUso: Sendable, Equatable {
    var tokens = Tokens()
    var custo: Double = 0
    var tokensSemPreco: Int64 = 0

    mutating func somar(_ t: Tokens, modelo: String) {
        tokens += t
        if let c = Precos.custo(t, modelo: modelo) { custo += c } else { tokensSemPreco += t.total }
    }

    static func + (a: ValorUso, b: ValorUso) -> ValorUso {
        ValorUso(tokens: a.tokens + b.tokens, custo: a.custo + b.custo, tokensSemPreco: a.tokensSemPreco + b.tokensSemPreco)
    }
}

struct DiaUso: Sendable, Identifiable {
    let dia: Int
    var valor = ValorUso()
    var id: Int { dia }
    var data: Date { Date(timeIntervalSince1970: Double(dia) * 86400 + 43200 - Double(TimeZone.current.secondsFromGMT())) }
}

struct LinhaUso: Sendable, Identifiable {
    /// Projeto: raiz do repositório; modelo: id do modelo.
    let id: String
    var nome: String
    var cor: String?
    var valor = ValorUso()
}

struct SessaoUso: Sendable, Identifiable {
    let id: String
    var caminho: String?
    var cwd: String?
    var projeto: String?
    var cor: String?
    var titulo: String?
    var ultima: Date
    var valor = ValorUso()
}

struct ResumoUso: Sendable {
    var hoje = ValorUso()
    var semana = ValorUso()
    var mes = ValorUso()
    /// Últimos 30 dias, do mais antigo para hoje (dias sem uso entram zerados).
    var dias: [DiaUso] = []
    var projetosMes: [LinhaUso] = []
    var projetosHoje: [LinhaUso] = []
    var modelosMes: [LinhaUso] = []
    /// As 10 sessões mais caras dos últimos 7 dias.
    var sessoesSemana: [SessaoUso] = []

    var ultimos7: ArraySlice<DiaUso> { dias.suffix(7) }

    /// Soma por cwd (fora da main). `projetos*` saem com id = cwd e são juntados por projeto na main.
    static func bruto(_ e: EstadoUso, hoje: Int) -> ResumoUso {
        var r = ResumoUso()
        var dias: [Int: ValorUso] = [:]
        var projMes: [String: ValorUso] = [:], projHoje: [String: ValorUso] = [:]
        var modelos: [String: ValorUso] = [:]
        var sessoes: [String: ValorUso] = [:]
        for (k, t) in e.baldes {
            guard let p = EstadoUso.partes(k) else { continue }
            let idade = hoje - p.dia
            guard idade >= 0, idade < 30 else { continue }
            var v = ValorUso()
            v.somar(t, modelo: p.modelo)
            dias[p.dia, default: ValorUso()] = dias[p.dia, default: ValorUso()] + v
            let cwd = e.sessoes[p.sessao]?.cwd ?? ""
            projMes[cwd, default: ValorUso()] = projMes[cwd, default: ValorUso()] + v
            modelos[p.modelo, default: ValorUso()] = modelos[p.modelo, default: ValorUso()] + v
            r.mes = r.mes + v
            if idade < 7 {
                r.semana = r.semana + v
                sessoes[p.sessao, default: ValorUso()] = sessoes[p.sessao, default: ValorUso()] + v
            }
            if idade == 0 {
                r.hoje = r.hoje + v
                projHoje[cwd, default: ValorUso()] = projHoje[cwd, default: ValorUso()] + v
            }
        }
        r.dias = ((hoje - 29)...hoje).map { DiaUso(dia: $0, valor: dias[$0] ?? ValorUso()) }
        r.projetosMes = projMes.map { LinhaUso(id: $0.key, nome: $0.key, valor: $0.value) }
        r.projetosHoje = projHoje.map { LinhaUso(id: $0.key, nome: $0.key, valor: $0.value) }
        r.modelosMes = modelos.map { LinhaUso(id: $0.key, nome: Precos.nome($0.key), valor: $0.value) }
            .sorted(by: maisCaro)
        r.sessoesSemana = sessoes.sorted { maisCaro($0.value, $1.value) }.prefix(10).map { id, v in
            let s = e.sessoes[id]
            return SessaoUso(id: id, caminho: s?.caminho, cwd: s?.cwd,
                             ultima: Date(timeIntervalSince1970: s?.ultima ?? 0), valor: v)
        }
        return r
    }

    /// Ordem: custo; empate (ou sem preço), tokens.
    static func maisCaro(_ a: ValorUso, _ b: ValorUso) -> Bool {
        a.custo != b.custo ? a.custo > b.custo : a.tokens.total > b.tokens.total
    }
    static func maisCaro(_ a: LinhaUso, _ b: LinhaUso) -> Bool { maisCaro(a.valor, b.valor) }
}
