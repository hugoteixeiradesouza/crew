import Foundation
import SwiftUI

// MARK: - Chat

enum ChatRole { case user, assistant }

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: ChatRole
    let content: String
}
