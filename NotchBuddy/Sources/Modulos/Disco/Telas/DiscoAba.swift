import SwiftUI

// Aba do Disco na ilha: espaço livre e quanto dá para recuperar com segurança, com um botão.
// Limpar abre a confirmação aqui mesmo (o que sai e quanto); a lista inteira fica na Central.

struct DiscoAba: View {
    @Environment(\.telaVisivel) private var telaVisivel
    private let s = DiscoServico.shared

    private let cinza = Color(hex: "#8E939C")
    private let apagado = Color(hex: "#5F646D")
    private let texto = Color(hex: "#F5F6F8")

    var body: some View {
        ZStack {
            CardBackground(wash: nil)
            Group {
                if let lista = s.confirmacao {
                    confirmacao(lista)
                } else {
                    HStack(spacing: 18) {
                        espaco.frame(width: 170)
                        Rectangle().fill(Color.white.opacity(0.07)).frame(width: 1, height: 58)
                        limpeza.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.leading, 108)
            .padding(.trailing, 18)
        }
        .onAppear { if telaVisivel { s.assinar("aba") } }
        .onChange(of: telaVisivel) { _, v in v ? s.assinar("aba") : s.soltar("aba") }
        .onDisappear { s.soltar("aba") }
    }

    // MARK: Espaço

    private var espaco: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Livre").font(.system(size: 10.5)).foregroundColor(cinza)
            Text(s.volume.map { DiscoFormato.bytes($0.livre) } ?? "—")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundColor(texto).monospacedDigit()
            BarraDisco(volume: s.volume)
            Text(s.volume.map { "de \(DiscoFormato.bytes($0.total))" } ?? " ")
                .font(.system(size: 10.5)).foregroundColor(cinza).monospacedDigit()
        }
    }

    // MARK: Limpeza

    @ViewBuilder
    private var limpeza: some View {
        if s.movendo {
            linhaProgresso("Movendo para a Lixeira…")
        } else if s.preparando {
            linhaProgresso("Conferindo cada item…")
        } else if case .varrendo(let etapa) = s.estado {
            linhaProgresso(etapa)
        } else if let r = s.ultimo, Date().timeIntervalSince(r.quando) < 120 {
            resultado(r)
        } else if case .pronto(let quando) = s.estado {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(DiscoFormato.bytes(s.recuperavel))
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundColor(texto).monospacedDigit()
                    Text("recuperáveis com segurança").font(.system(size: 11)).foregroundColor(cinza)
                    Text(linhaProcurado(quando)).font(.system(size: 10)).foregroundColor(apagado).lineLimit(1)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 6) {
                    PrimaryButton("Limpar") { s.prepararConfirmacao() }
                        .disabled(s.selecionados.isEmpty)
                        .opacity(s.selecionados.isEmpty ? 0.4 : 1)
                    Button { s.procurar() } label: {
                        Text("Procurar de novo").font(.system(size: 10.5)).foregroundColor(cinza)
                    }
                    .buttonStyle(.plain)
                }
            }
        } else {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Caches que dá para limpar").font(.system(size: 12.5, weight: .medium)).foregroundColor(texto)
                    Text("Xcode, npm, brew, apps… sempre para a Lixeira.")
                        .font(.system(size: 11)).foregroundColor(cinza)
                }
                Spacer(minLength: 4)
                PrimaryButton("Procurar") { s.procurar() }
            }
        }
    }

    /// O único total a mais na ilha: projetos parados, se já foram procurados (na Central).
    private func linhaProcurado(_ quando: Date) -> String {
        let p = ProjetosServico.shared
        guard case .pronto = p.estado, p.total > 0 else { return "procurado \(DiscoFormato.ha(quando))" }
        return "\(DiscoFormato.ha(quando)) · +\(DiscoFormato.bytes(p.total)) em projetos"
    }

    private func linhaProgresso(_ t: String) -> some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small).tint(cinza)
            Text(t).font(.system(size: 12)).foregroundColor(cinza)
        }
    }

    private func resultado(_ r: ResultadoLimpeza) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(DiscoFormato.bytes(r.bytesMovidos)) na Lixeira")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(texto).monospacedDigit()
            if let v = r.bytesVoltaram {
                Text("\(DiscoFormato.bytes(v)) já voltaram ao disco").font(.system(size: 11)).foregroundColor(Color(hex: "#34D399"))
            } else {
                Text("O espaço volta quando a Lixeira for esvaziada.").font(.system(size: 11)).foregroundColor(cinza)
            }
            if !r.falhas.isEmpty || !r.retirados.isEmpty {
                Button { Central.abrir(modulo: DiscoModulo.shared.id) } label: {
                    Text("\(r.falhas.count + r.retirados.count) ficaram de fora — ver detalhes")
                        .font(.system(size: 10)).foregroundColor(Color(hex: "#F5A524")).underline()
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Confirmação

    private func confirmacao(_ lista: [ItemLimpeza]) -> some View {
        let total = lista.reduce(Int64(0)) { $0 + $1.bytes }
        let topo = lista.sorted { $0.bytes > $1.bytes }
        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Mover para a Lixeira: \(lista.count) \(lista.count == 1 ? "item" : "itens") · \(DiscoFormato.bytes(total))")
                    .font(.system(size: 13, weight: .semibold)).foregroundColor(texto).monospacedDigit()
                ForEach(topo.prefix(2)) { i in
                    HStack(spacing: 6) {
                        Text(i.nome).lineLimit(1).truncationMode(.tail)
                        Spacer(minLength: 4)
                        Text(DiscoFormato.bytes(i.bytes)).foregroundColor(cinza).monospacedDigit()
                    }
                    .font(.system(size: 11)).foregroundColor(Color(hex: "#C9CCD1"))
                }
                if lista.count > 2 {
                    Button { Central.abrir(modulo: DiscoModulo.shared.id) } label: {
                        Text("e mais \(lista.count - 2) — ver lista completa")
                            .font(.system(size: 10.5)).foregroundColor(cinza).underline()
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 6) {
                PrimaryButton("Mover") { s.confirmarMover() }
                SecondaryButton("Cancelar") { s.cancelarConfirmacao() }
            }
        }
    }
}
