import CoreGraphics
import Foundation

// Regras puras da Captura (sem tela, sem disco): os argumentos do `screencapture`, os nomes dos
// arquivos, o que sai quando passa do limite e a ordem de leitura do texto reconhecido.

enum ModoCaptura: String, CaseIterable, Sendable, Identifiable {
    case area, janela, tela, texto

    var id: String { rawValue }

    var nome: String {
        switch self {
        case .area: "Área"
        case .janela: "Janela"
        case .tela: "Tela inteira"
        case .texto: "Texto da tela"
        }
    }

    /// SF Symbol.
    var icone: String {
        switch self {
        case .area: "rectangle.dashed"
        case .janela: "macwindow"
        case .tela: "display"
        case .texto: "text.viewfinder"
        }
    }

    var explicacao: String {
        switch self {
        case .area: "Arraste para escolher um pedaço da tela."
        case .janela: "Clique na janela que quer fotografar."
        case .tela: "A tela onde o mouse está, inteira."
        case .texto: "Arraste sobre um texto: ele vai direto para a área de transferência. Nenhuma imagem é guardada."
        }
    }
}

enum PoliticaCaptura {
    static let executavel = "/usr/sbin/screencapture"
    static let prefixo = "Captura "
    static let sufixoAnotada = "-anotada"
    static let manterPadrao = 50
    static let tempoPreviaPadrao = 6.0

    /// Argumentos do `screencapture`. `-x` = sem som; `-i` = o Hugo escolhe a área; `-W` = começa
    /// escolhendo janela; sem `-i` = a tela inteira. `tela`: número da tela (1 = principal), só
    /// para a tela inteira com mais de um monitor.
    static func argumentos(_ modo: ModoCaptura, destino: String, tela: Int? = nil) -> [String] {
        var a = ["-x", "-t", "png"]
        switch modo {
        case .area, .texto: a.append("-i")
        case .janela: a += ["-i", "-W"]
        case .tela: if let tela { a += ["-D", String(tela)] }
        }
        return a + [destino]
    }

    /// "Captura 2026-11-09 14.32.05.png" — ordena por nome igual a por data.
    static func nomeArquivo(_ data: Date, calendario: Calendar = .current) -> String {
        let c = calendario.dateComponents([.year, .month, .day, .hour, .minute, .second], from: data)
        return String(format: "%@%04d-%02d-%02d %02d.%02d.%02d.png", prefixo,
                      c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }

    /// Nome livre na pasta: se já existe (duas capturas no mesmo segundo), ganha " 2", " 3"…
    static func nomeLivre(_ nome: String, existentes: Set<String>) -> String {
        guard existentes.contains(nome) else { return nome }
        let base = (nome as NSString).deletingPathExtension, ext = (nome as NSString).pathExtension
        var n = 2
        while existentes.contains("\(base) \(n).\(ext)") { n += 1 }
        return "\(base) \(n).\(ext)"
    }

    /// Nome da cópia anotada: o original nunca é regravado.
    static func nomeAnotada(de original: String, existentes: Set<String>) -> String {
        var base = (original as NSString).deletingPathExtension
        if let r = base.range(of: sufixoAnotada, options: .backwards) { base = String(base[..<r.lowerBound]) }
        return nomeLivre(base + sufixoAnotada + ".png", existentes: existentes)
    }

    static func ehCaptura(_ nome: String) -> Bool {
        nome.hasPrefix(prefixo) && nome.lowercased().hasSuffix(".png")
    }

    /// O que sai da pasta do Crew para ficarem só as `manter` mais novas.
    static func sobras<T>(_ itens: [T], manter: Int, data: (T) -> Date) -> [T] {
        guard manter > 0, itens.count > manter else { return [] }
        return Array(itens.sorted { data($0) > data($1) }.dropFirst(manter))
    }

    // MARK: Texto reconhecido

    /// Um pedaço de texto e onde ele está (coordenadas do Vision: 0…1, origem embaixo à esquerda).
    struct Trecho: Sendable {
        let texto: String
        let caixa: CGRect
    }

    /// Junta os trechos na ordem em que se lê: de cima para baixo, e dentro da mesma linha da
    /// esquerda para a direita (o Vision devolve em ordem própria, que embaralha colunas e
    /// rótulos lado a lado). Um vão maior que uma linha vira parágrafo.
    static func emOrdemDeLeitura(_ trechos: [Trecho]) -> String {
        let validos = trechos.filter { !$0.texto.trimmingCharacters(in: .whitespaces).isEmpty }
        var linhas: [[Trecho]] = []
        for t in validos.sorted(by: { $0.caixa.midY > $1.caixa.midY }) {
            if let ultima = linhas.last, let ref = ultima.first {
                let altura = min(ref.caixa.height, t.caixa.height)
                if abs(ref.caixa.midY - t.caixa.midY) < altura * 0.5 {
                    linhas[linhas.count - 1].append(t)
                    continue
                }
            }
            linhas.append([t])
        }
        var saida = ""
        var anterior: CGRect?
        for linha in linhas {
            let ordenada = linha.sorted { $0.caixa.minX < $1.caixa.minX }
            let caixa = ordenada.reduce(ordenada[0].caixa) { $0.union($1.caixa) }
            if let a = anterior {
                let vao = a.minY - caixa.maxY
                saida += vao > min(a.height, caixa.height) * 1.5 ? "\n\n" : "\n"
            }
            saida += ordenada.map { $0.texto.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
            anterior = caixa
        }
        return saida
    }

    /// Começo do texto para o aviso na ilha ("Texto copiado: …").
    static func primeirasPalavras(_ texto: String, maximo: Int = 34) -> String {
        let plano = texto.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
        guard plano.count > maximo else { return plano }
        var corte = String(plano.prefix(maximo))
        if let espaco = corte.lastIndex(of: " "), corte.distance(from: corte.startIndex, to: espaco) > maximo / 2 {
            corte = String(corte[..<espaco])
        }
        return corte + "…"
    }
}
