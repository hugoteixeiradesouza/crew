import Foundation

// Conferência do leitor da conversa. Três partes:
//  1. regras do texto do pedido (texto colado, comando de barra, ruído do sistema);
//  2. um transcript montado aqui com cada forma de mensagem e de passo;
//  3. transcripts de verdade: o que o Hugo mandou (dito pelo próprio transcript) × o que o
//     leitor antigo mostrava × o que o novo mostra, com o tempo de leitura dos dois.
// Não imprime o conteúdo das conversas: só contagens, tamanhos e o começo de cada caso.

@main
enum Conferir {
    nonisolated(unsafe) static var falhas = 0
    nonisolated(unsafe) static var feitas = 0

    static func confere(_ ok: Bool, _ o: String) {
        feitas += 1
        if !ok { falhas += 1; print("  FALHOU: \(o)") }
    }

    static func main() {
        regras()
        montado()
        let args = Array(CommandLine.arguments.dropFirst())
        let pasta = NSHomeDirectory() + "/.claude/projects/-Users-hugo-dev-crew"
        let casoReal = pasta + "/dbd8104e-7e6a-4f58-9c75-9be425a93641.jsonl"
        if args.isEmpty {
            if FileManager.default.fileExists(atPath: casoReal) { casoDoHugo(casoReal) }
            let todos = ((try? FileManager.default.contentsOfDirectory(atPath: pasta)) ?? [])
                .filter { $0.hasSuffix(".jsonl") }.sorted().map { pasta + "/" + $0 }
            var soma = (verdade: 0, antigo: 0, novo: 0)
            for t in todos {
                let r = comparar(t)
                soma.verdade += r.verdade; soma.antigo += r.antigo; soma.novo += r.novo
            }
            print("\nTODAS (\(todos.count) transcrições): \(soma.verdade) mensagens do Hugo · leitor antigo errava \(soma.antigo) · leitor novo erra \(soma.novo)")
            confere(soma.novo == 0, "o leitor novo ainda mostra mensagem errada")
        } else {
            for t in args { let r = comparar(t); confere(r.novo == 0, "leitor novo erra em \(t)") }
        }
        print("\n\(feitas) conferências, \(falhas) falhas")
        exit(falhas == 0 ? 0 : 1)
    }

    // MARK: 1. Regras do texto

    static func regras() {
        print("== Regras do texto do pedido")
        let l = { (s: String) in TextoDoPedido.limpar(s) }
        confere(l("oi") == "oi", "texto simples")
        confere(l("\n\n<pasted_content id=\"2660\">\n1. primeiro\n2. segundo\n</pasted_content id=\"2660\">\n\nfim [Image #2]")
                == "1. primeiro\n2. segundo\n\nfim [Image #2]", "texto colado perde só as marcas: \(l("\n\n<pasted_content id=\"2660\">\n1. primeiro\n2. segundo\n</pasted_content id=\"2660\">\n\nfim [Image #2]").debugDescription)")
        confere(l("antes <pasted_content id=\"1\">meio</pasted_content> depois") == "antes meio depois", "colado no meio da frase")
        confere(l("<system-reminder>\nlembrete\n</system-reminder>") == "", "lembrete do sistema fica fora")
        confere(l("pergunta\n<system-reminder>x</system-reminder>") == "pergunta", "lembrete grudado na fala sai, a fala fica")
        confere(l("<task-notification>\n<task-id>a</task-id>\n</task-notification>") == "", "aviso de tarefa fica fora")
        confere(l("<command-name>/model</command-name>\n<command-message>model</command-message>\n<command-args>opus</command-args>") == "/model opus", "comando de barra: \(l("<command-name>/model</command-name>\n<command-message>model</command-message>\n<command-args>opus</command-args>").debugDescription)")
        confere(l("<command-name>/clear</command-name>\n<command-message>clear</command-message>\n<command-args></command-args>") == "/clear", "comando de barra sem argumento")
        confere(l("<local-command-stdout>Set model to opus</local-command-stdout>") == "", "saída de comando local fica fora")
        confere(l("<local-command-caveat>Caveat: x</local-command-caveat>") == "", "aviso de comando local fica fora")
        confere(l("<bash-input>ls -la</bash-input>") == "! ls -la", "comando de shell com !")
        confere(l("<coisa-nova>recado</coisa-nova>") == "", "bloco só de marca desconhecida, sem origem: ruído")
        confere(TextoDoPedido.limpar("<div>colei html</div>", humano: true) == "<div>colei html</div>", "html colado pelo Hugo fica")
        confere(l("use List<String> aqui e 2 < 3") == "use List<String> aqui e 2 < 3", "sinal de menor no meio do texto fica")
        confere(l("<nome> é o campo que falta") == "<nome> é o campo que falta", "fala que começa com < mas não é bloco fica")
        confere(TextoDoPedido.ehInterrupcao("[Request interrupted by user for tool use]"), "aviso de interrupção")
        // Retorno de comando fica na conversa
        confere(TextoDoPedido.saidaDeComando("<local-command-stdout>Set model to `Opus 5.5`</local-command-stdout>") == "Set model to `Opus 5.5`", "retorno do /model")
        confere(TextoDoPedido.saidaDeComando("<local-command-stdout>\u{1B}[1mTotal\u{1B}[0m: 3</local-command-stdout>") == "Total: 3", "retorno sem as cores do terminal")
        confere(TextoDoPedido.saidaDeComando("<bash-stdout>a\nb</bash-stdout><bash-stderr></bash-stderr>") == "a\nb", "retorno de comando de shell")
        confere(TextoDoPedido.saidaDeComando("<local-command-stdout></local-command-stdout>") == nil, "retorno vazio não vira fala")
        confere(TextoDoPedido.saidaDeComando("<local-command-stdout>(no content)</local-command-stdout>") == nil, "sem conteúdo não vira fala")
        confere(TextoDoPedido.saidaDeComando("<command-name>/model</command-name><local-command-stdout>x</local-command-stdout>") == nil, "linha com o comando é a fala do Hugo")
        confere(TextoDoPedido.saidaDeComando("oi, tudo bem?") == nil, "fala comum não é retorno")
        tarefas()
        // A data do transcript, contada na mão, bate com a do sistema.
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for d in ["2026-11-13T03:15:13.874Z", "2024-02-29T23:59:59.001Z", "2025-01-01T00:00:00.000Z", "2026-03-01T12:00:00.500Z"] {
            let nossa = TranscriptReader.instante(iso: d)?.timeIntervalSince1970 ?? -1
            confere(abs(nossa - (iso.date(from: d)?.timeIntervalSince1970 ?? -2)) < 0.0005, "data \(d)")
        }
    }

    // A lista de tarefas do Claude, montada a partir dos passos.
    static func tarefas() {
        func fala(_ passos: [PassoConversa]) -> SessionMessage { SessionMessage(id: passos.count, fromUser: false, text: "", passos: passos) }
        func passo(_ id: String, _ nome: String, _ entrada: [String: Any], resultado: String? = "ok", erro: Bool = false) -> PassoConversa {
            var p = LeitorPassos.passo(id: id, nome: nome, entrada: entrada, quando: nil)
            if let resultado {
                p.resultado = LeitorPassos.resultado(bloco: ["content": resultado, "is_error": erro], estruturado: nil, quando: nil)
            }
            return p
        }
        // Lista inteira de uma vez (TodoWrite): a última vale.
        let a = ListaDeTarefas.montar([fala([
            passo("a1", "TodoWrite", ["todos": [["content": "Ler", "status": "in_progress", "activeForm": "Lendo"], ["content": "Testar", "status": "pending"]]]),
            passo("a2", "TodoWrite", ["todos": [["content": "Ler", "status": "completed"], ["content": "Testar", "status": "in_progress"]]]),
        ])])
        confere(a.map(\.titulo) == ["Ler", "Testar"] && a.map(\.estado) == [.feita, .fazendo], "lista inteira: vale a última")
        // Criar e atualizar (TaskCreate / TaskUpdate), com o número vindo do resultado.
        let b = ListaDeTarefas.montar([fala([
            passo("b1", "TaskCreate", ["subject": "Ler a cadeia", "activeForm": "Lendo a cadeia"], resultado: "Task #1 created successfully: Ler a cadeia"),
            passo("b2", "TaskCreate", ["subject": "Testar"], resultado: "Task #2 created successfully: Testar"),
            passo("b3", "TaskUpdate", ["taskId": "1", "status": "in_progress"]),
        ]), fala([
            passo("b4", "TaskUpdate", ["taskId": "1", "status": "completed"]),
            passo("b5", "TaskUpdate", ["taskId": "2", "status": "in_progress", "subject": "Testar tudo"]),
            passo("b6", "TaskUpdate", ["taskId": "9", "status": "completed"]),
        ])])
        confere(b.map(\.id) == ["1", "2"], "tarefa criada leva o número do resultado")
        confere(b.map(\.estado) == [.feita, .fazendo] && b[1].titulo == "Testar tudo", "atualizações na ordem; tarefa desconhecida é ignorada")
        confere(b[0].fazendo == "Lendo a cadeia", "a frase de andamento fica guardada")
        // Ainda sem resultado: numera em sequência. Apagada sai. Criação que deu erro não entra.
        let c = ListaDeTarefas.montar([fala([
            passo("c1", "TaskCreate", ["subject": "Um"], resultado: nil),
            passo("c2", "TaskCreate", ["subject": "Dois"], resultado: nil),
            passo("c3", "TaskCreate", ["subject": "Falhou"], resultado: "erro", erro: true),
            passo("c4", "TaskUpdate", ["taskId": "1", "status": "deleted"]),
        ])])
        confere(c.map(\.id) == ["2"] && c[0].titulo == "Dois", "sem resultado numera em sequência; apagada sai; erro não entra")
        // Plano novo depois de um concluído: o antigo sai.
        let d = ListaDeTarefas.montar([fala([
            passo("d1", "TaskCreate", ["subject": "Antiga"], resultado: "Task #1 created successfully"),
            passo("d2", "TaskUpdate", ["taskId": "1", "status": "completed"]),
            passo("d3", "TaskCreate", ["subject": "Nova"], resultado: "Task #2 created successfully"),
        ])])
        confere(d.map(\.titulo) == ["Nova"], "plano novo substitui o concluído")
        confere(ListaDeTarefas.montar([fala([passo("e1", "TaskList", [:]), passo("e2", "Bash", ["command": "ls"])])]).isEmpty, "consulta e outras ferramentas não criam lista")
    }

    // MARK: 2. Transcript montado

    static func montado() {
        print("== Transcript montado (cada forma de mensagem e de passo)")
        let png = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
        func img() -> [String: Any] { ["type": "image", "source": ["type": "base64", "media_type": "image/png", "data": png]] }
        func usuario(_ c: Any, _ extra: [String: Any] = ["origin": ["kind": "human"], "permissionMode": "auto"]) -> [String: Any] {
            var o: [String: Any] = ["type": "user", "timestamp": "2026-11-13T10:00:00.000Z", "message": ["role": "user", "content": c]]
            o.merge(extra) { _, b in b }
            return o
        }
        func claude(_ blocos: [[String: Any]], _ extra: [String: Any] = [:]) -> [String: Any] {
            var o: [String: Any] = ["type": "assistant", "timestamp": "2026-11-13T10:00:05.000Z",
                                    "message": ["role": "assistant", "id": "msg_\(blocos.count)", "content": blocos, "usage": ["output_tokens": 10]]]
            o.merge(extra) { _, b in b }
            return o
        }
        func uso(_ id: String, _ nome: String, _ entrada: [String: Any]) -> [String: Any] {
            claude([["type": "tool_use", "id": id, "name": nome, "input": entrada]])
        }
        func volta(_ id: String, _ conteudo: Any, erro: Bool = false, estruturado: Any? = nil) -> [String: Any] {
            var o = usuario([["type": "tool_result", "tool_use_id": id, "content": conteudo, "is_error": erro]], [:])
            if let estruturado { o["toolUseResult"] = estruturado }
            return o
        }
        let saidaLonga = (1...113).map { "linha \($0)" }.joined(separator: "\n")
        let linhas: [[String: Any]] = [
            // 0: texto simples
            usuario("primeira pergunta"),
            claude([["type": "text", "text": "Resposta um."]]),
            // 2: comando de barra (sem origem) + aviso + saída
            usuario("<local-command-caveat>Caveat</local-command-caveat>", ["isMeta": true]),
            usuario("<command-name>/model</command-name>\n<command-message>model</command-message>\n<command-args>opus</command-args>", [:]),
            usuario("<local-command-stdout>Set model to opus</local-command-stdout>", [:]),
            // 5: texto colado + duas imagens (o caso do Hugo)
            usuario([["type": "text", "text": "\n\n<pasted_content id=\"9\">\n1. item um\n2. item dois\n</pasted_content id=\"9\">\n\n3. digitado[Image #1] [Image #2]"], img(), img()]),
            usuario([["type": "text", "text": "[Image: source: /tmp/a.png]"]], ["isMeta": true]),
            claude([["type": "thinking", "thinking": ""]], ["thinkingDurationMs": 8200]),
            claude([["type": "text", "text": "Vou olhar os arquivos."]]),
            uso("t1", "Read", ["file_path": "/p/A.swift"]),
            volta("t1", "1\tx", estruturado: ["type": "text", "file": ["filePath": "/p/A.swift", "numLines": 120, "totalLines": 120]]),
            uso("t2", "Read", ["file_path": "/p/B.swift"]),
            volta("t2", "1\tx", estruturado: ["type": "text", "file": ["filePath": "/p/B.swift", "numLines": 50, "totalLines": 900]]),
            uso("t3", "Bash", ["command": "xcodebuild -scheme X build 2>&1 | tail -5", "description": "Compilar o app"]),
            volta("t3", saidaLonga, estruturado: ["stdout": saidaLonga, "stderr": "", "interrupted": false]),
            uso("t4", "Bash", ["command": "rm -rf /"]),
            volta("t4", "Permission for this action was denied by the Claude Code auto mode classifier. Reason: [Destrutivo]. If you have other tasks, continue.", erro: true),
            uso("t5", "Edit", ["file_path": "/p/A.swift", "old_string": "a", "new_string": "b"]),
            volta("t5", "updated", estruturado: ["filePath": "/p/A.swift", "structuredPatch": [["lines": [" x", "-a", "+b", "+c"]]]]),
            uso("t6", "Bash", ["command": "swift test", "description": "Rodar os testes"]),
            volta("t6", "Exit code 1\nerro: falhou\n<system-reminder>ruído</system-reminder>", erro: true),
            // mensagem mandada no meio do turno, com imagem (pedido em lista)
            ["type": "attachment", "attachment": ["type": "queued_command", "commandMode": "prompt", "origin": ["kind": "human"],
                                                  "prompt": [["type": "text", "text": "[Image #3] olha isso também"], img()]]],
            // aviso de tarefa na fila: não é fala
            ["type": "attachment", "attachment": ["type": "queued_command", "commandMode": "task-notification",
                                                  "origin": ["kind": "task-notification"], "prompt": "<task-notification>x</task-notification>"]],
            usuario("<task-notification>\n<task-id>z</task-id>\n</task-notification>", ["origin": ["kind": "task-notification"]]),
            claude([["type": "text", "text": "Resposta final do turno."]]),
            ["type": "system", "subtype": "turn_duration", "durationMs": 95000, "timestamp": "2026-11-13T10:02:00.000Z"],
            // resumo de contexto e continuação
            usuario("This session is being continued… resumo enorme", ["isCompactSummary": true]),
            usuario("continua de onde parou"),
            uso("t7", "Agent", ["description": "Varrer o módulo", "prompt": "…", "subagent_type": "Explore"]),
            volta("t7", [["type": "text", "text": "Async agent launched"]], estruturado: ["isAsync": true, "agentId": "a1"]),
            claude([["type": "text", "text": "Lancei o agente."]]),
            usuario([["type": "text", "text": "[Request interrupted by user]"]], [:]),
            // turno em andamento: fala, passo sem resultado
            usuario("e agora?"),
            claude([["type": "text", "text": "Conferindo."]]),
            uso("t8", "Grep", ["pattern": "TODO", "path": "/p"]),
        ]
        let caminho = NSTemporaryDirectory() + "crew-conferir-\(getpid()).jsonl"
        let txt = linhas.map { String(data: try! JSONSerialization.data(withJSONObject: $0), encoding: .utf8)! }.joined(separator: "\n") + "\n"
        try! txt.write(toFile: caminho, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: caminho) }

        let msgs = TranscriptReader.ler(path: caminho, limit: 500).mensagens
        let doHugo = msgs.filter(\.fromUser)
        confere(doHugo.map(\.text) == ["primeira pergunta", "/model opus", "1. item um\n2. item dois\n\n3. digitado[Image #1] [Image #2]",
                                       "[Image #3] olha isso também", "continua de onde parou", "e agora?"],
                "falas do Hugo: \(doHugo.map(\.text))")
        confere(doHugo[2].images.count == 2, "as duas imagens da mensagem colada")
        confere(doHugo[3].images.count == 1, "a imagem da mensagem mandada no meio do turno")
        confere(doHugo[0].modoPermissao == "auto", "modo de permissão do pedido")
        confere(msgs.filter(\.resumo).count == 1, "um marco de conversa resumida")

        let antigas = LeitorAntigo.ler(path: caminho, limit: 500).mensagens.filter(\.fromUser).map(\.text)
        print("  leitor antigo mostrava \(antigas.count) das 6 falas do Hugo; o novo, \(doHugo.count)")
        confere(antigas == ["primeira pergunta", "", "continua de onde parou", "e agora?"], "o leitor antigo errava 3 das 6 (colada sem o texto; barra e meio do turno sumidas): \(antigas)")

        let turnos = TurnoConversa.agrupar(msgs)
        confere(turnos.count == 7, "7 turnos (com o marco de resumo): \(turnos.count)")
        guard turnos.count == 7 else { return }
        let t = turnos[2]   // o turno da mensagem colada
        // A mensagem mandada no meio do turno abre o turno seguinte: a resposta e o tempo ficam nele.
        confere(t.answer == nil && turnos[3].answer?.text == "Resposta final do turno.", "resposta final: \(turnos[3].answer?.text ?? "nil")")
        confere(turnos[3].duracao == 95, "duração do turno")
        confere(t.totalDePassos == 6, "6 passos de ferramenta: \(t.totalDePassos)")
        let formas = t.caminho.map { item -> String in
            switch item {
            case .fala: return "fala"
            case .passo(let p): return p.tipo.rawValue
            case .grupo(_, let tipo, let ps): return "\(ps.count)x\(tipo.rawValue)"
            }
        }
        confere(formas == ["pensamento", "fala", "2xleitura", "comando", "comando", "edicao", "comando"], "forma do caminho: \(formas)")
        let ps = t.passos.filter { $0.tipo != .pensamento }
        confere(ps[0].alvo == "A.swift" && ps[0].resultado?.resumo == "120 linhas", "leitura: \(ps[0].alvo) \(ps[0].resultado?.resumo ?? "")")
        confere(ps[1].resultado?.resumo == "50 de 900 linhas", "leitura parcial: \(ps[1].resultado?.resumo ?? "")")
        confere(ps[2].alvo == "Compilar o app" && ps[2].tecnico.hasPrefix("xcodebuild"), "comando com descrição")
        confere(ps[2].resultado?.total == 113 && ps[2].resultado?.linhas.count == 60, "saída longa: total e teto guardado")
        confere(ps[3].resultado?.negado == "auto" && ps[3].resultado?.linhas == ["[Destrutivo]"], "bloqueio do modo automático com o motivo: \(ps[3].resultado?.linhas ?? [])")
        confere(ps[4].resultado?.resumo == "+2 −1 linhas", "edição: \(ps[4].resultado?.resumo ?? "")")
        confere(ps[5].resultado?.erro == true && ps[5].resultado?.linhas == ["Exit code 1", "erro: falhou"], "erro sem o lembrete: \(ps[5].resultado?.linhas ?? [])")
        confere(t.resumoDoCaminho == "3 comandos · leu 2 arquivos · mexeu em 1 arquivo · 1 erro · 1 bloqueado", "resumo: \(t.resumoDoCaminho)")
        confere(turnos[3].user?.text == "[Image #3] olha isso também", "mensagem do meio do turno abre turno")
        let agente = turnos[5]
        confere(agente.answer?.text == "Lancei o agente." && agente.passos.contains { $0.tipo == .interrupcao }, "interrupção vira marco, a resposta fica")
        confere(agente.passos.first?.resultado?.resumo == "lançado em segundo plano", "agente em segundo plano")
        let vivo = turnos[6]
        confere(vivo.answer == nil && vivo.passoRodando?.id == "t8", "turno em andamento: passo rodando, sem resposta ainda")
        // A ilha continua recebendo só falas.
        confere(TranscriptReader.messages(path: caminho, limit: 500).allSatisfy { $0.ehFala && $0.passos.isEmpty }, "ilha: só falas")
    }

    // MARK: 3. Transcripts de verdade

    struct Esperada { let id: Int; let texto: String; let imagens: Int }

    /// O que o Hugo mandou, dito pelo transcript — por um caminho independente do leitor:
    /// linhas com origem "human" (ou comando de barra), com as marcas de colagem tiradas à mão.
    static func verdade(_ caminho: String) -> [Esperada] {
        guard let data = FileManager.default.contents(atPath: caminho) else { return [] }
        var out: [Esperada] = []
        var lo = 0
        func textoEImagens(_ c: Any?) -> (String, Int) {
            if let s = c as? String { return (s, 0) }
            let partes = c as? [[String: Any]] ?? []
            return (partes.compactMap { $0["text"] as? String }.joined(separator: "\n"),
                    partes.filter { $0["type"] as? String == "image" }.count)
        }
        while lo < data.count {
            let hi = data[lo...].firstIndex(of: 0x0A) ?? data.count
            defer { lo = hi + 1 }
            guard hi > lo, let o = try? JSONSerialization.jsonObject(with: data[lo..<hi]) as? [String: Any] else { continue }
            var bruto: (String, Int)?
            if o["type"] as? String == "user", o["isMeta"] as? Bool != true, o["isSidechain"] as? Bool != true,
               o["isCompactSummary"] as? Bool != true, let m = o["message"] as? [String: Any] {
                let origem = (o["origin"] as? [String: Any])?["kind"] as? String
                let (t, n) = textoEImagens(m["content"])
                if origem == "human" { bruto = (t, n) }
                else if origem == nil, t.contains("<command-name>") {
                    // "/nome args"
                    func entre(_ a: String) -> String {
                        guard let i = t.range(of: "<\(a)>"), let f = t.range(of: "</\(a)>") else { return "" }
                        return String(t[i.upperBound..<f.lowerBound])
                    }
                    let nome = entre("command-name")
                    bruto = ((nome.hasPrefix("/") ? nome : "/" + nome) + " " + entre("command-args"), 0)
                }
            } else if o["type"] as? String == "attachment", let a = o["attachment"] as? [String: Any],
                      a["type"] as? String == "queued_command", a["commandMode"] as? String ?? "prompt" == "prompt",
                      (a["origin"] as? [String: Any])?["kind"] as? String == "human" {
                bruto = textoEImagens(a["prompt"])
            }
            guard let (t0, n) = bruto else { continue }
            let t = t0.replacingOccurrences(of: #"</?pasted_content[^>]*>"#, with: "", options: .regularExpression)
            if t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, n == 0 { continue }
            out.append(Esperada(id: lo, texto: t, imagens: n))
        }
        return out
    }

    /// Compara sem ligar para espaço e quebra de linha (o leitor apara as pontas).
    static func igual(_ a: String, _ b: String) -> Bool {
        a.filter { !$0.isWhitespace } == b.filter { !$0.isWhitespace }
    }

    static func cronometrar<T>(_ f: () -> T) -> (T, Double) {
        let t0 = DispatchTime.now().uptimeNanoseconds
        let r = f()
        return (r, Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000)
    }

    static func comparar(_ caminho: String) -> (verdade: Int, antigo: Int, novo: Int) {
        let esperadas = verdade(caminho)
        let tamanho = (try? FileManager.default.attributesOfItem(atPath: caminho))?[.size] as? UInt64 ?? 0
        // Tempo a frio (o leitor guarda as linhas por caminho: cada medida usa um caminho novo),
        // mediana de 5, alternando antigo e novo: abrir a conversa (as 30 falas do fim, como o
        // app faz) e ler o transcript inteiro. "Reler" é a leitura seguinte, com as linhas guardadas.
        var copias: [String] = []
        defer { for c in copias { try? FileManager.default.removeItem(atPath: c) } }
        func copia() -> String {
            let c = NSTemporaryDirectory() + "crew-conferir-\(getpid())-\(copias.count)-" + (caminho as NSString).lastPathComponent
            try? FileManager.default.removeItem(atPath: c)
            try? FileManager.default.createSymbolicLink(atPath: c, withDestinationPath: caminho)
            copias.append(c)
            return c
        }
        func mediana(_ v: [Double]) -> Double { v.sorted()[v.count / 2] }
        _ = FileManager.default.contents(atPath: caminho)   // aquece o disco para os dois
        var tAbrirAntigo: [Double] = [], tAbrirNovo: [Double] = [], tTudoAntigo: [Double] = [], tTudoNovo: [Double] = []
        var antigo: [FalaAntiga] = []
        var leitura = LeituraConversa()
        var relerNovo = 0.0
        for _ in 0..<5 {
            let a = copia(), b = copia(), c = copia(), d = copia()
            tAbrirAntigo.append(cronometrar { LeitorAntigo.ler(path: a, limit: 30) }.1)
            tAbrirNovo.append(cronometrar { TranscriptReader.ler(path: b, limit: 30) }.1)
            let ra = cronometrar { LeitorAntigo.ler(path: c, limit: 1_000_000).mensagens }
            antigo = ra.0; tTudoAntigo.append(ra.1)
            let rn = cronometrar { TranscriptReader.ler(path: d, limit: 1_000_000) }
            leitura = rn.0; tTudoNovo.append(rn.1)
            relerNovo = cronometrar { TranscriptReader.ler(path: d, limit: 1_000_000) }.1
        }
        let (abrirAntigo, abrirNovo, tudoAntigo, tudoNovo) = (mediana(tAbrirAntigo), mediana(tAbrirNovo), mediana(tTudoAntigo), mediana(tTudoNovo))
        let novo = leitura.mensagens
        let porIdAntigo = Dictionary(antigo.filter { $0.fromUser && !$0.naFila }.map { ($0.id, $0) }) { a, _ in a }
        let porIdNovo = Dictionary(novo.filter { $0.fromUser && !$0.naFila }.map { ($0.id, $0) }) { a, _ in a }
        var erradasAntigo = 0, sumidasAntigo = 0, erradasNovo = 0
        for e in esperadas {
            if let a = porIdAntigo[e.id] {
                if !igual(a.text, e.texto) || a.images.count != e.imagens { erradasAntigo += 1 }
            } else { erradasAntigo += 1; sumidasAntigo += 1 }
            if let n = porIdNovo[e.id], igual(n.text, e.texto), n.images.count == e.imagens, !n.text.contains("<pasted_content") {} else {
                erradasNovo += 1
                print("    novo erra na linha de posição \(e.id): esperava \(e.texto.count) letras e \(e.imagens) imagens, veio \(porIdNovo[e.id].map { "\($0.text.count) letras e \($0.images.count) imagens" } ?? "nada")")
            }
        }
        // Fala atribuída ao Hugo que o transcript não diz ser dele.
        let ids = Set(esperadas.map(\.id))
        let aMais = porIdNovo.keys.filter { !ids.contains($0) }.count
        let passos = novo.reduce(0) { $0 + $1.passos.filter { $0.tipo != .pensamento && $0.tipo != .interrupcao }.count }
        let semResultado = novo.reduce(0) { $0 + $1.passos.filter(\.rodando).count }
        let nome = (caminho as NSString).lastPathComponent.prefix(8)
        print(String(format: "  %@  %5.1f MB  Hugo mandou %3d · antigo errava %3d (%d sumidas inteiras) · novo erra %d · a mais %d · passos %d (%d sem resultado)",
                     String(nome), Double(tamanho) / 1_000_000, esperadas.count, erradasAntigo, sumidasAntigo, erradasNovo, aMais, passos, semResultado))
        print(String(format: "            abrir (30 falas): antigo %.0f ms · novo %.0f ms   |   ler tudo: antigo %.0f ms · novo %.0f ms · reler %.0f ms",
                     abrirAntigo, abrirNovo, tudoAntigo, tudoNovo, relerNovo))
        confere(aMais == 0, "fala a mais atribuída ao Hugo em \(nome)")
        return (esperadas.count, erradasAntigo, erradasNovo)
    }

    /// A mensagem que o Hugo mostrou na captura: texto colado em itens + duas imagens.
    static func casoDoHugo(_ caminho: String) {
        print("== Caso real: a mensagem de 2026-11-13 08:48 (texto colado + 2 imagens)")
        let comeco = "1. o menu lateral esquerdo tá ruim"
        let novo = TranscriptReader.ler(path: caminho, limit: 1_000_000).mensagens
        let antigo = LeitorAntigo.ler(path: caminho, limit: 1_000_000).mensagens
        guard let esperada = verdade(caminho).first(where: { $0.texto.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(comeco) }) else {
            confere(false, "a mensagem não está mais no transcript"); return
        }
        let a = antigo.first { $0.id == esperada.id }
        let n = novo.first { $0.id == esperada.id }
        print("  no transcript: \(esperada.texto.filter { !$0.isWhitespace }.count) letras (sem espaços) e \(esperada.imagens) imagens")
        print("  leitor antigo: \(a.map { "\($0.text.count) letras de texto e \($0.images.count) imagens" } ?? "nada")")
        print("  leitor novo:   \(n.map { "\($0.text.filter { !$0.isWhitespace }.count) letras (sem espaços) e \($0.images.count) imagens; começa com “\($0.text.prefix(34))”" } ?? "nada")")
        confere(a?.text.isEmpty == true && a?.images.count == 2, "o leitor antigo mostrava só as duas imagens (o defeito relatado)")
        guard let n else { confere(false, "o leitor novo não mostra a mensagem"); return }
        confere(n.text.hasPrefix(comeco), "o texto começa pelo item 1")
        confere(igual(n.text, esperada.texto), "o texto inteiro, letra por letra")
        confere(n.images.count == 2, "as duas imagens")
        confere(n.text.hasSuffix("[Image #2] [Image #3]"), "as marcas das imagens no fim, como no terminal")
        confere(!n.text.contains("pasted_content"), "sem as marcas de colagem")
        for item in ["1. ", "2. ", "3. ", "4. "] { confere(n.text.contains(item), "tem o item \(item)") }
    }
}
