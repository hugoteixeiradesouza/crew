import QuickLook
import SwiftUI

// Seções "Arquivos grandes" e "Duplicados" da página do Disco na Central. Arquivo pessoal:
// nada vem marcado e nada disto entra na limpeza de um clique da ilha.

struct ArquivosGrandesCentral: View {
    private let s = ArquivosServico.shared
    @State private var previa: URL?
    /// A lista pode ter milhares: mostra os maiores e diz quantos faltam.
    private let maxLinhas = 200

    var body: some View {
        Group {
            if let lista = s.confirmacao {
                confirmacao(lista)
            } else {
                Secao("Arquivos grandes", descricao) {
                    HStack(spacing: 8) {
                        Text("A partir de").font(.system(size: 12))
                        SeletorCrew(selecao: Binding(get: { s.minimoMB }, set: { s.minimoMB = $0 }),
                                    opcoes: ArquivosServico.opcoesMB.map { mb in
                                        (valor: mb, titulo: mb >= 1000 ? "\(mb / 1000) GB" : "\(mb) MB")
                                    },
                                    largura: 90)
                        Text("usado há mais de").font(.system(size: 12))
                        SeletorCrew(selecao: Binding(get: { s.mesesParado }, set: { s.mesesParado = $0 }),
                                    opcoes: ArquivosServico.opcoesMeses.map { m in
                                        (valor: m, titulo: m == 0 ? "qualquer tempo" : m == 1 ? "1 mês" : "\(m) meses")
                                    },
                                    largura: 130)
                        Spacer()
                    }
                    let lista = s.filtrados
                    BarraBusca(estado: s.estado,
                               resumo: "\(lista.count) \(lista.count == 1 ? "arquivo" : "arquivos") · \(DiscoFormato.bytes(lista.reduce(0) { $0 + $1.bytes }))",
                               botao: "Procurar", desabilitado: s.movendo) { s.procurar() }
                    if let r = s.ultimo { ResultadoLixeira(r: r) }
                    if case .pronto = s.estado {
                        if lista.isEmpty {
                            Text("Nenhum arquivo com esses filtros (\(s.vistos) arquivos olhados).")
                                .font(.system(size: 12)).foregroundColor(.secondary)
                        } else {
                            LazyVStack(alignment: .leading, spacing: 6) {
                                ForEach(lista.prefix(maxLinhas)) { linha($0) }
                            }
                            if lista.count > maxLinhas {
                                Text("Mostrando os \(maxLinhas) maiores de \(lista.count). Aumente o tamanho mínimo para ver o resto.")
                                    .font(.system(size: 11)).foregroundColor(.secondary)
                            }
                            Divider()
                            HStack {
                                Text("Selecionado: \(s.selecionadosItens.count) · \(DiscoFormato.bytes(s.totalSelecionado))")
                                    .font(.system(size: 12, weight: .medium)).monospacedDigit()
                                Spacer()
                                Button("Mover para a Lixeira…") { s.prepararConfirmacao() }
                                    .disabled(s.selecionadosItens.isEmpty || s.movendo)
                            }
                        }
                    }
                }
            }
        }
        .quickLookPreview($previa)
    }

    private var descricao: String {
        let base = "Os maiores arquivos em Documentos, Mesa, Downloads, Filmes, Música e Imagens. Fotos, Música, iMovie, apps e pastas de projeto ficam de fora; nada vem marcado — olhe antes (o olho abre o Quick Look). Vai para a Lixeira."
        return DiscoServico.shared.acesso == .total ? base
            : base + " Sem Acesso Total ao Disco, só Filmes, Música e Imagens (Documentos, Mesa e Downloads fariam o macOS pedir permissão)."
    }

    private func linha(_ a: ArquivoGrande) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Toggle("", isOn: Binding(get: { s.selecionados.contains(a.id) }, set: { _ in s.alternar(a.id) }))
                .toggleStyle(.checkbox).labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                Text(a.nome).font(.system(size: 12.5)).lineLimit(1).truncationMode(.middle)
                Text("\(a.pasta) · usado \(DiscoFormato.idade(a.ultimoUso))")
                    .font(.system(size: 10.5)).foregroundColor(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            BotoesArquivo(caminho: a.caminho, previa: $previa)
            Text(DiscoFormato.bytes(a.bytes)).font(.system(size: 12)).monospacedDigit().frame(minWidth: 64, alignment: .trailing)
        }
    }

    private func confirmacao(_ lista: [ArquivoGrande]) -> some View {
        let total = lista.reduce(Int64(0)) { $0 + $1.bytes }
        return Secao("Confirmar: mover para a Lixeira — arquivos grandes",
                     "São arquivos seus. Ficam na Lixeira até você esvaziá-la (dá para pôr de volta pelo Finder).") {
            ForEach(lista) { a in LinhaConfirmacao(nome: a.nome, detalhe: a.pasta, bytes: a.bytes) }
            ListaRetirados(titulo: "Saíram da lista:", itens: s.retirados)
            RodapeConfirmacao(total: "Total: \(lista.count) \(lista.count == 1 ? "arquivo" : "arquivos") · \(DiscoFormato.bytes(total))",
                              botao: "Mover para a Lixeira", ocupado: s.movendo,
                              cancelar: { s.cancelarConfirmacao() }, confirmar: { s.confirmarMover() })
        }
    }
}

struct DuplicadosCentral: View {
    private let s = ArquivosServico.shared
    @State private var previa: URL?

    var body: some View {
        Group {
            if let lista = s.confirmacaoDup {
                confirmacao(lista)
            } else {
                Secao("Duplicados",
                      "Arquivos iguais byte a byte (a partir de 1 MB), nas mesmas pastas dos arquivos grandes. Só procura quando você pede: compara início e fim, e só confirma com o conteúdo inteiro. Em cada grupo o Crew sugere qual manter (o que mora no lugar \"de verdade\" e não tem nome de cópia) — troque se quiser. Nenhum grupo vem incluído. Hard links ficam de fora; clones do APFS podem liberar menos que o mostrado.") {
                    barra
                    if let r = s.ultimoDup { ResultadoLixeira(r: r) }
                    if case .pronto = s.estadoDup {
                        if s.grupos.isEmpty {
                            Text("Nenhum duplicado encontrado.").font(.system(size: 12)).foregroundColor(.secondary)
                        } else {
                            ForEach(s.grupos.prefix(100)) { grupo($0) }
                            if s.grupos.count > 100 {
                                Text("Mostrando os 100 grupos que mais liberam, de \(s.grupos.count).")
                                    .font(.system(size: 11)).foregroundColor(.secondary)
                            }
                            Divider()
                            HStack {
                                Text("Incluídos: \(s.incluidos.count) \(s.incluidos.count == 1 ? "grupo" : "grupos") · \(DiscoFormato.bytes(s.totalIncluidoDup))")
                                    .font(.system(size: 12, weight: .medium)).monospacedDigit()
                                Spacer()
                                if s.preparandoDup { ProgressView().controlSize(.small) }
                                Button("Mover as cópias para a Lixeira…") { s.prepararConfirmacaoDup() }
                                    .disabled(s.incluidos.isEmpty || s.preparandoDup || s.movendoDup)
                            }
                        }
                    }
                }
            }
        }
        .quickLookPreview($previa)
    }

    @ViewBuilder
    private var barra: some View {
        HStack(spacing: 10) {
            switch s.estadoDup {
            case .nunca:
                Text("Ainda não procurou.").font(.system(size: 12)).foregroundColor(.secondary)
            case .cancelado:
                Text("Cancelado.").font(.system(size: 12)).foregroundColor(.secondary)
            case .rodando(let etapa, let feito, let total):
                if total > 0 {
                    ProgressView(value: Double(feito), total: Double(total)).frame(width: 120)
                } else {
                    ProgressView().controlSize(.small)
                }
                Text(total > 0 ? "\(etapa) \(feito) de \(total)" : etapa).font(.system(size: 12)).foregroundColor(.secondary).monospacedDigit()
            case .pronto(let q):
                Text("Procurado \(DiscoFormato.ha(q)) · \(s.grupos.count) \(s.grupos.count == 1 ? "grupo" : "grupos") · \(DiscoFormato.bytes(s.recuperavelDup)) em cópias")
                    .font(.system(size: 12)).foregroundColor(.secondary)
            }
            Spacer()
            if s.estadoDup.rodando {
                Button("Cancelar") { s.cancelarDuplicados() }
            } else {
                Button(s.estadoDup == .nunca ? "Procurar duplicados" : "Procurar de novo") { s.procurarDuplicados() }
                    .disabled(s.movendoDup)
            }
        }
    }

    private func grupo(_ g: GrupoDuplicado) -> some View {
        let fica = s.manter[g.id] ?? g.sugestao
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Toggle("", isOn: Binding(get: { s.incluidos.contains(g.id) }, set: { _ in s.alternarGrupo(g.id) }))
                    .toggleStyle(.checkbox).labelsHidden()
                Text((fica as NSString).lastPathComponent).font(.system(size: 12.5, weight: .medium)).lineLimit(1).truncationMode(.middle)
                Text("\(g.caminhos.count) cópias de \(DiscoFormato.bytes(g.bytes))").font(.system(size: 10.5)).foregroundColor(.secondary)
                Spacer(minLength: 8)
                Text("libera \(DiscoFormato.bytes(g.recuperavel))").font(.system(size: 12)).monospacedDigit()
            }
            ForEach(g.caminhos, id: \.self) { c in
                HStack(spacing: 6) {
                    Button { s.manter[g.id] = c } label: {
                        Image(systemName: c == fica ? "largecircle.fill.circle" : "circle")
                            .foregroundColor(c == fica ? .accentColor : .secondary)
                    }
                    .buttonStyle(.borderless).help("Manter esta")
                    Text(DiscoFormato.curto(c)).font(.system(size: 11)).foregroundColor(c == fica ? .primary : .secondary)
                        .lineLimit(1).truncationMode(.middle)
                    if c == fica {
                        Text(c == g.sugestao ? "fica (sugerida)" : "fica").font(.system(size: 9.5, weight: .medium)).foregroundColor(.green)
                    } else if s.incluidos.contains(g.id) {
                        Text("vai para a Lixeira").font(.system(size: 9.5, weight: .medium)).foregroundColor(.orange)
                    }
                    Spacer(minLength: 6)
                    BotoesArquivo(caminho: c, previa: $previa)
                }
                .padding(.leading, 26)
            }
        }
    }

    private func confirmacao(_ lista: [(grupo: GrupoDuplicado, manter: String, sair: [String])]) -> some View {
        let n = lista.reduce(0) { $0 + $1.sair.count }
        let total = lista.reduce(Int64(0)) { $0 + $1.grupo.bytes * Int64($1.sair.count) }
        return Secao("Confirmar: mover cópias para a Lixeira — duplicados",
                     "Conferido de novo agora: cada cópia ainda é igual à que fica (mesma data, mesmo início e fim). A que fica não é tocada. Tudo fica na Lixeira até você esvaziá-la.") {
            ForEach(lista, id: \.grupo.id) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text("Fica: \(DiscoFormato.curto(item.manter))").font(.system(size: 11)).foregroundColor(.green)
                        .lineLimit(1).truncationMode(.middle)
                    ForEach(item.sair, id: \.self) { c in
                        LinhaConfirmacao(nome: (c as NSString).lastPathComponent, detalhe: DiscoFormato.curto(c), bytes: item.grupo.bytes)
                    }
                }
            }
            ListaRetirados(titulo: "Saíram da lista:", itens: s.retiradosDup)
            RodapeConfirmacao(total: "Total: \(n) \(n == 1 ? "cópia" : "cópias") · \(DiscoFormato.bytes(total))",
                              botao: "Mover para a Lixeira", ocupado: s.movendoDup,
                              cancelar: { s.cancelarConfirmacaoDup() }, confirmar: { s.confirmarMoverDup() })
        }
    }
}
