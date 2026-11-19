#!/bin/bash
# Compila a worktree de onde é chamado e instala em /Applications/Crew.app.
#
#   scripts/instalar.sh             compila e instala esta worktree
#   scripts/instalar.sh --anterior  volta o build instalado antes deste
#   scripts/instalar.sh --oficial   volta o app que estava instalado antes do primeiro build nosso
#   scripts/instalar.sh --status    mostra o que está instalado
#
# Precisa do Xcode e do xcodegen. A assinatura é a deste Mac (scripts/assinatura.sh): o
# certificado Apple Development de quem instala ou, sem certificado, assinatura local.
#
# Só existe um app instalado para todas as sessões: a trava impede duas
# instalações ao mesmo tempo.
set -euo pipefail

ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
APP="/Applications/Crew.app"
BUNDLE_ID="fr.louisraille.NotchBuddy"
STATE="$HOME/Library/Application Support/Crew-dev"
LOCK="$STATE/instalar.lock"

# --- migração do nome antigo do app (uma vez) ------------------------------------------
OLD_STATE="$HOME/Library/Application Support/Coucou-dev"
if [ -d "$OLD_STATE" ] && [ ! -d "$STATE" ]; then
    mv "$OLD_STATE" "$STATE"
    for d in anterior oficial; do
        [ -d "$STATE/$d/Coucou.app" ] && mv "$STATE/$d/Coucou.app" "$STATE/$d/Crew.app"
    done
    # Scripts antigos (outras worktrees ainda não rebaseadas) continuam achando o estado e as travas
    ln -s "$STATE" "$OLD_STATE"
fi
mkdir -p "$STATE"

if [ "${1:-}" = "--status" ]; then
    cat "$STATE/instalado.txt" 2>/dev/null || echo "Nenhum build nosso instalado ainda."
    exit 0
fi

# --- trava -------------------------------------------------------------------
if ! mkdir "$LOCK" 2>/dev/null; then
    owner="$(cat "$LOCK/info" 2>/dev/null || true)"
    pid="${owner%% *}"
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        echo "Outra sessão está instalando agora: $owner"
        echo "Espere ela terminar e rode de novo."
        exit 1
    fi
    # Trava órfã de uma instalação que morreu no meio.
    rm -rf "$LOCK"
    mkdir "$LOCK"
fi
echo "$$ $ROOT $(date +%H:%M:%S)" > "$LOCK/info"
trap 'rm -rf "$LOCK"' EXIT

# --- funções -----------------------------------------------------------------
quit_app() {
    osascript -e "quit app id \"$BUNDLE_ID\"" >/dev/null 2>&1 || true
    for _ in $(seq 1 40); do
        pgrep -xq Crew || pgrep -xq Coucou || return 0
        sleep 0.25
    done
    pkill -x Crew 2>/dev/null || true
    pkill -x Coucou 2>/dev/null || true
    sleep 0.5
}

# Sessões do Claude Code de pé no motor do Crew (tmux `crew-<id>`), uma por linha.
sessoes_vivas() {
    tmux list-sessions -F '#{session_name}' 2>/dev/null | grep '^crew-' || true
}

# Troca $2 (instalado) por $1 (novo) sem que o caminho $2 fique um instante sem pacote.
#
# Por quê: as sessões (tmux e Claude Code) são processos filhos do Crew. Quando o Crew fecha,
# o macOS (loginwindow) pergunta ao BTM se o app em /Applications/Crew.app pode manter processos
# de fundo. Se o pacote não estiver lá nessa hora, o BTM não responde (erro -98) e o macOS MATA
# todos os filhos: foi assim que uma instalação derrubou a sessão e os agentes em 2026-11-13.
# Com o pacote sempre presente a resposta é "pode", e as sessões seguem vivas.
trocar_pacote() {
    local novo="$1" destino="$2" palco="${2%.app}.novo.app" velho="${2%.app}.velho.app"
    rm -rf "$palco" "$velho"
    ditto "$novo" "$palco"
    # O ditto mantém a data do pacote compilado (a pasta é reaproveitada entre builds) e o
    # macOS guarda o ícone por caminho + data: sem data nova, Dock e Spotlight seguem com o
    # ícone antigo. Data de agora a cada troca.
    touch "$palco"
    if [ -d "$destino" ]; then
        # renamex_np(RENAME_SWAP): os dois nomes trocam de conteúdo numa operação só.
        if ! /usr/bin/python3 -c 'import ctypes,sys
l=ctypes.CDLL(None,use_errno=True)
sys.exit(0 if l.renamex_np(sys.argv[1].encode(),sys.argv[2].encode(),2)==0 else 1)' "$palco" "$destino" 2>/dev/null; then
            mv "$destino" "$velho" && mv "$palco" "$destino"
        fi
        rm -rf "$palco" "$velho"
    else
        mv "$palco" "$destino"
    fi
}

swap_in() {
    # Troca o app instalado por $1 e abre. As sessões de pé têm de atravessar a troca.
    local antes; antes="$(sessoes_vivas)"
    if [ -n "$antes" ]; then
        echo "Sessões de pé: $(wc -l <<< "$antes" | tr -d ' '). Elas continuam rodando durante a troca."
    fi
    quit_app
    # O macOS decide o destino dos filhos do Crew logo depois que ele fecha: o pacote antigo
    # fica onde está até essa decisão passar.
    sleep 3
    # App ainda com o nome antigo: sai de /Applications e do início de sessão
    if [ -d "/Applications/Coucou.app" ]; then
        rm -rf "/Applications/Coucou.app"
        osascript -e 'tell application "System Events" to delete login item "Coucou"' >/dev/null 2>&1 || true
        MIGROU_LOGIN=1
    fi
    trocar_pacote "$1" "$APP"
    # Se o Crew antigo foi reaberto na espera acima (aconteceu em 2026-11-13: o pacote novo ficou
    # no disco e o antigo seguiu rodando, sem aviso), ele sai de novo — agora com o pacote novo
    # já no lugar — para o `open` abaixo subir o build certo.
    if pgrep -x Crew >/dev/null 2>&1; then
        quit_app
        sleep 3
    fi
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" >/dev/null 2>&1 || true
    # Item de início só depois que o Crew.app existe
    if [ "${MIGROU_LOGIN:-}" = 1 ]; then
        osascript -e 'tell application "System Events" to make login item at end with properties {path:"/Applications/Crew.app", hidden:false}' >/dev/null 2>&1 || true
    fi
    # Logo após fechar o antigo o LaunchServices às vezes recusa (-600/-609): tenta de novo.
    local aberto=""
    for _ in 1 2 3 4 5; do
        if open "$APP" 2>/dev/null; then aberto=1; break; fi
        sleep 1
    done
    [ -n "$aberto" ] || open "$APP"
    conferir_sessoes "$antes"
}

# Depois da troca: toda sessão que estava de pé tem de continuar de pé. Se alguma caiu, diz
# qual e como retomar (a conversa fica salva; o que estava rodando nela, não).
conferir_sessoes() {
    local antes="$1" agora caidas=""
    [ -n "$antes" ] || return 0
    sleep 2
    agora="$(sessoes_vivas)"
    while IFS= read -r s; do
        grep -qxF "$s" <<< "$agora" || caidas="$caidas $s"
    done <<< "$antes"
    if [ -n "$caidas" ]; then
        echo "ATENÇÃO: sessões que CAÍRAM na troca:"
        for s in $caidas; do echo "  $s  (retomar: claude --resume ${s#crew-})"; done
        return 0
    fi
    echo "Sessões conferidas: todas as $(wc -l <<< "$antes" | tr -d ' ') continuam de pé."
}

# --- voltar versões ----------------------------------------------------------
case "${1:-}" in
    --anterior)
        [ -d "$STATE/anterior/Crew.app" ] || { echo "Não há build anterior guardado."; exit 1; }
        swap_in "$STATE/anterior/Crew.app"
        cp "$STATE/anterior/instalado.txt" "$STATE/instalado.txt" 2>/dev/null || echo "build anterior" > "$STATE/instalado.txt"
        echo "Voltou para: $(cat "$STATE/instalado.txt")"
        exit 0
        ;;
    --oficial)
        [ -d "$STATE/oficial/Crew.app" ] || { echo "Cópia do app original não encontrada."; exit 1; }
        swap_in "$STATE/oficial/Crew.app"
        echo "original (app de antes do primeiro build nosso)" > "$STATE/instalado.txt"
        echo "Voltou para o app original."
        exit 0
        ;;
    "") ;;
    *) echo "Opção desconhecida: $1"; exit 1 ;;
esac

# --- o que este Mac precisa ter ------------------------------------------------
if ! xcodebuild -version >/dev/null 2>&1; then
    echo "Falta o Xcode (o completo, da App Store; as Command Line Tools sozinhas não compilam o app)."
    echo "Depois de instalar e abrir uma vez:  sudo xcode-select -s /Applications/Xcode.app"
    exit 1
fi
if ! command -v xcodegen >/dev/null 2>&1; then
    echo "Falta o xcodegen:  brew install xcodegen"
    exit 1
fi
# shellcheck source=scripts/assinatura.sh
source "$ROOT/scripts/assinatura.sh"

# --- compilar ----------------------------------------------------------------
BRANCH="$(git -C "$ROOT" branch --show-current)"
COMMIT="$(git -C "$ROOT" rev-parse --short HEAD)"
DIRTY=""
git -C "$ROOT" diff --quiet HEAD -- 2>/dev/null || DIRTY=" (+ alterações não commitadas)"
DERIVED="$ROOT/.build/DerivedData"
LOG="$STATE/ultimo-build.log"

echo "Compilando $BRANCH@$COMMIT${DIRTY}…"
# O .xcodeproj sai do project.yml; regenera para pegar arquivo novo.
(cd "$ROOT/NotchBuddy" && xcodegen generate -q) || { echo "xcodegen falhou (brew install xcodegen)"; exit 1; }
if ! xcodebuild \
    -project "$ROOT/NotchBuddy/NotchBuddy.xcodeproj" \
    -scheme NotchBuddy \
    -configuration Release \
    -derivedDataPath "$DERIVED" \
    "${ASSINATURA[@]}" \
    build > "$LOG" 2>&1
then
    grep -E "error:" "$LOG" | sort -u | head -20 || true
    echo "Build falhou; nada foi instalado. Log completo: $LOG"
    exit 1
fi
NEW="$DERIVED/Build/Products/Release/Crew.app"

# --- guardar o que está instalado -------------------------------------------
if [ -d "$APP" ]; then
    # O instalado é um build nosso quando este script já registrou uma instalação. (Antes a
    # pergunta era "a assinatura é local?", mas quem não tem certificado também instala assim.)
    NOSSO=""
    if [ -f "$STATE/instalado.txt" ] && ! grep -q '^original' "$STATE/instalado.txt"; then NOSSO=1; fi
    if [ -z "$NOSSO" ]; then
        # Primeira troca: guarda o release original uma vez, para sempre dar para voltar.
        if [ ! -d "$STATE/oficial/Crew.app" ]; then
            mkdir -p "$STATE/oficial"
            ditto "$APP" "$STATE/oficial/Crew.app"
            echo "App original guardado em $STATE/oficial"
        fi
    else
        rm -rf "$STATE/anterior"
        mkdir -p "$STATE/anterior"
        ditto "$APP" "$STATE/anterior/Crew.app"
        cp "$STATE/instalado.txt" "$STATE/anterior/instalado.txt" 2>/dev/null || true
    fi
fi

# --- instalar ----------------------------------------------------------------
swap_in "$NEW"
echo "$BRANCH@$COMMIT$DIRTY · $ROOT · $(date '+%Y-%m-%d %H:%M')" > "$STATE/instalado.txt"

sleep 2
if pgrep -xq Crew || pgrep -xq Coucou; then
    echo "Instalado e aberto: $(cat "$STATE/instalado.txt")"
    if [ "$ASSINATURA_TIPO" = "local" ]; then
        echo "Assinatura local (este Mac não tem certificado Apple Development): a cada atualização o"
        echo "macOS pede de novo as permissões do Crew. Para elas ficarem: Xcode › Settings › Accounts,"
        echo "entre com seu Apple ID e crie um certificado Apple Development; depois rode de novo."
    fi
    # As sessões do Crew rodam o Claude Code dentro do tmux: sem os dois o app abre, mas não há sessão.
    achar() { local n="$1"; shift; command -v "$n" >/dev/null 2>&1 && return 0; for c in "$@"; do [ -x "$c" ] && return 0; done; return 1; }
    achar tmux /opt/homebrew/bin/tmux /usr/local/bin/tmux /usr/bin/tmux \
        || echo "Falta o tmux (as sessões do Crew rodam nele):  brew install tmux"
    achar claude /opt/homebrew/bin/claude "$HOME/.local/bin/claude" "$HOME/.claude/local/claude" /usr/local/bin/claude \
        || echo "Falta o Claude Code (o Crew acompanha e abre sessões dele):  https://claude.com/claude-code"
else
    echo "Instalado, mas o app não ficou aberto. Volte com: scripts/instalar.sh --anterior"
    exit 1
fi
