import Foundation
import Observation

// チャット画面の状態を持ち、ChatService と ConversationStore を橋渡しする
@Observable
final class ChatViewModel {
    private(set) var messages: [ChatMessage]
    var inputText = ""
    // nil は起動時の復元・利用可否の確認中
    private(set) var availabilityState: ModelAvailabilityState?
    private(set) var isResponding = false
    private(set) var needsNewConversation: Bool
    private(set) var errorMessage: String?

    private let service: ChatService
    private let store: ConversationStore
    // 「新しい会話」ごとに加算。古い送信処理が新しい会話を書き換えないための目印
    private var generation = 0

    init(
        service: ChatService,
        store: ConversationStore,
        messages: [ChatMessage] = [],
        needsNewConversation: Bool = false
    ) {
        self.service = service
        self.store = store
        self.messages = messages
        self.needsNewConversation = needsNewConversation
    }

    var isInputEnabled: Bool {
        availabilityState == .available && !isResponding && !needsNewConversation
    }

    var canSend: Bool {
        isInputEnabled && !trimmedInput.isEmpty
    }

    var bannerMessage: String? {
        if needsNewConversation {
            return "会話が長くなったため、これ以上続けられません。「新しい会話」を押して始め直してください。"
        }
        if let errorMessage {
            return errorMessage
        }
        switch availabilityState {
        case .unavailable(.deviceNotEligible):
            return "この Mac は Apple Intelligence に対応していないため利用できません。"
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Apple Intelligence が無効です。システム設定で有効にしてください。"
        case .unavailable(.modelNotReady):
            return "モデルを準備中です（ダウンロード中など）。しばらく待ってから再度お試しください。"
        case .unavailable(.other):
            return "原因を特定できませんが、現在モデルを利用できません。"
        case .available, nil:
            return nil
        }
    }

    // 起動時に保存済みの会話を復元し、利用可否を確認する
    func start() async {
        let outcome = await service.resetSession(seedTranscriptData: store.loadTranscriptData())
        switch outcome {
        case .restored(let restored):
            messages = restored
        case .empty:
            break
        case .decodeFailed:
            // 読めないデータは消して、次回以降も同じ失敗を繰り返さない
            store.clear()
        }
        availabilityState = service.checkAvailability()
    }

    func send() async {
        guard canSend else { return }
        let prompt = trimmedInput
        let sendingGeneration = generation
        let userMessage = ChatMessage(role: .user, text: prompt)
        let reply = ChatMessage(role: .assistant, text: "", isStreaming: true)

        inputText = ""
        errorMessage = nil
        messages += [userMessage, reply]
        isResponding = true
        defer {
            if sendingGeneration == generation {
                isResponding = false
            }
        }

        do {
            for try await partial in service.streamResponse(to: prompt) {
                updateMessage(id: reply.id) { $0.text = partial }
            }
            guard sendingGeneration == generation else { return }
            updateMessage(id: reply.id) { $0.isStreaming = false }
            if let data = service.currentTranscriptData() {
                store.save(transcriptData: data)
            }
        } catch is CancellationError {
            // 「新しい会話」による中断。画面の片付けは startNewConversation が行う
        } catch {
            guard sendingGeneration == generation else { return }
            // 応答を得られなかった発言は一覧から外し、入力欄に戻して再送しやすくする
            messages.removeAll { $0.id == userMessage.id || $0.id == reply.id }
            inputText = prompt
            if error as? ChatServiceError == .contextSizeExceeded {
                needsNewConversation = true
            } else {
                errorMessage = "返答の取得に失敗しました。もう一度送信してください。"
            }
        }
    }

    // 入力欄の下書きは残す（上限超過後もそのまま再送できるように）
    func startNewConversation() async {
        generation += 1
        _ = await service.resetSession(seedTranscriptData: nil)
        store.clear()
        messages = []
        isResponding = false
        needsNewConversation = false
        errorMessage = nil
    }

    private var trimmedInput: String {
        inputText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func updateMessage(id: UUID, _ change: (inout ChatMessage) -> Void) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        change(&messages[index])
    }
}
