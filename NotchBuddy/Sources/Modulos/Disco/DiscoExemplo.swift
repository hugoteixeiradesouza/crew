import Foundation

// Dados de exemplo só para o modo de captura (`Crew --capturas`): nada é varrido nem movido.

extension DiscoServico {
    func exemploParaCaptura(confirmar: Bool) {
        let gb: Int64 = 1_000_000_000
        func i(_ id: String, _ g: GrupoLimpeza, _ nome: String, _ ex: String, _ n: NivelRotulo, _ b: Int64) -> ItemLimpeza {
            ItemLimpeza(id: id, grupo: g, nome: nome, explicacao: ex, nivel: n, caminhos: ["~/exemplo/\(id)"], bytes: b)
        }
        let dev = Dictionary(uniqueKeysWithValues: CatalogoCaches.desenvolvimento.map { ($0.nome, $0) })
        func d(_ nome: String, _ b: Int64) -> ItemLimpeza {
            let x = dev[nome]!
            return i("dev:" + nome, .desenvolvimento, nome, x.explicacao, x.nivel, b)
        }
        volume = AmostraVolume(total: 494 * gb, livre: 61 * gb)
        acesso = .limitado
        itens = [
            d("Xcode — DerivedData", 14 * gb), d("Xcode — suporte a aparelhos", 9 * gb), d("npm", 3 * gb + 400_000_000),
            d("Homebrew", 2 * gb + 100_000_000), d("pnpm", 1 * gb + 800_000_000), d("Cargo (Rust)", 900_000_000),
            i("app:chrome", .apps, "Google Chrome", Rotulos.explicacao(tipo: "browser"), .seguro, 1 * gb + 200_000_000),
            i("app:slack", .apps, "Slack", Rotulos.explicacao(tipo: "messaging"), .seguro, 640_000_000),
            i("app:google-updater", .apps, "Atualizador do Google", Rotulos.explicacao(tipo: "updater"), .seguro, 310_000_000),
            i("sis:logs", .registros, "Registros (logs) de apps", "Registros antigos e relatórios de travamento dos apps. A pasta fica; só o conteúdo sai.", .seguro, 220_000_000),
        ]
        selecionados = Set(itens.filter { $0.nivel == .seguro }.map(\.id))
        estado = .pronto(Date().addingTimeInterval(-240))
        ultimo = nil
        retiradosNaRevalidacao = []
        confirmacao = confirmar ? selecionadosItens : nil
        Self.exemploSecoesNovas()
    }

    /// Projetos parados, simuladores, arquivos grandes e duplicados de mentira (só captura).
    static func exemploSecoesNovas() {
        let mb: Int64 = 1_000_000
        let h = PoliticaSeguranca.home
        let dia: TimeInterval = 86_400
        let p = ProjetosServico.shared
        func a(_ raiz: String, _ pasta: String, _ tipo: String, _ b: Int64, _ cmd: String,
               _ r: EstadoReinstalacao = .reinstalavel) -> ArtefatoProjeto {
            ArtefatoProjeto(caminho: "\(raiz)/\(pasta)", tipo: tipo, pastaRelativa: pasta, nivel: .seguro, reinstalacao: r,
                            comando: cmd, bytes: b)
        }
        let r1 = "\(h)/dev/copa-2026", r2 = "\(h)/macos-keyboardblocker", r3 = "\(h)/dev/_archive/site-antigo"
        p.projetos = [
            ProjetoParado(raiz: r1, nome: "copa-2026", ecossistemas: ["Node"], ultimoSinal: Date().addingTimeInterval(-91 * dia),
                          repositorio: r1, artefatos: [a(r1, "node_modules", "Dependências", 476 * mb, "cd \"\(r1)\" && npm install"),
                                                       a(r1, ".next", "Build do Next.js", 88 * mb, "cd \"\(r1)\" && npm install")]),
            ProjetoParado(raiz: r2, nome: "macos-keyboardblocker", ecossistemas: ["Swift"], ultimoSinal: Date().addingTimeInterval(-136 * dia),
                          repositorio: r2, artefatos: [a(r2, ".build", "Build do Swift", 220 * mb, "cd \"\(r2)\" && swift build")]),
            ProjetoParado(raiz: r3, nome: "site-antigo", ecossistemas: ["Node"], ultimoSinal: Date().addingTimeInterval(-400 * dia),
                          repositorio: nil, artefatos: [a(r3, "node_modules", "Dependências", 140 * mb, "cd \"\(r3)\" && npm install", .semLockfile)]),
        ]
        p.escondidos = EscondidosProjetos(emUso: 1, recentes: 7, comMudancas: 2, semConferir: 0)
        p.selecionados = Set(p.projetos.flatMap(\.artefatos).filter(\.marcadoPorPadrao).map(\.id))
        p.mesesDaLista = p.meses
        p.estado = .pronto(Date().addingTimeInterval(-120))

        let sim = SimuladoresServico.shared
        sim.temXcode = true
        sim.lista = [
            Simulador(udid: "6B1F0E5A-0000-4000-8000-000000000001", nome: "iPhone 15 Pro", sistema: "iOS 17.5", disponivel: false,
                      ultimoUso: Date().addingTimeInterval(-300 * dia), pasta: "", bytes: 2_400 * mb),
            Simulador(udid: "6B1F0E5A-0000-4000-8000-000000000002", nome: "iPad Air (5ª geração)", sistema: "iOS 18.2", disponivel: true,
                      ultimoUso: Date().addingTimeInterval(-60 * dia), pasta: "", bytes: 1_100 * mb),
        ]
        sim.estado = .pronto(Date().addingTimeInterval(-60))

        let ar = ArquivosServico.shared
        ar.todos = [
            ArquivoGrande(caminho: "\(h)/Movies/gravacao-tela-2026-03.mov", bytes: 3_800 * mb, ultimoUso: Date().addingTimeInterval(-190 * dia)),
            ArquivoGrande(caminho: "\(h)/Downloads/Xcode_26.xip", bytes: 2_900 * mb, ultimoUso: Date().addingTimeInterval(-120 * dia)),
            ArquivoGrande(caminho: "\(h)/Movies/CapCut/cantor-preview.mp4", bytes: 412 * mb, ultimoUso: Date().addingTimeInterval(-30 * dia)),
        ]
        ar.vistos = 19_870
        ar.selecionados = []
        ar.estado = .pronto(Date().addingTimeInterval(-90))
        let c1 = "\(h)/Movies/apresentacao.mp4", c2 = "\(h)/Downloads/apresentacao (1).mp4"
        ar.grupos = [GrupoDuplicado(id: "a1", caminhos: [c2, c1], bytes: 640 * mb, datas: [:], sugestao: c1)]
        ar.manter = ["a1": c1]
        ar.incluidos = ["a1"]
        ar.estadoDup = .pronto(Date().addingTimeInterval(-30))
    }
}
