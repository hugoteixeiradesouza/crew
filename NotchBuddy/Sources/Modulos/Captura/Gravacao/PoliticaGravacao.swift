import CoreGraphics
import Foundation

// Regras puras da gravação de tela (sem tela, sem disco): o que se grava, os nomes dos arquivos,
// o tamanho do vídeo e como duração e tamanho aparecem escritos.

enum AlvoGravacao: String, CaseIterable, Sendable, Identifiable {
    case tela, janela, area

    var id: String { rawValue }

    var nome: String {
        switch self {
        case .tela: "Tela inteira"
        case .janela: "Janela"
        case .area: "Área"
        }
    }

    /// SF Symbol.
    var icone: String {
        switch self {
        case .tela: "display"
        case .janela: "macwindow"
        case .area: "rectangle.dashed"
        }
    }

    var explicacao: String {
        switch self {
        case .tela: "Grava a tela onde o mouse está, inteira."
        case .janela: "O macOS mostra o seletor dele: escolha a janela. A bolha da câmera não entra (só a janela é gravada)."
        case .area: "Arraste para escolher um pedaço da tela; Esc cancela."
        }
    }
}

enum PoliticaGravacao {
    static let subpasta = "gravacoes"
    static let prefixo = "Gravação "
    static let extensao = "mp4"
    /// Menor área que vale gravar (pontos).
    static let ladoMinimo: CGFloat = 48

    /// "Gravação 2026-11-12 14.32.05.mp4" — ordena por nome igual a por data.
    static func nomeArquivo(_ data: Date, calendario: Calendar = .current) -> String {
        let c = calendario.dateComponents([.year, .month, .day, .hour, .minute, .second], from: data)
        return String(format: "%@%04d-%02d-%02d %02d.%02d.%02d.%@", prefixo,
                      c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0, extensao)
    }

    static func ehGravacao(_ nome: String) -> Bool {
        let n = nome.lowercased()
        return nome.hasPrefix(prefixo) && (n.hasSuffix(".mp4") || n.hasSuffix(".mov"))
    }

    /// O arquivo do rastro do mouse de uma gravação: mesmo nome, `.json`, ao lado do vídeo.
    static func rastro(de video: URL) -> URL { video.deletingPathExtension().appendingPathExtension("json") }

    /// Largura e altura do vídeo em pixels, sempre pares (o H.264 exige). `leve` grava na medida
    /// dos pontos (metade dos pixels numa tela Retina): arquivo bem menor, texto menos nítido.
    static func dimensoes(pontos: CGSize, escala: CGFloat, leve: Bool) -> (largura: Int, altura: Int) {
        let e = leve ? 1 : max(1, escala)
        func par(_ v: CGFloat) -> Int { max(2, Int((v * e).rounded()) / 2 * 2) }
        return (par(pontos.width), par(pontos.height))
    }

    /// O retângulo arrastado entre dois pontos, preso aos limites; nil se ficou pequeno demais.
    static func retangulo(de a: CGPoint, ate b: CGPoint, dentro limites: CGRect) -> CGRect? {
        let r = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
            .intersection(limites).integral
        guard !r.isNull, r.width >= ladoMinimo, r.height >= ladoMinimo else { return nil }
        return r
    }

    /// "0:42", "12:05", "1:02:03".
    static func duracao(_ segundos: TimeInterval) -> String {
        let s = max(0, Int(segundos.rounded()))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60)
                         : String(format: "%d:%02d", s / 60, s % 60)
    }

    /// "840 KB", "12,4 MB", "1,2 GB".
    static func tamanho(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useKB, .useMB, .useGB]
        return f.string(fromByteCount: bytes)
    }
}
