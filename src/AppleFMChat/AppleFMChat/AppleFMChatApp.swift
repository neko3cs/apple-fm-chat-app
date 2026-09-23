//
//  AppleFMChatApp.swift
//  AppleFMChat
//
//  Created by ねこさん on 2026/09/23.
//

import SwiftUI

@main
struct AppleFMChatApp: App {
    // SwiftData の生成は ConversationStore に閉じ込める
    @State private var viewModel = ChatViewModel(service: ChatService(), store: ConversationStore())

    var body: some Scene {
        WindowGroup {
            ChatView(viewModel: viewModel)
        }
    }
}
