import Foundation
import NaturalLanguage
import Translation

// O tradutor do comando universal: o framework Translation da Apple, no aparelho. Nada do que
// é digitado sai do Mac. O idioma do texto é reconhecido pelo NaturalLanguage (também local).
//
// O pacote de cada par de idiomas é baixado pelo macOS (Ajustes do Sistema › Geral › Idioma e
// Região › Idiomas de Tradução). Sem o pacote, o comando DIZ isso — não baixa nada sozinho e
// não falha calado.
//
// macOS 26+: a sessão é criada direto (`TranslationSession(installedSource:target:)`).
// macOS 15: a sessão só nasce de dentro de uma tela SwiftUI (`.translationTask`); o painel
// pendura esse modificador e usa `pedidoParaTela` (ver PainelComandoView).

@MainActor
final class Tradutor: ObservableObject {
    enum Estado: Equatable {
        case traduzindo(de: String, para: String)
        case pronto(texto: String, de: String, para: String)
        /// O par existe, mas o pacote não está baixado neste Mac.
        case semPacote(de: String, para: String)
        case semSuporte(de: String, para: String)
        case naoIdentificou
        case mesmoIdioma(String)
        case falhou(String)
    }

    /// Pedido em vigor (o que está na linha do painel) e o estado dele.
    @Published private(set) var estado: Estado?
    private(set) var textoPedido = ""

    /// macOS 15: o que a tela precisa para traduzir (configuração + texto). nil nos mais novos.
    struct PedidoParaTela: Equatable, Sendable {
        let texto: String
        let de: String
        let para: String
    }
    @Published private(set) var pedidoParaTela: PedidoParaTela?

    private var tarefa: Task<Void, Never>?

    /// Idiomas em que o reconhecimento aposta (os que o comando entende pelo nome).
    private static let conhecidos: [NLLanguage] = [
        .portuguese, .english, .spanish, .french, .german, .italian, .japanese, .simplifiedChinese,
        .korean, .russian, .arabic, .dutch, .polish, .turkish, .ukrainian, .hindi, .indonesian, .thai, .vietnamese,
    ]

    /// O idioma do texto ("en", "pt"…) e o quanto dá para confiar (0…1). nil = não deu para dizer.
    static func idioma(de texto: String) -> (codigo: String, confianca: Double)? {
        let r = NLLanguageRecognizer()
        r.languageConstraints = conhecidos
        r.processString(texto)
        guard let (lingua, p) = r.languageHypotheses(withMaximum: 1).first else { return nil }
        let codigo = lingua.rawValue.split(separator: "-").first.map(String.init) ?? lingua.rawValue
        return (codigo, p)
    }

    /// Texto solto que parece estar em outra língua (e não um nome de app ou de arquivo):
    /// frase de três palavras ou mais, reconhecida com folga como não sendo português.
    static func pareceEstrangeiro(_ texto: String) -> Bool {
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.split(separator: " ").count >= 3, t.count >= 12, t.contains(where: \.isLetter) else { return false }
        guard let (codigo, p) = idioma(de: t) else { return false }
        return codigo != "pt" && p >= 0.8
    }

    /// Para onde traduzir quando ele não disse: português vira inglês; o resto vira português.
    static func destinoPadrao(origem: String) -> String { origem == "pt" ? "en" : "pt" }

    /// Começa (ou troca) a tradução. `destino` nil = decide pelo idioma do texto.
    func traduzir(_ texto: String, destino: String?) {
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        tarefa?.cancel()
        pedidoParaTela = nil
        textoPedido = t
        guard !t.isEmpty else { estado = nil; return }
        guard let origem = Self.idioma(de: t)?.codigo else { estado = .naoIdentificou; return }
        let para = destino ?? Self.destinoPadrao(origem: origem)
        guard para != origem else { estado = .mesmoIdioma(para); return }
        estado = .traduzindo(de: origem, para: para)
        tarefa = Task { [weak self] in
            // Pausa curta: digitando, não se traduz letra por letra.
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            let de = Locale.Language(identifier: origem), ate = Locale.Language(identifier: para)
            let situacao = await LanguageAvailability().status(from: de, to: ate)
            guard !Task.isCancelled, let self, self.textoPedido == t else { return }
            switch situacao {
            case .installed:
                await self.traduzirInstalado(t, origem: origem, para: para)
            case .supported:
                self.estado = .semPacote(de: origem, para: para)
            case .unsupported:
                self.estado = .semSuporte(de: origem, para: para)
            @unknown default:
                self.estado = .falhou("O macOS não disse se este par de idiomas existe.")
            }
        }
    }

    private func traduzirInstalado(_ t: String, origem: String, para: String) async {
        if #available(macOS 26.0, *) {
            let sessao = TranslationSession(installedSource: Locale.Language(identifier: origem),
                                            target: Locale.Language(identifier: para))
            do {
                let resposta = try await sessao.translate(t)
                guard !Task.isCancelled, textoPedido == t else { return }
                estado = .pronto(texto: resposta.targetText, de: origem, para: para)
            } catch {
                guard !Task.isCancelled, textoPedido == t else { return }
                estado = Self.estado(doErro: error, de: origem, para: para)
            }
        } else {
            // A tela traduz e devolve por `entregar`.
            pedidoParaTela = PedidoParaTela(texto: t, de: origem, para: para)
        }
    }

    /// macOS 15: o resultado que a tela conseguiu (nil = não traduziu).
    func entregar(_ traduzido: String?, pedido: PedidoParaTela) {
        guard pedidoParaTela == pedido, textoPedido == pedido.texto else { return }
        pedidoParaTela = nil
        if let traduzido {
            estado = .pronto(texto: traduzido, de: pedido.de, para: pedido.para)
        } else {
            estado = .falhou("O macOS não traduziu este texto.")
        }
    }

    private static func estado(doErro erro: Error, de: String, para: String) -> Estado {
        if #available(macOS 26.0, *), TranslationError.notInstalled ~= erro { return .semPacote(de: de, para: para) }
        if TranslationError.unsupportedLanguagePairing ~= erro || TranslationError.unsupportedSourceLanguage ~= erro
            || TranslationError.unsupportedTargetLanguage ~= erro { return .semSuporte(de: de, para: para) }
        if TranslationError.unableToIdentifyLanguage ~= erro { return .naoIdentificou }
        return .falhou(erro.localizedDescription)
    }

    /// Painel fechou ou o texto deixou de ser pedido de tradução.
    func parar() {
        tarefa?.cancel()
        tarefa = nil
        pedidoParaTela = nil
        textoPedido = ""
        estado = nil
    }

    /// Estado de exemplo, para o modo de capturas (não chama o framework).
    func exemploParaCaptura(_ texto: String, _ e: Estado) {
        tarefa?.cancel()
        textoPedido = texto
        estado = e
    }
}
