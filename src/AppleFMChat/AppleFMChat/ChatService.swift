import Foundation
import FoundationModels

// ChatService が外に返すエラー。LanguageModelError などフレームワークの型は外に出さない
enum ChatServiceError: Error, Equatable {
    case contextSizeExceeded
    case generationFailed
}

enum SessionRestoreOutcome {
    case restored([ChatMessage])
    case empty
    case decodeFailed
}

// Foundation Models とのやり取りを担当する。Transcript のエンコード・デコードもここで行う
final class ChatService {
    private var session = LanguageModelSession()
    private var streamingTask: Task<Void, Never>?

    func checkAvailability() -> ModelAvailabilityState {
        switch SystemLanguageModel.default.availability {
        case .available:
            .available
        case .unavailable(.deviceNotEligible):
            .unavailable(.deviceNotEligible)
        case .unavailable(.appleIntelligenceNotEnabled):
            .unavailable(.appleIntelligenceNotEnabled)
        case .unavailable(.modelNotReady):
            .unavailable(.modelNotReady)
        case .unavailable:
            .unavailable(.other)
        }
    }

    // 生成途中までの全文を順に流す。キャンセル時は CancellationError で終わる
    func streamResponse(to prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let session = session
            let task = Task {
                do {
                    for try await snapshot in session.streamResponse(to: prompt) {
                        // キャンセル後の部分テキストは通知しない
                        guard !Task.isCancelled else { break }
                        continuation.yield(snapshot.content)
                    }
                    if Task.isCancelled {
                        continuation.finish(throwing: CancellationError())
                    } else {
                        continuation.finish()
                    }
                } catch {
                    continuation.finish(throwing: Self.convert(error))
                }
            }
            streamingTask = task
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // 進行中のストリーミングを必ず止めてからセッションを差し替える
    func resetSession(seedTranscriptData: Data?) async -> SessionRestoreOutcome {
        if let streamingTask {
            streamingTask.cancel()
            await streamingTask.value
        }
        streamingTask = nil

        guard let seedTranscriptData else {
            session = LanguageModelSession()
            return .empty
        }
        guard let transcript = try? JSONDecoder().decode(Transcript.self, from: seedTranscriptData) else {
            session = LanguageModelSession()
            return .decodeFailed
        }
        session = LanguageModelSession(transcript: transcript)
        return .restored(Self.messages(from: transcript))
    }

    func currentTranscriptData() -> Data? {
        try? JSONEncoder().encode(session.transcript)
    }

    private static func convert(_ error: Error) -> Error {
        if error is CancellationError {
            return error
        }
        // macOS 27 ターゲットでは LanguageModelError が届く（旧 GenerationError は deprecated）
        if let modelError = error as? LanguageModelError, case .contextSizeExceeded = modelError {
            return ChatServiceError.contextSizeExceeded
        }
        return ChatServiceError.generationFailed
    }

    private static func messages(from transcript: Transcript) -> [ChatMessage] {
        transcript.compactMap { entry -> ChatMessage? in
            switch entry {
            case .prompt(let prompt):
                ChatMessage(role: .user, text: text(of: prompt.segments))
            case .response(let response):
                ChatMessage(role: .assistant, text: text(of: response.segments))
            default:
                nil
            }
        }
    }

    private static func text(of segments: [Transcript.Segment]) -> String {
        segments.compactMap { segment -> String? in
            guard case .text(let textSegment) = segment else { return nil }
            return textSegment.content
        }
        .joined()
    }
}
