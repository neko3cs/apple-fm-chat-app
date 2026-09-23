# PLAN.md

## Goals
- Build a minimal, working macOS chat app using the Foundation Models framework (on-device LLM), per `docs/requirements.md`.

## Issues
- The app is implemented, and requirements 1–3 and 5–7 were verified on-device by Claude. Requirement 4 (unavailable-reason banner) and the SwiftUI previews in the Xcode canvas are unverified, and the user has not run their own on-device check yet.

## Deliverables
- An Xcode project at `src/AppleFMChat/AppleFMChat.xcodeproj` (macOS 27 target, SwiftUI, SwiftData).
- Swift implementation matching `docs/design.md`'s module breakdown: `ChatView`, `ChatViewModel`, `ChatService`, `ConversationStore`, `ChatMessage`, `PersistedConversation`.
- A build that succeeds via `xcodebuild`/Xcode, with a working SwiftUI preview for the chat screen.

## Usecases
- The user runs the app locally on their own Apple Silicon Mac (macOS 27, Apple Intelligence enabled) to verify the chat flow end-to-end.

## Success Conditions
- The Xcode project exists in the repo and builds for macOS with zero compiler warnings (see `AGENTS.md` Commands).
- All 7 requirements in `docs/requirements.md`'s 機能要件 table are implemented and manually verified by the user on-device.
- The SwiftUI preview for the chat screen renders without crashing.

## Failure Conditions
- A literal token-count constant appears anywhere in code instead of reading `SystemLanguageModel.contextSize` — the context-size limit must never be hardcoded (`docs/architecture.md` invariant).
- `ChatView` or `ChatViewModel` references Foundation Models types (`LanguageModelSession`, `Transcript`, `SystemLanguageModel`) or SwiftData types (`ModelContext`) directly — only `ChatService` and `ConversationStore` may.
- Multi-conversation management (listing/switching between saved conversations) gets implemented — explicitly out of scope.
- Context-size overflow is auto-recovered silently instead of surfacing the `NeedsNewConversation` state that blocks sending until the user presses "新しい会話".
- `docs/design.md` is left stale after an implementation detail diverges from it.
- `project.pbxproj` has any `SDKROOT` other than `macosx`.
- Handling for the deprecated `LanguageModelSession.GenerationError` gets added back — with a macOS 27 deployment target only `LanguageModelError` arrives.

## Next Actions
- User runs the app from Xcode on "My Mac" and walks the on-device checklist: streaming, follow-up questions, relaunch restore, "新しい会話" during streaming, overflow banner (send ~2600 digits a few times).
- User checks requirement 4: turn Apple Intelligence off in System Settings, launch, and confirm the reason banner; then open `ChatView.swift` and check the three previews in the canvas.
- User confirms the choices made during implementation: banner wording, failed prompts returning to the input field, persistence failures not shown. Any spec-level changes go to GitHub Issues, not here.
