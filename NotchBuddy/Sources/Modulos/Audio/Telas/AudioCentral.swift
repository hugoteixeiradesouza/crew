import SwiftUI

// Página do Áudio na Central: listas completas, alertas do sistema, o que aconteceu, e os ajustes
// da trava do microfone.

struct AudioCentral: View {
    private let s = AudioServico.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VolumePorAppCentral()
            Secao("Saída", "Para onde vai o som do Mac. Clique para trocar.") {
                lista(s.saidas, atual: s.saidaPadrao, entrada: false) { s.usarSaida($0) }
            }
            Secao("Entrada", "O microfone que os apps usam. Trocar não abre o microfone.") {
                lista(s.entradas, atual: s.entradaPadrao, entrada: true) { s.usarEntrada($0) }
            }
            Secao("Alertas e efeitos sonoros", "Onde tocam os sons do sistema (aviso, Lixeira, captura de tela).") {
                SeletorCrew(selecao: Binding(get: { s.somDoSistema },
                                             set: { id in if let d = s.saidas.first(where: { $0.id == id }) { s.usarSomDoSistema(d) } }),
                            opcoes: s.saidas.map { (valor: $0.id, titulo: $0.nome) })
                    .frame(maxWidth: 320, alignment: .leading)
            }
            Secao("O que aconteceu", "Conexões, trocas e devoluções do microfone desde que o Crew abriu.") {
                if s.historico.isEmpty {
                    Text("Nada ainda.").font(.system(size: 12)).foregroundColor(.secondary)
                }
                ForEach(s.historico.prefix(12)) { e in
                    HStack(spacing: 8) {
                        Image(systemName: e.icone).frame(width: 18).foregroundColor(.secondary)
                        Text(e.texto).lineLimit(1)
                        Spacer()
                        Text(e.data.formatted(date: .omitted, time: .shortened)).foregroundColor(.secondary).monospacedDigit()
                    }
                    .font(.system(size: 12))
                }
            }
        }
    }

    private func lista(_ ds: [DispositivoAudio], atual: UInt32, entrada: Bool,
                       usar: @escaping (DispositivoAudio) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(ds) { d in
                Button { usar(d) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: d.icone(entrada: entrada)).frame(width: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(d.nome).font(.system(size: 13, weight: d.id == atual ? .semibold : .regular))
                            Text(detalhe(d, entrada: entrada)).font(.system(size: 11)).foregroundColor(.secondary)
                        }
                        Spacer()
                        if d.id == atual {
                            Image(systemName: "checkmark").foregroundColor(.accentColor)
                        }
                    }
                    .padding(.vertical, 5).padding(.horizontal, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if ds.isEmpty {
                Text("Nenhum dispositivo.").font(.system(size: 12)).foregroundColor(.secondary)
            }
        }
    }

    private func detalhe(_ d: DispositivoAudio, entrada: Bool) -> String {
        var partes = [d.transporte.nome]
        if !entrada && !d.volumeNoHardware { partes.append("sem controle de volume pelo macOS") }
        if entrada && d.uid == s.micTravadoUID && s.travaLigada { partes.append("travado") }
        return partes.joined(separator: " · ")
    }
}

/// Ajustes do Áudio: trava do microfone e alertas acompanhando a saída.
struct AudioAjustes: View {
    @Bindable private var s = AudioServico.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Manter o microfone fixo", isOn: $s.travaLigada)
                .toggleStyle(.switch).controlSize(.small)
            HStack(spacing: 8) {
                Text("Microfone").font(.system(size: 12))
                SeletorCrew(selecao: Binding(get: { s.micTravadoUID ?? "" },
                                             set: { s.micTravadoEscolhido = $0 == s.micEmbutido?.uid ? nil : $0 }),
                            opcoes: opcoesMicTravado)
                    .frame(maxWidth: 280, alignment: .leading)
                    .disabled(!s.travaLigada)
            }
            Text("Quando um dispositivo conecta e o macOS muda a entrada sozinho (AirPods, por exemplo), o Crew devolve para este microfone. Troca feita por você, aqui ou nos Ajustes do Sistema, é respeitada. Se ele estiver desconectado, nada é forçado; quando ele voltar, a entrada volta para ele.")
                .font(.system(size: 11)).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle("Alertas do sistema acompanham a saída escolhida no Crew", isOn: $s.alertasAcompanham)
                .toggleStyle(.switch).controlSize(.small)
            Toggle("Avisar na ilha quando um fone ou caixa conecta, desconecta ou o microfone é devolvido", isOn: $s.avisarNaIlha)
                .toggleStyle(.switch).controlSize(.small)
            VolumePorAppAjustes()
        }
    }

    /// Entradas ligadas; o microfone escolhido que está desconectado continua na lista.
    private var opcoesMicTravado: [(valor: String, titulo: String)] {
        var opcoes = s.entradas.map { (valor: $0.uid, titulo: $0.nome) }
        if let uid = s.micTravadoUID, !s.entradas.contains(where: { $0.uid == uid }) {
            opcoes.append((valor: uid, titulo: "Escolhido (desconectado)"))
        }
        return opcoes
    }
}
