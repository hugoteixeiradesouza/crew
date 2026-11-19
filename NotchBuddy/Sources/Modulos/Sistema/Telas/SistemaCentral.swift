import SwiftUI

// Página do Sistema na Central: o painel completo.

struct SistemaCentral: View {
    private let s = SistemaServico.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 22) {
                grande("CPU", AnelSistema(fracao: s.cpu.total, texto: FormatoSistema.pct(s.cpu.total), cor: FormatoSistema.corCPU,
                                          espessura: 8, fonte: 17, trilho: Color.primary.opacity(0.08)))
                grande("Memória", AnelSistema(fracao: s.memoria.fracao, texto: FormatoSistema.pct(s.memoria.fracao),
                                              cor: FormatoSistema.corPressao(s.memoria.pressao), espessura: 8, fonte: 17,
                                              trilho: Color.primary.opacity(0.08)))
                grande("Temperatura", AnelSistema(fracao: (s.temperatura ?? 0) / 100, texto: FormatoSistema.temp(s.temperatura),
                                                  cor: FormatoSistema.corTemp(s.temperatura), espessura: 8, fonte: 17,
                                                  trilho: Color.primary.opacity(0.08)))
                if let g = s.gpu {
                    grande("GPU", AnelSistema(fracao: g, texto: FormatoSistema.pct(g), cor: FormatoSistema.corGPU,
                                              espessura: 8, fonte: 17, trilho: Color.primary.opacity(0.08)))
                }
            }

            Secao("Uso de CPU", "Últimos \(SistemaServico.pontosHistorico) segundos.") {
                GraficoHistorico(pontos: s.historicoCPU, total: SistemaServico.pontosHistorico, cor: FormatoSistema.corCPU)
                    .frame(height: 90)
                HStack(spacing: 18) {
                    par("Sistema", FormatoSistema.pct(s.cpu.sistema))
                    par("Usuário", FormatoSistema.pct(s.cpu.usuario))
                    if s.cpu.nucleosE > 0 {
                        par("Eficiência (\(s.cpu.nucleosE))", FormatoSistema.pct(s.cpu.eficiencia))
                        par("Desempenho (\(s.cpu.nucleosP))", FormatoSistema.pct(s.cpu.desempenho))
                    }
                }
                HStack(spacing: 18) {
                    par("Carga 1 min", String(format: "%.2f", s.carga.um))
                    par("5 min", String(format: "%.2f", s.carga.cinco))
                    par("15 min", String(format: "%.2f", s.carga.quinze))
                    par("Ligado há", FormatoSistema.duracao(s.carga.ligadoHa))
                }
            }

            Secao("Monitor de atividade", "Todos os processos do Mac. Os do sistema (root e outros usuários) mostram só CPU e memória residente, lidos pelo ps; encerrar fica só para os seus.") {
                MonitorAtividade(naIlha: false)
                    .frame(height: 520)
            }

            Secao("Memória", nil) {
                HStack(spacing: 18) {
                    par("Em uso", "\(FormatoSistema.bytes(s.memoria.usada)) de \(FormatoSistema.bytes(s.memoria.total))")
                    par("Apps", FormatoSistema.bytes(s.memoria.app))
                    par("Fixa", FormatoSistema.bytes(s.memoria.fixa))
                    par("Comprimida", FormatoSistema.bytes(s.memoria.comprimida))
                    par("Swap", FormatoSistema.bytes(s.memoria.swapUsado))
                    par("Pressão", s.memoria.pressao >= 4 ? "crítica" : s.memoria.pressao >= 2 ? "atenção" : "normal")
                }
            }

            HStack(alignment: .top, spacing: 14) {
                Secao("Rede", nil) {
                    par("Recebendo", FormatoSistema.taxa(s.rede.entrada))
                    par("Enviando", FormatoSistema.taxa(s.rede.saida))
                }
                Secao("Disco", nil) {
                    let usado = s.disco.total > 0 ? 1 - Double(s.disco.livre) / Double(s.disco.total) : 0
                    ProgressView(value: usado).tint(usado > 0.9 ? .red : .accentColor)
                    par("Livre", "\(FormatoSistema.disco(s.disco.livre)) de \(FormatoSistema.disco(s.disco.total))")
                }
                if let b = s.bateria {
                    Secao("Bateria", nil) {
                        par("Nível", FormatoSistema.pct(b.nivel) + (b.carregando ? " · carregando" : b.naTomada ? " · na tomada" : ""))
                        if let m = b.minutosRestantes { par(b.carregando ? "Até encher" : "Restante", FormatoSistema.duracao(Double(m * 60))) }
                        if let sa = b.saude { par("Saúde", FormatoSistema.pct(sa)) }
                        if let c = b.ciclos { par("Ciclos", "\(c)") }
                    }
                }
            }
        }
        .onAppear { s.assinar("central", [.rapido, .temperatura, .lento]) }
        .onDisappear { s.soltar("central", [.rapido, .temperatura, .lento]) }
    }

    private func grande<V: View>(_ nome: String, _ anel: V) -> some View {
        VStack(spacing: 6) {
            anel.frame(width: 84, height: 84)
            Text(nome).font(.system(size: 11)).foregroundColor(.secondary)
        }
    }

    private func par(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(k).font(.system(size: 10.5)).foregroundColor(.secondary)
            Text(v).font(.system(size: 13, weight: .medium)).monospacedDigit()
        }
    }
}
