# Claude Bubble

A little always-on floating assistant bubble for macOS, **powered by Claude Code (Opus 4.8)**.

A bouncy bubble sits in the top-left corner of the screen, always on top, on every
Space. Click it (or press **⌃⌥⌘B** from anywhere) to expand a chat box; messages
stream in live, and follow-up questions keep the conversation going.

Native Swift + SwiftUI, no Xcode project, tiny memory footprint.

## Features

- **Floating bubble** — always-on-top, all Spaces, no Dock icon. Click to toggle.
- **Global hotkey ⌃⌥⌘B** — summon/dismiss from any app (Carbon hotkey, no
  accessibility permission needed).
- **Streaming answers** — `--output-format stream-json --include-partial-messages`;
  text appears token-by-token as Claude writes it.
- **Follow-up conversations** — first turn uses `--session-id <uuid>`, later turns
  `--resume <uuid>`, so context carries across messages. The pencil icon starts a
  new chat (fresh session).

## Requirements

- macOS 12+ with the Swift toolchain (Xcode Command Line Tools: `xcode-select --install`)
- [Claude Code](https://claude.com/claude-code) installed and logged in — the app
  expects the CLI at `~/.local/bin/claude` (see `CLAUDE_PATH` in `main.swift` to change)

## Build & run

```bash
git clone https://github.com/wlshlad86/claude-bubble && cd claude-bubble
bash build.sh          # compiles main.swift -> ClaudeBubble.app (ad-hoc signed)
open ClaudeBubble.app  # launches the bubble (top-left of screen)
```

Quit it: `pkill -f ClaudeBubble`

## How it works

- `main.swift` — one file. A borderless, always-on-top `NSPanel` hosts a SwiftUI
  `BubbleView`. Collapsed = 72×72 (just the bubble); clicking expands the panel to
  show a text field + scrollable response.
- The brain is `claude -p "<your question>"`, run on a background thread. The
  subprocess env sets `PATH`, `HOME`, `USER`, `LOGNAME` so it can read the OAuth
  creds from the macOS Keychain (service `Claude Code-credentials`) — required, or
  `claude` reports "Not logged in".
- `LSUIElement` is true, so no Dock icon / menu-bar clutter.

## Status: v0.2

Done: floating bubble, click-to-ask, **streaming answers**, **follow-up
conversations**, **global hotkey ⌃⌥⌘B**, launch-at-login.

Launch-at-login is installed as a LaunchAgent:
`~/Library/LaunchAgents/com.pensaer.claudebubble.plist` (RunAtLoad, KeepAlive off).
- Relaunch now: `launchctl kickstart gui/$(id -u)/com.pensaer.claudebubble`
- Stop auto-start: `launchctl bootout gui/$(id -u)/com.pensaer.claudebubble`
- After editing the plist: `bootout` then `launchctl bootstrap gui/$(id -u) <plist>`

Next ideas (not built yet):
- Refined idle/bounce + thinking animation.
- Persist conversations across app restarts (currently in-memory only).
- Drag-to-reposition that remembers its spot.
- Configurable hotkey + markdown rendering of answers.
