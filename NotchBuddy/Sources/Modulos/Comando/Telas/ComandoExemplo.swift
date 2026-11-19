import SwiftUI

// Cenas do comando universal para o modo de capturas (`Crew --capturas <pasta> --so comando`).
// A lista é montada pelo serviço de verdade (mesma ordenação do uso), mas com dados de exemplo
// no lugar das fontes: nenhum arquivo do Hugo é procurado, nada é traduzido, nada é gravado.

@MainActor
enum ComandoExemplo {
    struct Cena {
        let arquivo: String
        let altura: CGFloat
        let preparar: @MainActor () -> Void
    }

    /// O painel sobre um fundo de mesa, como aparece por cima de outro app.
    static var palco: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.20, green: 0.24, blue: 0.38), Color(red: 0.10, green: 0.11, blue: 0.16)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            PainelComandoView().frame(width: PainelComando.largura).padding(.top, 28)
        }
    }

    private static let apps: [AppDoComando] = [
        ("/System/Applications/Calculator.app", "Calculadora", "Calculator"),
        ("/System/Applications/Calendar.app", "Calendário", "Calendar"),
        ("/System/Applications/Utilities/Screenshot.app", "Captura de Tela", "Screenshot"),
        ("/System/Applications/Notes.app", "Notas", "Notes"),
        ("/System/Applications/Mail.app", "Mail", "Mail"),
        ("/System/Applications/Maps.app", "Mapas", "Maps"),
        ("/System/Applications/Music.app", "Música", "Music"),
        ("/System/Applications/System Settings.app", "Ajustes do Sistema", "System Settings"),
        ("/System/Applications/Utilities/Terminal.app", "Terminal", "Terminal"),
    ].map { AppDoComando(caminho: $0.0, nome: $0.1, nomeNoDisco: $0.2) }

    private static func arquivo(_ caminho: String, pasta: Bool = false, dias: Double) -> ArquivoAchado {
        ArquivoAchado(caminho: NSHomeDirectory() + caminho, nome: (caminho as NSString).lastPathComponent,
                      ehPasta: pasta, ultimoUso: Date().addingTimeInterval(-dias * 86400))
    }

    static var cenas: [Cena] {
        let s = ComandoServico.shared
        return [
            Cena(arquivo: "45a_comando_vazio.png", altura: 440) {
                NavegadorServico.shared.exemploParaCaptura()
                s.exemploParaCaptura(texto: "", apps: apps)
            },
            Cena(arquivo: "45b_comando_apps_arquivos.png", altura: 700) {
                s.exemploParaCaptura(texto: "ca", apps: apps, arquivos: [
                    arquivo("/Documents/Contratos/Carta proposta 2026.pdf", dias: 1),
                    arquivo("/Documents/Cardápio novembro.xlsx", dias: 3),
                    arquivo("/Pictures/Capturas", pasta: true, dias: 9),
                ])
            },
            Cena(arquivo: "45c_comando_conta.png", altura: 260) {
                s.exemploParaCaptura(texto: "1.234,56 + 10%", apps: apps)
            },
            Cena(arquivo: "45d_comando_unidade.png", altura: 260) {
                s.exemploParaCaptura(texto: "10 km em milhas", apps: apps)
            },
            Cena(arquivo: "45e_comando_traducao.png", altura: 380) {
                s.exemploParaCaptura(texto: "traduz o relatório fica pronto amanhã cedo", apps: apps,
                                     traducao: .pronto(texto: "The report will be ready early tomorrow", de: "pt", para: "en"))
            },
            Cena(arquivo: "45f_comando_traducao_sem_pacote.png", altura: 380) {
                s.exemploParaCaptura(texto: "bom dia em japonês", apps: apps, traducao: .semPacote(de: "pt", para: "ja"))
            },
            Cena(arquivo: "45g_comando_endereco.png", altura: 380) {
                s.exemploParaCaptura(texto: "github.com", apps: apps)
            },
            Cena(arquivo: "45h_comando_crew.png", altura: 560) {
                s.exemploParaCaptura(texto: "crew", apps: apps)
            },
            Cena(arquivo: "45i_comando_pergunta.png", altura: 320) {
                s.exemploParaCaptura(texto: "por que o build de ontem falhou?", apps: apps)
            },
            Cena(arquivo: "45j_comando_nota.png", altura: 380) {
                s.exemploParaCaptura(texto: "nota ligar para o contador", apps: apps)
            },
        ]
    }
}
