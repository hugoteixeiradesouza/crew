import AppKit

// Espaço próprio do macOS (CGS, API privada do WindowServer), num nível acima das áreas de
// trabalho. Janela posta nele não some durante a troca de tela/área de trabalho — é o que
// outros apps de notch fazem. Funções carregadas na hora: se não
// existirem (macOS futuro), nada acontece e a ilha segue como antes.

@MainActor
final class EspacoProprio {
    private typealias FConexao = @convention(c) () -> Int32
    private typealias FCriar = @convention(c) (Int32, Int, CFDictionary?) -> UInt64
    private typealias FNivel = @convention(c) (Int32, UInt64, Int) -> Void
    private typealias FMostrar = @convention(c) (Int32, CFArray) -> Void
    private typealias FJanelas = @convention(c) (Int32, CFArray, CFArray) -> Void

    private let conexao: Int32
    private let id: UInt64
    private let adicionar: FJanelas

    init?(nivel: Int = 2_147_483_647) {
        func f<T>(_ nome: String, _: T.Type) -> T? {
            dlsym(UnsafeMutableRawPointer(bitPattern: -2), nome).map { unsafeBitCast($0, to: T.self) }
        }
        guard let conn = f("_CGSDefaultConnection", FConexao.self),
              let criar = f("CGSSpaceCreate", FCriar.self),
              let nivelF = f("CGSSpaceSetAbsoluteLevel", FNivel.self),
              let mostrar = f("CGSShowSpaces", FMostrar.self),
              let adicionar = f("CGSAddWindowsToSpaces", FJanelas.self) else { return nil }
        conexao = conn()
        id = criar(conexao, 1, nil)
        guard id != 0 else { return nil }
        self.adicionar = adicionar
        nivelF(conexao, id, nivel)
        mostrar(conexao, [NSNumber(value: id)] as CFArray)
    }

    func incluir(_ janela: NSWindow) {
        guard janela.windowNumber > 0 else { return }
        adicionar(conexao, [NSNumber(value: janela.windowNumber)] as CFArray, [NSNumber(value: id)] as CFArray)
    }
}
