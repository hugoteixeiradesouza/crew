import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// Triagem em tempo real: cada nota do Hugo, pedido dele a uma sessão e entrega de uma sessão
// passa por aqui. O modelo local da Apple (FoundationModels, sem rede) diz se é pendência DO
// HUGO, qual a ação, com quem, o trecho que fala de prazo e a urgência; a hora absoluta do prazo
// sai de `Prazos` (regra, não modelo). Sem o modelo, uma heurística simples faz o mesmo papel.
//
// Este arquivo não depende de nada do app além de `IAdoMac.disponivel` — dá para compilar com um
// `main.swift` de teste (ver o relatório do módulo).

enum Urgencia: String, Codable, Sendable, CaseIterable {
    case agora, hoje, semPressa
    var nome: String {
        switch self {
        case .agora: return "agora"
        case .hoje: return "hoje"
        case .semPressa: return "sem pressa"
        }
    }
}

/// De onde veio o texto triado.
enum OrigemTriagem: String, Sendable {
    case nota, pedido, entrega, whatsapp
}

struct Triagem: Sendable, Equatable {
    enum Tipo: String, Sendable {
        case tarefa, compromisso, esperando, agente, registro

        /// Como o modelo chama cada tipo. Leva o nome de quem usa o Mac, por isso não é o valor do caso.
        var rotulo: String {
            switch self {
            case .tarefa: return "tarefa de \(Usuario.nome)"
            case .compromisso: return "compromisso de \(Usuario.nome)"
            case .esperando: return "esperando \(Usuario.nome)"
            case .agente: return "trabalho do agente"
            case .registro: return "ideia ou registro"
            }
        }
        static let todos: [Tipo] = [.tarefa, .compromisso, .esperando, .agente, .registro]
        static var rotulos: [String] { todos.map(\.rotulo) }
        init?(rotulo: String) {
            guard let t = Tipo.todos.first(where: { $0.rotulo == rotulo }) else { return nil }
            self = t
        }
    }
    var tipo: Tipo
    var acao: String
    /// Até ~5 palavras, para o aviso na barra da ilha.
    var curta: String = ""
    var pessoa: String?
    var trechoPrazo: String?
    var urgencia: Urgencia
    var comIA: Bool
    /// O tema, em poucas palavras, sem quem disse nem quando ("alinhar a tela de estoque").
    var assunto: String? = nil
    /// Por que o modelo acha que é task, em uma frase (mostrado no "Vira task?" expandido).
    var porque: String? = nil
    /// Número (1…) da pendência aberta do contexto que esta triagem muda; nil = nova.
    var atualiza: Int? = nil

    var ehPendencia: Bool { tipo == .tarefa || tipo == .compromisso || tipo == .esperando }
}

#if canImport(FoundationModels)
@available(macOS 26, *)
@Generable
struct TriagemGerada {
    @Guide(description: "um item por combinado ou pendência de \(Usuario.nome) na conversa (no máximo 3), o mais recente primeiro; sem nenhum, um único item 'ideia ou registro'", .maximumCount(3))
    var itens: [ItemGerado]
}

@available(macOS 26, *)
@Generable
struct ItemGerado {
    @Guide(description: "o que o texto é", .anyOf(Triagem.Tipo.rotulos))
    var tipo: String
    @Guide(description: "título curto e assertivo, até 7 palavras, só com o que está na conversa: tarefa = verbo no infinitivo + objeto + pessoa; compromisso = o que é + com quem + hora; vazio se não for pendência")
    var acao: String
    @Guide(description: "o título em até 5 palavras; vazio se não for pendência")
    var acaoCurta: String
    @Guide(description: "do que se trata, até 10 palavras, tirado da conversa (o tema dito nela), sem quem disse, onde nem quando; vazio se a conversa não diz o tema")
    var assunto: String
    @Guide(description: "em uma frase curta, por que isso seria uma pendência de \(Usuario.nome), citando o que foi dito na conversa; vazio se não for pendência")
    var porque: String
    @Guide(description: "nome da pessoa ou empresa envolvida (nunca '\(Usuario.nome)' nem 'agente'); vazio se nenhuma")
    var pessoa: String
    @Guide(description: "copie as palavras exatas da conversa que dizem o prazo ou a hora valendo agora; vazio se ninguém falou de prazo")
    var trechoDoPrazo: String
    @Guide(description: "agora, hoje ou semPressa", .anyOf(["agora", "hoje", "semPressa"]))
    var urgencia: String
    @Guide(description: "número da pendência já aberta que a conversa muda ou repete (novo horário, novo prazo, título melhor); 0 se é nova ou se não há lista")
    var atualiza: Int
}

@available(macOS 26, *)
@Generable
struct FeitoGerado {
    @Guide(description: "o que foi feito no dia, em até 5 itens curtos (até 14 palavras cada), começando pelo nome do projeto", .maximumCount(5))
    var itens: [String]
}
#endif

/// O que toda consulta de triagem ao modelo recebe além do texto novo, no mesmo formato para
/// todas as origens: a conversa recente de onde ele veio (WhatsApp: os dois lados; sessão: os
/// pedidos e entregas anteriores) e as pendências já abertas daquela conversa, para o modelo
/// decidir pelo estado ATUAL do combinado e mudar uma pendência em vez de duplicar.
/// Só vive na memória durante a consulta; nada disso vai para log nem para o disco.
struct ContextoTriagem: Sendable {
    struct Fala: Sendable {
        let quem: String
        let hora: Date
        let texto: String
    }
    struct Aberta: Sendable {
        let id: UUID
        let acao: String
        let prazo: Date?
    }
    var conversa: [Fala] = []
    var abertas: [Aberta] = []
    /// O critério do Hugo, aprendido das respostas dele (títulos; nunca texto de mensagem).
    var naoEram: [String] = []
    var eram: [String] = []
    static let vazio = ContextoTriagem()

    /// Bloco do prompt: "Conversa…", "Pendências abertas…" e o critério aprendido, cortado para
    /// caber no modelo local. Na conversa, o tempo vai relativo ("há 5 min"): hora no formato
    /// HH:mm o modelo confundia com a hora do compromisso.
    func texto(agora: Date, _ hora: (Date) -> String) -> String {
        var partes: [String] = []
        if !conversa.isEmpty {
            var linhas: [String] = []
            var total = 0
            // Do fim para o começo: o mais recente sempre cabe
            for f in conversa.reversed() {
                let min = max(0, Int(agora.timeIntervalSince(f.hora) / 60))
                let quando = min < 1 ? "agora" : min < 60 ? "há \(min) min" : "há \(min / 60) h"
                let l = "(\(quando)) \(f.quem): \(TriagemIA.curto(f.texto, 280))"
                total += l.count
                if total > 1600 { break }
                linhas.insert(l, at: 0)
            }
            partes.append("Conversa (mais antiga primeiro):\n" + linhas.joined(separator: "\n"))
        }
        if !abertas.isEmpty {
            let l = abertas.prefix(8).enumerated().map { i, a in
                "\(i + 1). \(a.acao)" + (a.prazo.map { " (prazo \(hora($0)))" } ?? "")
            }
            partes.append("Pendências já abertas desta conversa:\n" + l.joined(separator: "\n"))
        }
        if !naoEram.isEmpty || !eram.isEmpty {
            var c = "Critério de \(Usuario.nome) (respostas dele a 'isso é task?'):"
            if !naoEram.isEmpty { c += "\nNÃO eram task: " + naoEram.joined(separator: "; ") }
            if !eram.isEmpty { c += "\nERAM task: " + eram.joined(separator: "; ") }
            partes.append(c)
        }
        return partes.joined(separator: "\n")
    }
}

enum TriagemIA {
    static var instrucoes: String { """
    Você faz a triagem do dia de trabalho de \(Usuario.nome) e decide se um texto traz uma pendência DE \(Usuario.nome.uppercased()).
    Classifique o texto:
    - "tarefa de \(Usuario.nome)": algo que o próprio \(Usuario.nome) precisa fazer (mandar, ligar, pagar, revisar, ver, responder, comprar…).
    - "compromisso de \(Usuario.nome)": reunião, consulta ou evento com hora.
    - "esperando \(Usuario.nome)": um agente parou e só continua quando \(Usuario.nome) aprovar, der o OK, fizer login, passar um dado.
    - "trabalho do agente": ordem que \(Usuario.nome) deu para o agente fazer, ou o relato do que o agente fez.
    - "ideia ou registro": ideia, observação, oferta opcional do agente ("quer que eu…?").
    Regras:
    - Pendência é SÓ o que \(Usuario.nome) vai parar para fazer ele mesmo, fora da conversa com os agentes, e que leva \
    uns 5 minutos ou mais: ligar, mandar algo a alguém, pagar, ir a uma reunião, revisar um documento, comprar. \
    Decidir, aprovar, dar o OK ou responder a um agente NÃO é pendência ("ideia ou registro").
    - Origem "whatsapp": mensagem que \(Usuario.nome) ENVIOU no WhatsApp; o texto começa com "Para <contato>:". \
    Só é tarefa de \(Usuario.nome) se ele promete fazer algo para alguém ("te mando amanhã", "vou ver e te falo", \
    "passo aí às 15h", "te ligo depois") — ação é o que ele prometeu, pessoa é o contato. Conversa, \
    resposta, pergunta, opinião, agradecimento, combinado já feito → "ideia ou registro". Na dúvida, registro.
    - Origem "nota": anotação do próprio \(Usuario.nome). Lembretes de fazer algo são tarefa; ideias e registros não.
    - Origem "pedido": ordem que \(Usuario.nome) deu a um agente de programação. O AGENTE vai fazer, então é trabalho do agente, \
    a menos que \(Usuario.nome) diga que ELE mesmo vai fazer algo ("depois eu ligo pro Rafa").
    - Origem "entrega": o agente terminou. Só é "esperando \(Usuario.nome)" se o agente está parado esperando \(Usuario.nome) aprovar, \
    dar o OK, decidir ou fazer algo que só ele pode. Oferta opcional ("quer que eu…?") é ideia ou registro.
    - Ação é um TÍTULO: curto (até 7 palavras), assertivo, com a pessoa e a hora quando houver. Nunca copie \
    a frase original ("nos reunirmos para falar sobre…" vira "Reunião com Guilherme às 12h").
    - Ordem ou recado que \(Usuario.nome) dá a OUTRAS pessoas ("não deixem…", "façam…", "lembra de…", "pode mandar") \
    é tarefa delas, não de \(Usuario.nome) → "ideia ou registro". Conversa casual, piada, desabafo → registro.
    - Na dúvida, "ideia ou registro": \(Usuario.nome) prefere perder uma sugestão a receber ruído.
    Contexto:
    - Se vier o "Critério de \(Usuario.nome)", siga-o: o que se parece com o que NÃO era task é "ideia ou registro".
    - Pode vir a CONVERSA recente de onde o texto saiu (os dois lados) e as pendências já abertas dela. \
    Decida pelo estado ATUAL do combinado, não por uma frase solta: se o outro sugeriu outro horário e o \
    \(Usuario.nome) aceitou ou não recusou, vale o horário novo; se desmarcaram, é "ideia ou registro".
    - Uma conversa pode ter mais de um combinado (uma reunião E um envio): um item para cada, no máximo 3.
    - Se um item muda ou repete uma pendência já aberta (o MESMO combinado), devolva o número dela em \
    "atualiza", com a ação e o prazo já atualizados. Combinado novo: atualiza 0. Nunca duas pendências \
    para o mesmo combinado; nunca use "atualiza" para trocar um combinado por outro diferente.
    - O "Texto" é a mensagem mais nova; o prazo pode estar em qualquer mensagem da conversa.
    Urgência: "agora" se é para já ou em menos de 1 hora; "hoje" se tem que ser hoje ou o agente está esperando; senão "semPressa".
    Exemplos (só mostram o FORMATO; nunca copie nomes, objetos, assuntos ou horários deles):
    nota "mandar a planilha pro Rafa até meio-dia" → tarefa de \(Usuario.nome), ação "mandar a planilha pro Rafa", pessoa "Rafa", prazo "até meio-dia", hoje
    nota "ligar pro banco amanhã" → tarefa de \(Usuario.nome), ação "ligar pro banco", pessoa "banco", prazo "amanhã", semPressa
    nota "dentista às 10h" → compromisso de \(Usuario.nome), ação "ir ao dentista", prazo "às 10h", hoje
    nota "ideia: tela de relatórios com gráfico" → ideia ou registro
    pedido "corrige o login e roda os testes" → trabalho do agente
    pedido "faz o deploy, depois eu aviso a Carla" → tarefa de \(Usuario.nome), ação "avisar a Carla", pessoa "Carla"
    whatsapp "Para Guilherme Menezes: às 12h precisamos nos reunir para falar sobre a tela de estoque" → compromisso de \(Usuario.nome), ação "Reunião com Guilherme às 12h", pessoa "Guilherme Menezes", prazo "às 12h", hoje
    whatsapp com conversa "(há 6 min) \(Usuario.nome): precisamos nos reunir às 12h / (há 4 min) Pedro: 12h não dá, pode ser 14h? / (há 3 min) \(Usuario.nome): fechado" e aberta "1. Reunião com Pedro às 12h" → compromisso de \(Usuario.nome), ação "Reunião com Pedro às 14h", pessoa "Pedro", prazo "14h", atualiza 1
    whatsapp "Para Carla: te mando o contrato amanhã cedo" → tarefa de \(Usuario.nome), ação "Mandar o contrato pra Carla", pessoa "Carla", prazo "amanhã cedo", semPressa
    entrega "Falta você aprovar o PR para eu subir." → esperando \(Usuario.nome), ação "aprovar o PR", hoje
    entrega "Pronto, tudo no ar. Quer que eu atualize o README?" → ideia ou registro
    """ }

    /// Pedido a uma sessão só vai ao modelo se o Hugo fala de algo que ELE vai fazer — o resto é
    /// ordem para o agente (e não gasta o modelo à toa).
    static let marcasDoHugo = ["depois eu", "eu vou", "vou ter que", "tenho que", "preciso ", "me lembra", "lembrar de",
                               "eu mando", "eu ligo", "eu aviso", "eu falo", "eu pago", "eu resolvo", "eu vejo"]

    static func pedidoFalaDoHugo(_ texto: String) -> Bool {
        let t = Prazos.normalizar(texto)
        return marcasDoHugo.contains { t.contains($0) }
    }

    /// Do pedido, só o pedaço em que o Hugo fala de si ("faz o deploy, depois eu aviso a Carla" →
    /// "depois eu aviso a Carla"): o modelo pequeno se confunde com a ordem ao agente junto.
    static func trechoDoHugo(_ texto: String) -> String {
        let alvo = texto.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
        var inicio: String.Index?
        for m in marcasDoHugo {
            if let r = alvo.range(of: m), inicio == nil || r.lowerBound < inicio! { inicio = r.lowerBound }
        }
        guard let i = inicio, alvo.count == texto.count else { return texto }
        let off = alvo.distance(from: alvo.startIndex, to: i)
        var resto = String(texto[texto.index(texto.startIndex, offsetBy: off)...])
        if let fim = resto.firstIndex(where: { ".!?\n".contains($0) }) { resto = String(resto[..<fim]) }
        return resto
    }

    static func triar(_ texto: String, origem: OrigemTriagem, hora: Date, contexto: ContextoTriagem = .vazio,
                      usarIA: Bool) async -> [Triagem] {
        let limpo = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpo.isEmpty else { return [] }
        if origem == .pedido && !pedidoFalaDoHugo(limpo) {
            return [Triagem(tipo: .agente, acao: "", pessoa: nil, trechoPrazo: nil, urgencia: .semPressa, comIA: false)]
        }
        let alvo = origem == .pedido ? trechoDoHugo(limpo) : limpo
        if usarIA, let t = await triarComIA(alvo, origem: origem, hora: hora, contexto: contexto) { return t }
        return [heuristica(limpo, origem: origem)]
    }

    private static func triarComIA(_ texto: String, origem: OrigemTriagem, hora: Date, contexto: ContextoTriagem) async -> [Triagem]? {
        #if canImport(FoundationModels)
        if #available(macOS 26, *), IAdoMac.disponivel {
            let f = DateFormatter()
            f.locale = Locale(identifier: "pt_BR")
            f.dateFormat = "EEEE, dd/MM/yyyy HH:mm"
            // Entrega longa: o que importa (pergunta, pendência) costuma estar no fim
            let corpo = origem == .entrega ? String(texto.suffix(900)) : String(texto.prefix(600))
            let h = DateFormatter()
            h.dateFormat = "HH:mm"
            let ctx = contexto.texto(agora: hora) { h.string(from: $0) }
            let pergunta = "Data e hora: \(f.string(from: hora))\nOrigem: \(origem.rawValue)\n"
                + (ctx.isEmpty ? "" : ctx + "\n") + "Texto: \"\(corpo)\""
            do {
                let s = LanguageModelSession(instructions: instrucoes)
                let r = try await s.respond(to: pergunta, generating: TriagemGerada.self)
                // O modelo pequeno às vezes copia os exemplos do prompt: título, assunto e prazo
                // só valem se saíram da conversa de verdade
                let fonte = Prazos.normalizar(([corpo] + contexto.conversa.map(\.texto) + contexto.abertas.map(\.acao)).joined(separator: " "))
                var usados = Set<Int>()
                let itens = r.content.itens.prefix(3).map { g -> Triagem in
                    var tipo = Triagem.Tipo(rotulo: g.tipo) ?? .registro
                    if tipo == .tarefa || tipo == .compromisso, !g.acao.isEmpty, !temPalavraEmComum(g.acao, fonte) {
                        tipo = .registro
                    }
                    var acao = g.acao.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'.")))
                    if acao.isEmpty, tipo == .compromisso || tipo == .tarefa { acao = curto(texto, 80) }
                    acao = titulo(semTelefone(acao))
                    let curta = g.acaoCurta.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'.")))
                    // Só muda uma aberta se é o MESMO combinado (mesma natureza: reunião ≠ mandar planilha)
                    var atualiza: Int?
                    if (1...max(1, contexto.abertas.count)).contains(g.atualiza), !contexto.abertas.isEmpty,
                       !usados.contains(g.atualiza),
                       mesmaNatureza(acao, contexto.abertas[g.atualiza - 1].acao) {
                        atualiza = g.atualiza
                        usados.insert(g.atualiza)
                    }
                    return Triagem(tipo: tipo, acao: acao, curta: curtaValida(curta, acao: acao), pessoa: pessoaValida(g.pessoa, em: texto),
                                   trechoPrazo: g.trechoDoPrazo.isEmpty || !fonte.contains(Prazos.normalizar(g.trechoDoPrazo)) ? nil : g.trechoDoPrazo,
                                   urgencia: Urgencia(rawValue: g.urgencia) ?? .semPressa, comIA: true,
                                   assunto: temPalavraEmComum(g.assunto, fonte) ? assuntoValido(g.assunto) : nil,
                                   porque: g.porque.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : curto(g.porque, 200),
                                   atualiza: atualiza)
                }
                return itens.isEmpty ? nil : itens
            } catch {
                return nil
            }
        }
        #endif
        return nil
    }

    /// Sem modelo: nota com prazo ou começando por verbo vira tarefa; entrega que diz que espera
    /// o Hugo vira "esperando"; pedido em que ele fala de si vira tarefa.
    static func heuristica(_ texto: String, origem: OrigemTriagem) -> Triagem {
        let t = Prazos.normalizar(texto)
        let temPrazo = Prazos.resolver(texto, desde: Date()) != nil
        switch origem {
        case .nota:
            let primeira = t.split(separator: " ").first.map(String.init) ?? ""
            let verbo = primeira.count > 3 && ["ar", "er", "ir", "or"].contains(String(primeira.suffix(2)))
            if temPrazo || verbo {
                return Triagem(tipo: .tarefa, acao: curto(texto, 80), pessoa: nil, trechoPrazo: nil,
                               urgencia: .semPressa, comIA: false)
            }
        case .entrega:
            let marcas = ["falta voce", "preciso que voce", "aguardo", "me da o ok", "me de o ok", "me avise",
                          "sua aprovacao", "voce aprovar", "quando voce", "depende de voce", "so voce"]
            if marcas.contains(where: { t.contains($0) }) {
                return Triagem(tipo: .esperando, acao: curto(texto.split(separator: "\n").last.map(String.init) ?? texto, 80),
                               pessoa: nil, trechoPrazo: nil, urgencia: .hoje, comIA: false)
            }
        case .pedido:
            return Triagem(tipo: .tarefa, acao: curto(trechoDoHugo(texto), 80), pessoa: nil, trechoPrazo: nil,
                           urgencia: .semPressa, comIA: false)
        case .whatsapp:
            // Sem modelo (ou o modelo recusou a frase): reunião com hora vira compromisso
            if t.range(of: #"\b(reuniao|reunir|reunimos|call|encontro)\b"#, options: .regularExpression) != nil,
               let hora = texto.range(of: #"\b\d{1,2}(h\d{0,2}|:\d{2})"#, options: .regularExpression) {
                let quem = contatoDoTexto(texto)
                let titulo = "Reunião" + (quem.map { " com \($0)" } ?? "") + " às \(texto[hora])"
                var assunto: String?
                if let r = texto.range(of: #"(falar sobre|sobre|para|pra) [^.?!\n]{3,80}"#, options: .regularExpression) {
                    assunto = assuntoValido(String(texto[r]).replacingOccurrences(of: #"^(falar sobre|sobre|para|pra) "#, with: "", options: .regularExpression))
                }
                return Triagem(tipo: .compromisso, acao: titulo, pessoa: quem, trechoPrazo: "às \(texto[hora])",
                               urgencia: .hoje, comIA: false, assunto: assunto)
            }
            // Só promessa clara com prazo ("te mando amanhã")
            let promessa = t.range(of: #"\b(te mando|te envio|te passo|te ligo|te falo|te aviso|te retorno|vou mandar|vou enviar|vou ligar)\b"#,
                                   options: .regularExpression) != nil
            if promessa && temPrazo {
                return Triagem(tipo: .tarefa, acao: curto(texto, 80), pessoa: nil, trechoPrazo: nil,
                               urgencia: .semPressa, comIA: false)
            }
        }
        return Triagem(tipo: .registro, acao: "", pessoa: nil, trechoPrazo: nil, urgencia: .semPressa, comIA: false)
    }

    /// Primeiro nome do contato no "Para <contato>:" da mensagem do WhatsApp (grupo não conta).
    static func contatoDoTexto(_ texto: String) -> String? {
        guard texto.hasPrefix("Para "), let fim = texto.firstIndex(of: ":") else { return nil }
        let nome = texto[texto.index(texto.startIndex, offsetBy: 5)..<fim]
        guard !nome.hasPrefix("o grupo"), !nome.hasPrefix("um contato") else { return nil }
        return nome.split(separator: " ").first.map(String.init)
    }

    /// Pessoa só se for alguém de verdade citado no texto (o modelo às vezes devolve "Hugo",
    /// "não especificado" ou o objeto da frase).
    static func pessoaValida(_ p: String, em texto: String) -> String? {
        let p = p.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'.")))
        guard !p.isEmpty, p.count <= 40, p.filter(\.isNumber).count < 7 else { return nil }
        let n = Prazos.normalizar(p)
        if n == Prazos.normalizar(Usuario.nome) || ["agente", "voce", "eu", "ninguem", "nenhum", "nenhuma"].contains(n) || n.contains("especificad") { return nil }
        let tn = Prazos.normalizar(texto)
        guard let r = tn.range(of: n) else { return nil }
        // Nome próprio (maiúscula no texto) ou alguém depois de pro/pra/com/ao/à
        let original = texto.range(of: p, options: [.caseInsensitive, .diacriticInsensitive])
        if let o = original, texto[o].first?.isUppercase == true { return p }
        let antes = tn[..<r.lowerBound].trimmingCharacters(in: .whitespaces)
        if ["pro", "pra", "com o", "com a", "com", "ao", "a", "para o", "para a"].contains(where: { antes.hasSuffix($0) }) { return p }
        return nil
    }

    /// Versão curta da ação: a do modelo se tiver até 6 palavras; senão as 5 primeiras palavras.
    static func curtaValida(_ curta: String, acao: String) -> String {
        let palavras = curta.split(separator: " ")
        if !palavras.isEmpty && palavras.count <= 6 { return curta }
        let a = acao.split(separator: " ")
        return a.prefix(5).joined(separator: " ") + (a.count > 5 ? "…" : "")
    }

    /// Contato sem nome no WhatsApp chega como telefone: tira do título ("Reunião com +55 15…").
    static func semTelefone(_ s: String) -> String {
        s.replacingOccurrences(of: #"\s*(com|pro|pra|para|a|ao)?\s*\+?\d[\d\s().-]{7,}\d"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// Mesmo tipo de combinado? Compara a primeira palavra do título ("Reunião…" × "Reunião…" sim;
    /// "Reunião…" × "Mandar…" não).
    static func mesmaNatureza(_ a: String, _ b: String) -> Bool {
        func primeira(_ s: String) -> String { Prazos.normalizar(s).split(separator: " ").first.map(String.init) ?? "" }
        return primeira(a) == primeira(b)
    }

    /// Alguma palavra de verdade (4+ letras, fora as genéricas) do texto aparece na fonte?
    static func temPalavraEmComum(_ texto: String, _ fonte: String) -> Bool {
        let genericas: Set<String> = ["reuniao", "reunir", "mandar", "enviar", "falar", "sobre", "ligar", "fazer",
                                      "para", "com", "amanha", "hoje", "depois", "conversa", "alinhar", "ver"]
        let palavras = Set(fonte.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        return Prazos.normalizar(texto).split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init).contains { $0.count >= 4 && !genericas.contains($0) && palavras.contains($0) }
    }

    static func assuntoValido(_ a: String) -> String? {
        let t = a.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'.")))
        guard t.count >= 3 else { return nil }
        return titulo(curto(t, 90))
    }

    /// Título da pendência: primeira letra maiúscula (o resto como o modelo escreveu).
    static func titulo(_ acao: String) -> String {
        guard let p = acao.first else { return acao }
        return p.uppercased() + acao.dropFirst()
    }

    static func curto(_ s: String, _ n: Int) -> String {
        let t = s.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count > n ? String(t.prefix(n - 1)) + "…" : t
    }

    /// Resumo do que foi feito no dia (o "Feito" do fechamento), a partir das entregas e commits
    /// já compactados por projeto. nil = sem modelo ou falhou (quem chama monta sem IA).
    static func feito(_ compactado: String) async -> [String]? {
        #if canImport(FoundationModels)
        if #available(macOS 26, *), IAdoMac.disponivel {
            let instr = """
            Você escreve o fechamento do dia de trabalho de \(Usuario.nome), em português, curto e direto. Recebe o que \
            os agentes entregaram e os commits, agrupados por projeto. Junte o que é do mesmo assunto, ignore \
            detalhes técnicos miúdos e não invente nada que não esteja no texto. Cada item começa com o nome do projeto.
            """
            do {
                let s = LanguageModelSession(instructions: instr)
                let r = try await s.respond(to: compactado, generating: FeitoGerado.self)
                let itens = r.content.itens.map { i -> String in
                    var t = i.trimmingCharacters(in: .whitespacesAndNewlines)
                    if t.hasPrefix("Projeto ") { t = String(t.dropFirst("Projeto ".count)) }
                    return t
                }.filter { !$0.isEmpty }
                return itens.isEmpty ? nil : itens
            } catch {
                return nil
            }
        }
        #endif
        return nil
    }
}
