# Claude Bubble

**Floating Mac bubble for Claude Code — hotkey, stream answers, copy them out.**

[![Download latest](https://img.shields.io/github/v/release/wlshlad86/claude-bubble?label=download&style=for-the-badge)](https://github.com/wlshlad86/claude-bubble/releases/latest)
[![macOS 12+](https://img.shields.io/badge/macOS-12%2B-black?style=for-the-badge)](https://github.com/wlshlad86/claude-bubble/releases/latest)

A bouncy always-on-top bubble for every Space. Press **⌃⌥⌘B** (rebindable) from any
app, ask Claude Code, watch the answer stream in, then select + **⌘C** or one-click
copy the full reply. Native Swift + SwiftUI, one file, ~127 KB download.

**Needs [Claude Code](https://claude.com/claude-code) installed and logged in.** First
open is ad-hoc signed: **right-click → Open**. Promo copy for X / HN / Reddit lives in
[`PROMO.md`](PROMO.md).

## Features

- **Floating bubble** — always-on-top, all Spaces, no Dock icon. Click to toggle.
- **Global hotkey** — summon/dismiss from any app (Carbon hotkey, no accessibility
  permission needed). Default ⌃⌥⌘B; **reassign it** from the in-app settings popover.
- **Streaming answers** — `--output-format stream-json --include-partial-messages`;
  text appears token-by-token as Claude writes it.
- **Markdown rendering** — answers render with bold/italic, headings, bullet lists,
  inline code, and **fenced code blocks in a monospace box with a one-click copy**.
  Full answer text is **selectable** (⌘C) and each Claude reply has a **copy-full-answer** button.
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

## Download (easiest)

**[Download the latest release](https://github.com/wlshlad86/claude-bubble/releases/latest)**  
→ grab `ClaudeBubble-v*-macos.zip` → unzip → open `ClaudeBubble.app`.

### Requirements (download)

- macOS 12+
- [Claude Code](https://claude.com/claude-code) installed and logged in  
  (the bubble is a thin UI over the `claude` CLI — it does not ship Claude)

### First open (Gatekeeper)

The app is **ad-hoc signed** (not Developer ID / notarized yet). On first launch macOS
may say it can't be opened. Fix:

1. **Right-click** `ClaudeBubble.app` → **Open** → **Open**, or
2. System Settings → Privacy & Security → **Open Anyway**

Quit: `pkill -x ClaudeBubble` (or force-quit from Activity Monitor)

## Build from source

Needs the Swift toolchain (Xcode Command Line Tools: `xcode-select --install`).

```bash
git clone https://github.com/wlshlad86/claude-bubble && cd claude-bubble
bash build.sh          # compiles main.swift -> ClaudeBubble.app (ad-hoc signed)
open ClaudeBubble.app  # launches the bubble (top-left of screen)
```

## How it works

- `main.swift` — one file. A borderless, always-on-top `NSPanel` hosts a SwiftUI
  `BubbleView`. Collapsed = 72×72 (just the bubble); clicking expands the panel to
  show a text field + scrollable response.
- The brain is `claude -p "<your question>"`, run on a background thread. The
  subprocess env sets `PATH`, `HOME`, `USER`, `LOGNAME` so it can read the OAuth
  creds from the macOS Keychain (service `Claude Code-credentials`) — required, or
  `claude` reports "Not logged in".
- `LSUIElement` is true, so no Dock icon / menu-bar clutter.

## Status: v0.4

Done: floating bubble, click-to-ask, **streaming answers**, **follow-up
conversations**, **global hotkey (configurable)**, **markdown + code-block rendering
with copy**, **selectable prose + whole-answer copy**, **persistent history across
restarts**, **drag-to-reposition memory**, stop-streaming, Esc-to-collapse, ⌘N new
chat, friendly error surfacing, CLI auto-detection, thinking animation, launch-at-login.

**v0.4** — Claude answers are fully selectable (⌘C) and each reply has a one-click
copy-full-answer control (in addition to the existing code-block copy button).

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
