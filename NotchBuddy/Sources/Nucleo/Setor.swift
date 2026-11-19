import Foundation

// Os setores do Crew — docs/ARQUITETURA.md §1. Um setor é um problema que o Crew ajuda a
// resolver; é por ele que o app (barra de setores da janela) e os Ajustes se organizam.
// Nomes, ícones e frases moram só aqui: trocar "Spot" por outro nome é mudar uma linha.
// Os nomes de tela são em inglês, na pegada de rua do Crew e do Homie (Hugo, 2026-11-13):
// Squad, Spot, Booth, Rig, Grind, Link; a busca ⌥Espaço é o Plug. No código, os casos e as
// pastas seguem em português (comando, mesa, estudio…): mudar quebraria ajustes guardados.
//
// Relação com `Pilar`: o pilar é o tema amplo do módulo (IA, Mac, Criar, Eu) e hoje só serve
// de padrão para o setor de um módulo que não declarou o dele. Nenhuma tela agrupa por pilar.

enum Setor: String, CaseIterable, Identifiable {
    case comando, mesa, estudio, maquina, dia, conexoes

    var id: String { rawValue }

    var nome: String {
        switch self {
        case .comando: "Squad"
        case .mesa: "Spot"
        case .estudio: "Booth"
        case .maquina: "Rig"
        case .dia: "Grind"
        case .conexoes: "Link"
        }
    }

    /// SF Symbol.
    var icone: String {
        switch self {
        case .comando: "command"
        case .mesa: "macwindow"
        case .estudio: "camera.aperture"
        case .maquina: "laptopcomputer"
        case .dia: "calendar"
        case .conexoes: "network"
        }
    }

    /// O problema que o setor resolve, em uma frase.
    var problema: String {
        switch self {
        case .comando: "Dirigir várias IAs sem perder o fio"
        case .mesa: "Trabalhar sem sair do Crew"
        case .estudio: "Produzir material"
        case .maquina: "O Mac aguentar e ficar limpo"
        case .dia: "Saber o que devo e o que foi feito"
        case .conexoes: "O Crew falar com o mundo de fora"
        }
    }

    /// Posição na barra de setores, a partir de 1 (é também o atalho: ⌘1 … ⌘6).
    var numero: Int { (Setor.allCases.firstIndex(of: self) ?? 0) + 1 }

    /// Os módulos de cada setor, na ordem em que aparecem nele. Módulo novo declara o setor no
    /// próprio arquivo (`let setor = Setor.estudio`); esta lista cobre os que já existiam e
    /// dá a ordem dentro do setor.
    private static let modulos: [Setor: [String]] = [
        .comando: ["sessoes", "homies", "agentes", "rotinas", "modelos", "uso"],
        .mesa: ["arquivos"],
        .estudio: ["captura", "video", "voz"],
        .maquina: ["sistema", "disco", "apps", "audio", "nivel", "midia"],
        .dia: ["diario"],
        .conexoes: ["automacao"],
    ]

    /// O setor de um módulo que não declarou o dele: pela lista acima; fora dela, pelo pilar.
    static func padrao(id: String, pilar: Pilar) -> Setor {
        if let s = modulos.first(where: { $0.value.contains(id) })?.key { return s }
        switch pilar {
        case .ia: return .comando
        case .mac: return .maquina
        case .criar: return .estudio
        case .eu: return .dia
        }
    }

    /// Ordem do módulo dentro do setor (quem não está na lista vai para o fim, na ordem do registro).
    static func posicao(_ id: String) -> Int {
        for lista in modulos.values {
            if let i = lista.firstIndex(of: id) { return i }
        }
        return Int.max
    }
}

extension Modulo {
    var setor: Setor { Setor.padrao(id: id, pilar: pilar) }
}

extension Registro {
    /// Os módulos de um setor, na ordem dele.
    func doSetor(_ s: Setor) -> [any Modulo] {
        modulos.enumerated()
            .filter { $0.element.setor == s }
            .sorted { (Setor.posicao($0.element.id), $0.offset) < (Setor.posicao($1.element.id), $1.offset) }
            .map(\.element)
    }
}
