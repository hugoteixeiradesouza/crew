import SwiftUI
import AppKit
import Quartz
import UniformTypeIdentifiers

// Arquivo aberto de dentro do Crew (caminho na conversa, dois cliques na árvore de arquivos)
// aparece aqui mesmo, por cima da janela — imagem, PDF, vídeo, texto, o que o macOS souber
// mostrar. Nada de janela avulsa de outro app; ir para o app padrão é um botão, por escolha.

extension Notification.Name {
    /// App do Crew: mostra um arquivo por cima da janela (`object`: URL de arquivo).
    static let verArquivoNoCrew = Notification.Name("crew.verArquivoNoCrew")
}

@MainActor
enum VisorCrew {
    /// Abre o arquivo dentro da janela do Crew. Pasta não tem o que mostrar: vai para o Finder.
    static func abrir(_ url: URL) {
        var pasta: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &pasta) else {
            NSSound.beep()
            return
        }
        if pasta.boolValue {
            NSWorkspace.shared.open(url)
        } else {
            NotificationCenter.default.post(name: .verArquivoNoCrew, object: url)
        }
    }
}

/// Põe o visor por cima da janela quando alguém pede para ver um arquivo.
struct VisorDeArquivos: ViewModifier {
    @State private var aberto: URL?

    func body(content: Content) -> some View {
        content
            .overlay {
                if let url = aberto {
                    VisorArquivo(url: url) { withAnimation(.easeOut(duration: 0.15)) { aberto = nil } }
                        .id(url)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .verArquivoNoCrew)) { n in
                guard let url = n.object as? URL else { return }
                withAnimation(.easeOut(duration: 0.18)) { aberto = url }
            }
    }
}

/// O arquivo por cima da janela. Clique fora, o X ou Esc fecha.
struct VisorArquivo: View {
    let url: URL
    let fechar: () -> Void

    @State private var vigiaEsc: Any?

    var body: some View {
        ZStack {
            Color.black.opacity(0.82)
                .onTapGesture(perform: fechar)
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(url.lastPathComponent)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Tema.texto)
                            .lineLimit(1).truncationMode(.middle)
                        Text((url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(Tema.texto3)
                            .lineLimit(1).truncationMode(.head)
                    }
                    Spacer(minLength: 8)
                    BotaoIcone(icone: "folder", ajuda: "Mostrar no Finder", lado: 26) {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                    BotaoIcone(icone: "arrow.up.forward.app", ajuda: "Abrir no app padrão", lado: 26) {
                        NSWorkspace.shared.open(url)
                        fechar()
                    }
                    BotaoIcone(icone: "xmark", ajuda: "Fechar (Esc)", lado: 26, acao: fechar)
                }
                .padding(.leading, 16).padding(.trailing, 10)
                .frame(height: 46)
                Fio()
                // Imagem é desenhada aqui mesmo; o resto (PDF, vídeo, texto) pela prévia do macOS.
                if let tipo = UTType(filenameExtension: url.pathExtension), tipo.conforms(to: .image),
                   let img = NSImage(contentsOf: url) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(14)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    PreviaDoSistema(url: url)
                }
            }
            .background(Tema.painel)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Tema.bordaForte))
            .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
            .padding(.horizontal, 36)
            .padding(.top, 44)      // os botões da janela ficam livres
            .padding(.bottom, 30)
        }
        .transition(.opacity)
        .onAppear {
            guard vigiaEsc == nil else { return }
            let fechar = fechar
            vigiaEsc = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { evento in
                guard evento.keyCode == 53 else { return evento }
                MainActor.assumeIsolated { fechar() }
                return nil
            }
        }
        .onDisappear {
            if let v = vigiaEsc { NSEvent.removeMonitor(v) }
            vigiaEsc = nil
        }
    }
}

/// A prévia do macOS (a mesma do espaço no Finder), dentro da janela.
private struct PreviaDoSistema: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let v = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        v.autostarts = true
        v.previewItem = url as NSURL
        return v
    }

    func updateNSView(_ v: QLPreviewView, context: Context) {
        if (v.previewItem?.previewItemURL ?? nil) != url { v.previewItem = url as NSURL }
    }

    static func dismantleNSView(_ v: QLPreviewView, coordinator: ()) { v.close() }
}
