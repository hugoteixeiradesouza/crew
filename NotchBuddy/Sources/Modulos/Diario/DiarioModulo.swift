import SwiftUI

// Diário — primeiro módulo do pilar "Eu" (docs/ARQUITETURA.md §0 e §1). O Crew de olho no dia do
// Hugo: registra o que ele pede e recebe das sessões, as notas dele e onde passou o tempo; tria
// na hora o que é pendência DELE e cobra no momento certo, dizendo de onde veio, com 3 saídas
// (Feito · Adiar · Ignorar). Às 18h, o fechamento do dia. Tudo local, nada sai do Mac.

@MainActor
final class DiarioModulo: Modulo {
    static let shared = DiarioModulo()

    let id = DiarioServico.idModulo
    let nome = "Tasks"
    let icone = "checklist"
    let pilar = Pilar.eu
    let superficies: [Superficie] = [.ilha, .claude]
    var temBloco: Bool { true }
    var blocoPorPadrao: Bool { true }
    func bloco() -> AnyView { AnyView(DiarioBloco()) }
    let resumo = "O seu dia de trabalho: pedidos e entregas das sessões, notas rápidas e tempo por app. Separa na hora o que é pendência sua e avisa na hora certa; às 18h, o resumo do dia. Modelo local, nada sai do Mac."
    var temAba: Bool { true }

    func iniciar() { DiarioServico.shared.iniciar() }
    var alturaExpandida: CGFloat? { DiarioServico.alturaExpandida }
    func expandirAba() { DiarioServico.shared.expandir() }
    func recolherAba() { DiarioServico.shared.recolher() }
    func parar() { DiarioServico.shared.parar() }

    func aba() -> AnyView { AnyView(DiarioAba()) }
    func central() -> AnyView? { AnyView(DiarioCentral()) }
    func ajustes() -> AnyView? { AnyView(DiarioAjustes()) }

    /// crew://diario/nota?texto=…   anota (passa pela triagem)
    /// crew://diario/resumir         gera o resumo do dia e abre na Central
    func executar(_ acao: String, _ parametros: [String: String]) -> Bool {
        switch acao {
        case "nota":
            guard let t = parametros["texto"], !t.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
            DiarioServico.shared.adicionarNota(t)
            return true
        case "diagnostico-whatsapp":
            // Só a ESTRUTURA do banco do WhatsApp (tabelas, colunas, contagens) — nenhum conteúdo
            Task.detached {
                let txt = WhatsAppBanco.diagnostico()
                let pasta = HookServer.supportDir.appendingPathComponent("diario")
                try? FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
                try? txt.write(to: pasta.appendingPathComponent("diagnostico-whatsapp.txt"), atomically: true, encoding: .utf8)
            }
            return true
        case "expandir":
            // crew://diario/expandir[?segmento=pendencias|hoje|resumo] — abre a ilha no Diário inteiro
            NotificationCenter.default.post(name: .abrirIlha, object: id)
            let seg: DiarioServico.Segmento? = switch parametros["segmento"] {
                case "hoje": .hoje
                case "resumo": .resumo
                case "pendencias": .pendencias
                default: nil
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                MainActor.assumeIsolated { DiarioServico.shared.expandir(seg) }
            }
            return true
        case "reler-whatsapp":
            // crew://diario/reler-whatsapp?minutos=30 — volta o ponto de leitura e tria de novo
            let minutos = Double(parametros["minutos"] ?? "") ?? 30
            FonteWhatsApp.shared.reler(minutos: Swift.min(Swift.max(minutos, 1), 24 * 60))
            return true
        case "editar":
            // crew://diario/editar?id=<início do id>&acao=<novo título> — retitula uma pendência
            guard let pre = parametros["id"]?.lowercased(), pre.count >= 6,
                  let a = parametros["acao"]?.trimmingCharacters(in: .whitespaces), !a.isEmpty,
                  let p = DiarioServico.shared.pendencias.first(where: { $0.id.uuidString.lowercased().hasPrefix(pre) })
            else { return false }
            DiarioServico.shared.editar(p.id, acao: a)
            return true
        case "resumir":
            Task {
                await DiarioServico.shared.resumir()
                Central.abrir(modulo: id)
            }
            return true
        default:
            return false
        }
    }
}
