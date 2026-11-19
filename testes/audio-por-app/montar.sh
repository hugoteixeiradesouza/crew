#!/bin/zsh
# Monta os dois apps do teste (tocador de seno e medidor do som que sai) em ./build.
set -e
T=${0:a:h}; B=$T/build; rm -rf $B; mkdir -p $B
for par in "TocaTeste:tocador" "MedidorTeste:medidor"; do
  nome=${par%%:*}; fonte=${par##*:}
  A=$B/$nome.app/Contents; mkdir -p $A/MacOS
  cp $T/$nome-Info.plist $A/Info.plist
  swiftc -O $T/$fonte.swift -o $A/MacOS/$nome
  codesign -s - --force $B/$nome.app >/dev/null
done
echo "Pronto: $B"
