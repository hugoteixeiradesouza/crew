import SwiftUI

// Aba dos Modelos na ilha: quanto os modelos locais ocupam, quantos são e o que está carregado
// agora (com a memória). A lista e a remoção ficam na Central.

struct ModelosAba: View {
    @Environment(\.telaVisivel) private var telaVisivel
    private let s = ModelosServico.shared

    var body: some View {
        ZStack {
            CardBackground(wash: nil)
            Group {
                if let v = s.varredura, !v.modelos.isEmpty {
                    cheia(v)
                } else if let v = s.varredura {
                    vazia(v)
                } else {
                    Text("Lendo as pastas de modelos…").font(.system(size: 12)).foregroundColor(FormatoModelos.apagado)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.leading, 108)
            .padding(.trailing, 16)
        }
        .onAppear { if telaVisivel { s.assinar("aba") } }
        .onChange(of: telaVisivel) { _, v in v ? s.assinar("aba") : s.soltar("aba") }
        .onDisappear { s.soltar("aba") }
    }

    private func cheia(_ v: VarreduraModelos) -> some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Em disco").font(.system(size: 10.5)).foregroundColor(FormatoModelos.rotulo)
                Text(FormatoModelos.bytes(v.totalDisco))
                    .font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit()
                Text(FormatoModelos.contagem(v))
                    .font(.system(size: 11)).foregroundColor(FormatoModelos.rotulo).lineLimit(1)
            }
            .frame(width: 185, alignment: .leading)

            Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1, height: 58)

            VStack(alignment: .leading, spacing: 5) {
                Text("Carregado agora").font(.system(size: 10.5)).foregroundColor(FormatoModelos.rotulo)
                if let c = s.carregados {
                    if c.isEmpty {
                        Text("Nenhum: o Ollama está de pé, sem modelo na memória.")
                            .font(.system(size: 11.5)).foregroundColor(FormatoModelos.apagado).lineLimit(2)
                    }
                    ForEach(c.prefix(2)) { m in
                        HStack(spacing: 6) {
                            Circle().fill(FormatoModelos.corAtivo).frame(width: 6, height: 6)
                            Text(m.nome).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 4)
                            Text(FormatoModelos.bytes(m.memoria)).font(.system(size: 11.5)).monospacedDigit()
                                .foregroundColor(FormatoModelos.rotulo)
                        }
                    }
                    if c.count > 2 {
                        Text("+ \(c.count - 2) nos Ajustes").font(.system(size: 10.5)).foregroundColor(FormatoModelos.apagado)
                    }
                } else {
                    Text(v.binarioOllama == nil && !v.modelos.contains { $0.origem == .ollama }
                         ? "Ollama não instalado." : "Ollama parado: nada na memória.")
                        .font(.system(size: 11.5)).foregroundColor(FormatoModelos.apagado).lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            botaoAtualizar
        }
    }

    private func vazia(_ v: VarreduraModelos) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Nenhum modelo local neste Mac").font(.system(size: 13.5, weight: .semibold))
                Text(v.binarioOllama != nil
                     ? "O Ollama está instalado, mas sem modelos. Um `ollama pull` e ele aparece aqui."
                     : "Baixe um pelo Ollama ou pelo LM Studio e ele aparece aqui, com o tamanho real e o que está carregado.")
                    .font(.system(size: 11.5)).foregroundColor(FormatoModelos.rotulo)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            botaoAtualizar
        }
    }

    private var botaoAtualizar: some View {
        Button { s.atualizar() } label: {
            Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .semibold))
                .rotationEffect(.degrees(s.varrendo ? 180 : 0))
                .animation(.easeInOut(duration: 0.4), value: s.varrendo)
        }
        .buttonStyle(IconButtonStyle())
        .foregroundColor(Color(hex: "#F1F2F4"))
        .help("Ler as pastas de novo")
    }
}
