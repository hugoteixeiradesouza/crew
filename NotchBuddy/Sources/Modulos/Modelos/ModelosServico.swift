import AppKit
import Foundation
import Observation

// Dados do módulo Modelos. Nada roda sem uma tela olhando: a varredura do disco acontece quando
// a aba ou a página da Central aparece (no máximo uma vez a cada 30 s) ou no botão "Atualizar";
// o "carregado agora" é lido do Ollama a cada 5 s só enquanto alguma tela assina.

@Observable @MainActor
final class ModelosServico {
    static let shared = ModelosServico()

    private(set) var varredura: VarreduraModelos?
    private(set) var varrendo = false
    /// Nil = servidor do Ollama não respondeu (parado ou não instalado).
    private(set) var carregados: [ModeloCarregado]?
    /// Modelo sendo removido agora (para a lista mostrar o progresso).
    private(set) var removendo: String?
    /// Última mensagem de uma remoção (erro ou confirmação).
    var aviso: String?

    var servidorAtivo: Bool { carregados != nil }

    @ObservationIgnored private var amostrador: Amostrador<[ModeloCarregado]?>!
    @ObservationIgnored private var simulado = false
    private static let validadeVarredura: TimeInterval = 30

    private init() {
        amostrador = Amostrador("modelos.carregados", intervalo: 5,
            ler: { LeitorCarregados.ler() },
            entregar: { [weak self] v in
                guard let self, !self.simulado else { return }
                self.carregados = v
            })
    }

    /// Uma tela começou a mostrar os modelos.
    func assinar(_ quem: String) {
        amostrador.assinar(quem)
        if let v = varredura, Date().timeIntervalSince(v.quando) < Self.validadeVarredura { return }
        atualizar()
    }

    func soltar(_ quem: String) { amostrador.soltar(quem) }

    /// Varre as pastas de modelos fora da main.
    func atualizar() {
        guard !varrendo, !simulado else { return }
        varrendo = true
        Task {
            let v = await Task.detached(priority: .utility) { LeitorModelos.varrer() }.value
            self.varredura = v
            self.varrendo = false
        }
    }

    // MARK: Remover

    enum Modo: Equatable {
        /// `ollama rm <nome>`: definitivo, não passa pela Lixeira.
        case ollamaRm(binario: String)
        /// Arquivos exclusivos do modelo para a Lixeira.
        case lixeira([URL])
        /// Nada que a política deixe tirar.
        case impossivel
    }

    struct Plano {
        let modelo: ModeloLocal
        let modo: Modo
        /// O que sai do disco de fato.
        var libera: Int64 { modelo.recuperavel }
    }

    /// Como este modelo sairia. Ollama com o binário e o servidor de pé: pelo próprio Ollama
    /// (mantém o estado dele coerente). Senão: só os arquivos exclusivos, para a Lixeira.
    func plano(_ m: ModeloLocal) -> Plano {
        if m.origem == .ollama, servidorAtivo, let bin = varredura?.binarioOllama {
            return Plano(modelo: m, modo: .ollamaRm(binario: bin))
        }
        let arquivos = m.arquivos.filter { PoliticaModelos.podeSair($0) }
        // Ollama sem o manifesto não é remoção: os blobs sairiam e o Ollama seguiria listando o modelo.
        if arquivos.isEmpty || (m.origem == .ollama && arquivos.first != m.arquivos.first) {
            return Plano(modelo: m, modo: .impossivel)
        }
        return Plano(modelo: m, modo: .lixeira(arquivos))
    }

    /// Executa um plano já confirmado pelo Hugo.
    func executar(_ p: Plano) {
        guard removendo == nil else { return }
        removendo = p.modelo.id
        aviso = nil
        let nome = p.modelo.nome
        let modo = p.modo
        Task {
            let erro: String?
            switch modo {
            case .ollamaRm(let bin):
                let r = await Processo.rodar(bin, ["rm", nome], tempoMax: 60)
                erro = r.ok ? nil : (r.erro.isEmpty ? r.saida : r.erro).trimmingCharacters(in: .whitespacesAndNewlines)
            case .lixeira(let arquivos):
                erro = await Task.detached(priority: .userInitiated) { Self.paraLixeira(arquivos) }.value
            case .impossivel:
                erro = "Nada deste modelo pode sair com segurança."
            }
            Log.de("modelos").info("remover \(nome, privacy: .public): \(erro ?? "ok", privacy: .public)")
            self.aviso = erro.map { "Não deu para remover \(nome): \($0)" } ?? "\(nome) removido."
            self.removendo = nil
            self.varredura = nil
            self.atualizar()
        }
    }

    nonisolated private static func paraLixeira(_ arquivos: [URL]) -> String? {
        for u in arquivos where PoliticaModelos.podeSair(u) {
            do { try FileManager.default.trashItem(at: u, resultingItemURL: nil) } catch {
                return error.localizedDescription
            }
        }
        return nil
    }

    // MARK: Capturas

    /// Dados de exemplo para as capturas (`--capturas`): desliga a leitura de verdade.
    func simular(_ v: VarreduraModelos?, carregados: [ModeloCarregado]?) {
        simulado = true
        varredura = v
        self.carregados = carregados
    }
}
