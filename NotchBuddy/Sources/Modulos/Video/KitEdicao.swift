import Foundation

// O kit de edição que vai dentro de cada projeto de vídeo nascido de uma gravação: a montagem
// (`kit/Edicao.tsx`) e os blocos dela (fundo, moldura, zoom nos cliques, destaque do cursor e por
// moldura, cartão da câmera, palco de gráficos, dados, diagrama, legendas, faixa inferior,
// capítulo e cartelas). São blocos neutros: a cara de cada vídeo vem do `tema.ts`. Os textos abaixo são os arquivos
// como foram renderizados e conferidos no motor; o que muda por gravação (`gravacao.ts`,
// `tema.ts`, `roteiro.ts`, o guia) está em `ModeloEdicao.swift`.

enum KitEdicao {
    /// Caminho dentro do projeto → conteúdo.
    static let arquivos: [(caminho: String, texto: String)] = [
        ("index.ts", #"""
        import { registerRoot } from "remotion";
        import { Raiz } from "./Raiz";

        registerRoot(Raiz);

        """#),
        ("Raiz.tsx", #"""
        import React from "react";
        import { AbsoluteFill, Composition, OffthreadVideo, staticFile } from "remotion";
        import { gravacao } from "./gravacao";
        import { Edicao, duracaoDaEdicao } from "./kit/Edicao";
        import { roteiro } from "./roteiro";

        // Criado pelo Crew a partir de uma gravação de tela. Leia o CLAUDE.md desta pasta.
        // - Video:    a edição em paisagem (16:9), montada pelo roteiro.ts.
        // - Vertical: a mesma edição em 9:16 (a câmera acompanha o ponteiro).
        // - Gravacao: a gravação crua, do tamanho dela, para conferir.

        const Crua: React.FC = () => (
          <AbsoluteFill style={{ backgroundColor: "black" }}>
            <OffthreadVideo src={staticFile(gravacao.arquivo)} />
          </AbsoluteFill>
        );

        const Editado: React.FC = () => <Edicao roteiro={roteiro} />;

        export const Raiz: React.FC = () => {
          const quadros = duracaoDaEdicao(roteiro, gravacao.fps);
          return (
            <>
              <Composition id="Video" component={Editado} durationInFrames={quadros} fps={gravacao.fps} width={1920} height={1080} />
              <Composition id="Vertical" component={Editado} durationInFrames={quadros} fps={gravacao.fps} width={1080} height={1920} />
              <Composition
                id="Gravacao"
                component={Crua}
                durationInFrames={Math.max(1, Math.floor(gravacao.duracao * gravacao.fps))}
                fps={gravacao.fps}
                width={gravacao.largura}
                height={gravacao.altura}
              />
            </>
          );
        };

        """#),
        ("kit/movimento.ts", #"""
        import { Easing, interpolate } from "remotion";

        // Movimento do vídeo inteiro num lugar só: três durações e três curvas. Use estas, não
        // invente outra em cada componente — é o que faz a edição parecer de uma mão só.

        /** Durações em segundos. */
        export const tempo = { rapido: 0.22, medio: 0.5, lento: 0.9 } as const;

        export const curva = {
          /** Entradas: sai rápido e assenta devagar. */
          entra: Easing.bezier(0.16, 1, 0.3, 1),
          /** Saídas: começa devagar e some rápido. */
          sai: Easing.bezier(0.7, 0, 0.84, 0),
          /** Câmera (zoom e deslocamento): suave nas duas pontas. */
          camera: Easing.inOut(Easing.cubic),
        } as const;

        /** 0 → 1 entre `inicio` e `inicio + duracao` (segundos), preso nas pontas. */
        export const anima = (t: number, inicio: number, duracao: number = tempo.medio, easing: (n: number) => number = curva.entra): number =>
          interpolate(t, [inicio, inicio + Math.max(1e-4, duracao)], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing });

        /** 0 → 1 → 0: entra em `inicio`, fica, e sai terminando em `fim`. */
        export const presenca = (t: number, inicio: number, fim: number, entra: number = tempo.medio, sai: number = tempo.rapido): number =>
          Math.min(anima(t, inicio, entra), 1 - anima(t, fim - sai, sai, curva.sai));

        export const mistura = (a: number, b: number, f: number): number => a + (b - a) * f;

        """#),
        ("kit/layout.ts", #"""
        import { gravacao } from "../gravacao";

        // Onde cada coisa mora no quadro, em paisagem e em vertical. Tudo sai daqui para que margem,
        // moldura, câmera, cabeçalho e legenda conversem entre si. `u` é a unidade: 1 num vídeo de
        // 1080 de lado menor — multiplique tamanhos de fonte e espaços por ela.

        export type Caixa = { x: number; y: number; largura: number; altura: number };

        export type Layout = {
          vertical: boolean;
          u: number;
          largura: number;
          altura: number;
          margem: number;
          /** Demonstração: a moldura da gravação (quase o quadro inteiro em paisagem). */
          quadro: Caixa;
          /** Demonstração: a câmera em miniatura, no canto de cima à direita, por cima da moldura. */
          miniatura: Caixa;
          /** Fala: o cartão grande da câmera e o palco dos gráficos ao lado. */
          camera: Caixa;
          palco: Caixa;
          /** Faixa do cabeçalho (só no vertical: capítulo em cima da moldura). */
          cabecalho: Caixa;
          /** Faixa da legenda. */
          legenda: Caixa;
        };

        const cabe = (area: Caixa, proporcao: number): Caixa => {
          const altura = Math.min(area.altura, area.largura / proporcao);
          const largura = altura * proporcao;
          return { x: area.x + (area.largura - largura) / 2, y: area.y + (area.altura - altura) / 2, largura, altura };
        };

        /** `comLegenda`: em paisagem, reserva a faixa de baixo para a legenda (a moldura encolhe). */
        export const layoutDe = (largura: number, altura: number, comLegenda = false): Layout => {
          const vertical = altura > largura;
          const u = Math.min(largura, altura) / 1080;
          const proporcao = gravacao.largura / gravacao.altura;
          if (vertical) {
            const margem = 48 * u;
            const topo = 300 * u;
            const base = 400 * u;
            const lq = largura - margem * 2;
            // Gravação larga é recortada em 4:5 (a câmera acompanha o ponteiro); gravação alta cabe inteira.
            const aq = Math.min(altura - topo - base, lq / 0.8);
            const lf = proporcao < 0.8 ? Math.min(lq, aq * proporcao) : lq;
            const y = topo + (altura - topo - base - aq) / 2;
            const quadro = { x: (largura - lf) / 2, y, largura: lf, altura: aq };
            return {
              vertical, u, largura, altura, margem, quadro,
              miniatura: { x: quadro.x + quadro.largura - 300 * u, y: quadro.y - 96 * u, largura: 320 * u, altura: 200 * u },
              camera: { x: margem, y: 96 * u, largura: lq, altura: 860 * u },
              palco: { x: margem + 24 * u, y: 1010 * u, largura: lq - 48 * u, altura: altura - 1010 * u - 150 * u },
              cabecalho: { x: margem, y: 110 * u, largura: lq, altura: topo - 140 * u },
              legenda: { x: margem, y: y + aq + 40 * u, largura: lq, altura: base - 120 * u },
            };
          }
          const margem = 44 * u;
          const base = comLegenda ? 150 * u : margem;
          const quadro = cabe({ x: margem, y: margem, largura: largura - margem * 2, altura: altura - margem - base }, proporcao);
          const lc = 0.31 * largura;
          const camera = { x: largura - lc - 84 * u, y: 96 * u, largura: lc, altura: altura - 192 * u };
          return {
            vertical, u, largura, altura, margem, quadro,
            miniatura: { x: largura - 372 * u, y: 22 * u, largura: 350 * u, altura: 206 * u },
            camera,
            palco: { x: 110 * u, y: 96 * u, largura: camera.x - 110 * u - 90 * u, altura: altura - 192 * u },
            cabecalho: { x: quadro.x, y: quadro.y, largura: quadro.largura, altura: 0 },
            legenda: { x: margem, y: quadro.y + quadro.altura, largura: largura - margem * 2, altura: altura - (quadro.y + quadro.altura) },
          };
        };

        """#),
        ("kit/Fundo.tsx", #"""
        import React from "react";
        import { AbsoluteFill, useCurrentFrame, useVideoConfig } from "remotion";
        import { comAlfa, tema } from "../tema";

        // O fundo do vídeo inteiro: a cor de fundo do tema, com brilhos nas cores do projeto que
        // respiram devagar e uma malha de pontos bem leve. De onde o brilho vem é escolha do tema
        // (`tema.brilho`: "baixo", "cima", "cantos" ou "nenhum"). Fica parado embaixo de todas as
        // cenas: é o que costura fala, demonstração e cartelas.
        export const Fundo: React.FC<{ intensidade?: number }> = ({ intensidade = 1 }) => {
          const frame = useCurrentFrame();
          const { fps, width, height } = useVideoConfig();
          const t = frame / fps;
          const u = Math.min(width, height) / 1080;
          const vai = Math.sin(t * 0.19) * 6;
          const vem = Math.cos(t * 0.17) * 5;
          const forca = (0.32 + Math.sin(t * 0.31) * 0.04) * intensidade;
          const luz = (cor: string, f: number, forma: string) => `radial-gradient(${forma}, ${comAlfa(cor, f)} 0%, ${comAlfa(cor, f * 0.35)} 45%, ${comAlfa(cor, 0)} 78%)`;
          const brilhos: Record<string, string[]> = {
            baixo: [luz(tema.cor, forca, `75% 58% at ${50 + vai}% 112%`), luz(tema.cor2, forca * 0.4, `45% 40% at ${14 + vem}% -6%`)],
            cima: [luz(tema.cor, forca, `75% 58% at ${50 + vai}% -12%`), luz(tema.cor2, forca * 0.4, `45% 40% at ${86 + vem}% 106%`)],
            cantos: [luz(tema.cor, forca * 0.9, `60% 55% at ${16 + vai}% ${8 + vem}%`), luz(tema.cor2, forca * 0.7, `55% 50% at ${88 + vem}% ${96 + vai * 0.6}%`)],
            nenhum: [],
          };
          const camadas = brilhos[tema.brilho] ?? brilhos.cantos;
          return (
            <AbsoluteFill style={{ backgroundColor: tema.fundo }}>
              {camadas.length > 0 ? <AbsoluteFill style={{ background: camadas.join(", ") }} /> : null}
              <AbsoluteFill
                style={{
                  backgroundImage: `radial-gradient(${comAlfa(tema.tinta, 0.07)} ${1.2 * u}px, transparent ${1.2 * u}px)`,
                  backgroundSize: `${30 * u}px ${30 * u}px`,
                  maskImage: "radial-gradient(90% 90% at 50% 50%, black 20%, transparent 100%)",
                  WebkitMaskImage: "radial-gradient(90% 90% at 50% 50%, black 20%, transparent 100%)",
                }}
              />
              <AbsoluteFill style={{ background: `radial-gradient(120% 120% at 50% 50%, transparent 55%, ${comAlfa("#000000", 0.45)} 100%)` }} />
            </AbsoluteFill>
          );
        };

        """#),
        ("kit/Moldura.tsx", #"""
        import React from "react";
        import { comAlfa, tema } from "../tema";
        import type { Caixa } from "./layout";

        // A moldura da gravação: cantos arredondados, um fio de luz na borda e sombra funda sobre o
        // fundo. O que vai dentro (a gravação com zoom) é recortado pelos cantos.
        export const Moldura: React.FC<{
          caixa: Caixa;
          u: number;
          /** 0 → 1: a moldura entra subindo e crescendo um pouco. */
          presenca?: number;
          children: React.ReactNode;
        }> = ({ caixa, u, presenca = 1, children }) => {
          const raio = tema.raio * u;
          return (
            <div
              style={{
                position: "absolute",
                left: caixa.x,
                top: caixa.y,
                width: caixa.largura,
                height: caixa.altura,
                opacity: presenca,
                filter: presenca < 1 ? `blur(${(1 - presenca) * 12 * u}px)` : undefined,
                transform: `translateY(${(1 - presenca) * 28 * u}px) scale(${0.965 + 0.035 * presenca})`,
                borderRadius: raio,
                boxShadow: [
                  `0 ${48 * u}px ${120 * u}px ${comAlfa("#000000", 0.55)}`,
                  `0 ${12 * u}px ${32 * u}px ${comAlfa("#000000", 0.35)}`,
                  `0 0 ${140 * u}px ${comAlfa(tema.cor, 0.14)}`,
                ].join(", "),
              }}
            >
              <div style={{ position: "absolute", inset: 0, borderRadius: raio, overflow: "hidden", backgroundColor: tema.superficie }}>{children}</div>
              <div
                style={{
                  position: "absolute",
                  inset: 0,
                  borderRadius: raio,
                  boxShadow: `inset 0 0 0 ${1.5 * u}px ${comAlfa("#FFFFFF", 0.14)}, inset 0 ${1.5 * u}px 0 ${comAlfa("#FFFFFF", 0.16)}`,
                  pointerEvents: "none",
                }}
              />
            </div>
          );
        };

        """#),
        ("kit/ZoomNosCliques.tsx", #"""
        import React from "react";
        import { interpolate } from "remotion";
        import { gravacao } from "../gravacao";
        import rastro from "../public/mouse.json";
        import { curva, mistura } from "./movimento";

        // A câmera da gravação: zoom suave em cada clique e, quando a moldura é mais estreita que a
        // gravação (vídeo vertical), acompanha o ponteiro. Lê public/mouse.json (formato no CLAUDE.md).

        export type Clique = { t: number; x: number; y: number; botao: string };
        export type Trecho = { inicio: number; fim: number; cliques: Clique[] };

        export const cliques = ((rastro as { cliques?: unknown }).cliques ?? []) as Clique[];
        /** [segundo, x, y] — x e y de 0 a 1 dentro do quadro gravado. */
        export const mouse = ((rastro as { mouse?: unknown }).mouse ?? []) as [number, number, number][];
        export const temMouse = mouse.length > 1;
        /** O ponteiro aparece desenhado na gravação? (se não, o destaque do cursor desenha um). */
        export const cursorNoVideo = (rastro as { cursorNoVideo?: boolean }).cursorNoVideo !== false;

        /** Onde o ponteiro estava no segundo `t` da gravação. */
        export const posicaoDoMouse = (t: number): { x: number; y: number } => {
          if (mouse.length === 0) return { x: 0.5, y: 0.5 };
          let a = 0;
          let b = mouse.length - 1;
          if (t <= mouse[a][0]) return { x: mouse[a][1], y: mouse[a][2] };
          if (t >= mouse[b][0]) return { x: mouse[b][1], y: mouse[b][2] };
          while (b - a > 1) {
            const m = (a + b) >> 1;
            if (mouse[m][0] <= t) a = m;
            else b = m;
          }
          const f = (t - mouse[a][0]) / Math.max(1e-6, mouse[b][0] - mouse[a][0]);
          return { x: mouse[a][1] + (mouse[b][1] - mouse[a][1]) * f, y: mouse[a][2] + (mouse[b][2] - mouse[a][2]) * f };
        };

        /** O ponteiro sem tremor: média de uma janela de `janela` segundos (para a câmera seguir). */
        export const mouseSuave = (t: number, janela = 1.4): { x: number; y: number } => {
          const n = 9;
          let x = 0;
          let y = 0;
          for (let i = 0; i < n; i++) {
            const p = posicaoDoMouse(t - janela / 2 + (janela * i) / (n - 1));
            x += Math.min(1, Math.max(0, p.x));
            y += Math.min(1, Math.max(0, p.y));
          }
          return { x: x / n, y: y / n };
        };

        /** Junta os cliques em trechos de zoom: cliques a menos de `folga` s um do outro ficam no mesmo trecho. */
        export const trechosDeZoom = (antes = 0.6, depois = 1.9, folga = 2.2): Trecho[] => {
          const trechos: Trecho[] = [];
          for (const c of cliques) {
            if (c.x < 0 || c.x > 1 || c.y < 0 || c.y > 1) continue; // clique fora do quadro gravado
            const ultimo = trechos[trechos.length - 1];
            if (ultimo && c.t - antes <= ultimo.fim + folga) {
              ultimo.fim = c.t + depois;
              ultimo.cliques.push(c);
            } else {
              trechos.push({ inicio: Math.max(0, c.t - antes), fim: c.t + depois, cliques: [c] });
            }
          }
          return trechos;
        };

        const suave = { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: curva.camera } as const;

        /** O ponto que o zoom segura: o clique da vez, deslizando até o próximo. */
        const focoDoTrecho = (trecho: Trecho, t: number) => {
          let foco = { x: trecho.cliques[0].x, y: trecho.cliques[0].y };
          for (let i = 1; i < trecho.cliques.length; i++) {
            const c = trecho.cliques[i];
            const f = interpolate(t, [c.t - 0.7, c.t - 0.1], [0, 1], suave);
            foco = { x: mistura(foco.x, c.x, f), y: mistura(foco.y, c.y, f) };
          }
          return foco;
        };

        const padrao = trechosDeZoom();

        /** Quanto de zoom (0 a 1) e em que ponto, no segundo `t` da gravação. */
        export const zoomEm = (t: number, trechos: Trecho[] = padrao): { forca: number; foco: { x: number; y: number } } => {
          let forca = 0;
          let foco = mouseSuave(t);
          for (const trecho of trechos) {
            const f = interpolate(t, [trecho.inicio, trecho.inicio + 0.7, trecho.fim, trecho.fim + 0.9], [0, 1, 1, 0], suave);
            if (f > forca) {
              forca = f;
              const alvo = focoDoTrecho(trecho, t);
              foco = { x: mistura(foco.x, alvo.x, f), y: mistura(foco.y, alvo.y, f) };
            }
          }
          return { forca, foco };
        };

        /**
         * Enquadra a gravação numa caixa de `largura` × `altura` pixels.
         * - `tempo`: segundo da gravação que está na tela neste quadro.
         * - `escala`: quanto aproxima nos cliques (1.6 = 60 % maior; 1 = sem zoom).
         * - `trechos`: para escolher à mão onde dar zoom (o padrão vem dos cliques).
         * Os filhos ocupam o plano da gravação inteiro: ponha o vídeo e o que deve andar junto com
         * ele (destaque do cursor, setas, marcações em coordenadas da gravação).
         */
        export const ZoomNosCliques: React.FC<{
          tempo: number;
          largura: number;
          altura: number;
          escala?: number;
          trechos?: Trecho[];
          children: React.ReactNode;
        }> = ({ tempo, largura, altura, escala = 1.6, trechos, children }) => {
          const proporcao = gravacao.largura / gravacao.altura;
          // O plano da gravação cobrindo a caixa (sem zoom).
          const lp = Math.max(largura, altura * proporcao);
          const ap = lp / proporcao;
          const { forca, foco } = zoomEm(tempo, trechos);
          const z = 1 + (escala - 1) * forca;
          const preso = (v: number, min: number) => Math.min(0, Math.max(min, v));
          const x = preso(largura / 2 - foco.x * lp * z, largura - lp * z);
          const y = preso(altura / 2 - foco.y * ap * z, altura - ap * z);
          return (
            <div style={{ position: "absolute", left: 0, top: 0, width: lp, height: ap, transformOrigin: "0 0", transform: `translate(${x}px, ${y}px) scale(${z})` }}>
              {children}
            </div>
          );
        };

        """#),
        ("kit/DestaqueCursor.tsx", #"""
        import React from "react";
        import { comAlfa, tema } from "../tema";
        import { anima, curva } from "./movimento";
        import { cliques, cursorNoVideo, posicaoDoMouse, temMouse } from "./ZoomNosCliques";

        // Destaque do cursor: um halo leve acompanha o ponteiro e cada clique solta um anel que abre
        // e some. Vai DENTRO do <ZoomNosCliques>, por cima do vídeo: as posições são da gravação.
        // `halo={false}` deixa só os anéis; `tamanho` aumenta ou diminui os dois.
        export const DestaqueCursor: React.FC<{ tempo: number; halo?: boolean; tamanho?: number }> = ({ tempo, halo = true, tamanho = 1 }) => {
          if (!temMouse) return null;
          const p = posicaoDoMouse(tempo);
          const dentro = p.x >= 0 && p.x <= 1 && p.y >= 0 && p.y <= 1;
          // Tamanhos em % da largura do plano: acompanham a gravação em qualquer formato.
          const raioHalo = 2.6 * tamanho;
          const raioAnel = 2.7 * tamanho;
          const ativos = cliques.filter((c) => tempo >= c.t - 0.05 && tempo <= c.t + 0.75);
          return (
            <div style={{ position: "absolute", inset: 0, pointerEvents: "none" }}>
              {halo && dentro ? (
                <div
                  style={{
                    position: "absolute",
                    left: `${p.x * 100}%`,
                    top: `${p.y * 100}%`,
                    width: `${raioHalo * 2}%`,
                    aspectRatio: "1",
                    transform: "translate(-50%, -50%)",
                    borderRadius: "50%",
                    background: `radial-gradient(circle, ${comAlfa(tema.cor, 0.3)} 0%, ${comAlfa(tema.cor, 0.12)} 55%, ${comAlfa(tema.cor, 0)} 72%)`,
                  }}
                />
              ) : null}
              {ativos.map((c) => {
                const abre = anima(tempo, c.t, 0.6, curva.entra);
                const some = 1 - anima(tempo, c.t + 0.15, 0.55, curva.sai);
                const toque = 1 - anima(tempo, c.t, 0.28, curva.entra);
                return (
                  <React.Fragment key={c.t}>
                    <div
                      style={{
                        position: "absolute",
                        left: `${c.x * 100}%`,
                        top: `${c.y * 100}%`,
                        width: `${raioAnel * 2}%`,
                        aspectRatio: "1",
                        transform: `translate(-50%, -50%) scale(${0.25 + 0.75 * abre})`,
                        borderRadius: "50%",
                        border: `0.22vw solid ${tema.cor}`,
                        boxSizing: "border-box",
                        opacity: some,
                      }}
                    />
                    <div
                      style={{
                        position: "absolute",
                        left: `${c.x * 100}%`,
                        top: `${c.y * 100}%`,
                        width: `${raioAnel * 0.9}%`,
                        aspectRatio: "1",
                        transform: `translate(-50%, -50%) scale(${0.4 + 0.6 * toque})`,
                        borderRadius: "50%",
                        backgroundColor: comAlfa(tema.cor, 0.55),
                        opacity: toque,
                      }}
                    />
                  </React.Fragment>
                );
              })}
              {!cursorNoVideo && dentro ? (
                <svg viewBox="0 0 15 22" style={{ position: "absolute", left: `${p.x * 100}%`, top: `${p.y * 100}%`, width: "1.3%" }}>
                  <path d="M1 1 L1 17 L5 13.5 L8 20 L10.5 19 L7.5 12.5 L13 12.5 Z" fill="#111" stroke="#fff" strokeWidth={1.2} strokeLinejoin="round" />
                </svg>
              ) : null}
            </div>
          );
        };

        """#),
        ("kit/DestaqueMoldura.tsx", #"""
        import React from "react";
        import { comAlfa, tema } from "../tema";
        import { presenca } from "./movimento";

        // Destaque por moldura: um contorno na cor do projeto em volta de uma parte da tela, com um
        // rótulo opcional. É o jeito padrão de chamar atenção (em vez de zoom forte). Vai DENTRO do
        // <ZoomNosCliques>: posição e tamanho em frações do quadro gravado, tempos da gravação.
        export type Destaque = { de: number; ate: number; x: number; y: number; largura: number; altura: number; rotulo?: string };

        export const DestaqueMoldura: React.FC<{ tempo: number; destaques: Destaque[] }> = ({ tempo, destaques }) => (
          <div style={{ position: "absolute", inset: 0, pointerEvents: "none" }}>
            {destaques.map((d, i) => {
              const p = presenca(tempo, d.de, d.ate, 0.45, 0.25);
              if (p <= 0) return null;
              return (
                <div
                  key={i}
                  style={{
                    position: "absolute",
                    left: `${d.x * 100}%`,
                    top: `${d.y * 100}%`,
                    width: `${d.largura * 100}%`,
                    height: `${d.altura * 100}%`,
                    borderRadius: "0.7vw",
                    border: `0.2vw solid ${tema.cor}`,
                    boxShadow: `0 0 0 0.35vw ${comAlfa(tema.cor, 0.2)}, 0 0 2.4vw ${comAlfa(tema.cor, 0.45)}`,
                    boxSizing: "border-box",
                    opacity: p,
                    transform: `scale(${1.05 - 0.05 * p})`,
                  }}
                >
                  {d.rotulo ? (
                    <div
                      style={{
                        position: "absolute",
                        left: "-0.2vw",
                        bottom: "calc(100% + 0.5vw)",
                        padding: "0.3vw 0.75vw",
                        borderRadius: "0.5vw",
                        backgroundColor: tema.cor,
                        color: tema.fundo,
                        fontFamily: tema.fonteTexto,
                        fontSize: "1.05vw",
                        fontWeight: 700,
                        whiteSpace: "nowrap",
                      }}
                    >
                      {d.rotulo}
                    </div>
                  ) : null}
                </div>
              );
            })}
          </div>
        );

        """#),
        ("kit/CartaoCamera.tsx", #"""
        import React from "react";
        import { OffthreadVideo, staticFile } from "remotion";
        import { gravacao } from "../gravacao";
        import { comAlfa, tema } from "../tema";
        import type { Caixa } from "./layout";

        // A câmera de quem apresenta, num cartão de cantos arredondados: grande ao lado dos gráficos
        // (cena de fala) ou em miniatura no canto da demonstração. Duas fontes:
        // - `arquivo`: um vídeo da câmera em public/ (gravado à parte), com `atraso` = quantos segundos
        //   depois do começo da gravação da tela ele começou (negativo se começou antes);
        // - `recorte`: a bolha da câmera que já está DENTRO da gravação da tela — centro e lado em
        //   frações da largura/altura do quadro gravado. A imagem é pequena: serve bem para miniatura
        //   e para um cartão médio, não para tela cheia.

        export type FonteDaCamera = { arquivo: string; atraso?: number } | { recorte: { x: number; y: number; lado: number } };

        export const CartaoCamera: React.FC<{
          fonte: FonteDaCamera;
          caixa: Caixa;
          u: number;
          /** Segundo da gravação da tela neste quadro (a câmera acompanha). */
          tempo: number;
          fps: number;
          /** 0 → 1: entra com desfoque, crescendo um pouco. */
          presenca?: number;
        }> = ({ fonte, caixa, u, tempo, fps, presenca = 1 }) => {
          const raio = Math.min(tema.raio * 1.3 * u, caixa.largura / 6);
          let miolo: React.ReactNode;
          if ("arquivo" in fonte) {
            const inicio = Math.max(0, Math.round((tempo - (fonte.atraso ?? 0)) * fps));
            miolo = (
              <OffthreadVideo
                src={staticFile(fonte.arquivo)}
                trimBefore={inicio}
                muted
                style={{ position: "absolute", inset: 0, width: "100%", height: "100%", objectFit: "cover" }}
              />
            );
          } else {
            // Amplia o plano da gravação até a bolha cobrir o cartão, com o centro dela no centro.
            const { x, y, lado } = fonte.recorte;
            const ladoPx = Math.max(caixa.largura, caixa.altura);
            const lp = ladoPx / lado; // largura do plano da gravação, em pixels do vídeo
            const ap = lp * (gravacao.altura / gravacao.largura);
            miolo = (
              <OffthreadVideo
                src={staticFile(gravacao.arquivo)}
                trimBefore={Math.max(0, Math.round(tempo * fps))}
                muted
                style={{ position: "absolute", width: lp, height: ap, left: caixa.largura / 2 - x * lp, top: caixa.altura / 2 - y * ap, maxWidth: "none" }}
              />
            );
          }
          return (
            <div
              style={{
                position: "absolute",
                left: caixa.x,
                top: caixa.y,
                width: caixa.largura,
                height: caixa.altura,
                borderRadius: raio,
                opacity: presenca,
                filter: presenca < 1 ? `blur(${(1 - presenca) * 14 * u}px)` : undefined,
                transform: `scale(${0.95 + 0.05 * presenca})`,
                boxShadow: `0 ${30 * u}px ${80 * u}px ${comAlfa("#000000", 0.55)}, 0 0 ${90 * u}px ${comAlfa(tema.cor, 0.1)}`,
              }}
            >
              <div style={{ position: "absolute", inset: 0, borderRadius: raio, overflow: "hidden", backgroundColor: tema.superficie }}>{miolo}</div>
              <div style={{ position: "absolute", inset: 0, borderRadius: raio, boxShadow: `inset 0 0 0 ${1.5 * u}px ${comAlfa("#FFFFFF", 0.14)}` }} />
            </div>
          );
        };

        """#),
        ("kit/Legendas.tsx", #"""
        import React from "react";
        import dados from "../public/legendas.json";
        import { comAlfa, tema } from "../tema";
        import { anima } from "./movimento";
        import type { Caixa } from "./layout";

        // Legendas pela fala, lidas de public/legendas.json (o Crew transcreve a gravação no Mac).
        // Cada bloco mostra poucas palavras; a palavra dita na hora acende na cor do projeto.
        // O texto do JSON pode ser corrigido à mão (nomes próprios, termos do projeto): só não mexa
        // nos tempos.

        export type Palavra = { t: number; fim: number; texto: string };
        export type Frase = { inicio: number; fim: number; texto: string; palavras: Palavra[] };
        type Bloco = { inicio: number; fim: number; palavras: Palavra[] };

        export const frases = ((dados as { frases?: unknown }).frases ?? []) as Frase[];
        export const temLegendas = frases.length > 0;

        /**
         * Quebra as frases em blocos de até `maximo` caracteres, sem atravessar de uma frase para
         * outra e sem deixar palavra sozinha: a frase é repartida em blocos de tamanho parecido.
         */
        export const blocosDeLegenda = (maximo: number): Bloco[] => {
          const blocos: Bloco[] = [];
          for (const f of frases) {
            const palavras = f.palavras.length > 0 ? f.palavras : [{ t: f.inicio, fim: f.fim, texto: f.texto }];
            const total = palavras.reduce((n, p) => n + p.texto.length + 1, 0);
            const partes = Math.max(1, Math.ceil(total / maximo));
            const alvo = total / partes;
            let atual: Palavra[] = [];
            let tamanho = 0;
            const fecha = () => {
              if (atual.length > 0) blocos.push({ inicio: atual[0].t, fim: atual[atual.length - 1].fim, palavras: atual });
              atual = [];
              tamanho = 0;
            };
            palavras.forEach((p, i) => {
              const resto = palavras.slice(i).reduce((n, x) => n + x.texto.length + 1, 0);
              // Fecha antes desta palavra se ela estoura o bloco, ou se o bloco já chegou no tamanho
              // certo e o que sobra ainda enche outro.
              if (tamanho > 0 && (tamanho + p.texto.length + 1 > maximo || (tamanho >= alvo * 0.9 && resto >= alvo * 0.5))) fecha();
              atual.push(p);
              tamanho += p.texto.length + 1;
            });
            fecha();
          }
          return blocos;
        };

        /**
         * - `tempo`: segundo da gravação neste quadro.
         * - `caixa`: a faixa onde a legenda mora (vem do layout).
         * - `tamanho`: tamanho da letra em pixels; `maximo`: caracteres por bloco.
         */
        export const Legendas: React.FC<{ tempo: number; caixa: Caixa; u: number; tamanho?: number; maximo?: number }> = ({
          tempo,
          caixa,
          u,
          tamanho = 40 * u,
          maximo = 44,
        }) => {
          const blocos = React.useMemo(() => blocosDeLegenda(maximo), [maximo]);
          // O bloco fica um instante depois da última palavra, a não ser que o próximo já comece.
          let bloco: Bloco | undefined;
          for (let i = 0; i < blocos.length; i++) {
            const b = blocos[i];
            const proximo = blocos[i + 1];
            const ate = Math.min(b.fim + 0.5, proximo ? proximo.inicio - 0.02 : Infinity);
            if (tempo >= b.inicio - 0.1 && tempo < ate) bloco = b;
          }
          if (!bloco) return null;
          const entra = anima(tempo, bloco.inicio - 0.1, 0.22);
          return (
            <div style={{ position: "absolute", left: caixa.x, top: caixa.y, width: caixa.largura, height: caixa.altura, display: "flex", justifyContent: "center", alignItems: "center" }}>
              <div
                style={{
                  maxWidth: "92%",
                  padding: `${tamanho * 0.36}px ${tamanho * 0.72}px`,
                  borderRadius: tamanho * 0.5,
                  backgroundColor: comAlfa(tema.superficie, 0.88),
                  boxShadow: `inset 0 0 0 ${1.5 * u}px ${comAlfa("#FFFFFF", 0.09)}, 0 ${14 * u}px ${40 * u}px ${comAlfa("#000000", 0.4)}`,
                  fontFamily: tema.fonteTexto,
                  fontSize: tamanho,
                  fontWeight: 650,
                  lineHeight: 1.22,
                  letterSpacing: -0.012 * tamanho,
                  textAlign: "center",
                  opacity: entra,
                  transform: `translateY(${(1 - entra) * tamanho * 0.3}px)`,
                }}
              >
                {bloco.palavras.map((p, i) => {
                  const dita = tempo >= p.t;
                  const agora = dita && tempo < p.fim + 0.06;
                  return (
                    <span key={i} style={{ color: agora ? tema.cor : tema.tinta, opacity: dita ? 1 : 0.42 }}>
                      {p.texto}
                      {i < bloco.palavras.length - 1 ? " " : ""}
                    </span>
                  );
                })}
              </div>
            </div>
          );
        };

        """#),
        ("kit/FaixaInferior.tsx", #"""
        import React from "react";
        import { comAlfa, tema } from "../tema";
        import { anima, presenca } from "./movimento";
        import type { Caixa } from "./layout";

        // Faixa inferior (o "quem e o quê"): nome e contexto no canto de baixo da moldura. Entra
        // abrindo da esquerda, fica alguns segundos e sai. `t` é o segundo dentro da cena.
        export const FaixaInferior: React.FC<{
          t: number;
          quadro: Caixa;
          u: number;
          nome: string;
          contexto?: string;
          de?: number;
          ate?: number;
        }> = ({ t, quadro, u, nome, contexto, de = 0.9, ate = 5.2 }) => {
          const p = presenca(t, de, ate, 0.6, 0.3);
          if (p <= 0) return null;
          const texto = anima(t, de + 0.18, 0.5);
          const folga = 26 * u;
          return (
            <div
              style={{
                position: "absolute",
                left: quadro.x + folga,
                bottom: `calc(100% - ${quadro.y + quadro.altura - folga}px)`,
                display: "flex",
                alignItems: "stretch",
                gap: 16 * u,
                padding: `${14 * u}px ${24 * u}px ${14 * u}px ${14 * u}px`,
                borderRadius: 16 * u,
                backgroundColor: comAlfa(tema.superficie, 0.92),
                boxShadow: `inset 0 0 0 ${1.5 * u}px ${comAlfa("#FFFFFF", 0.1)}, 0 ${16 * u}px ${44 * u}px ${comAlfa("#000000", 0.45)}`,
                clipPath: `inset(0 ${(1 - p) * 100}% 0 0 round ${16 * u}px)`,
                opacity: Math.min(1, p * 3),
              }}
            >
              <div style={{ width: 5 * u, borderRadius: 3 * u, backgroundColor: tema.cor }} />
              <div style={{ display: "flex", flexDirection: "column", gap: 3 * u, opacity: texto, transform: `translateY(${(1 - texto) * 8 * u}px)` }}>
                <div style={{ fontFamily: tema.fonteTitulo, fontSize: 30 * u, fontWeight: 700, letterSpacing: -0.5 * u, color: tema.tinta, whiteSpace: "nowrap" }}>{nome}</div>
                {contexto ? (
                  <div style={{ fontFamily: tema.fonteTexto, fontSize: 20 * u, fontWeight: 500, color: tema.apagado, whiteSpace: "nowrap" }}>{contexto}</div>
                ) : null}
              </div>
            </div>
          );
        };

        """#),
        ("kit/Cabecalho.tsx", #"""
        import React from "react";
        import { comAlfa, tema } from "../tema";
        import { anima } from "./movimento";
        import type { Layout } from "./layout";

        // O capítulo que acompanha a gravação: em paisagem, uma etiqueta (número + nome) no canto de cima
        // da moldura, que some depois de alguns segundos; no vertical, o título grande acima da moldura,
        // com o selo do projeto. `t` é o segundo dentro da cena.
        export const Cabecalho: React.FC<{ t: number; layout: Layout; numero?: number; capitulo?: string }> = ({ t, layout, numero, capitulo }) => {
          const { u, cabecalho, vertical } = layout;
          const p = anima(t, 0.15, 0.5);
          const selo = (
            <div style={{ display: "flex", alignItems: "center", gap: 10 * u, fontFamily: tema.fonteTexto, fontSize: (vertical ? 24 : 17) * u, fontWeight: 650, letterSpacing: 3 * u, textTransform: "uppercase", color: tema.apagado }}>
              <div style={{ width: 9 * u, height: 9 * u, borderRadius: "50%", backgroundColor: tema.cor }} />
              {tema.projeto}
            </div>
          );
          if (vertical) {
            return (
              <div style={{ position: "absolute", left: cabecalho.x, top: cabecalho.y, width: cabecalho.largura, display: "flex", flexDirection: "column", gap: 22 * u, opacity: p, transform: `translateY(${(1 - p) * 14 * u}px)` }}>
                {selo}
                {capitulo ? (
                  <div style={{ display: "flex", alignItems: "baseline", gap: 20 * u }}>
                    {numero ? <span style={{ fontFamily: tema.fonteMono, fontSize: 34 * u, fontWeight: 600, color: tema.cor }}>{String(numero).padStart(2, "0")}</span> : null}
                    <span style={{ fontFamily: tema.fonteTitulo, fontSize: 62 * u, fontWeight: 750, letterSpacing: -1.6 * u, lineHeight: 1.04, color: tema.tinta }}>{capitulo}</span>
                  </div>
                ) : null}
              </div>
            );
          }
          // Paisagem: uma etiqueta presa na borda de cima da moldura (metade para fora, para cobrir
          // quase nada da tela), que some depois de alguns segundos.
          if (!capitulo) return null;
          const some = 1 - anima(t, 3.6, 0.4);
          const q = layout.quadro;
          return (
            <div
              style={{
                position: "absolute",
                left: q.x + 26 * u,
                top: q.y - 22 * u,
                display: "flex",
                alignItems: "center",
                gap: 12 * u,
                padding: `${10 * u}px ${18 * u}px ${10 * u}px ${12 * u}px`,
                borderRadius: 14 * u,
                backgroundColor: comAlfa(tema.superficie, 0.92),
                boxShadow: `inset 0 0 0 ${1.5 * u}px ${comAlfa("#FFFFFF", 0.1)}, 0 ${12 * u}px ${32 * u}px ${comAlfa("#000000", 0.4)}`,
                opacity: Math.min(p, some),
                transform: `translateY(${(1 - p) * -10 * u}px)`,
              }}
            >
              {numero ? (
                <span style={{ fontFamily: tema.fonteMono, fontSize: 17 * u, fontWeight: 600, color: tema.cor, padding: `${4 * u}px ${9 * u}px`, borderRadius: 7 * u, backgroundColor: comAlfa(tema.cor, 0.16) }}>
                  {String(numero).padStart(2, "0")}
                </span>
              ) : null}
              <span style={{ fontFamily: tema.fonteTitulo, fontSize: 24 * u, fontWeight: 680, letterSpacing: -0.3 * u, color: tema.tinta }}>{capitulo}</span>
            </div>
          );
        };

        /** Fio de andamento na base do quadro: `fracao` de 0 a 1 do vídeo inteiro. */
        export const Andamento: React.FC<{ fracao: number; u: number }> = ({ fracao, u }) => (
          <div style={{ position: "absolute", left: 0, right: 0, bottom: 0, height: 5 * u, backgroundColor: comAlfa(tema.tinta, 0.07) }}>
            <div style={{ width: `${Math.min(1, Math.max(0, fracao)) * 100}%`, height: "100%", backgroundColor: tema.cor, borderRadius: `0 ${3 * u}px ${3 * u}px 0` }} />
          </div>
        );

        """#),
        ("kit/Palco.tsx", #"""
        import React from "react";
        import { Freeze, Img, OffthreadVideo, staticFile, useVideoConfig } from "remotion";
        import { gravacao } from "../gravacao";
        import { comAlfa, tema } from "../tema";
        import { anima } from "./movimento";

        // As peças do palco de gráficos (o espaço ao lado da câmera na cena de fala, ou o quadro
        // inteiro numa cartela de dados): título curto com uma palavra em destaque, pilha de
        // miniaturas, cartão de aviso e a grade de dados. Pouco texto por tela: 2 a 4 palavras.
        // `t` é sempre o segundo dentro da cena.

        /** Texto que entra palavra por palavra, por trás de uma máscara; `destaque` pinta palavras na cor do projeto. */
        export const Palavras: React.FC<{ texto: string; t: number; inicio?: number; passo?: number; destaque?: string; estilo: React.CSSProperties }> = ({
          texto,
          t,
          inicio = 0,
          passo = 0.07,
          destaque,
          estilo,
        }) => {
          const limpa = (s: string) => s.toLowerCase().replace(/[^\p{L}\p{N}]/gu, "");
          const fortes = new Set((destaque ?? "").split(/\s+/).map(limpa).filter(Boolean));
          return (
            <div style={{ ...estilo, display: "flex", flexWrap: "wrap", columnGap: "0.26em" }}>
              {texto.split(/\s+/).map((palavra, i) => {
                const p = anima(t, inicio + i * passo, 0.7);
                return (
                  <span key={i} style={{ display: "inline-block", overflow: "hidden", paddingBottom: "0.16em", marginBottom: "-0.16em" }}>
                    <span style={{ display: "inline-block", transform: `translateY(${(1 - p) * 105}%)`, opacity: Math.min(1, p * 2), color: fortes.has(limpa(palavra)) ? tema.cor : undefined }}>
                      {palavra}
                    </span>
                  </span>
                );
              })}
            </div>
          );
        };

        /** Título curto do palco (minúsculas, peso forte) com uma linha de apoio opcional. */
        export const TituloCurto: React.FC<{ t: number; u: number; titulo: string; destaque?: string; linha?: string; tamanho?: number }> = ({ t, u, titulo, destaque, linha, tamanho = 78 }) => (
          <div style={{ display: "flex", flexDirection: "column", gap: 18 * u }}>
            <Palavras texto={titulo} t={t} inicio={0.1} destaque={destaque} estilo={{ fontFamily: tema.fonteTitulo, fontSize: tamanho * u, fontWeight: 780, lineHeight: 1.05, letterSpacing: -0.03 * tamanho * u, color: tema.tinta }} />
            {linha ? (
              <Palavras texto={linha} t={t} inicio={0.45} passo={0.04} destaque={destaque} estilo={{ fontFamily: tema.fonteTexto, fontSize: 34 * u, fontWeight: 500, lineHeight: 1.25, color: comAlfa(tema.tinta, 0.72) }} />
            ) : null}
          </div>
        );

        export type Miniatura = {
          /** Imagem em public/ … */
          imagem?: string;
          /** … ou um quadro da própria gravação (segundo). */
          quadro?: number;
          rotulo?: string;
          detalhe?: string;
        };

        /** Uma miniatura: imagem do projeto ou um quadro da gravação, com cantos e fio de luz. */
        export const Figura: React.FC<{ item: Miniatura; u: number; estilo?: React.CSSProperties }> = ({ item, u, estilo }) => {
          const { fps } = useVideoConfig();
          const cheio: React.CSSProperties = { position: "absolute", inset: 0, width: "100%", height: "100%", objectFit: "cover" };
          return (
            <div style={{ position: "relative", aspectRatio: `${gravacao.largura} / ${gravacao.altura}`, borderRadius: 14 * u, overflow: "hidden", backgroundColor: tema.superficie, boxShadow: `0 ${18 * u}px ${48 * u}px ${comAlfa("#000000", 0.5)}, inset 0 0 0 ${1.5 * u}px ${comAlfa("#FFFFFF", 0.1)}`, ...estilo }}>
              {item.imagem ? (
                <Img src={staticFile(item.imagem)} style={cheio} />
              ) : (
                <Freeze frame={0}>
                  <OffthreadVideo src={staticFile(gravacao.arquivo)} trimBefore={Math.round((item.quadro ?? 0) * fps)} muted style={cheio} />
                </Freeze>
              )}
              <div style={{ position: "absolute", inset: 0, borderRadius: 14 * u, boxShadow: `inset 0 0 0 ${1.5 * u}px ${comAlfa("#FFFFFF", 0.12)}` }} />
            </div>
          );
        };

        /** Miniaturas que entram uma a uma, em pilha: a da frente nítida, as de trás recuadas e desfocadas. */
        export const PilhaDeMiniaturas: React.FC<{ t: number; u: number; itens: Miniatura[]; largura: number; inicio?: number; passo?: number }> = ({ t, u, itens, largura, inicio = 0.5, passo = 0.55 }) => {
          const lf = largura * 0.78;
          const altura = (lf * gravacao.altura) / gravacao.largura;
          return (
            <div style={{ position: "relative", width: largura, height: altura + 30 * u, flexShrink: 0 }}>
              {itens.map((item, i) => {
                const p = anima(t, inicio + i * passo, 0.7);
                if (p <= 0) return null;
                // Quantas já entraram por cima desta (0 = é a da frente).
                let recuo = 0;
                for (let j = i + 1; j < itens.length; j++) recuo += anima(t, inicio + j * passo, 0.7);
                recuo = Math.min(recuo, 3);
                return (
                  <div
                    key={i}
                    style={{
                      position: "absolute",
                      left: ((largura - lf) * recuo) / 3,
                      top: 30 * u - recuo * 10 * u,
                      width: lf,
                      zIndex: i,
                      opacity: p * (1 - Math.max(0, recuo - 1) * 0.25),
                      filter: `blur(${((1 - p) * 16 + recuo * 2.4) * u}px)`,
                      transform: `translateX(${(1 - p) * -90 * u}px) scale(${(0.94 + 0.06 * p) * (1 - recuo * 0.05)})`,
                      transformOrigin: "right center",
                    }}
                  >
                    <Figura item={item} u={u} />
                  </div>
                );
              })}
            </div>
          );
        };

        /** Rótulo de uma ou duas palavras embaixo dos gráficos. */
        export const Rotulo: React.FC<{ t: number; u: number; texto: string; inicio?: number }> = ({ t, u, texto, inicio = 0.6 }) => {
          const p = anima(t, inicio, 0.5);
          return (
            <div style={{ fontFamily: tema.fonteTitulo, fontSize: 40 * u, fontWeight: 740, letterSpacing: -0.8 * u, color: comAlfa(tema.tinta, 0.86), opacity: p, transform: `translateY(${(1 - p) * 12 * u}px)`, filter: `blur(${(1 - p) * 8 * u}px)` }}>{texto}</div>
          );
        };

        const Cadeado: React.FC<{ lado: number; cor: string }> = ({ lado, cor }) => (
          <svg width={lado} height={lado} viewBox="0 0 24 24" fill="none">
            <rect x={5} y={10.5} width={14} height={10} rx={2.6} fill={cor} />
            <path d="M8.2 10.5V7.8a3.8 3.8 0 0 1 7.6 0v2.7" stroke={cor} strokeWidth={2.2} strokeLinecap="round" />
          </svg>
        );

        /** Cartão de aviso, com as cores do tema invertidas ("fica para o próximo vídeo"): título forte e uma linha na cor do projeto. */
        export const CartaoAviso: React.FC<{ t: number; u: number; titulo: string; linha?: string; cadeado?: boolean; inicio?: number; largura?: number }> = ({ t, u, titulo, linha, cadeado, inicio = 0.3, largura }) => {
          const p = anima(t, inicio, 0.6);
          return (
            <div
              style={{
                width: largura,
                padding: `${54 * u}px ${48 * u}px`,
                borderRadius: 22 * u,
                backgroundColor: tema.tinta,
                boxShadow: `0 ${30 * u}px ${80 * u}px ${comAlfa("#000000", 0.55)}`,
                display: "flex",
                flexDirection: "column",
                alignItems: "center",
                gap: 12 * u,
                opacity: p,
                filter: `blur(${(1 - p) * 14 * u}px)`,
                transform: `scale(${0.94 + 0.06 * p})`,
                boxSizing: "border-box",
              }}
            >
              {cadeado ? <Cadeado lado={54 * u} cor={tema.fundo} /> : null}
              <div style={{ fontFamily: tema.fonteTitulo, fontSize: 60 * u, fontWeight: 800, letterSpacing: -1.6 * u, color: tema.fundo, textAlign: "center" }}>{titulo}</div>
              {linha ? <div style={{ fontFamily: tema.fonteTexto, fontSize: 27 * u, fontWeight: 650, color: tema.cor, textAlign: "center" }}>{linha}</div> : null}
            </div>
          );
        };

        export type Numero = { valor: string; texto: string };

        /** Cartela de dados: números grandes na cor do projeto em cima e a grade de miniaturas com legenda. */
        export const GradeDeDados: React.FC<{ t: number; u: number; largura: number; numeros?: Numero[]; itens: Miniatura[]; colunas?: number }> = ({ t, u, largura, numeros = [], itens, colunas = 3 }) => {
          const vao = 26 * u;
          return (
            <div style={{ width: largura, display: "flex", flexDirection: "column", gap: 40 * u }}>
              {numeros.length > 0 ? (
                <div style={{ display: "flex", flexWrap: "wrap", columnGap: 70 * u, rowGap: 10 * u }}>
                  {numeros.map((n, i) => {
                    const p = anima(t, 0.1 + i * 0.16, 0.6);
                    return (
                      <div key={i} style={{ display: "flex", alignItems: "baseline", gap: 16 * u, opacity: p, transform: `translateY(${(1 - p) * 18 * u}px)`, filter: `blur(${(1 - p) * 8 * u}px)` }}>
                        <span style={{ fontFamily: tema.fonteTitulo, fontSize: 104 * u, fontWeight: 820, letterSpacing: -4 * u, lineHeight: 1, color: tema.cor }}>{n.valor}</span>
                        <span style={{ fontFamily: tema.fonteTitulo, fontSize: 46 * u, fontWeight: 760, letterSpacing: -1.2 * u, color: tema.tinta }}>{n.texto}</span>
                      </div>
                    );
                  })}
                </div>
              ) : null}
              <div style={{ display: "grid", gridTemplateColumns: `repeat(${colunas}, 1fr)`, columnGap: vao, rowGap: vao }}>
                {itens.map((item, i) => {
                  const p = anima(t, 0.45 + i * 0.13, 0.65);
                  return (
                    <div key={i} style={{ display: "flex", flexDirection: "column", gap: 10 * u, opacity: p, filter: `blur(${(1 - p) * 14 * u}px)`, transform: `translateX(${(1 - p) * -40 * u}px) scale(${0.95 + 0.05 * p})` }}>
                      <Figura item={item} u={u} />
                      {item.rotulo || item.detalhe ? (
                        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", fontFamily: tema.fonteTexto, fontSize: 19 * u }}>
                          <span style={{ color: tema.apagado, fontWeight: 500 }}>{item.rotulo}</span>
                          <span style={{ color: tema.tinta, fontWeight: 700 }}>{item.detalhe}</span>
                        </div>
                      ) : null}
                    </div>
                  );
                })}
              </div>
            </div>
          );
        };

        """#),
        ("kit/Diagrama.tsx", #"""
        import React from "react";
        import { comAlfa, tema } from "../tema";
        import { anima } from "./movimento";

        // Diagrama explicativo: cartões em fila ligados por linhas, com um ponto que viaja de um para
        // o outro (pedido → valor → painel). Entra embaixo da gravação quando ela recua para o centro,
        // para explicar o que a demonstração faz. `t` é o segundo dentro da cena.
        export type CartaoDoDiagrama = { titulo: string; texto?: string };

        export const Diagrama: React.FC<{ t: number; u: number; largura: number; cartoes: CartaoDoDiagrama[]; inicio?: number; passo?: number }> = ({ t, u, largura, cartoes, inicio = 0.7, passo = 0.7 }) => {
          const n = cartoes.length;
          const vao = 64 * u;
          const lc = (largura - vao * (n - 1)) / n;
          // O ponto dá a volta inteira pelos cartões a cada `n * 1.1` segundos, depois de todos entrarem.
          const ciclo = Math.max(0, t - inicio - n * passo * 0.6) / 1.1;
          return (
            <div style={{ position: "relative", width: largura, display: "flex", gap: vao }}>
              {cartoes.map((c, i) => {
                const p = anima(t, inicio + i * passo, 0.6);
                const linha = anima(t, inicio + i * passo + 0.3, 0.5);
                const fase = ciclo - Math.floor(ciclo / n) * n - i; // 0..1 enquanto o ponto cruza esta ligação
                return (
                  <React.Fragment key={i}>
                    <div
                      style={{
                        width: lc,
                        boxSizing: "border-box",
                        padding: `${22 * u}px ${24 * u}px`,
                        borderRadius: 16 * u,
                        backgroundColor: comAlfa(tema.superficie, 0.94),
                        boxShadow: `inset 0 0 0 ${1.5 * u}px ${comAlfa("#FFFFFF", 0.1)}, 0 ${18 * u}px ${44 * u}px ${comAlfa("#000000", 0.4)}`,
                        display: "flex",
                        flexDirection: "column",
                        gap: 6 * u,
                        opacity: p,
                        filter: `blur(${(1 - p) * 12 * u}px)`,
                        transform: `translateY(${(1 - p) * 24 * u}px)`,
                      }}
                    >
                      <div style={{ display: "flex", alignItems: "center", gap: 12 * u }}>
                        <span style={{ fontFamily: tema.fonteMono, fontSize: 17 * u, fontWeight: 600, color: tema.cor }}>{String(i + 1).padStart(2, "0")}</span>
                        <span style={{ fontFamily: tema.fonteTitulo, fontSize: 30 * u, fontWeight: 740, letterSpacing: -0.6 * u, color: tema.tinta }}>{c.titulo}</span>
                      </div>
                      {c.texto ? <div style={{ fontFamily: tema.fonteTexto, fontSize: 20 * u, fontWeight: 500, lineHeight: 1.3, color: tema.apagado }}>{c.texto}</div> : null}
                    </div>
                    {i < n - 1 ? (
                      <div style={{ position: "absolute", left: (lc + vao) * i + lc + 8 * u, top: "50%", width: (vao - 16 * u) * linha, height: 2 * u, backgroundColor: comAlfa(tema.tinta, 0.28) }}>
                        {fase >= 0 && fase <= 1 && linha >= 1 ? (
                          <div style={{ position: "absolute", left: `${fase * 100}%`, top: "50%", width: 12 * u, height: 12 * u, borderRadius: "50%", backgroundColor: tema.cor, transform: "translate(-50%, -50%)", boxShadow: `0 0 ${16 * u}px ${tema.cor}` }} />
                        ) : null}
                      </div>
                    ) : null}
                  </React.Fragment>
                );
              })}
            </div>
          );
        };

        """#),
        ("kit/Cartelas.tsx", #"""
        import React from "react";
        import { Img, staticFile } from "remotion";
        import { comAlfa, tema } from "../tema";
        import { anima, presenca } from "./movimento";
        import type { Layout } from "./layout";
        import { Palavras } from "./Palco";

        // As cartelas de tela cheia: título (abertura), capítulo e encerramento. Mesmo alinhamento à
        // esquerda, mesma régua de tamanhos e o mesmo jeito de entrar: palavra por palavra, de baixo
        // para cima, por trás de uma máscara. `t` é o segundo dentro da cena; `duracao`, o total dela.

        const Selo: React.FC<{ u: number; texto: string; p: number }> = ({ u, texto, p }) => (
          <div style={{ display: "flex", alignItems: "center", gap: 14 * u, fontFamily: tema.fonteTexto, fontSize: 22 * u, fontWeight: 650, letterSpacing: 4.5 * u, textTransform: "uppercase", color: tema.apagado, opacity: p, transform: `translateX(${(1 - p) * -12 * u}px)` }}>
            <div style={{ width: 11 * u, height: 11 * u, borderRadius: "50%", backgroundColor: tema.cor, boxShadow: `0 0 ${18 * u}px ${comAlfa(tema.cor, 0.8)}` }} />
            {texto}
          </div>
        );

        const Fio: React.FC<{ u: number; p: number }> = ({ u, p }) => (
          <div style={{ width: 132 * u * p, height: 6 * u, borderRadius: 3 * u, backgroundColor: tema.cor }} />
        );

        const palco = (layout: Layout, opacidade: number, extra: React.CSSProperties = {}): React.CSSProperties => ({
          position: "absolute",
          inset: 0,
          display: "flex",
          flexDirection: "column",
          justifyContent: "center",
          padding: layout.vertical ? `0 ${84 * layout.u}px` : `0 ${150 * layout.u}px`,
          boxSizing: "border-box",
          opacity: opacidade,
          ...extra,
        });

        /** Abertura: selo do projeto, título grande, fio na cor da marca, subtítulo e assinatura. */
        export const CartelaTitulo: React.FC<{ t: number; duracao: number; layout: Layout; titulo: string; destaque?: string; subtitulo?: string; autor?: string }> = ({ t, duracao, layout, titulo, destaque, subtitulo, autor }) => {
          const { u, vertical } = layout;
          const sai = 1 - anima(t, duracao - 0.35, 0.35, (n) => n * n);
          const tamanho = (vertical ? 104 : titulo.length > 34 ? 104 : 128) * u;
          return (
            <div style={palco(layout, sai, { transform: `scale(${1 + (1 - sai) * 0.04})`, filter: `blur(${(1 - sai) * 10 * u}px)` })}>
              <div style={{ display: "flex", flexDirection: "column", gap: 34 * u, maxWidth: vertical ? "100%" : 1500 * u }}>
                <Selo u={u} texto={tema.projeto} p={anima(t, 0.1, 0.6)} />
                <Palavras texto={titulo} t={t} inicio={0.25} destaque={destaque} estilo={{ fontFamily: tema.fonteTitulo, fontSize: tamanho, fontWeight: 780, lineHeight: 1.03, letterSpacing: -0.032 * tamanho, color: tema.tinta }} />
                <Fio u={u} p={anima(t, 0.75, 0.7)} />
                {subtitulo ? (
                  <div style={{ fontFamily: tema.fonteTexto, fontSize: (vertical ? 42 : 38) * u, fontWeight: 450, lineHeight: 1.3, color: tema.apagado, opacity: anima(t, 0.95, 0.6), transform: `translateY(${(1 - anima(t, 0.95, 0.6)) * 14 * u}px)` }}>{subtitulo}</div>
                ) : null}
              </div>
              {autor ? (
                <div style={{ position: "absolute", left: (vertical ? 84 : 150) * u, bottom: (vertical ? 150 : 84) * u, fontFamily: tema.fonteMono, fontSize: (vertical ? 26 : 20) * u, fontWeight: 500, color: comAlfa(tema.tinta, 0.5), opacity: anima(t, 1.2, 0.6) }}>{autor}</div>
              ) : null}
            </div>
          );
        };

        /** Cartela de capítulo: número, nome e o fio. Curta (1,5 s costuma bastar). */
        export const CartelaCapitulo: React.FC<{ t: number; duracao: number; layout: Layout; numero: number; titulo: string }> = ({ t, duracao, layout, numero, titulo }) => {
          const { u, vertical } = layout;
          const p = presenca(t, 0, duracao, 0.3, 0.28);
          const tamanho = (vertical ? 92 : 100) * u;
          return (
            <div style={palco(layout, Math.min(1, p * 1.5), { filter: `blur(${(1 - Math.min(1, p * 1.5)) * 10 * u}px)` })}>
              <div style={{ display: "flex", flexDirection: "column", gap: 26 * u }}>
                <div style={{ display: "flex", alignItems: "center", gap: 18 * u, opacity: anima(t, 0.05, 0.45) }}>
                  <span style={{ fontFamily: tema.fonteMono, fontSize: 30 * u, fontWeight: 600, color: tema.cor }}>{String(numero).padStart(2, "0")}</span>
                  <div style={{ width: 64 * u * anima(t, 0.1, 0.6), height: 2 * u, backgroundColor: comAlfa(tema.tinta, 0.3) }} />
                </div>
                <Palavras texto={titulo} t={t} inicio={0.12} passo={0.06} estilo={{ fontFamily: tema.fonteTitulo, fontSize: tamanho, fontWeight: 750, lineHeight: 1.05, letterSpacing: -0.03 * tamanho, color: tema.tinta }} />
              </div>
            </div>
          );
        };

        /** Encerramento: a frase final, uma linha de apoio, o selo do projeto e, se houver, um QR code com chamada. */
        export const CartelaEncerramento: React.FC<{ t: number; duracao: number; layout: Layout; titulo: string; destaque?: string; linha?: string; qr?: string; chamada?: string }> = ({ t, duracao, layout, titulo, destaque, linha, qr, chamada }) => {
          const { u, vertical } = layout;
          const sai = 1 - anima(t, duracao - 0.5, 0.5, (n) => n * n);
          const tamanho = (vertical ? 92 : 108) * u;
          const pq = anima(t, 0.9, 0.7);
          return (
            <div style={palco(layout, sai, vertical ? {} : { flexDirection: "row", alignItems: "center", justifyContent: "space-between", gap: 80 * u })}>
              <div style={{ display: "flex", flexDirection: "column", gap: 32 * u, flex: 1 }}>
                <Fio u={u} p={anima(t, 0.1, 0.7)} />
                <Palavras texto={titulo} t={t} inicio={0.2} destaque={destaque} estilo={{ fontFamily: tema.fonteTitulo, fontSize: tamanho, fontWeight: 780, lineHeight: 1.04, letterSpacing: -0.03 * tamanho, color: tema.tinta }} />
                {linha ? <div style={{ fontFamily: tema.fonteTexto, fontSize: (vertical ? 40 : 36) * u, fontWeight: 450, color: tema.apagado, opacity: anima(t, 0.8, 0.6) }}>{linha}</div> : null}
                <div style={{ marginTop: 20 * u }}>
                  <Selo u={u} texto={tema.projeto} p={anima(t, 1.0, 0.6)} />
                </div>
              </div>
              {qr ? (
                <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 20 * u, marginTop: vertical ? 70 * u : 0, alignSelf: vertical ? "flex-start" : "center", opacity: pq, filter: `blur(${(1 - pq) * 12 * u}px)`, transform: `scale(${0.94 + 0.06 * pq})` }}>
                  <div style={{ padding: 22 * u, borderRadius: 26 * u, backgroundColor: "#FFFFFF", boxShadow: `0 ${30 * u}px ${80 * u}px ${comAlfa("#000000", 0.5)}, 0 0 ${90 * u}px ${comAlfa(tema.cor, 0.25)}` }}>
                    <Img src={staticFile(qr)} style={{ display: "block", width: 290 * u, height: 290 * u, imageRendering: "pixelated" }} />
                  </div>
                  {chamada ? <div style={{ fontFamily: tema.fonteTitulo, fontSize: 28 * u, fontWeight: 700, color: tema.tinta }}>{chamada}</div> : null}
                </div>
              ) : null}
            </div>
          );
        };

        """#),
        ("kit/Edicao.tsx", #"""
        import React from "react";
        import { AbsoluteFill, Audio, OffthreadVideo, Sequence, staticFile, useCurrentFrame, useVideoConfig } from "remotion";
        import { gravacao } from "../gravacao";
        import { Andamento, Cabecalho } from "./Cabecalho";
        import { CartaoCamera, type FonteDaCamera } from "./CartaoCamera";
        import { CartelaCapitulo, CartelaEncerramento, CartelaTitulo } from "./Cartelas";
        import { DestaqueCursor } from "./DestaqueCursor";
        import { DestaqueMoldura, type Destaque } from "./DestaqueMoldura";
        import { Diagrama, type CartaoDoDiagrama } from "./Diagrama";
        import { FaixaInferior } from "./FaixaInferior";
        import { Fundo } from "./Fundo";
        import { Legendas } from "./Legendas";
        import { layoutDe, type Caixa } from "./layout";
        import { Moldura } from "./Moldura";
        import { anima, curva, mistura, presenca } from "./movimento";
        import { CartaoAviso, GradeDeDados, PilhaDeMiniaturas, Rotulo, TituloCurto, type Miniatura, type Numero } from "./Palco";
        import { ZoomNosCliques } from "./ZoomNosCliques";

        // A montagem: lê o roteiro e põe os blocos em fila, sobre um fundo só. Os blocos:
        // - demonstração: a gravação emoldurada (zoom nos cliques, destaque do cursor, destaques por
        //   moldura, câmera em miniatura, legenda opcional);
        // - fala: a câmera num cartão grande e, ao lado, o palco de gráficos (título curto, miniaturas,
        //   aviso) — sem câmera, o palco ocupa o quadro e a voz continua;
        // - dados: números grandes e uma grade de miniaturas;
        // - diagrama: a gravação recua e cartões ligados por linhas explicam o que ela mostra;
        // - cartelas: abertura, capítulo e encerramento.
        // É um ponto de partida, não um molde: para uma composição própria, monte as cenas à mão com as
        // peças do kit em <Sequence>, ou acrescente um bloco novo aqui.

        /** Demonstração: um pedaço da gravação da tela. */
        export type Demo = {
          /** Segundos da gravação: onde o trecho começa e termina. */
          de: number;
          ate: number;
          /** Nome do capítulo que começa aqui (ganha cartela e etiqueta). */
          capitulo?: string;
          /** 2 = duas vezes mais rápido (o som do trecho é cortado). */
          velocidade?: number;
          /** Zoom nos cliques: false desliga; um número troca a escala (padrão 1.35). */
          zoom?: boolean | number;
          /** Liga ou desliga a legenda só neste trecho. */
          legenda?: boolean;
          /** Contornos em volta de partes da tela (tempos e posições da gravação). */
          destaques?: Destaque[];
        };

        /** Fala: a câmera grande e o palco de gráficos; o som é o da gravação entre `de` e `ate`. */
        export type Fala = {
          fala: {
            de: number;
            ate: number;
            capitulo?: string;
            titulo?: string;
            /** Palavra(s) do título e da linha pintadas na cor do projeto. */
            destaque?: string;
            linha?: string;
            rotulo?: string;
            miniaturas?: Miniatura[];
            aviso?: { titulo: string; linha?: string; cadeado?: boolean };
            /** De que lado fica a câmera em paisagem (padrão: direita). */
            lado?: "direita" | "esquerda";
          };
        };

        /** Dados: números e grade de miniaturas. Com `de`/`ate`, toca a voz da gravação; sem, dura `duracao` s. */
        export type Dados = { dados: { de?: number; ate?: number; duracao?: number; capitulo?: string; numeros?: Numero[]; itens: Miniatura[]; colunas?: number } };

        /** Diagrama: a gravação (de–até) recua ao centro e os cartões explicam o caminho. */
        export type Explica = { diagrama: { de: number; ate: number; capitulo?: string; cartoes: CartaoDoDiagrama[] } };

        export type TrechoDoRoteiro = Demo | Fala | Dados | Explica;

        export type Roteiro = {
          titulo: string;
          /** Palavra(s) do título pintadas na cor do projeto. */
          destaque?: string;
          subtitulo?: string;
          autor?: string;
          /** Nome e contexto da faixa inferior, no começo da primeira demonstração. */
          faixa?: { nome: string; contexto?: string };
          /** Um pedaço forte da gravação mostrado antes do título, para prender. */
          gancho?: { de: number; ate: number };
          /** A câmera de quem apresenta: arquivo à parte ou a bolha recortada da gravação (ver CartaoCamera.tsx). */
          camera?: FonteDaCamera;
          /** Legenda pela fala: true/false para todos os formatos; sem dizer, só no vertical. */
          legendas?: boolean;
          /** Fio de andamento na base do vídeo. */
          andamento?: boolean;
          trechos: TrechoDoRoteiro[];
          encerramento?: { titulo: string; destaque?: string; linha?: string; qr?: string; chamada?: string };
        };

        const ABERTURA = 3.6;
        const CAPITULO = 1.6;
        const ENCERRAMENTO = 4;

        type Cena =
          | { tipo: "gancho" | "demo"; de: number; quadros: number; trecho: Demo; numero?: number; capitulo?: string; primeiro: boolean }
          | { tipo: "fala"; de: number; quadros: number; fala: Fala["fala"] }
          | { tipo: "dados"; de: number; quadros: number; dados: Dados["dados"] }
          | { tipo: "diagrama"; de: number; quadros: number; diagrama: Explica["diagrama"]; numero?: number; capitulo?: string }
          | { tipo: "abertura" | "encerramento"; de: number; quadros: number }
          | { tipo: "capitulo"; de: number; quadros: number; numero: number; titulo: string };

        type SemInicio<T> = T extends unknown ? Omit<T, "de"> : never;

        /** As cenas do roteiro, com o quadro em que cada uma começa. */
        export const cenasDe = (roteiro: Roteiro, fps: number): Cena[] => {
          const cenas: Cena[] = [];
          let de = 0;
          const q = (segundos: number) => Math.max(1, Math.round(segundos * fps));
          const empurra = (cena: SemInicio<Cena>) => {
            cenas.push({ ...cena, de } as Cena);
            de += cena.quadros;
          };
          if (roteiro.gancho && roteiro.gancho.ate > roteiro.gancho.de) {
            empurra({ tipo: "gancho", quadros: q(roteiro.gancho.ate - roteiro.gancho.de), trecho: { ...roteiro.gancho }, primeiro: false });
          }
          empurra({ tipo: "abertura", quadros: q(ABERTURA) });
          let numero = 0;
          let capitulo: string | undefined;
          let primeiro = true;
          const abre = (nome?: string) => {
            if (!nome) return;
            numero += 1;
            capitulo = nome;
            empurra({ tipo: "capitulo", quadros: q(CAPITULO), numero, titulo: nome });
          };
          for (const trecho of roteiro.trechos) {
            if ("fala" in trecho) {
              if (trecho.fala.ate <= trecho.fala.de) continue;
              abre(trecho.fala.capitulo);
              empurra({ tipo: "fala", quadros: q(trecho.fala.ate - trecho.fala.de), fala: trecho.fala });
            } else if ("dados" in trecho) {
              const d = trecho.dados;
              abre(d.capitulo);
              empurra({ tipo: "dados", quadros: q(d.de !== undefined && d.ate !== undefined && d.ate > d.de ? d.ate - d.de : d.duracao ?? 5), dados: d });
            } else if ("diagrama" in trecho) {
              if (trecho.diagrama.ate <= trecho.diagrama.de) continue;
              abre(trecho.diagrama.capitulo);
              empurra({ tipo: "diagrama", quadros: q(trecho.diagrama.ate - trecho.diagrama.de), diagrama: trecho.diagrama, numero: numero || undefined, capitulo });
            } else {
              if (trecho.ate <= trecho.de) continue;
              abre(trecho.capitulo);
              empurra({ tipo: "demo", quadros: q((trecho.ate - trecho.de) / (trecho.velocidade ?? 1)), trecho, numero: numero || undefined, capitulo, primeiro });
              primeiro = false;
            }
          }
          if (roteiro.encerramento) empurra({ tipo: "encerramento", quadros: q(ENCERRAMENTO) });
          return cenas;
        };

        export const duracaoDaEdicao = (roteiro: Roteiro, fps: number): number => {
          const cenas = cenasDe(roteiro, fps);
          const ultima = cenas[cenas.length - 1];
          return ultima ? ultima.de + ultima.quadros : 1;
        };

        const useCena = (quadros: number, comLegenda = false) => {
          const frame = useCurrentFrame();
          const { fps, width, height } = useVideoConfig();
          const layout = layoutDe(width, height, comLegenda);
          const t = frame / fps;
          const duracao = quadros / fps;
          return { fps, layout, t, duracao, p: presenca(t, 0, duracao, 0.55, 0.25) };
        };

        /** A voz da gravação entre `de` e o fim da cena (para os blocos que não mostram a gravação). */
        const Voz: React.FC<{ de: number; fps: number }> = ({ de, fps }) => <Audio src={staticFile(gravacao.arquivo)} trimBefore={Math.round(de * fps)} />;

        /** Demonstração: a gravação emoldurada, com tudo que anda junto com ela. */
        const CenaDeDemo: React.FC<{ cena: Extract<Cena, { tipo: "gancho" | "demo" }>; roteiro: Roteiro }> = ({ cena, roteiro }) => {
          const { height, width } = useVideoConfig();
          const comLegenda = (cena.trecho.legenda ?? roteiro.legendas ?? height > width) && (cena.trecho.velocidade ?? 1) === 1;
          const { fps, layout, t, duracao, p } = useCena(cena.quadros, comLegenda);
          const { u, quadro, vertical } = layout;
          const velocidade = cena.trecho.velocidade ?? 1;
          const tempo = cena.trecho.de + t * velocidade;
          const zoom = cena.trecho.zoom;
          const escala = zoom === false ? 1 : typeof zoom === "number" ? zoom : 1.35;
          return (
            <AbsoluteFill>
              {vertical || cena.tipo === "demo" ? <Cabecalho t={t} layout={layout} numero={cena.numero} capitulo={vertical ? cena.capitulo : undefined} /> : null}
              <Moldura caixa={quadro} u={u} presenca={p}>
                <ZoomNosCliques tempo={tempo} largura={quadro.largura} altura={quadro.altura} escala={escala}>
                  <OffthreadVideo
                    src={staticFile(gravacao.arquivo)}
                    trimBefore={Math.round(cena.trecho.de * fps)}
                    playbackRate={velocidade}
                    muted={velocidade !== 1}
                    style={{ position: "absolute", inset: 0, width: "100%", height: "100%" }}
                  />
                  <DestaqueCursor tempo={tempo} />
                  {cena.trecho.destaques ? <DestaqueMoldura tempo={tempo} destaques={cena.trecho.destaques} /> : null}
                </ZoomNosCliques>
              </Moldura>
              {!vertical && cena.tipo === "demo" && cena.capitulo ? <Cabecalho t={t} layout={layout} numero={cena.numero} capitulo={cena.capitulo} /> : null}
              {roteiro.camera && "arquivo" in roteiro.camera ? <CartaoCamera fonte={roteiro.camera} caixa={layout.miniatura} u={u} tempo={tempo} fps={fps} presenca={p} /> : null}
              {cena.tipo === "demo" && cena.primeiro && roteiro.faixa ? (
                <FaixaInferior t={t} quadro={quadro} u={u} nome={roteiro.faixa.nome} contexto={roteiro.faixa.contexto} ate={Math.min(5.2, duracao - 0.3)} />
              ) : null}
              {comLegenda ? (
                <div style={{ opacity: Math.min(1, p * 2) }}>
                  <Legendas tempo={tempo} caixa={layout.legenda} u={u} tamanho={(vertical ? 54 : 38) * u} maximo={vertical ? 26 : 46} />
                </div>
              ) : null}
            </AbsoluteFill>
          );
        };

        /** Fala: a câmera num cartão grande e o palco de gráficos ao lado (ou embaixo, no vertical). */
        const CenaDeFala: React.FC<{ cena: Extract<Cena, { tipo: "fala" }>; roteiro: Roteiro }> = ({ cena, roteiro }) => {
          const { fps, layout, t, p } = useCena(cena.quadros);
          const { u, vertical, largura } = layout;
          const f = cena.fala;
          const tempo = f.de + t;
          const camera = roteiro.camera;
          // Sem câmera, o palco ocupa o quadro; com a câmera à esquerda, os dois trocam de lado.
          let palco: Caixa = camera ? layout.palco : { ...layout.palco, largura: vertical ? layout.palco.largura : largura - 220 * u, y: vertical ? 420 * u : layout.palco.y };
          let cartao = layout.camera;
          if (camera && !vertical && f.lado === "esquerda") {
            cartao = { ...cartao, x: 84 * u };
            palco = { ...palco, x: cartao.x + cartao.largura + 90 * u };
          }
          return (
            <AbsoluteFill>
              <Voz de={f.de} fps={fps} />
              {camera ? <CartaoCamera fonte={camera} caixa={cartao} u={u} tempo={tempo} fps={fps} presenca={p} /> : null}
              <div style={{ position: "absolute", left: palco.x, top: palco.y, width: palco.largura, height: palco.altura, display: "flex", flexDirection: "column", justifyContent: vertical ? "flex-start" : "center", gap: 44 * u, opacity: Math.min(1, p * 1.5) }}>
                {f.titulo ? <TituloCurto t={t} u={u} titulo={f.titulo} destaque={f.destaque} linha={f.linha} tamanho={vertical ? 84 : 78} /> : null}
                {f.miniaturas && f.miniaturas.length > 0 ? <PilhaDeMiniaturas t={t} u={u} itens={f.miniaturas} largura={Math.min(palco.largura, 900 * u)} /> : null}
                {f.aviso ? <CartaoAviso t={t} u={u} titulo={f.aviso.titulo} linha={f.aviso.linha} cadeado={f.aviso.cadeado} largura={Math.min(palco.largura, 760 * u)} /> : null}
                {f.rotulo ? <Rotulo t={t} u={u} texto={f.rotulo} /> : null}
              </div>
            </AbsoluteFill>
          );
        };

        /** Dados: números grandes e a grade de miniaturas, no quadro inteiro. */
        const CenaDeDados: React.FC<{ cena: Extract<Cena, { tipo: "dados" }> }> = ({ cena }) => {
          const { fps, layout, t, p } = useCena(cena.quadros);
          const { u, vertical, largura } = layout;
          const d = cena.dados;
          const margem = (vertical ? 70 : 150) * u;
          return (
            <AbsoluteFill style={{ justifyContent: "center", paddingLeft: margem, opacity: Math.min(1, p * 1.5), filter: `blur(${(1 - Math.min(1, p * 1.5)) * 10 * u}px)` }}>
              {d.de !== undefined ? <Voz de={d.de} fps={fps} /> : null}
              <GradeDeDados t={t} u={u} largura={largura - margem * 2} numeros={d.numeros} itens={d.itens} colunas={d.colunas ?? (vertical ? 2 : 3)} />
            </AbsoluteFill>
          );
        };

        /** Diagrama: a gravação recua para cima e os cartões entram embaixo, ligados por linhas. */
        const CenaDeDiagrama: React.FC<{ cena: Extract<Cena, { tipo: "diagrama" }> }> = ({ cena }) => {
          const { fps, layout, t, duracao, p } = useCena(cena.quadros);
          const { u, quadro, vertical, largura, altura } = layout;
          const d = cena.diagrama;
          const tempo = d.de + t;
          const recuo = Math.min(anima(t, 0.2, 0.9, curva.camera), 1 - anima(t, duracao - 0.9, 0.7, curva.camera));
          const fator = vertical ? 0.86 : 0.66;
          const caixa: Caixa = {
            x: mistura(quadro.x, (largura - quadro.largura * fator) / 2, recuo),
            y: mistura(quadro.y, vertical ? quadro.y : 56 * u, recuo),
            largura: mistura(quadro.largura, quadro.largura * fator, recuo),
            altura: mistura(quadro.altura, quadro.altura * fator, recuo),
          };
          const ld = largura - (vertical ? 96 : 300) * u;
          return (
            <AbsoluteFill>
              <Moldura caixa={caixa} u={u} presenca={p}>
                <ZoomNosCliques tempo={tempo} largura={caixa.largura} altura={caixa.altura} escala={1}>
                  <OffthreadVideo src={staticFile(gravacao.arquivo)} trimBefore={Math.round(d.de * fps)} style={{ position: "absolute", inset: 0, width: "100%", height: "100%" }} />
                </ZoomNosCliques>
              </Moldura>
              <div style={{ position: "absolute", left: (largura - ld) / 2, top: vertical ? caixa.y + caixa.altura + 70 * u : altura - 250 * u, opacity: recuo }}>
                <Diagrama t={t} u={vertical ? u * 0.9 : u} largura={ld} cartoes={d.cartoes} />
              </div>
            </AbsoluteFill>
          );
        };

        const CenaDeCartela: React.FC<{ cena: Cena; roteiro: Roteiro }> = ({ cena, roteiro }) => {
          const { layout, t, duracao } = useCena(cena.quadros);
          if (cena.tipo === "abertura") {
            return <CartelaTitulo t={t} duracao={duracao} layout={layout} titulo={roteiro.titulo} destaque={roteiro.destaque} subtitulo={roteiro.subtitulo} autor={roteiro.autor} />;
          }
          if (cena.tipo === "capitulo") return <CartelaCapitulo t={t} duracao={duracao} layout={layout} numero={cena.numero} titulo={cena.titulo} />;
          if (cena.tipo === "encerramento" && roteiro.encerramento) {
            const e = roteiro.encerramento;
            return <CartelaEncerramento t={t} duracao={duracao} layout={layout} titulo={e.titulo} destaque={e.destaque} linha={e.linha} qr={e.qr} chamada={e.chamada} />;
          }
          return null;
        };

        export const Edicao: React.FC<{ roteiro: Roteiro }> = ({ roteiro }) => {
          const frame = useCurrentFrame();
          const { fps, width, height, durationInFrames } = useVideoConfig();
          const cenas = React.useMemo(() => cenasDe(roteiro, fps), [roteiro, fps]);
          const u = Math.min(width, height) / 1080;
          return (
            <AbsoluteFill>
              <Fundo />
              {cenas.map((cena, i) => (
                <Sequence key={i} from={cena.de} durationInFrames={cena.quadros} name={cena.tipo}>
                  {cena.tipo === "gancho" || cena.tipo === "demo" ? (
                    <CenaDeDemo cena={cena} roteiro={roteiro} />
                  ) : cena.tipo === "fala" ? (
                    <CenaDeFala cena={cena} roteiro={roteiro} />
                  ) : cena.tipo === "dados" ? (
                    <CenaDeDados cena={cena} />
                  ) : cena.tipo === "diagrama" ? (
                    <CenaDeDiagrama cena={cena} />
                  ) : (
                    <CenaDeCartela cena={cena} roteiro={roteiro} />
                  )}
                </Sequence>
              ))}
              {roteiro.andamento ? <Andamento fracao={frame / Math.max(1, durationInFrames - 1)} u={u} /> : null}
            </AbsoluteFill>
          );
        };

        """#),
    ]
}
