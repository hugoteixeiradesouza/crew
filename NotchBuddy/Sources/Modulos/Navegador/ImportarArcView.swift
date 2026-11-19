import SwiftUI

// A folha "Importar do Arc": mostra o que há em cada perfil do Arc (espaços, abas, contas),
// o Hugo marca quais entram e confirma. Nada é gravado antes do clique em "Importar".

struct ImportarArcView: View {
    let fechar: () -> Void
    @ObservedObject private var s = NavegadorServico.shared

    private enum Fase: Equatable { case lendo, pronto, trabalhando, feito(String) }
    @State private var fase = Fase.lendo
    @State private var perfis: [ArcLeitor.Perfil] = []
    @State private var escolhidos: Set<String> = ["Default"]

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).onTapGesture { if fase != .trabalhando { fechar() } }
            VStack(alignment: .leading, spacing: 12) {
                Text("Importar do Arc").font(Tema.titulo(16, .bold)).foregroundStyle(Tema.texto)
                conteudo
            }
            .padding(22)
            .frame(width: 470)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Tema.elevado))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Tema.bordaForte))
            .shadow(color: .black.opacity(0.5), radius: 40, y: 16)
        }
        .task {
            perfis = await Task.detached { ArcLeitor.previa() }.value
            // Vem tudo marcado: os espaços do Arc costumam morar fora do perfil padrão.
            escolhidos = Set(perfis.map(\.pasta))
            fase = .pronto
        }
    }

    @ViewBuilder
    private var conteudo: some View {
        switch fase {
        case .lendo:
            HStack(spacing: 8) { ProgressView().controlSize(.small); texto("Olhando o que o Arc tem neste Mac…") }
        case .trabalhando:
            HStack(spacing: 8) { ProgressView().controlSize(.small); texto("Trabalhando… se o macOS pedir a chave do Arc, é agora.") }
        case .feito(let resumo):
            texto(resumo)
            HStack { Spacer(); BotaoPilula(titulo: "Fechar", estilo: .ambar, altura: 34, acao: fechar) }
        case .pronto:
            if perfis.isEmpty {
                texto(ArcLeitor.instalado ? "Não achei nada para importar no Arc." : "O Arc não foi encontrado neste Mac.")
            } else {
                texto("Marque os perfis do Arc que entram. As abas viram espaços e abas fixadas; as contas (cookies) deixam os sites já logados. Senhas salvas não entram.")
                VStack(spacing: 6) { ForEach(perfis) { linha($0) } }
                texto("Para ler as contas, o macOS vai pedir a senha do seu usuário para liberar a chave “Arc Safe Storage”. Use “Permitir” (uma vez). Cada perfil que não é o padrão fica com as contas separadas, como no Arc. Nada no Arc é alterado.")
                    .font(.system(size: 11.5))
            }
            HStack(spacing: 8) {
                if s.temImportacaoDoArc {
                    Button { desfazer() } label: {
                        Text("Desfazer a importação").font(.system(size: 12.5, weight: .medium)).foregroundStyle(Tema.vermelho.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                    .help("Tira os espaços, as abas e as contas que vieram do Arc; o que já era do Crew fica")
                }
                Spacer()
                BotaoPilula(titulo: "Cancelar", estilo: .discreto, altura: 34, acao: fechar)
                BotaoPilula(titulo: "Importar", icone: "square.and.arrow.down", estilo: .ambar, altura: 34) { importar() }
                    .disabled(escolhidos.isEmpty || perfis.isEmpty)
            }
            .padding(.top, 4)
        }
    }

    private func texto(_ t: String) -> some View {
        Text(t).font(.system(size: 13)).foregroundStyle(Tema.texto2).lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func linha(_ p: ArcLeitor.Perfil) -> some View {
        let marcado = escolhidos.contains(p.pasta)
        return Button {
            if marcado { escolhidos.remove(p.pasta) } else { escolhidos.insert(p.pasta) }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: marcado ? "checkmark.square.fill" : "square")
                    .font(.system(size: 14)).foregroundStyle(marcado ? Tema.azul : Tema.texto3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.nome).font(.system(size: 13, weight: .medium)).foregroundStyle(Tema.texto)
                    Text(resumo(p)).font(.system(size: 11.5)).foregroundStyle(Tema.texto3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.white.opacity(marcado ? 0.09 : 0.045)))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(marcado ? Tema.azul.opacity(0.45) : Tema.borda))
            .contentShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
    }

    private func resumo(_ p: ArcLeitor.Perfil) -> String {
        var partes: [String] = []
        if !p.espacos.isEmpty {
            let nomes = p.espacos.map { "\($0.titulo) (\($0.abas.count))" }.joined(separator: ", ")
            partes.append(p.espacos.count == 1 ? "1 espaço: \(nomes)" : "\(p.espacos.count) espaços: \(nomes)")
        } else {
            partes.append("nenhum espaço")
        }
        if !p.favoritos.isEmpty { partes.append("\(p.favoritos.count) favorito\(p.favoritos.count == 1 ? "" : "s")") }
        partes.append(p.cookies == 0 ? "sem contas" : "\(p.cookies) cookies de \(p.sites) sites")
        return partes.joined(separator: " · ")
    }

    private func importar() {
        let alvo = perfis.filter { escolhidos.contains($0.pasta) }
        fase = .trabalhando
        Task {
            let r = await s.importarDoArc(alvo)
            var t = "Entraram \(r.espacos) espaço\(r.espacos == 1 ? "" : "s"), \(r.abas) aba\(r.abas == 1 ? "" : "s") e \(r.cookies) cookies."
            if r.jaExistiam > 0 { t += " \(r.jaExistiam) cookies já existiam no Crew e ficaram como estavam." }
            if let e = r.erro { t += "\n\nFicou de fora: \(e)" }
            fase = .feito(t)
        }
    }

    private func desfazer() {
        fase = .trabalhando
        Task {
            let r = await s.desfazerImportacaoDoArc()
            fase = .feito("Saíram \(r.espacos) espaço\(r.espacos == 1 ? "" : "s"), \(r.abas) aba\(r.abas == 1 ? "" : "s") e \(r.cookies) cookies do armazenamento comum, mais as contas dos perfis separados.")
        }
    }
}
