# Claude Bubble — launch / promo kit

Use this when posting a new version. Always link **Latest release** (not a fixed tag), so people land on the current zip:

**https://github.com/wlshlad86/claude-bubble/releases/latest**

Direct v0.4 zip (for this cut only):

**https://github.com/wlshlad86/claude-bubble/releases/download/v0.4/ClaudeBubble-v0.4-macos.zip**

---

## One-liner (default)

> Floating Mac bubble for Claude Code — hotkey, stream answers, copy them out. Download the zip (~127 KB). Needs Claude Code logged in; first open: right-click → Open.

---

## X / Twitter (short)

```
Floating Mac bubble for Claude Code.

Hotkey → ask → stream → copy the answer out.
~127 KB zip. Needs Claude Code logged in.
First open: right-click → Open (ad-hoc signed).

https://github.com/wlshlad86/claude-bubble/releases/latest
```

Attach a 15–30s screen recording if you have one (hotkey → ask → copy).

---

## Hacker News — Show HN

**Title:**
```
Show HN: Claude Bubble – floating Mac UI for Claude Code (~127 KB)
```

**Body:**
```
I built a tiny always-on floating bubble for macOS that sits on top of every Space and talks to the Claude Code CLI you already use.

- Global hotkey (default ⌃⌥⌘B; rebindable)
- Live streaming answers
- Markdown + code blocks + copy (select text or one-click full answer)
- Conversation history survives restarts
- Single Swift file, no Xcode project, ~127 KB download

Requirements: macOS 12+, Claude Code installed and logged in.
The app is ad-hoc signed (not notarized yet) — first open: right-click → Open.

Download: https://github.com/wlshlad86/claude-bubble/releases/latest
Source: https://github.com/wlshlad86/claude-bubble

Happy to hear what would make this something you’d reach for instead of the terminal.
```

Post at: https://news.ycombinator.com/submit

---

## Reddit

### r/ClaudeAI / r/ClaudeCode (if present)

**Title:**
```
Claude Bubble – floating Mac hotkey UI over the Claude Code CLI (free, open source)
```

**Body:**
```
If you already use Claude Code on a Mac and want answers without leaving the app you’re in:

- Floating always-on-top bubble
- Hotkey to summon
- Streams replies live
- Select + copy, or one-click copy full answer / code block
- History persists

Download (zip): https://github.com/wlshlad86/claude-bubble/releases/latest  
Needs Claude Code logged in. First open may need right-click → Open (unsigned/ad-hoc).

Source: https://github.com/wlshlad86/claude-bubble
```

### r/MacApps / r/macapps

Same body; lead with “for people who already run Claude Code,” so expectations stay honest.

---

## Demo checklist (record once, reuse)

1. Start on a normal app (Notes / browser).
2. Hit ⌃⌥⌘B → bubble expands.
3. Ask a short question → tokens stream.
4. Highlight prose → ⌘C → paste next door.
5. Ask for a code snippet → hit code copy / full-answer copy.
6. 15–30 seconds total. Export GIF or MP4 → drop in a tweet / README later.

macOS: Screenshot toolbar **⌘⇧5** → Record Selected Portion.

---

## Per-version post habit

When you cut **v0.5**, **v0.6**, …:

1. Ship release + zip asset (see PLAYBOOK).
2. One post with *what’s new in one line* + `/releases/latest`.
3. Don’t re-Show-HN the same project every week — use X/Reddit for minor cuts; Show HN once for a real jump (e.g. notarized download, multi-line input).

---

## Not yet (later growth)

- Apple Developer ID + notarize → fewer Gatekeeper bounces  
- Homebrew cask once notarized  
- Auto-update (Sparkle) — only if people actually reinstall  
