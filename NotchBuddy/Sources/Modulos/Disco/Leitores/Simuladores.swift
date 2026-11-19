import Foundation

// Simuladores do iOS desligados.
// Listar e apagar só pelo `simctl` (via `Processo.rodar`, fora da main). Apagar é DEFINITIVO:
// o `simctl delete` remove o aparelho com apps e dados; não passa pela Lixeira.

struct Simulador: Identifiable, Sendable, Hashable {
    var id: String { udid }
    let udid: String
    let nome: String
    let sistema: String
    let disponivel: Bool
    let ultimoUso: Date?
    let pasta: String
    var bytes: Int64
}

enum Simuladores {
    static let tempoLista: TimeInterval = 30

    /// Xcode instalado? Sem ele a seção nem aparece.
    static var temXcode: Bool { Xcode.pastaDeveloper() != nil }

    static var pastaDevices: String { PoliticaSeguranca.home + "/Library/Developer/CoreSimulator/Devices" }

    /// Nil = não deu para listar (sem Xcode, erro ou tempo esgotado).
    static func listar(medir: Bool) async -> [Simulador]? {
        guard let (exe, pre) = Xcode.simctl() else { return nil }
        let r = await Processo.rodar(exe, pre + ["list", "devices", "--json"], tempoMax: tempoLista)
        guard r.ok, let json = try? JSONSerialization.jsonObject(with: Data(r.saida.utf8)) as? [String: Any],
              let mapa = json["devices"] as? [String: Any] else { return nil }
        let raiz = pastaDevices
        let iso = ISO8601DateFormatter()
        var lista: [Simulador] = []
        for (runtime, bruto) in mapa {
            guard let devs = bruto as? [[String: Any]] else { continue }
            let sistema = rotuloSistema(runtime)
            for d in devs {
                guard let udid = d["udid"] as? String, UUID(uuidString: udid) != nil else { continue }
                // Ligado nunca aparece.
                if (d["state"] as? String ?? "") != "Shutdown" { continue }
                let pasta: String
                if let dp = d["dataPath"] as? String { pasta = (dp as NSString).deletingLastPathComponent } else { pasta = raiz + "/" + udid }
                guard (pasta as NSString).standardizingPath.hasPrefix(raiz + "/"), existeSemSeguir(URL(fileURLWithPath: pasta)) else { continue }
                lista.append(Simulador(udid: udid, nome: d["name"] as? String ?? "Simulador", sistema: sistema,
                                       disponivel: d["isAvailable"] as? Bool ?? true,
                                       ultimoUso: (d["lastBootedAt"] as? String).flatMap { iso.date(from: $0) },
                                       pasta: pasta, bytes: 0))
            }
        }
        if medir, !lista.isEmpty {
            let t = await Tamanhos.medir(lista.map { URL(fileURLWithPath: $0.pasta) })
            for i in lista.indices { lista[i].bytes = t[URL(fileURLWithPath: lista[i].pasta).standardizedFileURL.path] ?? 0 }
        }
        return lista.sorted { ($0.disponivel ? 1 : 0, -$0.bytes) < ($1.disponivel ? 1 : 0, -$1.bytes) }
    }

    /// Apaga de vez, um por um, conferindo antes que ainda está desligado.
    static func apagar(_ alvo: [Simulador]) async -> (apagados: [Simulador], falhas: [Retirado]) {
        guard let (exe, pre) = Xcode.simctl() else {
            return ([], alvo.map { Retirado(nome: $0.nome, motivo: "Xcode não encontrado.") })
        }
        let agora = await listar(medir: false)
        let desligados = Set((agora ?? []).map(\.udid))
        var ok: [Simulador] = []
        var falhas: [Retirado] = []
        for s in alvo {
            guard desligados.contains(s.udid) else {
                falhas.append(Retirado(nome: s.nome, motivo: "Ligado agora ou não existe mais."))
                continue
            }
            let r = await Processo.rodar(exe, pre + ["delete", s.udid], tempoMax: 60)
            if r.ok { ok.append(s) } else {
                falhas.append(Retirado(nome: s.nome, motivo: r.erro.isEmpty ? "simctl falhou." : r.erro.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
        }
        return (ok, falhas)
    }

    /// `com.apple.CoreSimulator.SimRuntime.iOS-17-5` → `iOS 17.5`.
    static func rotuloSistema(_ chave: String) -> String {
        let ultimo = chave.split(separator: ".").last.map(String.init) ?? chave
        let partes = ultimo.split(separator: "-")
        guard let so = partes.first else { return ultimo }
        let versao = partes.dropFirst().joined(separator: ".")
        return versao.isEmpty ? String(so) : "\(so) \(versao)"
    }
}
