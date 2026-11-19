import SwiftUI

// O que o Hugo estava escrevendo e ainda não enviou, por campo (cada sessão e o início).
// Trocar de setor, de sessão ou entrar e sair da grade desmonta a tela do campo; sem isto o
// texto ia embora junto. Vive enquanto o app está aberto.

@MainActor
enum Rascunhos {
    static var texto: [String: String] = [:]
    static var anexos: [String: [URL]] = [:]
}

/// Devolve o rascunho ao campo quando ele volta à tela e o guarda a cada mudança.
struct GuardaRascunho: ViewModifier {
    let chave: String
    @Binding var texto: String
    @Binding var anexos: [URL]
    /// Texto que não pode voltar (o pedido que acabou de virar sessão).
    var ignorar: String? = nil

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard texto.isEmpty, anexos.isEmpty else { return }
                let t = Rascunhos.texto[chave] ?? ""
                if let ignorar, t.trimmingCharacters(in: .whitespacesAndNewlines) == ignorar {
                    Rascunhos.texto[chave] = nil
                    Rascunhos.anexos[chave] = nil
                    return
                }
                let a = Rascunhos.anexos[chave] ?? []
                if !a.isEmpty { anexos = a }
                if !t.isEmpty { texto = t }
            }
            .onChange(of: texto) { _, t in Rascunhos.texto[chave] = t.isEmpty ? nil : t }
            .onChange(of: anexos) { _, a in Rascunhos.anexos[chave] = a.isEmpty ? nil : a }
    }
}
