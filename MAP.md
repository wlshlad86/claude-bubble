# MAP — what this project is

**Claude Bubble** — a borderless, always-on-top macOS bubble (SwiftUI in an `NSPanel`)
that runs the `claude` CLI on a background thread and streams the answer back into a
chat panel. `LSUIElement` → no Dock icon. Native Swift, no Xcode project.

## Files
- `main.swift` — the entire app. Sections (in order):
  - **CLI discovery** — `resolveClaudePath()` probes common install locations;
    `bubbleSupportDir()` is the on-disk home for persisted state.
  - **Persistence model** — `StoredMessage` / `PersistedState` (Codable JSON).
  - **`AppState`** — the brain. Owns messages, the streaming `Process`, session id,
    save/load, error surfacing (`friendlyError`), and `ask` / `stop` / `newChat`.
  - **Markdown** — `MarkdownParser` splits prose vs fenced code; `MarkdownText`,
    `ProseText`, `CodeBlock` render it. `MessageRow` picks plain text (you) vs markdown (Claude).
  - **`BubbleView`** — the bubble + chat panel + settings popover.
  - **`HotkeyManager`** — Carbon global hotkey; persists keycode+modifiers; records new combos.
  - **`AppDelegate`** — builds the panel, wires `expanded` → `position()`, drag-position
    memory (`NSWindow.didMoveNotification`), and registers the hotkey.
- `build.sh` — compiles `main.swift` → `ClaudeBubble.app`, writes Info.plist, ad-hoc signs.
- `README.md` — user-facing overview + status.
- `bubble.log` — runtime log (gitignored, never commit).
- `ClaudeBubble.app/` — build artifact (gitignored).

## Build / run / test
```bash
bash build.sh           # main.swift -> ClaudeBubble.app (ad-hoc signed)
open ClaudeBubble.app    # launches the bubble (restores last position)
pkill -f ClaudeBubble    # quit
```
There is no automated test suite — verification is: it compiles, launches, the bubble
appears, the hotkey toggles it, a question streams an answer, markdown/code render, and
the conversation is still there after quit+relaunch.

## Key runtime facts
- The CLI subprocess needs `PATH/HOME/USER/LOGNAME` set so it can read OAuth creds from
  the Keychain (service `Claude Code-credentials`) — otherwise it reports "Not logged in".
- First turn: `--session-id <uuid>`. Later turns: `--resume <uuid>`. Streaming via
  `--output-format stream-json --verbose --include-partial-messages`; only
  `content_block_delta` → `text_delta` events carry visible text.
- Persisted conversation: `~/Library/Application Support/ClaudeBubble/conversation.json`.
- Hotkey + bubble position: `UserDefaults` (`hotkeyKeyCode`, `hotkeyModifiers`, `bubbleX`, `bubbleY`).
- Repo: `https://github.com/wlshlad86/claude-bubble` (public). Bundle id `com.pensaer.claudebubble`.
