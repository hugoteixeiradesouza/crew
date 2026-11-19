import SwiftUI

/// Aviso de pendência na barra da ilha fechada: a ação e de onde veio. Clique abre a aba do
/// Diário com a pendência em destaque e as 3 saídas (Feito · Adiar · Ignorar).
struct AvisoDiario: View {
    /// Ação curta (até ~5 palavras): corta no fim, nunca no meio.
    let acao: String
    /// "12:00 · em 15 min", "agora · 12:00", "pra já" — nunca corta.
    let quando: String
    /// "você anotou às 11:40" — segunda linha, só se couber.
    let origem: String
    let cor: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "bell.badge.fill").font(.system(size: 12.5, weight: .semibold)).foregroundColor(cor)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    Text(acao).font(.system(size: 12, weight: .semibold)).foregroundColor(Color(hex: "#ECEDEF"))
                        .lineLimit(1).truncationMode(.tail)
                    Text(quando).font(.system(size: 11.5, weight: .medium)).foregroundColor(cor)
                        .lineLimit(1).fixedSize()
                }
                Text(origem).font(.system(size: 10)).foregroundColor(Color(hex: "#8E939C"))
                    .lineLimit(1).truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            DiarioServico.shared.detalhe = DiarioServico.shared.destaque
            abrirModulo(DiarioServico.idModulo)
        }
        .help("\(acao) (\(quando)) — \(origem). Clique para resolver.")
    }
}

/// "Resumo do dia pronto" na barra; clique abre o Diário na Central (onde o resumo cabe).
struct AvisoResumoPronto: View {
    var body: some View {
        AvisoBarra(icone: "text.book.closed.fill", texto: "Resumo do dia pronto — clique para ver",
                   cor: Color(hex: "#A78BFA"))
            .contentShape(Rectangle())
            .onTapGesture {
                Arbitro.shared.retirar("diario.resumo")
                Central.abrir(modulo: DiarioServico.idModulo)
            }
    }
}
