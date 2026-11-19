#!/bin/zsh
# Confere as regras do campo de endereço do navegador sem abrir o app.
set -e
raiz="${0:A:h:h:h}"
saida="$(mktemp -d)/conferir-navegador"
swiftc -O -parse-as-library \
  "$raiz/NotchBuddy/Sources/Modulos/Navegador/Politicas/SugestoesEndereco.swift" \
  "${0:A:h}/conferir.swift" -o "$saida"
"$saida"
