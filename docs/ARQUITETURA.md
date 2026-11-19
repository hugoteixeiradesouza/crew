# Arquitetura do Crew

> Documento vivo. Fonte da verdade sobre **como o Crew é organizado e para onde ele cresce**.
> Quem abre uma sessão para mexer no Crew lê isto antes. Pesquisa que embasou as decisões:
> `docs/pesquisa/` (o mapa do Crew antes da reorganização).

## 0. Missão

**O Crew trabalha junto com o Hugo.** O Hugo controla tudo; o Crew fica de olho por ele —
nas IAs, no Mac e no próprio trabalho do Hugo — para que ele continue no controle. O Homie é
quem faz isso: a presença no notch que mostra, lembra, cobra e prepara, e nunca decide no
lugar do Hugo.

Em uma frase: **você no controle; o Crew de olho por você.**

Os compromissos que vêm dessa missão (valem acima de qualquer funcionalidade):

1. **O Hugo decide; o Crew prepara.** Nenhuma ação que sai do Mac ou que não se desfaz
   (mandar mensagem, apagar, aprovar, gastar) acontece sem o clique dele. O Crew rascunha,
   sugere, lembra — e para aí.
2. **Local primeiro.** O que o Crew vê fica no Mac. Modelo local (Apple Intelligence) para
   ler e organizar; o Claude só entra quando o Hugo manda um trabalho para ele.
3. **Cada fonte é ligada pelo Hugo.** Nada é lido "por padrão": sessões e Mac já são do
   Crew; WhatsApp, e-mail e o que vier depois são ligados um a um, e desligar apaga o que
   foi guardado daquela fonte.
4. **Cobrar com respeito.** Pouco, na hora certa, com motivo à vista ("você disse ao Rafa às
   14:05…") e três saídas sempre: feito, pôr na lista, ignorar. O que o Hugo ignora ensina o
   Crew a cobrar menos aquilo.
5. **Explicar o porquê.** Todo aviso diz de onde veio. Nada de caixa-preta.
6. **Barato de existir.** Zero CPU parado, sem rede própria, sem conta, sem nuvem.

## 1. O que o Crew é

**O parceiro de trabalho do Hugo no Mac** — a central das IAs que trabalham nele, da própria
máquina e do dia do Hugo, com o Homie como a interface viva no notch.

Quatro pilares, um app só (o quarto, **Criar**, entrou em 2026-11-12):

| Pilar | O que cobre | Módulos |
|---|---|---|
| **IA** | os agentes que trabalham no Mac | Sessões (Claude Code hoje; Codex/Cursor depois), Agentes (worktrees, sessões paralelas), Modelos locais (Ollama/LM Studio), Uso e custo, Rotinas (pedidos agendados), Automação (crew:// e MCP), Integrações |
| **Mac** | a máquina em si | Sistema (CPU, memória, temperatura, rede, bateria), Áudio (volume e saída por app, microfone), Disco (espaço, limpeza segura), Apps (desinstalar), Tela (brilho), Música, Arquivos |
| **Criar** | produzir: o que sai do Mac como texto, imagem, áudio e vídeo | Captura (captura de tela, texto da tela, anotar; vem: gravação de tela, câmera e áudio), Voz (ditado, leitura em voz alta; vem: a voz do computador), e vêm Vídeo (Remotion) e Imagem (gerada pelas sessões) |
| **Eu** | o dia de trabalho do Hugo | Diário (o que foi feito, notas rápidas, resumo do dia), Compromissos (promessas feitas no WhatsApp e no e-mail, cobradas na hora certa), Lista (Lembretes do macOS) — o **assistente** é o Homie |

### Setores — como o Crew se organiza por dentro (2026-11-13)

O Crew é um **gestor de IA e do Mac**: junta o que o Mac oferece a favor de quem constrói com
IA. Por dentro, ele se divide em **seis setores**; cada um existe por causa de um problema:

| Setor | O problema que resolve | O que mora nele hoje |
|---|---|---|
| **Squad** (`comando`) | dirigir várias IAs sem perder o fio | sessões, projetos e histórico (a tela inicial do app), Homies, Agentes, Rotinas, Modelos, Uso |
| **Spot** (`mesa`) | trabalhar sem sair do Crew | Navegador e Arquivos de um projeto (o terminal segue dentro da sessão) |
| **Booth** (`estudio`) | produzir material | Captura, Vídeo, Voz |
| **Rig** (`maquina`) | o Mac aguentar e ficar limpo | Sistema, Disco, Apps, Áudio (e, só nos Ajustes, Brilho e volume e Música) |
| **Grind** (`dia`) | saber o que devo e o que foi feito | Tasks (o Diário) |
| **Link** (`conexoes`) | o Crew falar com o mundo de fora | Automação (`crew://` e MCP) |

Três coisas atravessam os setores e **não** são setor: a **Ilha** (vitrine: cada ferramenta
decide o que mostra nela), o **comando universal** e o **Homie**.

**Onde isso vive no código**
- `Nucleo/Setor.swift` — o `enum Setor` (nome, ícone, frase do problema, número). É o único
  lugar dos nomes: trocar "Mesa" por outro nome é mudar uma linha. Cada módulo tem
  `Modulo.setor`; os que já existiam estão na lista `Setor.modulos` (que também dá a ordem
  dentro do setor) e **módulo novo declara o dele no próprio arquivo** (`let setor = Setor.estudio`).
- `Central/Setores/` — a navegação do app: `LateralSetores` (a barra lateral é uma só, em
  qualquer setor: `TrocaSetores` é a fileira que troca de setor; `LateralSetor` lista as
  ferramentas do setor e as sessões rodando, que acompanham o Hugo; `DivisaoComSessao` põe uma
  sessão ao lado da tela em que ele está), `TelaSetor` (a tela de trabalho da ferramenta
  escolhida; sem abas — trocar de setor e de ferramenta é só na barra lateral), `PaginaFerramenta` (o título e o
  `Modulo.central()` do módulo) e `Setores` (o catálogo: que ferramentas cada setor tem).
- O setor na tela **sai da seleção** (`NavegacaoCrew.setor` é calculado de `Selecao`; o caso novo
  é `.ferramenta(id)`): não há dois estados para se desencontrarem. O Comando é a tela das
  sessões de sempre, com as outras ferramentas dele no pé da barra lateral (`FerramentasComando`).
- Ferramenta que não é módulo (navegador, arquivos da Mesa) entra no catálogo em
  `Setores.ferramentas(_:)`. Setor sem tela para uma função prometida **não ganha tela falsa**.
- `Central.abrir(modulo:)` (botões "Detalhes"/"Revisar" da ilha, avisos, `crew://central/<modulo>`,
  MCP `abrir_no_crew`) abre a **tela de trabalho** do módulo no setor dele; só módulo sem tela
  cai nos Ajustes. A configuração abre por `Central.ajustes(modulo:)` (botão "Ajustes" da tela).
- Atalhos: ⌘1 … ⌘6 vão para o setor (itens do menu "Ir", resolvidos pela camada 5 de
  `Central/Atalhos.swift`, sem depender da barra de menus).

**Relação com pilar e superfície** — são três perguntas diferentes, e só uma agrupa telas:
- **Setor** = *que problema resolve*. É o agrupamento da navegação: barra de setores do app e
  seções da barra lateral dos Ajustes.
- **Superfície** = *onde aparece* (Ilha, App, Atalho, Claude). Um módulo de qualquer setor
  escolhe as dele; "App" hoje quer dizer "tem tela no setor dele".
- **Pilar** (IA, Mac, Criar, Eu) = o tema amplo, de antes dos setores. **Não agrupa mais tela
  nenhuma**; fica no contrato só como padrão do setor para módulo que não declarou
  (`Setor.padrao`: IA → Comando, Mac → Máquina, Criar → Estúdio, Eu → Dia). Pode sair do
  contrato quando todos os módulos declararem o setor.

**O que ficou igual de propósito**: a ordem das ferramentas na ilha (atalhos ao lado da câmera,
grade, blocos da home) continua a do `Registro` — ordenar por setor trocaria quais duas
ferramentas ficam ao lado da câmera. As integrações (GitHub, Vercel, Stripe, Notion, n8n…)
estão desligadas no código (`AgentTask.integracoesLigadas = false`) e por isso não aparecem em
Conexões; quando voltarem, entram como ferramentas desse setor.

E as superfícies. **Um módulo não é "da ilha" nem "do app": é uma capacidade que escolhe em
quais superfícies aparece** — e declara isso em `Modulo.superficies` (`Nucleo/Modulo.swift`,
enum `Superficie`), que vira a linha "Onde aparece" da página dele nos Ajustes:

| Superfície | Para quê | Tempo |
|---|---|---|
| **Ilha** | atalho para a rotina: olhar, aprovar, começar ou parar algo | segundos |
| **App** | onde se trabalha: sessões, navegador, arquivos, terminal e o estúdio (gravações, vídeo, voz, imagem) | horas |
| **Atalho** (fundo) | atalho global, por cima de qualquer app: ditar, capturar, volume do app | um gesto |
| **Claude** | o que as sessões usam sozinhas: `crew://`, MCP e as ferramentas de criação | — |
| **Ajustes** | configurar; todo módulo tem página | raro |

Em detalhe:

1. **Ilha (notch)** — olhar e agir em um clique. Compacta: um sinal por vez (o mais
   importante agora). Expandida: a aba do módulo, curta.
2. **O app do Crew (janela das sessões)** — `Central/AppCrewView.swift` + `Modulos/Sessoes/Central/`,
   hospedado pela `JanelaCrew`. Só sessões, com cara própria (escuro, estilo app de conversa, o
   Homie vivo; tema em `Central/TemaCrew.swift`): início com o campo de pedido (projeto, motor,
   modelo, modo), barra lateral Sessões | Projetos | Histórico, conversa, aprovação/pergunta em
   destaque acima do campo e o terminal ao vivo da sessão. Aberta, o Crew vira app de Dock com
   menu próprio; fechada, volta a morar só no notch.
   **Dois motores de sessão**: o **motor do Crew** (`Modulos/Sessoes/Motor/MotorCrew.swift`,
   2026-11-09) abre o Claude Code pelo CLI num tmux `crew-<session_id>` (`claude --session-id`),
   sem depender de outro app — hooks, transcript e `send-keys` fazem o resto; e o **Xirp**
   (engenharia reversa de 2026-10-15: daemon local em `127.0.0.1:63100`, cada sessão num tmux
   `xirp-<id>` com o `squab` dono do PTY, histórico num Postgres embutido — o Crew fala com ele
   só pelo CLI `xirp`). Os projetos (`ProjetosCrew`) juntam as pastas adicionadas no Crew, os
   projetos do Xirp e as pastas das sessões abertas.
   **Leva de 2026-11-12**: histórico próprio (`Motor/HistoricoCrew.swift`, `historico-sessoes.json`:
   toda sessão que sai da lista, de qualquer origem, somada às do Xirp; as do Crew retomam com
   `claude --resume` no tmux); projetos com Arquivar / Excluir da lista (chaves
   `modulo.sessoes.projetosArquivados` / `projetosExcluidos`; nada toca a pasta nem o Xirp); grade
   até 4 × 4 (`Central/GradeSessoes.swift`: colunas automáticas ou fixas, ordem do Hugo por arraste
   do cabeçalho, menu ou ⌃⌘← ⌃⌘→); falas num campo de texto só (`Central/TextoConversa.swift`,
   NSTextView/TextKit 1: seleção livre dentro da fala, links em azul que só abrem com ⌘ clique);
   **entregáveis da resposta**: o markdown é lido em blocos por `Politicas/BlocosResposta.swift`
   (título com nível, lista, checklist, citação, código com linguagem, tabela com alinhamento) e a
   fala é repartida em partes — o texto corrido continua num campo só (bloco de código com faixa
   de linguagem e "Copiar", caixa/citação/fio desenhados por baixo do texto, arquivo citado como
   `Fontes/X.swift:42` vira link pela pasta da sessão, `Politicas/ArquivosNoTexto.swift`) e cada
   tabela vira `Central/TabelaConversa.swift` + `Central/VistaTabela.swift` (desenhada em AppKit:
   colunas pela largura do conteúdo, número à direita, lista "a · b · c" com um item por linha,
   cabeçalho preso ao rolar, rolagem lateral com setas quando não cabe, clique copia a célula,
   título ordena, filtro, copiar para planilha/Markdown, salvar CSV e ampliar na janela inteira);
   as regras (`Politicas/RegrasTabela.swift`) são puras e conferidas por
   `testes/entregaveis/conferir.sh`; cenas `--so entregavel` (40s–40z);
   terminal ao lado da conversa (divisor arrastável), agora um terminal de verdade: emulador
   SwiftTerm (MIT, pacote fixado em 1.10.0 no `project.yml` — a **única dependência de terceiros**
   do Crew, decisão do Hugo em 2026-11-12; versões 1.20+ exigem rodar um plugin de build do
   pacote, por isso a 1.10.0) com `tmux attach` na sessão. **Falta**: seleção de texto
   atravessando falas diferentes; histórico das sessões encerradas antes desta leva.
   **Conversa fiel ao terminal (2026-11-13)**: o leitor (`Chat/SessionChat.swift`) jogava fora
   toda fala do Hugo que começasse com "<" — e texto colado chega embrulhado em
   `<pasted_content>`: a mensagem aparecia só com as imagens. Agora o texto do pedido passa por
   `Politicas/TextoDoPedido.swift` (regra pura: tira só as marcas de colagem, mostra comando de
   barra como "/x args", deixa fora lembrete do sistema, aviso de tarefa e recado de outra
   sessão — pela `origin.kind` da linha quando existe); pedido mandado no meio do turno com
   imagem (lista de blocos) também entra. O leitor passou a trazer os **passos** do turno
   (`Chat/PassosConversa.swift`, puro: cada `tool_use` com o `tool_result` dele, "pensou por
   Ns", interrupção, duração do turno, modo de permissão do pedido) e a conversa do app os
   mostra em `Central/PassosTurno.swift`: uma linha por ferramenta, sequência de leituras/buscas
   agrupada, saída resumida com "+N linhas" (guarda até 60 linhas por passo; o resto fica no
   terminal), erro em vermelho, bloqueio do modo automático em âmbar; **recolhido numa linha de
   resumo, também enquanto o turno roda (pedido do Hugo); um clique abre**. A ilha continua só com falas
   (`TranscriptReader.messages`). Conferência fora do app: `testes/conversa/conferir.sh` compila
   o leitor de agora e o de antes (do git) e compara os dois com o que o transcript diz que o
   Hugo mandou — em 2026-11-13, 12 transcrições, 161 mensagens: o antigo errava 28, o novo 0.
   Capturas `40p_app_conversa_colada`, `40q_app_conversa_passos` e, com
   `CREW_CAPTURA_TRANSCRIPT=<jsonl>`, `40r_app_conversa_real`. **Não está no transcript**: quais
   passos pediram permissão ao Hugo e foram aprovados (só o modo do turno e o que foi negado).
   **Não testado em uso**: a conversa ao vivo no app instalado (só capturas e a conferência).
   **Navegador e comandos no chat (2026-11-12)**: `Modulos/Navegador/` — navegador dentro do
   Crew com WKWebView (motor do Safari; sem Chromium, sem extensões), ideias do Arc/Zen
   reimplementadas: abas fixadas, um espaço por projeto (as abas ficam no alto, como no Safari), duas abas
   lado a lado, endereço que também busca, busca na página, downloads para a pasta Downloads.
   Abre ao lado da sessão (globo no cabeçalho, "Abrir navegador" no menu) ou na janela inteira
   (globo na barra lateral); ⌘ clique num link da conversa abre nele. Abas em `navegador.json`.
   Ainda não é `Modulo` do registro (sem página de Ajustes nem `crew://`). Comandos: digitar "/"
   sugere os comandos; numa sessão do motor do Crew, o menu que o comando abre no terminal
   (`/model`) é lido da tela do tmux (`Sessoes/Politicas/MenuDoTerminal.swift`, regra pura) e
   vira botões no chat. **Não testado em uso**: página de verdade carregando, logins, downloads,
   e o menu de um comando real (só telas de exemplo).
   **Histórico, sugestões e senhas (2026-11-13)**: `HistoricoNav` guarda as visitas (endereço,
   título, quando, quantas vezes) em `navegador-historico.json`, só no Mac, com teto de 5000
   páginas, pausa e "Limpar histórico…" (no "…" da barra). O campo de endereço
   (`CampoEndereco.swift`, um `NSTextField`) completa em linha o domínio que mais pesa e mostra a
   lista — site, buscar, aba aberta ("Ir para a aba"), páginas, outros sites e, só quando nada
   visitado casa, buscas sugeridas (`BuscasSugeridas`: o texto vai ao serviço de sugestões do
   Google, sem cookies; desliga no "…"). ↑ ↓, Enter, Tab aceita, Esc. Regras puras em
   `Politicas/SugestoesEndereco.swift`, conferidas por `testes/navegador/conferir.sh` (o projeto
   não tem target de teste). **Senhas da Apple** (`SenhasNav.swift`): a chave da barra, ⇧⌘P e
   "Preencher senha…" abrem o painel de senhas do macOS sobre o campo da página; quem
   autentica, lista e digita é o sistema. A entrada é interna do AppKit
   (`NSAutoFillHeuristicController`, conferida antes de chamar) — não há API pública. Sugerir a
   senha sozinho ao focar o campo e passkeys das Chaves do iCloud pedem autorização de navegador
   dada pela Apple: não existem aqui. **Não testado em uso**: o campo com teclado de verdade
   (só a captura `40p_app_navegador_sugestoes` e as regras), e escolher uma senha no painel até
   ela cair no campo (provado fora do app: o painel abre para um campo de página e o texto
   entregue pelo sistema chega ao campo).
   **Importar do Arc, arquivos e envio (2026-11-12)**: `Navegador/ImportadorArc.swift` lê os
   espaços/abas/favoritos do Arc (`StorableSidebar.json`) e os cookies de cada perfil (banco do
   Chromium decifrado com a chave "Arc Safe Storage" do Keychain — o macOS pede ao Hugo); perfil
   que não é o padrão vira um `WKWebsiteDataStore` próprio (`EspacoNav.perfil`); cookie que já
   existe não é trocado e `arc-importado.json` guarda o que entrou, para desfazer. Senhas não
   entram. `Sessoes/Central/ArquivosProjeto.swift`: árvore de arquivos da pasta da sessão ao lado
   da conversa (prévia, mencionar no chat com @). Envio pelo tmux (`TerminalBridge.entregar`):
   pausa antes do Enter e conferência de que o texto saiu do campo (o Enter era engolido como
   parte da colagem). O `tmux set-option` do terminal não aceita alvo com "=".
   **Fecho da leva de 2026-11-12**: atalhos num lugar só (`Central/Atalhos.swift`, com a ordem
   das camadas no cabeçalho) — nenhum depende da barra de menus, que o SwiftUI troca; botão
   "Terminal" = shell novo na pasta da sessão (tmux `crewsh-<id>`), o terminal do Claude Code
   fica no "…"; ⌘N na grade abre sessão em branco no fim dela; painéis da grade redimensionáveis
   pelas divisórias (tamanhos não são guardados entre aberturas); arquivos do projeto como coluna
   ou visualização principal; todo endereço vira link (`Politicas/EnderecosNoTexto.swift`);
   câmera, microfone e localização por site no navegador (`PermissoesNav`; a localização usa uma
   chamada interna do WebKit, não testada).
   **Painel do projeto e Crew sem Xirp (2026-11-12)**: clicar num projeto abre o painel dele no
   lugar da conversa (`Selecao.projeto`, `Sessoes/Central/PainelProjeto*.swift`), com cinco abas:
   Visão geral (sessões abertas, últimas conversas, gasto de hoje e de 30 dias, git, worktrees,
   rotinas, tamanho), Detalhes (nome de exibição, cor, ícone, fixar, nota), Sessões novas (modelo,
   esforço, permissões, instrução fixa via `--append-system-prompt`, isolamento: um comando do
   projeto cria a pasta própria da sessão), Claude Code (CLAUDE.md com edição — só grava no
   "Salvar", dizendo quantas linhas mudam e guardando a versão anterior em `claude-md-anteriores/`;
   servidores MCP, permissões e memórias só leitura) e Avisos (som por projeto, arquivar, excluir).
   Configuração em `projetos.json` (`Motor/ConfigProjetos.swift`); leitura do disco em
   `Motor/LeitorProjeto.swift`, fora da main e só com o painel na tela. "Nova sessão aqui", fixar
   e mover ficam no "…" da linha. Os projetos deixaram de vir do Xirp (só pastas adicionadas e
   sessões abertas) e a sessão nova abre sempre pelo motor do Crew. **Ainda fala com o Xirp**:
   canal de conversa de sessão aberta por ele (`SessionChat`), histórico dele, renomear/parar
   (`AppState`). **Não testado em uso**: abrir sessão com esforço/instrução fixa, o isolamento
   rodando um comando de verdade, gravar um CLAUDE.md, o som silenciado. O painel usa Uso,
   Rotinas e Agentes direto (não há `Eventos` no núcleo ainda).
   **Setores (2026-11-13)**: a janela deixou de ser só sessões — ganhou a barra de setores e a
   tela de trabalho de cada ferramenta (ver "Setores", acima). Os Ajustes ficaram só com a
   configuração: a página do módulo não mostra mais a tela dele, e sim o caminho para ela.
   **Ajustes (janela à parte)** — `JanelaAjustes` + `Central/CentralView.swift`, organizados por
   superfície (2026-11-12) e, desde 2026-11-13, por setor: **Crew** (início com o Mac, permissões do macOS com quem usa cada
   uma, índice dos atalhos globais, contas e chaves — `Ajustes/SettingsView.swift`), **Ilha**
   (personagem, sons, abrir e fechar, e a tabela do que aparece na ilha) e **App** (sessões,
   navegador, atalhos da janela) — as duas em `Ajustes/PaginasSuperficie.swift` — e
   **Ferramentas**: uma página por módulo, agrupadas pelos seis setores, sempre no mesmo formato
   (o que faz, chave de ligar, "Onde aparece", "Na ilha", o botão que abre a tela de trabalho no
   app, ajustes). Abre pelo menu "Ajustes…" (⌘,) e
   pelos atalhos que levam direto à página de um módulo (`Central.abrir(modulo:)`).
3. **Automação** — o Crew controlável de fora: `crew://modulo/acao` (URL scheme), e depois um
   servidor MCP local para que o próprio Claude Code consulte e peça coisas ao Crew
   (ler CPU/disco, pausar música, listar worktrees órfãs). Ação destrutiva pedida por
   automação **sempre** vira um pedido na ilha, aprovado com clique do Hugo.

## 2. Princípios (valem para todo módulo)

1. **Módulo é a unidade.** Funcionalidade nova = pasta nova em `Modulos/` + uma linha no
   registro + o setor dela (`let setor = Setor.…` no módulo): a tela (`central()`) aparece
   sozinha no setor, e a página de configuração, na seção dele nos Ajustes. Não se edita a ilha, o `AppState` nem os ajustes de outro módulo para plugar.
2. **0 % de CPU com a ilha escondida — de verdade, medido.** Nada de polling sem alguém
   olhando. Leitura periódica só por **assinatura** (o `Amostrador` liga quando a primeira
   tela/sinal assina e desliga quando a última sai). Módulo que precise vigiar em segundo
   plano (ex.: alerta de temperatura) declara o custo e usa o intervalo mais longo que
   resolve. Hoje isso **não** está cumprido (ver §6).
3. **Nada destrutivo sem clique.** Apagar, desinstalar, aprovar permissão, mandar e-mail:
   sempre um clique explícito. Limpeza vai para a Lixeira. Agendamento só *avisa*.
4. **Nunca travar o que é do sistema.** O hook nunca trava o Claude Code; o áudio nunca
   fica mudo se o Crew cair (limpeza de emergência + limpeza na abertura); comandos externos
   nunca na main thread.
5. **Sem dependência de terceiros; código de terceiros só com licença compatível.**
   Código MIT: pode portar. Código GPL: **não copiar** — reimplementar a partir da
   técnica (APIs da Apple não têm dono), para o Crew poder ser distribuído um dia.
   **Motores externos (2026-11-12)**: ferramenta que não é Swift (Node, Python) não entra no
   binário — roda como **processo à parte**, que o Crew instala, liga, desliga e mostra nos
   Ajustes. Vale para o que não dá para refazer nativo (Remotion, VoiceStudio). Regras: nada
   sobe sozinho (liga no primeiro uso, desliga parado); fica em
   `~/Library/Application Support/NotchBuddy/motores/<nome>/`; o Crew fala com ele por CLI ou
   HTTP local; código AGPL/GPL **nunca** é copiado para dentro do Crew (rodar ao lado pode).
   O que dá para refazer com API da Apple continua sendo refeito (ditado, gravação de tela).
6. **Português** em UI, comentários e documentação. Nomes técnicos herdados ficam (ver CLAUDE.md).

## 3. Estrutura de pastas

```
NotchBuddy/Sources/
├── App/          entrada e montagem: NotchBuddyApp, AppDelegate, Registro de módulos, CaptureTool
├── Nucleo/       infraestrutura sem UI, usada por todos
│                 hoje: AppState (a desmontar), Keychain
│                 vem:  Modulo, Registro, Arbitro, Ajuste, Amostrador, Teclas, Permissoes,
│                       ProcessRunner, Log, Eventos
├── Ilha/         a janela do notch: controlador, máquina de estados, raiz, cabeçalho
│   └── Componentes/   peças visuais compartilhadas (cartões, botões, markdown…)
├── Central/      (vem) a janela grande, com barra lateral por pilar
├── Ajustes/      ajustes atuais (migram para a Central)
├── Homie/        o personagem (BotEngine/BotStyle; desenho em HomieCorpo/HomieBone/HomieTons), saudação, sons
└── Modulos/
    ├── Sessoes/       Claude Code: HookServer, Projetos, Telas/, Chat/
    ├── Arquivos/      soltar arquivo, upload, e-mail
    ├── Midia/         Spotify/Música
    ├── Nivel/         brilho e volume do sistema (vira Tela + Áudio)
    ├── Integracoes/   <Servico>/{Poller, Views} — n8n, Vercel, Resend, GitHub, Stripe, Cal.com, Notion
    ├── Busca/         API do Claude + busca (hoje sem uso — decidir se fica)
    └── (vêm) Sistema/ Audio/ Disco/ Agentes/ Modelos/ Uso/
```

**Dentro de cada módulo**, o mesmo formato, sempre:

```
Modulos/<Nome>/
├── <Nome>Modulo.swift     identidade + o que oferece (abas, sinais, ajustes, ações)
├── <Nome>Servico.swift    dados e regras, sem UI (@Observable, @MainActor; trabalho pesado fora da main)
├── Telas/                 o que aparece na ilha
├── Central/               o que aparece na janela Central
└── Politicas/             regras puras e testáveis (o que pode apagar, prioridades…) — quando houver
```

Regra de dependência: `Modulos/X` usa `Nucleo/`, `Ilha/Componentes/` e `Homie/`; **nunca**
outro módulo diretamente — conversa por `Eventos` do núcleo. `Ilha/` não conhece módulo
nenhum pelo nome: só o protocolo.

> Quando passar de ~10 módulos, cada módulo pode virar um target/pacote local (SwiftPM) e o
> compilador passa a garantir a regra de dependência. Não antes: hoje custaria mais do que paga.

## 4. As peças do núcleo

### `Modulo` — o contrato

```swift
@MainActor
protocol Modulo: AnyObject {
    static var id: String { get }            // "sistema", "audio"… (prefixo das chaves de ajuste)
    var nome: String { get }                 // "Sistema"
    var icone: String { get }                // SF Symbol
    var pilar: Pilar { get }                 // .ia | .mac | .criar | .eu (só padrão do setor)
    var setor: Setor { get }                 // onde mora no app e nos Ajustes (Nucleo/Setor.swift)
    var permissoes: [Permissao] { get }      // .acessibilidade, .discoTotal, .capturaAudio, .automacao(app)

    func iniciar()                           // chamado ao ligar o módulo
    func parar()                             // ao desligar: solta timers, taps, observadores

    var abas: [AbaIlha] { get }              // telas na ilha expandida (0…n), cada uma com altura e posição do Homie
    var central: AnyView? { get }            // tela de trabalho, no setor dele (janela do Crew)
    var ajustes: AnyView? { get }            // seção de ajustes
    var acoes: [Acao] { get }                // o que dá para chamar por atalho, crew:// e MCP
}
```

O `Registro` (em `App/`) é a **única** lista de módulos. Ligar/desligar módulo vira ajuste
genérico (`modulo.<id>.ligado`), e a ilha, a Central e os atalhos se montam a partir dele.

### `Arbitro` — quem aparece na ilha compacta

Hoje o tamanho e o conteúdo da ilha fechada são decididos por `if`s espalhados
(`islandSize`, `botPosition`, `nivelNaIlha`, `holdVisible`, `baseMode`). Passa a ser:

- módulos **publicam sinais**: `Sinal(id, prioridade, conteudo, duracao, seguraAberta, homie)`;
- o árbitro escolhe **um** (maior prioridade; empate → mais recente) e a ilha desenha;
- prioridades fixas, da mais alta: **aprovação/pergunta** → **erro** → **HUD** (volume,
  brilho, volume por app; passageiro) → **alerta** (disco cheio, CPU quente, AirPods
  conectou) → **atividade** (música, sessões rodando) → **ocioso**;
- o sinal também diz como o Homie reage (fones, celular, suando, dormindo).

Isso substitui as duas máquinas de estado paralelas (`IslandMode` × `IslandStateMachine`)
por uma: a FSM decide *se* a ilha está aberta; o árbitro decide *o quê* mostra.

### `Ajuste<T>` — ajustes por módulo

Property wrapper sobre `UserDefaults` com chave `modulo.<id>.<nome>`. Acaba com o `didSet` +
carga manual no `init` do `AppState`. Chaves antigas são migradas uma vez (não se perde o
que o Hugo já configurou). Segredos continuam no Keychain (`Nucleo/Keychain.swift`).

### Ilha alta por módulo

`Modulo.pedirAlturaAba(_:)` → `AppState.alturaAba`: a aba do módulo na frente pede uma altura
maior (até a do chat esticado); `islandSize` usa essa altura, a ilha anima, o painel cresce antes
e encolhe depois (o mesmo `fitPanel` do chat). Fechar a ilha, trocar de tela ou de módulo volta a
`nil` sozinho.

**Padrão (2026-10-06): expandir é o mesmo cartão crescendo.** O Homie e o topo da tela ficam
exatamente onde estavam; o que é novo aparece embaixo. E toda tela que cresce tem o **elástico do
chat** (`Ilha/ElasticoIlha.swift`): rolar para baixo estica a ilha seguindo o dedo e trava aberta;
rolar para cima, com a lista no fim, encolhe e trava fechada. Para dar isso a uma tela:
- aba de módulo: declarar `alturaExpandida` no módulo (e `expandirAba`/`recolherAba` se abrir
  fizer mais que pedir a altura);
- outra tela da ilha: um caso em `ElasticoIlha.alvo()` e `IslandView.cresce`;
- toda lista rolável dentro dela: `.rolagemDaIlha()` (avisa quando chegou ao fim).

### `Amostrador` — leitura periódica sob demanda

Fonte de leitura com intervalo (CPU a cada 1 s, disco a cada 30 s…) que **só roda enquanto
tem assinante**. A aba de Sistema assina ao aparecer e solta ao sumir. Um alerta em segundo
plano assina com intervalo longo. Ninguém assinando = nenhum timer.

### `Teclas` — um único interceptador

Hoje o `NivelService` tem o seu `CGEventTap`. Áudio por app, atalhos de volume do app tocando
e os atalhos do Crew vão precisar do mesmo. Um só tap no núcleo, com vigia (religa se o
macOS desligar), e os módulos registram o que querem tratar.

### `Permissoes`, `ProcessRunner`, `Log`, `Eventos`

- **Permissoes**: estado e pedido de Acessibilidade, Acesso Total ao Disco, Captura de Áudio,
  Automação. A Central mostra o que falta e por que cada módulo pede.
- **ProcessRunner**: roda `osascript`, `du`, `git`, `xcrun`, `xirp`
  sem travar (drena saída, timeout, SIGTERM→SIGKILL). Substitui as 4 cópias atuais.
- **Log**: `os.Logger` com subsistema `fr.louisraille.NotchBuddy` e categoria por módulo.
  Substitui `NivelService.log` e `HookServer.nbLog`.
- **Eventos**: enum tipado em vez dos 15 `Notification.Name` soltos com `object as? X`.

### Estado

`AppState` hoje é o balde de tudo e qualquer `@Published` redesenha a ilha inteira. Destino:
cada módulo tem o seu serviço `@Observable` (macOS 15 suporta) e as telas observam só o que
usam; `AppState` encolhe para o estado da ilha (modo, aba atual, mouse). Migração módulo a
módulo, sem big-bang.

## 5. Roteiro

Cada passo é uma leva própria (sessão, worktree, instalação, aprovação, integração).
Passo da fundação **não muda o que o Hugo vê** — a prova é o app igual e a CPU menor.

### Fase 0 — Fundação

| Passo | Entrega | Estado |
|---|---|---|
| 0a | código em pastas por área; `IslandViewContent` (3755 linhas) dividido por módulo | **feito** (código idêntico, só movido) |
| 0b | CPU em repouso | **feito** (2026-10-04). Medido em 60 s: antes 34 % (27 h aberto) / 11–16 % (recém-aberto); depois **8–11 %** com a ilha compacta. Mouse por evento (laço de 60 Hz só perto da ilha); Homie compacto a 24 quadros e mini-Homies a 12 num relógio único, com a física no ritmo de antes; abas invisíveis não animam; barra de contagem só aberta; título do transcript lido só no pedaço novo; nome no Xirp só das sessões ativas; "!"/"?" do selo sem layout de texto por quadro |
| 0b2 | Homie desenhado fora do ciclo do SwiftUI (camada própria). O que sobra dos 8–11 % é o SwiftUI refazendo o layout e o commit da janela a cada quadro (o desenho em si é ~5 % disso). Hospedagem SwiftUI separada **não** resolve (testado: piorou) | |
| 0c | núcleo: `Modulo`, `Registro`, `Ajustes`, `Log`, `Processo`, `Amostrador`; aba de módulo na ilha (`IslandView.modulo` + `AppState.moduloAberto`), vinda do registro | **feito** (2026-10-04). Primeiro módulo no formato novo: **Sistema** |
| 0d | ilha: só a aba ativa montada; abas dos módulos vindas do registro; layout sem `!` | **feito** (2026-10-05): antes todas as ~20 telas ficavam montadas (opacidade 0); agora só a da frente, com a mesma transição. `IslandConst.layout(_:)` cai no layout padrão em vez de derrubar o app. Próximo: com 8+ abas o cabeçalho enche — abas de módulo além de 4 vão para um menu "mais" |
| 0d2 | cabeçalho que desvia do notch | **feito** (2026-10-05): nada clicável embaixo da câmera — abas fixas à esquerda; à direita, até 2 módulos favoritos + botão de grade (tela `.modulos` com todos os módulos) + ações. Largura real do notch (`state.notchWidth`) + 12 pt de folga de cada lado |
| 0e | árbitro da ilha compacta + FSM única | **árbitro feito** (2026-10-04): `Nucleo/Arbitro.swift` com dois lugares na ilha fechada — **barra** (embaixo do notch) e **canto** (à direita) — e prioridades indicador < atividade < alerta < hud. Brilho/volume e a capa da música viraram sinais; Sistema publica avisos por evento (bateria 10 %/5 %, memória crítica) e um indicador opcional no canto. Falta: unificar `IslandMode` × `IslandStateMachine` e aprovação/pergunta como sinal |
| 0f | recursos antigos como módulos | **feito** (2026-10-05): Claude Code (hooks), Brilho e volume, Música e Arquivos têm página na Central com os ajustes deles; marcados `podeDesligar = false` (coração do Crew). As abas deles seguem fixas no cabeçalho; o estado ainda mora no `AppState` (desmontar é trabalho contínuo) |
| 0g | janela Central com barra lateral; Ajustes migram para ela | **base feita**: Central com barra lateral por pilar, página por módulo (liga/desliga, tela, ajustes) e "Geral" com os ajustes de sempre. Falta migrar os ajustes de cada recurso antigo para o módulo dele |
| 0h | limpeza | **feito** (2026-10-04): target `CrewAppStore` e todo `#if APPSTORE` removidos (fica só a versão sem sandbox); texto da permissão de Acessibilidade em português. `Busca/` fica como base de um futuro módulo de IA (perguntar ao Claude pela ilha). `SPEC.md` (francês, protótipo) segue desatualizado — este documento é a referência |

### Fase 1 — Ganhos baratos

- **Sistema** — **aba e Central feitas** (2026-10-04): anéis de CPU, memória e
  temperatura, histórico, núcleos E/P e top processos na ilha; painel completo na Central
  (carga, memória detalhada, rede, disco, bateria com saúde e ciclos). Falta: indicador na ilha
  compacta e alertas (dependem do árbitro, 0e). Ver §7.
  **Monitor de atividade** (2026-10-05): botão no canto da aba expande a ilha (450 pt) com abas
  CPU · Memória · Energia · Disco · Rede, todos os processos (ícone e nome do app), colunas por aba
  ordenáveis, busca, rodapé com os totais (carga, pressão, bateria, E/S de disco, pacotes) e
  detalhe (pid, usuário, caminho, início) com Encerrar (SIGTERM) / Forçar (SIGKILL), sempre com
  confirmação e conferindo que o pid ainda é o mesmo processo. Processos de outro usuário,
  `loginwindow` e o próprio Crew: ação desabilitada com o motivo. Mesma tela na Central (no lugar
  de "processos que mais gastam"). Também `crew://sistema/monitor`. Leitura só com o monitor na
  tela, a cada 2 s: `sysctl KERN_PROC_ALL` + `proc_pid_rusage` V6 + `PROC_PIDTASKINFO` nos
  processos do Hugo; os de outro usuário (209 de 720 aqui) o macOS nega sem root — vêm do
  `/bin/ps` (setuid root; só tempo de CPU e residente) pelo `Processo.rodar`. Custo medido por
  leitura: ~5 ms de CPU no Crew + ~12 ms no ps. **Fica de fora**: bytes de rede por processo (só o
  `nettop` tem o direito privado `com.apple.private.network.statistics`; a aba Rede mostra sockets
  abertos); threads/disco/energia dos processos do sistema; kernel_task.
- **Disco** — **aba e Central feitas** (2026-10-04): espaço livre/total; "recuperável com
  segurança" por varredura sob demanda (botão, fora da main, `du` com no máximo 4 lotes ao
  mesmo tempo) dos caches de desenvolvimento (Xcode, npm, pnpm, Yarn, brew, Gradle, Cargo, Go,
  SwiftPM, CocoaPods…) e de apps (só rótulos "seguro"), mais os registros de
  `~/Library/Logs`. Política de segurança (allowlist, nunca-apagar,
  só-esvaziar, caches de conta/iCloud/chaveiro bloqueados), revalidação antes de confirmar e
  de novo imediatamente antes de mover; tudo para a Lixeira; resultado mostra o movido e o
  delta medido do volume. Sem Acesso Total ao Disco fica fora de contêineres, caches de mídia e
  pastas protegidas (nenhum pedido do macOS). Regra estrita:
  `workspaceStorage` do VS Code/Cursor e `Zed/db` não saem; `~/.gem` é "conferir".
  **Fase 3 do Disco feita** (2026-10-04), na página da Central (a aba ganhou só "+N em projetos"):
  **projetos parados** (artefatos do catálogo em `~/dev`, `~/Developer`, `~/projetos`…,
  profundidade 4, sem links/ocultas; parado há 1/3/6/12 meses pela última atividade do projeto
  inteiro, git incluso; nunca aparece com processo dentro, lock ou mudança não commitada
  (`git --no-optional-locks status`), nem pasta versionada nem `.coucou-sessoes`; sem lockfile =
  desmarcado; comando de reinstalar em cada linha); **simuladores** (`simctl`, só no botão, pula os
  ligados, apagar é definitivo e diz isso; some sem Xcode); **arquivos grandes** (≥ 50 MB a 1 GB,
  "usado há mais de", Quick Look e Finder, nunca marcado; sem Acesso Total só Filmes/Música/Imagens;
  pula bibliotecas, pacotes, pastas de projeto e arquivo só no iCloud); **duplicados** (sob demanda,
  ≥ 1 MB, tamanho → amostra 64 KB início/fim → SHA-256 inteiro, sem hard links; sugestão de qual
  manter trocável; progresso e cancelar). Tudo revalidado antes de confirmar e antes de mover.
  **Fica de fora**: desinstalador, limpeza agendada, esvaziar a Lixeira pelo Crew, aviso de disco
  quase cheio na compacta, exclusões por caminho, duplicados abaixo de 1 MB.
- **Homies** — **leva 1 feita** (2026-11-13): quem faz, separado da sessão. Um Homie
  (`Modulos/Homies/`) tem nome, função, instrução, modelo e uma **pasta só dele** em
  `~/Library/Application Support/NotchBuddy/Homies/<nome>/` — `CLAUDE.md` (guia, escrito uma vez
  e nunca por cima), `.mcp.json`, `.claude/skills/` e `notas/`: MCPs, skills e memória por Homie
  saem do que o Claude Code já lê na pasta, sem formato novo. Conversar = sessão do motor do Crew
  nessa pasta, com a identidade em `--append-system-prompt` e o nome do Homie em `--name`;
  "Continuar a última" retoma o `session_id` guardado. Lista em `homies.json`; na primeira vez
  nasce o assistente pessoal ("Homie"). Nenhum Homie abre sessão sozinho. Regras puras em
  `Politicas/PoliticaHomies.swift`. **Falta** (levas seguintes): perfil de navegador por Homie e
  ferramentas MCP para o Claude dirigir o navegador; rotinas e fila por Homie; conversa entre
  Homies; as sessões de um Homie ainda aparecem na lista geral, como um projeto qualquer.
  **Não testado em uso**: a primeira abertura numa pasta nova (o Claude Code pergunta se confia
  nela) e o "Continuar a última".
  **Leva 2 (2026-11-16)** — tela em equipe + conversa (a conversa do Homie fica na própria
  tela); Homie novo nasce de um **briefing** (uma conversa de montagem escreve guia, skills,
  MCPs e a ficha `homie.json`); e (rotina por agente;
  canal com líder) **rotinas e time**:
  - **Rotina do Homie** = uma `Rotina` do módulo Rotinas com `homie` preenchido (mesma agenda,
    chave, pausa e histórico). Quem configura é o Hugo, na aba "Rotinas" do Homie (nome, o que
    ele entrega, quando, se enxerga os MCPs dele). A sessão abre na pasta dele, sem ninguém por
    perto, com limites fixos (`HomiesServico.planoDaRotina`): edita só na pasta dele, sem shell
    (`Bash` negado), sem MCP (ou só os do `.mcp.json` dele), time só para leitura. O que pedir
    permissão para e espera o Hugo.
  - **Página** — a rotina escreve `paginas/<rotina>.json` (título, resumo em markdown, até 6
    ações propostas, `semNovidade`). O Crew espera o arquivo só enquanto a rotina roda, avisa
    no notch, mostra na aba "Hoje" e fecha a sessão. **Nenhuma ação é executada**: "Fazer" abre
    uma conversa com quem deve fazer, já com o pedido; "Dispensar" só marca. As decisões ficam
    em `paginas/<rotina>.decisoes.json` e valem só para aquela página.
  - **Time** — `Homie.chefe` (o campo "Responde a"). Quem coordena abre a sessão enxergando a
    pasta de cada um do time e com a instrução de passar trabalho por subagente (um por Homie,
    que lê o guia e as notas da própria pasta) e responder numa voz só. Limite conhecido: o
    subagente usa as ferramentas da sessão do coordenador, não os MCPs da pasta do membro.
  - Regras em `Politicas/PoliticaHomies.swift`, conferidas por `testes/homies/conferir.sh`.
- **Agentes** — **feito** (2026-10-04): worktrees órfãs (Claude Code, Cursor, Codex, Conductor,
  T3) com uma regra só — as que o repositório não lista mais (conferido em disco, sem
  rodar git), sem processo com cwd dentro, sem lock e fora de janelas do Cursor; volume
  desmontado = não aparece; `.coucou-sessoes/` nunca entra. Aba na ilha (quantas órfãs, espaço,
  ativas recentes, "Revisar") e página na Central (marcar e mover para a Lixeira com
  confirmação; worktrees ativas por projeto com branch, idade e quem está usando, só leitura).
  Varre ao abrir a aba/página ou no botão, fora da main. "Revisar" abre a Central na página do
  módulo. Falta: sobras do Cursor em `~/.cursor/projects`; aviso na ilha compacta quando
  aparecer órfã (pede varredura em segundo plano — hoje só varre com tela aberta).
- **Modelos**: Ollama/LM Studio — **feito** (2026-10-04): aba na ilha (total em disco, nº de
  modelos, o carregado agora com a memória) e Central (lista com tamanho, quanto libera,
  modificação; remover com confirmação: `ollama rm` com o servidor de pé — definitivo — ou
  manifesto + blobs exclusivos para a Lixeira). Leitura só com tela olhando; `/api/ps` só em
  127.0.0.1, nunca sobe o servidor. Liga sozinho só se o Mac tem Ollama/LM Studio (este não
  tem: vem desligado). Falta: testar com modelos de verdade; LM Studio carregado (o servidor
  dele, porta 1234) não é lido; `OLLAMA_MODELS` definido só no shell não chega ao app aberto
  pelo Finder.
- **Áudio barato** — **feito** (2026-10-04), módulo `Modulos/Audio/`: saídas e entradas com
  transporte (embutido, Bluetooth, USB, HDMI/DisplayPort, AirPlay…), troca em um clique na ilha
  e na Central (alertas do sistema acompanham, ajustável), tudo por evento do Core Audio (sem
  timer). Trava do microfone ligada por padrão no embutido: dispositivo recém-conectado (≤ 10 s)
  que vira a entrada é desfeito; troca manual é respeitada; eco das trocas do Crew ignorado;
  desiste após 3 devoluções em 20 s; travado ausente = nada forçado, e quando volta a entrada
  volta para ele. Aviso passageiro na ilha fechada pelo árbitro (`audio.aviso`, prioridade
  alerta, 4 s; desligável). Central mostra quais saídas não têm volume pelo macOS. Falta:
  prioridade de dispositivos (troca automática de saída); volume em TV/DAC sem controle de
  hardware (precisa de tap + aggregate, fase 2); testar com AirPods de verdade (este Mac só tem
  os dispositivos embutidos).

  **Ferramentas (2026-11-16).** Um catálogo de servidores
  MCP: conectar grava o endereço, o login é no navegador. Decisão do Hugo: conecta-se uma vez
  no módulo (página Ferramentas, ao pé da equipe) e em cada Homie só se ativa ou desativa.
  Quem liga, entra e tira é o Claude Code (`claude mcp add/login/remove --scope local`): no
  módulo, numa pasta neutra (`NotchBuddy/ferramentas`); ao ativar, na pasta do Homie. Vale só
  para quem ativou, sem aprovação de projeto, e o Crew não guarda credencial. Não confirmado:
  se o login feito no módulo vale para o Homie sem pedir de novo (há "Entrar" na linha dele).
  Catálogo curto em `Politicas/FerramentasHomie.swift`, só com o que conecta sem chave digitada;
  "Outra ferramenta" aceita qualquer endereço https. A rotina com MCPs recebe um arquivo só com
  as ferramentas dele (`paginas/.ferramentas.json`, gerado a cada execução). Não testado no app:
  a tela, o login pelo botão e o uso das ferramentas dentro de uma rotina.

- **Uso** (custo do Claude Code) — **feito** (2026-10-04), módulo `Modulos/Uso/`: lê os
  transcripts locais (`~/.claude/projects/**/*.jsonl`, subagentes somados à sessão que os chamou),
  sem rede, fora da main e só o que cresceu desde a última leitura; o somado fica em
  `~/Library/Application Support/NotchBuddy/uso.json` (60 dias). Mensagem repetida conta uma vez
  (mesmo arquivo: vale a última linha; cópia em sessão retomada: ignorada) — conferido contra uma
  soma independente: 7 dias batem a menos de 0,03 % (a diferença é o que chegou entre as duas
  leituras). Primeira leitura completa deste Mac: 608 arquivos, 1,05 GB em 2,8 s (5,4 s com o Mac
  ocupado); depois, ~0,03 s. Aba na ilha (hoje, 7 dias em barras, projeto que mais gastou hoje,
  "Detalhes" → Central) e Central (30 dias em custo ou tokens, por projeto, por modelo, 10 sessões
  mais caras da semana com título). Custo = estimativa pelos preços de API em
  `Uso/Politicas/Precos.swift` (conferidos em 05/10/2026); modelo sem preço fica só em tokens.
  Alerta opcional (desligado por padrão) do custo do dia na barra, por FSEvents em
  `~/.claude/projects` (no máximo um aviso por minuto, sem timer). Falta: testar o alerta com uso
  real; preço de contexto longo e de modo rápido fora do Opus não estão na tabela; Codex/Cursor.

- **Apps** — **feito** (2026-10-04), módulo `Modulos/Apps/`, só Central + aviso na ilha
  fechada (sem aba: o cabeçalho está cheio). Desinstalador: apps de /Applications e ~/Applications (um
  nível de subpasta; sem os do sistema/volume só de leitura e sem o Crew), tamanho e último uso pelo
  Spotlight (`du` como reserva); sobras com o casamento estrito (bundle id e grupo marcados; só
  por nome inteiro, desmarcado; pasta dividida com outro app instalado não sai) em 10 raízes de
  `~/Library` (inclui WebKit) e 3 de `/Library`. Portão próprio (pacote numa raiz de apps ou filho direto
  de uma raiz de sobras) com os vetos da `PoliticaSeguranca` do Disco (usada sem mudar nada lá). App
  aberto: `terminate()` e até 3 s; não fechou = nada sai; pacote que não sai = sobras ficam. Sem helper
  root: o que esbarra em permissão aparece marcado "sem permissão" e o resultado diz o que ficou e por
  quê. Sobras de apps já apagados (regra estrita: id com 3+ partes, SDKs embutidos e helpers do
  mesmo fabricante de um app instalado têm dono; 30+ dias parado; nada marcado). Aviso de app apagado:
  FSEvents em /Applications e ~/Applications (ligado por padrão), espera 10 s e confere se o mesmo id
  voltou ou há outra cópia; com sobras, sinal `apps.apagado` na barra (10 s; clique abre a Central) e
  "apagados recentemente" (7 dias). Testado: app falso em ~/Applications apagado → aviso em 10 s;
  apagado e reposto em 4 s → sem aviso; CPU com a vigia ligada 8,1–9,4 % (igual), nada do módulo no
  `sample`. Falta: sem Acesso Total ao Disco, Contêineres e Contêineres de grupo ficam de fora (apps da
  App Store quase não aparecem limpos); mover .app de terceiros pode exigir "Gerenciamento de Apps"
  para o Crew (não testado com app de verdade — nada do Hugo foi removido); seguir o pacote pela
  Lixeira por inode não foi feito.

- **Captura** (inspirado na parte de captura do ScreenDrop; reimplementado, nenhum código copiado) —
  **feito** (2026-11-09), módulo `Modulos/Captura/`, pilar Mac, sem aba na ilha (página nos Ajustes +
  prévia flutuante + aviso na ilha fechada), ligado por padrão, pode desligar. Quem fotografa é o
  `/usr/sbin/screencapture` do macOS via `Processo.rodar` (`-x -t png`, `-i` área, `-i -W` janela, sem
  `-i` a tela onde o mouse está; teto de 3 min na seleção): ele cuida da seleção e da permissão de
  Gravação de Tela. Sem arquivo no fim = cancelou (Esc) ou falta a permissão
  (`CGPreflightScreenCaptureAccess`), e a página e a ilha dizem qual. Só captura por atalho, botão ou
  `crew://captura/area|janela|tela|texto`. Arquivos em `~/Library/Application Support/NotchBuddy/capturas/`
  ("Captura AAAA-MM-DD HH.MM.SS.png"); passando do limite (padrão 50) as mais antigas vão para a
  Lixeira; numa pasta escolhida pelo Hugo o Crew nunca tira nada. **Texto da tela**: área → Vision
  (`VNRecognizeTextRequest` preciso, pt-BR + en-US, linhas reordenadas de cima para baixo e da esquerda
  para a direita em `PoliticaCaptura.emOrdemDeLeitura`) → área de transferência; a imagem temporária é
  apagada; sinal `captura.aviso` na barra ("Texto copiado: …", 3,5 s). **Pilha de prévias**
  (`Telas/PilhaPrevias.swift`): `NSPanel` que não ativa o Crew, no canto de baixo à direita da tela do
  mouse, fora das capturas seguintes (`sharingType = .none`), some no tempo dos ajustes (padrão 6 s)
  salvo mouse em cima ou fixada; até 5 empilhadas. Por prévia: copiar imagem, salvar como, arrastar o
  arquivo, fixar, Lixeira, copiar texto, anotar e **mandar para a sessão** em foco (nome dela no botão;
  `Xirp.sessionId` + `TerminalBridge.channel` + `TerminalBridge.send(_, anexos:via:)`, o caminho dos
  anexos do chat; só no clique). **Anotar** (`Telas/Anotar.swift` + `Politicas/Anotacoes.swift`): seta,
  retângulo, traço livre, etiqueta de texto e tarja sólida, 6 cores, desfazer; o mesmo desenho
  (CoreGraphics) vale na tela e na cópia final; o original fica intocado e a anotada é salva ao lado
  ("…-anotada.png"). **Atalhos** (Carbon `RegisterEventHotKey`, ligados por padrão): ⌃⌥⌘4 área, ⌃⌥⌘5
  janela, ⌃⌥⌘3 tela, ⌃⌥⌘2 texto; cada um com chave e gravador de combinação próprios; combinação
  recusada aparece na página. Custo parado: nenhum timer, nenhuma vigia de pasta — só os atalhos
  registrados no sistema e disparos únicos do prazo da prévia. Conferido: build sem erro nem aviso
  novo; OCR e ordem de leitura com imagens desenhadas em código (`CapturaExemplo`, binário de teste
  avulso); a composição das anotações (mesmo tamanho do original, tarja sem texto legível por baixo);
  página, pilha, anotador e aviso da ilha pelo modo de capturas (cenas 42…42e). **Não testado** (pede
  tela e permissão de verdade, e o app instalado): o `screencapture` chamado pelo Crew e a detecção
  cancelou × sem permissão; os atalhos apertados de fato (inclusive com os do Áudio ligados — o
  tratador fica no alvo do despachante para não ser engolido pelo deles); painel sem roubar foco,
  clique e arrastar para fora; a entrega à sessão por cada canal; o gravador de combinação; tela
  inteira com mais de um monitor (`-D`). Falta: itens de captura no menu da barra de status (o
  `AppDelegate` monta o menu fechado; não há gancho de módulo para isso); texto em colunas sai
  intercalado linha a linha; a entrega à sessão sempre envia (o `TerminalBridge.send` dá Enter) — não
  há "só anexar"; gravação de tela, estúdio, teleprompter e nuvem ficaram de fora de propósito.

### Pilar Eu — Diário (**feito**, 2026-10-05)

Módulo `Modulos/Diario/`, primeiro do pilar "Eu" (2º atalho ao lado da câmera, logo depois de Automação
no registro). Registra, só por evento: pedidos e entregas das sessões (diferença em `AppState.$tasks`;
sessão restaurada ao abrir o Crew não conta de novo), notas do Hugo (campo na aba; `crew://diario/nota?texto=`)
e tempo por app em foco (NSWorkspace; pausa com tela apagada/bloqueada/Mac dormindo; o Crew não conta).
Um JSON por dia em `~/Library/Application Support/NotchBuddy/diario/AAAA-MM-DD.json`, gravação com folga de
3 s; modo de capturas não grava.
**Triagem em tempo real** (o coração): cada nota, pedido em que o Hugo fala de si ("depois eu aviso a
Carla") e entrega passa pelo modelo local (`Politicas/TriagemIA.swift`, `@Generable`): tipo (tarefa,
compromisso, esperando o Hugo, trabalho do agente, registro), ação, ação curta (barra), pessoa, trecho do
prazo e urgência. A hora do prazo sai de regra (`Politicas/Prazos.swift`: "meio-dia", "amanhã cedo",
"daqui 30 min", "sexta", "às 3"…), não do modelo. Pendências (aberta/feita/adiada/ignorada) moram no
arquivo do dia em que nasceram e seguem nos dias seguintes enquanto abertas (30 dias). Avisos: "agora" na
hora; com prazo, N min antes (ajuste, padrão 15) e no prazo; adiada volta na hora marcada; tudo com UM
`DispatchSourceTimer` de relógio de parede para o próximo evento, recalculado ao acordar. O aviso (barra,
`diario.aviso`) diz a ação curta, quando e de onde veio; clique abre a aba com Feito · Adiar (30 min/1 h/
amanhã) · Ignorar. Sessão que esperava o Hugo fecha sozinha quando ele responde a ela.
**Resumo do dia** às 18h (ajuste; outro timer único; perdido com o Mac dormindo sai ao acordar) ou no botão:
Feito pelo modelo local (entregas + commits do dia por projeto, compactados a ~3500 caracteres), Aberto e
Prometido por regra a partir das pendências; sem modelo, contagens e listas. Commits só na hora do resumo
(`git log --all --since` por raiz de projeto do dia, `user.email` de cada repo, `Processo.rodar`).
Central: pendências, resumo, linha do tempo com filtro, tempo por app, commits e ajustes (cada fonte
desliga e **apaga** o guardado dela, com confirmação). CPU parado igual ao de antes (9–12 % com a ilha
compacta, o mesmo do 0b; o Diário só aparece no `sample` quando grava um evento).
**Diário expandido** (2026-10-06): botão no canto da aba (o mesmo do monitor do Sistema, via
`Modulo.pedirAlturaAba`, 450 pt) abre o Diário inteiro na ilha — Pendências (todas as abertas/adiadas
com detalhe, edição e as 3 saídas; resolvidas de hoje com reabrir), Hoje (linha do tempo filtrável;
a entrada abre o texto inteiro; nota edita e apaga com confirmação; qualquer entrada vira pendência
"manual" com prazo em um clique — a limpeza automática não mexe nelas) e Resumo (gerar de novo).
"Anotar…" no topo; recolher, fechar a ilha ou trocar de aba volta ao normal. Linhas da aba normal,
"+N" e "Resumir o dia" abrem direto no segmento certo; `crew://diario/expandir?segmento=`.
Tempo por app: tela bloqueada não conta mais (loginwindow e protetor de tela ignorados; a pausa só
sai quando saem todos os motivos — tela, sono, sessão, bloqueio — conferindo
`CGSSessionScreenIsLocked`); o tempo do loginwindow já gravado é tirado ao carregar o dia.
Falta: aprender com o que o Hugo ignora (compromisso 4: cobrar menos o que ele ignora); pendências de
WhatsApp/e-mail (módulo Compromissos); notificação do macOS quando a ilha está escondida.

### Voz — ditado, segurar para falar e leitura (**código feito**, 2026-11-09; falta o teste com microfone)

Módulo `Modulos/Voz/` (pilar IA, sem aba na ilha, ligado por padrão, pode desligar). Inspirado no
ditado / push-to-talk / leitura do OpenMausBot e do rakazo — reimplementado com as APIs da Apple,
nenhum código deles.
- **Ditado** (`VozServico` + `Leitores/CapturaVoz.swift`): `SFSpeechRecognizer` + `AVAudioEngine`,
  pt-BR por padrão (ajuste entre os idiomas do reconhecedor). Reconhecimento **exigido no aparelho**
  sempre que o Mac suporta o idioma; se não suporta, o ditado para com o motivo na tela e **não**
  cai para a rede — só com o ajuste "permitir reconhecimento pela Apple (rede)" (desligado por
  padrão). Publica texto parcial, texto final, nível (medidor) e estado (parado / pedindo permissão
  / ouvindo / finalizando / erro com motivo). O motor de áudio, o tap e o reconhecedor existem só
  durante o ditado (um `CapturaVoz` por ditado, fora do MainActor; eventos voltam para a main como
  valores); parado não há motor, tap nem timer. O único relógio é um disparo de 2,5 s ao parar,
  caso o reconhecedor não feche o texto. Microfone e Reconhecimento de Fala são pedidos só no
  primeiro uso, depois de um balão que explica, e nunca por atalho ou `crew://`.
- **`BotaoDitar(texto:estilo:)`** e **`BotaoOuvir(texto:estilo:)`** (`Telas/BotaoDitar.swift`):
  peças de uma linha para qualquer tela. Cada botão é um "dono" do ditado: só quem começou recebe o
  texto, que entra no fim do campo (o parcial é trocado até o final chegar). Somem com o módulo
  desligado.
- **Segurar para falar** (`AtalhoFalar` + `VozGlobal`; desligado por padrão; ⌃⌥Espaço, ou ⌃⌥⌘ /
  ⌥⌘ Espaço): Carbon `RegisterEventHotKey` com apertar e soltar. O texto chega na barra da ilha
  fechada (sinal `voz.ditado`, prioridade hud, Homie de fones) e, ao soltar, vai para a área de
  transferência. Só é enviado à sessão em foco com o ajuste "mandar para a sessão em foco"
  (desligado por padrão), pelo `TerminalBridge.send` — e nunca para sessão que pede permissão ou
  pergunta algo (o texto responderia ao pedido): aí só copia e diz por quê.
- **Lapidar o ditado** (`Politicas/LapidarDitado.swift` + `IAdoMac.pontuarDitado`; ajuste "Formatar
  o que você fala": Literal, Limpar, Limpar e formatar; padrão **Literal**). A regra: as palavras do
  texto final são sempre as da fala. Em código, sem modelo: o dicionário do Hugo ("como eu falo ->
  como se escreve", troca por palavra inteira), muletas, palavra repetida e correção no meio da fala
  quando há número/horário/dia ou marcador explícito ("aliás", "quer dizer", "não, pera"). O modelo
  local (FoundationModels, amostragem determinística, resposta limitada ao tamanho da fala, relógio
  de 10 s) só devolve a fala pontuada; a resposta é alinhada palavra a palavra com a fala e dela só
  se aproveitam pontuação, maiúsculas e quebras de linha. Palavra trocada, cortada ou inventada além
  de uma margem pequena (o modelo respondeu, resumiu ou reescreveu) descarta a resposta inteira e
  o texto sai só com o que o código faz. Lista só com dois itens ou mais; "primeiro, segundo" vira
  lista numerada. Medido em 2026-11-13 com falas digitadas (não com microfone), régua dura: nas 49
  falas usadas para ajustar, 48 certas (o método anterior, de instrução única, 12); em 32 falas
  novas, 25 na primeira rodada e 28 depois de ajustes gerais (anterior: 9); em outras 17 falas
  novas, sem ajuste depois, 15 (anterior: 4). Tempo: perto de 1 s por fala comum, 3 a 5 s em fala
  de um minuto. Limites conhecidos: enumeração sem deixa fica em frase; ponto e interrogação fora
  do lugar em fala longa; entrada do dicionário que também é palavra comum ("cru") troca nos dois
  sentidos; quando o modelo mexe nas palavras, o texto sai sem pontuação. Falta: testar com o
  microfone e passar as grafias do dicionário como dica ao reconhecedor (`contextualStrings`).
- **Ler em voz alta**: `VozServico.falar(_:)` / `parar()` com `AVSpeechSynthesizer` (voz pt-BR e
  velocidade nos ajustes); `Politicas/TextoFalavel.swift` tira o markdown (bloco de código vira
  "trecho de código", link é lido pelo texto). Opcional (desligado): ler o primeiro parágrafo da
  entrega quando a sessão termina — assinatura de `AppState.$tasks` só com o ajuste ligado, por
  diferença de `delivery` com estado `finished`; sessão restaurada não é lida; duas entregas
  juntas ficam em fila. O sintetizador é solto quando a fila esvazia.
- Central: permissões com botões, caixa de teste do ditado, teste da voz e os ajustes.
  `crew://voz/ditar` (alterna; mesmo caminho do atalho), `crew://voz/parar`, `crew://voz/falar?texto=`.
- Fora do módulo: `NSMicrophoneUsageDescription` e `NSSpeechRecognitionUsageDescription` no
  `project.yml`; `com.apple.security.device.audio-input` em `Resources/Crew.entitlements` (o app
  instalado usa hardened runtime: sem isso o microfone é negado calado); o tratador de
  `AtalhosVolume` passou a devolver "não tratado" para atalho que não é dele (antes consumia o
  evento de qualquer atalho do Crew, e o segurar-para-falar não chegaria com os dois ligados).
- **Falta / não testado**: nada foi testado com microfone de verdade nem com os pedidos do macOS
  (build e capturas só): ditado real, qualidade do pt-BR no aparelho, se este Mac tem o idioma
  baixado, o atalho global (⌃⌥Espaço pode ser do macOS quando há mais de um teclado/idioma de
  entrada — por isso as alternativas), envio à sessão e leitura da entrega ao vivo. Pausa longa no
  ditado no aparelho pode reiniciar o texto parcial em algumas versões do macOS (não tratado). O
  Homie usa o adereço de fones (com notas musicais) enquanto ouve — um adereço próprio de
  microfone pede mexer no `BotEngine`. Pela regra de dependência o módulo não deveria chamar
  `TerminalBridge`/`Xirp` (são de Sessões) direto: falta um ponto no núcleo para "falar com a
  sessão". Combinação de atalho livre (gravar teclas) e ditado no compositor do app (uma linha
  com `BotaoDitar`) ficam para depois.

### Fase 2 — Áudio por app

Volume e mudo por app (até 4×) via process tap + aggregate device, **sob demanda** (só nos
apps que o Hugo mexeu, nunca em todos o tempo todo). HUD por app no notch,
atalho para "o app que está tocando", saída por app. Limpeza de emergência obrigatória
antes de ligar para o Hugo.

**Volume e mudo por app — código feito (2026-10-05), falta o teste com som de verdade**
(`Modulos/Audio/PorApp/`):
- Tap privado `mutedWhenTapped` (mistura estéreo dos processos do app) + aggregate privado com
  a saída padrão como sub-device; IOProc com rampa exponencial de 30 ms (entra do zero, sem
  clique), limitador suave acima de 0,95 para o reforço, até 400 %. Callback sem alocação, lock
  ou log; parâmetros por `Atomic` (`Synchronization`). Montagem/desmontagem numa fila serial
  fora da main, na ordem parar → IOProc → aggregate → tap.
- Sob demanda: tap só para app ajustado (≠ 100 % ou mudo) que está tocando; fica enquanto o app
  tiver áudio aberto; 100 % sem mudo desmonta. Nenhum ajuste = nenhum tap e nenhum timer.
  Ajuste salvo por bundle id (`modulo.audio.porApp`) volta quando o app toca.
- Segurança: handler de sinal (SIGABRT/SEGV/BUS/TRAP/ILL/FPE/TERM/HUP/INT, sem tomar handler
  de outro) destrói aggregates e taps do Crew; limpeza de órfãos com o prefixo do Crew na
  abertura; ao sair, desmonta tudo; monitor de 2 s (só com tap de pé) remonta se o callback
  parar e desiste após 3 vezes em 1 min (app volta ao som normal); troca de saída remonta.
  Sem permissão, ou com o pedido na tela, nenhum tap é criado (o tap entregaria silêncio e o
  app ficaria mudo).
- Lista de apps por evento (`ProcessObjectList` + `IsRunningOutput` por processo), helpers
  agrupados no app dono (responsável → árvore de processos → prefixo do bundle).
- HUD na barra (`audio.app`, prioridade hud, Homie de fones); atalhos ⌃⌥⌘↑/↓/M do app tocando
  agora (desligados por padrão, Carbon `RegisterEventHotKey`); aba da ilha com dois modos (Apps /
  Dispositivos); Central com a lista completa, ignorados (FaceTime, Zoom, Teams, WhatsApp por
  padrão) e atalhos. Permissão "Gravação de Áudio do Sistema" explicada antes do 1º uso.
- SPI usadas (dlsym, com saída se sumirem): `responsibility_get_pid_responsible_for_pid`
  (agrupar o WebKit do Safari/Mail no app) e `TCCAccessPreflight`/`TCCAccessRequest` (estado e
  pedido da permissão sem criar tap).
- **Falta**: teste com som de verdade (volume, mudo, remover, `kill -9`) e CPU com 1 app
  ajustado — o Mac estava bloqueado e o pedido de permissão do macOS precisa do clique do Hugo;
  saída por app; VU por app; crossfade ao trocar de saída.

**Saída por app — feito (2026-10-05)**: cada app pode seguir a padrão ou ter um dispositivo fixo
(`AjusteApp.saidaUID`, salvo junto do volume). Saída fixa sempre usa tap (mesmo a 100 %); o
aggregate usa o dispositivo escolhido como sub-device, com compensação de deriva quando ele
difere da padrão. Fixa desconectada → o app vai na hora para a padrão (`EscolhaSaida`) com aviso
na barra (`audio.app.saida`); voltou → volta para ela. Trocar a padrão não mexe em app fixo. Na
ilha, ícone redondo da saída em cada linha (tracejado = segue a padrão; laranja = fixa
desconectada) abre a fileira de saídas; na Central, coluna "Saída". Os aggregates do Crew não
aparecem mais como dispositivo do Hugo. Testado ao vivo: app fixo no alto-falante com AirPods de
padrão; fixa inexistente cai na padrão. **Falta**: o teste de desconectar os AirPods de verdade
(roteiro em `testes/audio-por-app/LEIAME.md`); crossfade na troca.

**Volume em TV/DAC sem controle de hardware — ponto de integração (não feito)**: as teclas de
volume são do `NivelService.tecla(codigo:apertou:fino:)` (`Modulos/Nivel/NivelService.swift`,
`case 0, 1, 7`). Quando `CoreAudioHW.ler(dispositivo)?.volumeNoHardware == false`, em vez de
`gravarVolume`/`gravarMudo` (que falham calados), ele chamaria um `VolumePorApp.ganhoGlobal`
(a criar): um único tap global `CATapDescription(stereoGlobalTapButExcludeProcesses: [Crew])`
+ aggregate na saída atual, usando o mesmo `TapApp`, e o HUD do `mostrar(_:)` com o valor desse ganho. Fica para depois porque exige mexer no `NivelService` (fora do módulo).

### Automação — `crew://` (**feito**, 2026-10-05)

`Nucleo/Automacao.swift`: `crew://ilha[/<modulo>]`, `crew://central[/<modulo>]` e
`crew://<modulo>/<acao>?k=v` (cada módulo responde em `Modulo.executar`; nada destrutivo).
Exemplo: `open "crew://sistema/indicador?tipo=cpu"`.

**Servidor MCP** (**feito**, 2026-10-05) — módulo `Modulos/Automacao/`: script Python
(`~/Library/Application Support/NotchBuddy/crew-mcp.py`, regravado pelo Crew) que fala MCP
por stdio e repassa ao Crew pelo `nb.sock` (chave `crew_mcp`). Ferramentas: `estado_do_mac`,
`sessoes_abertas`, `avisar_no_notch`, `abrir_no_crew` — nada destrutivo. Registro no Claude
Code (`claude mcp add --scope user crew …`) só pelo botão da Central, com confirmação. Próximo:
ferramentas dos outros módulos (Disco recuperável, worktrees órfãs, uso do dia).

### Plug (era "Comando") — o comando universal (**código feito**, 2026-11-13; falta o uso de verdade)

Módulo `Modulos/Comando/` (superfícies Atalho e Claude; sem aba na ilha; dá para desligar). Um
painel flutuante aberto por atalho global (padrão **⌥ Espaço**, trocável nos ajustes; o ⌘ Espaço
continua do Spotlight, e a página explica como passá-lo ao Crew) com um campo e resultados ao
digitar. ↑ ↓ escolhem, Enter faz, ⌘Enter é a segunda ação, Esc limpa e fecha. Também
`crew://comando/abrir[?texto=…]`.

O que acha, em blocos de ordem fixa (`GrupoComando`):

1. **Resposta** — conta (`Politicas/Calculadora.swift`: expressões, porcentagem, unidades; sem
   moeda, que pediria rede), tradução (`Fontes/Tradutor.swift`: framework Translation, no
   aparelho; sem o pacote do idioma, a linha diz isso e o Enter abre Idioma e Região), endereço
   (abre no navegador do Crew) e ação com texto (`nota …`, `falar …`).
2. **Melhores** — tudo o que tem nome, numa lista só: apps (`Fontes/FonteApps.swift`), ações do
   Crew, sessões abertas, projetos, páginas dos Ajustes do Crew, Ajustes do Sistema
   (`Fontes/AjustesDoSistema.swift`) e abas do navegador do Crew.
3. **Arquivos** — índice do macOS (`Fontes/FonteArquivos.swift`, `NSMetadataQuery`, só nomes).
   Chegam depois, num bloco próprio embaixo: o que já estava na tela não sai do lugar.
4. **Adiante** — "Pesquisar na web" e "Perguntar ao Claude Code" (sessão nova no último
   projeto, com os padrões e o isolamento dele). Sempre item que o Hugo escolhe, nunca automático.

**Registro de ações** (`AcoesComando.swift`): o que o Crew sabe fazer, achável pelo nome. Quase
tudo é um endereço `crew://` que o módulo já entende em `Modulo.executar`. Ferramenta nova
entra com **uma linha** em `AcoesComando.fixas` (`.endereco("Capturar área", "crew://captura/area", …)`)
ou, de dentro do módulo, com `AcoesComando.registrar([...])` no `iniciar()`. Ação do módulo
desligado some sozinha. Nada destrutivo entra na lista.

Regras: fechado, **nada roda** (a consulta de arquivos nasce ao digitar e se solta ao juntar os
resultados ou ao fechar; só o atalho do Carbon fica registrado). Nada sai do Mac, fora a página
que ele mandar abrir. O que ele escolhe sobe (`AprendizadoComando`, em
`modulo.comando.aprendizado`, com teto e botão "Esquecer"). Regras puras e testáveis em
`Politicas/` (entrada, contas, casamento de nome, ordenação). O painel
(`Telas/PainelComando.swift`) é um `NSPanel` que não ativa o Crew; as teclas da lista são
tratadas na janela, sem depender da barra de menus.

Limites de hoje: o navegador do Crew não tem favoritos (aparecem as abas, com as fixadas
marcadas, e as 300 páginas do histórico que mais pesam), e escolher uma aba abre o endereço em
aba nova — focar a aba que já existe pede um aviso novo em `AppCrewView`. O mecanismo de busca é o do navegador (Google,
fixo no código dele). `Modulos/Busca/` (pergunta rápida da ilha, antiga) não foi tocado.

### Rotinas — pedidos guardados e agendados (**código feito**, 2026-11-09; falta a execução de verdade)

Módulo `Modulos/Rotinas/` (pilar IA, sem aba na ilha, ligado por padrão, dá para desligar). Uma
**rotina** é um pedido guardado que abre uma sessão do Claude Code num projeto, pela agenda ou à
mão. Inspirado nas "routines / triggers / schedules" do rakazo e do OpenMausBot — só a ideia;
nenhum código deles.

**Feito**
- Modelo e arquivo (`RotinasTipos.swift`): nome, pasta, pedido, modelo, modo de permissão, agenda,
  ligada, recuperar perdida, última/próxima execução e histórico (20 últimas tentativas: quando,
  origem, sessão, ok ou motivo). `~/Library/Application Support/NotchBuddy/rotinas.json`, gravação
  atômica numa fila serial fora da main. Arquivo que existe e não deu para ler **nunca** é
  sobrescrito: vira cópia `rotinas.ilegivel-<hora>.json`, a página avisa e nada é gravado até o
  Hugo clicar em "Começar do zero". Modo de capturas não grava nem executa.
- Agenda (`Politicas/AgendaRotina.swift`, só Foundation, pura): só à mão; todo dia às HH:mm; dias
  da semana às HH:mm; a cada N minutos/horas (mínimo 15 min, grade a partir de uma âncora, tempo
  corrido); uma vez numa data. `proxima(depois:)` no calendário local; horário de verão: hora que
  não existe roda na primeira hora válida do dia, hora repetida roda uma vez.
- Sem fila de atrasadas (`PoliticaRotinas.vencida`): até 2 min de atraso conta como na hora; passou
  disso (Mac dormindo, Crew fechado) roda **no máximo uma vez**, e só se a rotina tiver "Recuperar
  execução perdida" (padrão desligado); senão anota "passou da hora" no histórico. A próxima é
  sempre contada a partir de agora.
- Custo parado zero (`RotinasServico`): UM `DispatchSourceTimer` de relógio de parede para a
  próxima rotina ligada, refeito ao acordar, ao acertar o relógio e ao trocar de fuso. Sem rotina
  ligada, pausado ou sem a confirmação: nenhum timer.
- Segurança: a agenda só roda rotina com a chave ligada pelo Hugo; a primeira chave pede uma
  confirmação única (o Crew vai abrir sessões sozinho e gastar uso; `modulo.rotinas.consentiu`).
  "Pausar todas" (`modulo.rotinas.pausadas`) — o que vence durante a pausa não roda ao voltar.
  Pela agenda, pula e anota o motivo quando a sessão da execução anterior da mesma rotina ainda
  está aberta (`MotorCrew.ehDoCrew`), a pasta não existe ou o motor não está disponível.
  "Rodar agora" é o clique do Hugo e vale sempre (inclusive com a anterior aberta).
- Execução: `MotorCrew.nova(pasta:pedido:opcoes:)` com o nome da rotina. Cada tentativa publica um
  sinal passageiro na barra (`rotinas.aviso`): "Rotina X abriu uma sessão" / "Rotina X não rodou:
  motivo".
- `crew://rotinas/rodar?id=<uuid>` ou `?nome=<nome>`: **não roda**. Não existe no núcleo um
  ajudante de "pedido na ilha com aprovação" (§1), então o pedido vira um sinal clicável na barra
  (`rotinas.pedido`, 2 min) que abre a página com a rotina em destaque e os botões "Rodar agora" /
  "Dispensar". Quem roda é o clique do Hugo.
- Central (`Central/RotinasCentral.swift`, `RotinaEditor.swift`): lista (chave, projeto, agenda em
  português, "próxima: hoje às 18:00", último resultado, rodar agora, histórico, editar, apagar
  com confirmação) e a folha de criar/editar (projeto de `ProjetosCrew` ou "Escolher pasta…",
  pedido, modelo Padrão/Fable/Opus/Sonnet/Haiku, permissões Padrão/Aceitar edições/Planejar/
  Automático, agenda com prévia da próxima). Capturas `41_central_rotinas` e `41b_rotinas_editor`.
- Conferência da agenda: script à parte (o projeto não tem target de teste) que compila
  `AgendaRotina.swift` sozinho — 40 conferências (diária, semanal, intervalo, uma vez, horário de
  verão de Nova York nos dois sentidos, 3 dias dormindo = uma decisão, textos, JSON), todas
  passando em 2026-11-09.

**Não testado**
- Nenhuma execução de verdade: nem pela agenda nem por "Rodar agora" (o `MotorCrew.nova` nunca
  foi chamado por este módulo; a regra da sessão era não abrir sessão real).
- O timer disparando na hora, o acordar do Mac com rotina vencida e a troca de fuso, ao vivo.
- O sinal na barra e o clique no pedido do `crew://` (só o caminho do código foi conferido).
- A folha de criar/editar aberta na janela (a captura fotografa a view solta) e os dois alertas.

**Falta**
- Ferramenta MCP para pedir uma rotina (hoje só `crew://`; mesmo caminho de pedido, sem executar).
- Um ajudante do núcleo para "pedido de automação aprovado na ilha", com o botão na própria barra.
- Saber quando a sessão da rotina terminou e com que resultado (hoje o histórico só diz que abriu).
- Notificação do macOS quando a ilha está escondida; aba ou bloco na ilha, se virar uso diário.
- Usa `MotorCrew`/`ProjetosCrew` do módulo Sessões direto (não há `Eventos` no núcleo ainda).

### Nova era — Crew como lugar único de trabalho (decisão de 2026-11-12)

O Hugo quer trabalhar só com o Crew (largar Arc, Wispr Flow e os apps avulsos). Seis
ferramentas de código aberto servem de referência; nenhuma é Swift, então cada uma entra de um
jeito. Uma leva por linha, nesta ordem:

| # | Leva | Referência (licença) | Como entra | Estado |
|---|---|---|---|---|
| 1 | Ajustes por superfície + pilar Criar + "Onde aparece" | — | — | **feito** (2026-11-12; visto só em capturas) |
| 2 | Ditado no lugar do Wispr Flow: segurar Fn, colar no app em foco | OpenWhispr (MIT) | refeito nativo em `Modulos/Voz/` | |
| 3 | Gravação de tela, câmera e áudio num fluxo só, com biblioteca | Cap (AGPL: só a ideia) | refeito nativo em `Modulos/Captura/` | **código feito** (2026-11-12; visto só em capturas, nenhuma gravação de verdade feita) |
| 4 | A voz do computador: vozes humanizadas, gestão de vozes | VoiceStudio (AGPL: só a ideia; é um app Electron + Python/PyTorch, pesado para rodar ao lado), omnivoice.cpp (MIT) com o modelo OmniVoice (CC BY-NC 4.0: uso não comercial) | motor externo nativo; `Modulos/Voz/Fala/` fala com ele por HTTP local | **feito (2026-11-13; motor provado fora do app, tela vista só em capturas, nada ouvido no app)**: `FalaServico` decide quem fala — a voz do macOS (padrão, na hora) ou a voz humanizada. O motor é o `tts-server` do omnivoice.cpp (o mesmo modelo que o VoiceStudio usa por padrão), em `motores/omnivoice/`: instalado por botão (`MotorOmniVoice`: commit e pesos fixados com sha256, compila neste Mac com Metal, 945 MB de pesos Q8), ligado na primeira fala e desligado depois de 5 minutos parado (`ServidorOmniVoice`, só em 127.0.0.1, ~1,1 GB de memória ligado; sobra de queda é limpa pelo `servidor.pid`). Toda fala continua entrando por `VozServico.falar`; se o motor falha, sai pela voz do macOS. Vozes do Hugo em `motores/omnivoice/vozes/<id>/` (`VozHumanizada`: desenhada por atributos ou clonada de gravação; ficam quando o motor é removido). Sessões: ferramentas MCP `falar` / `vozes` (`FalaMCP`) e `crew://voz/falar?texto=…&voz=…`; ajustes "as sessões podem falar" (ligado) e "avisar por voz quando uma sessão precisa de você" (desligado por padrão). Medido num M2: de 5 a 13 s de espera por frase curta — a voz humanizada serve para ler e avisar sem pressa, não para resposta imediata |
| 5 | Vídeo por código e imagem/vídeo gerados pelas sessões | Remotion (licença própria: grátis para pessoa física e empresa até 3 pessoas), Open Higgsfield (sem arquivo de licença) | motor externo + ferramenta do Claude; prévia e galeria no app | **Remotion feito (2026-11-12)**: módulo `Modulos/Video/` — motor em `motores/remotion/` (instalado por botão, versão fixada em `MotorRemotion.versao`), projetos em `motores/remotion/videos/<nome>/` (acham o `node_modules` do motor sem cópia), `CLAUDE.md` do motor como guia das sessões, prévia (Remotion Studio) no navegador do Crew, renderização com andamento na barra da ilha, vídeos prontos em `~/Movies/Crew`, ferramentas MCP `videos` / `video_criar` / `video_renderizar`. Processo de vida longa: `Nucleo/ProcessoVivo.swift` (serve aos próximos motores). Falta: Higgsfield |
| 6 | SEO dos sites dos projetos | Open SEO (MIT) | ferramenta do Claude + aba no painel do projeto | |

**Leva 3 — gravação de tela (2026-11-12)**, em `Modulos/Captura/Gravacao/` (ideia do Cap/Loom; nenhum
código copiado). `GravadorTela` = `SCStream` + `SCRecordingOutput` do ScreenCaptureKit (macOS 15), que
escreve o MP4 (H.264) sozinho, com som do Mac (`capturesAudio`, sem os sons do Crew) e microfone
(`captureMicrophone`). Alvos: tela onde o mouse está, área (seleção própria, `SeletorArea`, com moldura
tracejada durante a gravação) e janela (seletor do macOS, `SCContentSharingPicker`). A ilha e toda
janela do Crew com `sharingType = .none` (prévias, moldura, contagem) ficam fora do vídeo; a bolha da
câmera (`BolhaCamera`: painel redondo arrastável com `AVCaptureVideoPreviewLayer`) entra por estar na
tela — menos na gravação de janela. `GravacaoServico` cuida do fluxo: ⌃⌥⌘6 (ou `crew://captura/gravar`
`?alvo=tela|janela|area` e `crew://captura/parar`) começa, contagem de 3 s, sinal `captura.gravando` na
barra da ilha (ponto vermelho, tempo, botão Parar; por isso o módulo passou a declarar `.ilha`), o
mesmo atalho para. O vídeo vai para `capturas/gravacoes/` ("Gravação AAAA-MM-DD HH.MM.SS.mp4"; o Crew
nunca apaga gravação sozinho), abre a prévia (`Telas/PreviaGravacao.swift`: tocar, Finder, copiar
caminho, arrastar, mandar para a sessão em foco, Lixeira) e entra na lista da página (primeiro quadro,
duração, tamanho). Ajustes em `modulo.captura.gravacao.*`. Parado não há stream, câmera nem timer — só
o atalho registrado. Permissões pedidas só por clique na página; sem microfone ou câmera liberados a
gravação sai sem eles e diz isso.

**Leva 3b — o que a edição precisa (2026-11-13).**
- **Sair do Crew gravando não estraga o arquivo**: `AppDelegate.applicationShouldTerminate` segura a saída
  (`.terminateLater`) enquanto `GravacaoServico.fecharParaSair()` para o stream e espera o MP4 fechar e o
  rastro ser escrito; teto de 9 s (o `instalar.sh` espera 10 s antes de matar). Matar o processo à força
  (`kill -9`, queda de energia) ainda perde o arquivo: o `SCRecordingOutput` só fecha o MP4 no fim.
- **Microfone e câmera à escolha** (`gravacao.microfoneId`, `gravacao.cameraId` = `uniqueID` do aparelho;
  vazio ou aparelho desconectado = o padrão do macOS). A lista é lida ao abrir os ajustes, sem vigia.
- **Rastro do mouse** (`Gravacao/RastroMouse.swift`, ajuste `gravacao.rastroDoMouse`, ligado por padrão):
  enquanto grava, um timer de 30 Hz lê `NSEvent.mouseLocation` (só guarda quando mudou de lugar) e um
  monitor de eventos pega **só** os botões do mouse — nenhuma tecla, e nada disso existe fora da gravação.
  No fim vira "Gravação ….json" ao lado do MP4: `quadro` (o retângulo gravado), `cliques` e `mouse`, com
  `t` em segundos do vídeo e `x`/`y` de 0 a 1 dentro do quadro. O zero do vídeo é o aviso
  `recordingOutputDidStartRecording` (pode ter desvio de décimos de segundo; não medido). Na gravação de
  janela o quadro é o da janela ao começar. Apagar a gravação leva o JSON junto para a Lixeira.
- **Editar** (`VideoServico.editarGravacao`): `MidiaGravacao.levar` junta som do Mac e microfone (duas
  trilhas no MP4; navegador e Remotion só tocam a primeira) numa trilha só, sem recodificar a imagem; o
  rastro vai para `public/mouse.json`; o projeto nasce com `ZoomNosCliques.tsx` e a composição
  `GravacaoComZoom` (zoom automático em cada clique), e o `CLAUDE.md` do projeto explica o formato.

**Provado rodando (fora do app)**: a junção das trilhas (arquivo de teste com dois tons → uma trilha com
os dois), o JSON do rastro e o projeto gerado (tipos conferidos com `tsc`, quadros da `GravacaoComZoom`
renderizados pelo motor instalado, zoom no ponto do clique). **Não testado**: nenhuma gravação de verdade
(só build e capturas 42f…42i) — arquivo, áudio, microfone, seletor de janela, bolha, atalho, clique no
Parar da ilha, sair gravando, escolha de aparelho e o acerto do tempo do rastro com a imagem.
**Falta / limites**: app com volume ajustado pelo Áudio por app toca pelo Crew e pode ficar fora do som
gravado; área só na tela do mouse; sem pausar. (A transcrição da fala e a edição com contexto vieram na leva 3c, abaixo.)

**Leva 3c — gravei, o Claude edita com o contexto do projeto (2026-11-13).** Pedido do Hugo: gravar a
tela fazendo algo e sair um vídeo de criador bem editado, lendo o projeto de onde o vídeo vem. A
referência que ele mandou vale pelo **tipo** de vídeo, não pelo estilo: o kit é de blocos neutros e a
cara de cada vídeo nasce da identidade do projeto.
- **De qual projeto é o vídeo** (`Video/Telas/EscolhaProjetoVideo.swift`): o botão Editar de uma gravação
  (lista e prévia) abre o menu do app com os projetos do Crew — primeiro, marcado, o da sessão em foco
  (sem ela, o último usado) — e "Nenhum projeto". A escolha fica em `crew.json` no projeto de vídeo, e
  "Editar com o Claude Code" depois reabre do mesmo jeito.
- **A sessão enxerga o projeto, só para ler**: `MotorCrew.Opcoes.pastasExtras` (`--add-dir`) e
  `somenteLeitura` (`--disallowedTools "Edit(//pasta/**)"`), mais a instrução fixa. As opções de lista
  vão antes do `--session-id` (no fim da linha engoliriam o pedido). A sessão nasce com um pedido:
  assistir, ler o projeto, montar o roteiro e **propor em 5 linhas antes de editar**.
- **O projeto de vídeo** (`KitEdicao.swift` = os arquivos como foram testados no motor; `ModeloEdicao.swift`
  = o que muda por gravação): `roteiro.ts` (a edição: gancho, título, blocos, capítulos, encerramento),
  `tema.ts` (cores, fontes, brilho, raio), `gravacao.ts` (fatos) e `kit/` — `Edicao` (montagem), `Fundo`,
  `Moldura`, `ZoomNosCliques` (zoom nos cliques; no vertical acompanha o ponteiro), `DestaqueCursor`,
  `DestaqueMoldura` (contorno com rótulo), `CartaoCamera` (arquivo à parte ou a bolha recortada da
  gravação), `Palco` (título curto com palavra em destaque, pilha de miniaturas, aviso, grade de dados),
  `Diagrama` (cartões ligados por linhas), `Legendas`, `FaixaInferior`, `Cabecalho`, `Cartelas`, `layout`
  e `movimento`. Composições `Video` (16:9), `Vertical` (9:16) e `Gravacao` (crua); a duração sai do
  roteiro. O `CLAUDE.md` gerado traz o passo a passo, o repertório de blocos e princípios de design, e
  diz explicitamente para propor uma direção visual própria em vez de repetir um modelo.
- **Legendas pela fala** (`Video/TranscricaoFala.swift`): `SpeechAnalyzer` + `SpeechTranscriber` (macOS
  26; antes disso, sem legenda), no aparelho, com o tempo de cada palavra → `public/legendas.json`.
  Idioma = o do ditado. O modelo do idioma precisa estar no Mac: a página do Vídeo mostra o estado e tem
  o botão "Baixar o modelo" (vem da Apple, pelo sistema; só por clique). Sem modelo a edição segue sem
  legenda e o guia diz isso à sessão; "Refazer as legendas pela fala" no menu do projeto refaz depois.
  No vídeo a legenda é opcional (`roteiro.legendas`; sem dizer, só no vertical); o JSON serve de
  qualquer jeito para a sessão saber o que é dito e cortar no silêncio.
- **Provado rodando (fora do app)**: a transcrição com o mesmo `TranscricaoFala.swift` num utilitário
  (Swift 6), sobre um MP4 com fala sintetizada em arquivo, **em inglês** (o modelo en-US já estava
  neste Mac); vídeo sem fala devolve zero frases. `--add-dir` + regra de negar edição no CLI real
  (escrita negada na pasta do projeto, leitura liberada). O projeto de edição inteiro renderizado pelo
  motor instalado nos dois formatos, com todos os blocos, sobre uma gravação sintética com rastro de
  mouse e narração; quadros olhados um a um. Quadros e QR pelos comandos que o guia ensina.
- **Só compilou**: o menu de escolha (captura 42j), a criação do projeto pelo app (`editarGravacao` com
  o kit novo), o botão de baixar o modelo, refazer legendas, a sessão abrindo com as opções novas.
- **Falta / limites**: **pt-BR não foi provado** — o modelo novo de pt-BR não está baixado neste Mac
  (`faltaModelo`) e o reconhecedor antigo (`SFSpeechRecognizer` / `DictationTranscriber`) corta a frase
  depois de 4 ou 5 palavras em arquivo, por isso não é usado. A **câmera não é gravada em arquivo à
  parte**: a bolha entra na gravação por estar na tela, e o kit a recorta de lá (`camera.recorte`),
  com a qualidade do tamanho da bolha; gravar a câmera num `.mov` ao lado (com o atraso em relação à
  tela) é o próximo passo natural, e o kit já aceita (`camera.arquivo`). A posição da bolha não vai
  para o projeto: a sessão mede num quadro. Uma sessão de edição de verdade, do começo ao fim, ainda
  não foi rodada.

### Fase 3 — Profundidade

Projetos parados (`node_modules`, `target`…), arquivos grandes e duplicados, EQ, servidor **MCP** do Crew. (Uso e custo foi adiantado para a
Fase 1.)

## 6. Dívidas conhecidas (de `docs/pesquisa/crew-antes-da-reorganizacao.md`)

- **CPU com a ilha compacta** (o estado normal com sessões abertas): 8–11 %, quase tudo
  layout + commit do SwiftUI por quadro do Homie (ver 0b2).
- `IslandContentView` mantém **todas** as telas montadas (opacidade 0). As animações delas já
  param fora da tela (`\.telaVisivel`), mas o custo de montagem fica até o passo 0d.
- `IslandConst.viewLayouts[view]!` derruba o app se uma tela nova esquecer a entrada.
- `ClaudeService` (agora em `Modulos/Busca/`) não é chamado por ninguém.
- `docs/SPEC.md`/`INTEGRATIONS.md` (francês) descrevem o protótipo, não o app atual.

## 7. Módulo Sistema

Monitor de barra de menus nunca some, e por isso os leitores dele nunca param. No Crew a
regra é a contrária: ilha escondida = nenhum leitor rodando.

**Leitores** (cada um um `Amostrador`, com consumidores declarados):

| Leitor | Fonte (sem subprocesso) | Intervalo | Quem consome |
|---|---|---|---|
| CPU total + E/P + sistema/usuário | `host_processor_info`, topologia `AppleARMPE` lida 1× | 1 s | aba; compacta (2–5 s) se escolhido |
| Load average + uptime | `getloadavg()`, `sysctl kern.boottime` | 5 s | aba |
| Memória: pressão, swap, compressão | `host_statistics64`, `vm.swapusage`; pressão por `DispatchSource.makeMemoryPressureSource` | 2 s / evento | aba; alerta por **evento** |
| Top processos (CPU, memória, energia) | `proc_listallpids` + `proc_pid_rusage` em delta | 2 s | aba / Central; encerrar só com clique |
| Temperatura CPU/SoC | SMC (chaves por geração) ou HID | 3 s | aba; alerta lento (30 s) se ligado |
| Frequência E/P, potência do SoC | IOReport (privado) | ≥ 2 s | só aba aberta |
| GPU | IORegistry `PerformanceStatistics` | 2 s | aba |
| Bateria: saúde, ciclos, W, tempo | `IOPSNotificationCreateRunLoopSource` + `AppleSmartBattery` | **evento** | compacta, aba, alerta |
| Rede ↑↓, IP local, link | `NET_RT_IFLIST2`; `NWPathMonitor` (evento) | 1 s | aba |
| Disco: espaço, R/W, SMART | `volumeAvailableCapacityForImportantUsageKey`; IORegistry `Statistics`; NVMe SMART | 30 s / 1 s / 1× por abertura | aba; espaço também no módulo Disco |
| Bateria de AirPods/periféricos | IORegistry `BatteryPercent` + plist do Bluetooth | ao conectar / ao abrir | aba; alerta de bateria baixa |

**Fica de fora**: controle de ventoinha (helper root, abandonado pelo autor), IP público e
envio para nuvem do autor, LevelDB, `ps`/`top`/`nettop`/`system_profiler` no ciclo de leitura.

**Na ilha**: compacta mostra **um** indicador que o Hugo escolhe (CPU %, temperatura, pressão
de memória ou nada) — e só aparece se o árbitro não tiver nada mais importante. Expandida:
anéis (CPU, memória, temperatura), linha de histórico, top 5 processos. A Central tem o
painel completo com histórico mais longo.

**Alertas** com histerese e N leituras seguidas: CPU alta
sustentada, memória em pressão, temperatura, bateria baixa, disco quase cheio. O alerta vira
sinal no árbitro e o Homie reage (suando, cansado…), em vez de notificação do sistema.

**Lições que viram regra do núcleo** (valem para todo módulo, não só Sistema):

1. Um `Amostrador` por fonte, dono único do timer, com consumidores declarados; liga só com
   consumidor visível. Timer é `DispatchSourceTimer` suspenso/retomado, com leeway.
2. Evento antes de polling (IOPS, `NWPathMonitor`, pressão de memória, acordar do Mac).
3. Nunca subprocesso no ciclo de leitura; o que é caro vai para cache com validade longa.
4. Separar ler de desenhar: o módulo guarda o último valor e o histórico; a tela só pinta
   quando visível e quando o valor mudou.
5. Descritor estático por módulo (nome, ícone, ligado por padrão, indicadores disponíveis).

## 8. Decisões

| Data | Decisão |
|---|---|
| 2026-10-04 | Crew cresce como **central de IA + Mac**, organizado em módulos (esta arquitetura). |
| 2026-10-04 | Código GPL não entra: reimplementar a técnica. Código MIT pode ser portado com aviso de copyright. |
| 2026-10-04 | Target `CrewAppStore` sai: os módulos novos não funcionam no sandbox e o uso é pessoal. |
| 2026-10-04 | Janela **Central** para gestão; a ilha fica para olhar e agir rápido. |
| 2026-10-04 | Fundação (fase 0) antes das funcionalidades novas. |
| 2026-10-04 | O Crew assume o áudio por app. |
| 2026-10-05 | **Missão e terceiro pilar "Eu"**: o Crew trabalha junto com o Hugo — ele controla, o Crew fica de olho por ele. O assistente é o próprio Homie. Fontes do pilar Eu: WhatsApp (conversa do dia a dia) e e-mail (envios corporativos sérios), ligadas uma a uma. |
| 2026-10-05 | Agentes sem aba na ilha: as sessões já estão na ilha e as worktrees órfãs são faxina eventual — só na Central. Critério para aba na ilha: algo para olhar ou agir em segundos. |
| 2026-11-12 | **Crew independente do Xirp** (o Hugo parou de usar): projetos e sessões novas não passam mais por ele; o resto do código do Xirp sai numa leva própria. |
| 2026-11-12 | **Nova era**: o Crew vira o lugar único de trabalho. Quarto pilar **Criar** (Captura, Voz, Vídeo, Imagem). Superfícies nomeadas (Ilha, App, Atalho, Claude, Ajustes) e declaradas por módulo. **Motores externos** permitidos (processo à parte gerenciado pelo Crew) para o que não é Swift; AGPL/GPL nunca copiado para dentro. Ajustes reorganizados por superfície. |
| 2026-11-13 | **Nomes em inglês, pegada de rua** (decisão do Hugo): setores Squad (Comando), Spot (Mesa), Booth (Estúdio), Rig (Máquina), Grind (Dia), Link (Conexões); a busca ⌥Espaço é o **Plug**. Só o nome de tela muda (`Setor.nome`, `ComandoModulo.nome`); casos, pastas e chaves de ajuste seguem em português. Ferramentas de dentro dos setores ficam com nome descritivo (Navegador, Arquivos, Ditado). |
| 2026-11-13 | **Setores**: o app vira a casa de seis setores (Comando, Mesa, Estúdio, Máquina, Dia, Conexões), cada um com um problema; a tela de trabalho de cada ferramenta sai dos Ajustes e vai para o setor; os Ajustes ficam só com configuração, agrupados pelos mesmos nomes. O pilar deixa de agrupar telas. Nome "Mesa" ainda em aberto (alternativas: Trabalho, Navegar). |
| 2026-11-09 | **App do Crew = só sessões**, com motor próprio (tmux + CLI) além do Xirp e visual próprio (referência: apps de conversa com agentes, tipo OpenMausBot); as páginas dos módulos viram a janela de Ajustes (⌘,). Módulos novos na mesma leva: Voz, Rotinas, Captura (inspirados em OpenMausBot, rakazo e ScreenDrop; nenhum código copiado). |
