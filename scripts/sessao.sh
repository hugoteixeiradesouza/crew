#!/bin/bash
# Cria a worktree de uma sessão nova, a partir de `estavel`.
#
#   scripts/sessao.sh <nome>     cria .coucou-sessoes/<nome> (pasta oculta na raiz) no branch feat/<nome>
#   scripts/sessao.sh --lista    mostra as sessões abertas
#
# Cada sessão do Claude Code trabalha só na sua worktree. A raiz
# (~/dev/crew) fica em `estavel` e só recebe integração.
set -euo pipefail

ROOT="$(git -C "$(dirname "$0")" rev-parse --path-format=absolute --git-common-dir)"
ROOT="$(dirname "$ROOT")"
BASE_DIR="$ROOT/.coucou-sessoes"

if [ "${1:-}" = "--lista" ] || [ -z "${1:-}" ]; then
    git -C "$ROOT" worktree list
    [ -n "${1:-}" ] || { echo; echo "Uso: scripts/sessao.sh <nome>"; }
    exit 0
fi

NAME="$1"
if ! [[ "$NAME" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
    echo "Nome inválido: use minúsculas, números e hífen (ex.: sessoes-xirp)."
    exit 1
fi

BRANCH="feat/$NAME"
DIR="$BASE_DIR/$NAME"

if [ -d "$DIR" ]; then
    echo "Já existe: $DIR (branch $(git -C "$DIR" branch --show-current))"
    exit 0
fi

git -C "$ROOT" fetch -q origin estavel 2>/dev/null || true
# Parte do estavel mais novo entre o local e o do GitHub.
BASE="estavel"
if git -C "$ROOT" rev-parse -q --verify origin/estavel >/dev/null \
    && git -C "$ROOT" merge-base --is-ancestor estavel origin/estavel; then
    BASE="origin/estavel"
fi

mkdir -p "$BASE_DIR"
if git -C "$ROOT" rev-parse -q --verify "$BRANCH" >/dev/null; then
    git -C "$ROOT" worktree add -q "$DIR" "$BRANCH"
else
    git -C "$ROOT" worktree add -q -b "$BRANCH" "$DIR" "$BASE"
fi
echo "Sessão pronta: $DIR (branch $BRANCH, a partir de $BASE)"
