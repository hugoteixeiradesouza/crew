import SwiftUI

/// Bloco da home: custo estimado e tokens de hoje.
struct UsoBloco: View {
    private let s = UsoServico.shared

    var body: some View {
        BlocoPainel(titulo: "\(FormatoUso.custo(s.resumo.hoje)) hoje",
                    legenda: "\(FormatoUso.tokens(s.resumo.hoje.tokens.total)) tokens",
                    ajuda: "Abrir Uso", acao: { abrirModulo("uso") }) {
            Image(systemName: "chart.bar.fill").font(.system(size: 13)).foregroundColor(Color(hex: "#C9CDD3"))
        }
        .onAppear { s.atualizarSeVelho(validade: 120) }
    }
}
