import Foundation

// Commits do Hugo no dia, só na hora do resumo (ou quando ele pede na Central): para cada raiz
// de projeto que apareceu no dia, `git log --since=<meia-noite> --until=<fim do dia>
// --author=<user.email do repo>`. Fora da main, com tempo máximo; repo que falhar fica de fora.

enum CommitsDoDia {
    static let git = "/usr/bin/git"

    static func ler(raizes: [String: String], dia: Date) async -> [CommitDiario] {
        let cal = Calendar.current
        let inicio = cal.startOfDay(for: dia)
        let fim = cal.date(byAdding: .day, value: 1, to: inicio) ?? dia
        let iso = ISO8601DateFormatter()
        var todos: [CommitDiario] = []
        for (raiz, projeto) in raizes.sorted(by: { $0.value < $1.value }) {
            guard FileManager.default.fileExists(atPath: raiz + "/.git") else { continue }
            let email = await Processo.rodar(git, ["-C", raiz, "config", "user.email"], tempoMax: 5)
            let autor = email.saida.trimmingCharacters(in: .whitespacesAndNewlines)
            guard email.ok, !autor.isEmpty else { continue }
            let r = await Processo.rodar(git, ["-C", raiz, "--no-optional-locks", "log", "--all", "--no-merges",
                                               "--since=\(iso.string(from: inicio))", "--until=\(iso.string(from: fim))",
                                               "--author=\(autor)", "--format=%H%x1f%aI%x1f%s"], tempoMax: 10)
            guard r.ok else { continue }
            var vistos = Set<String>()   // por título: o rebase do integrar deixa o mesmo commit em dois branches
            for linha in r.saida.split(separator: "\n") {
                let p = linha.split(separator: "\u{1f}", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
                guard p.count == 3, vistos.insert(p[2]).inserted, let h = iso.date(from: p[1]) else { continue }
                todos.append(CommitDiario(hash: String(p[0].prefix(10)), hora: h, titulo: p[2], projeto: projeto))
            }
        }
        return todos.sorted { $0.hora < $1.hora }
    }
}
