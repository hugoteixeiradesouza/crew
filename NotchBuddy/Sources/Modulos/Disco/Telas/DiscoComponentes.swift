import AppKit
import SwiftUI

// Peças comuns das seções novas do Disco na Central (projetos, simuladores, arquivos, duplicados).

extension DiscoFormato {
    /// "há 12 dias", "há 7 meses", "há 2 anos".
    static func idade(_ d: Date) -> String {
        let dias = Int(Date().timeIntervalSince(d) / 86_400)
        if dias < 1 { return "hoje" }
        if dias < 31 { return dias == 1 ? "há 1 dia" : "há \(dias) dias" }
        let meses = dias / 30
        if meses < 12 { return meses == 1 ? "há 1 mês" : "há \(meses) meses" }
        let anos = dias / 365
        return anos == 1 ? "há 1 ano" : "há \(anos) anos"
    }

    static func curto(_ caminho: String) -> String { (caminho as NSString).abbreviatingWithTildeInPath }
}

/// Linha de estado + botão de procurar, igual em todas as seções.
struct BarraBusca: View {
    let estado: EstadoBusca
    let resumo: String
    let botao: String
    let desabilitado: Bool
    let acao: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            switch estado {
            case .nunca:
                Text("Ainda não procurou.").font(.system(size: 12)).foregroundColor(.secondary)
            case .procurando(let etapa):
                ProgressView().controlSize(.small)
                Text(etapa).font(.system(size: 12)).foregroundColor(.secondary)
            case .pronto(let q):
                Text("Procurado \(DiscoFormato.ha(q)) · \(resumo)").font(.system(size: 12)).foregroundColor(.secondary)
            }
            Spacer()
            Button(estado == .nunca ? botao : "Procurar de novo", action: acao).disabled(desabilitado || estado.procurando)
        }
    }
}

/// Uma linha da confirmação: nome, caminho e tamanho.
struct LinhaConfirmacao: View {
    let nome: String
    let detalhe: String
    let bytes: Int64

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 1) {
                Text(nome).font(.system(size: 12))
                Text(detalhe).font(.system(size: 10.5)).foregroundColor(.secondary).lineLimit(2).truncationMode(.middle)
            }
            Spacer()
            Text(DiscoFormato.bytes(bytes)).font(.system(size: 12)).monospacedDigit()
        }
    }
}

/// Rodapé da confirmação: total e os dois botões.
struct RodapeConfirmacao: View {
    let total: String
    let botao: String
    let ocupado: Bool
    var destrutivo = false
    let cancelar: () -> Void
    let confirmar: () -> Void

    var body: some View {
        Divider()
        HStack {
            Text(total).font(.system(size: 12.5, weight: .semibold)).monospacedDigit()
            Spacer()
            if ocupado { ProgressView().controlSize(.small) }
            Button("Cancelar", action: cancelar).disabled(ocupado)
            if destrutivo {
                Button(botao, role: .destructive, action: confirmar).disabled(ocupado)
            } else {
                Button(botao, action: confirmar).keyboardShortcut(.defaultAction).disabled(ocupado)
            }
        }
    }
}

/// O que ficou de fora numa revalidação ou numa limpeza.
struct ListaRetirados: View {
    let titulo: String
    let itens: [Retirado]

    var body: some View {
        if !itens.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(titulo).font(.system(size: 11, weight: .medium)).foregroundColor(.orange)
                ForEach(Array(itens.prefix(8).enumerated()), id: \.offset) { _, r in
                    Text("\(r.nome): \(r.motivo)").font(.system(size: 11)).foregroundColor(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if itens.count > 8 {
                    Text("e mais \(itens.count - 8)").font(.system(size: 11)).foregroundColor(.orange)
                }
            }
        }
    }
}

/// Resultado de uma ida para a Lixeira.
struct ResultadoLixeira: View {
    let r: ResultadoMover

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(r.movidos.count) \(r.movidos.count == 1 ? "item foi" : "itens foram") para a Lixeira · \(DiscoFormato.bytes(r.bytes)) · \(DiscoFormato.ha(r.quando))")
                .font(.system(size: 11.5, weight: .medium)).foregroundColor(Color(hex: "#34D399")).monospacedDigit()
            Text("O espaço volta quando a Lixeira for esvaziada.").font(.system(size: 11)).foregroundColor(.secondary)
            ListaRetirados(titulo: "Ficaram de fora:", itens: r.falhas)
        }
    }
}

/// Botões de olhar (Quick Look) e "Mostrar no Finder".
struct BotoesArquivo: View {
    let caminho: String
    @Binding var previa: URL?

    var body: some View {
        HStack(spacing: 4) {
            Button { previa = URL(fileURLWithPath: caminho) } label: { Image(systemName: "eye") }
                .buttonStyle(.borderless).help("Olhar (Quick Look)")
            Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: caminho)]) } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless).help("Mostrar no Finder")
        }
    }
}
