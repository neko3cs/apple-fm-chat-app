# 詳細設計

## モジュール・クラス構成

```mermaid
classDiagram
    class ChatView {
        SwiftUI View
        +body
    }
    class ChatViewModel {
        <<@Observable>>
        +messages: [ChatMessage]
        +inputText: String
        +availabilityState: ModelAvailabilityState
        +isResponding: Bool
        +send()
        +startNewConversation()
    }
    class ChatService {
        -session: LanguageModelSession
        +checkAvailability() ModelAvailabilityState
        +streamResponse(to: String) AsyncSequence
        +resetSession()
    }
    class ChatMessage {
        +id: UUID
        +role: Role
        +text: String
        +isStreaming: Bool
    }
    class ModelAvailabilityState {
        <<enum>>
        available
        unavailable(reason)
    }

    ChatView --> ChatViewModel : 保持・観測
    ChatViewModel --> ChatService : 処理を委譲
    ChatViewModel --> ChatMessage : 保持
    ChatService --> ChatMessage
    ChatService ..> ModelAvailabilityState : 生成
```

- `ChatView`: SwiftUI の View。メッセージ一覧・入力欄・送信ボタン・新しい会話ボタン・利用不可バナーの表示のみを担当する。Foundation Models の型を直接扱わない。
- `ChatViewModel`: 画面の状態（メッセージ配列、入力文字列、応答中フラグ、利用可否）を保持し、`ChatView` から呼ばれる操作を `ChatService` に委譲する。
- `ChatService`: `LanguageModelSession` / `SystemLanguageModel` をラップし、フレームワーク固有の型・エラーをこの層に閉じ込める。View・ViewModel からはフレームワークの型が見えない。
- `ChatMessage`: 画面表示用のメッセージデータ。永続化はしない。

## 主要な処理の流れ

最もリスクが高い「送信〜ストリーミング表示〜コンテキスト上限到達時のリカバリ」を中心に記載する。

```mermaid
sequenceDiagram
    actor User
    participant View as ChatView
    participant VM as ChatViewModel
    participant Svc as ChatService
    participant Session as LanguageModelSession

    User->>View: 本文を入力し送信
    View->>VM: send()
    VM->>Svc: streamResponse(to: prompt)
    Svc->>Session: streamResponse(to:)
    loop 部分応答を受信するたび
        Session-->>Svc: 部分テキスト
        Svc-->>VM: 部分テキストを通知
        VM-->>View: メッセージ本文を更新（再描画）
    end

    alt 正常終了
        Session-->>Svc: 最終テキスト
        Svc-->>VM: 応答完了
        VM-->>View: isResponding = false
    else コンテキスト上限超過（LanguageModelError.contextSizeExceeded）
        Session-->>Svc: エラー送出
        Svc->>Svc: 新しい LanguageModelSession を生成（resetSession 相当）
        Svc-->>VM: セッションを再作成したことを通知
        VM-->>View: 会話は継続可能な状態のまま（クラッシュ・停止なし）
    else その他のエラー
        Session-->>Svc: エラー送出
        Svc-->>VM: エラーを通知
        VM-->>View: 再送信可能な状態に戻す
    end
```

- コンテキスト上限超過時に前の文脈をどこまで新セッションへ引き継ぐか（先頭・末尾の `Transcript.Entry` を種にするか、何も引き継がず空の状態から始めるか）は TBD。要件上は「新しいセッションで会話を続けられる」ことが必須で、引き継ぎの精度は問わない。

## 状態遷移

`ChatViewModel` が持つ「モデル利用可否」と「応答生成」の状態遷移。起きてはいけない遷移（利用不可のまま送信できてしまう等）を明示する。

```mermaid
stateDiagram-v2
    [*] --> Checking: 画面表示
    Checking --> Unavailable: SystemLanguageModel.availability が unavailable
    Checking --> Idle: availability が available

    Unavailable --> Idle: 再チェックで available になる（TBD: 自動再チェックの要否・タイミング）

    Idle --> Responding: 送信（入力欄が空でない）
    Responding --> Idle: 応答完了
    Responding --> Idle: コンテキスト上限超過 → 新セッションへ切替（エラー表示にはしない）
    Responding --> Idle: その他のエラー

    Idle --> Idle: 新しい会話ボタン（セッション・メッセージ一覧をリセット）

    note right of Unavailable
        この状態では送信ボタン・入力欄を無効化する
        （Unavailable のまま送信できる遷移は作らない）
    end note
```

## データアクセス設計

永続化を行わないため、データアクセス層は存在しない。`ChatViewModel` が保持する `[ChatMessage]` 配列と `ChatService` が保持する `LanguageModelSession` は、いずれもアプリプロセスのメモリ上にのみ存在し、アプリ終了・「新しい会話」操作のいずれかで破棄される。
