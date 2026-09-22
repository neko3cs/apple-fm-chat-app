# PLAN.md

## Goals
- Build a minimal, working macOS chat app using the Foundation Models framework (on-device LLM), per `docs/requirements.md`.

## Issues
- No working implementation exists yet — only the design docs (`docs/*.md`) are complete and merged to `main`.

## Deliverables
- An Xcode project (macOS App target, SwiftUI, SwiftData storage) created inside this repo root. Not yet created.
- Swift implementation matching `docs/design.md`'s module breakdown: `ChatView`, `ChatViewModel`, `ChatService`, `ConversationStore`, `ChatMessage`, `PersistedConversation`.
- A build that succeeds via `xcodebuild`/Xcode, with a working SwiftUI preview for the chat screen.

## Usecases
- The user runs the app locally on their own Apple Silicon Mac (macOS 27, Apple Intelligence enabled) to verify the chat flow end-to-end.

## Success Conditions
- The Xcode project exists in the repo and builds without errors.
- All 7 requirements in `docs/requirements.md`'s 機能要件 table are implemented and manually verified by the user on-device.
- The SwiftUI preview for the chat screen renders without crashing.

## Failure Conditions
- A literal token-count constant appears anywhere in code instead of reading `SystemLanguageModel.contextSize` — the context-size limit must never be hardcoded (`docs/architecture.md` invariant).
- `ChatView` or `ChatViewModel` references Foundation Models types (`LanguageModelSession`, `Transcript`, `SystemLanguageModel`) or SwiftData types (`ModelContext`) directly — only `ChatService` and `ConversationStore` may.
- Multi-conversation management (listing/switching between saved conversations) gets implemented — explicitly out of scope.
- Context-size overflow is auto-recovered silently instead of surfacing the `NeedsNewConversation` state that blocks sending until the user presses "新しい会話".
- `docs/design.md` is left stale after an implementation detail diverges from it.

## Next Actions
- User creates the Xcode project (macOS App, SwiftUI, Swift, SwiftData storage checkbox, saved at the repo root, git-repo-creation unchecked).
- Once the project exists, implement the non-persistence happy path first (`ChatView` / `ChatViewModel` / `ChatService`), then add `ConversationStore` / SwiftData persistence.
