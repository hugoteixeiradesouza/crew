import SwiftUI

// Aba dos Agentes na ilha: quantas worktrees órfãs há e quanto ocupam, as ativas mais recentes
// e o botão "Revisar" (abre a Central na página do módulo). Varre ao aparecer, se a última varredura for velha.

struct AgentesAba: View {
    @Environment(\.telaVisivel) private var telaVisivel
    private let s = AgentesServico.shared

    private let cinza = Color(hex: "#8E939C")
    private let apagado = Color(hex: "#5F646D")

    var body: some View {
        ZStack {
            CardBackground(wash: nil)
            HStack(spacing: 16) {
                resumoOrfas.frame(width: 128, alignment: .leading)
                Rectangle().fill(Color.white.opacity(0.07)).frame(width: 1, height: 64)
                ativasRecentes.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 8) {
                    PrimaryButton("Revisar") { Central.abrir(modulo: AgentesModulo.shared.id) }
                    Button { s.varrer() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise").font(.system(size: 10, weight: .semibold))
                            Text(s.varrendo ? "Varrendo…" : "Varrer").font(.system(size: 11))
                        }
                        .foregroundColor(cinza)
                    }
                    .buttonStyle(.plain)
                    .disabled(s.varrendo)
                }
            }
            .padding(.leading, 108)
            .padding(.trailing, 16)
        }
        .onAppear { if telaVisivel { s.varrerSeVelho() } }
        .onChange(of: telaVisivel) { _, v in if v { s.varrerSeVelho() } }
    }

    private var resumoOrfas: some View {
        VStack(alignment: .leading, spacing: 3) {
            if s.ultimaVarredura == nil {
                Text("—").font(.system(size: 28, weight: .semibold, design: .rounded)).foregroundColor(apagado)
                Text("Lendo worktrees…").font(.system(size: 11)).foregroundColor(cinza)
            } else if s.orfas.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(Color(hex: "#34D399"))
                    Text("Nenhuma órfã").font(.system(size: 13, weight: .semibold)).foregroundColor(Color(hex: "#F5F6F8"))
                }
                Text("Nada para limpar").font(.system(size: 11)).foregroundColor(cinza)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(s.orfas.count)")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundColor(Color(hex: "#F5A524"))
                        .monospacedDigit()
                    Text(s.orfas.count == 1 ? "órfã" : "órfãs")
                        .font(.system(size: 12, weight: .medium)).foregroundColor(Color(hex: "#F1F2F4"))
                }
                Text(s.medindo && s.totalOrfas == 0 ? "medindo…" : "\(s.orfas.count == 1 ? "ocupa" : "ocupam") \(FormatoAgentes.bytes(s.totalOrfas))")
                    .font(.system(size: 11)).foregroundColor(cinza).monospacedDigit()
            }
        }
    }

    private var ativasRecentes: some View {
        let recentes = s.ativas.flatMap { r in r.worktrees.filter { !$0.pastaSumiu }.map { (r.nome, $0) } }
            .sorted { ($0.1.ultimaMudanca ?? .distantPast) > ($1.1.ultimaMudanca ?? .distantPast) }
        return VStack(alignment: .leading, spacing: 4) {
            Text("\(s.totalAtivas) ativas · \(s.ativasEmUso) em uso")
                .font(.system(size: 10.5, weight: .medium)).foregroundColor(cinza)
            ForEach(Array(recentes.prefix(3)), id: \.1.id) { projeto, w in
                HStack(spacing: 6) {
                    Circle().fill(w.emUso ? Color(hex: "#34D399") : Color.white.opacity(0.18)).frame(width: 6, height: 6)
                    Text(projeto).foregroundColor(cinza)
                    Text(w.branch ?? w.commit ?? w.nome).foregroundColor(Color(hex: "#F1F2F4"))
                        .lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 4)
                    Text(FormatoAgentes.idade(w.ultimaMudanca)).foregroundColor(apagado).monospacedDigit()
                }
                .font(.system(size: 11))
            }
            if recentes.isEmpty && s.ultimaVarredura != nil {
                Text("Nenhuma worktree ativa nos projetos do Claude Code.")
                    .font(.system(size: 11)).foregroundColor(apagado)
            }
        }
    }
}
