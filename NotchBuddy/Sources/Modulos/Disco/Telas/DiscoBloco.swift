import SwiftUI

/// Bloco da home: espaço livre e, se já procurou, quanto dá para recuperar.
struct DiscoBloco: View {
    @Environment(\.telaVisivel) private var telaVisivel
    private let s = DiscoServico.shared

    var body: some View {
        let livre = s.volume.map { "\(Int((Double($0.livre) / 1e9).rounded())) GB" } ?? "—"
        BlocoPainel(titulo: "\(livre) livres",
                    legenda: s.recuperavel > 0 ? "\(Int((Double(s.recuperavel) / 1e9).rounded())) GB a limpar" : "no disco",
                    ajuda: "Abrir Disco", acao: { abrirModulo("disco") }) {
            Image(systemName: "internaldrive").font(.system(size: 14)).foregroundColor(Color(hex: "#C9CDD3"))
        }
        .onAppear { if telaVisivel { s.assinar("home") } }
        .onChange(of: telaVisivel) { _, v in v ? s.assinar("home") : s.soltar("home") }
        .onDisappear { s.soltar("home") }
    }
}
