import SwiftUI

// Painel "Mac agora" (cartão da direita da home): até 4 blocos vindos dos módulos — um número
// ou um controle de relance. O Hugo escolhe quais na Central ("Bloco na home").

struct PainelMac: View {
    @ObservedObject private var registro = Registro.shared

    var body: some View {
        let blocos = registro.blocosHome
        VStack(alignment: .leading, spacing: 5) {
            Text("MAC AGORA").font(.system(size: 9, weight: .bold)).tracking(0.7)
                .foregroundColor(Color(hex: "#7C818A"))
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                ForEach(blocos, id: \.id) { m in m.bloco() }
            }
            if blocos.isEmpty {
                Button { Central.abrir() } label: {
                    Text("Escolha os blocos nos Ajustes").font(.system(size: 11)).foregroundColor(Color(hex: "#8E939C"))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 8).padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Moldura comum dos blocos: ícone/arte à esquerda, valor e legenda à direita. Clique = ação.
struct BlocoPainel<Arte: View>: View {
    let titulo: String
    let legenda: String
    var ajuda: String = ""
    let acao: () -> Void
    @ViewBuilder let arte: Arte
    @State private var sobre = false

    var body: some View {
        Button(action: acao) {
            HStack(spacing: 7) {
                arte.frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 0) {
                    Text(titulo).font(.system(size: 11.5, weight: .semibold)).foregroundColor(Color(hex: "#E8E9EC"))
                        .lineLimit(1).monospacedDigit()
                    Text(legenda).font(.system(size: 9.5)).foregroundColor(Color(hex: "#8E939C")).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 7)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(sobre ? 0.10 : 0.05)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(ajuda)
        .onHover { sobre = $0 }
    }
}

/// Abre a aba do módulo na ilha (ou a página dele na Central, se não tiver aba).
@MainActor
func abrirModulo(_ id: String) {
    NotificationCenter.default.post(name: .abrirIlha, object: id)
}
