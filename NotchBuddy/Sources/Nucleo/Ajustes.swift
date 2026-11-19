import Foundation

// Ajustes por módulo, com chave `modulo.<id>.<nome>` no UserDefaults.
// Segredo não entra aqui: vai para o Keychain (Nucleo/Keychain.swift).

enum Ajustes {
    static func chave(_ modulo: String, _ nome: String) -> String { "modulo.\(modulo).\(nome)" }

    static func bool(_ modulo: String, _ nome: String, padrao: Bool) -> Bool {
        let k = chave(modulo, nome)
        return UserDefaults.standard.object(forKey: k) == nil ? padrao : UserDefaults.standard.bool(forKey: k)
    }

    static func double(_ modulo: String, _ nome: String, padrao: Double) -> Double {
        let k = chave(modulo, nome)
        return UserDefaults.standard.object(forKey: k) == nil ? padrao : UserDefaults.standard.double(forKey: k)
    }

    static func string(_ modulo: String, _ nome: String) -> String? {
        UserDefaults.standard.string(forKey: chave(modulo, nome))
    }

    static func definir(_ modulo: String, _ nome: String, _ valor: Any?) {
        Gravar.padrao.set(valor, forKey: chave(modulo, nome))
    }
}

/// Único caminho de gravação de ajustes do app. No modo de capturas (`Crew --capturas`), nada
/// é gravado: as cenas mexem no estado à vontade sem tocar nos ajustes do Hugo (antes o som do
/// Homie aparecia desligado depois de cada rodada de capturas).
final class Gravar: @unchecked Sendable {
    nonisolated(unsafe) static var desligado = false
    static let padrao = Gravar()

    func set(_ valor: Any?, forKey chave: String) {
        guard !Gravar.desligado else { return }
        UserDefaults.standard.set(valor, forKey: chave)
    }

    func removeObject(forKey chave: String) {
        guard !Gravar.desligado else { return }
        UserDefaults.standard.removeObject(forKey: chave)
    }
}
