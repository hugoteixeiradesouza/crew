import CoreGraphics
import Foundation
import ImageIO
import Vision

// Texto de uma imagem pelo Vision do macOS (no próprio Mac, sem rede): modo preciso, português
// e inglês, devolvido na ordem de leitura. Roda fora da main.

enum LeitorTexto {
    static let idiomas = ["pt-BR", "en-US"]

    /// nil = não deu para abrir a imagem ou o Vision falhou; "" = imagem sem texto.
    static func ler(_ url: URL) async -> String? {
        await Task.detached(priority: .userInitiated) { () -> String? in
            guard let fonte = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let imagem = CGImageSourceCreateImageAtIndex(fonte, 0, nil) else { return nil }
            return lerAgora(imagem)
        }.value
    }

    /// Síncrono: chame fora da main.
    static func lerAgora(_ imagem: CGImage) -> String? {
        let pedido = VNRecognizeTextRequest()
        pedido.recognitionLevel = .accurate
        pedido.recognitionLanguages = idiomas
        pedido.usesLanguageCorrection = true
        do {
            try VNImageRequestHandler(cgImage: imagem, options: [:]).perform([pedido])
        } catch {
            return nil
        }
        let trechos = (pedido.results ?? []).compactMap { o -> PoliticaCaptura.Trecho? in
            guard let melhor = o.topCandidates(1).first else { return nil }
            return PoliticaCaptura.Trecho(texto: melhor.string, caixa: o.boundingBox)
        }
        return PoliticaCaptura.emOrdemDeLeitura(trechos)
    }
}
