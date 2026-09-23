import Foundation
import SwiftData

// SwiftData への保存を担当する。Transcript は知らず Data だけを扱う。レコードは常に 0〜1 件
final class ConversationStore {
    private let container: ModelContainer

    private var context: ModelContext {
        container.mainContext
    }

    init(inMemory: Bool = false) {
        let schema = Schema([PersistedConversation.self])
        do {
            container = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)]
            )
        } catch {
            // 保存領域を開けなくても起動は続ける（永続化なしで動作する）
            container = try! ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
            )
        }
    }

    func loadTranscriptData() -> Data? {
        fetchConversation()?.transcriptData
    }

    func save(transcriptData: Data) {
        if let conversation = fetchConversation() {
            conversation.transcriptData = transcriptData
            conversation.updatedAt = .now
        } else {
            context.insert(PersistedConversation(transcriptData: transcriptData))
        }
        // 保存失敗時の画面表示は仕様 TBD。会話自体は続けられるため握りつぶす
        try? context.save()
    }

    func clear() {
        try? context.delete(model: PersistedConversation.self)
        try? context.save()
    }

    private func fetchConversation() -> PersistedConversation? {
        var descriptor = FetchDescriptor<PersistedConversation>()
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
