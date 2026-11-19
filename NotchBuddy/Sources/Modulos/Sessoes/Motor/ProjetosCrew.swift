import Foundation
import AppKit

// Os projetos do app do Crew: pastas onde o Hugo abre sessões. Junta duas fontes, sem
// duplicar (a chave é a raiz do repositório): as que ele adicionou no Crew e as pastas das
// sessões que estão abertas agora. O Crew não consulta nenhum outro app para isso.
// Qualquer projeto pode ser arquivado (sai da lista e fica em "Arquivados", de onde volta) ou
// excluído da lista (some até ser adicionado de novo). Nada disso toca a pasta.
// O que o Hugo configurou em cada um (nome, ícone, ordem, padrões) mora em `ConfigProjetos`.

struct ProjetoCrew: Identifiable, Hashable {
    /// A pasta (raiz do repositório).
    let caminho: String
    let nome: String
    /// Cor fixa do projeto (hex), a mesma da ilha.
    let cor: String
    /// Adicionado pelo Hugo no Crew (dá para tirar).
    let adicionado: Bool
    var id: String { caminho }

    var caminhoCurto: String {
        caminho.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
    }
}

@MainActor
final class ProjetosCrew: ObservableObject {
    static let shared = ProjetosCrew()

    @Published private(set) var lista: [ProjetoCrew] = []
    /// Arquivados pelo Hugo: fora da lista e dos menus, guardados para voltar.
    @Published private(set) var arquivados: [ProjetoCrew] = []

    private static let modulo = "sessoes"
    private var adicionados: [String] {
        get { UserDefaults.standard.stringArray(forKey: Ajustes.chave(Self.modulo, "projetos")) ?? [] }
        set { Ajustes.definir(Self.modulo, "projetos", newValue) }
    }

    private var chavesArquivados: [String] {
        get { UserDefaults.standard.stringArray(forKey: Ajustes.chave(Self.modulo, "projetosArquivados")) ?? [] }
        set { Ajustes.definir(Self.modulo, "projetosArquivados", newValue) }
    }
    private var chavesExcluidos: [String] {
        get { UserDefaults.standard.stringArray(forKey: Ajustes.chave(Self.modulo, "projetosExcluidos")) ?? [] }
        set { Ajustes.definir(Self.modulo, "projetosExcluidos", newValue) }
    }

    /// Último projeto em que o Hugo abriu sessão pelo Crew.
    var ultimo: String? {
        get { Ajustes.string(Self.modulo, "ultimoProjeto") }
        set { Ajustes.definir(Self.modulo, "ultimoProjeto", newValue) }
    }

    /// Relê as duas fontes. Barato: só leitura de `.git`.
    func recarregar() async {
        var adicionadoPor: [String: Bool] = [:]
        var ordem: [String] = []
        func entra(_ caminho: String, adicionado: Bool = false) {
            let raiz = Projetos.raiz(de: caminho) ?? caminho
            if let ja = adicionadoPor[raiz] {
                adicionadoPor[raiz] = ja || adicionado
            } else {
                adicionadoPor[raiz] = adicionado
                ordem.append(raiz)
            }
        }
        for c in adicionados where FileManager.default.fileExists(atPath: c) { entra(c, adicionado: true) }
        for t in AppState.shared.tasks where t.sessionId != nil && !t.isIntegration {
            if let c = t.sessionCwd { entra(c) }
        }
        let config = ConfigProjetos.shared
        let todos: [ProjetoCrew] = config.ordenar(ordem.map { c in
            ProjetoCrew(caminho: c, nome: config.de(c).nome ?? URL(fileURLWithPath: c).lastPathComponent,
                        cor: Projetos.cor(de: c) ?? "#9398A1", adicionado: adicionadoPor[c] ?? false)
        })
        let fora = Set(chavesExcluidos), guardados = Set(chavesArquivados)
        lista = todos.filter { !fora.contains($0.caminho) && !guardados.contains($0.caminho) }
        arquivados = todos.filter { guardados.contains($0.caminho) && !fora.contains($0.caminho) }
    }

    /// Tira o projeto da lista e guarda em "Arquivados".
    func arquivar(_ caminho: String) async {
        if !chavesArquivados.contains(caminho) { chavesArquivados.append(caminho) }
        if ultimo == caminho { ultimo = nil }
        await recarregar()
    }

    func desarquivar(_ caminho: String) async {
        chavesArquivados.removeAll { $0 == caminho }
        await recarregar()
    }

    /// Some da lista do Crew, venha de onde vier (adicionado ou sessão aberta). Só volta
    /// se o Hugo adicionar a pasta de novo. A pasta não é tocada.
    func excluir(_ caminho: String) async {
        adicionados.removeAll { $0 == caminho }
        chavesArquivados.removeAll { $0 == caminho }
        if !chavesExcluidos.contains(caminho) { chavesExcluidos.append(caminho) }
        if ultimo == caminho { ultimo = nil }
        await recarregar()
    }

    /// Só no modo de capturas do app: projetos de exemplo, nada lido nem gravado.
    func exemploParaCaptura() {
        let casa = FileManager.default.homeDirectoryForCurrentUser.path
        lista = [("crew", "Crew", "#FF7A59"), ("loja", "Loja", "#38BDF8"), ("site", "Site", "#34D399")].map {
            ProjetoCrew(caminho: casa + "/dev/" + $0.0, nome: $0.1, cor: $0.2, adicionado: true)
        }
    }

    func projeto(de caminho: String?) -> ProjetoCrew? {
        guard let r = Projetos.raiz(de: caminho) else { return nil }
        return lista.first { $0.caminho == r }
    }

    /// Pergunta a pasta ao Hugo e adiciona. Devolve o projeto escolhido.
    func adicionarPerguntando() async -> ProjetoCrew? {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.allowsMultipleSelection = false
        p.prompt = "Adicionar projeto"
        p.message = "Escolha a pasta do projeto"
        guard p.runModal() == .OK, let url = p.url else { return nil }
        return await adicionar(url.path)
    }

    @discardableResult
    func adicionar(_ caminho: String) async -> ProjetoCrew? {
        let raiz = Projetos.raiz(de: caminho) ?? caminho
        if !adicionados.contains(raiz) { adicionados.append(raiz) }
        // Adicionar de novo desfaz arquivar e excluir.
        chavesExcluidos.removeAll { $0 == raiz }
        chavesArquivados.removeAll { $0 == raiz }
        await recarregar()
        return lista.first { $0.caminho == raiz }
    }

}
