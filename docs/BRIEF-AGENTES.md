# Brief comum — sessão (agente) que mexe no Crew

O Crew é o app de notch do Hugo (Swift 6 + SwiftUI/AppKit, macOS 15+, sem dependências). O Hugo lê
consequência, não código; tudo em português (UI, comentários, commits, relatório).

## Antes de tudo
1. Leia `CLAUDE.md` e `docs/ARQUITETURA.md` inteiros (a seção 0 — Missão — vale acima de tudo).
2. Crie a worktree: `scripts/sessao.sh <nome>` e trabalhe SÓ em `.coucou-sessoes/<nome>` (caminhos
   absolutos). Nunca edite a raiz. Nada de EnterWorktree nem worktree do Xirp.
3. Referências prontas: `Modulos/Sistema/` (módulo, serviço @Observable, leitores fora da main, aba
   com `\.telaVisivel`, página na Central), `Nucleo/` (`Modulo`, `Registro`, `Ajustes`/`Gravar`,
   `Log`, `Processo`, `Amostrador`, `Arbitro`, `IAdoMac`, `Automacao`), `Ilha/Componentes/`
   (CardBackground, BlocoPainel…), `Secao` em `Ajustes/SettingsView.swift`.

## Regras
- Módulo novo em `Modulos/<Nome>/`; fora da pasta, só o mínimo (uma linha em `Registro.swift`,
  cena em `App/CaptureTool.swift`, `project.yml` se precisar de Info.plist). Mexer em `Ilha/` ou no
  núcleo só se a tarefa pedir — diga no relatório o que mudou fora do módulo.
- Na ilha só entra o que é de uso diário; nada clicável embaixo da câmera do notch (o cabeçalho já
  desvia). Visual no padrão das abas Sistema/Áudio (o Hugo aprovou: colunas, títulos pequenos em
  caixa alta, ícones redondos, nomes curtos). Mudança visual vai com prévia (capturas).
- CPU: zero trabalho sem tela olhando; leitura periódica só por assinatura (`Amostrador`); evento
  antes de polling; subprocesso só via `Processo.rodar`, nunca na main e nunca no ciclo de leitura.
- Nada destrutivo ou que saia do Mac sem clique do Hugo, com confirmação dizendo o que acontece.
  Apagar = Lixeira. Brilho automático NUNCA aparece na ilha (ver `NivelService.brilhoMudou`).
- Código de terceiros: MIT pode portar, sem citar a origem; GPL não —
  só a técnica.
- Swift 6 estrito: bloco que roda fora da main não pode nascer dentro de método @MainActor sem
  `@Sendable`/`nonisolated` (o runtime derruba o app). Sem warnings novos.
- `NotchBuddy.xcodeproj` NÃO é versionado. Ajustes do app só via `Gravar` (no modo de capturas nada
  é gravado). Capturas desenham fora da tela.

## Verificar
1. Compilar: `cd <worktree>/NotchBuddy && xcodegen -q && xcodebuild -scheme NotchBuddy -configuration
   Debug -derivedDataPath /tmp/dd-<nome> build`.
2. Capturas: acrescente cena(s) em `App/CaptureTool.swift`; rode `<app Debug>/Contents/MacOS/Crew
   --capturas <pasta> [--so <prefixo>]` e OLHE as imagens. Ajuste até ficar no padrão.
3. Destrutivo: teste a política em modo leitura; nada do Hugo é apagado durante o teste.
4. `scripts/instalar.sh` (se outra sessão estiver instalando, espere e repita). Meça CPU 60 s com a
   tela do módulo fechada (`ps -o time=`), e `sample <pid> 8` sem nada do módulo.
5. Commits só dos seus arquivos (`git status` + `git log -5`; nunca `git add -A`), em português,
   terminando com `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
6. Atualize `docs/ARQUITETURA.md` (o que foi feito, com data, e o que falta).
7. `scripts/integrar.sh`. Conflito em arquivos compartilhados: mantenha os dois lados, compile.

## Relatório final (curto, português)
O que o Hugo ganhou (consequência), o que ficou de fora e por quê, permissões novas, commit
integrado. Só números medidos.
