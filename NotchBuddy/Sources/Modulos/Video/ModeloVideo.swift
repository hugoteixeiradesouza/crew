import Foundation

// Os textos que o Crew escreve na pasta do motor de vídeo: o pacote do Node, o guia que as
// sessões leem e o vídeo de partida de cada projeto novo.

enum ModeloVideo {
    static func pacote(versao: String) -> String {
        """
        {
          "name": "crew-motor-remotion",
          "private": true,
          "version": "1.0.0",
          "description": "Motor de vídeo do Crew — gerado pelo app. Não edite: o Crew regrava.",
          "dependencies": {
            "@remotion/cli": "\(versao)",
            "remotion": "\(versao)",
            "react": "19.2.0",
            "react-dom": "19.2.0"
          },
          "devDependencies": {
            "typescript": "5.9.3",
            "@types/react": "19.2.2"
          }
        }

        """
    }

    static let tsconfig = """
    {
      "compilerOptions": {
        "target": "ES2022",
        "module": "ESNext",
        "moduleResolution": "Bundler",
        "jsx": "react-jsx",
        "strict": true,
        "noEmit": true,
        "skipLibCheck": true,
        "esModuleInterop": true,
        "resolveJsonModule": true
      },
      "include": ["videos"]
    }

    """

    static func guia(saidas: String) -> String {
        """
        # Vídeos do Crew (Remotion)

        Esta pasta é o motor de vídeo do Crew. Cada pasta em `videos/<nome>/` é um projeto de vídeo
        escrito em React com o Remotion. Este arquivo é regravado pelo Crew: não edite.

        ## Como um projeto é montado

        - `index.ts` chama `registerRoot(Raiz)`. Não mude.
        - `Raiz.tsx` declara as composições (`<Composition id=… component=… durationInFrames=… fps=… width=… height=… />`).
          Cada composição é um vídeo que pode ser renderizado. O `id` só aceita letras, números e hífen.
        - Crie os componentes em arquivos próprios na mesma pasta (`Cena1.tsx`, `Legenda.tsx`…).
        - Imagens, áudio e vídeo de apoio: pasta `public/` dentro do projeto, lidos com `staticFile("arquivo.png")`.
        - As dependências (`remotion`, `react`) estão em `../../node_modules`: não rode `npm install`
          dentro do projeto e não crie outro `package.json`. Precisa de um pacote a mais
          (`@remotion/transitions`, `@remotion/google-fonts`…)? Instale na pasta do motor, na MESMA
          versão do `remotion` que está no `package.json` de lá: `cd ../.. && npm install @remotion/transitions@<versão>`.

        ## Regras do Remotion (as que mais quebram)

        - Toda animação vem de `useCurrentFrame()`. Nada de animação por CSS (`transition`, `@keyframes`),
          `setTimeout`, `Date.now()` ou `Math.random()`: o vídeo é renderizado quadro a quadro, fora de ordem.
          Aleatório determinístico: `random("semente")`.
        - Movimento: `interpolate(frame, [de, ate], [a, b], { extrapolateLeft: "clamp", extrapolateRight: "clamp" })`
          e `spring({ frame, fps })`.
        - Tempo: `<Sequence from={30} durationInFrames={60}>` para encadear cenas; `<Series>` para uma atrás da outra.
          Dentro de uma `Sequence`, `useCurrentFrame()` começa do zero.
        - Mídia: `<Img>`, `<OffthreadVideo>` e `<Audio>` do `remotion` (nunca `<img>` ou `<video>` puros).
        - Tamanho e duração vêm de `useVideoConfig()`; não escreva 1920 ou 30 fixos dentro dos componentes.
        - Dado que demora (fonte, imagem remota, requisição): `delayRender()` / `continueRender()`.
        - Texto que muda por vídeo entra como `defaultProps` da composição, para poder renderizar variações.

        ## Ver e renderizar

        - Ver enquanto edita: \(Usuario.nome) abre a prévia pelo Crew (Ajustes › Vídeo › Abrir prévia).
        - Conferir um quadro sem renderizar tudo (rápido; faça isso antes de dizer que ficou bom), da pasta do motor:
          `cd ../.. && ./node_modules/.bin/remotion still videos/<projeto>/index.ts <Composicao> /tmp/quadro.png --frame=45 --public-dir=videos/<projeto>/public`
          e olhe a imagem.
        - Projeto nascido de uma gravação de tela tem um `CLAUDE.md` próprio com o kit de edição e o passo a passo: leia-o primeiro.
        - Renderizar: use a ferramenta `video_renderizar` do servidor MCP `crew` (o Crew mostra o
          andamento no notch e guarda o vídeo na galeria). Sem o MCP:
          de dentro da pasta do projeto, `../../node_modules/.bin/remotion render index.ts <Composicao> "\(saidas)/<nome>.mp4"`.
          Rode o `remotion` sempre de dentro da pasta do projeto: é de lá que ele acha a `public/`.
        - Os vídeos prontos ficam em `\(saidas)`.

        ## Formatos comuns

        | Uso | Largura × altura | fps |
        |---|---|---|
        | Paisagem (YouTube, apresentação) | 1920 × 1080 | 30 |
        | Vertical (Reels, Shorts, TikTok) | 1080 × 1920 | 30 |
        | Quadrado (feed) | 1080 × 1080 | 30 |

        """
    }

    static let indice = """
    import { registerRoot } from "remotion";
    import { Raiz } from "./Raiz";

    registerRoot(Raiz);

    """

    /// O vídeo de partida: um título que entra, para o projeto já nascer renderizável.
    static func raiz(titulo: String) -> String {
        let seguro = titulo.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return """
        import React from "react";
        import { AbsoluteFill, Composition, interpolate, spring, useCurrentFrame, useVideoConfig } from "remotion";

        // Vídeo de partida criado pelo Crew. Troque à vontade: cada <Composition> abaixo é um vídeo.

        const Abertura: React.FC<{ titulo: string }> = ({ titulo }) => {
          const frame = useCurrentFrame();
          const { fps, durationInFrames } = useVideoConfig();
          const entrada = spring({ frame, fps, config: { damping: 16 } });
          const saida = interpolate(frame, [durationInFrames - 15, durationInFrames], [1, 0], {
            extrapolateLeft: "clamp",
            extrapolateRight: "clamp",
          });
          return (
            <AbsoluteFill style={{ backgroundColor: "#0B0B0F", justifyContent: "center", alignItems: "center" }}>
              <div
                style={{
                  color: "white",
                  fontFamily: "-apple-system, 'Helvetica Neue', sans-serif",
                  fontSize: 110,
                  fontWeight: 700,
                  letterSpacing: -2,
                  opacity: entrada * saida,
                  transform: `translateY(${interpolate(entrada, [0, 1], [40, 0])}px)`,
                }}
              >
                {titulo}
              </div>
            </AbsoluteFill>
          );
        };

        export const Raiz: React.FC = () => (
          <>
            <Composition
              id="Abertura"
              component={Abertura}
              durationInFrames={90}
              fps={30}
              width={1920}
              height={1080}
              defaultProps={{ titulo: "\(seguro)" }}
            />
          </>
        );

        """
    }
}
