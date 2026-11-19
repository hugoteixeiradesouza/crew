import SwiftUI
import AppKit

// O catálogo dos setores na janela do Crew: que ferramentas cada setor tem, qual seleção abre
// cada uma e como se chega nelas de fora (menu, ⌘1 … ⌘6, `Central.abrir(modulo:)`, crew://).
// A definição dos setores (nome, ícone, frase) mora em `Nucleo/Setor.swift`.

/// Uma ferramenta dentro de um setor: quase sempre um módulo com tela de trabalho
/// (`Modulo.central()`); na Mesa, também o navegador e os arquivos, que não são módulo.
@MainActor
struct FerramentaSetor: Identifiable {
    let id: String
    let nome: String
    /// SF Symbol.
    let icone: String
    let resumo: String
    let setor: Setor
    /// O módulo por trás dela (nil no navegador e nos arquivos).
    let modulo: (any Modulo)?

    /// O que a janela mostra quando ela é escolhida.
    var selecao: NavegacaoCrew.Selecao { id == Setores.navegador ? .navegador : .ferramenta(id) }
}

@MainActor
enum Setores {
    // Ferramentas que não são módulo do registro.
    static let navegador = "navegador"
    static let arquivos = "arquivos-do-projeto"

    /// Módulos com tela de trabalho. Conferido uma vez: a lista de módulos não muda com o app aberto.
    private static let comTela: Set<String> = Set(Registro.shared.modulos.filter { $0.central() != nil }.map(\.id))

    /// O módulo tem tela de trabalho num setor (senão, só página nos Ajustes).
    static func temTela(_ idModulo: String) -> Bool { comTela.contains(idModulo) }

    /// As ferramentas do setor, na ordem em que aparecem. Só o que existe: setor sem tela
    /// para uma função prometida não ganha tela de mentira.
    static func ferramentas(_ s: Setor) -> [FerramentaSetor] {
        var lista: [FerramentaSetor] = []
        if s == .mesa {
            lista.append(FerramentaSetor(id: navegador, nome: "Navegador", icone: "globe",
                                         resumo: "O navegador do Crew: abas no alto, como no Safari, e um espaço por projeto.",
                                         setor: .mesa, modulo: nil))
            lista.append(FerramentaSetor(id: arquivos, nome: "Arquivos", icone: "folder",
                                         resumo: "A pasta de um projeto em árvore, com o arquivo aberto ao lado.",
                                         setor: .mesa, modulo: nil))
        }
        for m in Registro.shared.doSetor(s) where comTela.contains(m.id) {
            lista.append(FerramentaSetor(id: m.id, nome: m.nome, icone: m.icone, resumo: m.resumo, setor: s, modulo: m))
        }
        return lista
    }

    static func ferramenta(_ id: String) -> FerramentaSetor? {
        for s in Setor.allCases {
            if let f = ferramentas(s).first(where: { $0.id == id }) { return f }
        }
        return nil
    }

    /// Em que setor a janela está, pelo que ela mostra. Sessões, projetos e histórico são do Comando.
    static func setor(de selecao: NavegacaoCrew.Selecao) -> Setor {
        switch selecao {
        case .navegador: return .mesa
        case .ferramenta(let id): return ferramenta(id)?.setor ?? .comando
        default: return .comando
        }
    }

    /// O que abre na primeira visita a um setor: no Comando, o início; nos outros, a primeira
    /// ferramenta ligada.
    static func entrada(_ s: Setor) -> NavegacaoCrew.Selecao {
        guard s != .comando else { return .inicio }
        let lista = ferramentas(s)
        let ligada = lista.first { f in f.modulo.map { Registro.shared.estaLigado($0.id) } ?? true }
        return (ligada ?? lista.first)?.selecao ?? .inicio
    }
}

extension NavegacaoCrew {
    /// O setor na tela (sai da seleção: não há dois estados para ficarem desencontrados).
    var setor: Setor { Setores.setor(de: selecao) }

    /// Clique na barra de setores (ou ⌘1 … ⌘6): volta ao que estava aberto naquele setor.
    func irPara(_ s: Setor) {
        guard s != setor else { return }
        selecao = ultimaNoSetor[s] ?? Setores.entrada(s)
    }

    /// Abre a tela de uma ferramenta (id do módulo, ou o navegador / os arquivos da Mesa).
    func abrirFerramenta(_ id: String) {
        guard let f = Setores.ferramenta(id) else { return }
        selecao = f.selecao
    }
}

extension Notification.Name {
    /// App do Crew: vai para um setor (`object`: `Setor.rawValue`).
    static let irParaSetor = Notification.Name("crew.irParaSetor")
    /// App do Crew: abre a tela de uma ferramenta (`object`: id, String).
    static let abrirFerramentaNoApp = Notification.Name("crew.abrirFerramentaNoApp")
}

extension JanelaCrew {
    /// Abre o app do Crew num setor.
    func abrir(setor: Setor) {
        abrir()
        // Janela recém-criada: a tela ainda não escuta; avisa no próximo ciclo.
        DispatchQueue.main.async { NotificationCenter.default.post(name: .irParaSetor, object: setor.rawValue) }
    }

    /// Abre o app do Crew na tela de trabalho de uma ferramenta.
    func abrir(ferramenta id: String) {
        abrir()
        DispatchQueue.main.async { NotificationCenter.default.post(name: .abrirFerramentaNoApp, object: id) }
    }
}

extension AlvoMenu {
    /// Menu "Ir" (⌘1 … ⌘6): o `tag` do item é o número do setor.
    @objc func irParaSetor(_ item: NSMenuItem) {
        guard let s = Setor.allCases.first(where: { $0.numero == item.tag }) else { return }
        JanelaCrew.shared.abrir(setor: s)
    }
}

extension Central {
    /// Abre os Ajustes na página de configuração de um módulo.
    static func ajustes(modulo: String) { JanelaAjustes.shared.abrir(.modulo(modulo)) }
}

/// Recebe os pedidos de ir para um setor ou abrir uma ferramenta (menu, atalhos, ilha, crew://).
struct AvisosDosSetores: ViewModifier {
    let nav: NavegacaoCrew

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .irParaSetor)) { n in
                if let s = (n.object as? String).flatMap(Setor.init(rawValue:)) { nav.irPara(s) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .abrirFerramentaNoApp)) { n in
                if let id = n.object as? String { nav.abrirFerramenta(id) }
            }
    }
}
