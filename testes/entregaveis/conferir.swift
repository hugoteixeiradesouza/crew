import Foundation

// Conferência das regras dos entregáveis: o markdown em blocos, a tabela (coluna de número,
// larguras, lista dentro da célula, ordenar, filtrar, exportar) e os arquivos citados no texto.
// Os dados são inventados aqui; nada vem de conversa de verdade.

@main
enum Conferir {
    nonisolated(unsafe) static var falhas = 0
    nonisolated(unsafe) static var feitas = 0

    static func confere(_ ok: Bool, _ o: String) {
        feitas += 1
        if !ok { falhas += 1; print("  FALHOU: \(o)") }
    }

    static func igual<T: Equatable>(_ a: T, _ b: T, _ o: String) {
        feitas += 1
        if a != b { falhas += 1; print("  FALHOU: \(o)\n    veio:     \(a)\n    esperado: \(b)") }
    }

    static func main() {
        blocos()
        numeros()
        listas()
        larguras()
        ordenarEFiltrar()
        exportar()
        arquivos()
        tempo()
        print("\n\(feitas) conferências, \(falhas) falhas")
        exit(falhas == 0 ? 0 : 1)
    }

    // MARK: Blocos

    static func blocos() {
        print("== Blocos do markdown")
        let texto = """
        # Título
        Parágrafo de duas
        linhas.

        ## Seção ##
        - um
          continuação do um
        - [x] feito
        - [ ] a fazer
          - filho
        1. primeiro
        2) segundo

        > citação
        > segunda linha

        ---
        ```swift
        let a = 1
          let b = 2
        ```
        #semespaco não é título
        | A | B |
        |:--|--:|
        | 1 | `x|y` |
        | 2 | a \\| b | sobra |
        fim
        """
        let b = BlocosResposta.ler(texto)
        igual(b.count, 15, "quantidade de blocos")
        igual(b[0], .titulo(nivel: 1, texto: "Título"), "título de nível 1")
        igual(b[1], .paragrafo("Parágrafo de duas\nlinhas."), "parágrafo com quebra")
        igual(b[2], .titulo(nivel: 2, texto: "Seção"), "título de nível 2 sem os # do fim")
        igual(b[3], .item(marca: .ponto, texto: "um\ncontinuação do um", recuo: 0), "linha recuada continua o item")
        igual(b[4], .item(marca: .feito, texto: "feito", recuo: 0), "checklist marcado")
        igual(b[5], .item(marca: .aFazer, texto: "a fazer", recuo: 0), "checklist a fazer")
        igual(b[6], .item(marca: .ponto, texto: "filho", recuo: 1), "item filho")
        igual(b[7], .item(marca: .numero("1."), texto: "primeiro", recuo: 0), "item numerado")
        igual(b[8], .item(marca: .numero("2)"), texto: "segundo", recuo: 0), "item numerado com parêntese")
        igual(b[9], .citacao("citação\nsegunda linha"), "citação de duas linhas")
        igual(b[10], .fio, "separador")
        igual(b[11], .codigo(linguagem: "swift", texto: "let a = 1\n  let b = 2"), "código com linguagem e recuo")
        igual(b[12], .paragrafo("#semespaco não é título"), "# sem espaço é texto")
        if case .tabela(let t) = b[13] {
            igual(t.cabecalho, ["A", "B", ""], "cabeçalho completado até a linha mais larga")
            igual(t.linhas, [["1", "`x|y`", ""], ["2", "a | b", "sobra"]], "barra dentro de código e barra escapada não separam")
            igual(t.alinhamento, [.esquerda, .direita, nil], "alinhamento da linha de traços")
        } else { confere(false, "o bloco 13 devia ser tabela") }
        igual(b[14], .paragrafo("fim"), "texto depois da tabela")

        // Tabela sem barra no começo e cerca nunca fechada.
        let solta = BlocosResposta.ler("Nome | Valor\n---|---\na | 1\nb | 2\n\n```\nfica aberto")
        if case .tabela(let t) = solta.first {
            igual(t.cabecalho, ["Nome", "Valor"], "tabela sem barra: cabeçalho")
            igual(t.linhas.count, 2, "tabela sem barra: linhas")
        } else { confere(false, "tabela sem barra no começo") }
        igual(solta.last, .codigo(linguagem: "", texto: "fica aberto"), "cerca sem fim vira código até o fim")
        igual(BlocosResposta.ler("a | b sem tabela"), [.paragrafo("a | b sem tabela")], "barra no meio do texto não é tabela")
        // Cerca recuada dentro de lista: o recuo dela sai do código.
        igual(BlocosResposta.ler("- item\n  ```sh\n  ls -la\n    eco\n  ```").last, .codigo(linguagem: "sh", texto: "ls -la\n  eco"), "cerca recuada")
        igual(BlocosResposta.ler(""), [], "texto vazio")
    }

    // MARK: Números

    static func numeros() {
        print("== Números")
        for s in ["12", "1.234", "1.234,56", "R$ 71,78", "-7,5%", "+40,6%", "12 kg", "3 un", "0,5", "R$ -3,00", "45%", "1,2 s", "80 km/h"] {
            confere(RegrasTabela.ehNumero(s), "\"\(s)\" é número")
        }
        for s in ["", "abc", "P-1007", "12/03/2026", "Loja 3", "3 de 4", "v1.2", "10:30", "—"] {
            confere(!RegrasTabela.ehNumero(s), "\"\(s)\" não é número")
        }
        igual(RegrasTabela.valor("1.234,56"), 1234.56, "milhar com ponto e decimal com vírgula")
        igual(RegrasTabela.valor("1,234.56"), 1234.56, "milhar com vírgula e decimal com ponto")
        igual(RegrasTabela.valor("R$ 86.420,50"), 86420.5, "moeda")
        igual(RegrasTabela.valor("1.204"), 1204, "um ponto e três casas é milhar")
        igual(RegrasTabela.valor("0.125"), 0.125, "zero ponto é decimal")
        igual(RegrasTabela.valor("12.5"), 12.5, "ponto decimal")
        igual(RegrasTabela.valor("-7,5%"), -7.5, "negativo com porcentagem")
        igual(RegrasTabela.valor("−3"), -3, "sinal de menos tipográfico")
        igual(RegrasTabela.valor("2.500.000"), 2_500_000, "vários pontos são milhar")
        igual(RegrasTabela.valor("12 kg"), 12, "com unidade")
        igual(RegrasTabela.valor("abc"), nil, "texto não tem valor")

        confere(RegrasTabela.colunaNumerica(["1", "2", "3"]), "coluna de inteiros")
        confere(RegrasTabela.colunaNumerica(["R$ 1,00", "—", "R$ 2,50", ""]), "vazio e travessão não contam contra")
        confere(RegrasTabela.colunaNumerica(["**1.204**", "`3`"]), "número em negrito ou código")
        confere(!RegrasTabela.colunaNumerica(["1", "dois", "3"]), "um terço de texto: não é coluna de número")
        confere(!RegrasTabela.colunaNumerica(["—", "", "-"]), "coluna só de vazios")
        confere(!RegrasTabela.colunaNumerica(["Depósito 1 → Loja 2"]), "texto com número dentro")
        confere(RegrasTabela.colunaNumerica(["1", "2", "3", "4", "total"]), "quatro números e um texto (80%)")
    }

    // MARK: Lista na célula

    static func listas() {
        print("== Lista dentro da célula")
        igual(RegrasTabela.separadorDeLista(["Caixa (2) · Fita (4) · Lacre (9)", "Palete (1)"]), " · ", "uma célula com três itens")
        igual(RegrasTabela.separadorDeLista(["a; b", "c; d", "e"]), ";", "metade das células com dois itens")
        igual(RegrasTabela.separadorDeLista(["um<br>dois<BR/>três"]), "<br>", "quebra com <br>")
        igual(RegrasTabela.separadorDeLista(["frase com; um ponto e vírgula", "outra frase", "mais uma", "e outra"]), nil, "um ponto e vírgula solto não faz lista")
        igual(RegrasTabela.separadorDeLista(["Estável", "Cresceu em março"]), nil, "texto corrido")
        igual(RegrasTabela.separadorDeLista([]), nil, "coluna vazia")
        igual(RegrasTabela.itens("Caixa (2) · Fita (4) ·  Lacre (9) ", separador: " · "), ["Caixa (2)", "Fita (4)", "Lacre (9)"], "itens sem espaço sobrando")
        igual(RegrasTabela.itens("um<br>dois<BR/>três", separador: "<br>"), ["um", "dois", "três"], "itens por <br>")
        igual(RegrasTabela.limpo("**Total** de `3` [itens](https://exemplo.com)<br>fim"), "Total de 3 itens fim", "célula sem as marcas")
        igual(RegrasTabela.limpo("2 * 3 * 4"), "2 * 3 * 4", "asterisco de conta fica")
    }

    // MARK: Larguras

    static func larguras() {
        print("== Larguras das colunas")
        // O caso da captura: "#" curtíssima, origem → destino média, itens longa.
        let l = RegrasTabela.larguras(naturais: [40, 230, 1400], minimas: [40, 150, 220], disponivel: 736)
        igual(l.colunas[0], 40, "coluna curta fica do tamanho dela")
        igual(l.colunas[1], 230, "coluna média fica do tamanho dela")
        igual(l.colunas[2], 466, "coluna longa leva todo o resto")
        confere(!l.rola, "cabe: não rola")
        igual(l.total, 736, "a soma é a largura disponível")

        let cabe = RegrasTabela.larguras(naturais: [40, 100, 200], minimas: [40, 60, 80], disponivel: 736)
        igual(cabe.colunas, [40, 100, 200], "cabendo tudo, cada coluna fica com o natural (não estica)")

        // Duas longas dividem o resto na proporção do conteúdo.
        let duas = RegrasTabela.larguras(naturais: [50, 600, 1200], minimas: [50, 100, 100], disponivel: 650)
        igual(duas.colunas, [50, 200, 400], "duas colunas longas: proporção do conteúdo")

        // Uma das longas ficaria abaixo do mínimo: fica no mínimo e a outra cede.
        let minimo = RegrasTabela.larguras(naturais: [300, 3000], minimas: [180, 200], disponivel: 500)
        igual(minimo.colunas, [180, 320], "nenhuma coluna desce do mínimo")
        // A curta levaria o natural e a longa não caberia no mínimo dela: a curta cede.
        let cede = RegrasTabela.larguras(naturais: [100, 400], minimas: [50, 380], disponivel: 440)
        igual(cede.colunas, [60, 380], "coluna curta cede quando a longa já está no mínimo")

        // Nem os mínimos cabem: tamanho confortável e rolagem para o lado.
        let muitas = RegrasTabela.larguras(naturais: [80, 400, 120, 500, 90, 90, 90, 200, 150],
                                           minimas: [80, 160, 120, 160, 90, 90, 90, 140, 150], disponivel: 736, teto: 300)
        confere(muitas.rola, "não cabe nem no mínimo: rola")
        igual(muitas.colunas, [80, 300, 120, 300, 90, 90, 90, 200, 150], "rolando, coluna longa para no teto e as outras ficam inteiras")
        confere(muitas.total > 736, "a tabela fica mais larga que o espaço")

        igual(RegrasTabela.larguras(naturais: [], minimas: [], disponivel: 500).colunas, [], "tabela sem coluna")
        // Propriedade: sem rolar, a soma nunca passa do disponível e ninguém passa do natural.
        var ok = true
        var semente: UInt64 = 42
        func sorteio(_ ate: Double) -> Double {
            semente = semente &* 6364136223846793005 &+ 1442695040888963407
            return Double(semente >> 33).truncatingRemainder(dividingBy: ate)
        }
        for _ in 0..<2000 {
            let n = Int(sorteio(8)) + 1
            let nat = (0..<n).map { _ in 20 + sorteio(1500) }
            let mins = nat.map { min($0, 30 + sorteio(200)) }
            let disp = 200 + sorteio(1200)
            let r = RegrasTabela.larguras(naturais: nat, minimas: mins, disponivel: disp)
            if r.rola { if mins.reduce(0, +) <= disp { ok = false } }
            else {
                if r.total > disp + 0.01 { ok = false }
                for c in 0..<n where r.colunas[c] > nat[c] + 0.01 || r.colunas[c] < mins[c] - 0.01 { ok = false }
            }
        }
        confere(ok, "2000 tabelas sorteadas: soma dentro do espaço, cada coluna entre o mínimo e o natural")
    }

    // MARK: Ordenar e filtrar

    static func ordenarEFiltrar() {
        print("== Ordenar e filtrar")
        let linhas = [["Março", "1.467", "R$ 112.380,90"], ["abril", "1.390", "—"], ["Fevereiro", "980", "R$ 79.905,00"], ["Água", "12", "R$ 9,00"]]
        igual(RegrasTabela.ordenar(linhas, coluna: 1, crescente: true, numerica: true), [3, 2, 1, 0], "número crescente por valor (980 < 1.390)")
        igual(RegrasTabela.ordenar(linhas, coluna: 1, crescente: false, numerica: true), [0, 1, 2, 3], "número decrescente")
        igual(RegrasTabela.ordenar(linhas, coluna: 2, crescente: true, numerica: true), [3, 2, 0, 1], "vazio vai para o fim (crescente)")
        igual(RegrasTabela.ordenar(linhas, coluna: 2, crescente: false, numerica: true), [0, 2, 3, 1], "vazio vai para o fim (decrescente)")
        igual(RegrasTabela.ordenar(linhas, coluna: 0, crescente: true, numerica: false), [1, 3, 2, 0], "texto sem ligar para maiúscula nem acento")
        igual(RegrasTabela.ordenar([["b"], ["a"], ["b"], ["a"]], coluna: 0, crescente: true, numerica: false), [1, 3, 0, 2], "empate mantém a ordem original")
        igual(RegrasTabela.ordenar([["Loja 10"], ["Loja 2"]], coluna: 0, crescente: true, numerica: false), [1, 0], "número dentro do texto em ordem natural")

        igual(RegrasTabela.filtrar(linhas, texto: "MARCO"), [0], "filtro sem acento nem maiúscula")
        igual(RegrasTabela.filtrar(linhas, texto: "r$ agua"), [3], "duas palavras: as duas têm que aparecer")
        igual(RegrasTabela.filtrar(linhas, texto: "  "), [0, 1, 2, 3], "filtro vazio mostra tudo")
        igual(RegrasTabela.filtrar(linhas, texto: "nada disso"), [], "sem resultado")
        igual(RegrasTabela.filtrar([["**Total**", "x"]], texto: "total"), [0], "o filtro olha o texto, não as marcas")
    }

    // MARK: Exportar

    static func exportar() {
        print("== Exportar")
        let cab = ["#", "Item", "Valor"]
        let linhas = [["1", "**Caixa** \"grande\"; 30 L", "R$ 12,50"], ["2", "Fita\tlarga", "—"]]
        igual(RegrasTabela.tsv(cabecalho: cab, linhas: linhas), "#\tItem\tValor\n1\tCaixa \"grande\"; 30 L\tR$ 12,50\n2\tFita larga\t—", "texto tabulado, sem marcas e sem tab dentro da célula")
        igual(RegrasTabela.csv(cabecalho: cab, linhas: linhas), "#;Item;Valor\r\n1;\"Caixa \"\"grande\"\"; 30 L\";R$ 12,50\r\n2;Fita\tlarga;—\r\n", "CSV com ponto e vírgula: aspas dobradas e campo com separador entre aspas")
        igual(RegrasTabela.csv(cabecalho: ["a", "b"], linhas: [["1,5", "x"]], separador: ","), "a,b\r\n\"1,5\",x\r\n", "CSV com vírgula")
        igual(RegrasTabela.markdown(cabecalho: cab, linhas: [["1", "a | b", "3"]], direita: [true, false, true]), "| # | Item | Valor |\n|---:|---|---:|\n| 1 | a \\| b | 3 |", "Markdown com alinhamento e barra escapada")
        igual(RegrasTabela.html(cabecalho: ["A"], linhas: [["<b> & **c**"]], direita: [true]), "<meta charset=\"utf-8\"><table><tr><th align=\"right\">A</th></tr><tr><td align=\"right\">&lt;b&gt; &amp; c</td></tr></table>", "HTML escapado")
        // Ida e volta: o Markdown exportado, lido de novo, é a mesma tabela.
        let md = RegrasTabela.markdown(cabecalho: cab, linhas: linhas.map { $0.map { $0.replacingOccurrences(of: "\t", with: " ") } })
        if case .tabela(let t)? = BlocosResposta.ler(md).first {
            igual(t.linhas[0], linhas[0], "ida e volta do Markdown")
        } else { confere(false, "o Markdown exportado não voltou como tabela") }
    }

    // MARK: Arquivos citados

    static func arquivos() {
        print("== Arquivos citados no texto")
        let pasta = NSTemporaryDirectory() + "crew-conferir-entregaveis-\(ProcessInfo.processInfo.processIdentifier)"
        let fm = FileManager.default
        try? fm.createDirectory(atPath: pasta + "/Fontes/Sub", withIntermediateDirectories: true)
        for a in ["Fontes/Leitor.swift", "Fontes/Sub/Tabela+Larguras.swift", "roteiro.md", "Makefile.in"] {
            fm.createFile(atPath: pasta + "/" + a, contents: Data("x".utf8))
        }
        defer { try? fm.removeItem(atPath: pasta) }

        let texto = "Veja Fontes/Leitor.swift:42 e `roteiro.md`, depois Fontes/Sub/Tabela+Larguras.swift:10-20. " +
            "Não existe: Fontes/Nada.swift:3, e/ou, v1.2, exemplo.com, Fontes. Inteiro: \(pasta)/roteiro.md:7 e \(pasta)/roteiro.md."
        let a = ArquivosNoTexto.achar(em: texto, pasta: pasta)
        let ns = texto as NSString
        igual(a.map { ns.substring(with: $0.faixa) },
              ["Fontes/Leitor.swift:42", "roteiro.md", "Fontes/Sub/Tabela+Larguras.swift:10-20", "\(pasta)/roteiro.md:7"],
              "acha relativo, com linha, com faixa de linhas e inteiro com linha; ignora o que não existe")
        igual(a.map(\.linha), [42, nil, 10, 7], "a linha citada")
        igual(a.first?.url.path, URL(fileURLWithPath: pasta + "/Fontes/Leitor.swift").standardizedFileURL.path, "o relativo aponta para a pasta da sessão")
        igual(ArquivosNoTexto.achar(em: "Fontes/Leitor.swift:42", pasta: nil).count, 0, "sem pasta da sessão, relativo não vira link")
        igual(ArquivosNoTexto.achar(em: "pasta Fontes/Sub e arquivo.", pasta: pasta).count, 0, "pasta e fim de frase não viram link")
        igual(ArquivosNoTexto.achar(em: "https://exemplo.com/roteiro.md", pasta: pasta).count, 0, "pedaço de endereço da web não é arquivo")
    }

    // MARK: Tempo

    static func tempo() {
        print("== Tempo das regras (tabela de 300 linhas × 6 colunas)")
        var linhas = ["| # | Rota | Itens | Peso | Valor | Situação |", "|---|---|---|---|---|---|"]
        for i in 1...300 {
            let lista = (0..<(i % 6 + 1)).map { "Item de exemplo \($0 + i) (\(i * 3 % 40 + 1))" }.joined(separator: " · ")
            linhas.append("| \(i) | Depósito \(i % 4 + 1) → Loja \(i % 9 + 1) | \(lista) | \(i * 13 % 900) kg | R$ \(i * 17),50 | \(i % 3 == 0 ? "Pendente" : "Conferida") |")
        }
        let texto = linhas.joined(separator: "\n")
        let t0 = Date()
        var t: TabelaResposta?
        for _ in 0..<20 {
            if case .tabela(let x)? = BlocosResposta.ler(texto).first { t = x }
        }
        let ler = Date().timeIntervalSince(t0) / 20 * 1000
        guard let t else { confere(false, "a tabela grande não foi lida"); return }
        igual(t.linhas.count, 300, "300 linhas lidas")
        let t1 = Date()
        var numericas: [Bool] = []
        for _ in 0..<20 {
            numericas = (0..<t.colunas).map { c in RegrasTabela.colunaNumerica(t.linhas.map { $0[c] }) }
            _ = (0..<t.colunas).map { c in RegrasTabela.separadorDeLista(t.linhas.map { $0[c] }) }
            _ = RegrasTabela.ordenar(t.linhas, coluna: 4, crescente: false, numerica: true)
            _ = RegrasTabela.filtrar(t.linhas, texto: "loja 3 pendente")
            _ = RegrasTabela.tsv(cabecalho: t.cabecalho, linhas: t.linhas)
        }
        let regras = Date().timeIntervalSince(t1) / 20 * 1000
        igual(numericas, [true, false, false, true, true, false], "colunas de número da tabela grande")
        print(String(format: "  ler o markdown: %.2f ms · classificar, ordenar, filtrar e exportar: %.2f ms", ler, regras))
        confere(ler < 50 && regras < 100, "regras lentas demais para uma tabela de 300 linhas")
    }
}
