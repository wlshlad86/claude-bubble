# Claude Bubble

A little always-on floating assistant bubble for macOS, **powered by Claude Code (Opus 4.8)**.

A bouncy bubble sits in the top-left corner of the screen, always on top, on every
Space. Click it (or press **⌃⌥⌘B** from anywhere) to expand a chat box; messages
stream in live, and follow-up questions keep the conversation going.

Native Swift + SwiftUI, no Xcode project, tiny memory footprint.

## Features

- **Floating bubble** — always-on-top, all Spaces, no Dock icon. Click to toggle.
- **Global hotkey** — summon/dismiss from any app (Carbon hotkey, no accessibility
  permission needed). Default ⌃⌥⌘B; **reassign it** from the in-app settings popover.
- **Streaming answers** — `--output-format stream-json --include-partial-messages`;
  text appears token-by-token as Claude writes it.
- **Markdown rendering** — answers render with bold/italic, headings, bullet lists,
  inline code, and **fenced code blocks in a monospace box with a one-click copy**.
- **Follow-up conversations** — first turn uses `--session-id <uuid>`, later turns
  `--resume <uuid>`, so context carries across messages.
- **Persistent history** — the conversation is saved to disk and restored on the
  next launch (Application Support/ClaudeBubble/conversation.json). The pencil icon
  (⌘N) starts a fresh chat.
- **Remembers its spot** — drag the bubble anywhere; it reopens where you left it.
- **Stop button** — interrupt a running answer mid-stream; **Esc** collapses the panel.
- **Real error messages** — if Claude Code isn't logged in or the CLI is missing,
  the bubble says so instead of silently showing "(no response)". The CLI path is
  auto-detected across common locations (override with `CLAUDE_PATH`).

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

## Status: v0.3

Done: floating bubble, click-to-ask, **streaming answers**, **follow-up
conversations**, **global hotkey (configurable)**, **markdown + code-block rendering
with copy**, **persistent history across restarts**, **drag-to-reposition memory**,
stop-streaming, Esc-to-collapse, ⌘N new chat, friendly error surfacing, CLI
auto-detection, thinking animation, launch-at-login.

Launch-at-login is installed as a LaunchAgent:
`~/Library/LaunchAgents/com.pensaer.claudebubble.plist` (RunAtLoad, KeepAlive off).
- Relaunch now: `launchctl kickstart gui/$(id -u)/com.pensaer.claudebubble`
- Stop auto-start: `launchctl bootout gui/$(id -u)/com.pensaer.claudebubble`
- After editing the plist: `bootout` then `launchctl bootstrap gui/$(id -u) <plist>`

Next ideas (not built yet):
- Multi-line input (Shift+Enter for newlines) via a custom NSTextView.
- Syntax highlighting inside code blocks.
- Resizable / detachable chat panel.
- Model picker and a token/cost indicator.
