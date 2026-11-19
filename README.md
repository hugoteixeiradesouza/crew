# Crew

**Crew** é um app de notch para o Mac: o **Homie** — o personagem de boné que mora no notch do
MacBook — acompanha as sessões do Claude Code (uma por sessão), traz aprovações, perguntas e
entregas para responder ali mesmo, e junta num lugar só o que o Mac oferece a quem trabalha com
IA: janela de trabalho com as conversas, Homies com função fixa, rotinas, voz, captura de tela,
navegador, monitor do sistema e música.

## Instalar

O repositório é privado: você precisa ter sido adicionado a ele. Não há app pronto para baixar;
cada um compila o seu, no próprio Mac.

**Precisa ter**

- macOS 15 ou mais novo, de preferência num MacBook com notch;
- [Xcode](https://apps.apple.com/app/xcode/id497799835) completo, aberto ao menos uma vez
  (testado com o Xcode 27);
- [Homebrew](https://brew.sh), e por ele: `brew install xcodegen tmux`;
- [Claude Code](https://claude.com/claude-code) instalado e com login feito (`claude` no terminal).

**Instalar**

```
git clone https://github.com/hugoteixeiradesouza/crew.git
cd crew
scripts/instalar.sh
```

O script compila, põe o `Crew.app` em `/Applications` e abre. Se faltar algo, ele diz o quê.
A primeira compilação leva alguns minutos.

**Primeiro uso**

1. No Crew, abra os Ajustes, vá à página **Claude Code** e clique em **Instalar hooks**: é o que liga o Claude Code
   ao notch. O Crew mostra o que vai mudar no `~/.claude/settings.json`, guarda uma cópia e só
   grava depois do seu sim.
2. O macOS pede cada permissão (Acessibilidade, microfone, gravação de tela…) na primeira vez em
   que a ferramenta que precisa dela é usada. A página **Crew** dos Ajustes mostra o que já foi liberado.
3. Nos Ajustes, página **Crew**, seção **Você**, confira como o Crew te chama (vem do nome da conta do Mac).

**Atualizar**

```
git pull
scripts/instalar.sh
```

`scripts/instalar.sh --anterior` volta para o build de antes; `--status` diz o que está instalado.

### Assinatura

O instalador assina com o que achar neste Mac (`scripts/assinatura.sh` mostra o quê):

- **Certificado Apple Development** (recomendado): o macOS reconhece o app de uma atualização
  para a outra e as permissões ficam. Para criar: Xcode › Settings › Accounts, entre com seu
  Apple ID (serve a conta gratuita) › Manage Certificates › **+** › Apple Development.
- **Sem certificado**: o app é assinado localmente e roda igual, mas a cada atualização o macOS
  pede as permissões de novo.

Quem tem mais de um certificado escolhe o time com `CREW_TEAM=XXXXXXXXXX scripts/instalar.sh`.

## Adaptar

O código é seu para mexer. `docs/ARQUITETURA.md` explica a estrutura: cada funcionalidade é uma
pasta em `NotchBuddy/Sources/Modulos/`, com um contrato de módulo. O fluxo de trabalho com várias
sessões do Claude Code no mesmo repositório (`scripts/sessao.sh`, `scripts/integrar.sh`) está no
[`CLAUDE.md`](CLAUDE.md); para só compilar o que você mudou, basta `scripts/instalar.sh`.

Para compilar sem instalar:

```
cd NotchBuddy && xcodegen && xcodebuild -scheme NotchBuddy -configuration Debug build
```
