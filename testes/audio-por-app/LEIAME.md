# Teste manual — volume por app (módulo Áudio, fase 2)

Mede o som que de fato sai de um app enquanto o Crew aplica volume/mudo nele.

1. `./montar.sh` — compila o tocador (seno de 440 Hz baixo) e o medidor em `./build`.
2. O Hugo precisa clicar **Permitir** em "Gravação de Áudio do Sistema" para o **Crew** e para o
   **MedidorTeste** (o medidor só lê o que sai; dá para tirar a permissão dele depois).
3. `./teste-som.sh` — aplica 50 %, 200 %, mudo, remove, mudo + `kill -9` no Crew, e imprime o nível
   medido em cada etapa. Esperado (seno de RMS ~0,021): base ≈ 0,021 · 50 % ≈ 0,005 · 200 % ≈ 0,042 ·
   mudo ≈ 0 · sem ajuste ≈ 0,021 · depois do `kill -9` ≈ 0,021 (o app nunca fica mudo).

O script usa um ajuste de teste nas preferências do Crew (`modulo.audio.porApp`) e apaga no fim.

# Teste manual — saída por app (com AirPods Pro e o alto-falante do Mac)

Precisa da permissão "Gravação de Áudio do Sistema" para o Crew (já concedida em 05/10/2026).
Saída padrão: AirPods. Toque Spotify e um vídeo no Arc ao mesmo tempo.

1. Ilha › Áudio › **Apps**: na linha do **Arc**, clique no ícone redondo da saída (tracejado =
   segue a padrão) e escolha o **MacBook**. Ouvir: Spotify nos AirPods, Arc no alto-falante.
   O ícone do Arc fica preenchido (saída fixa).
2. **Desconecte os AirPods** (tire do ouvido e guarde no estojo, ou desligue no Bluetooth).
   Ouvir: o Arc segue no Mac; o Spotify cai para o Mac como sempre (é o macOS trocando a padrão).
3. Volte o Spotify para os AirPods (ícone dele → AirPods) e desconecte de novo. Ouvir: o Spotify
   vai para o Mac na hora (nunca fica mudo) e a ilha avisa "Spotify → MacBook Air (AirPods Pro
   desconectou)". Reconecte: o Spotify volta para os AirPods sozinho ("Spotify → AirPods Pro de novo").
4. Troque a saída padrão do Mac (aba Saídas) com o Arc fixo no Mac: o Arc não muda.
5. Ícone → **Seguir a padrão** (seta) em cada app: tudo volta ao normal do macOS.
6. Central › Áudio: a coluna "Saída" de cada app mostra e troca a mesma escolha.

Já medido sem o Hugo (05/10/2026): app de teste fixo no alto-falante com os AirPods como padrão →
tap no "MacBook Air Speakers" e o alto-falante rodando, Spotify seguindo nos AirPods; saída fixa
inexistente → o app foi para a padrão (AirPods) com o aviso.
