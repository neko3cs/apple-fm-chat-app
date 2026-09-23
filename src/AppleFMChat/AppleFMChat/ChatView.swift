import SwiftUI

// チャット画面。表示だけを担当し、処理と文言は ChatViewModel に任せる
struct ChatView: View {
    @Bindable var viewModel: ChatViewModel

    var body: some View {
        VStack(spacing: 0) {
            if let message = viewModel.bannerMessage {
                StatusBanner(message: message)
            }
            messageList
            Divider()
            inputBar
        }
        .frame(minWidth: 480, minHeight: 400)
        .toolbar {
            Button("新しい会話", systemImage: "square.and.pencil") {
                Task { await viewModel.startNewConversation() }
            }
        }
        .task { await viewModel.start() }
    }

    // 会話はコンテキストサイズで長さが頭打ちになるため、Lazy にせず高さを正確に測る
    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(viewModel.messages) { message in
                        MessageBubble(message: message)
                    }
                }
                .padding()
            }
            .defaultScrollAnchor(.bottom)
            // 追加時・ストリーミングで本文が伸びた時に最新行を表示する
            .onChange(of: viewModel.messages.count) { scrollToLatest(proxy) }
            .onChange(of: viewModel.messages.last?.text) { scrollToLatest(proxy) }
        }
    }

    private func scrollToLatest(_ proxy: ScrollViewProxy) {
        guard let last = viewModel.messages.last else { return }
        proxy.scrollTo(last.id, anchor: .bottom)
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("メッセージを入力", text: $viewModel.inputText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...5)
                .disabled(!viewModel.isInputEnabled)
                .onSubmit { Task { await viewModel.send() } }
            if viewModel.isResponding {
                ProgressView()
                    .controlSize(.small)
            }
            Button("送信") {
                Task { await viewModel.send() }
            }
            .disabled(!viewModel.canSend)
        }
        .padding()
    }
}

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 40)
            }
            content
                .padding(10)
                .background(background, in: .rect(cornerRadius: 12))
            if message.role == .assistant {
                Spacer(minLength: 40)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if message.isStreaming && message.text.isEmpty {
            ProgressView()
                .controlSize(.small)
        } else {
            Text(message.text)
                .textSelection(.enabled)
        }
    }

    private var background: Color {
        message.role == .user ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.12)
    }
}

private struct StatusBanner: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.yellow.opacity(0.2))
    }
}

private let previewMessages = [
    ChatMessage(role: .user, text: "こんにちは。今日の東京の天気に合う服装を教えて。"),
    ChatMessage(role: .assistant, text: "天気の情報は取得できませんが、季節に合わせた一般的な服装ならご提案できます。今の季節を教えてもらえますか？"),
    ChatMessage(role: .user, text: "秋です。"),
    ChatMessage(role: .assistant, text: "", isStreaming: true),
]

#Preview("会話中") {
    ChatView(viewModel: ChatViewModel(
        service: ChatService(),
        store: ConversationStore(inMemory: true),
        messages: previewMessages
    ))
}

#Preview("コンテキスト上限") {
    ChatView(viewModel: ChatViewModel(
        service: ChatService(),
        store: ConversationStore(inMemory: true),
        messages: Array(previewMessages.dropLast()),
        needsNewConversation: true
    ))
}

#Preview("利用不可バナー") {
    StatusBanner(message: "Apple Intelligence が無効です。システム設定で有効にしてください。")
}
