import SwiftUI
import IOKit.ps

// Avisos do Sistema na ilha fechada — só por evento, nenhum timer:
//   • bateria em 10 % e em 5 % fora da tomada (aviso de fonte de energia do macOS);
//   • memória em pressão crítica (fonte de pressão de memória do kernel).
// Viram um sinal de alerta na barra do árbitro e o Homie se assusta.

@MainActor
final class SistemaAlertas {
    static let shared = SistemaAlertas()

    private var fonteEnergia: CFRunLoopSource?
    private var pressao: DispatchSourceMemoryPressure?
    /// Último degrau de bateria já avisado (100 = nenhum). Volta a 100 na tomada.
    private var degrauAvisado = 100

    func ligar() {
        guard fonteEnergia == nil else { return }
        let ctx = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        if let src = IOPSNotificationCreateRunLoopSource({ _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { SistemaAlertas.shared.energiaMudou() } }
        }, ctx)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
            fonteEnergia = src
        }
        let p = DispatchSource.makeMemoryPressureSource(eventMask: [.critical], queue: .main)
        p.setEventHandler(handler: Self.pressaoMudou)
        p.resume()
        pressao = p
        energiaMudou()
    }

    func desligar() {
        if let src = fonteEnergia { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .defaultMode) }
        fonteEnergia = nil
        pressao?.cancel()
        pressao = nil
        Arbitro.shared.retirar("sistema.alerta")
    }

    private func energiaMudou() {
        guard let b = LeitorBateria.ler() else { return }
        if b.naTomada || b.carregando {
            degrauAvisado = 100
            Arbitro.shared.retirar("sistema.alerta")
            return
        }
        let pct = Int((b.nivel * 100).rounded())
        for degrau in [5, 10] where pct <= degrau && degrauAvisado > degrau {
            degrauAvisado = degrau
            var texto = "Bateria em \(pct)% — ligue na tomada"
            if let m = b.minutosRestantes { texto += " (\(m) min)" }
            avisar(icone: pct <= 5 ? "battery.0percent" : "battery.25percent", texto: texto, cor: Color(hex: "#F4505E"))
            break
        }
    }

    nonisolated private static func pressaoMudou() {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                SistemaAlertas.shared.avisar(icone: "memorychip", texto: "Memória em pressão crítica — feche algo pesado",
                                             cor: Color(hex: "#F5A524"))
            }
        }
    }

    private func avisar(icone: String, texto: String, cor: Color) {
        Arbitro.shared.publicar(Sinal(id: "sistema.alerta", lugar: .barra, prioridade: .alerta, duracao: 8,
                                      conteudo: AnyView(AvisoBarra(icone: icone, texto: texto, cor: cor))))
        NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.surprised)
    }
}

/// Uma linha de aviso na barra da ilha fechada.
struct AvisoBarra: View {
    let icone: String
    let texto: String
    let cor: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icone).font(.system(size: 13, weight: .semibold)).foregroundColor(cor)
            Text(texto).font(.system(size: 12, weight: .medium)).foregroundColor(Color(hex: "#DADDE2"))
                .lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
    }
}
