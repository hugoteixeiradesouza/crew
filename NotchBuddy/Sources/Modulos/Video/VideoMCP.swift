import Foundation

// O que as sessões do Claude Code fazem com o Vídeo pelo servidor MCP do Crew: ver o estado,
// criar um projeto e mandar renderizar. Renderizar começa e volta na hora (a ferramenta não
// pode ficar esperando minutos): a sessão acompanha por `videos`.

@MainActor
enum VideoMCP {
    static let ferramentas: Set<String> = ["videos", "video_criar", "video_renderizar"]

    static func responder(_ ferramenta: String, _ args: [String: Any]) -> [String: Any] {
        guard Registro.shared.estaLigado(VideoServico.modulo) else {
            return ["erro": "O módulo Vídeo está desligado (Ajustes do Crew › Vídeo)."]
        }
        let s = VideoServico.shared
        switch ferramenta {
        case "videos":
            s.atualizar()
            var r: [String: Any] = [
                "motor_instalado": s.instalado,
                "pasta_dos_projetos": MotorRemotion.videos.path,
                "pasta_dos_videos_prontos": MotorRemotion.saidas.path,
                "projetos": s.projetos.map { p -> [String: Any] in
                    var o: [String: Any] = ["nome": p.nome, "pasta": p.pasta.path]
                    if let c = s.composicoes[p.nome] { o["composicoes"] = c }
                    return o
                },
                "prontos": s.prontos.prefix(10).map { ["arquivo": $0.url.path, "bytes": $0.bytes] as [String: Any] },
            ]
            if !s.instalado { r["como_instalar"] = "\(Usuario.nome) instala pelo botão em Ajustes do Crew › Vídeo." }
            if let v = s.render {
                r["renderizando"] = ["projeto": v.projeto, "composicao": v.composicao, "fase": v.fase,
                                     "quadros_feitos": v.feitos, "quadros_total": v.total, "saida": v.saida.path] as [String: Any]
            }
            if let e = s.ultimoErro { r["ultimo_erro"] = e }
            return r
        case "video_criar":
            guard s.instalado else { return ["erro": "O motor de vídeo não está instalado. \(Usuario.nome) instala em Ajustes do Crew › Vídeo."] }
            switch s.criar(nome: args["nome"] as? String ?? "", titulo: args["titulo"] as? String) {
            case .success(let p):
                return ["ok": true, "nome": p.nome, "pasta": p.pasta.path,
                        "proximo_passo": "Edite Raiz.tsx nessa pasta (leia o CLAUDE.md dois níveis acima) e chame video_renderizar."]
            case .failure(let f): return ["erro": f.texto]
            }
        case "video_renderizar":
            let projeto = args["projeto"] as? String ?? ""
            let composicao = args["composicao"] as? String ?? ""
            guard !projeto.isEmpty, !composicao.isEmpty else { return ["erro": "Informe projeto e composicao."] }
            var props: String?
            if let p = args["props"] as? [String: Any], !p.isEmpty,
               let d = try? JSONSerialization.data(withJSONObject: p) { props = String(decoding: d, as: UTF8.self) }
            switch s.renderizar(projeto: projeto, composicao: composicao, props: props) {
            case .success(let saida):
                return ["iniciado": true, "saida": saida.path,
                        "acompanhar": "Chame `videos` para ver o andamento; quando `renderizando` sumir, confira `ultimo_erro` e se o arquivo existe."]
            case .failure(let f): return ["erro": f.texto]
            }
        default:
            return ["erro": "Ferramenta desconhecida."]
        }
    }
}
