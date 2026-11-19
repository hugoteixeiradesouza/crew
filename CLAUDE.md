# Crew — o app de notch do Hugo

**Crew** é o app; **Homie** é o personagem que mora no notch. São esses os nomes em tudo que
alguém lê: app, menus, janelas, textos, documentação. (O personagem já se chamou Hook; agora
é Homie.)

Repositório privado (`hugoteixeiradesouza/crew`). Instalado como `/Applications/Crew.app`.

**Não citar apps de terceiros** como origem ou referência em código, comentário, tela ou
documento, nem trazer de volta arquivo de licença ou de crédito (decisão do Hugo,
2026-11-19: repositório limpo; se um dia o Crew for vendido, ele revê a origem de cada parte).

**Nomes técnicos herdados que ficam como estão** (mudar quebraria o que já funciona):
- bundle id `fr.louisraille.NotchBuddy` — Keychain, ajustes, permissões e item de início dependem dele;
- pasta/target/scheme `NotchBuddy` do Xcode e `~/Library/Application Support/NotchBuddy/` (o
  `nb-hook` instalado no `~/.claude/settings.json` aponta para lá);
- `~/.claude/coucou/`, a chave `coucouHooksInstalled` e `.coucou-sessoes/`.

**No código, o desenho do personagem é `BotEngine` / `BotConst` / `BotStyle`** (e o boné,
`drawHomieCap`). "Hook" no código (`HookServer`, `nb-hook`) é sempre o hook do Claude Code.

Repositório privado, compartilhado com quem o Hugo convida; cada um compila e instala o seu
(ver `README.md`). O ícone já é nosso; os sons ainda são herdados e falta trocar.

## Branches e remotes

- `estavel` — a nossa versão, o que fica instalado. Branch padrão no GitHub.
- `feat/<nome>` — trabalho de uma sessão, numa worktree própria.
- `origin` = nosso repo privado. **Nunca** abrir PR nem dar push em outro remote.

## Fluxo de trabalho — várias sessões ao mesmo tempo

A raiz `~/dev/crew` fica em `estavel` e **ninguém edita nela**. Cada sessão:

1. `scripts/sessao.sh <nome>` → cria `~/dev/crew/.coucou-sessoes/<nome>` (oculta, no
   `.gitignore`) no branch `feat/<nome>`.
   Trabalhe **só** dentro dessa pasta (caminhos absolutos).
2. Para o Hugo ver: `scripts/instalar.sh` de dentro da worktree. Roda xcodegen, compila e
   troca o app em `/Applications`. O Hugo testa no notch.
3. Commits atômicos só nos seus arquivos (`git status` + `git log -5` antes; nunca `git add -A`).
4. Aprovado: `scripts/integrar.sh` → rebase em cima do `estavel`, confere o build, avança o
   `estavel`, envia ao GitHub, instala e remove a worktree.

O app instalado é **um só** para todas as sessões: quem instalou por último é o que roda.
`scripts/instalar.sh --status` diz qual branch/commit/worktree está instalado. Travas impedem
duas instalações ou integrações simultâneas — se aparecer "outra sessão está…", espere e repita.

Voltar: `scripts/instalar.sh --anterior` (build anterior) ou `--oficial` (app que estava instalado
antes do primeiro build nosso, guardado na primeira troca). Estado e logs: `~/Library/Application Support/Crew-dev/`.

Não use worktree do Xirp/Chirp (`--new-branch`) nem `EnterWorktree`: o isolamento é por
`scripts/sessao.sh`.

## Build

Sempre pelos scripts. `project.yml` é a fonte; o `.xcodeproj` é regenerado pelo xcodegen a cada
build (`brew install xcodegen`) e **não é versionado** (está no `.gitignore`). A assinatura é a de quem
compila, descoberta por `scripts/assinatura.sh` (certificado "Apple Development" das chaves do Mac ou,
sem certificado, assinatura local) e passada por linha de comando — o `project.yml` continua com um
time herdado, que os scripts sobrepõem. Nada de time, nome ou caminho de uma pessoa fixo no código: o repositório é
compartilhado e cada um instala o seu (ver `README.md`); o nome de quem usa vem de `Usuario`
(`Nucleo/Usuario.swift`), nunca escrito à mão num texto.

## Arquitetura

O Crew cresce como **central de IA + Mac**, em módulos. **Leia `docs/ARQUITETURA.md` antes de
mexer**: estrutura de pastas, contrato de módulo, roteiro e decisões. Funcionalidade nova é
pasta nova em `NotchBuddy/Sources/Modulos/`, nunca mais um pedaço num arquivo central.
O mapa do Crew antes da reorganização está em `docs/pesquisa/`.

## Regras desta versão

- **O Crew é independente do Xirp** (decisão do Hugo, 2026-11-12: ele parou de usar). Sessões
  vêm do motor do Crew (tmux + CLI) e do terminal. Nada novo depende do Xirp nem o cita na
  interface; o código antigo dele (canal de conversa, histórico, renomear/parar) sai aos poucos.
- `~/.claude/settings.json` é de todas as sessões do Hugo, em todos os projetos. Só o botão
  "Install hooks" do app mexe nele (backup + diff + confirmação). O Xirp já tem hooks próprios
  lá (inclusive `PermissionRequest`): não remover nem alterar os dele.
- O hook nunca pode travar o Claude Code; aprovar permissão só com clique explícito do Hugo.
- UI e comentários novos em português.

---

# Guia do código (ainda vale)


Crew is a native macOS app: Homie, a small animated character living in the MacBook notch, shows Claude Code sessions and a few integrations, and lets the user approve, answer, chat and drop files from the notch.

## Where things are
- `NotchBuddy/Sources/` — all Swift code, organized by area and module: `App/`, `Nucleo/`, `Ilha/`, `Homie/`, `Ajustes/`, `Modulos/<Modulo>/`. See `docs/ARQUITETURA.md`. `NotchBuddy/Resources/sounds/` — the 28 WAV sounds. `NotchBuddy/project.yml` — XcodeGen project (never edit the `.xcodeproj` by hand).
- `docs/SPEC.md`, `docs/INTEGRATIONS.md` — behaviour, views, states, integrations (in French).
- `design/prototype/crew.html` — original prototype, the visual source of truth. `design/captures/` — target screenshots.

## Build
```
cd NotchBuddy && xcodegen && xcodebuild -scheme NotchBuddy -configuration Debug build
```

## Rules
- Swift 6, SwiftUI + AppKit. No third-party dependencies unless truly unavoidable. The character is drawn in code (`Canvas` + `TimelineView`), no Rive/Lottie/images.
- Secrets live in the Keychain, never on disk or in git.
- No telemetry. Network calls only to services the user configured.
- Never block Claude Code: if the app doesn't answer, the hook exits immediately.
- Never overwrite `~/.claude/settings.json`: dated backup, merge, show the diff, write only after the user confirms.
- Never send an email or approve a Claude Code permission without an explicit click.
- Performance: 0 % CPU when the island is hidden.
- Keep the bundle identifier `fr.louisraille.NotchBuddy` (Keychain items, preferences and permissions depend on it).
- Visual changes must match the prototype and the screenshots in `design/captures/`.
