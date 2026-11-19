import SwiftUI

// Quem aparece na ilha fechada — docs/ARQUITETURA.md §4.
// Módulos publicam sinais; o árbitro escolhe UM por lugar (maior prioridade; empate → o mais
// recente). Dois lugares na ilha fechada:
//   • barra — a ilha cresce embaixo do notch (brilho/volume, avisos);
//   • canto — o quadradinho à direita do notch (capa da música, indicador do Sistema);
//     sem sinal no canto, ficam os mini-Homies das outras sessões.

struct Sinal {
    enum Lugar { case barra, canto }

    enum Prioridade: Int, Comparable {
        case indicador = 0   // valor que o Hugo escolheu ver (CPU, temperatura…)
        case atividade = 1   // algo acontecendo (música tocando)
        case alerta = 2      // precisa de atenção (bateria acabando)
        case hud = 3         // resposta a uma ação dele agora (tecla de brilho/volume)
        static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    }

    /// O que o Homie segura enquanto o sinal está na barra.
    enum Homie: Equatable { case nenhum, celular(Double), fones(Double) }

    let id: String
    let lugar: Lugar
    let prioridade: Prioridade
    var homie: Homie = .nenhum
    /// Passageiro: some sozinho depois deste tempo.
    var duracao: TimeInterval? = nil
    /// O aviso tem clique próprio: com ele na barra, passar o mouse não abre a ilha e o clique
    /// nele vai só para o aviso (senão a ilha abria e o aviso sumia antes do clique).
    var clicavel = false
    let conteudo: AnyView
    let criadoEm = Date()
}

@MainActor
final class Arbitro: ObservableObject {
    static let shared = Arbitro()

    @Published private(set) var sinais: [String: Sinal] = [:]
    private var expiracoes: [String: DispatchWorkItem] = [:]

    /// Publica (ou troca) o sinal com este id.
    func publicar(_ s: Sinal) {
        expiracoes[s.id]?.cancel()
        sinais[s.id] = s
        if let d = s.duracao {
            let item = DispatchWorkItem { [weak self] in self?.retirar(s.id) }
            expiracoes[s.id] = item
            DispatchQueue.main.asyncAfter(deadline: .now() + d, execute: item)
        }
    }

    func retirar(_ id: String) {
        expiracoes.removeValue(forKey: id)?.cancel()
        sinais.removeValue(forKey: id)
    }

    /// Só para o modo de capturas: começa cada cena do zero.
    func limparTudo() { for id in Array(sinais.keys) { retirar(id) } }

    var barra: Sinal? { vencedor(.barra) }
    var barraClicavel: Bool { barra?.clicavel == true }
    var canto: Sinal? { vencedor(.canto) }

    /// O canto comporta dois sinais lado a lado (ex.: CPU e a capa da música); a ilha alarga
    /// um pouco quando há dois. Mais importante à direita.
    static let maxCanto = 2
    var cantos: [Sinal] {
        Array(sinais.values.filter { $0.lugar == .canto }
            .sorted { ($0.prioridade, $0.criadoEm) > ($1.prioridade, $1.criadoEm) }
            .prefix(Self.maxCanto)).reversed()
    }
    /// Largura extra da ilha fechada para o segundo sinal do canto.
    var larguraExtraCanto: CGFloat { cantos.count > 1 ? 34 : 0 }

    private func vencedor(_ lugar: Sinal.Lugar) -> Sinal? {
        sinais.values.filter { $0.lugar == lugar }.max {
            ($0.prioridade, $0.criadoEm) < ($1.prioridade, $1.criadoEm)
        }
    }
}
