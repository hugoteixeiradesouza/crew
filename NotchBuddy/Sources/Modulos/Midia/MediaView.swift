import SwiftUI

// MARK: - Aba de mídia: o que está tocando, com capa, progresso e controles

struct MediaView: View {
    @ObservedObject private var media = MediaService.shared

    var body: some View {
        ZStack {
            CardBackground(wash: nil)
            if let np = media.nowPlaying {
                HStack(spacing: 14) {
                    cover
                    VStack(alignment: .leading, spacing: 4) {
                        Text(np.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color(hex: "#F5F6F8"))
                            .lineLimit(1)
                        Text([np.artist, np.album].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: "#9398A1"))
                            .lineLimit(1)
                        if np.duration > 0 { MediaProgress(np: np).padding(.top, 4) }
                        controls(np).padding(.top, 2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.leading, 108)
                .padding(.trailing, 18)
            } else {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Nada tocando agora.")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Spotify ou Música aparecem aqui quando tocarem.")
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: "#9398A1"))
                    }
                    Spacer()
                    PrimaryButton("Abrir Spotify") { media.openPlayer() }
                }
                .padding(.leading, 118)
                .padding(.trailing, 18)
            }
        }
    }

    private var cover: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06))
            if let img = media.artwork {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 26))
                    .foregroundColor(Color(hex: "#5F646D"))
            }
        }
        .frame(width: 92, height: 92)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture { media.openPlayer() }
        .help("Abrir \(media.nowPlaying?.player.rawValue ?? "player")")
    }

    private func controls(_ np: NowPlaying) -> some View {
        HStack(spacing: 18) {
            MediaButton(icon: "backward.fill", size: 13) { media.previous() }
            MediaButton(icon: np.isPlaying ? "pause.fill" : "play.fill", size: 18) { media.playPause() }
            MediaButton(icon: "forward.fill", size: 13) { media.next() }
            Spacer()
            Text(np.player.rawValue)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Color(hex: "#5F646D"))
        }
    }
}

/// Barra de progresso; só atualiza (1x/s) enquanto toca e a aba está aberta.
/// Clicar ou arrastar na barra pula para aquele ponto da música.
struct MediaProgress: View {
    let np: NowPlaying
    @State private var arrasto: Double? = nil   // fração 0…1 enquanto arrasta
    @State private var hover = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: np.isPlaying ? 1 : 3600)) { ctx in
            let real = np.currentPosition(at: ctx.date)
            let pos = arrasto.map { $0 * np.duration } ?? real
            let ativo = hover || arrasto != nil
            VStack(spacing: 3) {
                GeometryReader { g in
                    let frac = CGFloat(np.duration > 0 ? min(1, pos / np.duration) : 0)
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.10))
                            .frame(height: ativo ? 5 : 3)
                        Capsule().fill(Color(hex: "#E8E9EC"))
                            .frame(width: g.size.width * frac, height: ativo ? 5 : 3)
                        if ativo {
                            Circle().fill(Color.white)
                                .frame(width: 10, height: 10)
                                .offset(x: g.size.width * frac - 5)
                        }
                    }
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { v in arrasto = Double(min(max(0, v.location.x / g.size.width), 1)) }
                            .onEnded { v in
                                let f = Double(min(max(0, v.location.x / g.size.width), 1))
                                MediaService.shared.seek(to: f * np.duration)
                                arrasto = nil
                            }
                    )
                    .onHover { hover = $0 }
                }
                .frame(height: 12)
                .animation(.easeOut(duration: 0.12), value: ativo)
                HStack {
                    Text(Self.fmt(pos))
                    Spacer()
                    Text("-" + Self.fmt(max(0, np.duration - pos)))
                }
                .font(.system(size: 10).monospacedDigit())
                .foregroundColor(Color(hex: "#6B7079"))
            }
        }
    }

    static func fmt(_ s: Double) -> String {
        let t = Int(s.rounded())
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}

struct MediaButton: View {
    let icon: String
    let size: CGFloat
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size))
                .foregroundColor(hover ? .white : Color(hex: "#C5C8CD"))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: - Capa na ilha fechada (sinal do canto)

struct CapaCompacta: View {
    @ObservedObject private var media = MediaService.shared

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08))
            if let img = media.artwork {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "music.note").font(.system(size: 11)).foregroundColor(Color(hex: "#8E939C"))
            }
        }
        .frame(width: 24, height: 24)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .frame(width: 28, height: 28)
    }
}
