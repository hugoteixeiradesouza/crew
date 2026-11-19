import SwiftUI

// Contrato de um módulo do Crew — ver docs/ARQUITETURA.md §4.
// Módulo novo = pasta em Modulos/<Nome>/ + uma linha em Registro.modulos.

enum Pilar: String, CaseIterable, Identifiable {
    case ia = "IA"
    case mac = "Mac"
    /// Produzir: capturar a tela, ditar e falar, vídeo e imagem — docs/ARQUITETURA.md §1.
    case criar = "Criar"
    /// O dia de trabalho do Hugo (Diário, Compromissos, Lista) — docs/ARQUITETURA.md §1.
    case eu = "Eu"
    var id: String { rawValue }
}

/// Onde uma ferramenta aparece. Um módulo não é "da ilha" nem "do app": é uma capacidade que
/// escolhe as superfícies dela — docs/ARQUITETURA.md §1.
enum Superficie: String, CaseIterable, Identifiable {
    /// O notch: olhar e agir em segundos.
    case ilha = "Ilha"
    /// A janela do Crew: onde se trabalha por horas.
    case app = "App"
    /// Atalho global: funciona com qualquer app na frente.
    case atalho = "Atalho"
    /// As sessões do Claude Code podem usar (crew:// e MCP).
    case claude = "Claude"
    var id: String { rawValue }

    var icone: String {
        switch self {
        case .ilha: "rectangle.topthird.inset.filled"
        case .app: "macwindow"
        case .atalho: "keyboard"
        case .claude: "sparkles"
        }
    }

    var explicacao: String {
        switch self {
        case .ilha: "Aparece no notch, para olhar e agir em segundos."
        case .app: "Tem lugar na janela do Crew, onde você trabalha."
        case .atalho: "Tem atalho global: funciona com qualquer app na frente."
        case .claude: "As sessões do Claude Code podem usar (crew:// e MCP)."
        }
    }
}

@MainActor
protocol Modulo: AnyObject {
    /// Identificador estável: prefixo das chaves de ajuste (`modulo.<id>.…`).
    var id: String { get }
    var nome: String { get }
    /// SF Symbol.
    var icone: String { get }
    var pilar: Pilar { get }
    /// O setor em que a ferramenta mora no app e nos Ajustes (`Nucleo/Setor.swift`).
    var setor: Setor { get }
    /// Uma frase: o que o módulo faz (aparece na Central).
    var resumo: String { get }
    var ligadoPorPadrao: Bool { get }
    /// Onde a ferramenta aparece (linha "Onde aparece" da página dela nos Ajustes).
    var superficies: [Superficie] { get }
    /// Tem aba na ilha expandida?
    var temAba: Bool { get }
    /// false = parte do coração do Crew: sempre ligado, sem chave na Central.
    var podeDesligar: Bool { get }
    /// Tem bloco no painel "Mac agora" da home?
    var temBloco: Bool { get }
    /// O bloco aparece na home sem o Hugo escolher?
    var blocoPorPadrao: Bool { get }

    /// Ao ligar o módulo (ou no launch, se ligado). Nada de timer aqui: leitura periódica
    /// só por assinatura (Amostrador), quando alguma tela estiver olhando.
    func iniciar()
    /// Ao desligar: solta tudo o que segurava.
    func parar()

    /// Aba na ilha expandida (altura padrão da ilha; o Homie fica à esquerda, ~108 pt).
    func aba() -> AnyView
    /// Bloco do painel da home (~140×36 pt): um número ou um controle, de relance.
    func bloco() -> AnyView
    /// A tela de trabalho da ferramenta: aparece no setor dela, na janela do Crew.
    func central() -> AnyView?
    /// A tela de trabalho ocupa a área toda, sem o título e a margem da página (ela traz os dela).
    var telaCheia: Bool { get }
    /// Ajustes do módulo (aparecem na página dele na Central).
    func ajustes() -> AnyView?
    /// Ação por endereço `crew://<id>/<acao>?k=v`. true = entendeu. Nunca destrutiva.
    func executar(_ acao: String, _ parametros: [String: String]) -> Bool
    /// Altura da versão expandida da aba (nil = não tem). Com ela, a aba ganha o elástico do chat:
    /// rolar para baixo estica a ilha e trava aberta; rolar para cima (no fim da lista) recolhe.
    var alturaExpandida: CGFloat? { get }
    /// Abre / fecha a versão expandida (padrão: só pede a altura).
    func expandirAba()
    func recolherAba()
}

extension Modulo {
    var ligadoPorPadrao: Bool { true }
    var superficies: [Superficie] { temAba || temBloco ? [.ilha] : [] }
    var temAba: Bool { false }
    var podeDesligar: Bool { true }
    var temBloco: Bool { false }
    var blocoPorPadrao: Bool { false }
    var telaCheia: Bool { false }
    func bloco() -> AnyView { AnyView(EmptyView()) }
    func iniciar() {}
    func parar() {}
    func aba() -> AnyView { AnyView(EmptyView()) }
    func central() -> AnyView? { nil }
    func ajustes() -> AnyView? { nil }
    func executar(_ acao: String, _ parametros: [String: String]) -> Bool { false }
    var alturaExpandida: CGFloat? { nil }
    func expandirAba() { pedirAlturaAba(alturaExpandida) }
    func recolherAba() { pedirAlturaAba(nil) }

    /// Pede à ilha uma altura maior para a aba deste módulo enquanto ela está na frente
    /// (nil = volta à padrão). A ilha anima até lá; fechar a ilha ou trocar de aba desfaz
    /// sozinho. Pedido de módulo que não está na frente é ignorado.
    func pedirAlturaAba(_ altura: CGFloat?) {
        let s = AppState.shared
        guard let altura else {
            if s.moduloAberto == id { s.alturaAba = nil }
            return
        }
        guard s.mode == .expanded, s.view == .modulo, s.moduloAberto == id else { return }
        s.alturaAba = min(max(altura, IslandConst.layout(.modulo).height), s.alturaAbaMaxima)
    }
}
