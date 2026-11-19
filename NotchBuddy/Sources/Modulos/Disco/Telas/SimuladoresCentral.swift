import SwiftUI

// Seção "Simuladores do iOS" da página do Disco na Central. Só aparece com o Xcode instalado.

struct SimuladoresCentral: View {
    private let s = SimuladoresServico.shared

    var body: some View {
        Group {
            if !s.temXcode {
                EmptyView()
            } else if let lista = s.confirmacao {
                confirmacao(lista)
            } else {
                Secao("Simuladores do iOS",
                      "Aparelhos do Simulador que estão desligados. Apagar remove o aparelho com os apps e os dados dele — é definitivo (não passa pela Lixeira); o sistema (runtime) fica e o Xcode cria outro quando precisar. Os ligados nunca aparecem.") {
                    BarraBusca(estado: s.estado, resumo: resumo, botao: "Procurar", desabilitado: s.apagando) { s.listar() }
                    if let u = s.ultimo {
                        Text("\(u.apagados.count) \(u.apagados.count == 1 ? "simulador apagado" : "simuladores apagados") · \(DiscoFormato.bytes(u.apagados.reduce(0) { $0 + $1.bytes })) · \(DiscoFormato.ha(u.quando))")
                            .font(.system(size: 11.5, weight: .medium)).foregroundColor(Color(hex: "#34D399"))
                        ListaRetirados(titulo: "Não apagados:", itens: u.falhas)
                    }
                    if case .pronto = s.estado {
                        if s.lista == nil {
                            Text("O simctl não respondeu. Tente de novo com o Xcode aberto uma vez.")
                                .font(.system(size: 12)).foregroundColor(.secondary)
                        } else if s.lista?.isEmpty == true {
                            Text("Nenhum simulador desligado.").font(.system(size: 12)).foregroundColor(.secondary)
                        } else {
                            ForEach(s.lista ?? []) { linha($0) }
                            Divider()
                            HStack {
                                Text("Selecionado: \(s.selecionadosItens.count) · \(DiscoFormato.bytes(s.selecionadosItens.reduce(0) { $0 + $1.bytes }))")
                                    .font(.system(size: 12, weight: .medium)).monospacedDigit()
                                Spacer()
                                Button("Apagar…") { s.prepararConfirmacao() }
                                    .disabled(s.selecionados.isEmpty || s.apagando)
                            }
                        }
                    }
                }
            }
        }
    }

    private var resumo: String {
        guard let l = s.lista else { return "sem resposta" }
        return "\(l.count) \(l.count == 1 ? "desligado" : "desligados") · \(DiscoFormato.bytes(s.total))"
    }

    private func linha(_ x: Simulador) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Toggle("", isOn: Binding(get: { s.selecionados.contains(x.id) }, set: { _ in s.alternar(x.id) }))
                .toggleStyle(.checkbox).labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(x.nome).font(.system(size: 12.5))
                    Text(x.sistema).font(.system(size: 10.5)).foregroundColor(.secondary)
                    if !x.disponivel {
                        Text("o Xcode não roda mais").font(.system(size: 9.5, weight: .medium))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.15)).clipShape(Capsule())
                    }
                }
                Text(x.ultimoUso.map { "Último uso \(DiscoFormato.idade($0))" } ?? "Último uso desconhecido")
                    .font(.system(size: 10.5)).foregroundColor(.secondary)
            }
            Spacer(minLength: 8)
            Text(DiscoFormato.bytes(x.bytes)).font(.system(size: 12)).monospacedDigit()
        }
    }

    private func confirmacao(_ lista: [Simulador]) -> some View {
        let total = lista.reduce(Int64(0)) { $0 + $1.bytes }
        return Secao("Confirmar: apagar simuladores — DEFINITIVO",
                     "Estes aparelhos do Simulador, com os apps e os dados deles, são apagados de vez pelo simctl. Não vão para a Lixeira e não dá para desfazer. Antes de cada um, o Crew confere de novo que ele continua desligado.") {
            ForEach(lista) { x in
                LinhaConfirmacao(nome: "\(x.nome) · \(x.sistema)", detalhe: x.udid, bytes: x.bytes)
            }
            RodapeConfirmacao(total: "Total: \(lista.count) · \(DiscoFormato.bytes(total))", botao: "Apagar de vez",
                              ocupado: s.apagando, destrutivo: true,
                              cancelar: { s.cancelarConfirmacao() }, confirmar: { s.confirmarApagar() })
        }
    }
}
