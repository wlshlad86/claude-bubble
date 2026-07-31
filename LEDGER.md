# LEDGER — decisions & corrections

Append-only. Newest at top. One entry per durable lesson or decision.

## 2026-07-31 — release assets + download path
- **GitHub Releases are the public product surface**, not only tags. v0.2–v0.4 live on
  the Releases page; each cut should attach `ClaudeBubble-vX.Y-macos.zip` via
  `gh release upload`. Ad-hoc signed → README must document right-click Open / Gatekeeper.
- Downloaders need Claude Code logged in, not the Swift toolchain; split README
  Requirements into Download vs Build from source.

## 2026-07-31 — v0.4: copy-out answers (usable text)
- **Claude prose was not selectable.** `.textSelection(.enabled)` lived on your bubbles and
  code blocks only; `ProseText` headings/bullets/paragraphs had none, so normal answers
  could not be highlighted or ⌘C'd. Fix: enable selection on every prose `Text`, plus a
  per-message "Copy full answer" button that puts raw markdown (including fences) on the
  pasteboard via shared `copyToClipboard`. Code-block one-click copy unchanged.

## 2026-06-29 — v0.3: usability + continuity pass
- **Markdown is rendered by a hand-rolled splitter, not a library.** `AttributedString(markdown:)`
  handles inline syntax only (`.inlineOnlyPreservingWhitespace`); block structure (code
  fences, bullets, headings) is done by `MarkdownParser`/`ProseText`. Rationale: zero
  dependencies, macOS 12-safe, and code blocks (the real pain point) get a dedicated
  monospace+copy view. Good enough for chat; not a full CommonMark renderer.
- **Conversations persist to JSON in Application Support**, not UserDefaults — messages can
  be large. Session id is saved too, so `--resume` continues the *same* Claude session
  after relaunch (subject to Claude Code's own session retention).
- **Bubble position is anchored top-left and clamped on-screen.** Programmatic expand/collapse
  is guarded (`isProgrammaticMove` + 0.4s window) so it can't be mistaken for a user drag,
  which previously would have made the bubble drift upward near the bottom edge.
- **Errors are surfaced, not swallowed.** stderr is captured and the exit status checked;
  "Not logged in" and missing-CLI cases get plain-English guidance instead of "(no response)".
- **Deferred multi-line input.** A custom NSTextView (Enter=send, Shift+Enter=newline) is the
  right fix but adds the most compile risk; kept the working single-line `TextField` +
  `@FocusState` for this pass. Tracked in README "Next ideas".

## Standing constraints
- **Swift only compiles on the Mac** — never assume a sandbox build verifies anything.
- **Keep it one file.** The smallness is the product.
- **Public repo — ask before pushing.**
