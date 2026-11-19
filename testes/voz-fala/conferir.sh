#!/bin/zsh
# Confere, fora do app, as regras da voz humanizada que não precisam do motor: o corte do texto
# em pedaços e o guardado de falas (chave, teto, o que sai primeiro). Só Foundation e CryptoKit;
# escreve numa pasta temporária e a apaga. Não abre nem toca no Crew, nem nas vozes do Hugo.
#
#   testes/voz-fala/conferir.sh
set -e
raiz="${0:A:h:h:h}"
fontes="$raiz/NotchBuddy/Sources/Modulos/Voz/Fala"
saida="$(mktemp -d)/conferir-voz-fala"
swiftc -O -parse-as-library \
  "$fontes/PedacosDeFala.swift" "$fontes/CacheDeFala.swift" \
  "${0:A:h}/conferir.swift" -o "$saida"
"$saida"
