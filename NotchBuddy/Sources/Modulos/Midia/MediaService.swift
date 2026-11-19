import SwiftUI
import AppKit
import Combine

// MARK: - O que está tocando (Spotify e Música do Mac)
// Escuta os avisos que os próprios players publicam no sistema a cada troca de faixa
// ou play/pause — sem polling, nada roda com a ilha escondida. Controles e capa vão
// por AppleScript (o macOS pede permissão na primeira vez).

struct NowPlaying: Equatable {
    enum Player: String { case spotify = "Spotify", music = "Música" }

    var player: Player
    var title: String
    var artist: String
    var album: String
    var isPlaying: Bool
    var duration: Double          // segundos (0 = desconhecida)
    var position: Double          // segundos, no instante `positionAt`
    var positionAt: Date
    var artworkURL: URL?

    /// Posição agora, andando sozinha enquanto toca.
    func currentPosition(at now: Date = .now) -> Double {
        let p = isPlaying ? position + now.timeIntervalSince(positionAt) : position
        return duration > 0 ? min(max(0, p), duration) : max(0, p)
    }
}

/// Conteúdo do aviso do player, já copiado para tipos simples.
struct PlayerUpdate: Sendable {
    let state: String, title: String, artist: String, album: String
    let durationMs: Double
    let position: Double?

    init(_ info: [AnyHashable: Any]?) {
        let i = info ?? [:]
        state = i["Player State"] as? String ?? ""
        title = i["Name"] as? String ?? ""
        artist = i["Artist"] as? String ?? ""
        album = i["Album"] as? String ?? ""
        durationMs = (i["Duration"] as? Double) ?? (i["Total Time"] as? Double) ?? 0
        position = i["Playback Position"] as? Double
    }
}

@MainActor
final class MediaService: ObservableObject {
    static let shared = MediaService()

    @Published private(set) var nowPlaying: NowPlaying? {
        didSet {
            // Começou a tocar: a ilha aparece (compacta) e não some enquanto tocar
            guard nowPlaying?.isPlaying != oldValue?.isPlaying else { return }
            AppState.shared.syncMode()
            if nowPlaying?.isPlaying == true {
                // Capa no canto da ilha fechada, no lugar dos mini-Homies
                Arbitro.shared.publicar(Sinal(id: "midia", lugar: .canto, prioridade: .atividade,
                                              conteudo: AnyView(CapaCompacta())))
                NotificationCenter.default.post(name: .hookReveal, object: nil)
            } else {
                Arbitro.shared.retirar("midia")
            }
        }
    }
    @Published private(set) var artwork: NSImage?

    private var artworkFor: URL?

    private init() {}

    func start() {
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(forName: Notification.Name("com.spotify.client.PlaybackStateChanged"),
                        object: nil, queue: .main) { note in
            let u = PlayerUpdate(note.userInfo)
            MainActor.assumeIsolated { MediaService.shared.handle(.spotify, u) }
        }
        dnc.addObserver(forName: Notification.Name("com.apple.Music.playerInfo"),
                        object: nil, queue: .main) { note in
            let u = PlayerUpdate(note.userInfo)
            MainActor.assumeIsolated { MediaService.shared.handle(.music, u) }
        }
        // Já tocava antes de o Crew abrir? Pergunta uma vez.
        if isRunning(.spotify) || isRunning(.music) { refresh() }
    }

    /// Só para o modo de captura: define o que está tocando sem player de verdade.
    func simular(_ np: NowPlaying?, capa: NSImage?) {
        nowPlaying = np
        artwork = capa
    }

    // MARK: Avisos dos players

    private func handle(_ player: NowPlaying.Player, _ u: PlayerUpdate) {
        let state = u.state
        if state == "Stopped" {
            if nowPlaying?.player == player { nowPlaying = nil; artwork = nil }
            return
        }
        let playing = state == "Playing"
        // Outro player pausou enquanto este toca: ignora
        if !playing, let cur = nowPlaying, cur.player != player, cur.isPlaying { return }

        let durMs = u.durationMs
        let pos = u.position
        var np = NowPlaying(player: player,
                            title: u.title,
                            artist: u.artist,
                            album: u.album,
                            isPlaying: playing,
                            duration: durMs / 1000,
                            position: pos ?? 0,
                            positionAt: .now,
                            artworkURL: nil)
        // Mesma faixa (só play/pause): mantém capa e, se o aviso não trouxe posição, a posição
        if let cur = nowPlaying, cur.player == player, cur.title == np.title, cur.artist == np.artist {
            np.artworkURL = cur.artworkURL
            if pos == nil { np.position = cur.currentPosition(); np.positionAt = .now }
            nowPlaying = np
        } else {
            nowPlaying = np
            artwork = nil
            refresh()   // capa e posição exata da faixa nova
        }
    }

    // MARK: Leitura completa (capa, posição)

    /// Pergunta ao player o estado completo. Usado ao abrir o app, em faixa nova e ao abrir a aba.
    func refresh() {
        let player: NowPlaying.Player = nowPlaying?.player ?? (isRunning(.spotify) ? .spotify : .music)
        guard isRunning(player) else { nowPlaying = nil; artwork = nil; return }
        let script: String
        switch player {
        case .spotify:
            script = """
            tell application "Spotify"
                set s to (player state as string)
                if s is "stopped" then return "stopped"
                set t to current track
                return s & "\\n" & (name of t) & "\\n" & (artist of t) & "\\n" & (album of t) & "\\n" & ((duration of t) / 1000) & "\\n" & (player position) & "\\n" & (artwork url of t)
            end tell
            """
        case .music:
            script = """
            tell application "Music"
                set s to (player state as string)
                if s is "stopped" then return "stopped"
                set t to current track
                return s & "\\n" & (name of t) & "\\n" & (artist of t) & "\\n" & (album of t) & "\\n" & (duration of t) & "\\n" & (player position) & "\\n"
            end tell
            """
        }
        Task {
            guard let out = await Self.osascript(script) else { return }
            let lines = out.components(separatedBy: "\n")
            if lines.first == "stopped" || lines.count < 6 {
                if nowPlaying?.player == player { nowPlaying = nil; artwork = nil }
                return
            }
            let num = { (s: String) in Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0 }
            let np = NowPlaying(player: player, title: lines[1], artist: lines[2], album: lines[3],
                                isPlaying: lines[0] == "playing", duration: num(lines[4]),
                                position: num(lines[5]), positionAt: .now,
                                artworkURL: lines.count > 6 ? URL(string: lines[6]) : nil)
            nowPlaying = np
            loadArtwork(np.artworkURL)
        }
    }

    private func loadArtwork(_ url: URL?) {
        guard let url, url != artworkFor else { return }
        artworkFor = url
        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let img = NSImage(data: data), artworkFor == url else { return }
            artwork = img
        }
    }

    // MARK: Controles

    func playPause() { control("playpause") }
    func next()      { control("next track") }
    func previous()  { control("previous track") }

    /// Pula para um ponto da faixa (segundos). Atualiza a barra na hora; o player confirma depois.
    func seek(to seconds: Double) {
        guard var np = nowPlaying, np.duration > 0 else { return }
        let alvo = min(max(0, seconds), np.duration - 0.5)
        np.position = alvo
        np.positionAt = .now
        nowPlaying = np
        control("set player position to \(String(format: "%.1f", alvo))")
    }

    private func control(_ cmd: String) {
        guard let player = nowPlaying?.player ?? (isRunning(.spotify) ? .spotify : nil) else { return }
        let app = player == .spotify ? "Spotify" : "Music"
        Task {
            _ = await Self.osascript("tell application \"\(app)\" to \(cmd)")
            // O player avisa sozinho; o refresh garante posição certa se o aviso atrasar
            try? await Task.sleep(for: .milliseconds(400))
            refresh()
        }
    }

    func openPlayer() {
        let id = nowPlaying?.player == .music ? "com.apple.Music" : "com.spotify.client"
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }

    // MARK: Apoio

    private func isRunning(_ p: NowPlaying.Player) -> Bool {
        let id = p == .spotify ? "com.spotify.client" : "com.apple.Music"
        return NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == id }
    }

    /// Roda AppleScript fora da main. nil = erro (ex.: permissão negada).
    private static func osascript(_ source: String) async -> String? {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                p.arguments = ["-e", source]
                let out = Pipe()
                p.standardOutput = out
                p.standardError = Pipe()
                do { try p.run() } catch { cont.resume(returning: nil); return }
                let data = out.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                guard p.terminationStatus == 0 else { cont.resume(returning: nil); return }
                cont.resume(returning: String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
    }
}
