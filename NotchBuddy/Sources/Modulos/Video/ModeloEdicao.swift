import Foundation

// O que o Crew escreve num projeto de vídeo nascido de uma gravação e que muda de gravação para
// gravação: os fatos dela (`gravacao.ts`), a cara do vídeo (`tema.ts`), o roteiro de partida
// (`roteiro.ts`), o guia da sessão que edita (`CLAUDE.md`) e o primeiro pedido dessa sessão.
// As peças que não mudam estão em `KitEdicao.swift`.

enum ModeloEdicao {
    /// Nomes dentro da `public/` do projeto.
    static let arquivoMouse = "mouse.json"
    static let arquivoLegendas = "legendas.json"
    /// Rastro vazio: o kit importa o arquivo sempre, com ou sem mouse gravado.
    static let mouseVazio = "{\"cliques\": [], \"mouse\": []}\n"

    /// De que projeto do Hugo é o vídeo (a sessão lê essa pasta, sem escrever nela).
    struct Contexto: Equatable {
        let nome: String
        let caminho: String
        /// Cor do projeto no Crew ("#RRGGBB"): só o ponto de partida do tema.
        let cor: String
    }

    /// O que aconteceu com as legendas, para o guia dizer a verdade à sessão.
    enum Fala: Equatable {
        case transcrita(frases: Int, idioma: String)
        case semFala
        case indisponivel(String)
    }

    /// Texto dentro de aspas duplas de TypeScript.
    private static func ts(_ texto: String) -> String {
        var s = texto.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        s = s.replacingOccurrences(of: "\n", with: " ")
        return "\"\(s)\""
    }

    static func gravacaoTS(arquivo: String, largura: Int, altura: Int, fps: Int, segundos: Double) -> String {
        """
        // Escrito pelo Crew: os fatos da gravação. Não edite (a edição mora em roteiro.ts e tema.ts).
        export const gravacao = {
          arquivo: \(ts(arquivo)),
          largura: \(largura),
          altura: \(altura),
          fps: \(fps),
          duracao: \(String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), segundos)),
        } as const;

        """
    }

    static func temaTS(projeto: String, cor: String) -> String {
        """
        // A cara do vídeo. Estes valores são só um ponto de partida neutro: troque pela direção
        // visual que você propôs para este projeto (cores, fontes, nome, brilho, raio). É daqui que
        // todos os blocos do kit tiram cor, tipografia e forma.
        export const tema = {
          /** Nome do projeto, como aparece no selo. */
          projeto: \(ts(projeto)),
          /** Cor de destaque (a principal da marca). */
          cor: \(ts(cor)),
          /** Segunda cor do brilho de fundo (pode ser a mesma, ou uma vizinha da marca). */
          cor2: "#7C5CFF",
          /** De onde vem o brilho do fundo: "baixo", "cima", "cantos" ou "nenhum". */
          brilho: "cantos" as "baixo" | "cima" | "cantos" | "nenhum",
          /** Fundo e superfícies. */
          fundo: "#0A0B0F",
          superficie: "#14161C",
          /** Texto principal e texto de apoio. */
          tinta: "#F4F5F7",
          apagado: "#9A9FAB",
          /** Tipografia: títulos, texto e números/código. */
          fonteTitulo: `"SF Pro Display", -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif`,
          fonteTexto: `"SF Pro Text", -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif`,
          fonteMono: `"SF Mono", ui-monospace, Menlo, monospace`,
          /** Raio dos cantos da moldura da gravação (em pixels de um vídeo de 1080 de lado menor). */
          raio: 22,
        };

        /** "#RRGGBB" com transparência: comAlfa(tema.cor, 0.3). */
        export const comAlfa = (hex: string, alfa: number): string => {
          const h = hex.replace("#", "");
          const c = h.length === 3 ? h.split("").map((x) => x + x).join("") : h;
          const n = parseInt(c.slice(0, 6), 16);
          return `rgba(${(n >> 16) & 255}, ${(n >> 8) & 255}, ${n & 255}, ${alfa})`;
        };

        """
    }

    /// Roteiro de partida: a gravação inteira num trecho só, com abertura e encerramento. Já
    /// renderiza; a sessão troca pelos cortes e capítulos de verdade.
    static func roteiroTS(titulo: String, autor: String, segundos: Double) -> String {
        let fim = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), max(0.1, (segundos * 100).rounded(.down) / 100))
        let assinatura = autor.isEmpty ? "" : "\n  autor: \(ts(autor)),\n  faixa: { nome: \(ts(autor)) },"
        return """
        import type { Roteiro } from "./kit/Edicao";

        // O roteiro da edição: é aqui que o vídeo é montado. Tempos em segundos DA GRAVAÇÃO.
        // Este é só o ponto de partida (a gravação inteira, sem corte): troque pelo roteiro de
        // verdade. Campos e exemplos no CLAUDE.md desta pasta.
        export const roteiro: Roteiro = {
          titulo: \(ts(titulo)),\(assinatura)
          trechos: [{ de: 0, ate: \(fim) }],
          encerramento: { titulo: \(ts(titulo)) },
        };

        """
    }

    /// O primeiro pedido da sessão que edita: ela assiste, lê o projeto e propõe antes de mexer.
    static func pedidoInicial(contexto: Contexto?) -> String {
        let projeto = contexto.map { " e leia o projeto \($0.nome) em \($0.caminho) (somente leitura)" } ?? ""
        return "Leia o CLAUDE.md desta pasta e siga o passo a passo dele até a proposta: assista à gravação\(projeto), monte o roteiro de cortes e me proponha a edição em 5 linhas. Não edite nada antes de eu responder."
    }

    /// Instrução fixa da sessão quando há projeto: ler, nunca escrever nele.
    static func instrucao(contexto: Contexto) -> String {
        "Esta sessão edita um vídeo no projeto de vídeo da pasta atual. A pasta \(contexto.caminho) é o projeto \(contexto.nome) de \(Usuario.nome) e está aqui só para consulta: leia o que precisar dela, mas nunca crie, altere, mova nem apague nada lá (nem por comandos de terminal, nem git). Tudo o que você escreve fica na pasta atual."
    }

    static func guia(arquivo: String, largura: Int, altura: Int, fps: Int, segundos: Double, comMouse: Bool,
                     trilhasJuntadas: Int, fala: Fala, contexto: Contexto?, nomeDoProjetoDeVideo: String) -> String {
        let s = Int(segundos.rounded())
        let som = trilhasJuntadas > 1
            ? " O som do Mac e o microfone foram gravados separados e aqui já estão juntos numa trilha só."
            : ""
        let mouse = comMouse
            ? "`public/\(arquivoMouse)` tem onde o ponteiro estava e onde \(Usuario.nome) clicou (nenhuma tecla): o zoom e o destaque do cursor saem dele."
            : "Esta gravação veio **sem rastro do mouse** (`public/\(arquivoMouse)` está vazio): não há zoom automático nem destaque de cursor. Se precisar de zoom, passe `trechos` à mão ao `<ZoomNosCliques>` (formato em `kit/ZoomNosCliques.tsx`), com os pontos que você viu nos quadros."
        let legendas: String
        switch fala {
        case .transcrita(let n, let idioma):
            legendas = "`public/\(arquivoLegendas)` tem a fala transcrita neste Mac (\(n) \(n == 1 ? "frase" : "frases"), \(idioma)), com o tempo de cada palavra. **Leia o arquivo inteiro: é o jeito mais rápido de saber o que \(Usuario.nome) diz e quando.** A transcrição erra nome próprio e termo técnico: corrija o `texto` (das frases e das palavras) com o vocabulário do projeto, sem mexer nos tempos."
        case .semFala:
            legendas = "`public/\(arquivoLegendas)` está vazio: a gravação não tem fala (ou não tem som). O vídeo fica sem legenda; se \(Usuario.nome) quiser texto na tela, escreva as frases à mão no mesmo formato (abaixo)."
        case .indisponivel(let motivo):
            legendas = "`public/\(arquivoLegendas)` está vazio: a fala **não foi transcrita** (\(motivo)). Edite sem legenda e diga isso a \(Usuario.nome) na proposta — ele resolve em Ajustes do Crew › Vídeo e manda refazer as legendas no projeto, sem perder a edição."
        }
        let doProjeto: String
        if let c = contexto {
            doProjeto = """

            ## O projeto de onde este vídeo vem: \(c.nome)

            Pasta: `\(c.caminho)` — esta sessão enxerga essa pasta **só para ler**. Nunca crie, altere nem
            apague nada lá (nem por terminal, nem git): tudo o que você escreve fica aqui, no projeto de vídeo.

            O vídeo tem que falar a língua desse projeto. Antes de propor qualquer coisa, leia (o que existir):

            1. `README*` e `CLAUDE.md` da raiz: o que o produto é, para quem, e como ele se chama em cada lugar.
            2. A identidade visual, nesta ordem de confiança: tokens de design e tema (`tailwind.config.*`,
               `theme.*`, `tokens.*`, variáveis em `:root` de `globals.css`/`app.css`, `DesignSystem`/`Tema`/`Colors`
               em Swift ou Kotlin), depois logo e ícones (`public/`, `assets/`, `*.svg`, `AppIcon`), depois as
               fontes (`@font-face`, `next/font`, arquivos `.woff2`/`.ttf`/`.otf`).
            3. `git log --oneline -30` (rode com `git -C \(c.caminho) log …`): o que mudou há pouco costuma ser o
               assunto do vídeo.
            4. Se a gravação mostra uma tela específica, ache o código dela para usar os nomes certos.

            Depois **transforme o que achou numa direção visual** e passe para `tema.ts`: `projeto` (o nome
            como o produto se apresenta), `cor` (a cor principal da marca), `cor2`, `fundo`/`superficie`/`tinta`
            coerentes com o produto (produto claro pode pedir vídeo claro), `brilho`, `raio` (produto de
            cantos retos pede moldura de cantos retos) e as fontes. Fonte que não é do sistema: copie o arquivo para
            `public/` e carregue com `FontFace` + `delayRender()`/`continueRender()` num arquivo `fontes.ts`
            importado em `Raiz.tsx`. Logo: copie para `public/` e use `<Img src={staticFile("logo.svg")} />`
            na abertura e no encerramento. A cor que veio em `tema.ts` (\(c.cor)) é só a cor do projeto na
            lista do Crew, não a marca: troque pela de verdade.

            """
        } else {
            doProjeto = """

            ## Sem projeto de origem

            \(Usuario.nome) não ligou este vídeo a nenhum projeto. Tire o assunto, os nomes e o tom da própria
            gravação (quadros e fala) e pergunte a ele só o que não der para ver.

            """
        }
        let passoProjeto = contexto == nil
            ? "Sem projeto de origem: entenda pelo que a gravação mostra."
            : "Leia o projeto (seção acima) e ajuste `tema.ts`."
        return """
        # Edição de uma gravação de tela — \(nomeDoProjetoDeVideo)

        Este projeto nasceu de uma gravação de tela de \(Usuario.nome), feita pelo Crew. O trabalho desta sessão é
        transformá-la num **vídeo de criador bem editado**, com uma direção visual própria, tirada do
        projeto de onde o vídeo vem. Regras gerais do Remotion: `../../CLAUDE.md` (leia também).

        - Gravação: `public/\(arquivo)` — \(largura) × \(altura), \(s / 60) min \(s % 60) s, \(fps) fps.\(som) **Nunca altere nem apague esse arquivo**: a edição é toda no código.
        - \(mouse)
        - \(legendas)
        \(doProjeto)
        ## O que já está pronto aqui

        | Arquivo | O que é | Você mexe? |
        |---|---|---|
        | `roteiro.ts` | **A edição**: título, gancho, blocos (demonstração, fala, dados, diagrama), capítulos, encerramento | sim, é o principal |
        | `tema.ts` | Cores, fontes, nome do projeto, brilho do fundo, raio | sim: é a direção visual |
        | `Raiz.tsx` | As composições: `Video` (16:9), `Vertical` (9:16) e `Gravacao` (crua) | para acrescentar formato ou cena |
        | `kit/` | Os blocos e a montagem | à vontade: são seus para adaptar |
        | `gravacao.ts` | Os fatos da gravação (tamanho, duração) | não |

        O projeto **já renderiza** como está (a gravação inteira emoldurada, com abertura e encerramento
        neutros). Isso é só o chão: o vídeo de verdade nasce do que você decidir abaixo.

        ## O que se espera: uma direção visual própria

        O gênero é o vídeo de criador que grava a tela fazendo algo e sai bem editado: **a tela é a
        protagonista, a pessoa está presente, cartelas e gráficos explicam o que está sendo mostrado,
        poucos cortes e transições limpas.** Dentro disso, **não existe layout obrigatório**. O kit é um
        repertório de blocos neutros, não um modelo para repetir: para cada vídeo, proponha uma direção
        visual que saia da identidade do projeto que você leu (cores, tipografia, tom de voz, formas) e
        do que \(Usuario.nome) pediu, e componha com liberdade — troque posições, tamanhos, o fundo, o jeito de
        entrar, crie um bloco que não existe. Dois vídeos de projetos diferentes não devem parecer o
        mesmo modelo com outra cor. Não copie a aparência de um vídeo de referência: referência serve
        para entender o tipo de vídeo, não para reproduzir o estilo.

        ## Passo a passo (siga nesta ordem)

        1. **Assista.** Você não enxerga o vídeo sozinho: tire quadros e olhe as imagens.
           - Um quadro: `../../node_modules/.bin/remotion ffmpeg -v error -ss 12 -i public/\(arquivo) -frames:v 1 -vf scale=1280:-2 -y /tmp/q-12.png`
           - A gravação inteira, um quadro a cada 5 s (aumente o passo se passar de 40 quadros):
             `mkdir -p /tmp/quadros && for t in $(seq 0 5 \(max(0, s - 1))); do ../../node_modules/.bin/remotion ffmpeg -v error -ss $t -i public/\(arquivo) -frames:v 1 -vf scale=960:-2 -y /tmp/quadros/$(printf %04d $t).png; done`
           - Onde há silêncio (candidato a corte): `../../node_modules/.bin/remotion ffmpeg -i public/\(arquivo) -af silencedetect=noise=-35dB:d=1.2 -f null - 2>&1 | grep silence_`
           - Leia `public/\(arquivoLegendas)` (o que é dito, e quando) e os cliques em `public/\(arquivoMouse)`.
           Anote: o que acontece em cada intervalo, onde ele erra ou espera, qual é o melhor momento, e
           se a bolha da câmera aparece na tela (onde, e de que tamanho).
        2. **Entenda o projeto.** \(passoProjeto)
        3. **Monte o roteiro** (no papel, antes do código): que trechos ficam (de–até em segundos da
           gravação), o que sai (espera, erro, repetição, silêncio), o que acelera, os capítulos (2 a 5,
           nomes de 2 a 4 palavras), o gancho (os 2 a 4 s mais fortes, em geral o resultado final), o
           título, e **onde um gráfico explica melhor que a tela** (um número, um antes e depois, o
           caminho de um dado, as partes de um todo).
        4. **Proponha a \(Usuario.nome) em 5 linhas** e espere a resposta: (1) título e gancho; (2) capítulos com os
           tempos e os blocos de cada um; (3) o que sai e quanto o vídeo encurta; (4) a direção visual
           deste vídeo — cores, fonte, fundo e o que a faz ser deste projeto; (5) formatos, duração final e,
           se for o caso, legenda. Sem código nessa mensagem.
        5. **Edite**: `tema.ts`, depois `roteiro.ts`; depois adapte ou crie blocos no `kit/`.
        6. **Renderize a prévia e confira quadros.** Um quadro por cena, no mínimo, nos dois formatos:
           `cd ../.. && ./node_modules/.bin/remotion still videos/\(nomeDoProjetoDeVideo)/index.ts Video /tmp/v-120.png --frame=120 --public-dir=videos/\(nomeDoProjetoDeVideo)/public`
           Olhe cada imagem com olho crítico (lista "Conferir" abaixo) e corrija antes de seguir.
        7. **Entregue**: renderize com a ferramenta `video_renderizar` do MCP `crew` (projeto
           `\(nomeDoProjetoDeVideo)`, composição `Video`; depois `Vertical` se \(Usuario.nome) quiser) e diga em 3 linhas o
           que o vídeo tem, a duração e o que ficou de fora.

        ## O repertório de blocos

        Cada item de `trechos` no roteiro é um bloco. Tempos sempre em **segundos da gravação**; o que não
        está em nenhum bloco foi cortado.

        ```ts
        export const roteiro: Roteiro = {
          titulo: "um vídeo de lançamento sem abrir o editor",   // promessa concreta, 4 a 9 palavras
          destaque: "sem editor",                 // palavras do título na cor do projeto
          subtitulo: "Do pedido ao arquivo pronto, em uma gravação",
          autor: "\(Usuario.nomeCompleto)",
          faixa: { nome: "\(Usuario.nomeCompleto)", contexto: "Montando o vídeo de lançamento" }, // na 1ª demonstração
          gancho: { de: 16.3, ate: 19.6 },        // pedaço forte mostrado ANTES do título
          camera: { recorte: { x: 0.9, y: 0.86, lado: 0.11 } },   // ver "A câmera"
          legendas: false,                        // sem dizer: só no vertical
          trechos: [
            // fala: a pessoa em destaque e o palco de gráficos ao lado; a voz é a da gravação
            { fala: { de: 0, ate: 4.3, titulo: "do pedido ao vídeo pronto", destaque: "pronto",
                      linha: "pedido + projeto = vídeo", rotulo: "três passos",
                      miniaturas: [{ quadro: 4 }, { quadro: 10 }, { imagem: "capa.png" }] } },
            // demonstração: a gravação emoldurada; capitulo = cartela + etiqueta
            { de: 4.3, ate: 7.6, capitulo: "Abrir os projetos" },
            { de: 7.6, ate: 11.7, capitulo: "Descrever o vídeo",
              destaques: [{ de: 8.6, ate: 11.6, x: 0.29, y: 0.46, largura: 0.42, altura: 0.1, rotulo: "o pedido, em uma frase" }] },
            { de: 21, ate: 48, velocidade: 6 },   // espera acelerada (sem som e sem legenda)
            // diagrama: a gravação recua e cartões ligados por linhas explicam o caminho
            { diagrama: { de: 11.7, ate: 16.1, cartoes: [{ titulo: "Pedido", texto: "o que o vídeo mostra" },
                          { titulo: "Projeto", texto: "cores, fontes e nomes" }, { titulo: "Cenas" }] } },
            { de: 48, ate: 61.5, capitulo: "Renderizar", zoom: 1.8 },   // zoom: false desliga; número = escala
            // dados: números grandes e grade de miniaturas (de/ate = com a voz; senão, duracao)
            { dados: { duracao: 4.5, numeros: [{ valor: "1", texto: "gravação" }, { valor: "0", texto: "cortes à mão" }],
                       itens: [{ quadro: 2, rotulo: "início", detalhe: "0:02" }, { quadro: 21, rotulo: "pronto", detalhe: "0:21" }] } },
          ],
          encerramento: { titulo: "pronto para publicar", destaque: "publicar", linha: "…", qr: "qr.png", chamada: "o projeto" },
        };
        ```

        Os blocos e as peças (em `kit/`, todos com as props comentadas no próprio arquivo):

        - **Demonstração** — `Moldura` + `ZoomNosCliques` (aproxima em cada clique; no vertical acompanha o
          ponteiro) + `DestaqueCursor` (halo e anel no clique) + `DestaqueMoldura` (contorno com rótulo em
          volta de uma parte da tela: o jeito mais limpo de apontar algo) + etiqueta de capítulo + câmera
          em miniatura. Prefira destaque por moldura e zoom leve a zoom forte.
        - **Fala** — `CartaoCamera` grande e o palco de gráficos (`TituloCurto` com palavra em destaque,
          `PilhaDeMiniaturas`, `CartaoAviso`, `Rotulo`). Sem câmera, o palco ocupa o quadro e a voz continua:
          serve para explicar um conceito sobre a narração. `lado` troca a câmera de lado.
        - **Dados** — `GradeDeDados`: números na cor do projeto e miniaturas com legenda (colunas à escolha).
        - **Diagrama** — `Diagrama`: cartões em fila ligados por linhas com um ponto viajando, enquanto a
          gravação recua. Para explicar o que a demonstração faz por dentro.
        - **Cartelas** — `CartelaTitulo`, `CartelaCapitulo`, `CartelaEncerramento` (QR code opcional).
        - **Sempre por baixo** — `Fundo` (cor e brilho vêm do tema; `brilho: "nenhum"` dá fundo liso).
        - **Opcionais** — `Legendas` (palavra dita acende), `FaixaInferior` (nome e contexto), `Andamento`.
        - `layout.ts` (onde cada coisa mora em paisagem e em vertical) e `movimento.ts` (durações e curvas).

        `Edicao.tsx` enfileira os blocos do roteiro; é ponto de partida. Composição que o roteiro não
        descreve (tela dividida, câmera em outro lugar, um gráfico só deste vídeo): edite `Edicao.tsx` e
        `layout.ts`, ou monte a cena à mão em `<Sequence>` com as peças.

        Miniatura: `{ quadro: 12 }` é um quadro da própria gravação; `{ imagem: "x.png" }` é um arquivo em
        `public/` (capturas e imagens do projeto de origem: copie para cá, não aponte para fora).

        QR code (se \(Usuario.nome) quiser uma chamada no fim), gerado neste Mac:
        `swift -e 'import AppKit; import CoreImage.CIFilterBuiltins; let f = CIFilter.qrCodeGenerator(); f.message = Data("https://exemplo.com".utf8); let r = NSBitmapImageRep(ciImage: f.outputImage!.transformed(by: .init(scaleX: 16, y: 16))); try! r.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "public/qr.png"))'`

        ## A câmera

        Hoje o Crew não grava a câmera num arquivo à parte: quando \(Usuario.nome) liga a **bolha da câmera**, ela
        é uma janela redonda na tela dele e já está **dentro da gravação**. Veja nos quadros se ela aparece.

        - **Aparece**: na demonstração ela já faz o papel de câmera em miniatura — não cubra (mude a faixa
          inferior de lado, desligue o zoom que a corta: `zoom: false`). Para os blocos de fala, use
          `camera: { recorte: { x, y, lado } }` no roteiro: centro da bolha e o lado dela, em frações da
          largura (x, lado) e da altura (y) do quadro gravado, medidos num quadro. A imagem é pequena:
          fica boa em cartão médio, não em tela cheia. Se \(Usuario.nome) arrastou a bolha no meio da gravação, o
          recorte vale só até ali.
        - **Não aparece**: faça os blocos de fala sem câmera (o palco ocupa o quadro, a voz continua).
        - **Há um vídeo da câmera à parte** (\(Usuario.nome) pôs um arquivo em `public/`): `camera: { arquivo:
          "camera.mp4", atraso: 0 }` — `atraso` é quantos segundos depois da gravação da tela ele começou;
          acerte comparando um gesto ou uma palavra nos dois. Com arquivo, a demonstração ganha a
          miniatura no canto (posição em `layout.ts`).

        ## Princípios de design (valem para tudo que você compuser)

        - **Poucas cores, uma só que grita.** A cor de destaque do tema aparece pouco: palavra-chave,
          número, fio, contorno. O resto é texto, texto apagado e superfícies.
        - **Pouco texto por tela**: 2 a 6 palavras num título, uma ideia por cartela. Se precisa de frase
          longa, é assunto para a voz, não para a tela.
        - **Hierarquia em três níveis** (título, apoio, rótulo) por tamanho e peso; não crie um quarto no meio.
        - **Tudo em múltiplos de `u`** (`layoutDe(width, height).u`): é o que faz o mesmo bloco servir a 16:9
          e 9:16. Nunca escreva 1920, 1080 ou pixel fixo dentro de componente.
        - **Alinhe numa grade só** e deixe ar: metade vazia numa cartela é desenho, não defeito.
        - **Movimento com uma mão só** (`kit/movimento.ts`): as mesmas três durações e curvas no vídeo
          inteiro; entradas suaves (desfoque + escala + deslize curtos), texto em sequência, nada de quique
          ou giro. Se o projeto pede outro caráter (mais seco, mais elástico), mude lá, uma vez.
        - **A tela é a protagonista**: nada cobre o que ele está mostrando; gráfico entra entre trechos
          ou ao lado, não por cima do ponto de atenção.
        - **Ritmo**: gancho de 2 a 4 s, título em até 4 s, cartela de capítulo curta; demonstração pode
          correr inteira, sem picotar — corte só espera, erro e repetição. A cada 20 a 40 s, algo novo na
          tela (destaque, gráfico, capítulo).
        - **Texto do vídeo em português**, com os nomes que o projeto usa no README e na interface.

        ## Formatos

        `Video` (1920 × 1080) e `Vertical` (1080 × 1920) saem do mesmo roteiro: no vertical a moldura vira
        4:5 e a câmera acompanha o ponteiro, o capítulo vira título em cima, a fala empilha câmera e palco, e
        a legenda liga sozinha. Confira sempre os dois. Quadrado (1080 × 1080): acrescente uma
        `<Composition>` em `Raiz.tsx` com o mesmo `Editado`; o `layout.ts` trata como paisagem.

        ## Os dados

        `public/\(arquivoMouse)` — `t` em segundos do vídeo; `x` e `y` de 0 a 1 dentro do quadro gravado, a
        partir do canto de cima à esquerda (fora de 0–1 = ponteiro fora do que foi gravado):

        ```json
        { "alvo": "tela", "quadro": {"x": 0, "y": 0, "largura": 1512, "altura": 982}, "cursorNoVideo": true,
          "duracao": 42.31, "cliques": [{"t": 3.21, "x": 0.4312, "y": 0.2207, "botao": "esquerdo"}],
          "mouse": [[0.000, 0.5000, 0.5000], [0.033, 0.5012, 0.4991]] }
        ```

        Os tempos podem ter um desvio de décimos de segundo em relação à imagem: confira um clique num
        quadro antes de confiar. Na gravação de janela, `quadro` é onde a janela estava ao começar.

        `public/\(arquivoLegendas)` — a fala, com o tempo de cada palavra (serve para legendar e, mesmo sem
        legenda no vídeo, para cortar no silêncio e saber o que é dito em cada trecho):

        ```json
        { "idioma": "pt-BR", "frases": [ { "inicio": 0.0, "fim": 4.14, "texto": "Hoje eu vou mostrar o Crew.",
          "palavras": [ { "t": 0.0, "fim": 0.24, "texto": "Hoje" }, { "t": 0.24, "fim": 0.5, "texto": "eu" } ] } ] }
        ```

        Corte no silêncio, nunca no meio de uma palavra: deixe 0,15 s de folga antes da primeira palavra e
        depois da última. A duração do vídeo sai do roteiro sozinha; não escreva `durationInFrames` à mão.

        ## Outras receitas

        - **Borrar dado sensível** (senha, token, e-mail de cliente à vista): um `<div>` absoluto dentro do
          `<ZoomNosCliques>` com `backdropFilter: "blur(18px)"`, em % do quadro gravado — e avise \(Usuario.nome).
        - **Trilha**: `<Audio src={staticFile("trilha.mp3")} volume={0.12} />` em `Edicao.tsx`, baixa o bastante
          para não brigar com a voz. Só com arquivo que \(Usuario.nome) forneceu (direito de uso).
        - **Fonte do projeto**: copie o arquivo para `public/` e carregue com `FontFace` +
          `delayRender()`/`continueRender()` num `fontes.ts` importado em `Raiz.tsx`.

        ## Conferir (antes de dizer que ficou pronto)

        Olhe os quadros e responda sim para tudo: o vídeo tem a cara **deste** projeto (e não a de um
        modelo)? O título cabe em até duas linhas (três no vertical)? Nada está cortado pela borda ou em
        cima da bolha da câmera? Os destaques contornam exatamente o que foi dito? As cores são as do
        projeto, e só uma grita? Algum nome escrito errado? O primeiro e o último quadro de cada cena
        estão limpos (sem texto pela metade)? Renderizou sem erro do começo ao fim, nos dois formatos?

        """
    }
}
