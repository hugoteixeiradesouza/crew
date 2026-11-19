import Foundation

// O que as sessões do Claude Code fazem com a voz do computador pelo servidor MCP do Crew:
// falar um texto e ver as vozes. `falar` volta na hora (a ferramenta não espera a fala acabar)
// e só funciona com o ajuste "As sessões podem falar" ligado.

@MainActor
enum FalaMCP {
    static let ferramentas: Set<String> = ["falar", "vozes"]
    /// Limite do que uma sessão pode mandar falar de uma vez.
    static let maximo = 600

    static func responder(_ ferramenta: String, _ args: [String: Any]) -> [String: Any] {
        guard Registro.shared.estaLigado(VozServico.modulo) else {
            return ["erro": "O módulo Voz está desligado (Ajustes do Crew › Voz)."]
        }
        let s = FalaServico.shared
        let v = VozServico.shared
        switch ferramenta {
        case "falar":
            guard s.sessoesFalam else {
                return ["erro": "\(Usuario.nome) desligou a fala pelas sessões (Ajustes do Crew › Voz › Quando o Crew fala)."]
            }
            let texto = (args["texto"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !texto.isEmpty else { return ["erro": "Texto vazio."] }
            guard texto.count <= maximo else { return ["erro": "Texto longo demais (\(texto.count) caracteres; o limite é \(maximo)). Resuma."] }
            guard !v.ocupado else { return ["erro": "\(Usuario.nome) está ditando agora: a voz entraria no microfone. Tente depois."] }
            let pedida = (args["voz"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            if let pedida, !s.vozes.contains(where: { $0.id == pedida || $0.nome.localizedCaseInsensitiveCompare(pedida) == .orderedSame }) {
                return ["erro": "Não existe voz humanizada chamada \(pedida). Veja as que existem com `vozes`."]
            }
            let quem = s.falar(texto, voz: pedida)
            var r: [String: Any] = ["ok": true, "falando_com": quem]
            if quem.hasPrefix("voz humanizada") { r["observacao"] = "A voz humanizada leva alguns segundos para gerar cada frase antes de tocar." }
            return r
        case "vozes":
            s.atualizar()
            var r: [String: Any] = [
                "motor_em_uso": s.humanizadaEmUso ? "voz humanizada (OmniVoice, local)" : "voz do macOS",
                "motor_humanizado_instalado": s.instalado,
                "motor_humanizado_ligado": s.servidorLigado,
                "vozes_humanizadas": s.vozes.map { ["nome": $0.nome, "origem": $0.origem.rawValue, "padrao": $0.id == s.vozId] as [String: Any] },
                "vozes_do_macos": v.vozes().map { ["nome": $0.nome, "padrao": $0.id == v.vozId] as [String: Any] },
                "sessoes_podem_falar": s.sessoesFalam,
            ]
            if !s.instalado { r["como_instalar"] = "\(Usuario.nome) instala o motor de voz humanizada pelo botão em Ajustes do Crew › Voz." }
            return r
        default:
            return ["erro": "Ferramenta desconhecida."]
        }
    }
}
