import Foundation
import SwiftData

// 永続化する単一の会話。Transcript をエンコードした Data をそのまま持つ
@Model
final class PersistedConversation {
    var id: UUID
    // 会話が伸びるほど大きくなるため SQLite 本体とは別領域に置く
    @Attribute(.externalStorage) var transcriptData: Data
    var updatedAt: Date

    init(transcriptData: Data) {
        id = UUID()
        self.transcriptData = transcriptData
        updatedAt = .now
    }
}
