import SwiftUI

// Aba do Áudio na ilha, em dois modos (chave "Saídas | Apps" à direita):
//   • Apps — os apps tocando agora, cada um com slider de volume (até 400%) e mudo;
//   • Saídas — duas colunas (Saída, Microfone): cada dispositivo um ícone redondo (o atual
//     aceso), o nome curto embaixo e o cadeado da trava no título do microfone.
// Abre em Apps quando algum app está tocando ou tem ajuste; senão em Dispositivos. Tudo por
// evento: nada a assinar.

struct AudioAba: View {
    private let s = AudioServico.shared
    private let v = VolumePorApp.shared
    enum Modo { case apps, dispositivos }
    @State private var escolhido: Modo?

    private var modo: Modo {
        escolhido ?? (v.tocando.contains { !v.ignorado($0.id) } || !v.ajustes.isEmpty ? .apps : .dispositivos)
    }

    var body: some View {
        ZStack {
            CardBackground(wash: nil)
            HStack(spacing: 14) {
                Group {
                    if modo == .apps {
                        VolumeAppsIlha()
                    } else {
                        HStack(alignment: .top, spacing: 18) {
                            ColunaDispositivos(titulo: "Saída", lista: s.saidas, atual: s.saidaPadrao,
                                               entrada: false) { s.usarSaida($0) }
                            Rectangle().fill(Color.white.opacity(0.07)).frame(width: 1, height: 58)
                            ColunaDispositivos(titulo: "Microfone", lista: s.entradas, atual: s.entradaPadrao,
                                               entrada: true, trava: true) { s.usarEntrada($0) }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                seletor
            }
            .padding(.leading, 108)
            .padding(.trailing, 12)
        }
    }

    /// Troca entre os dois modos, com texto (antes eram dois ícones sem legenda).
    private var seletor: some View {
        VStack(spacing: 3) {
            botaoModo(.dispositivos, "Saídas")
            botaoModo(.apps, "Apps")
        }
        .padding(3)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func botaoModo(_ m: Modo, _ texto: String) -> some View {
        Button { escolhido = m } label: {
            Text(texto)
                .font(.system(size: 11, weight: modo == m ? .semibold : .regular))
                .foregroundColor(modo == m ? Color(hex: "#0B0C0E") : Color(hex: "#9398A1"))
                .frame(width: 54, height: 24)
                .background(modo == m ? Color(hex: "#F5F6F8") : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(m == .apps ? "Volume de cada app" : "Saída de som e microfone")
    }
}

/// Uma coluna: título, os dispositivos como ícones redondos (o atual aceso) e o nome curto do
/// atual — ou do que está sob o mouse. No microfone, o cadeado da trava fica no título.
struct ColunaDispositivos: View {
    let titulo: String
    let lista: [DispositivoAudio]
    let atual: UInt32
    let entrada: Bool
    var trava = false
    let usar: (DispositivoAudio) -> Void
    @State private var sobre: DispositivoAudio?
    private let s = AudioServico.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Text(titulo.uppercased())
                    .font(.system(size: 9.5, weight: .semibold)).tracking(0.6)
                    .foregroundColor(Color(hex: "#7C818A"))
                if trava {
                    Button { s.travaLigada.toggle() } label: {
                        Image(systemName: s.travaLigada ? "lock.fill" : "lock.open")
                            .font(.system(size: 9.5))
                            .foregroundColor(s.travaLigada ? Color(hex: "#34D399") : Color(hex: "#7C818A"))
                    }
                    .buttonStyle(.plain)
                    .help(s.travaLigada
                          ? "Travado: se o macOS trocar o microfone sozinho (ex.: AirPods conectando), o Crew devolve. Clique para destravar."
                          : "Livre: o macOS escolhe o microfone. Clique para travar no atual.")
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(lista) { d in
                        let ativo = d.id == atual
                        Button { usar(d) } label: {
                            Image(systemName: d.icone(entrada: entrada))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(ativo ? Color(hex: "#0B0C0E") : Color(hex: "#DADDE2"))
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(ativo ? Color(hex: "#F5F6F8")
                                                          : Color.white.opacity(sobre?.id == d.id ? 0.16 : 0.09)))
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help(d.nome)
                        .onHover { sobre = $0 ? d : (sobre?.id == d.id ? nil : sobre) }
                    }
                    if lista.isEmpty {
                        Text("Nenhum").font(.system(size: 11.5)).foregroundColor(Color(hex: "#5F646D"))
                    }
                }
            }
            .frame(height: 32)
            Text(legenda)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(Color(hex: sobre == nil ? "#E8E9EC" : "#9398A1"))
                .lineLimit(1)
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }

    private var legenda: String {
        if let d = sobre, d.id != atual { return "Trocar para \(Self.nomeCurto(d.nome))" }
        guard let d = lista.first(where: { $0.id == atual }) else { return "—" }
        let n = Self.nomeCurto(d.nome)
        return trava && s.travaLigada ? "\(n) · travado" : n
    }

    /// "AirPods Pro de Hugo" → "AirPods Pro"; "MacBook Air Speakers" → "MacBook Air";
    /// "iPhone de Hugo Microphone" → "iPhone".
    static func nomeCurto(_ nome: String) -> String {
        var n = nome
        for sufixo in [" Microphone", " Speakers", " Microfone", " Alto-falantes"] where n.hasSuffix(sufixo) {
            n = String(n.dropLast(sufixo.count))
        }
        if let r = n.range(of: " de ", options: .backwards) { n = String(n[..<r.lowerBound]) }
        if let r = n.range(of: "’s ") ?? n.range(of: "'s ") { n = String(n[r.upperBound...]) }
        return n.trimmingCharacters(in: .whitespaces)
    }
}

/// Aviso do Áudio na barra da ilha fechada (via árbitro).
struct AvisoAudio: View {
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
