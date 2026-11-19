import Foundation

// O motor de voz humanizada: o OmniVoice (o mesmo modelo que o VoiceStudio usa por padrão)
// rodando ao lado do Crew como processo nativo à parte — docs/ARQUITETURA.md, "Motores externos".
// Nada dele entra no binário do Crew, e nenhum código do VoiceStudio (AGPL) é usado: o programa
// é o omnivoice.cpp (MIT), compilado neste Mac com Metal na instalação.
//
//   ~/Library/Application Support/NotchBuddy/motores/omnivoice/
//     bin/tts-server        o servidor de fala (HTTP local, só em 127.0.0.1; ~9 MB)
//     bin/versao            o commit do omnivoice.cpp que foi compilado
//     modelos/*.gguf        os pesos (Q8: 945 MB no total)
//     vozes/<id>/           as vozes do Hugo: voz.json + ref.wav (ficam quando o motor é removido)
//     falas/                falas já geradas, para repetir sem gerar de novo (CacheDeFala)
//     instalar.sh           o roteiro da instalação (gerado pelo Crew)
//     servidor.pid          o servidor ligado agora (para limpar sobra se o Crew cair)
//
// Licenças: omnivoice.cpp e ggml são MIT. Os pesos (k2-fsa/OmniVoice, convertidos em
// Serveurperso/OmniVoice-GGUF) são CC BY-NC 4.0: uso não comercial. Fica dito na página.

enum MotorOmniVoice {
    /// Commit do omnivoice.cpp fixado (o que foi testado neste Mac). Atualizar é trocar aqui e reinstalar.
    static let commit = "dbfc792d6fbe0cc3a776817f56de35a3744d7594"
    static let repositorio = "https://github.com/ServeurpersoCom/omnivoice.cpp.git"
    /// Revisão fixada dos pesos no Hugging Face.
    static let revisaoDosPesos = "017094167b5c9ed565a5076ac9b3b93c5ecf5c73"
    /// O ajuste do Crew aplicado por cima do commit na compilação: o servidor passa a aceitar
    /// `num_step` por pedido (a biblioteca do motor já aceita; o servidor original fixa em 32).
    /// Mudou o ajuste, muda o nome: o motor instalado sem ele continua falando, só sem a escolha.
    static let ajuste = "crew1"
    static var versaoEsperada: String { commit + "+" + ajuste }

    struct Peso {
        let arquivo: String
        let sha256: String
        let bytes: Int64
    }

    static let pesos = [
        Peso(arquivo: "omnivoice-base-Q8_0.gguf",
             sha256: "2882d887921798aea13d45236556bdf8012842ab6f8cd2690943eead6289f298", bytes: 656_395_008),
        Peso(arquivo: "omnivoice-tokenizer-Q8_0.gguf",
             sha256: "75204fa566a8e30984e7a1066da6557184c9fd099c8f1bc0cb5b9415edfec255", bytes: 288_889_600),
    ]

    static var pasta: URL { HookServer.supportDir.appendingPathComponent("motores/omnivoice") }
    static var servidor: URL { pasta.appendingPathComponent("bin/tts-server") }
    static var modelos: URL { pasta.appendingPathComponent("modelos") }
    static var vozes: URL { pasta.appendingPathComponent("vozes") }
    static var roteiro: URL { pasta.appendingPathComponent("instalar.sh") }
    static var arquivoPid: URL { pasta.appendingPathComponent("servidor.pid") }
    static var falas: URL { pasta.appendingPathComponent("falas") }
    static var modelo: URL { modelos.appendingPathComponent(pesos[0].arquivo) }
    static var codec: URL { modelos.appendingPathComponent(pesos[1].arquivo) }

    /// Pronto para falar: o programa compilado e os dois arquivos de pesos inteiros.
    static var instalado: Bool {
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: servidor.path) else { return false }
        return pesos.allSatisfy { p in
            let t = (try? fm.attributesOfItem(atPath: modelos.appendingPathComponent(p.arquivo).path)[.size] as? NSNumber)?.int64Value
            return t == p.bytes
        }
    }

    static var versaoInstalada: String? {
        (try? String(contentsOf: pasta.appendingPathComponent("bin/versao"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// O servidor instalado aceita a escolha de velocidade (foi compilado com o ajuste do Crew).
    static var aceitaVelocidade: Bool { versaoInstalada == versaoEsperada }

    // MARK: Ferramentas de que a instalação precisa

    private static let pastasDeBinarios: [String] = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["/opt/homebrew/bin", "/usr/local/bin", home + "/.local/bin", home + "/.cargo/bin", "/usr/bin", "/bin"]
    }()

    private static func achar(_ nome: String) -> String? {
        pastasDeBinarios.map { $0 + "/" + nome }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Como chamar o cmake: o instalado ou, sem ele, o do `uvx` (baixado só para a compilação).
    static var cmake: String? {
        if let c = achar("cmake") { return "'\(c)'" }
        if let u = achar("uvx") { return "'\(u)' cmake" }
        return nil
    }

    /// Por que o motor não pode ser instalado neste Mac (nil = pode).
    static var motivoIndisponivel: String? {
        #if !arch(arm64)
        return "O motor de voz humanizada precisa de um Mac com Apple Silicon."
        #else
        if achar("git") == nil { return "git não encontrado neste Mac (vem com as ferramentas do Xcode: xcode-select --install)." }
        if achar("clang") == nil { return "Compilador não encontrado (ferramentas do Xcode: xcode-select --install)." }
        if cmake == nil { return "cmake não encontrado neste Mac (brew install cmake)." }
        return nil
        #endif
    }

    /// Ambiente dos processos do motor: o PATH de um app aberto pelo Finder não tem o Homebrew.
    static var ambiente: [String: String] {
        var e = ProcessInfo.processInfo.environment
        e["PATH"] = pastasDeBinarios.joined(separator: ":")
        e["GIT_TERMINAL_PROMPT"] = "0"
        // O cmake do uvx fica na pasta do motor e sai no fim da instalação
        e["UV_CACHE_DIR"] = pasta.appendingPathComponent(".uv").path
        if let c = cmake { e["CREW_CMAKE"] = c }
        return e
    }

    // MARK: Instalação

    /// Escreve (ou atualiza) o roteiro da instalação. Não baixa nada.
    static func prepararPasta() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: vozes, withIntermediateDirectories: true)
        try fm.createDirectory(at: modelos, withIntermediateDirectories: true)
        if (try? String(contentsOf: roteiro, encoding: .utf8)) != roteiroDeInstalacao {
            try roteiroDeInstalacao.write(to: roteiro, atomically: true, encoding: .utf8)
        }
    }

    /// Argumentos do roteiro: pasta, commit, revisão, versão gravada e, por peso, "arquivo:sha256".
    static var argumentosDoRoteiro: [String] {
        [roteiro.path, pasta.path, repositorio, commit, revisaoDosPesos, versaoEsperada]
            + pesos.map { "\($0.arquivo):\($0.sha256)" }
    }

    /// Tira o motor do disco (programa e pesos). As vozes do Hugo ficam.
    static func remover() {
        let fm = FileManager.default
        for nome in ["bin", "modelos", "fonte", ".uv", "falas", "instalar.sh", "compilar.log", "servidor.pid"] {
            try? fm.removeItem(at: pasta.appendingPathComponent(nome))
        }
    }

    /// Tamanho do motor em disco (programa + pesos), em bytes.
    static func tamanho() -> Int64 {
        let fm = FileManager.default
        let arquivos = [servidor] + pesos.map { modelos.appendingPathComponent($0.arquivo) }
        return arquivos.reduce(0) { soma, u in
            soma + ((try? fm.attributesOfItem(atPath: u.path)[.size] as? NSNumber)?.int64Value ?? 0)
        }
    }

    static var bytesDosPesos: Int64 { pesos.reduce(0) { $0 + $1.bytes } }

    /// Derruba um servidor que sobrou de uma vez em que o Crew caiu (confere que o processo é
    /// mesmo o servidor do motor antes de sinalizar).
    static func limparSobra() {
        guard let texto = try? String(contentsOf: arquivoPid, encoding: .utf8),
              let pid = Int32(texto.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 1 else { return }
        try? FileManager.default.removeItem(at: arquivoPid)
        var caminho = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &caminho, UInt32(caminho.count)) > 0 else { return }
        let nome = String(decoding: caminho.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        if nome == servidor.path || nome == servidor.resolvingSymlinksInPath().path { kill(pid, SIGTERM) }
    }

    // Um processo só, do começo ao fim: cancelar derruba a árvore inteira (git, cmake, curl).
    // As linhas "PASSO: …" viram o texto da tela; o curl escreve a porcentagem.
    static let roteiroDeInstalacao = #"""
#!/bin/bash
# Instalação do motor de voz humanizada do Crew — gerado pelo app Crew. Não edite: o Crew regrava.
set -euo pipefail
RAIZ="$1"; REPO="$2"; COMMIT="$3"; REVISAO="$4"; VERSAO="$5"; shift 5
CMAKE="${CREW_CMAKE:-cmake}"
passo() { echo "PASSO: $*"; }

if [ ! -x "$RAIZ/bin/tts-server" ] || [ "$(cat "$RAIZ/bin/versao" 2>/dev/null || true)" != "$VERSAO" ]; then
  passo "Baixando o código do motor"
  rm -rf "$RAIZ/fonte"
  mkdir -p "$RAIZ/fonte"
  cd "$RAIZ/fonte"
  git init -q
  git remote add origin "$REPO"
  git fetch -q --depth 1 origin "$COMMIT"
  git checkout -q FETCH_HEAD
  git submodule update -q --init --depth 1
  # Ajuste do Crew: o servidor aceita "num_step" por pedido (a escolha de velocidade).
  # Se o trecho não aplicar, a instalação para aqui e o motor que já existe continua como está.
  git apply --whitespace=nowarn <<'AJUSTE_CREW'
diff --git a/src/tts-server.h b/src/tts-server.h
index a00b997..8f5af4f 100644
--- a/src/tts-server.h
+++ b/src/tts-server.h
@@ -46,6 +46,9 @@ struct tts_request {
     // random seed per request, matching the CLI convention; anything
     // else forwards verbatim for reproducible output.
     int64_t seed;
+
+    // Crew: MaskGIT decode steps for this request, 0 keeps the default.
+    int num_step;
 };
 
 // One voice registration parsed from the POST /v1/audio/voices JSON body.
@@ -174,6 +177,9 @@ static bool tts_parse_request(const std::string & body, tts_request & req, std::
     }
     req.seed = seed ? yyjson_get_sint(seed) : -1;
 
+    yyjson_val * num_step = yyjson_obj_get(root, "num_step");
+    req.num_step          = yyjson_is_int(num_step) ? (int) yyjson_get_sint(num_step) : 0;
+
     yyjson_doc_free(doc);
 
     if (req.format != "pcm" && req.format != "wav") {
diff --git a/tools/tts-server.cpp b/tools/tts-server.cpp
index cf903d0..4d839d0 100644
--- a/tools/tts-server.cpp
+++ b/tools/tts-server.cpp
@@ -247,6 +247,11 @@ int main(int argc, char ** argv) {
         // the MaskGIT sampler for reproducible output.
         p.mg_seed = (req.seed < 0) ? (uint64_t) std::random_device{}() : (uint64_t) req.seed;
 
+        // Crew: fewer MaskGIT steps trade quality for speed.
+        if (req.num_step >= 4 && req.num_step <= 64) {
+            p.mg_num_step = req.num_step;
+        }
+
         // Trampoline : the C ABI on_chunk forwards to the C++ sink.
         const tts_sink * sink_ptr = &sink;
         p.on_chunk                = [](const float * s, int ns, void * u) -> bool {
AJUSTE_CREW
  passo "Compilando o motor para este Mac (cerca de um minuto)"
  mkdir build
  cd build
  if ! { eval "$CMAKE .. -DCMAKE_BUILD_TYPE=Release -DGGML_METAL=ON -DBUILD_SHARED_LIBS=OFF" \
      && eval "$CMAKE --build . --config Release -j $(sysctl -n hw.ncpu) --target tts-server"; } > "$RAIZ/compilar.log" 2>&1; then
    tail -8 "$RAIZ/compilar.log"
    echo "A compilação falhou (registro em $RAIZ/compilar.log)."
    exit 1
  fi
  mkdir -p "$RAIZ/bin"
  # Arquivo novo e troca de nome: regravar por cima um programa que já rodou faz o macOS recusá-lo
  cp tts-server "$RAIZ/bin/tts-server.novo"
  mv -f "$RAIZ/bin/tts-server.novo" "$RAIZ/bin/tts-server"
  echo "$VERSAO" > "$RAIZ/bin/versao"
  cd "$RAIZ"
  rm -rf "$RAIZ/fonte" "$RAIZ/.uv" "$RAIZ/compilar.log"
fi

mkdir -p "$RAIZ/modelos"
N=0
for PAR in "$@"; do
  N=$((N + 1))
  ARQ="${PAR%%:*}"; SHA="${PAR##*:}"
  DEST="$RAIZ/modelos/$ARQ"
  if [ -f "$DEST" ] && [ "$(shasum -a 256 "$DEST" | cut -d' ' -f1)" = "$SHA" ]; then continue; fi
  passo "Baixando a voz ($N de $#)"
  curl -L --fail --progress-bar -C - -o "$DEST.parcial" "https://huggingface.co/Serveurperso/OmniVoice-GGUF/resolve/$REVISAO/$ARQ"
  passo "Conferindo o arquivo ($N de $#)"
  if [ "$(shasum -a 256 "$DEST.parcial" | cut -d' ' -f1)" != "$SHA" ]; then
    rm -f "$DEST.parcial"
    echo "O arquivo $ARQ chegou diferente do esperado. Tente instalar de novo."
    exit 1
  fi
  mv "$DEST.parcial" "$DEST"
done
passo "Pronto"
"""#
}
