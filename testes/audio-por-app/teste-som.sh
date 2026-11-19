#!/bin/zsh
# Teste do volume por app com som de verdade. Pré-requisito: o Hugo já clicou "Permitir" na
# "Gravação de Áudio do Sistema" para o Crew E para o MedidorTeste (este só mede o que sai).
# Cada etapa: grava o ajuste, reabre o Crew, mede 6 s. Esperado com seno de RMS ~0,021:
#   base ≈ 0,021 · 50% ≈ 0,005 · 200% ≈ 0,042 · mudo ≈ 0 · sem ajuste ≈ 0,021 · mudo + kill -9 ≈ 0,021
T=${0:a:h}/build; M=$T/medidor.txt; D=fr.louisraille.NotchBuddy; K=modulo.audio.porApp
pkill -f MedidorTeste; pkill -f TocaTeste; rm -f $M
open -n $T/MedidorTeste.app --args $M; sleep 3; open -n $T/TocaTeste.app; sleep 3
media() { sleep 6; tail -5 $M | awk '{s+=$3} END {printf "%.4f\n", s/NR}'; }
ajuste() { pkill -x Crew; sleep 1; if [ -z "$1" ]; then defaults delete $D $K 2>/dev/null; else
  defaults write $D $K -dict fr.teste.crew.tocador "<dict><key>v</key><real>$1</real><key>m</key><$2/></dict>"; fi
  open /Applications/Crew.app; sleep 4; }
ajuste; echo "base (sem ajuste): $(media)"
ajuste 0.5 false; echo "50%: $(media)"
ajuste 2.0 false; echo "200%: $(media)"
ajuste 1.0 true; echo "mudo: $(media)"
ajuste; echo "ajuste removido: $(media)"
ajuste 1.0 true; echo "mudo de novo: $(media)"
pkill -9 -x Crew; echo "depois de kill -9 no Crew: $(media)"
defaults delete $D $K 2>/dev/null; open /Applications/Crew.app
pkill -f TocaTeste; pkill -f MedidorTeste
/usr/bin/log show --last 3m --predicate 'subsystem == "fr.louisraille.NotchBuddy" AND category == "audio"' --info --style compact | grep -E "tap|órfão|permiss" | tail -15
