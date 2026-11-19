import Foundation

// Regras puras do áudio: quando a trava do microfone devolve a entrada, e como reconhecer o
// "eco" das trocas feitas pelo próprio Crew (para não entrar em laço com o macOS).

enum TravaMicrofone {
    /// Um dispositivo que apareceu há menos que isso e virou a entrada padrão = troca do macOS
    /// (AirPods conectando). O Bluetooth às vezes leva alguns segundos para virar a entrada.
    static let janelaConexao: TimeInterval = 10
    /// Mais devoluções que isso em `janelaLaco` = o macOS insiste; o Crew desiste e avisa.
    static let maxDevolucoes = 3
    static let janelaLaco: TimeInterval = 20

    enum Decisao: Equatable {
        case devolver(paraUID: String)
        case nada(String)
    }

    /// - Parameters:
    ///   - novaUID: entrada padrão agora (depois da troca que não foi do Crew).
    ///   - alvoUID: o microfone travado.
    ///   - entradas: UIDs das entradas presentes agora.
    ///   - vistoEm: quando cada UID apareceu pela primeira vez (os presentes na abertura do Crew = passado distante).
    ///   - devolucoes: datas das devoluções já feitas.
    static func decidir(ligada: Bool, alvoUID: String?, novaUID: String?, entradas: Set<String>,
                        vistoEm: [String: Date], devolucoes: [Date], agora: Date) -> Decisao {
        guard ligada else { return .nada("trava desligada") }
        guard let alvo = alvoUID else { return .nada("sem microfone escolhido") }
        guard entradas.contains(alvo) else { return .nada("o microfone travado não está conectado") }
        guard let nova = novaUID, nova != alvo else { return .nada("já está no microfone travado") }
        guard let visto = vistoEm[nova], agora.timeIntervalSince(visto) <= janelaConexao else {
            return .nada("troca manual (o dispositivo já estava conectado): respeitada")
        }
        let recentes = devolucoes.filter { agora.timeIntervalSince($0) <= janelaLaco }.count
        guard recentes < maxDevolucoes else { return .nada("o macOS insistiu \(recentes) vezes: o Crew desistiu") }
        return .devolver(paraUID: alvo)
    }

    /// Quando o microfone travado volta a aparecer e a entrada está em outro: volta para ele.
    static func aoReconectar(ligada: Bool, alvoUID: String?, chegaram: Set<String>, atualUID: String?) -> Bool {
        guard ligada, let alvo = alvoUID else { return false }
        return chegaram.contains(alvo) && atualUID != alvo
    }
}

/// Trocas de dispositivo padrão feitas pelo Crew. Quando o Core Audio avisa da troca, ela é
/// reconhecida aqui e não conta como "o macOS trocou sozinho".
struct EcoTrocas {
    static let validade: TimeInterval = 3
    private var esperadas: [(papel: String, id: UInt32, ate: Date)] = []

    mutating func esperar(_ papel: String, _ id: UInt32, agora: Date = .now) {
        esperadas.removeAll { $0.ate < agora || $0.papel == papel }
        esperadas.append((papel, id, agora.addingTimeInterval(Self.validade)))
    }

    /// true = este aviso é eco de uma troca do Crew (e é consumido).
    mutating func consumir(_ papel: String, _ id: UInt32, agora: Date = .now) -> Bool {
        esperadas.removeAll { $0.ate < agora }
        guard let i = esperadas.firstIndex(where: { $0.papel == papel && $0.id == id }) else { return false }
        esperadas.remove(at: i)
        return true
    }
}
