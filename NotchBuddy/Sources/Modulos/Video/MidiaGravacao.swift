import AVFoundation

// Leva uma gravação de tela para dentro de um projeto de vídeo. O Crew grava o som do Mac e o
// microfone em trilhas separadas do MP4, e o navegador (a prévia) e o Remotion só tocam a
// primeira: sem juntar, a voz ou o som do Mac sumiria na edição. Aqui as trilhas de som viram uma
// só; a imagem é copiada como está, sem recodificar.

enum MidiaGravacao {
    /// Copia `origem` para `destino`. Devolve quantas trilhas de som foram juntadas (0 = cópia
    /// simples: a gravação tinha no máximo uma, ou juntar falhou e foi como estava).
    static func levar(_ origem: URL, para destino: URL) async throws -> Int {
        let fm = FileManager.default
        let asset = AVURLAsset(url: origem)
        let sons = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
        if sons.count > 1, (try? await juntar(asset, sons: sons, em: destino)) != nil { return sons.count }
        try? fm.removeItem(at: destino)
        // No APFS a cópia não ocupa espaço.
        try fm.copyItem(at: origem, to: destino)
        return 0
    }

    private struct SemExportador: Error {}

    private static func juntar(_ asset: AVURLAsset, sons: [AVAssetTrack], em destino: URL) async throws {
        let fm = FileManager.default
        let mistura = fm.temporaryDirectory.appendingPathComponent("crew-som-\(UUID().uuidString).m4a")
        defer { try? fm.removeItem(at: mistura) }

        // 1) Só o som: o exportador mistura as trilhas numa.
        let soSom = AVMutableComposition()
        for som in sons {
            let faixa = try await som.load(.timeRange)
            guard let nova = soSom.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
            try nova.insertTimeRange(faixa, of: som, at: faixa.start)
        }
        guard let e1 = AVAssetExportSession(asset: soSom, presetName: AVAssetExportPresetAppleM4A) else { throw SemExportador() }
        try await e1.export(to: mistura, as: .m4a)

        // 2) A imagem original (sem recodificar) com o som misturado.
        let junto = AVMutableComposition()
        for video in try await asset.loadTracks(withMediaType: .video) {
            let faixa = try await video.load(.timeRange)
            guard let nova = junto.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
            try nova.insertTimeRange(faixa, of: video, at: faixa.start)
            nova.preferredTransform = try await video.load(.preferredTransform)
        }
        let misturado = AVURLAsset(url: mistura)
        if let som = try await misturado.loadTracks(withMediaType: .audio).first,
           let nova = junto.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            let faixa = try await som.load(.timeRange)
            try nova.insertTimeRange(faixa, of: som, at: faixa.start)
        }
        guard let e2 = AVAssetExportSession(asset: junto, presetName: AVAssetExportPresetPassthrough) else { throw SemExportador() }
        try? fm.removeItem(at: destino)
        try await e2.export(to: destino, as: destino.pathExtension.lowercased() == "mov" ? .mov : .mp4)
    }
}
