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
        +availabilityState: ModelAvailabilityState?
        +isResponding: Bool
        +needsNewConversation: Bool
        +errorMessage: String?
        -generation: Int
        +start()
        +send()
        +startNewConversation()
    }
    class ChatService {
        -session: LanguageModelSession
        -streamingTask: Task~Void, Never~?
        +checkAvailability() ModelAvailabilityState
        +streamResponse(to: String) AsyncThrowingStream~String, Error~
        +resetSession(seedTranscriptData: Data?) SessionRestoreOutcome
        +currentTranscriptData() Data?
    }
    class ConversationStore {
        -container: ModelContainer
        +init(inMemory: Bool)
        +loadTranscriptData() Data?
        +save(transcriptData: Data)
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

- `ChatView`: SwiftUI の View。メッセージ一覧・入力欄・送信ボタン・新しい会話ボタン・利用不可バナーの表示のみを担当する。Foundation Models・SwiftData いずれの型も直接扱わない。メッセージ一覧は `LazyVStack` ではなく `VStack` にし、メッセージ数・最新メッセージ本文の変化ごとに最新行へ明示的にスクロールする（`LazyVStack` + `defaultScrollAnchor(.bottom, for: .sizeChanges)` では、長文メッセージ追加時に最新行へ追従しないことを実機で確認したため）。
- `ChatViewModel`: 画面の状態（メッセージ配列、入力文字列、応答中フラグ、利用可否、`needsNewConversation`、`errorMessage`）を保持し、`ChatView` から呼ばれる操作を `ChatService`（モデル呼び出し）と `ConversationStore`（永続化）に委譲する。両者を橋渡しする役割を持つ。`availabilityState` が `nil` の間は起動時の復元・確認中（`Restoring`/`Checking`）を表し、送信できない。`needsNewConversation` はコンテキスト上限到達時に `true` になり、「新しい会話」が実行されるまで送信操作を塞ぐ。バナーに出す文言も ViewModel が決め、View は表示するだけにする。
- `ChatViewModel.generation`: 「新しい会話」を実行するたびに加算する世代番号。`send()` は開始時の世代を覚えておき、終了時に世代が変わっていれば（＝途中で新しい会話に切り替わっていれば）画面更新も永続化も行わない。キャンセル直前にストリームが正常終了した場合でも、新しい空のセッションの `Transcript` を保存してしまわないための防御。
- `ChatService`: `LanguageModelSession` / `SystemLanguageModel` / `Transcript` をラップし、フレームワーク固有の型・エラーをこの層に閉じ込める。`Transcript` のエンコード・デコードも ChatService の責務とし、外部には `Data` としてのみ公開する。エラーも `LanguageModelError` を外に出さず、`ChatServiceError`（`contextSizeExceeded` / `generationFailed`）に変換して返す。コンテキスト超過は `LanguageModelError.contextSizeExceeded` を `contextSizeExceeded` に変換する（macOS 27 ターゲットのアプリではこちらが届くことを実機で確認済み。ガードレール判定などその他の `LanguageModelError` は `generationFailed`）。キャンセル時は `CancellationError` をそのまま返す。進行中のストリーミングを `streamingTask` として保持し、`resetSession` は呼ばれるたびに（起動時の復元・「新しい会話」操作のいずれからでも）まず `streamingTask` を `cancel()` してから待ち合わせ、新しい `LanguageModelSession` を生成する。結果は `SessionRestoreOutcome`（`restored([ChatMessage])` / `empty` / `decodeFailed`）で返す。引き継ぐデータを省略すると空の会話から始める。
- `ConversationStore`: SwiftData の `ModelContainer` を自身で生成・保持し、`PersistedConversation.transcriptData`（`Data`）をそのまま読み書きする。`Transcript` 型は一切知らない（Foundation Models フレームワークに依存しない）。View・ViewModel・ChatService のいずれからも SwiftData の型が見えないようにする。`init(inMemory: true)` はプレビュー用。永続ストアを開けなかった場合はメモリ上のストアで起動を続ける（永続化なしで動作する）。
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
    VM->>Store: loadTranscriptData()
    Store-->>VM: Data?（中身は解釈しない）
    VM->>Svc: resetSession(seedTranscriptData: Data?)
    alt デコード成功（保存データがある）
        Svc->>Svc: Data を Transcript にデコードしセッションを復元
        Svc-->>VM: 復元済みセッションの利用可否と表示用メッセージ一覧
        VM-->>View: 保存済みメッセージ一覧を表示
    else 保存データが無い、またはデコードに失敗
        Svc-->>VM: 空の会話の利用可否（デコード失敗フラグ付き）
        VM->>Store: （デコード失敗時のみ）clear()
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
        VM->>Svc: currentTranscriptData()
        Svc-->>VM: Data（中身は解釈しない）
        VM->>Store: save(transcriptData: Data)
        VM-->>View: isResponding = false
    else コンテキスト上限超過（LanguageModelError.contextSizeExceeded）
        Session-->>Svc: エラー送出
        Svc-->>VM: コンテキスト上限超過を通知（セッションはまだ切り替えない）
        VM-->>View: needsNewConversation = true<br/>状態バナーで「新しい会話」を促す。送信は不可のまま
    else その他のエラー
        Session-->>Svc: エラー送出
        Svc-->>VM: エラーを通知
        VM-->>View: 再送信可能な状態に戻す
    end
```

- 永続化（`Store.save`）は、正常終了で応答が確定するたびに行う。ストリーミングの部分テキストごとには保存しない（書き込み頻度を抑えるため）。コンテキスト上限超過時は超過した発言への応答が得られていないため保存しない（超過前の状態のまま残る）。
- コンテキスト上限超過時に前の文脈を新しい会話へ引き継ぐことはしない（下記「新しい会話」の項を参照）。
- 応答を得られなかった発言（コンテキスト上限超過・その他のエラーの両方）は、メッセージ一覧から外して入力欄に戻す。「新しい会話」は入力欄を消さないため、上限超過後もそのまま新しい会話で再送できる。
- その他のエラー時は `Transcript` が更新されていないため保存しない。

### 新しい会話（通常時／応答生成中／コンテキスト上限到達時で共通）

```mermaid
sequenceDiagram
    actor User
    participant View as ChatView
    participant VM as ChatViewModel
    participant Svc as ChatService
    participant Store as ConversationStore

    User->>View: 「新しい会話」を押す
    View->>VM: startNewConversation()
    VM->>Svc: resetSession(seedTranscriptData: nil)
    opt ストリーミング中だった場合
        Svc->>Svc: streamingTask を cancel() し、完了を待ち合わせる
        Note over Svc: ループは Task.isCancelled を検知した時点で<br/>直ちに抜け、以降 VM への部分テキスト通知は行わない
    end
    Svc->>Svc: 新しい LanguageModelSession を生成
    Svc-->>VM: 空のセッションを返す
    VM->>Store: clear()
    VM-->>View: messages を空に、isResponding / needsNewConversation を false に
```

- この操作は `Idle`・`Responding`・コンテキスト上限到達（`needsNewConversation == true`）のいずれの状態からも同じ手順で実行できる。「進行中のストリーミング `Task` を必ずキャンセルしてから新しいセッションを生成する」のは `resetSession` 内部の不変条件とし、呼び出し元が状態を意識する必要はない。

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
    Responding --> NeedsNewConversation: コンテキスト上限超過（needsNewConversation = true、送信は不可のまま）
    Responding --> Idle: その他のエラー

    Idle --> Idle: 新しい会話ボタン（ストリーミングは無いのでキャンセル不要）
    Responding --> Idle: 新しい会話ボタン（進行中のストリーミング Task をキャンセルしてからリセット）
    NeedsNewConversation --> Idle: 新しい会話ボタン（この状態からの唯一の脱出経路）

    note right of NeedsNewConversation
        この状態では送信ボタン・入力欄を無効化し、
        状態バナーで「新しい会話」を促す
    end note
    note right of Unavailable
        この状態では送信ボタン・入力欄を無効化する
        （Unavailable のまま送信できる遷移は作らない）
    end note
```

## データアクセス設計

- 永続化には SwiftData を使い、`ConversationStore` が唯一のアクセス窓口となる。`ChatViewModel` は `ModelContext` を直接扱わない。`ConversationStore` 自身も `Transcript` 型を知らず、`Data` の読み書きに徹する（Foundation Models フレームワークに依存しない）。
- スキーマは `PersistedConversation`（`@Model`）1 種類のみ。`transcriptData: Data` は ChatService が `Transcript` を `JSONEncoder` 等でエンコードした結果をそのまま渡したもので、会話が進むほど肥大化しうるため `@Attribute(.externalStorage)` を付与し、SQLite 本体とは別領域に保存する。
- レコードは常に 0 件または 1 件（複数会話を一覧管理しない、要件のスコープ外）。書き込みは追加ではなく、既存レコードを探して更新、無ければ新規作成する upsert とする。
- 「新しい会話」操作時は、レコードを更新（空の `Transcript` 相当を保存）するのではなく削除する。次回起動時に迷わず「保存済みの会話が無い」と判定できるようにするため。
- `Data` から `Transcript` へのデコードは ChatService の責務。デコード失敗（OS・モデルのバージョン変化による表現の非互換などを想定、ADR-004 参照）時は例外を投げず「空の会話」として扱い、ChatViewModel 経由で `ConversationStore.clear()` を呼んで壊れたレコードを削除し、次回以降も同じ失敗を繰り返さないようにする。
- `ChatViewModel` が保持する画面表示用の `[ChatMessage]` 配列はアプリプロセスのメモリ上にのみ存在し、SwiftData には保存しない。起動時に表示する `[ChatMessage]` は ChatService が `Transcript` から組み立てて ChatViewModel に返す（ChatViewModel 自身は `Transcript.Entry` を解釈しない）。
