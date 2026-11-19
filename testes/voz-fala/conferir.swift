import Foundation

// Conferência da voz humanizada sem o motor: o corte do texto em pedaços e o guardado de falas.
// Os áudios são inventados aqui (cabeçalho de WAV + silêncio); nada vem das vozes do Hugo.

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
        pedacos()
        chaves()
        guardado()
        teto()
        tempo()
        print("\n\(feitas) conferências, \(falhas) falhas")
        exit(falhas == 0 ? 0 : 1)
    }

    // MARK: Pedaços

    static func pedacos() {
        print("== Corte do texto em pedaços")
        igual(PedacosDeFala.cortar("Terminei a tarefa."), ["Terminei a tarefa."], "frase curta fica inteira")
        igual(PedacosDeFala.cortar(""), [], "texto vazio não vira pedaço")
        igual(PedacosDeFala.cortar("Terminei a tarefa. Os testes passaram e só falta você aprovar a instalação."),
              ["Terminei a tarefa.", "Os testes passaram e só falta você aprovar a instalação."],
              "a primeira frase sai sozinha")

        let comprida = "Terminei a tarefa que você pediu hoje cedo, com todos os testes passando e o build de release sem avisos, e só falta você aprovar."
        let p = PedacosDeFala.cortar(comprida)
        igual(p.count, 2, "primeira frase comprida abre em dois")
        igual(p.first ?? "", "Terminei a tarefa que você pediu hoje cedo,", "abre na primeira vírgula que deixa um começo razoável")
        igual(p.joined(separator: " "), comprida, "nenhuma palavra se perde no corte")

        let semVirgula = String(repeating: "palavra ", count: 14) + "fim."
        igual(PedacosDeFala.cortar(semVirgula).count, 1, "frase comprida sem vírgula não é cortada no meio")
        let virgulaCedo = "Oi, " + String(repeating: "palavra ", count: 14) + "fim."
        igual(PedacosDeFala.cortar(virgulaCedo).count, 1, "vírgula cedo demais (começo de 3 letras) não corta")
        let media = "Os testes passaram, o build compilou e as capturas ficaram iguais."
        igual(PedacosDeFala.cortar(media), [media], "frase de até 90 caracteres não é cortada")

        let longo = """
        Terminei a tarefa que você pediu hoje cedo. Os testes passaram todos, o build de release compilou sem avisos e as capturas de tela ficaram iguais às de referência. Ficou de fora só a parte da integração, porque outra sessão está mexendo no mesmo arquivo e eu preferi não arriscar um conflito. Quando você puder, aprove a instalação para eu seguir com o resto.
        """
        let pl = PedacosDeFala.cortar(longo)
        igual(pl.first ?? "", "Terminei a tarefa que você pediu hoje cedo.", "texto longo começa pela primeira frase")
        confere(pl.count >= 3, "texto longo vira três pedaços ou mais (veio \(pl.count))")
        confere(pl.allSatisfy { $0.count <= 220 }, "nenhum pedaço deste texto passa de 220 caracteres")
        igual(pl.joined(separator: " "), longo, "o texto longo sai inteiro, na ordem")
        igual(PedacosDeFala.cortar("Primeira linha sem ponto\nSegunda linha sem ponto"),
              ["Primeira linha sem ponto", "Segunda linha sem ponto"], "quebra de linha separa pedaços")
    }

    // MARK: Chave

    static func chaves() {
        print("== Chave de uma fala")
        let a = CacheDeFala.chave(texto: "crew precisa da sua aprovação.", voz: "voz:clara:1:2", passos: 32)
        igual(a.count, 64, "a chave é um SHA-256 em hexadecimal")
        igual(a, CacheDeFala.chave(texto: "crew precisa da sua aprovação.", voz: "voz:clara:1:2", passos: 32), "mesma fala, mesma chave")
        confere(a != CacheDeFala.chave(texto: "crew precisa da sua aprovação.", voz: "voz:dom:1:2", passos: 32), "outra voz, outra chave")
        confere(a != CacheDeFala.chave(texto: "crew precisa da sua aprovação.", voz: "voz:clara:1:2", passos: 16), "outra velocidade, outra chave")
        confere(a != CacheDeFala.chave(texto: "crew tem uma pergunta para você.", voz: "voz:clara:1:2", passos: 32), "outro texto, outra chave")
        let ref = FileManager.default.temporaryDirectory.appendingPathComponent("conferir-ref-\(UUID().uuidString).wav")
        try? wav(segundos: 1).write(to: ref)
        let m1 = CacheDeFala.marca(id: "clara", referencia: ref)
        try? wav(segundos: 2).write(to: ref)
        confere(m1 != CacheDeFala.marca(id: "clara", referencia: ref), "voz recriada com o mesmo nome (outro áudio) tem outra marca")
        try? FileManager.default.removeItem(at: ref)
    }

    // MARK: Guardado

    static func wav(segundos: Double) -> Data {
        var d = Data("RIFF".utf8)
        d.append(Data(count: 40))
        d.append(Data(count: Int(segundos * 48_000)))
        return d
    }

    static func pastaTemporaria() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("conferir-falas-\(UUID().uuidString)")
    }

    static func guardado() {
        print("== Guardar e ler")
        let c = CacheDeFala(pasta: pastaTemporaria())
        defer { c.limpar() }
        confere(!c.tem("a"), "pasta que não existe: nada guardado")
        confere(c.ler("a") == nil, "ler o que não existe devolve nada")
        igual(c.ocupacao().falas, 0, "pasta que não existe: zero falas")
        let fala = wav(segundos: 2)
        c.guardar("a", fala)
        confere(c.tem("a"), "guardou")
        igual(c.ler("a"), fala, "o que volta é o que entrou")
        igual(c.ocupacao().falas, 1, "uma fala guardada")
        igual(c.ocupacao().bytes, Int64(fala.count), "ocupação em bytes")
        c.guardar("vazia", Data(count: 10))
        confere(!c.tem("vazia"), "áudio sem conteúdo não é guardado")
        try? Data("isto não é áudio, mas é comprido o bastante para passar do cabeçalho".utf8)
            .write(to: c.pasta.appendingPathComponent("lixo.wav"))
        confere(c.ler("lixo") == nil, "arquivo que não é WAV não é tocado")
        c.limpar()
        confere(!c.tem("a"), "limpar apaga tudo")
    }

    static func teto() {
        print("== Teto da pasta")
        // Cada fala de 1 s tem 48 044 bytes: o teto de 200 kB comporta 4
        let c = CacheDeFala(pasta: pastaTemporaria(), teto: 200_000)
        defer { c.limpar() }
        let agora = Date()
        for (i, nome) in ["a", "b", "c", "d"].enumerated() {
            c.guardar(nome, wav(segundos: 1))
            // Datas de uso espaçadas (o sistema de arquivos não distingue gravações coladas)
            try? FileManager.default.setAttributes([.modificationDate: agora.addingTimeInterval(Double(i - 100))],
                                                   ofItemAtPath: c.pasta.appendingPathComponent(nome + ".wav").path)
        }
        igual(c.ocupacao().falas, 4, "quatro falas cabem no teto")
        _ = c.ler("a")   // usar a mais antiga a traz para o fim da fila de saída
        c.guardar("e", wav(segundos: 1))
        confere(c.tem("a"), "a fala usada agora há pouco fica")
        confere(!c.tem("b"), "sai a fala usada há mais tempo")
        confere(c.tem("c") && c.tem("d") && c.tem("e"), "as outras ficam")
        confere(c.ocupacao().bytes <= 200_000, "a pasta volta para baixo do teto")
        c.guardar("enorme", wav(segundos: 2))
        confere(!c.tem("enorme"), "fala maior que um quarto do teto não entra")
    }

    // MARK: Tempo

    static func tempo() {
        print("== Tempo de tocar uma fala guardada (ler do disco)")
        let c = CacheDeFala(pasta: pastaTemporaria())
        defer { c.limpar() }
        // Um aviso típico tem ~2 s; uma leitura, pedaços de até ~15 s
        for (nome, s) in [("aviso de 2 s", 2.0), ("pedaço de 15 s", 15.0)] {
            c.guardar(nome, wav(segundos: s))
            var tempos: [Double] = []
            for _ in 0..<50 {
                let t0 = DispatchTime.now().uptimeNanoseconds
                _ = c.tem(nome)
                let d = c.ler(nome)
                tempos.append(Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6)
                if d == nil { falhas += 1 }
            }
            tempos.sort()
            print(String(format: "  %@: mediana %.2f ms, pior %.2f ms", nome, tempos[25], tempos[49]))
            confere(tempos[25] < 50, "\(nome): ler leva menos de 50 ms")
        }
    }
}
