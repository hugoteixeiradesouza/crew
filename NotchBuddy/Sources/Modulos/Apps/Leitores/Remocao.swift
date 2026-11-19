import AppKit
import Foundation

// Fechar o app e mover para a Lixeira.
// Sempre `trashItem`, nunca `removeItem`. Cada caminho passa de novo pelo portão
// (`PoliticaDesinstalar.podeSair`) imediatamente antes de sair. Sem helper de administrador:
// o que é do root fica, e o motivo vai para o resultado.

struct Ficou: Sendable, Hashable {
    let caminho: String
    let motivo: String
    var nome: String { (caminho as NSString).lastPathComponent }
}

struct ResultadoRemocao: Sendable {
    let titulo: String
    let movidos: [Sobra]
    let ficaram: [Ficou]
    let quando: Date
    var bytes: Int64 { movidos.reduce(0) { $0 + ($1.bytes ?? 0) } }
}

enum Remocao {
    /// Pede ao app (a cópia deste caminho; pode haver duas com o mesmo id) que feche, sem forçar,
    /// e espera até ~3 s. true = fechou (ou não estava aberto).
    @MainActor
    static func fechar(_ app: AlvoApp) async -> Bool {
        guard let id = app.bundleID else { return true }
        let alvo = URL(fileURLWithPath: app.caminho).standardizedFileURL
        func abertos() -> [NSRunningApplication] {
            NSRunningApplication.runningApplications(withBundleIdentifier: id)
                .filter { $0.bundleURL?.standardizedFileURL == alvo }
        }
        let lista = abertos()
        guard !lista.isEmpty else { return true }
        lista.forEach { $0.terminate() }
        for _ in 0..<30 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if abertos().isEmpty { return true }
        }
        return abertos().isEmpty
    }

    @MainActor
    static func aberto(_ app: AlvoApp) -> Bool {
        guard let id = app.bundleID else { return false }
        let alvo = URL(fileURLWithPath: app.caminho).standardizedFileURL
        return NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .contains { $0.bundleURL?.standardizedFileURL == alvo }
    }

    /// Confere de novo antes da confirmação: ainda existe e o portão ainda deixa.
    static func revalidar(_ s: [Sobra]) -> (validos: [Sobra], fora: [Ficou]) {
        var v: [Sobra] = [], f: [Ficou] = []
        for x in s {
            if !existe(x.caminho) { f.append(Ficou(caminho: x.caminho, motivo: "Não está mais lá.")); continue }
            if !PoliticaDesinstalar.podeSair(x.caminho) { f.append(Ficou(caminho: x.caminho, motivo: "Deixou de ser permitido.")); continue }
            var y = x
            y.precisaAdmin = PoliticaDesinstalar.precisaAdmin(x.caminho)
            v.append(y)
        }
        return (v, f)
    }

    /// Move para a Lixeira. Se o pacote do app estiver na lista, ele vai primeiro; se ele não
    /// sair, nada mais sai (tirar as pastas de um app que continua instalado o desconfiguraria).
    static func mover(_ itens: [Sobra], titulo: String) -> ResultadoRemocao {
        var movidos: [Sobra] = [], ficaram: [Ficou] = []
        let pacotes = itens.filter { $0.categoria == .app }
        for p in pacotes {
            if let erro = moverUm(p) {
                ficaram.append(Ficou(caminho: p.caminho, motivo: erro))
                for s in itens where s.categoria != .app {
                    ficaram.append(Ficou(caminho: s.caminho, motivo: "Ficou porque o app não saiu."))
                }
                return ResultadoRemocao(titulo: titulo, movidos: movidos, ficaram: ficaram, quando: Date())
            }
            movidos.append(p)
        }
        for s in itens where s.categoria != .app {
            if let erro = moverUm(s) { ficaram.append(Ficou(caminho: s.caminho, motivo: erro)) } else { movidos.append(s) }
        }
        return ResultadoRemocao(titulo: titulo, movidos: movidos, ficaram: ficaram, quando: Date())
    }

    /// nil = foi para a Lixeira; senão, o motivo de ter ficado.
    private static func moverUm(_ s: Sobra) -> String? {
        guard existe(s.caminho) else { return "Não está mais lá." }
        // Última checagem, imediatamente antes de mover.
        guard PoliticaDesinstalar.podeSair(s.caminho) else { return "Deixou de ser permitido." }
        do {
            try FileManager.default.trashItem(at: URL(fileURLWithPath: s.caminho), resultingItemURL: nil)
            return nil
        } catch {
            return motivo(error, caminho: s.caminho)
        }
    }

    static func motivo(_ e: Error, caminho: String) -> String {
        let ns = e as NSError
        let semPermissao = (ns.domain == NSCocoaErrorDomain && [NSFileWriteNoPermissionError, NSFileReadNoPermissionError].contains(ns.code))
            || (ns.domain == NSPOSIXErrorDomain && [Int(EACCES), Int(EPERM)].contains(ns.code))
            || (ns.underlyingErrors.first as NSError?).map { $0.domain == NSPOSIXErrorDomain && [Int(EACCES), Int(EPERM)].contains($0.code) } == true
        if semPermissao {
            if caminho.hasSuffix(".app"), PoliticaDesinstalar.raizesApps().contains(where: { caminho.hasPrefix($0 + "/") }),
               FileManager.default.isWritableFile(atPath: (caminho as NSString).deletingLastPathComponent),
               FileManager.default.isWritableFile(atPath: caminho) {
                return "O macOS bloqueou (proteção de apps). Para o Crew poder: Ajustes do Sistema › Privacidade e Segurança › Gerenciamento de Apps › ligar o Crew. Ou arraste pelo Finder."
            }
            return caminho.hasPrefix("/Library/") || caminho.hasPrefix("/Applications/")
                ? "Sem permissão: é do administrador. O Crew não pede senha nem usa helper; arraste pelo Finder (ele pede a senha)."
                : "Sem permissão (o macOS recusou). Arraste pelo Finder, se quiser tirar."
        }
        return ns.localizedDescription
    }

    /// Existe (sem seguir link: um link quebrado também conta).
    static func existe(_ c: String) -> Bool {
        var st = stat()
        return lstat(c, &st) == 0
    }
}
