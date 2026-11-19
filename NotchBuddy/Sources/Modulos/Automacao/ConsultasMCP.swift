import SwiftUI

// O que o Crew responde às ferramentas do servidor MCP. Só leitura, mais avisar no notch e
// abrir telas — nada destrutivo (regra de docs/ARQUITETURA.md). As ferramentas de vídeo são
// respondidas pelo módulo Vídeo (`Modulos/Video/VideoMCP.swift`).

@MainActor
enum ConsultasMCP {
    static func responder(_ pedido: [String: Any]) async -> [String: Any] {
        guard Registro.shared.estaLigado(AutomacaoModulo.shared.id) else {
            return ["erro": "O MCP do Crew está desligado (Ajustes → Automação)."]
        }
        let args = pedido["args"] as? [String: Any] ?? [:]
        let ferramenta = pedido["ferramenta"] as? String ?? ""
        if VideoMCP.ferramentas.contains(ferramenta) { return VideoMCP.responder(ferramenta, args) }
        if FalaMCP.ferramentas.contains(ferramenta) { return FalaMCP.responder(ferramenta, args) }
        switch ferramenta {
        case "estado_do_mac":   return await estadoDoMac()
        case "sessoes_abertas": return sessoes()
        case "avisar_no_notch": return avisar(args["texto"] as? String ?? "")
        case "abrir_no_crew":   return abrir(args)
        default:                return ["erro": "Ferramenta desconhecida."]
        }
    }

    private static func estadoDoMac() async -> [String: Any] {
        await Task.detached { () -> UncheckedSendable<[String: Any]> in
            let cpu = LeitorCPU()
            _ = cpu.ler()
            usleep(500_000)   // duas leituras: o uso de CPU é a diferença entre elas
            let c = cpu.ler(), m = LeitorMemoria.ler(), d = LeitorDisco.ler(), carga = LeitorCarga.ler()
            var r: [String: Any] = [
                "cpu_pct": pct(c.total),
                "memoria": ["em_uso_gb": gb(m.usada), "total_gb": gb(m.total), "swap_gb": gb(m.swapUsado),
                            "pressao": m.pressao >= 4 ? "crítica" : m.pressao >= 2 ? "atenção" : "normal"],
                "disco": ["livre_gb": gb(UInt64(max(0, d.livre))), "total_gb": gb(UInt64(max(0, d.total)))],
                "carga": [carga.um, carga.cinco, carga.quinze].map { (($0 * 100).rounded()) / 100 },
                "ligado_ha_horas": Int(carga.ligadoHa / 3600),
            ]
            if c.nucleosE > 0 { r["cpu_eficiencia_pct"] = pct(c.eficiencia); r["cpu_desempenho_pct"] = pct(c.desempenho) }
            if let t = LeitorTemperatura.ler() { r["temperatura_c"] = Int(t.rounded()) }
            if let b = LeitorBateria.ler() {
                var bat: [String: Any] = ["nivel_pct": pct(b.nivel), "carregando": b.carregando, "na_tomada": b.naTomada]
                if let s = b.saude { bat["saude_pct"] = pct(s) }
                if let m = b.minutosRestantes { bat["minutos_restantes"] = m }
                r["bateria"] = bat
            }
            return UncheckedSendable(r)
        }.value.valor
    }

    nonisolated private static func pct(_ f: Double) -> Int { Int((f * 100).rounded()) }
    nonisolated private static func gb(_ b: UInt64) -> Double { (Double(b) / 1_073_741_824 * 10).rounded() / 10 }

    private static func sessoes() -> [String: Any] {
        let lista = AppState.shared.tasks.filter { $0.source == .claudeCode }.map { t -> [String: Any] in
            var s: [String: Any] = ["estado": t.parada ? "parada" : t.state.rawValue, "oculta": t.oculta]
            if let v = t.title { s["titulo"] = v }
            if let v = t.sessionCwd { s["pasta"] = v; s["projeto"] = (v as NSString).lastPathComponent }
            return s
        }
        return ["sessoes": lista]
    }

    private static func avisar(_ texto: String) -> [String: Any] {
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return ["erro": "Texto vazio."] }
        let curto = t.count > 120 ? String(t.prefix(119)) + "…" : t
        Arbitro.shared.publicar(Sinal(id: "automacao.aviso", lugar: .barra, prioridade: .alerta, duracao: 8,
                                      conteudo: AnyView(AvisoBarra(icone: "sparkles", texto: curto, cor: Color(hex: "#A78BFA")))))
        NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
        return ["ok": true]
    }

    private static func abrir(_ args: [String: Any]) -> [String: Any] {
        let modulo = args["modulo"] as? String
        if args["onde"] as? String == "central" { Central.abrir(modulo: modulo) }
        else { NotificationCenter.default.post(name: .abrirIlha, object: modulo) }
        return ["ok": true]
    }
}
