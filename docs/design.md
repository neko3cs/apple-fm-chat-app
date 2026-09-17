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
        +resetSession(seedTranscript: Transcript?)
        +currentTranscript() Transcript
    }
    class ConversationStore {
        -modelContext: ModelContext
        +loadTranscript() Transcript?
        +save(transcript: Transcript)
        +clear()
    }
    class PersistedConversation {
        <<@Model>>
        +id: UUID
        +transcriptData: Data
        +updatedAt: Date
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
    ChatViewModel --> ConversationStore : 処理を委譲
    ChatViewModel --> ChatMessage : 保持
    ChatService --> ChatMessage
    ChatService ..> ModelAvailabilityState : 生成
    ConversationStore --> PersistedConversation : 読み書き
```

- `ChatView`: SwiftUI の View。メッセージ一覧・入力欄・送信ボタン・新しい会話ボタン・利用不可バナーの表示のみを担当する。Foundation Models・SwiftData いずれの型も直接扱わない。
- `ChatViewModel`: 画面の状態（メッセージ配列、入力文字列、応答中フラグ、利用可否）を保持し、`ChatView` から呼ばれる操作を `ChatService`（モデル呼び出し）と `ConversationStore`（永続化）に委譲する。両者を橋渡しする役割を持つ。
- `ChatService`: `LanguageModelSession` / `SystemLanguageModel` をラップし、フレームワーク固有の型・エラーをこの層に閉じ込める。`resetSession` は起動時の復元・コンテキスト超過時のいずれからも呼ばれ、引き継ぐ `Transcript` を省略すると空の会話から始める。
- `ConversationStore`: SwiftData（`ModelContext`）をラップし、`PersistedConversation` の読み書きを `Transcript` の受け渡しに変換する。View・ViewModel から SwiftData の型が見えないようにする。
- `PersistedConversation`: SwiftData の `@Model`。永続化する行は常に 1 件（`ConversationStore` が upsert する）。
- `ChatMessage`: 画面表示用のメッセージデータ。SwiftData には保存しない（永続化されるのは `Transcript` のみ）。

## 主要な処理の流れ

最もリスクが高い「起動時の会話復元」「送信〜ストリーミング表示〜コンテキスト上限到達時のリカバリ〜永続化」を中心に記載する。

### 起動時の会話復元

```mermaid
sequenceDiagram
    participant View as ChatView
    participant VM as ChatViewModel
    participant Store as ConversationStore
    participant Svc as ChatService

    View->>VM: 画面表示
    VM->>Store: loadTranscript()
    alt 保存済みの会話がある
        Store-->>VM: Transcript を返す
        VM->>Svc: resetSession(seedTranscript: Transcript)
        Svc-->>VM: 復元済みセッションで利用可否を返す
        VM-->>View: 保存済みメッセージ一覧を表示
    else 保存済みの会話が無い、またはデコードに失敗
        Store-->>VM: nil（失敗時は保存データを破棄）
        VM->>Svc: resetSession(seedTranscript: nil)
        Svc-->>VM: 空の会話で利用可否を返す
        VM-->>View: 空のメッセージ一覧を表示
    end
```

### メッセージ送信〜ストリーミング〜リカバリ〜永続化

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
        VM->>Store: save(transcript: Svc.currentTranscript())
        VM-->>View: isResponding = false
    else コンテキスト上限超過（LanguageModelError.contextSizeExceeded）
        Session-->>Svc: エラー送出
        Svc->>Svc: 新しい LanguageModelSession を生成（resetSession 相当）
        Svc-->>VM: セッションを再作成したことを通知
        VM->>Store: save(transcript: Svc.currentTranscript())
        VM-->>View: 会話は継続可能な状態のまま（クラッシュ・停止なし）
    else その他のエラー
        Session-->>Svc: エラー送出
        Svc-->>VM: エラーを通知
        VM-->>View: 再送信可能な状態に戻す
    end
```

- コンテキスト上限超過時に前の文脈をどこまで新セッションへ引き継ぐか（先頭・末尾の `Transcript.Entry` を種にするか、何も引き継がず空の状態から始めるか）は TBD。要件上は「新しいセッションで会話を続けられる」ことが必須で、引き継ぎの精度は問わない。
- 永続化（`Store.save`）は、応答が確定するたび（正常終了・コンテキスト超過リカバリ後）に行う。ストリーミングの部分テキストごとには保存しない（書き込み頻度を抑えるため）。
- その他のエラー時は `Transcript` が更新されていないため保存しない。
- 「新しい会話」ボタン押下時は `ChatViewModel.startNewConversation()` が `ChatService.resetSession(seedTranscript: nil)` と `ConversationStore.clear()` を呼び、セッション・永続化データの両方を空にする。

## 状態遷移

`ChatViewModel` が持つ「モデル利用可否」と「応答生成」の状態遷移。起きてはいけない遷移（利用不可のまま送信できてしまう等）を明示する。

```mermaid
stateDiagram-v2
    [*] --> Restoring: 画面表示
    Restoring --> Checking: ConversationStore.loadTranscript() 完了（成功・失敗いずれも）
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

- 永続化には SwiftData を使い、`ConversationStore` が唯一のアクセス窓口となる。`ChatViewModel` は `ModelContext` を直接扱わない。
- スキーマは `PersistedConversation`（`@Model`）1 種類のみ。`transcriptData` は `Transcript` を `JSONEncoder` 等でエンコードしたバイナリで、会話が進むほど肥大化しうるため `@Attribute(.externalStorage)` を付与し、SQLite 本体とは別領域に保存する。
- レコードは常に 0 件または 1 件（複数会話を一覧管理しない、要件のスコープ外）。書き込みは追加ではなく、既存レコードを探して更新、無ければ新規作成する upsert とする。
- 「新しい会話」操作時は、レコードを更新（空の `Transcript` 相当を保存）するのではなく削除する。次回起動時に迷わず「保存済みの会話が無い」と判定できるようにするため。
- 読み込み（`loadTranscript()`）でのデコード失敗（OS・モデルのバージョン変化による表現の非互換などを想定、ADR-004 参照）は例外を投げず `nil` を返し、呼び出し側で「空の会話から始める」ものとして扱う。あわせて、デコードできなかった既存レコードは削除し、次回以降も同じ失敗を繰り返さないようにする。
- `ChatViewModel` が保持する画面表示用の `[ChatMessage]` 配列はアプリプロセスのメモリ上にのみ存在し、SwiftData には保存しない。起動時は `Transcript` から `[ChatMessage]` を組み立てて表示に使う。
