import os

// Log do Crew no sistema (Console.app, `log stream --predicate 'subsystem == "fr.louisraille.NotchBuddy"'`).
// Uma categoria por módulo.

enum Log {
    static func de(_ categoria: String) -> Logger {
        Logger(subsystem: "fr.louisraille.NotchBuddy", category: categoria)
    }
}

extension Array where Element == CChar {
    /// Texto de um buffer C terminado em zero.
    var textoC: String { String(decoding: prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self) }
}
