import SwiftUI

/// Bloco da home: o que está tocando; clique pausa/retoma.
struct MidiaBloco: View {
    @ObservedObject private var media = MediaService.shared

    var body: some View {
        if let np = media.nowPlaying {
            BlocoPainel(titulo: np.title, legenda: np.isPlaying ? np.artist : "pausado",
                        ajuda: np.isPlaying ? "Pausar" : "Tocar", acao: { media.playPause() }) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.08))
                    if let img = media.artwork {
                        Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                    }
                    Image(systemName: np.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 9, weight: .bold)).foregroundColor(.white)
                        .shadow(radius: 2)
                }
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }
        } else {
            BlocoPainel(titulo: "Nada tocando", legenda: "Spotify ou Música", ajuda: "Abrir a aba de música",
                        acao: { AppState.shared.view = .media }) {
                Image(systemName: "music.note").font(.system(size: 13)).foregroundColor(Color(hex: "#8E939C"))
            }
        }
    }
}
