import Foundation

/// Quem usa este Mac, do jeito que o Crew chama: nos textos da tela e nas instruções que o Crew
/// escreve para os modelos e para as sessões. Sai do nome da conta do macOS (primeiro nome);
/// quem quiser outro escolhe em Ajustes › Geral.
///
/// Nas frases o nome entra sem artigo ("de \(Usuario.nome)", "a \(Usuario.nome)"): serve a
/// qualquer nome, sem o Crew precisar adivinhar "do" ou "da".
enum Usuario {
    static let chave = "usuario.nome"

    /// Como o Crew chama quem usa o Mac: o nome escolhido nos ajustes ou o primeiro nome da conta.
    static var nome: String {
        let escolhido = (UserDefaults.standard.string(forKey: chave) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return escolhido.isEmpty ? nomeDaConta : escolhido
    }

    /// Primeiro nome da conta do macOS; sem nome completo, o nome curto da conta.
    static var nomeDaConta: String {
        if let primeiro = NSFullUserName().split(separator: " ").first { return String(primeiro) }
        let curto = NSUserName()
        return curto.isEmpty ? "você" : curto
    }

    /// Nome para assinar o que sai do Mac (autor de um vídeo): o da conta, inteiro.
    static var nomeCompleto: String {
        let inteiro = NSFullUserName().trimmingCharacters(in: .whitespacesAndNewlines)
        return inteiro.isEmpty ? nome : inteiro
    }
}
