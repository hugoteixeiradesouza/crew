import AppKit

// O registro de ações do comando universal: o que o Crew sabe FAZER, achável pelo nome.
// Ferramenta nova entra com uma linha em `fixas` (ou, de dentro do módulo dela, com
// `AcoesComando.registrar(...)` no `iniciar()`). Quase tudo é um endereço crew:// que o módulo
// já entende (`Modulo.executar`): o comando não ganha caminho próprio para dentro de ninguém.
//
// Regra do Crew: nada destrutivo por aqui. Ação que apaga, move ou encerra não entra na lista.

@MainActor
struct AcaoComando: Identifiable {
    let id: String
    let titulo: String
    let detalhe: String
    /// SF Symbol.
    let icone: String
    /// Módulo dono (a ação some se ele estiver desligado); nil = do próprio Crew.
    let modulo: String?
    /// Outras palavras que acham a ação ("print", "screenshot").
    let palavras: [String]
    let executar: @MainActor () -> Void

    /// Ação que é um endereço crew:// (o caso comum).
    static func endereco(_ titulo: String, _ endereco: String, icone: String, detalhe: String,
                         palavras: [String] = []) -> AcaoComando {
        let url = URL(string: endereco)
        return AcaoComando(id: endereco, titulo: titulo, detalhe: detalhe, icone: icone,
                           modulo: url?.host().flatMap { ["ilha", "central"].contains($0) ? nil : $0 },
                           palavras: palavras) {
            if let url { Automacao.abrir(url) }
        }
    }
}

/// Ação que leva o texto digitado depois de uma palavra: "nota comprar pão".
@MainActor
struct AcaoComTexto {
    let id: String
    let gatilhos: [String]
    let modulo: String
    let icone: String
    let titulo: (String) -> String
    let detalhe: String
    /// Endereço crew:// sem os parâmetros; o texto vai em `parametro`.
    let endereco: String
    let parametro: String

    func url(_ texto: String) -> URL? {
        var c = URLComponents(string: endereco)
        c?.queryItems = [URLQueryItem(name: parametro, value: texto)]
        return c?.url
    }
}

@MainActor
enum AcoesComando {
    private static var extras: [AcaoComando] = []

    /// Um módulo acrescenta ações dele (chame no `iniciar()`; repetir o id substitui).
    static func registrar(_ acoes: [AcaoComando]) {
        let novos = Set(acoes.map(\.id))
        extras.removeAll { novos.contains($0.id) }
        extras += acoes
    }

    /// As ações que valem agora: as dos módulos ligados e as do próprio Crew.
    static var disponiveis: [AcaoComando] {
        (fixas + extras).filter { a in a.modulo.map { Registro.shared.estaLigado($0) } ?? true }
    }

    static var comTexto: [AcaoComTexto] {
        textuais.filter { Registro.shared.estaLigado($0.modulo) }
    }

    private static let fixas: [AcaoComando] = [
        // Captura
        .endereco("Capturar área", "crew://captura/area", icone: "rectangle.dashed",
                  detalhe: "Escolher um pedaço da tela", palavras: ["print", "screenshot", "captura de tela", "recorte"]),
        .endereco("Capturar janela", "crew://captura/janela", icone: "macwindow",
                  detalhe: "Uma janela inteira", palavras: ["print", "screenshot", "captura de tela"]),
        .endereco("Capturar tela inteira", "crew://captura/tela", icone: "display",
                  detalhe: "Tudo o que está na tela", palavras: ["print", "screenshot", "captura de tela"]),
        .endereco("Copiar texto da tela", "crew://captura/texto", icone: "text.viewfinder",
                  detalhe: "Ler o texto de um pedaço da tela e copiar", palavras: ["ocr", "capturar texto", "ler tela"]),
        // Voz
        .endereco("Ditar", "crew://voz/ditar", icone: "mic",
                  detalhe: "Falar em vez de digitar; chamar de novo encerra",palavras: ["ditado", "falar", "microfone", "voz"]),
        .endereco("Parar a leitura em voz alta", "crew://voz/parar", icone: "speaker.slash",
                  detalhe: "Cala o que estiver sendo lido ou ditado", palavras: ["calar", "silencio", "parar de falar"]),
        // Tasks (o módulo se chama "diario" por dentro)
        .endereco("Abrir as tarefas", "crew://diario/expandir", icone: "checklist",
                  detalhe: "Pendências do dia, na ilha", palavras: ["tasks", "pendencias", "lista", "diario"]),
        .endereco("Resumir o dia", "crew://diario/resumir", icone: "text.badge.checkmark",
                  detalhe: "Gera o resumo de hoje e abre", palavras: ["resumo", "fechamento", "diario"]),
        // Sistema
        .endereco("Monitor de atividade", "crew://sistema/monitor", icone: "gauge.with.dots.needle.33percent",
                  detalhe: "Processador, memória e o que está pesando", palavras: ["cpu", "memoria", "processos", "lento"]),
        // O Crew
        .endereco("Abrir a ilha", "crew://ilha", icone: "rectangle.topthird.inset.filled",
                  detalhe: "A visão geral, no notch", palavras: ["notch", "homie"]),
        AcaoComando(id: "crew:app", titulo: "Abrir o Crew", detalhe: "A janela das sessões", icone: "macwindow",
                    modulo: nil, palavras: ["sessoes", "janela", "claude code"]) { Central.abrirSessoes() },
        AcaoComando(id: "crew:nova-sessao", titulo: "Nova sessão", detalhe: "Começar um pedido ao Claude Code",
                    icone: "plus.bubble", modulo: nil, palavras: ["claude", "novo pedido", "sessao nova"]) {
            Central.abrirSessoes()
            // A janela pode estar nascendo agora: o pedido chega depois de ela montar.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                NotificationCenter.default.post(name: .novaSessao, object: nil)
            }
        },
        AcaoComando(id: "crew:ajustes", titulo: "Ajustes do Crew", detalhe: "Todas as páginas de ajuste",
                    icone: "gearshape", modulo: nil, palavras: ["configuracoes", "preferencias", "central"]) { Central.abrir() },
    ]

    private static let textuais: [AcaoComTexto] = [
        AcaoComTexto(id: "crew://diario/nota", gatilhos: ["nota", "anotar", "anota", "lembrar", "lembrete"],
                     modulo: "diario", icone: "square.and.pencil",
                     titulo: { "Anotar: \($0)" }, detalhe: "Vai para as tarefas do dia",
                     endereco: "crew://diario/nota", parametro: "texto"),
        AcaoComTexto(id: "crew://voz/falar", gatilhos: ["falar", "fala", "ler em voz alta", "diga"],
                     modulo: "voz", icone: "speaker.wave.2",
                     titulo: { "Falar: \($0)" }, detalhe: "Lê em voz alta neste Mac",
                     endereco: "crew://voz/falar", parametro: "texto"),
    ]
}
