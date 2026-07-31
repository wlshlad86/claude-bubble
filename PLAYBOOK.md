# PLAYBOOK — procedures

## Build & verify a change (the only loop that matters)
1. Edit `main.swift`.
2. `bash build.sh` on the Mac. If `swiftc` errors, fix and rebuild — there's no Xcode
   project to lean on, so the compiler is the gate.
3. `pkill -f ClaudeBubble` then `open ClaudeBubble.app`.
4. Smoke test, in order:
   - Bubble appears at its last position; bobbing animation runs.
   - Hotkey (default ⌃⌥⌘B, or whatever's set) toggles the panel from another app.
   - Ask a question → tokens stream in; the thinking ring pulses while loading.
   - Ask for code → it renders in a monospace block; the copy button works.
   - Ask for prose → highlight text and ⌘C; the whole-answer copy button copies the full reply.
   - Esc collapses; ⌘N clears; the Stop button interrupts a long answer.
   - Quit and relaunch → the conversation is still there.

## Cut a release / bump version
1. Update `CFBundleShortVersionString` in `build.sh`.
2. Update the `## Status: vX.Y` section and feature list in `README.md`.
3. Build + smoke test (above).
4. Commit with a clear message. **Ask before pushing** to the public repo.

## Change the default hotkey behaviour
`HotkeyManager` owns it. `register()` (re)registers the Carbon hotkey; `beginRecording()`
captures the next modified keypress via a local `NSEvent` monitor. Defaults live in `init()`.
The C callback `hotKeyHandler` posts `.toggleBubble`.

## Reposition / sizing logic
`AppDelegate.position(expanded:)` anchors the panel by its **top-left** corner so it grows
downward. Drags are saved in `NSWindow.didMoveNotification`; programmatic moves are guarded
by `isProgrammaticMove` so expand/collapse never causes drift. Clamp keeps it on-screen.

## Add a persisted setting
Store it in `UserDefaults` (like the hotkey/position) for simple scalars, or extend
`PersistedState` for conversation-scoped data. Keep `save()`/`load()` symmetric.

## Git
- Branch off `main` for anything non-trivial.
- `git status` / `git diff` and show the user before pushing.
- Never commit `bubble.log` or `ClaudeBubble.app/` (already in `.gitignore`).
