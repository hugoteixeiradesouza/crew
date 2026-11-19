import SwiftUI

// MARK: - Aba de módulo: o registro diz qual

struct AbaDoModulo: View {
    @ObservedObject var state: AppState
    @ObservedObject private var registro = Registro.shared

    var body: some View {
        if let m = registro.modulo(state.moduloAberto), registro.estaLigado(m.id) {
            m.aba().id(m.id)
        }
    }
}

// MARK: - Dispatch view content by IslandView

struct IslandViewContent: View {
    let view: IslandView
    @ObservedObject var state: AppState

    var body: some View {
        switch view {
        case .overview:  OverviewView(state: state)
        case .empty:     EmptyStateView(state: state)
        case .approval:  ApprovalView(state: state)
        case .question:  QuestionView(state: state)
        case .sugestao:  SugestaoTaskView()
        case .error:     ErrorView(state: state)
        case .finished:  FinishedView(state: state)
        case .confused:  ConfusedView()
        case .upload:    UploadView(state: state)
        case .uploading: UploadingView(state: state)
        case .choose:    ChooseView(state: state)
        case .mail:      MailView(state: state)
        case .prompt:    PromptView(state: state)
        case .searching: SearchingView(state: state)
        case .result:    ResultView(state: state)
        case .note:      NoteView(state: state)
        case .settings:  SettingsIslandView(state: state)
        case .media:     MediaView()
        case .modulo:    AbaDoModulo(state: state)
        case .modulos:   GradeModulos(state: state)
        case .greeting:  EmptyView()  // GreetingCanvasView overlaid in IslandRootView
        }
    }
}
