import Foundation

// Leitura periódica que só roda enquanto alguém assina (docs/ARQUITETURA.md §4 e §7).
// Ninguém olhando = nenhum timer. Timer suspenso/retomado com folga (leeway), leitura numa
// fila própria (fora da main) e entrega na main.

@MainActor
final class Amostrador<Valor: Sendable> {
    private let intervalo: TimeInterval
    private let fila: DispatchQueue
    private let ler: @Sendable () -> Valor
    private let entregar: @MainActor (Valor) -> Void
    private var assinantes: Set<String> = []
    private var timer: DispatchSourceTimer?

    /// `ler` roda sempre na mesma fila serial: o leitor pode guardar o estado da leitura anterior.
    init(_ nome: String, intervalo: TimeInterval,
         ler: @escaping @Sendable () -> Valor,
         entregar: @escaping @MainActor (Valor) -> Void) {
        self.intervalo = intervalo
        self.fila = DispatchQueue(label: "crew.amostrador.\(nome)", qos: .utility)
        self.ler = ler
        self.entregar = entregar
    }

    var rodando: Bool { timer != nil }

    func assinar(_ quem: String) {
        assinantes.insert(quem)
        if timer == nil { ligar() }
    }

    func soltar(_ quem: String) {
        assinantes.remove(quem)
        if assinantes.isEmpty { desligar() }
    }

    private func ligar() {
        let t = DispatchSource.makeTimerSource(queue: fila)
        let folga = DispatchTimeInterval.milliseconds(max(50, Int(intervalo * 100)))
        t.schedule(deadline: .now(), repeating: intervalo, leeway: folga)
        t.setEventHandler(handler: Self.tique(ler: ler, amostrador: self))
        t.resume()
        timer = t
    }

    /// O tique roda na fila do amostrador, fora da main: o bloco não pode herdar o isolamento
    /// da main (o Swift 6 derruba o app). Por isso é montado aqui, `nonisolated`.
    nonisolated private static func tique(ler: @escaping @Sendable () -> Valor,
                                          amostrador: Amostrador) -> @Sendable () -> Void {
        { [weak amostrador] in
            let v = ler()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { amostrador?.entregar(v) }
            }
        }
    }

    private func desligar() {
        timer?.cancel()
        timer = nil
    }
}
