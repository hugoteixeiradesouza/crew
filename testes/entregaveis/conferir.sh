#!/bin/zsh
# Confere as regras dos entregáveis da conversa (blocos do markdown, tabela, arquivos citados)
# fora do app: só Foundation, não abre nem toca no Crew.
#
#   testes/entregaveis/conferir.sh
set -e
raiz="${0:A:h:h:h}"
fontes="$raiz/NotchBuddy/Sources/Modulos/Sessoes/Politicas"
saida="$(mktemp -d)/conferir-entregaveis"
swiftc -O -parse-as-library \
  "$fontes/BlocosResposta.swift" "$fontes/RegrasTabela.swift" "$fontes/ArquivosNoTexto.swift" \
  "${0:A:h}/conferir.swift" -o "$saida"
"$saida"
