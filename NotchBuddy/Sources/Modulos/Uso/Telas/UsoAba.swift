import SwiftUI

// Aba do Uso na ilha: hoje (custo estimado e tokens), os últimos 7 dias em barrinhas e o projeto
// que mais gastou hoje. "Detalhes" abre a Central na página do módulo. Lê ao aparecer, se a
// última leitura tiver mais de 30 s (só o que cresceu nos transcripts).

struct UsoAba: View {
    @Environment(\.telaVisivel) private var telaVisivel
    private let s = UsoServico.shared

    private let cinza = Color(hex: "#8E939C")
    private let apagado = Color(hex: "#5F646D")
    private let claro = Color(hex: "#F1F2F4")

    var body: some View {
        ZStack {
            CardBackground(wash: nil)
            HStack(spacing: 16) {
                hoje.frame(width: 118, alignment: .leading)
                separador
                semana.frame(width: 176)
                separador
                topoHoje.frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 108)
            .padding(.trailing, 16)
        }
        .onAppear { if telaVisivel { s.atualizarSeVelho() } }
        .onChange(of: telaVisivel) { _, v in if v { s.atualizarSeVelho() } }
    }

    private var separador: some View {
        Rectangle().fill(Color.white.opacity(0.07)).frame(width: 1, height: 64)
    }

    private var hoje: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Hoje").font(.system(size: 10.5, weight: .medium)).foregroundColor(cinza)
            if s.ultimaLeitura == nil {
                Text("—").font(.system(size: 26, weight: .semibold, design: .rounded)).foregroundColor(apagado)
                Text(s.lendo ? "Lendo transcripts…" : " ").font(.system(size: 11)).foregroundColor(cinza)
            } else {
                Text(FormatoUso.custo(s.resumo.hoje))
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundColor(claro).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text("\(FormatoUso.tokens(s.resumo.hoje.tokens.total)) tokens")
                    .font(.system(size: 11)).foregroundColor(cinza).monospacedDigit()
            }
        }
    }

    private var semana: some View {
        let dias = Array(s.resumo.ultimos7)
        let maior = max(dias.map(\.valor.custo).max() ?? 0, 0.01)
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("7 dias").foregroundColor(cinza)
                Spacer()
                Text(s.ultimaLeitura == nil ? "" : FormatoUso.custo(s.resumo.semana))
                    .foregroundColor(claro).monospacedDigit()
            }
            .font(.system(size: 10.5, weight: .medium))
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(dias.enumerated()), id: \.element.id) { i, d in
                    let eHoje = i == dias.count - 1
                    VStack(spacing: 3) {
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.05))
                            RoundedRectangle(cornerRadius: 3)
                                .fill(eHoje ? FormatoUso.cor : FormatoUso.cor.opacity(0.45))
                                .frame(height: max(d.valor.custo > 0 ? 3 : 0, 40 * d.valor.custo / maior))
                        }
                        .frame(height: 40)
                        Text(FormatoUso.letraDia(d)).font(.system(size: 9.5, weight: eHoje ? .semibold : .regular))
                            .foregroundColor(eHoje ? claro : apagado)
                    }
                    .frame(maxWidth: .infinity)
                    .help("\(FormatoUso.data(d)): \(FormatoUso.custo(d.valor)) · \(FormatoUso.tokens(d.valor.tokens.total)) tokens")
                }
            }
        }
    }

    private var topoHoje: some View {
        let topo = s.resumo.projetosHoje.first
        return VStack(alignment: .leading, spacing: 4) {
            Text("Mais gastou hoje").font(.system(size: 10.5, weight: .medium)).foregroundColor(cinza)
            if let p = topo, p.valor.tokens.total > 0 {
                HStack(spacing: 6) {
                    Circle().fill(Color(hex: p.cor ?? "#8E939C")).frame(width: 7, height: 7)
                    Text(p.nome).font(.system(size: 13, weight: .semibold)).foregroundColor(claro)
                        .lineLimit(1).truncationMode(.middle)
                }
                Text("\(FormatoUso.custo(p.valor)) · \(FormatoUso.tokens(p.valor.tokens.total))")
                    .font(.system(size: 11)).foregroundColor(cinza).monospacedDigit().lineLimit(1)
            } else {
                Text(s.ultimaLeitura == nil ? "…" : "Nada hoje ainda")
                    .font(.system(size: 12)).foregroundColor(apagado)
            }
            HStack {
                Spacer()
                Button { Central.abrir(modulo: UsoModulo.shared.id) } label: {
                    HStack(spacing: 3) {
                        Text("Detalhes").font(.system(size: 11, weight: .medium))
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundColor(cinza)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
