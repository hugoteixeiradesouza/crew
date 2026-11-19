import SwiftUI

// Aba do Sistema na ilha: anéis (CPU, memória, temperatura), histórico e os 3 processos que
// mais gastam. Assina os leitores só enquanto está na tela. O botão no canto expande a ilha
// para o monitor de atividade (todos os processos); recolher volta a esta aba.

struct SistemaAba: View {
    @ObservedObject private var ilha = AppState.shared
    /// Altura da ilha com o monitor aberto.
    static let alturaMonitor: CGFloat = 450

    /// Expandir é o mesmo cartão crescendo: o resumo (anéis, histórico, processos) fica onde
    /// está, com o Homie ao lado, e o monitor de atividade aparece embaixo dele.
    var body: some View {
        ZStack(alignment: .top) {
            CardBackground(wash: nil)
            VStack(spacing: 0) {
                SistemaAbaResumo(aberto: ilha.alturaAba != nil).frame(height: Self.alturaResumo)
                if ilha.alturaAba != nil {
                    MonitorAtividade(naIlha: true,
                                     abaInicial: MonitorAtividade.captura?.aba ?? .cpu,
                                     selecionadoInicial: MonitorAtividade.captura?.pid,
                                     confirmarInicial: MonitorAtividade.captura?.confirmar)
                        .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 12)
                        .transition(.opacity)
                }
            }
        }
    }

    /// Altura do cartão normal da aba (o resumo ocupa sempre esta faixa de cima).
    static let alturaResumo: CGFloat = 98
}

struct SistemaAbaResumo: View {
    var aberto = false
    @Environment(\.telaVisivel) private var telaVisivel
    private let s = SistemaServico.shared

    var body: some View {
        ZStack {
            HStack(spacing: 14) {
                HStack(spacing: 10) {
                    rotulado("CPU") { AnelSistema(fracao: s.cpu.total, texto: FormatoSistema.pct(s.cpu.total), cor: FormatoSistema.corCPU) }
                    rotulado("Memória") { AnelSistema(fracao: s.memoria.fracao, texto: FormatoSistema.pct(s.memoria.fracao),
                                                      cor: FormatoSistema.corPressao(s.memoria.pressao)) }
                    rotulado("Temp.") { AnelSistema(fracao: (s.temperatura ?? 0) / 100, texto: FormatoSistema.temp(s.temperatura),
                                                    cor: FormatoSistema.corTemp(s.temperatura)) }
                }
                VStack(alignment: .leading, spacing: 4) {
                    GraficoHistorico(pontos: s.historicoCPU, total: SistemaServico.pontosHistorico, cor: FormatoSistema.corCPU)
                        .frame(height: 40)
                        .background(Color.white.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    if s.cpu.nucleosE > 0 {
                        Text("E \(FormatoSistema.pct(s.cpu.eficiencia)) · P \(FormatoSistema.pct(s.cpu.desempenho))")
                            .font(.system(size: 10.5)).foregroundColor(Color(hex: "#9398A1")).monospacedDigit()
                    }
                }
                .frame(width: 118)
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(s.processos.prefix(3)) { p in
                        HStack(spacing: 6) {
                            Text(p.nome).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 4)
                            Text(FormatoSistema.pct(p.cpu)).monospacedDigit().foregroundColor(Color(hex: "#9398A1"))
                        }
                        .font(.system(size: 11))
                    }
                    if s.processos.isEmpty {
                        Text("Lendo…").font(.system(size: 11)).foregroundColor(Color(hex: "#5F646D"))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 108)
            .padding(.trailing, 16)
            // Expandir/recolher o monitor é só rolar (elástico da ilha), sem botão
        }
        .onAppear { if telaVisivel { s.assinar("aba") } }
        .onChange(of: telaVisivel) { _, v in v ? s.assinar("aba") : s.soltar("aba") }
        .onDisappear { s.soltar("aba") }
    }

    private func rotulado<C: View>(_ nome: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(spacing: 4) {
            c().frame(width: 52, height: 52)
            Text(nome).font(.system(size: 10)).foregroundColor(Color(hex: "#8E939C")).lineLimit(1).fixedSize()
        }
    }
}
