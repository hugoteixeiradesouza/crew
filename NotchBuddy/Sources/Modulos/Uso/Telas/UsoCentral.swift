import SwiftUI

// Página do Uso na Central: 30 dias em barras (custo ou tokens), por projeto, por modelo e as 10
// sessões mais caras da semana. Custo é estimativa pelos preços de referência da API; o plano pode
// ser assinatura, então os tokens são o número firme.

struct UsoCentral: View {
    private let s = UsoServico.shared
    @State private var emTokens = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Button { s.atualizar() } label: {
                    Label(s.lendo ? "Lendo…" : "Ler agora", systemImage: "arrow.clockwise")
                }
                .disabled(s.lendo)
                if let u = s.ultimaLeitura {
                    Text("Lido \(FormatoUso.idade(u))").font(.system(size: 11)).foregroundColor(.secondary)
                }
                Spacer()
                if let c = s.leituraCompleta {
                    Text(String(format: "Primeira leitura: %d arquivos, %@ em %.1f s", c.arquivos,
                                ByteCountFormatter.string(fromByteCount: Int64(c.bytes), countStyle: .file), c.segundos))
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
            }

            totais

            Secao("Últimos 30 dias", "Passe o mouse numa barra para ver o dia.") {
                Picker("", selection: $emTokens) {
                    Text("Custo estimado").tag(false)
                    Text("Tokens").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 240)
                grafico.frame(height: 120)
            }

            Secao("Por projeto (30 dias)", "Projeto = repositório git da pasta da sessão (worktrees contam como o repositório).") {
                tabela(s.resumo.projetosMes, total: s.resumo.mes, cor: true)
            }

            Secao("Por modelo (30 dias)", nil) {
                modelos
            }

            Secao("Sessões mais caras da semana", "As 10 de maior custo estimado nos últimos 7 dias (subagentes somados à sessão que os chamou).") {
                if s.resumo.sessoesSemana.isEmpty {
                    Text(s.ultimaLeitura == nil ? "Lendo…" : "Nenhuma sessão nos últimos 7 dias.")
                        .font(.system(size: 12)).foregroundColor(.secondary)
                }
                ForEach(s.resumo.sessoesSemana) { sessao in linhaSessao(sessao) }
            }

            Text("Preços de referência de \(Precos.conferidoEm) (API da Anthropic, US$ por milhão de tokens; escrita de cache a 1,25× a entrada em 5 min e 2× em 1 h). Seu plano pode ser assinatura: aí o custo é só uma régua e os tokens são o número que vale. Modelo sem preço conhecido aparece só em tokens (\"sem preço\", ou \"+\" quando parte do valor ficou de fora).")
                .font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            tabelaPrecos
        }
        .onAppear { s.atualizarSeVelho(validade: 15) }
    }

    // MARK: Totais

    private var totais: some View {
        HStack(spacing: 12) {
            cartao("Hoje", s.resumo.hoje)
            cartao("7 dias", s.resumo.semana)
            cartao("30 dias", s.resumo.mes)
        }
    }

    private func cartao(_ titulo: String, _ v: ValorUso) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(titulo).font(.system(size: 11)).foregroundColor(.secondary)
            Text(FormatoUso.custo(v)).font(.system(size: 20, weight: .semibold, design: .rounded)).monospacedDigit()
            Text("\(FormatoUso.tokens(v.tokens.total)) tokens · \(FormatoUso.tokens(v.tokens.saida)) de saída")
                .font(.system(size: 11)).foregroundColor(.secondary).monospacedDigit()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: Gráfico

    private var grafico: some View {
        let dias = s.resumo.dias
        let valor: (DiaUso) -> Double = { emTokens ? Double($0.valor.tokens.total) : $0.valor.custo }
        let maior = max(dias.map(valor).max() ?? 0, 0.0001)
        return VStack(spacing: 4) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(dias.enumerated()), id: \.element.id) { i, d in
                    let v = valor(d)
                    ZStack(alignment: .bottom) {
                        Rectangle().fill(Color.primary.opacity(0.0001))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(FormatoUso.cor.opacity(i == dias.count - 1 ? 1 : 0.7))
                            .frame(height: v > 0 ? max(2, 100 * v / maior) : 0)
                    }
                    .frame(maxWidth: .infinity)
                    .help("\(FormatoUso.data(d)): \(FormatoUso.custo(d.valor)) · \(FormatoUso.tokens(d.valor.tokens.total)) tokens")
                }
            }
            .frame(height: 100)
            HStack {
                Text(dias.first.map(FormatoUso.data) ?? "")
                Spacer()
                Text("máx. " + (emTokens ? FormatoUso.tokens(Int64(maior)) : FormatoUso.custo(maior)))
                Spacer()
                Text("hoje")
            }
            .font(.system(size: 10)).foregroundColor(.secondary)
        }
    }

    // MARK: Tabelas

    private func tabela(_ linhas: [LinhaUso], total: ValorUso, cor: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if linhas.isEmpty {
                Text(s.ultimaLeitura == nil ? "Lendo…" : "Nada nos últimos 30 dias.")
                    .font(.system(size: 12)).foregroundColor(.secondary)
            }
            ForEach(linhas) { l in
                HStack(spacing: 8) {
                    if cor { Circle().fill(Color(hex: l.cor ?? "#8E939C")).frame(width: 8, height: 8) }
                    Text(l.nome).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                        .frame(width: 170, alignment: .leading)
                    GeometryReader { g in
                        let f = total.tokens.total > 0 ? Double(l.valor.tokens.total) / Double(total.tokens.total) : 0
                        RoundedRectangle(cornerRadius: 2).fill(FormatoUso.cor.opacity(0.55))
                            .frame(width: max(2, g.size.width * f), height: 6)
                            .frame(maxHeight: .infinity, alignment: .center)
                    }
                    .frame(height: 12)
                    Text(FormatoUso.tokens(l.valor.tokens.total)).font(.system(size: 11.5)).foregroundColor(.secondary)
                        .monospacedDigit().frame(width: 64, alignment: .trailing)
                    Text(FormatoUso.custo(l.valor)).font(.system(size: 12)).monospacedDigit()
                        .frame(width: 80, alignment: .trailing)
                }
            }
        }
    }

    private var modelos: some View {
        Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 6) {
            GridRow {
                Text("Modelo").gridColumnAlignment(.leading)
                Text("Entrada"); Text("Saída"); Text("Escrita cache"); Text("Leitura cache"); Text("Custo")
            }
            .font(.system(size: 10.5, weight: .medium)).foregroundColor(.secondary)
            ForEach(s.resumo.modelosMes) { m in
                GridRow {
                    Text(m.nome).font(.system(size: 12, weight: .medium))
                    Text(FormatoUso.tokens(m.valor.tokens.entrada))
                    Text(FormatoUso.tokens(m.valor.tokens.saida))
                    Text(FormatoUso.tokens(m.valor.tokens.escrita))
                    Text(FormatoUso.tokens(m.valor.tokens.leituraCache))
                    Text(FormatoUso.custo(m.valor)).foregroundColor(.primary)
                }
                .font(.system(size: 11.5)).foregroundColor(.secondary).monospacedDigit()
            }
            if s.resumo.modelosMes.isEmpty {
                GridRow { Text(s.ultimaLeitura == nil ? "Lendo…" : "Nada nos últimos 30 dias.").foregroundColor(.secondary) }
                    .font(.system(size: 12))
            }
        }
    }

    private func linhaSessao(_ x: SessaoUso) -> some View {
        HStack(spacing: 8) {
            Circle().fill(Color(hex: x.cor ?? "#8E939C")).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(x.titulo ?? "Sessão \(x.id.prefix(8))").font(.system(size: 12, weight: .medium))
                    .lineLimit(1).truncationMode(.tail)
                Text("\(x.projeto ?? "sem pasta") · \(FormatoUso.idade(x.ultima))")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }
            Spacer()
            Text(FormatoUso.tokens(x.valor.tokens.total)).font(.system(size: 11.5)).foregroundColor(.secondary)
                .monospacedDigit().frame(width: 64, alignment: .trailing)
            Text(FormatoUso.custo(x.valor)).font(.system(size: 12)).monospacedDigit()
                .frame(width: 80, alignment: .trailing)
        }
    }

    private var tabelaPrecos: some View {
        Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 3) {
            GridRow {
                Text("Modelo").gridColumnAlignment(.leading)
                Text("Entrada"); Text("Saída"); Text("Leitura cache")
            }
            .foregroundColor(.secondary)
            ForEach(Precos.tabela, id: \.prefixo) { e in
                GridRow {
                    Text(e.nome)
                    Text(FormatoUso.custo(e.preco.entrada)); Text(FormatoUso.custo(e.preco.saida))
                    Text(FormatoUso.custo(e.preco.leituraCache))
                }
                .monospacedDigit()
            }
        }
        .font(.system(size: 10.5))
    }
}

/// Ajustes do Uso: o alerta de custo do dia (desligado por padrão).
struct UsoAjustes: View {
    @State private var ligado = UsoAlerta.ligado
    @State private var limite = UsoAlerta.limite

    var body: some View {
        Toggle("Avisar na ilha quando o custo estimado do dia passar de", isOn: $ligado)
            .onChange(of: ligado) { _, v in UsoAlerta.ligado = v }
        HStack(spacing: 6) {
            Text("US$")
            TextField("", value: $limite, format: .number.precision(.fractionLength(0...2)))
                .frame(width: 80)
                .onSubmit { UsoAlerta.limite = max(0, limite) }
                .onChange(of: limite) { _, v in UsoAlerta.limite = max(0, v) }
            Text("por dia").foregroundColor(.secondary)
        }
        .disabled(!ligado)
        Text("Aviso uma vez por dia. Enquanto ligado, o Crew recebe do macOS um aviso quando os transcripts do Claude Code mudam (no máximo um por minuto, sem timer) e lê só o que cresceu. Desligado, nada roda sem você abrir a aba ou esta página.")
            .font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}
