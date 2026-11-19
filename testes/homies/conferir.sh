#!/bin/zsh
# Confere as regras dos Homies (time, página da rotina, pedido da rotina) fora do app.
#   testes/homies/conferir.sh
set -e
RAIZ="$(cd "$(dirname "$0")/../.." && pwd)"
SAIDA="${TMPDIR:-/tmp}/crew-conferir-homies"
mkdir -p "$SAIDA"
swiftc -O -parse-as-library -o "$SAIDA/conferir" \
  "$RAIZ/NotchBuddy/Sources/Modulos/Homies/Politicas/PoliticaHomies.swift" "$RAIZ/NotchBuddy/Sources/Nucleo/Usuario.swift" "$RAIZ/NotchBuddy/Sources/Modulos/Homies/Politicas/FerramentasHomie.swift" "$RAIZ/testes/homies/conferir.swift"
"$SAIDA/conferir"
