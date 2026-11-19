import SwiftUI

// A única lista de módulos do Crew. Módulo novo entra aqui (uma linha) e o resto se monta
// sozinho: aba na ilha, página e ajustes na Central, liga/desliga.

@MainActor
final class Registro: ObservableObject {
    static let shared = Registro()

    let modulos: [any Modulo] = [
        SessoesModulo.shared,
        HomiesModulo.shared,
        AutomacaoModulo.shared,
        DiarioModulo.shared,
        SistemaModulo.shared,
        ModelosModulo.shared,
        VozModulo.shared,
        AgentesModulo.shared,
        AudioModulo.shared,
        DiscoModulo.shared,
        AppsModulo.shared,
        NivelModulo.shared,
        MidiaModulo.shared,
        ArquivosModulo.shared,
        CapturaModulo.shared,
        VideoModulo.shared,
        UsoModulo.shared,
        RotinasModulo.shared,
        ComandoModulo.shared,
    ]

    @Published private(set) var ligados: Set<String> = []

    private init() {
        for m in modulos where !m.podeDesligar || Ajustes.bool(m.id, "ligado", padrao: m.ligadoPorPadrao) {
            ligados.insert(m.id)
        }
    }

    /// No launch: inicia os módulos ligados.
    func iniciar() {
        for m in modulos where ligados.contains(m.id) { m.iniciar() }
    }

    func modulo(_ id: String?) -> (any Modulo)? {
        guard let id else { return nil }
        return modulos.first { $0.id == id }
    }

    func estaLigado(_ id: String) -> Bool { ligados.contains(id) }

    func ligar(_ id: String, _ ligar: Bool) {
        guard let m = modulo(id), m.podeDesligar, ligar != ligados.contains(id) else { return }
        Ajustes.definir(id, "ligado", ligar)
        if ligar {
            ligados.insert(id)
            m.iniciar()
        } else {
            ligados.remove(id)
            m.parar()
            let s = AppState.shared
            if s.view == .modulo && s.moduloAberto == id { s.view = .overview }
        }
    }

    /// Módulos ligados com aba na ilha, na ordem do registro (todos aparecem na grade de módulos).
    var comAba: [any Modulo] { modulos.filter { ligados.contains($0.id) && $0.temAba } }

    /// Os que têm atalho direto no cabeçalho, ao lado da câmera (cabem poucos: o notch físico
    /// esconde o meio do cabeçalho).
    func favoritos(max: Int) -> [any Modulo] { Array(comAba.filter { abaNaIlha($0.id) }.prefix(max)) }

    /// Ids com atalho no topo agora (o cabeçalho informa ao desenhar): a grade não os repete.
    @Published var noTopo: [String] = []

    /// Blocos do painel "Mac agora" da home (até 4), na ordem do registro.
    static let maxBlocos = 4
    var blocosHome: [any Modulo] {
        Array(modulos.filter { ligados.contains($0.id) && $0.temBloco && naHome($0) }.prefix(Self.maxBlocos))
    }
    func naHome(_ m: any Modulo) -> Bool { Ajustes.bool(m.id, "naHome", padrao: m.blocoPorPadrao) }
    func definirNaHome(_ id: String, _ v: Bool) {
        Ajustes.definir(id, "naHome", v)
        objectWillChange.send()
    }

    /// Ajuste por módulo: atalho no topo da ilha (padrão: sim, até caber).
    func abaNaIlha(_ id: String) -> Bool { Ajustes.bool(id, "abaNaIlha", padrao: true) }

    func definirAbaNaIlha(_ id: String, _ v: Bool) {
        Ajustes.definir(id, "abaNaIlha", v)
        objectWillChange.send()
        let s = AppState.shared
        if !v, s.view == .modulo, s.moduloAberto == id { s.view = .overview }
    }

    func doPilar(_ p: Pilar) -> [any Modulo] { modulos.filter { $0.pilar == p } }
}
