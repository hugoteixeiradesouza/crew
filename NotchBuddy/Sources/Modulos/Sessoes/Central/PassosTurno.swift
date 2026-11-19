import SwiftUI
import AppKit

// O caminho de um turno na conversa do app do Crew: o que o Claude fez entre o pedido e a
// resposta, passo a passo, como o terminal do Claude Code mostra — cada ferramenta numa linha
// (o que rodou, o que leu, o que mudou), o resultado resumido com "+N linhas" para abrir, erro em
// vermelho, bloqueio de permissão em âmbar.
//
// Aberto ou fechado: enquanto o turno roda, o caminho fica ABERTO (é quando se quer acompanhar,
// e é o que o terminal faz); quando o turno termina, RECOLHE numa linha só com o resumo ("12
// passos · 5 comandos · leu 6 arquivos · levou 1m 35s"), para a conversa voltar a ser pedido e
// resposta. Um clique abre de novo; a escolha do Hugo vale mais que o padrão.

struct CaminhoTurno: View {
    let turno: TurnoConversa
    /// O turno está em andamento (é o último e a sessão está trabalhando).
    var vivo = false

    /// O que o Hugo escolheu na mão (nil = segue o padrão: recolhido, também enquanto roda —
    /// a linha de resumo e a pílula do passo atual já dizem o que está acontecendo).
    @State private var escolha: Bool?
    @State private var todos = false

    private var aberto: Bool { escolha ?? false }
    /// Quantas entradas aparecem de saída: rodando, só as últimas (o que importa é o agora).
    private var teto: Int { vivo ? 14 : 80 }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            cabecalho
            if aberto {
                let itens = turno.caminho
                let corte = todos ? 0 : max(0, itens.count - teto)
                VStack(alignment: .leading, spacing: 9) {
                    if corte > 0 {
                        Button { todos = true } label: {
                            Text("Mostrar os \(corte) passos anteriores")
                                .font(.system(size: 11.5)).foregroundStyle(Tema.texto3)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(itens[corte...]) { item in
                        switch item {
                        case .fala(let m):
                            TextoConversa(texto: m.text, tamanho: 12.5, cor: Tema.texto2, entrelinha: 2)
                        case .passo(let p):
                            LinhaPasso(passo: p, vivo: vivo)
                        case .grupo(_, let tipo, let passos):
                            LinhaGrupo(tipo: tipo, passos: passos, vivo: vivo)
                        }
                    }
                }
                .padding(.leading, 14)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1).fill(Color.white.opacity(0.1)).frame(width: 2)
                }
            }
        }
    }

    private var cabecalho: some View {
        Button { withAnimation(.easeOut(duration: 0.18)) { escolha = !aberto } } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8.5, weight: .bold))
                    .rotationEffect(.degrees(aberto ? 90 : 0))
                Text(titulo).font(.system(size: 12, weight: .medium)).foregroundStyle(Tema.texto2)
                if !detalhe.isEmpty {
                    Text(detalhe).font(.system(size: 12)).lineLimit(1).truncationMode(.tail)
                }
                if turno.temErro {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 9.5))
                        .foregroundStyle(Tema.vermelho.opacity(0.85))
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(Tema.texto3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(ajudaPermissao)
    }

    private var titulo: String {
        let n = turno.totalDePassos
        if n == 0 {
            let falas = turno.caminho.count
            return falas == 1 ? "1 mensagem no caminho" : "\(falas) mensagens no caminho"
        }
        return LeitorPassos.plural(n, "passo", "passos")
    }

    private var detalhe: String {
        var partes: [String] = []
        let r = turno.resumoDoCaminho
        if !r.isEmpty { partes.append(r) }
        if let d = turno.duracao, d >= 1 { partes.append("levou " + LeitorPassos.duracao(d)) }
        if let m = Self.nomeDoModo(turno.user?.modoPermissao) { partes.append(m) }
        return partes.isEmpty ? "" : "· " + partes.joined(separator: " · ")
    }

    /// Como as permissões foram decididas neste turno (o transcript guarda o modo do pedido).
    static func nomeDoModo(_ modo: String?) -> String? {
        switch modo {
        case "auto": return "modo automático"
        case "acceptEdits": return "edições liberadas"
        case "bypassPermissions": return "sem pedir permissão"
        case "plan": return "só planejando"
        default: return nil
        }
    }

    private var ajudaPermissao: String {
        switch turno.user?.modoPermissao {
        case "auto": return "Modo automático: o Claude Code decidiu sozinho o que podia rodar neste turno, sem perguntar. O que ele bloqueou aparece em âmbar."
        case "acceptEdits": return "Edições de arquivo liberadas neste turno; o resto pede permissão."
        case "bypassPermissions": return "Neste turno nada pediu permissão."
        case "plan": return "Modo de planejar: o Claude só leu e propôs, sem mudar nada."
        case "default": return "Neste turno o Claude pediu permissão quando precisou."
        default: return "O que o Claude fez neste turno, passo a passo."
        }
    }
}

// MARK: - Um passo

/// Uma ferramenta usada: o que fez, o texto técnico por baixo e o que voltou.
struct LinhaPasso: View {
    let passo: PassoConversa
    var vivo = false
    /// Dentro de um grupo ("Leu 4 arquivos"): mais enxuta, sem repetir o verbo.
    var enxuta = false

    @State private var expandido = false

    private var resultado: ResultadoPasso? { passo.resultado }
    private var cor: Color {
        if resultado?.negado != nil { return Tema.ambar }
        if resultado?.erro == true { return Tema.vermelho }
        return Tema.texto3
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icone)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(cor)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if passo.rodando, vivo {
                        TextoBrilhando(texto: passo.frase).layoutPriority(1)
                    } else {
                        (Text(enxuta || !passo.mostraVerbo ? "" : passo.verbo + " ").foregroundStyle(Tema.texto3)
                         + Text(passo.alvo).foregroundStyle(passo.tipo == .pensamento ? Tema.texto3 : Tema.texto2))
                            .font(.system(size: 12.5))
                            .lineLimit(2)
                            .layoutPriority(1)
                    }
                    if let nota { Text(nota).font(.system(size: 11.5)).foregroundStyle(cor).lineLimit(1) }
                    if let d = passo.duracao, d >= 2, passo.tipo != .pensamento {
                        Text(LeitorPassos.duracao(d)).font(.system(size: 11, design: .monospaced)).foregroundStyle(Tema.texto3)
                    }
                }
                if !passo.tecnico.isEmpty, !enxuta, passo.tipo == .comando || passo.tipo == .busca || passo.tipo == .navegador
                    || passo.tipo == .outro || passo.tipo == .web {
                    Text(passo.tecnico)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Tema.texto3)
                        .lineLimit(expandido ? 6 : 1).truncationMode(.tail)
                        .textSelection(.enabled)
                }
                saida
            }
            Spacer(minLength: 0)
        }
        .help(passo.tecnico.isEmpty ? passo.ferramenta : passo.tecnico)
    }

    private var icone: String {
        if resultado?.negado != nil { return "hand.raised.fill" }
        if resultado?.erro == true { return "xmark.octagon.fill" }
        return passo.icone
    }

    /// O recado curto ao lado do título: "120 linhas", "deu erro", "bloqueado pelo modo automático".
    private var nota: String? {
        guard let r = resultado else {
            // Sem resultado e o turno já acabou: foi interrompido antes de terminar.
            return passo.rodando && !vivo ? "não terminou" : nil
        }
        if !r.resumo.isEmpty { return "· " + (r.negado == "auto" ? "não rodou: " : "") + r.resumo }
        if passo.segundoPlano { return "· em segundo plano" }
        // Busca: quantas linhas voltaram diz mais que as próprias linhas.
        if passo.tipo == .busca, r.total > 0 { return "· " + LeitorPassos.plural(r.total, "resultado", "resultados") }
        return nil
    }

    /// Quantas linhas da saída aparecem sem abrir.
    private var previa: Int {
        guard let r = resultado else { return 0 }
        if r.erro { return 4 }
        switch passo.tipo {
        case .comando: return 3
        case .agente, .outro, .navegador, .web, .mensagem, .skill: return 2
        default: return 0   // leitura, busca, edição: o resumo já diz; a saída abre no clique
        }
    }

    @ViewBuilder
    private var saida: some View {
        if let r = resultado, !r.linhas.isEmpty {
            let mostradas = expandido ? r.linhas.count : min(previa, r.linhas.count)
            let escondidas = r.total - mostradas
            VStack(alignment: .leading, spacing: 3) {
                if mostradas > 0 {
                    Text(texto(r.linhas.prefix(mostradas), cor: r.negado != nil ? Tema.ambar : r.erro ? Tema.vermelho : nil))
                        .font(.system(size: 11, design: .monospaced))
                        .lineSpacing(1.5)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if escondidas > 0 || expandido {
                    Button { expandido.toggle() } label: {
                        Text(rotulo(mostradas: mostradas, r))
                            .font(.system(size: 11)).foregroundStyle(Tema.texto3)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!expandido && r.linhas.count <= mostradas)
                }
            }
            .padding(.leading, 9)
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1).fill(cor.opacity(resultado?.erro == true ? 0.5 : 0.25)).frame(width: 1.5)
            }
        }
    }

    private func rotulo(mostradas: Int, _ r: ResultadoPasso) -> String {
        if expandido {
            let fora = r.total - r.linhas.count
            return fora > 0 ? "Recolher · as outras \(fora) linhas estão no terminal" : "Recolher"
        }
        let n = r.total - mostradas
        if mostradas == 0 {
            return passo.tipo == .edicao || passo.tipo == .escrita ? "Ver a mudança" : "Ver " + LeitorPassos.plural(n, "linha", "linhas")
        }
        return "+" + LeitorPassos.plural(n, "linha", "linhas")
    }

    /// As linhas da saída; em edição, o que entrou em verde e o que saiu em vermelho.
    private func texto(_ linhas: ArraySlice<String>, cor: Color?) -> AttributedString {
        var out = AttributedString()
        let remendo = passo.tipo == .edicao || passo.tipo == .escrita
        for (i, l) in linhas.enumerated() {
            var a = AttributedString(l + (i < linhas.count - 1 ? "\n" : ""))
            if let cor { a.foregroundColor = cor.opacity(0.9) }
            else if remendo, l.hasPrefix("+") { a.foregroundColor = Tema.verde.opacity(0.9) }
            else if remendo, l.hasPrefix("-") { a.foregroundColor = Tema.vermelho.opacity(0.85) }
            else { a.foregroundColor = Tema.texto3 }
            out += a
        }
        return out
    }
}

// MARK: - Sequência de passos iguais

/// "Leu 4 arquivos": uma linha para a sequência, que abre com cada um.
struct LinhaGrupo: View {
    let tipo: PassoConversa.Tipo
    let passos: [PassoConversa]
    var vivo = false

    @State private var aberto = false

    private var rodando: Bool { vivo && passos.contains(where: \.rodando) }
    private var erros: Int { passos.filter { $0.resultado?.erro == true }.count }
    /// Pensamento não abre: não há o que listar além do tempo.
    private var abre: Bool { tipo != .pensamento }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { if abre { withAnimation(.easeOut(duration: 0.15)) { aberto.toggle() } } } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: passos[0].icone)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(erros > 0 ? Tema.vermelho : Tema.texto3)
                        .frame(width: 14)
                    if rodando {
                        TextoBrilhando(texto: titulo)
                    } else {
                        Text(titulo).font(.system(size: 12.5))
                            .foregroundStyle(tipo == .pensamento ? Tema.texto3 : Tema.texto2)
                    }
                    if !nomes.isEmpty, !aberto {
                        Text(nomes).font(.system(size: 11.5)).foregroundStyle(Tema.texto3).lineLimit(1).truncationMode(.tail)
                    }
                    if erros > 0 {
                        Text("· " + LeitorPassos.plural(erros, "erro", "erros")).font(.system(size: 11.5)).foregroundStyle(Tema.vermelho)
                    }
                    if abre {
                        Image(systemName: "chevron.right").font(.system(size: 7.5, weight: .bold))
                            .foregroundStyle(Tema.texto3).rotationEffect(.degrees(aberto ? 90 : 0))
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if aberto {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(passos) { LinhaPasso(passo: $0, vivo: vivo, enxuta: true) }
                }
                .padding(.leading, 22)
            }
        }
    }

    private var titulo: String {
        let n = passos.count
        switch tipo {
        case .leitura:
            let arquivos = Set(passos.map(\.tecnico)).count
            return (rodando ? "Lendo " : "Leu ") + LeitorPassos.plural(arquivos, "arquivo", "arquivos")
        case .busca: return (rodando ? "Fazendo " : "Fez ") + "\(n) buscas"
        case .pensamento:
            let total = passos.compactMap(\.duracao).reduce(0, +)
            return "Pensou por " + LeitorPassos.duracao(total)
        case .ferramentas: return "Carregou ferramentas (\(n) vezes)"
        case .tarefas: return "Atualizou as tarefas (\(n) vezes)"
        default: return "\(passos[0].verbo) (\(n) vezes)"
        }
    }

    /// Os nomes, na mesma linha, enquanto o grupo está fechado.
    private var nomes: String {
        guard tipo == .leitura || tipo == .busca else { return "" }
        var vistos = Set<String>()
        return passos.map(\.alvo).filter { vistos.insert($0).inserted }.joined(separator: ", ")
    }
}

// MARK: - A lista de tarefas

/// O plano do Claude no turno em andamento: cada tarefa com o estado (feita, em andamento,
/// pendente). Aparece acima do passo atual enquanto ele trabalha.
struct CartaoTarefas: View {
    let tarefas: [TarefaConversa]
    @Environment(\.telaVisivel) private var visivel

    private var feitas: Int { tarefas.filter { $0.estado == .feita }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: "checklist").font(.system(size: 10.5, weight: .medium))
                Text("Plano").font(.system(size: 12, weight: .medium))
                Text("· \(feitas) de \(tarefas.count)").font(.system(size: 12, design: .monospaced))
                Spacer(minLength: 0)
            }
            .foregroundStyle(Tema.texto3)
            ForEach(tarefas) { t in
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Image(systemName: icone(t.estado))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(t.estado == .feita ? Tema.verde.opacity(0.8) : t.estado == .fazendo ? Tema.texto : Tema.texto3)
                        .frame(width: 15)
                    if t.estado == .fazendo {
                        TextoBrilhando(texto: t.fazendo.isEmpty ? t.titulo : t.fazendo, vivo: visivel)
                    } else {
                        Text(t.titulo)
                            .font(.system(size: 12.5))
                            .foregroundStyle(t.estado == .feita ? Tema.texto3 : Tema.texto2)
                            .strikethrough(t.estado == .feita, color: Tema.texto3)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Tema.raioLinha + 2).fill(Color.white.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: Tema.raioLinha + 2).strokeBorder(Tema.borda))
    }

    private func icone(_ e: TarefaConversa.Estado) -> String {
        switch e {
        case .feita: return "checkmark.circle.fill"
        case .fazendo: return "circle.dotted.circle"
        case .pendente: return "circle.dashed"
        }
    }
}
