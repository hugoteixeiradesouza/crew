# Mapa da arquitetura do Crew (macOS)

Raiz analisada: `/Users/hugo/dev/crew`, branch `estavel`, último commit `f58dd65`. Fiz só leitura.

**Resumo:** o app tem um único estado global (`AppState.shared`), um único enum de telas (`IslandView`) e uma única view de despacho (`IslandViewContent`). Não existe protocolo nem registro de módulos. Uma funcionalidade nova hoje precisa mexer em 6 a 9 arquivos centrais. Além disso, o "0% de CPU com a ilha escondida" não é garantido de fato: dois timers rodam sempre (detalhes na seção 6).

---

## 1. Arquivos Swift (`NotchBuddy/Sources/App/`, 15.549 linhas no total)

| Arquivo | Linhas | Responsabilidade |
|---|---|---|
| `NotchBuddyApp.swift` | 13 | `@main NotchBuddyApp`, com uma cena `Settings { SettingsView() }` e `@NSApplicationDelegateAdaptor`. |
| `AppDelegate.swift` | 89 | Faz o bootstrap na seguinte ordem: `signal(SIGPIPE)`, o modo de captura (`CaptureTool`), aquece o `KeychainStore`, ativa a política `.accessory` e cria o `NSStatusItem` com o menu (Abrir, Ajustes…, Sair). Também cria o `IslandWindowController`, chama `fsm.launch()` e inicia `HookServer`, `MediaService` e `NivelService`. Os pollers só sobem se `AgentTask.integracoesLigadas` for true. Abre a janela de Ajustes, uma `NSWindow` com `NSHostingView(SettingsView)`. |
| `IslandWindowController.swift` | 1150 | Um dos arquivos-deus. Cria o `IslandPanel` (NSPanel 720×320, `.borderless/.nonactivatingPanel`, nível `mainMenu+3`). Liga a FSM às mudanças de modo. Roda o loop de 60 Hz (`pollFrame`), que alterna o clique-através, alimenta hover e posição do mouse e mantém o arrasto do Homie. Instala todos os monitores `NSEvent`: Esc, Option duas vezes, Cmd+V no chat, atalho global, clique fora, mouseDown/Dragged/Up. Também cuida de: puxão elástico do chat (`handleChatScroll`), painel fantasma e destaque de janela no "attach", detecção do notch (`notchScreen/notchWidth/notchHeight`), `reposicionarNaTela`, timers de dizzy e finished, os `Notification.Name` globais e as funções livres `islandSize(...)` e `nivelNaIlha(...)`. |
| `IslandStateMachine.swift` | 193 | FSM "pura" com estados `hidden / petit / home / saudacao`. Agenda timers com `DispatchWorkItem`. Recebe closures injetadas: `collapseDelay`, `holdOpen`, `holdVisible`, `hideDelay`. |
| `IslandTypes.swift` | 240 | Enums `IslandMode` (hidden/compact/expanded), `IslandView` (19 casos), `BotState`, `BotEmote`, `PillBadge`, `AgentSource`. Structs `ApprovalInfo`, `QuestionInfo`, `AgentTask` (com campos de sessão do Claude e de integração misturados). `IslandConst` reúne a tabela `viewLayouts` (altura e posição do Homie por view), cores de projeto, `allIntegrations` e `washColors`. |
| `IslandRootView.swift` | 677 | `IslandRootView` e `IslandContainer` (forma, tamanho animado, troca greeting/upload/conteúdo, barra de nível, grade compacta). Também `IslandShape`, `BotPlacement`, `botPosition(...)`, `CountdownBar`, `IslandContentView` (cabeçalho + ZStack com todas as views), `IslandHeader` (abas fixas: house, chat, music, plus, além de pin, engrenagem e som), `TabButton`, `CompactMiniGrid`, `NivelBarra` e `Color(hex:)`. |
| `IslandViewContent.swift` | 3755 | O maior arquivo-deus. O `switch` despachante `IslandViewContent` e todas as views: `OverviewView`, `EmptyStateView`, `ApprovalView`, `QuestionView`, `ErrorView`, `FinishedView`, `ConfusedView`, `UploadView`, `UploadingView`, `ChooseView`, `MailView` (Resend ou AppleScript do Mail), `PromptView` (chat com sessões, cerca de 400 linhas, 827–1228), `MarkdownText`, `SearchingView`, `ResultView`, `NoteView`. Também os cards de integração (`IntegrationCardView`, Vercel, Resend, GitHub, Stripe, Cal.com, Notion, n8n), `TickerView`, `TituloSessao`, `AgentPillsView`, `ColumnAgentsView`, `CardBackground`, os botões e estilos, e `SettingsIslandView`. |
| `AppState.swift` | 667 | `AppState: ObservableObject` singleton. Guarda modo, view e tarefas, a aparência do personagem, as flags de módulo, os ajustes persistidos, os dados de todas as integrações, o estado do chat e as pendências de aprovação. Contém ainda os modelos `VercelDeployment`, `ResendEmail`, `GitHubStats`, `StripePayment`, `CalcomBooking`, `NotionPage`, `ChatMessage`, `PromptContext`, `DroppedFile` e `SearchResult`. |
| `HookServer.swift` | 1281 | Socket Unix (`~/Library/Application Support/NotchBuddy/nb.sock`) numa thread própria. Converte eventos do Claude Code em mudanças no `AppState` (`processEvent`). Mantém `PermissionRequest` bloqueante por sessão (`pendingFDs`, timeout de 115 s que devolve "ask"). Persiste e restaura sessões (`saveSessions/restoreSessions`, JSON no supportDir). Faz `pruneDeadSessions` a cada 20 s, lê títulos e transcript, instala e remove os hooks no `~/.claude/settings.json` (inclusive a variante App Store com bookmark) e embute o script `nb-hook` (shell + relay em Python). |
| `BotEngine.swift` | 2016 | Motor do Homie (port da classe `Bot` do protótipo): tweens, partículas, estados, emotes, olhos e desenho em `GraphicsContext`. Inclui `BotStyle` (aparência estática global), `BotConst`, `EyeShape`, os acessórios (boné, fones, celular/fones do nível) e os observers das notificações `.triggerEmote/.triggerSlap/...`. |
| `BotCanvasView.swift` | 187 | `BotCanvasView` (TimelineView + Canvas, pausado se `hidden` e sem nível) e `MiniBotCanvasView` (TimelineView `.animation`, que não pausa). |
| `GreetingCanvasView.swift` | 636 | Animação de saudação no launch, desenhada à mão em Canvas e sincronizada com a FSM por notificações. |
| `UploadSequenceEngine.swift` | 437 | Física e coreografia do arrasto e soltura de arquivo ("bac", sucção, barra de progresso). Singleton. |
| `UploadCanvasView.swift` | 551 | Canvas da sequência de upload, com os botões do "choose". |
| `FileDropView.swift` | 205 | `FileDropNSView` (destino de drag no AppKit) e `FileDropHandler`: copia para `supportDir/inbox`, cuida dos ticks de som, de anexar ao chat e de colar no chat. |
| `MediaService.swift` | 227 | Mostra o que está tocando no Spotify e no Música via `DistributedNotificationCenter`. Usa AppleScript (`osascript` via `Process`) para ler capa e posição e para play/pause/next. Muda `AppState.syncMode()` e posta `.hookReveal`. |
| `MediaView.swift` | 128 | Aba de mídia: capa, progresso (`TimelineView(.periodic 1s)`) e botões. |
| `NivelService.swift` | 283 | Brilho e volume. CoreAudio com listeners de propriedade; brilho via `DisplayServices` (framework privado, `dlopen`), com aviso de mudança. Um `CGEvent.tapCreate` (NX_SYSDEFINED) intercepta as teclas de brilho e volume para suprimir o HUD do macOS e exige Acessibilidade. Escreve log em `~/Library/Logs/NotchBuddy/nb.log`. |
| `SessionChat.swift` | 342 | `TranscriptReader` (lê o JSONL da sessão), `Xirp` (CLI: projetos, sessionId, message, newSession, rename, stop), `SessionChannel` e `TerminalBridge` (tty → tmux send-keys / AppleScript no Terminal ou iTerm). |
| `ClaudeService.swift` | 358 | `Keychain` (SecItem), `KeychainStore` (cache lido uma vez no launch) e `ClaudeService` (API Messages + web_search, modelo `claude-sonnet-4-6`). `ClaudeService.shared` não é referenciado em nenhum outro arquivo e parece código morto. |
| `SettingsView.swift` | 837 | Janela de Ajustes. Seções Personagem, Módulos (toggles `Modulo`), Ilha, Atalho, Claude Code (hooks), Integrations e Active pills (só se `integracoesLigadas`), Anthropic API e Início (`SMAppService.mainApp`). Inclui `ShortcutRecorderButton`, `Secao`, `Modulo`, `PersonagemAjustes` e `PersonagemPrevia`. |
| `Projetos.swift` | 79 | Acha a raiz git e o nome do projeto pelo cwd (entende worktrees). Dá uma cor fixa por projeto (UserDefaults `coresProjetos`) e agrupa as sessões. |
| `WindowContextCapture.swift` | 68 | Título da janela via AX e URL do navegador via AppleScript. Fica desligado com `#if APPSTORE`. |
| `CaptureTool.swift` | 219 | Modo `--capturas <pasta>`: monta cenas, fotografa a ilha e sai. |
| `SoundEngine.swift` | 50 | 28 WAVs pré-carregados, com pool de 3 `AVAudioPlayer` por som. |
| `N8nPoller.swift` 272, `StripePoller.swift` 161, `VercelPoller.swift` 108, `NotionPoller.swift` 99, `CalcomPoller.swift` 97, `ResendPoller.swift` 62, `GithubPoller.swift` 62 | — | Cada um é um singleton `@unchecked Sendable` com `DispatchSourceTimer` em background, token do Keychain e escrita direta em campos do `AppState`. Hoje estão desligados (`AgentTask.integracoesLigadas = false` em `AppState.swift:8`). |

Fora do Swift:
- `docs/SPEC.md` e `docs/INTEGRATIONS.md` estão em francês e descrevem o protótipo original. Divergem do código atual: falam em modo `peek`, alturas de view diferentes e afirmam "Aucune permission Accessibilité nécessaire", mas o app hoje usa Acessibilidade.

## 2. Funcionalidades e onde moram

- **Sessões do Claude Code e hooks.**
  - Entrada: `HookServer.processEvent`, para os eventos SessionStart, UserPromptSubmit, PreToolUse, PostToolUse(Failure), Notification, Stop, StopFailure, Subagent* e SessionEnd.
  - Cada sessão vira uma `AgentTask` com id `sessao_<session_id>`.
  - Ocultar, dispensar, renomear e encerrar ficam em `AppState` (`ocultar/dispensar/renomear/encerrar`, com UserDefaults `sessoesDispensadas` e `nomesSessoes`); renomear e encerrar passam pelo Xirp.
  - UI: `OverviewView`, `TickerView`, `AgentPillsView`, `TituloSessao`, `CompactMiniGrid`.
- **Aprovação e perguntas.** `HookServer.processPermissionRequest/sendApprovalDecision/sendAnswers/resolvePending` e `AppState.pendingApprovals`. As views são `ApprovalView` e `QuestionView`. Também tratam AskUserQuestion e ExitPlanMode.
- **Chat com sessões.** `PromptView` (dentro de IslandViewContent), `SessionChat.swift` (Xirp/TerminalBridge/TranscriptReader) e o estado em `AppState` (`chatSelection`, `chatHeight`, `anexosChat`, `rascunhoChat`). O gesto elástico de altura fica em `IslandWindowController.handleChatScroll`.
- **Arquivos.** `FileDropNSView`/`FileDropHandler`, `UploadSequenceEngine` e `UploadCanvasView`, mais as views `upload/uploading/choose/mail`. O e-mail sai por Resend ou pelo Mail via AppleScript, em `MailView.sendMail`.
- **Brilho, volume e teclas.** `NivelService`. A UI é `NivelBarra` no `IslandContainer`, e o Homie segura um celular ou põe fones via `engine.nivelProp` em `BotCanvasView`. A ilha cresce em `islandSize` e `botPosition` através de `nivelNaIlha`.
- **Mídia.** `MediaService` e `MediaView`. A capa aparece na grade compacta, e música tocando impede a ilha de sumir (`holdVisible`, `syncMode`).
- **Personagem.** `BotEngine`/`BotStyle`/`BotCanvasView`, a saudação em `GreetingCanvasView` e a aparência em `AppState` (`corPersonagem`, `bonePersonagem`, … → `aplicarAparencia()` grava em `BotStyle`, que é estático). Ajustes em `PersonagemAjustes`. Interações (slap, dizzy, love, arrastar para anexar janela) ficam em `IslandWindowController`.
- **Integrações** (n8n, Vercel, Resend, GitHub, Stripe, Cal.com, Notion): pollers, cards em `IslandViewContent` e campos em `AppState`. Estão desligadas por flag.
- **API Claude (busca).** `ClaudeService` e as views `searching/result`. Aparentemente não estão ligadas ao fluxo atual.
- **Ajustes.** `SettingsView` (janela) e `SettingsIslandView` (aba dentro da ilha).
- **Outros.**
  - Option duas vezes e atalho global: `IslandWindowController`.
  - Anexar janela por arrasto do Homie: `IslandWindowController` + `WindowContextCapture`.
  - Modo de captura: `CaptureTool`.
  - Iniciar no login: `SMAppService` em `SettingsView`.

## 3. Estrutura da UI

- **Janela.** Uma `IslandPanel` (NSPanel transparente) fixa de 720×320, que estica até a altura máxima do chat via `fitPanel`. O conteúdo é um container com o `NSHostingView(IslandRootView)` e o `FileDropNSView` por cima, que só recebe drag. O clique-através é feito alternando `ignoresMouseEvents` no loop de 60 Hz. O painel vira key só no chat ou ao renomear.
- **Estados — há dois modelos paralelos:**
  - `IslandMode` (hidden/compact/expanded), em `AppState.mode`, guia a UI.
  - `IslandStateMachine.State` (hidden/petit/home/saudacao) guia os timers de hover e fechamento.
  - Eles são sincronizados à mão (`fsm.syncExpanded()`, `fsm.forceCompact()`, `onTransition → setMode/expand`). O `AppState.syncMode()` muda `mode` direto, sem passar pela FSM.
  - Os tamanhos vêm de `islandSize()` + `IslandConst.viewLayouts[view]!`. O force-unwrap derruba o app se uma view nova não entrar na tabela.
- **Navegação.** `AppState.view: IslandView` é a "rota". O `IslandHeader` tem as abas hardcoded (overview, prompt, media, upload, além do botão settings). O `IslandContentView` faz `ForEach(IslandView.allCases)` e mantém **todas** as views montadas ao mesmo tempo (opacidade 0 e hit-testing desligado nas inativas). O `IslandViewContent` é um `switch` gigante. Alertas abrem a ilha via `NotificationCenter` (`.hookExpand`, `.hookReveal`, `.islandCollapse`). `vistaAntesDoAlerta` guarda a tela anterior.
- **Como uma funcionalidade nova se pluga hoje.** Não há protocolo, registro de módulos nem injeção. Para uma aba nova é preciso:
  1. adicionar um caso em `IslandView` (`IslandTypes.swift`);
  2. adicionar uma entrada em `IslandConst.viewLayouts` (obrigatória por causa do `!`);
  3. adicionar o caso no `switch` de `IslandViewContent`;
  4. adicionar um `TabButton` em `IslandHeader`;
  5. ajustar a lista de "última vista" em `IslandWindowController` (linha 173);
  6. adicionar estado `@Published` e flag `moduloX` com `didSet` para UserDefaults e carga no `init` de `AppState`;
  7. adicionar um `Modulo(...)` em `SettingsView`;
  8. adicionar o `start()` em `AppDelegate.setupIsland`;
  9. se mexer no tamanho ou no Homie da ilha fechada, alterar `islandSize`/`botPosition`/`BotCanvasView` (como fez o `NivelService`).

  A "noção de módulo" que existe hoje são só os booleanos `moduloBrilho`, `moduloVolume`, `moduloAvisoProprio`, `moduloOptionDuplo` e `moduloAnexosChat` em `AppState`.

## 4. Estado global, dados, persistência e permissões

- **Singletons.**
  - `@MainActor` + `ObservableObject`: `AppState`, `NivelService`, `MediaService`, `BotEngine` (este é um por view, via `@StateObject`).
  - `@MainActor` sem `ObservableObject`: `SoundEngine`, `UploadSequenceEngine`, `ClaudeService`.
  - `@unchecked Sendable` com threads e GCD: `HookServer`, `KeychainStore` e todos os pollers.
  - Não há `@Observable` (macro), `actor` nem `@AppStorage`. São 11 usos de `@unchecked Sendable`, em Swift 6 com `-strict-concurrency=complete`.
- **Fluxo de dados.** Serviços escrevem direto em `AppState.shared`. As views recebem `@ObservedObject state` (o `AppState` inteiro) e invalidam a cada `@Published`. A comunicação lateral passa por `NotificationCenter`: há 15 nomes em `IslandWindowController.swift:1110` mais `.hookExpand` em HookServer. Os serviços também se chamam entre si diretamente: `AppState` chama `NivelService.atualizarTeclas()`, `SoundEngine`, `HookServer.recarregarTitulo` e `Xirp`; `MediaService` chama `AppState.syncMode`.
- **Ajustes.** `UserDefaults.standard` com chaves soltas, gravadas em `didSet` e carregadas à mão no `AppState.init`: soundEnabled/Volume, autoCloseInterval, absenceInterval, greetThreshold, hotkey*, modulo*, aparência do personagem, filtros vercel/n8n, activeIntegrations, sessoesDispensadas, nomesSessoes. `Projetos` usa a chave `coresProjetos`. As sessões ficam num arquivo JSON no supportDir.
- **Keychain.** `KeychainStore` (cache carregado uma vez no launch, em `AppDelegate`). Chaves: `anthropic-api-key`, `resend-api-key`, `resend-from`, `n8n-url`, `n8n-api-key`, `vercel-token`, `github-token`, `stripe-api-key`, `calcom-api-key`, `notion-api-key`.
- **Entitlements e permissões.**
  - Target `NotchBuddy`: `ENABLE_SANDBOX: NO`, Hardened Runtime ligado. `Resources/Crew.entitlements` só tem `com.apple.security.automation.apple-events`.
  - Target `CrewAppStore`: sandbox, `network.client`, `files.user-selected.read-write`, `bookmarks.app-scope` e a flag `APPSTORE`, que desliga captura AX e attach.
  - Info.plist: `LSUIElement`, `NSAppleEventsUsageDescription`, `NSAccessibilityUsageDescription` (texto ainda em francês).
  - Em uso: Acessibilidade (event tap de teclas em `NivelService`, AX em `WindowContextCapture`), Automação/AppleEvents (Spotify, Música, Mail, Terminal, iTerm, navegadores), monitores globais de `NSEvent` (keyDown, flagsChanged, mouseDown/Up), framework privado `DisplayServices` e `CGWindowListCopyWindowInfo`.
- **Versão mínima:** macOS 15.0 (`deploymentTarget` e `MACOSX_DEPLOYMENT_TARGET`). Swift 6.0, Xcode 27.

## 5. Acoplamentos e arquivos-deus que travam o crescimento

1. **`IslandViewContent.swift` (3755 linhas).** Todas as telas, os cards das 7 integrações, o chat, o markdown e os botões estão num arquivo só. Um módulo novo, como limpeza de disco ou áudio por app, iria parar aqui.
2. **`AppState` como balde universal.** Ele mistura UI (mode/view), sessões, chat, personagem, módulos, dados de Vercel/Resend/Stripe/Cal/Notion e upload. Toda view observa o objeto inteiro: um `@Published` de qualquer módulo (por exemplo, um uso de memória atualizado a cada segundo) re-renderiza todas as views montadas. O `init` carrega tudo à mão, e os modelos de integração vivem no mesmo arquivo.
3. **`IslandView` como enum fechado**, mais `viewLayouts[view]!`, mais o `switch` e as abas hardcoded em `IslandHeader`. Adicionar uma tela significa editar 4 a 5 lugares, e esquecer o layout causa crash.
4. **`IslandContentView` monta todas as views o tempo todo** (`ForEach(IslandView.allCases)`). Cada módulo novo soma custo de render e de `TimelineView` enquanto a ilha está aberta, mesmo invisível. Exemplos: `TickerShimmerText` e `UploadingView` usam `TimelineView(.animation)`, e `UploadingView` também tem um Timer a 20 Hz (linha 505).
5. **`IslandWindowController` (1150 linhas)** concentra todos os monitores globais e locais de evento. Um módulo que precise de tecla ou gesto (como um atalho de áudio) teria de ser costurado aqui. O controle de tamanho, o chat e o arrasto também estão misturados ali.
6. **Duas máquinas de estado** (`IslandMode` × `IslandStateMachine`) e mudanças de modo vindas de fora (`AppState.syncMode`, `MediaService`, `HookServer.expandIfNeeded`, `NotificationCenter`). Regras de "não sumir" estão espalhadas: `fsm.holdVisible` é uma closure que conhece música, aprovações e estados de sessão, e `baseMode()` repete parte dessa lógica.
7. **Ilha fechada acoplada a casos específicos.** `islandSize`/`botPosition`/`nivelNaIlha` e `BotCanvasView` consultam `NivelService.shared` e `MediaService.shared` diretamente. Um terceiro "HUD" (por exemplo, volume por app) exigiria mais `if` nesses lugares.
8. **Barramento por `NotificationCenter` com nomes globais e objetos não tipados** (`object as? IslandView`).
9. **Ajustes sem modelo.** O `SettingsView` tem 837 linhas e `@State` para cada chave do Keychain; a seção Módulos é uma lista manual de `Modulo(...)`.
10. **Infra de processo duplicada.** `osascript` e `Process` estão reimplementados em `MediaService.osascript`, `TerminalBridge.run`, `Xirp.run` e `MailView`. Logs também estão duplicados (`NivelService.log` e `HookServer.nbLog`).
11. **Sandbox desligado na build usada.** Módulos como limpeza de disco ou áudio por app (que provavelmente exigiria Core Audio taps ou drivers) cabem nesse modelo, mas o target App Store compila o mesmo código e ficaria inconsistente sem `#if APPSTORE`.
12. **Código e campos legados.** `ClaudeService` não é usado. Campos de integração ficam em `AgentTask` (`isIntegration`, `source: .n8n` usado para todas as integrações), e `AgentTask.==` é escrito à mão.

## 6. Desempenho em repouso (ilha escondida)

O que já economiza:
- `BotCanvasView` usa `TimelineView(.animation(paused: state.mode == .hidden && NivelService.shared.atual == nil))`, então o Homie principal para quando a ilha está escondida.
- Com a ilha escondida, `IslandContentView`, `GreetingCanvasView`, `UploadCanvasView` e `CompactMiniGrid` (com seus `MiniBotCanvasView`, que não pausam) não estão na árvore, porque só existem em `.expanded` ou `.compact`.
- `NivelService`, `MediaService` e o `HookServer` só reagem a eventos (listeners do CoreAudio, aviso do DisplayServices, `DistributedNotificationCenter`, `accept()` bloqueante numa thread). O comentário no código diz "Sem consulta periódica".
- Os pollers de integração estão desligados (`integracoesLigadas = false`).

O que roda sempre, mesmo escondida:
- **`IslandWindowController.startPolling()`** é um `Timer` de 60 Hz, sem condição, em `RunLoop.main .common`. A cada tick ele cria uma `Task @MainActor`, lê `NSEvent.mouseLocation`, calcula `islandSize`, pode escrever `AppState.mousePosition` (que não é `@Published`) e alimenta a FSM. É ele que detecta o hover para abrir a ilha, então nada o desliga quando ela está escondida.
- **`CountdownBar`** está sempre montada no `IslandContainer` e tem um `Timer` de 0,1 s que roda sempre. Com a ilha não expandida ela só faz `barWidth = 0`.
- **`HookServer`** tem um Timer de 20 s para `pruneDeadSessions`.
- O event tap de teclas (`NivelService`) e os monitores globais de `NSEvent` executam código a cada tecla e clique.

Conclusão: escondida, a ilha não desenha nada, mas não chega a 0% de CPU. O loop de 60 Hz e o timer de 10 Hz acordam o processo continuamente. Pelo que vi, nenhuma medição de CPU está registrada no repo. Para garantir 0% de verdade, o hover precisaria vir de evento (tracking area ou monitor de mouseMoved restrito) e os dois timers teriam de parar quando `mode == .hidden`.
