import CoreAudio
import Observation
import SwiftUI

// Dados e regras do módulo Áudio: dispositivos de saída e entrada, qual é o padrão, troca com
// um clique e a trava do microfone. Tudo por evento do Core Audio (conectou, desconectou,
// padrão mudou): parado, não gasta nada — sem timer, sem leitura periódica.
//
// O volume do sistema e as teclas de volume continuam no NivelService (Modulos/Nivel).
// Volume e mudo por app: PorApp/VolumePorApp.swift (taps sob demanda).

/// Algo que aconteceu com o áudio e que a ilha pode mostrar (quando houver o árbitro da ilha compacta).
struct EventoAudio: Identifiable, Equatable, Sendable {
    enum Tipo: Sendable, Equatable { case conectou, desconectou, saidaMudou, entradaMudou, travaDevolveu, travaDesistiu }
    let id = UUID()
    let tipo: Tipo
    let data: Date
    /// Frase pronta: "AirPods Pro conectou", "Microfone devolvido para o MacBook Pro".
    let texto: String
    /// SF Symbol do dispositivo envolvido.
    let icone: String
}

@Observable @MainActor
final class AudioServico {
    static let shared = AudioServico()

    private(set) var dispositivos: [DispositivoAudio] = []
    private(set) var saidaPadrao: AudioObjectID = 0
    private(set) var entradaPadrao: AudioObjectID = 0
    private(set) var somDoSistema: AudioObjectID = 0

    /// Ponto de ligação com a ilha: o evento mais recente (dispositivo conectou/desconectou,
    /// saída mudou, trava devolveu o microfone). Quem quiser avisar no notch observa isto.
    private(set) var ultimoEvento: EventoAudio?
    /// Os últimos eventos, o mais novo primeiro (para a Central).
    private(set) var historico: [EventoAudio] = []

    // Ajustes (chaves `modulo.audio.*`)
    var travaLigada: Bool {
        didSet { Ajustes.definir("audio", "travaMic", travaLigada) }
    }
    /// UID do microfone travado; nil = o embutido.
    var micTravadoEscolhido: String? {
        didSet { Ajustes.definir("audio", "micTravado", micTravadoEscolhido) }
    }
    /// Ao trocar a saída pelo Crew, os alertas e efeitos sonoros vão junto.
    var alertasAcompanham: Bool {
        didSet { Ajustes.definir("audio", "alertasAcompanham", alertasAcompanham) }
    }
    /// Aviso passageiro na ilha fechada: saída conectou/desconectou, o macOS trocou a saída, a
    /// trava devolveu o microfone.
    var avisarNaIlha: Bool {
        didSet { Ajustes.definir("audio", "avisarNaIlha", avisarNaIlha) }
    }

    var saidas: [DispositivoAudio] { dispositivos.filter(\.temSaida) }
    var entradas: [DispositivoAudio] { dispositivos.filter(\.temEntrada) }
    var saidaAtual: DispositivoAudio? { dispositivos.first { $0.id == saidaPadrao } }
    var entradaAtual: DispositivoAudio? { dispositivos.first { $0.id == entradaPadrao } }
    var somDoSistemaAtual: DispositivoAudio? { dispositivos.first { $0.id == somDoSistema } }
    var micEmbutido: DispositivoAudio? { entradas.first { $0.transporte == .embutido } }
    /// O microfone que a trava mantém (escolhido, ou o embutido).
    var micTravadoUID: String? { micTravadoEscolhido ?? micEmbutido?.uid }
    var micTravado: DispositivoAudio? { entradas.first { $0.uid == micTravadoUID } }

    @ObservationIgnored private let log = Log.de("audio")
    @ObservationIgnored private var ouvintes: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    @ObservationIgnored private var eco = EcoTrocas()
    @ObservationIgnored private var vistoEm: [String: Date] = [:]
    @ObservationIgnored private var devolucoes: [Date] = []
    @ObservationIgnored private var devolucaoPendente: Task<Void, Never>?
    @ObservationIgnored private var ativo = false

    private init() {
        travaLigada = Ajustes.bool("audio", "travaMic", padrao: true)
        micTravadoEscolhido = Ajustes.string("audio", "micTravado")
        alertasAcompanham = Ajustes.bool("audio", "alertasAcompanham", padrao: true)
        avisarNaIlha = Ajustes.bool("audio", "avisarNaIlha", padrao: true)
    }

    // MARK: Ciclo

    func iniciar() {
        guard !ativo else { return }
        ativo = true
        dispositivos = CoreAudioHW.dispositivos()
        for d in dispositivos { vistoEm[d.uid] = .distantPast }
        lerPadroes()
        ouvir(kAudioHardwarePropertyDevices) { [weak self] in self?.listaMudou() }
        ouvir(kAudioHardwarePropertyDefaultOutputDevice) { [weak self] in self?.padraoMudou(.saida) }
        ouvir(kAudioHardwarePropertyDefaultInputDevice) { [weak self] in self?.padraoMudou(.entrada) }
        ouvir(kAudioHardwarePropertyDefaultSystemOutputDevice) { [weak self] in self?.padraoMudou(.somDoSistema) }
        log.info("áudio: \(self.saidas.count) saídas, \(self.entradas.count) entradas")
        VolumePorApp.shared.iniciar()
    }

    func parar() {
        guard ativo else { return }
        ativo = false
        VolumePorApp.shared.parar()
        devolucaoPendente?.cancel()
        for (endereco, bloco) in ouvintes {
            var a = endereco
            AudioObjectRemovePropertyListenerBlock(CoreAudioHW.sistema, &a, .main, bloco)
        }
        ouvintes.removeAll()
    }

    private func ouvir(_ sel: AudioObjectPropertySelector, _ acao: @escaping @MainActor @Sendable () -> Void) {
        var a = CoreAudioHW.endereco(sel)
        let bloco = Self.bloco(acao)
        if AudioObjectAddPropertyListenerBlock(CoreAudioHW.sistema, &a, .main, bloco) == noErr {
            ouvintes.append((a, bloco))
        }
    }

    /// O Core Audio chama na fila principal (`.main` no registro), então dá para entrar no MainActor.
    private nonisolated static func bloco(_ acao: @escaping @MainActor @Sendable () -> Void) -> AudioObjectPropertyListenerBlock {
        { _, _ in MainActor.assumeIsolated { acao() } }
    }

    // MARK: Ações

    /// Troca a saída padrão (e os alertas, se o ajuste pedir).
    func usarSaida(_ d: DispositivoAudio) {
        eco.esperar("saida", d.id)
        if CoreAudioHW.definirPadrao(.saida, d.id) { saidaPadrao = d.id }
        if alertasAcompanham { usarSomDoSistema(d) }
    }

    func usarEntrada(_ d: DispositivoAudio) {
        devolucaoPendente?.cancel()
        eco.esperar("entrada", d.id)
        if CoreAudioHW.definirPadrao(.entrada, d.id) { entradaPadrao = d.id }
    }

    func usarSomDoSistema(_ d: DispositivoAudio) {
        guard d.id != somDoSistema else { return }
        eco.esperar("somDoSistema", d.id)
        if CoreAudioHW.definirPadrao(.somDoSistema, d.id) { somDoSistema = d.id }
    }

    // MARK: Eventos do Core Audio

    private func lerPadroes() {
        saidaPadrao = CoreAudioHW.padrao(.saida)
        entradaPadrao = CoreAudioHW.padrao(.entrada)
        somDoSistema = CoreAudioHW.padrao(.somDoSistema)
    }

    /// Relê a lista. O que chegou ou saiu vira evento; se o microfone travado voltou e a
    /// entrada está em outro, volta para ele. Chamado por qualquer aviso do Core Audio, porque
    /// o aviso de "padrão mudou" às vezes chega antes do de "lista mudou".
    private func releLista() {
        let antes = dispositivos
        let agora = CoreAudioHW.dispositivos()
        guard agora != antes else { return }
        dispositivos = agora
        let uidsAntes = Set(antes.map(\.uid)), uidsAgora = Set(agora.map(\.uid))
        let chegaram = agora.filter { !uidsAntes.contains($0.uid) }
        let sairam = antes.filter { !uidsAgora.contains($0.uid) }
        for d in chegaram {
            vistoEm[d.uid] = .now
            registrar(.conectou, "\(d.nome) conectou", d.icone(entrada: !d.temSaida), naIlha: d.temSaida)
        }
        for d in sairam {
            registrar(.desconectou, "\(d.nome) desconectou", d.icone(entrada: !d.temSaida), naIlha: d.temSaida)
        }
        let atual = dispositivos.first { $0.id == CoreAudioHW.padrao(.entrada) }?.uid
        if TravaMicrofone.aoReconectar(ligada: travaLigada, alvoUID: micTravadoUID,
                                       chegaram: Set(chegaram.map(\.uid)), atualUID: atual),
           let alvo = micTravado {
            log.info("trava: \(alvo.nome, privacy: .public) voltou; entrada volta para ele")
            usarEntrada(alvo)
            registrar(.travaDevolveu, "Microfone de volta no \(alvo.nome)", alvo.icone(entrada: true), naIlha: true)
        }
    }

    private func listaMudou() {
        releLista()
        lerPadroes()
    }

    private func padraoMudou(_ papel: CoreAudioHW.Papel) {
        releLista()
        let id = CoreAudioHW.padrao(papel)
        switch papel {
        case .saida:
            saidaPadrao = id
            if eco.consumir("saida", id) { return }
            if let d = saidaAtual { registrar(.saidaMudou, "Som saindo por \(d.nome)", d.icone(entrada: false), naIlha: true) }
        case .somDoSistema:
            somDoSistema = id
            _ = eco.consumir("somDoSistema", id)
        case .entrada:
            entradaPadrao = id
            if eco.consumir("entrada", id) { return }
            let nova = entradaAtual
            log.info("entrada mudou (fora do Crew) para \(nova?.nome ?? "?", privacy: .public)")
            avaliarTrava()
        }
    }

    /// O macOS (ou alguém) trocou a entrada: a trava decide se devolve.
    private func avaliarTrava() {
        let decisao = TravaMicrofone.decidir(ligada: travaLigada, alvoUID: micTravadoUID, novaUID: entradaAtual?.uid,
                                             entradas: Set(entradas.map(\.uid)), vistoEm: vistoEm,
                                             devolucoes: devolucoes, agora: .now)
        switch decisao {
        case .nada(let motivo):
            log.info("trava: nada a fazer (\(motivo, privacy: .public))")
            if motivo.hasPrefix("o macOS insistiu"), let alvo = micTravado {
                registrar(.travaDesistiu, "O macOS insistiu; microfone ficou fora do \(alvo.nome)", "mic.slash", naIlha: true)
            } else if let d = entradaAtual {
                registrar(.entradaMudou, "Microfone: \(d.nome)", d.icone(entrada: true))
            }
        case .devolver(let uid):
            // Um instante para o macOS terminar a troca dele (o Bluetooth troca em etapas).
            devolucaoPendente?.cancel()
            devolucaoPendente = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                guard let self, !Task.isCancelled else { return }
                self.releLista()
                self.lerPadroes()
                guard let alvo = self.entradas.first(where: { $0.uid == uid }), self.entradaPadrao != alvo.id else { return }
                let de = self.entradaAtual?.nome ?? "outro"
                self.devolucoes.append(.now)
                self.devolucoes.removeAll { Date.now.timeIntervalSince($0) > TravaMicrofone.janelaLaco }
                self.log.info("trava: \(de, privacy: .public) pegou a entrada; devolvendo para \(alvo.nome, privacy: .public)")
                self.usarEntrada(alvo)
                self.registrar(.travaDevolveu, "Microfone mantido no \(alvo.nome) (\(de) tentou pegar)", alvo.icone(entrada: true), naIlha: true)
            }
        }
    }

    private func registrar(_ tipo: EventoAudio.Tipo, _ texto: String, _ icone: String, naIlha: Bool = false) {
        let e = EventoAudio(tipo: tipo, data: .now, texto: texto, icone: icone)
        ultimoEvento = e
        historico.insert(e, at: 0)
        if historico.count > 30 { historico.removeLast(historico.count - 30) }
        guard naIlha, avisarNaIlha else { return }
        // Um id só: conectou → "som saindo por…" troca o aviso em vez de empilhar.
        let cor = tipo == .travaDesistiu ? Color(hex: "#F5A524") : tipo == .desconectou ? Color(hex: "#8E939C") : Color(hex: "#34D399")
        Arbitro.shared.publicar(Sinal(id: "audio.aviso", lugar: .barra, prioridade: .alerta, duracao: 4,
                                      conteudo: AnyView(AvisoAudio(icone: icone, texto: texto, cor: cor))))
    }
}
