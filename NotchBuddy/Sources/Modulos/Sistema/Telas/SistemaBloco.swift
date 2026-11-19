import SwiftUI

/// Bloco da home: CPU e memória de relance. Lê só enquanto a home está na tela.
struct SistemaBloco: View {
    @Environment(\.telaVisivel) private var telaVisivel
    private let s = SistemaServico.shared

    var body: some View {
        BlocoPainel(titulo: "CPU \(FormatoSistema.pct(s.cpu.total))",
                    legenda: "Mem \(FormatoSistema.pct(s.memoria.fracao))" + (s.temperatura.map { " · \(Int($0.rounded()))°" } ?? ""),
                    ajuda: "Abrir Sistema", acao: { abrirModulo("sistema") }) {
            AnelSistema(fracao: s.cpu.total, texto: "", cor: FormatoSistema.corCPU, espessura: 3)
        }
        .onAppear { if telaVisivel { s.assinar("home", [.rapido, .temperatura]) } }
        .onChange(of: telaVisivel) { _, v in v ? s.assinar("home", [.rapido, .temperatura]) : s.soltar("home", [.rapido, .temperatura]) }
        .onDisappear { s.soltar("home", [.rapido, .temperatura]) }
    }
}
