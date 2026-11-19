import SwiftUI

// Indicador opcional no canto da ilha fechada (escolhido nos ajustes do Sistema). Enquanto
// ligado, assina só a parte que mostra — é o único caso em que o Sistema lê com a ilha fechada.

enum IndicadorSistema: String, CaseIterable, Identifiable {
    case nenhum, cpu, memoria, temperatura
    var id: String { rawValue }
    var nome: String {
        switch self {
        case .nenhum: return "Nada"
        case .cpu: return "CPU"
        case .memoria: return "Memória"
        case .temperatura: return "Temperatura"
        }
    }
    var parte: SistemaServico.Parte? {
        switch self {
        case .nenhum: return nil
        case .cpu, .memoria: return .rapido
        case .temperatura: return .temperatura
        }
    }

    static var atual: IndicadorSistema {
        // Padrão: CPU (o Hugo quer o consumo do Mac sempre à vista na ilha fechada)
        get { IndicadorSistema(rawValue: Ajustes.string("sistema", "indicador") ?? "cpu") ?? .cpu }
        set { Ajustes.definir("sistema", "indicador", newValue.rawValue) }
    }
}

@MainActor
enum SistemaIndicador {
    private static var mostrando: IndicadorSistema = .nenhum

    /// Aplica a escolha atual (ou desliga, se o módulo parou).
    static func aplicar(ligado: Bool = true) {
        let novo = ligado ? IndicadorSistema.atual : .nenhum
        if let p = mostrando.parte { SistemaServico.shared.soltar("indicador", [p]) }
        mostrando = novo
        guard let p = novo.parte else { Arbitro.shared.retirar("sistema.indicador"); return }
        SistemaServico.shared.assinar("indicador", [p])
        Arbitro.shared.publicar(Sinal(id: "sistema.indicador", lugar: .canto, prioridade: .indicador,
                                      conteudo: AnyView(IndicadorCanto(tipo: novo))))
    }
}

struct IndicadorCanto: View {
    let tipo: IndicadorSistema
    private let s = SistemaServico.shared

    var body: some View {
        switch tipo {
        case .cpu:
            AnelSistema(fracao: s.cpu.total, texto: "\(Int((s.cpu.total * 100).rounded()))",
                        cor: FormatoSistema.corCPU, espessura: 2.5, fonte: 9)
        case .memoria:
            AnelSistema(fracao: s.memoria.fracao, texto: "\(Int((s.memoria.fracao * 100).rounded()))",
                        cor: FormatoSistema.corPressao(s.memoria.pressao), espessura: 2.5, fonte: 9)
        case .temperatura:
            AnelSistema(fracao: (s.temperatura ?? 0) / 100, texto: s.temperatura.map { "\(Int($0.rounded()))" } ?? "—",
                        cor: FormatoSistema.corTemp(s.temperatura), espessura: 2.5, fonte: 9)
        case .nenhum:
            EmptyView()
        }
    }
}

/// Ajustes do módulo Sistema (página na Central).
struct SistemaAjustes: View {
    @State private var indicador = IndicadorSistema.atual
    @State private var avisos = Ajustes.bool("sistema", "avisos", padrao: true)

    var body: some View {
        Picker("Na ilha fechada", selection: $indicador) {
            ForEach(IndicadorSistema.allCases) { Text($0.nome).tag($0) }
        }
        .onChange(of: indicador) { _, v in IndicadorSistema.atual = v; SistemaIndicador.aplicar() }
        Text("Fica no canto direito, no lugar dos mini-Homies, quando não há música tocando. Enquanto ligado, o Sistema lê só esse valor com a ilha fechada.")
            .font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
        Divider()
        Toggle("Avisos na ilha (bateria em 10% e 5%, memória em pressão crítica)", isOn: $avisos)
            .onChange(of: avisos) { _, v in
                Ajustes.definir("sistema", "avisos", v)
                v ? SistemaAlertas.shared.ligar() : SistemaAlertas.shared.desligar()
            }
    }
}
