#!/bin/bash
# Leva o trabalho de uma sessão para `estavel`, publica e instala.
# Rode de dentro da worktree da sessão, com tudo commitado.
#
#   scripts/integrar.sh            integra, envia ao GitHub e instala o estavel
#   scripts/integrar.sh --manter   idem, mas não apaga a worktree no fim
set -euo pipefail

HERE="$(git rev-parse --show-toplevel)"
ROOT="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")"
BRANCH="$(git -C "$HERE" branch --show-current)"
STATE="$HOME/Library/Application Support/Crew-dev"
# Antes da migração (primeira instalação do Crew) o estado ainda está no nome antigo
[ -d "$STATE" ] || STATE="$HOME/Library/Application Support/Coucou-dev"
LOCK="$STATE/integrar.lock"

[ "$HERE" != "$ROOT" ] || { echo "Rode de dentro da worktree da sessão, não da raiz."; exit 1; }
[[ "$BRANCH" == feat/* ]] || { echo "Branch inesperado: $BRANCH"; exit 1; }
git -C "$HERE" diff --quiet HEAD -- && [ -z "$(git -C "$HERE" ls-files --others --exclude-standard)" ] \
    || { echo "Há alterações não commitadas nesta worktree. Commite antes."; exit 1; }

mkdir -p "$STATE"
if ! mkdir "$LOCK" 2>/dev/null; then
    owner="$(cat "$LOCK/info" 2>/dev/null || true)"
    pid="${owner%% *}"
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        echo "Outra sessão está integrando agora: $owner"
        exit 1
    fi
    rm -rf "$LOCK"; mkdir "$LOCK"
fi
echo "$$ $HERE $(date +%H:%M:%S)" > "$LOCK/info"
trap 'rm -rf "$LOCK"' EXIT

[ "$(git -C "$ROOT" branch --show-current)" = "estavel" ] \
    || { echo "A raiz $ROOT não está em estavel. Não mexo nela."; exit 1; }
git -C "$ROOT" diff --quiet HEAD -- \
    || { echo "A raiz $ROOT tem alterações não commitadas. Não mexo nela."; exit 1; }

# Traz o que outras sessões já integraram.
git -C "$ROOT" pull -q --ff-only origin estavel

# O histórico do estavel foi refeito em 2026-11-19 (um commit só). Branch nascido antes disso não
# tem ancestral em comum com ele: um rebase comum reaplicaria o histórico antigo inteiro.
if ! git -C "$HERE" merge-base estavel HEAD >/dev/null 2>&1; then
    echo "Este branch nasceu antes da limpeza do histórico (2026-11-19) e não se liga ao estavel de hoje."
    echo "Traga só os commits dele:  git rebase --onto estavel <commit do estavel antigo de onde ele saiu>"
    echo "(o histórico antigo está em ~/Library/Application Support/Crew-dev/historico-antes-da-limpeza.bundle)"
    exit 1
fi

# Reaplica os commits da sessão em cima do estavel atual.
if ! git -C "$HERE" rebase -q estavel; then
    echo "Conflito com o que outra sessão integrou. Resolva aqui, 'git rebase --continue', e rode de novo."
    exit 1
fi

# Garante que o resultado combinado compila antes de publicar.
echo "Conferindo o build combinado…"
# shellcheck source=scripts/assinatura.sh
source "$HERE/scripts/assinatura.sh"
(cd "$HERE/NotchBuddy" && xcodegen generate -q)
if ! xcodebuild -project "$HERE/NotchBuddy/NotchBuddy.xcodeproj" -scheme NotchBuddy -configuration Release \
    -derivedDataPath "$HERE/.build/DerivedData" \
    "${ASSINATURA[@]}" \
    build > "$STATE/ultimo-build.log" 2>&1
then
    grep -E "error:" "$STATE/ultimo-build.log" | sort -u | head -20 || true
    echo "Build falhou depois do rebase; nada foi integrado."
    exit 1
fi

git -C "$ROOT" merge -q --ff-only "$BRANCH"
git -C "$ROOT" push -q origin estavel
echo "Integrado em estavel: $(git -C "$ROOT" log --oneline -1)"

# Mesmo commit do estavel; instala daqui para reaproveitar o build já feito.
"$HERE/scripts/instalar.sh" || { echo "Integrado, mas a instalação falhou; worktree mantida em $HERE."; exit 1; }

if [ "${1:-}" != "--manter" ]; then
    cd "$ROOT"
    git -C "$ROOT" worktree remove "$HERE"
    git -C "$ROOT" branch -q -d "$BRANCH"
    echo "Worktree $HERE removida."
fi
