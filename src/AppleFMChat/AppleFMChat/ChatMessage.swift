import Foundation

// 画面表示用のメッセージ。永続化されるのは Transcript のみで、これは保存しない
struct ChatMessage: Identifiable, Equatable {
    enum Role {
        case user
        case assistant
    }

    let id = UUID()
    let role: Role
    var text: String
    var isStreaming = false
}
