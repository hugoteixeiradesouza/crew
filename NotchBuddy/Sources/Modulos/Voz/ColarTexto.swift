import AppKit
import Carbon.HIToolbox
import CoreGraphics

// Cola um texto no app que está em foco, como se o Hugo tivesse apertado ⌘V — e devolve a
// área de transferência ao que ela tinha antes. É o caminho do ditado por Fn.
//
//   1. guarda o que está na área de transferência;
//   2. põe o texto lá, marcado como passageiro (gerenciadores de área de transferência ignoram);
//   3. manda ⌘V ao app em foco;
//   4. depois de um instante, devolve o que estava — só se ninguém mexeu nela nesse meio-tempo.
//
// Precisa de Acessibilidade para mandar a tecla. Sem ela, ou com um campo de senha em foco
// (entrada segura), não cola: quem chama deixa o texto copiado e avisa.

@MainActor
enum ColarTexto {
    enum Resultado: Equatable {
        case colou
        /// Não colou; o texto ficou na área de transferência. O motivo é para mostrar.
        case soCopiou(String)
    }

    /// Marca de conteúdo passageiro (convenção nspasteboard.org).
    private static let passageiro = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    /// Tempo para o app de destino ler a área de transferência antes de ela ser devolvida.
    private static let esperaParaDevolver: TimeInterval = 0.7

    static func colar(_ texto: String) -> Resultado {
        let area = NSPasteboard.general
        guard AXIsProcessTrusted() else {
            copiar(texto, em: area)
            return .soCopiou("falta a permissão de Acessibilidade")
        }
        guard !IsSecureEventInputEnabled() else {
            copiar(texto, em: area)
            return .soCopiou("há um campo de senha em foco")
        }
        let antes = guardar(area)
        area.clearContents()
        area.setString(texto, forType: .string)
        area.setData(Data(), forType: passageiro)
        let nossa = area.changeCount

        guard mandarComandoV() else {
            return .soCopiou("o macOS não deixou mandar a tecla")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + esperaParaDevolver) {
            // Alguém copiou outra coisa nesse meio-tempo: a área já não é nossa, não mexe.
            guard area.changeCount == nossa else { return }
            area.clearContents()
            if !antes.isEmpty { area.writeObjects(antes) }
        }
        return .colou
    }

    private static func copiar(_ texto: String, em area: NSPasteboard) {
        area.clearContents()
        area.setString(texto, forType: .string)
    }

    /// Cópia de tudo o que está na área de transferência (todos os itens, todos os tipos).
    private static func guardar(_ area: NSPasteboard) -> [NSPasteboardItem] {
        (area.pasteboardItems ?? []).map { item in
            let copia = NSPasteboardItem()
            for tipo in item.types {
                if let dados = item.data(forType: tipo) { copia.setData(dados, forType: tipo) }
            }
            return copia
        }
    }

    private static func mandarComandoV() -> Bool {
        let fonte = CGEventSource(stateID: .combinedSessionState)
        let v = CGKeyCode(kVK_ANSI_V)
        guard let desce = CGEvent(keyboardEventSource: fonte, virtualKey: v, keyDown: true),
              let sobe = CGEvent(keyboardEventSource: fonte, virtualKey: v, keyDown: false) else { return false }
        desce.flags = .maskCommand
        sobe.flags = .maskCommand
        desce.post(tap: .cgSessionEventTap)
        sobe.post(tap: .cgSessionEventTap)
        return true
    }
}
