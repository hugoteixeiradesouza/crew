import SwiftUI

/// Bloco da home: quantas pendências estão em aberto e a que vence primeiro. Clique abre o Diário.
struct DiarioBloco: View {
    private let s = DiarioServico.shared

    var body: some View {
        let abertas = s.abertas
        let prox = abertas.first
        BlocoPainel(titulo: abertas.isEmpty ? "Tudo em dia" : "\(abertas.count) em aberto",
                    legenda: prox.map { p in p.prazo.map { "\(p.acaoCurta) · \(FormatoDiario.quando($0))" } ?? p.acaoCurta }
                        ?? "nada em aberto",
                    ajuda: "Abrir as Tasks", acao: { abrirModulo(DiarioServico.idModulo) }) {
            Image(systemName: abertas.isEmpty ? "checkmark.circle" : "tray.full")
                .font(.system(size: 14))
                .foregroundColor(Color(hex: abertas.isEmpty ? "#34D399" : "#F5A524"))
        }
    }
}
