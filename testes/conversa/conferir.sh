#!/bin/zsh
# Confere o leitor da conversa (transcript do Claude Code → falas e passos) fora do app.
# Compila o leitor de agora e o de antes da correção (tirado do git) lado a lado e compara os
# dois contra o que o transcript diz que o Hugo mandou. Só lê os transcripts; não toca no app.
#
#   testes/conversa/conferir.sh                 # caso real + todas as transcrições do projeto
#   testes/conversa/conferir.sh <arquivo.jsonl> # uma transcrição
set -e
RAIZ="$(cd "$(dirname "$0")/../.." && pwd)"
FONTES="$RAIZ/NotchBuddy/Sources/Modulos/Sessoes"
SAIDA="${TMPDIR:-/tmp}/crew-conferir-conversa"
ANTES="76fafe8"   # último commit com o leitor antigo
mkdir -p "$SAIDA"
# Leitor antigo: só a parte de leitura, com os nomes trocados para conviver com o novo.
git -C "$RAIZ" show "$ANTES:NotchBuddy/Sources/Modulos/Sessoes/Chat/SessionChat.swift" \
  | awk '/^\/\/\/ Um pedaço do pedido a entregar/{exit} {print}' \
  | sed -e 's/TranscriptReader/LeitorAntigo/g' -e 's/SessionMessage/FalaAntiga/g' \
        -e 's/LeituraConversa/LeituraAntiga/g' -e 's/AndamentoTurno/AndamentoAntigo/g' \
  > "$SAIDA/LeitorAntigo.swift"
swiftc -O -parse-as-library -o "$SAIDA/conferir" \
  "$FONTES/Chat/SessionChat.swift" "$FONTES/Chat/PassosConversa.swift" \
  "$FONTES/Politicas/TextoDoPedido.swift" "$SAIDA/LeitorAntigo.swift" "$RAIZ/testes/conversa/conferir.swift"
"$SAIDA/conferir" "$@"
