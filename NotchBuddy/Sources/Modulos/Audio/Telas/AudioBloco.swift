import SwiftUI

/// Bloco da home: a saída de som atual; clique troca para a próxima (controle de relance).
struct AudioBloco: View {
    private let s = AudioServico.shared

    var body: some View {
        let atual = s.saidaAtual
        BlocoPainel(titulo: atual.map { ColunaDispositivos.nomeCurto($0.nome) } ?? "Sem saída",
                    legenda: s.saidas.count > 1 ? "clique para trocar" : "saída de som",
                    ajuda: "Trocar a saída de som (" + s.saidas.map { ColunaDispositivos.nomeCurto($0.nome) }.joined(separator: " → ") + ")",
                    acao: proxima) {
            Image(systemName: atual?.icone(entrada: false) ?? "speaker.slash")
                .font(.system(size: 12, weight: .medium)).foregroundColor(Color(hex: "#E8E9EC"))
                .frame(width: 24, height: 24).background(Circle().fill(Color.white.opacity(0.12)))
        }
    }

    private func proxima() {
        let lista = s.saidas
        guard lista.count > 1 else { abrirModulo("audio"); return }
        let i = lista.firstIndex { $0.id == s.saidaPadrao } ?? -1
        s.usarSaida(lista[(i + 1) % lista.count])
    }
}
