import Foundation

// Conferência das regras do campo de endereço do navegador (histórico, completar em linha e
// ordem das sugestões). Compila junto com `Politicas/SugestoesEndereco.swift`, sem o app.
// Rodar: testes/navegador/conferir.sh

@main
enum Conferir {
    nonisolated(unsafe) static var certas = 0
    nonisolated(unsafe) static var erradas = 0

    static func confere(_ nome: String, _ ok: Bool, _ detalhe: @autoclosure () -> String = "") {
        if ok { certas += 1 } else { erradas += 1; print("FALHOU: \(nome) \(detalhe())") }
    }

    static func main() {
        let agora = Date(timeIntervalSince1970: 1_800_000_000)
        func dias(_ n: Double) -> Date { agora.addingTimeInterval(-n * 86400) }
        func v(_ url: String, _ titulo: String, vezes: Int, ha d: Double) -> VisitaNav {
            VisitaNav(url: url, titulo: titulo, ultima: dias(d), vezes: vezes)
        }
        let visitas = [
            v("https://github.com/", "GitHub", vezes: 40, ha: 0.2),
            v("https://github.com/anthropics/claude-code", "anthropics/claude-code", vezes: 12, ha: 1),
            v("https://github.com/apple/swift", "apple/swift", vezes: 3, ha: 20),
            v("https://gitlab.com/", "GitLab", vezes: 2, ha: 3),
            v("https://www.exemplo.com.br/", "Exemplo — início", vezes: 9, ha: 2),
            v("https://www.exemplo.com.br/relatorios/vendas", "Relatório de vendas", vezes: 6, ha: 1),
            v("http://localhost:3000/", "App local", vezes: 30, ha: 0.1),
            v("http://localhost:3000/painel", "Painel", vezes: 4, ha: 0.1),
            v("https://developer.apple.com/documentation/webkit", "WebKit | Apple Developer", vezes: 5, ha: 6),
            v("https://pt.wikipedia.org/wiki/Previsão_do_tempo", "Previsão do tempo – Wikipédia", vezes: 1, ha: 40),
            v("https://exato.dev/", "Exato", vezes: 1, ha: 300),
        ]
        func completar(_ t: String, _ lista: [VisitaNav]? = nil) -> CompletarNav? {
            SugestoesEndereco.completar(t, visitas: lista ?? visitas, agora: agora)
        }
        func montar(_ t: String, abas: [AbaAbertaNav] = [], buscas: [String] = [], atual: String? = nil) -> [SugestaoNav] {
            SugestoesEndereco.montar(texto: t, visitas: visitas, abas: abas, buscas: buscas, abaAtual: atual, agora: agora)
        }

        // — Completar em linha
        confere("git completa github.com", completar("git")?.resto == "hub.com", "\(String(describing: completar("git")))")
        confere("git leva à raiz do github", completar("git")?.destino == "https://github.com/")
        confere("gitl completa gitlab.com", completar("gitl")?.mostrado == "gitlab.com")
        confere("maiúsculas não atrapalham", completar("GIT")?.resto == "hub.com")
        confere("casa sem www.: exe → exemplo.com.br", completar("exe")?.resto == "mplo.com.br", "\(String(describing: completar("exe")))")
        confere("o destino guarda o www. que o site usa", completar("exe")?.destino == "https://www.exemplo.com.br/")
        confere("www.exe também completa", completar("www.exe")?.resto == "mplo.com.br")
        confere("https://git também completa", completar("https://git")?.resto == "hub.com")
        confere("loc completa localhost:3000", completar("loc")?.mostrado == "localhost:3000")
        confere("localhost vai em http", completar("loc")?.destino == "http://localhost:3000/")
        confere("nada visitado: não completa", completar("zzz") == nil)
        confere("texto com espaço: não completa", completar("git hub") == nil)
        confere("vazio: não completa", completar("") == nil)
        confere("domínio inteiro digitado: nada a completar", completar("github.com") == nil)
        confere("com barra, completa a página", completar("github.com/an")?.resto == "thropics/claude-code", "\(String(describing: completar("github.com/an")))")
        confere("com barra, o destino é a página", completar("github.com/an")?.destino == "https://github.com/anthropics/claude-code")
        confere("meio do nome não completa (hub)", completar("hub") == nil)
        // Frequente e recente ganha de raro; muito recente ganha de frequente antigo.
        let disputa = [v("https://exato.dev/", "Exato", vezes: 30, ha: 200), v("https://exemplo.org/", "Exemplo", vezes: 8, ha: 0.5)]
        confere("recente ganha de frequente parado há meses", completar("ex", disputa)?.mostrado == "exemplo.org", "\(String(describing: completar("ex", disputa)))")
        let disputa2 = [v("https://exato.dev/", "Exato", vezes: 30, ha: 3), v("https://exemplo.org/", "Exemplo", vezes: 8, ha: 0.5)]
        confere("frequente da semana ganha de pouco usado", completar("ex", disputa2)?.mostrado == "exato.dev")
        let empate = [v("https://beta.dev/", "", vezes: 1, ha: 1), v("https://bala.dev/", "", vezes: 1, ha: 1)]
        confere("empate: sempre a mesma resposta", completar("b", empate)?.mostrado == "bala.dev")
        // As páginas do site somam para o domínio.
        let soma = [v("https://alfa.dev/a", "", vezes: 3, ha: 1), v("https://alfa.dev/b", "", vezes: 3, ha: 1), v("https://alto.dev/", "", vezes: 5, ha: 1)]
        confere("as páginas somam para o domínio", completar("al", soma)?.mostrado == "alfa.dev")

        // — Ordem da lista
        let l1 = montar("git", abas: [AbaAbertaNav(id: "a1", url: "https://github.com/apple/swift", titulo: "apple/swift", espaco: "geral")])
        confere("1ª linha: o site completado", l1.first?.tipo == .site && l1.first?.destino == "https://github.com/", "\(l1.map(\.id))")
        confere("o site mostra o título da página inicial", l1.first?.titulo == "GitHub" && l1.first?.detalhe == "github.com")
        confere("2ª linha: buscar o que foi digitado", l1.count > 1 && l1[1].tipo == .buscar && l1[1].destino == "git")
        confere("3ª linha: a aba aberta", l1.count > 2 && l1[2].tipo == .aba && l1[2].aba == "a1", "\(l1.map(\.id))")
        confere("depois, páginas do histórico", l1.dropFirst(3).first?.tipo == .pagina)
        confere("a página que já é aba não repete", !l1.contains { $0.tipo == .pagina && $0.destino == "https://github.com/apple/swift" })
        confere("a raiz completada não repete como página", l1.filter { $0.destino == "https://github.com/" }.count == 1)
        confere("outro site que casa aparece (gitlab)", l1.contains { $0.destino == "https://gitlab.com/" }, "\(l1.map(\.id))")
        // Site que casa só pelo domínio (nenhuma página dele entrou na lista) vem como site.
        let l1b = SugestoesEndereco.montar(texto: "hub", visitas: [v("https://github.com/a/b/c/d", "Projeto", vezes: 2, ha: 1), v("https://hubspot.com/x", "Outro", vezes: 1, ha: 1)], abas: [], buscas: [], agora: agora)
        confere("meio do domínio: o site entra na lista", l1b.contains { $0.tipo == .site && $0.detalhe == "github.com" }, "\(l1b.map(\.id))")
        confere("no máximo 4 páginas", l1.filter { $0.tipo == .pagina }.count <= 4)
        confere("sem linhas repetidas", Set(l1.map(\.id)).count == l1.count)

        let l2 = montar("previsao do tempo", buscas: ["previsão do tempo", "previsão do tempo amanhã", "previsão do tempo sp"])
        confere("texto com espaço: 1ª linha é buscar", l2.first?.tipo == .buscar)
        confere("acento não atrapalha: acha a página", l2.contains { $0.tipo == .pagina && $0.titulo.hasPrefix("Previsão") }, "\(l2.map(\.id))")
        confere("a busca sugerida igual ao digitado não repete", !l2.contains { $0.tipo == .busca && $0.titulo == "previsão do tempo" })
        confere("buscas sugeridas vão por último", l2.last?.tipo == .busca && l2.filter { $0.tipo == .busca }.count == 2)

        let l3 = montar("receita de pao", buscas: ["receita de pão caseiro", "receita de pão de queijo", "a", "b", "c", "d", "e"])
        confere("nunca visitado: buscar + sugeridas", l3.map(\.tipo) == [.buscar] + Array(repeating: .busca, count: 5), "\(l3.map(\.id))")

        let l4 = montar("novosite.com")
        confere("endereço novo: 1ª linha abre o endereço", l4.first?.tipo == .endereco && l4.first?.destino == "novosite.com")
        confere("endereço novo: 2ª linha busca", l4.count == 2 && l4[1].tipo == .buscar)
        let l5 = montar("github.com")
        confere("endereço já visitado: abre, sem linha repetida", l5.first?.tipo == .endereco && !l5.contains { $0.tipo == .site && $0.detalhe == "github.com" }, "\(l5.map(\.id))")
        confere("vazio: lista vazia", montar("   ").isEmpty)

        let abas = [AbaAbertaNav(id: "x", url: "http://localhost:3000/painel", titulo: "Painel", espaco: "geral"),
                    AbaAbertaNav(id: "y", url: "http://localhost:3000/painel", titulo: "Painel", espaco: "outro"),
                    AbaAbertaNav(id: "z", url: "https://exemplo.dev/painel-novo", titulo: "Painel novo", espaco: "geral")]
        let l6 = montar("painel", abas: abas, atual: "x")
        confere("a aba que está na tela não é sugerida", !l6.contains { $0.aba == "x" })
        confere("a mesma página em dois espaços aparece uma vez", l6.filter { $0.tipo == .aba }.map(\.aba) == ["y", "z"], "\(l6.map(\.id))")
        confere("a aba leva o espaço dela", l6.first { $0.aba == "y" }?.espaco == "outro")

        // — Quando pedir buscas sugeridas
        func quer(_ t: String) -> Bool { SugestoesEndereco.querBuscas(t, visitas: visitas, abas: [], agora: agora) }
        confere("nunca visitado: pede sugestões", quer("receita de pao"))
        confere("casa com o histórico: não pede", !quer("git"))
        confere("casa com página do histórico: não pede", !quer("relatorio"))
        confere("parece endereço: não pede", !quer("novosite.com"))
        confere("uma letra só: não pede", !quer("z"))

        // — Parece endereço
        for (t, e) in [("github.com", true), ("localhost:3000", true), ("192.168.0.1", true), ("https://a", true),
                       ("github", false), ("o que é swift", false), ("3.5", true), ("fim.", false), ("", false)] {
            confere("pareceEndereco(\(t))", SugestoesEndereco.pareceEndereco(t) == e)
        }

        // — Histórico
        var h: [VisitaNav] = []
        confere("guarda https", HistoricoRegras.registrar(&h, url: "https://a.dev/x#topo", titulo: "X", agora: dias(2)))
        confere("a âncora não faz outra página", h.first?.url == "https://a.dev/x")
        HistoricoRegras.registrar(&h, url: "https://a.dev/x#fim", titulo: "", agora: dias(1))
        confere("segunda visita soma e não apaga o título", h.count == 1 && h[0].vezes == 2 && h[0].titulo == "X" && h[0].ultima == dias(1))
        for ruim in ["about:blank", "file:///Users/x/a.html", "data:text/html,oi", "blob:https://a.dev/1", "", "javascript:void(0)"] {
            confere("não guarda \(ruim)", !HistoricoRegras.registrar(&h, url: ruim, titulo: "", agora: agora) && h.count == 1)
        }
        confere("título que chega depois não conta visita", HistoricoRegras.intitular(&h, url: "https://a.dev/x", titulo: "Novo") && h[0].vezes == 2 && h[0].titulo == "Novo")
        confere("título de página não visitada é ignorado", !HistoricoRegras.intitular(&h, url: "https://b.dev/", titulo: "B"))
        var cheio: [VisitaNav] = []
        for i in 0..<12 { HistoricoRegras.registrar(&cheio, url: "https://s\(i).dev/", titulo: "", agora: dias(Double(12 - i)), limite: 10) }
        confere("limite respeitado", cheio.count == 10)
        confere("saem as mais antigas", !cheio.contains { $0.url == "https://s0.dev/" || $0.url == "https://s1.dev/" } && cheio.contains { $0.url == "https://s11.dev/" })
        let dados = try! JSONEncoder().encode(h)
        confere("vai e volta do disco (JSON)", (try? JSONDecoder().decode([VisitaNav].self, from: dados)) == h)

        print("\(certas) certas, \(erradas) erradas")
        exit(erradas == 0 ? 0 : 1)
    }
}
