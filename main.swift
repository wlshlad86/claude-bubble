import SwiftUI
import AppKit
import Combine
import Carbon

// MARK: - CLI discovery

// Locate the Claude Code CLI — the bubble's brain. Honour a CLAUDE_PATH override,
// otherwise probe the usual install locations and fall back to the documented default.
func resolveClaudePath() -> String {
    let fm = FileManager.default
    if let override = ProcessInfo.processInfo.environment["CLAUDE_PATH"],
       fm.isExecutableFile(atPath: override) {
        return override
    }
    let home = NSHomeDirectory()
    let candidates = [
        "\(home)/.local/bin/claude",
        "/opt/homebrew/bin/claude",
        "/usr/local/bin/claude",
        "\(home)/.claude/local/claude",
        "/usr/bin/claude",
    ]
    for c in candidates where fm.isExecutableFile(atPath: c) { return c }
    return candidates[0]
}
let CLAUDE_PATH = resolveClaudePath()

// On-disk home for persisted conversation state.
func bubbleSupportDir() -> URL {
    let fm = FileManager.default
    let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
    let dir = base.appendingPathComponent("ClaudeBubble", isDirectory: true)
    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

extension Notification.Name { static let toggleBubble = Notification.Name("ToggleBubble") }

// MARK: - Persistence model

struct StoredMessage: Codable { var role: String; var text: String }
struct PersistedState: Codable {
    var sessionId: String
    var hasSession: Bool
    var messages: [StoredMessage]
}

// MARK: - State + streaming Claude call

final class AppState: ObservableObject {
    enum Role { case you, claude }
    struct Message: Identifiable { let id: Int; let role: Role; var text: String }

    @Published var expanded = false
    @Published var query = ""
    @Published var messages: [Message] = []
    @Published var loading = false

    private var nextId = 0
    private var sessionId = UUID().uuidString
    private var hasSession = false          // first turn sets the session, later turns resume it
    private var buffer = Data()
    private var stderrBuf = Data()
    private var current: Process?

    static let storeURL = bubbleSupportDir().appendingPathComponent("conversation.json")

    init() { load() }

    func newChat() {
        current?.terminate()
        messages.removeAll()
        query = ""
        sessionId = UUID().uuidString
        hasSession = false
        loading = false
        try? FileManager.default.removeItem(at: Self.storeURL)
    }

    func ask() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !loading else { return }
        query = ""
        loading = true
        messages.append(Message(id: nextId, role: .you, text: q)); nextId += 1
        messages.append(Message(id: nextId, role: .claude, text: "")); nextId += 1
        buffer = Data()
        stderrBuf = Data()
        save()
        let resume = hasSession
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.run(prompt: q, resume: resume)
        }
    }

    func stop() {
        current?.terminate()
        guard loading else { return }
        loading = false
        if let i = messages.indices.last, messages[i].role == .claude, messages[i].text.isEmpty {
            messages[i].text = "_(stopped)_"
        }
        save()
    }

    private func run(prompt: String, resume: Bool) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: CLAUDE_PATH)
        var args = ["-p", prompt,
                    "--output-format", "stream-json",
                    "--verbose", "--include-partial-messages"]
        args += resume ? ["--resume", sessionId] : ["--session-id", sessionId]
        proc.arguments = args

        var env = ProcessInfo.processInfo.environment
        let extra = "\(NSHomeDirectory())/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        env["PATH"] = extra + ":" + (env["PATH"] ?? "")
        env["HOME"] = NSHomeDirectory()
        env["USER"] = NSUserName()
        env["LOGNAME"] = NSUserName()
        proc.environment = env
        proc.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())

        let pipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = errPipe
        current = proc

        errPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            self?.stderrBuf.append(data)
        }

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self = self else { return }
            let data = handle.availableData
            if data.isEmpty {                       // EOF — stream finished
                handle.readabilityHandler = nil
                proc.waitUntilExit()
                let status = proc.terminationStatus
                let err = String(data: self.stderrBuf, encoding: .utf8) ?? ""
                DispatchQueue.main.async { self.finalize(status: status, stderr: err) }
                return
            }
            self.buffer.append(data)
            while let nl = self.buffer.firstIndex(of: 0x0A) {
                let line = self.buffer.subdata(in: self.buffer.startIndex..<nl)
                self.buffer.removeSubrange(self.buffer.startIndex...nl)
                if !line.isEmpty { self.handle(line: line) }
            }
        }

        do { try proc.run() }
        catch {
            DispatchQueue.main.async {
                self.appendDelta("Couldn't run claude: \(error.localizedDescription)")
                self.finalize()
            }
        }
    }

    private func handle(line: Data) {
        guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              obj["type"] as? String == "stream_event",
              let ev = obj["event"] as? [String: Any],
              ev["type"] as? String == "content_block_delta",
              let delta = ev["delta"] as? [String: Any],
              delta["type"] as? String == "text_delta",
              let t = delta["text"] as? String
        else { return }
        DispatchQueue.main.async { self.appendDelta(t) }
    }

    private func appendDelta(_ t: String) {
        if let i = messages.indices.last, messages[i].role == .claude {
            messages[i].text += t
        }
    }

    private func finalize(status: Int32 = 0, stderr: String = "") {
        guard loading else { return }
        loading = false
        hasSession = true
        if let i = messages.indices.last, messages[i].role == .claude, messages[i].text.isEmpty {
            messages[i].text = friendlyError(status: status, stderr: stderr)
        }
        save()
    }

    private func friendlyError(status: Int32, stderr: String) -> String {
        let s = stderr.lowercased()
        if s.contains("not logged in") || s.contains("unauthorized") || s.contains("please log in") {
            return "⚠️ Claude Code isn't logged in. Open a terminal, run `claude`, sign in, then try again."
        }
        if status == 127 || s.contains("no such file") || s.contains("command not found") {
            return "⚠️ Couldn't find the Claude CLI at `\(CLAUDE_PATH)`. Install Claude Code or set CLAUDE_PATH."
        }
        let tail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { return "⚠️ " + String(tail.suffix(300)) }
        return "(no response — try again)"
    }

    // MARK: Persistence

    private func save() {
        let stored = PersistedState(
            sessionId: sessionId,
            hasSession: hasSession,
            messages: messages.map { StoredMessage(role: $0.role == .you ? "you" : "claude", text: $0.text) })
        if let data = try? JSONEncoder().encode(stored) {
            try? data.write(to: Self.storeURL, options: .atomic)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.storeURL),
              let stored = try? JSONDecoder().decode(PersistedState.self, from: data) else { return }
        sessionId = stored.sessionId
        hasSession = stored.hasSession
        messages = stored.messages.enumerated().map { idx, m in
            Message(id: idx, role: m.role == "you" ? .you : .claude, text: m.text)
        }
        nextId = messages.count
    }
}

// MARK: - Markdown rendering

enum MDSegment { case prose(String); case code(String, String?) }

enum MarkdownParser {
    // Split a message into prose and fenced-code segments.
    static func segments(_ text: String) -> [MDSegment] {
        var result: [MDSegment] = []
        var inCode = false
        var codeLang: String?
        var codeBuf: [String] = []
        var proseBuf: [String] = []

        func flushProse() {
            let s = proseBuf.joined(separator: "\n")
            if !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result.append(.prose(s)) }
            proseBuf.removeAll()
        }

        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if inCode {
                    result.append(.code(codeBuf.joined(separator: "\n"), codeLang))
                    codeBuf.removeAll(); inCode = false; codeLang = nil
                } else {
                    flushProse()
                    inCode = true
                    let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    codeLang = lang.isEmpty ? nil : lang
                }
            } else if inCode {
                codeBuf.append(line)
            } else {
                proseBuf.append(line)
            }
        }
        if inCode { result.append(.code(codeBuf.joined(separator: "\n"), codeLang)) } // unterminated (mid-stream)
        flushProse()
        return result
    }
}

struct MarkdownText: View {
    let text: String
    var body: some View {
        let segs = MarkdownParser.segments(text)
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(segs.enumerated()), id: \.offset) { _, seg in
                switch seg {
                case .code(let code, let lang): CodeBlock(code: code, lang: lang)
                case .prose(let s): ProseText(text: s)
                }
            }
        }
    }
}

/// Put plain text on the system clipboard (code blocks + whole-answer copy).
func copyToClipboard(_ s: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(s, forType: .string)
}

struct ProseText: View {
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(text.components(separatedBy: "\n").enumerated()), id: \.offset) { _, raw in
                lineView(raw)
            }
        }
    }

    @ViewBuilder private func lineView(_ raw: String) -> some View {
        let t = raw.trimmingCharacters(in: .whitespaces)
        if t.isEmpty {
            Color.clear.frame(height: 4)
        } else if t.hasPrefix("### ") {
            Text(inline(String(t.dropFirst(4)))).font(.system(size: 12, weight: .semibold)).textSelection(.enabled)
        } else if t.hasPrefix("## ") {
            Text(inline(String(t.dropFirst(3)))).font(.system(size: 13, weight: .bold)).textSelection(.enabled)
        } else if t.hasPrefix("# ") {
            Text(inline(String(t.dropFirst(2)))).font(.system(size: 14, weight: .bold)).textSelection(.enabled)
        } else if let body = bullet(t) {
            HStack(alignment: .top, spacing: 6) {
                Text("•").font(.system(size: 12))
                Text(inline(body)).font(.system(size: 12)).textSelection(.enabled)
            }
        } else {
            Text(inline(raw)).font(.system(size: 12)).textSelection(.enabled)
        }
    }

    private func bullet(_ t: String) -> String? {
        for p in ["- ", "* ", "+ "] where t.hasPrefix(p) { return String(t.dropFirst(p.count)) }
        return nil
    }

    private func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}

struct CodeBlock: View {
    let code: String
    let lang: String?
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(lang ?? "code").font(.system(size: 9, weight: .medium)).foregroundColor(.secondary)
                Spacer()
                Button(action: copy) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.system(size: 10))
                }
                .buttonStyle(.plain).foregroundColor(.secondary).help("Copy code")
            }
            .padding(.horizontal, 8).padding(.top, 5).padding(.bottom, 3)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.horizontal, 8).padding(.bottom, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 8))
    }

    private func copy() {
        copyToClipboard(code)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
    }
}

// MARK: - Message row

struct MessageRow: View {
    let msg: AppState.Message
    @State private var copied = false

    var body: some View {
        HStack(spacing: 0) {
            if msg.role == .you { Spacer(minLength: 28) }
            Group {
                if msg.role == .you {
                    Text(msg.text).font(.system(size: 12)).textSelection(.enabled)
                } else {
                    HStack(alignment: .top, spacing: 6) {
                        MarkdownText(text: msg.text.isEmpty ? "…" : msg.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if !msg.text.isEmpty {
                            Button(action: copyAnswer) {
                                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 10))
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.secondary)
                            .help("Copy full answer")
                        }
                    }
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(
                msg.role == .you ? Color.accentColor.opacity(0.28) : Color.gray.opacity(0.18),
                in: RoundedRectangle(cornerRadius: 12))
            if msg.role == .claude { Spacer(minLength: 28) }
        }
    }

    private func copyAnswer() {
        copyToClipboard(msg.text)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
    }
}

// MARK: - Bubble + chat UI

struct BubbleView: View {
    @ObservedObject var state: AppState
    @ObservedObject var hotkey: HotkeyManager
    @State private var bob = false
    @State private var pulse = false
    @State private var showSettings = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            bubble
            if state.expanded { chatPanel }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: state.expanded) { exp in
            if exp { DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { inputFocused = true } }
        }
    }

    var bubble: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [Color(red: 0.45, green: 0.35, blue: 0.95),
                             Color(red: 0.88, green: 0.35, blue: 0.70)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 56, height: 56)
                .shadow(color: .black.opacity(0.28), radius: 8, y: 3)
            if state.loading {
                Circle().stroke(Color.white.opacity(0.6), lineWidth: 2)
                    .frame(width: 56, height: 56)
                    .scaleEffect(pulse ? 1.35 : 1.0)
                    .opacity(pulse ? 0 : 0.7)
            }
            Image(systemName: state.loading ? "ellipsis" : "sparkles")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.white)
        }
        .scaleEffect(bob ? 1.05 : 0.96)
        .offset(y: bob ? -3 : 3)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { bob = true }
        }
        .onChange(of: state.loading) { loading in
            if loading {
                pulse = false
                withAnimation(.easeOut(duration: 0.9).repeatForever(autoreverses: false)) { pulse = true }
            } else {
                pulse = false
            }
        }
        .onTapGesture { state.expanded.toggle() }
        .padding(8)
    }

    var chatPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if state.messages.isEmpty {
                            Text("Ask me anything.\n\(hotkey.displayString) summons me from anywhere.\nPowered by Claude Code · Opus 4.8")
                                .font(.system(size: 11)).foregroundColor(.secondary)
                        }
                        ForEach(state.messages) { m in MessageRow(msg: m).id(m.id) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
                .onChange(of: state.messages.last?.text) { _ in
                    if let last = state.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
            .frame(maxHeight: .infinity)
            inputBar
        }
        .padding(12)
        .frame(width: 336, height: 452, alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.15)))
        .onExitCommand { state.expanded = false }
    }

    var header: some View {
        HStack {
            Text("Claude bubble").font(.caption.weight(.semibold)).foregroundColor(.secondary)
            Spacer()
            Button(action: { showSettings.toggle() }) { Image(systemName: "gearshape") }
                .buttonStyle(.plain).help("Settings")
                .popover(isPresented: $showSettings, arrowEdge: .bottom) { settingsView }
            Button(action: { state.newChat() }) { Image(systemName: "square.and.pencil") }
                .buttonStyle(.plain).help("New chat (⌘N)")
                .keyboardShortcut("n", modifiers: .command)
        }
    }

    var inputBar: some View {
        HStack(spacing: 6) {
            TextField("Message…", text: $state.query)
                .textFieldStyle(.roundedBorder)
                .focused($inputFocused)
                .onSubmit { state.ask() }
            if state.loading {
                Button(action: { state.stop() }) {
                    Image(systemName: "stop.circle.fill").font(.title2)
                }
                .buttonStyle(.plain).help("Stop")
            } else {
                Button(action: { state.ask() }) {
                    Image(systemName: "arrow.up.circle.fill").font(.title2)
                }
                .buttonStyle(.plain)
            }
        }
    }

    var settingsView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Settings").font(.headline)
            HStack {
                Text("Global hotkey").font(.system(size: 12))
                Spacer()
                Button(hotkey.recording ? "Press keys…" : hotkey.displayString) {
                    hotkey.recording ? hotkey.endRecording() : hotkey.beginRecording()
                }
                .buttonStyle(.bordered)
            }
            Text("Click the button, then press a combo with at least one modifier (⌘ ⌥ ⌃ ⇧).")
                .font(.system(size: 10)).foregroundColor(.secondary)
            Divider()
            Text("Conversations are saved and restored across restarts.")
                .font(.system(size: 10)).foregroundColor(.secondary)
            Text("Powered by Claude Code · Opus 4.8")
                .font(.system(size: 10)).foregroundColor(.secondary)
        }
        .padding(14).frame(width: 264)
    }
}

// MARK: - Global hotkey

final class HotkeyManager: ObservableObject {
    @Published private(set) var keyCode: UInt32
    @Published private(set) var modifiers: UInt32       // Carbon modifier mask
    @Published var recording = false

    private var ref: EventHotKeyRef?
    private var handlerInstalled = false
    private var monitor: Any?

    init() {
        let d = UserDefaults.standard
        if d.object(forKey: "hotkeyKeyCode") != nil {
            keyCode = UInt32(d.integer(forKey: "hotkeyKeyCode"))
            modifiers = UInt32(d.integer(forKey: "hotkeyModifiers"))
        } else {
            keyCode = UInt32(kVK_ANSI_B)
            modifiers = UInt32(cmdKey | optionKey | controlKey)
        }
    }

    func register() {
        if !handlerInstalled {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                     eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), hotKeyHandler, 1, &spec, nil, nil)
            handlerInstalled = true
        }
        if let r = ref { UnregisterEventHotKey(r); ref = nil }
        let id = EventHotKeyID(signature: fourCharCode("BUBL"), id: 1)
        RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref)
    }

    func beginRecording() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] ev in
            guard let self = self else { return ev }
            var carbon: UInt32 = 0
            let mods = ev.modifierFlags
            if mods.contains(.command) { carbon |= UInt32(cmdKey) }
            if mods.contains(.option)  { carbon |= UInt32(optionKey) }
            if mods.contains(.control) { carbon |= UInt32(controlKey) }
            if mods.contains(.shift)   { carbon |= UInt32(shiftKey) }
            if carbon == 0 { return ev }            // require a modifier; ignore bare keys
            self.keyCode = UInt32(ev.keyCode)
            self.modifiers = carbon
            let d = UserDefaults.standard
            d.set(Int(self.keyCode), forKey: "hotkeyKeyCode")
            d.set(Int(self.modifiers), forKey: "hotkeyModifiers")
            self.register()
            self.endRecording()
            return nil                              // swallow the recorded combo
        }
    }

    func endRecording() {
        recording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }

    var displayString: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey)  != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey)   != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey)     != 0 { s += "⌘" }
        return s + Self.keyName(keyCode)
    }

    static func keyName(_ code: UInt32) -> String {
        let map: [Int: String] = [
            kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E",
            kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J",
            kVK_ANSI_K: "K", kVK_ANSI_L: "L", kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O",
            kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
            kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X", kVK_ANSI_Y: "Y",
            kVK_ANSI_Z: "Z",
            kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4",
            kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
            kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Escape: "⎋",
        ]
        return map[Int(code)] ?? "key\(code)"
    }
}

// Global hotkey C callback → posts a notification the app observes.
private func hotKeyHandler(_ next: EventHandlerCallRef?, _ event: EventRef?,
                           _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    NotificationCenter.default.post(name: .toggleBubble, object: nil)
    return noErr
}

private func fourCharCode(_ s: String) -> OSType {
    var r: OSType = 0
    for c in s.utf16 { r = (r << 8) + OSType(c) }
    return r
}

// MARK: - Floating panel

final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: KeyablePanel!
    let state = AppState()
    let hotkey = HotkeyManager()
    var cancellable: AnyCancellable?
    private var isProgrammaticMove = false

    func applicationDidFinishLaunching(_ note: Notification) {
        let hosting = NSHostingView(rootView: BubbleView(state: state, hotkey: hotkey))
        hosting.frame = NSRect(x: 0, y: 0, width: 360, height: 540)
        hosting.autoresizingMask = [.width, .height]

        panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 72, height: 72),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = true
        panel.contentView = hosting

        position(expanded: false)
        panel.orderFrontRegardless()

        cancellable = state.$expanded.sink { [weak self] exp in
            DispatchQueue.main.async {
                self?.position(expanded: exp)
                if exp {
                    NSApp.activate(ignoringOtherApps: true)
                    self?.panel.makeKeyAndOrderFront(nil)
                }
            }
        }

        NotificationCenter.default.addObserver(forName: .toggleBubble, object: nil, queue: .main) { [weak self] _ in
            self?.state.expanded.toggle()
        }
        // Remember where the user drags the bubble.
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) { [weak self] _ in
            guard let self = self, !self.isProgrammaticMove, let f = self.panel?.frame else { return }
            let d = UserDefaults.standard
            d.set(Double(f.minX), forKey: "bubbleX")   // top-left anchor
            d.set(Double(f.maxY), forKey: "bubbleY")
        }

        hotkey.register()
    }

    func position(expanded: Bool) {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        let vf = screen.visibleFrame
        let margin: CGFloat = 14
        let w: CGFloat = expanded ? 360 : 72
        let h: CGFloat = expanded ? 540 : 72

        // Anchor by the bubble's top-left corner so collapse/expand grows downward
        // from wherever the user last left it.
        let d = UserDefaults.standard
        let tl: NSPoint = d.object(forKey: "bubbleX") != nil
            ? NSPoint(x: d.double(forKey: "bubbleX"), y: d.double(forKey: "bubbleY"))
            : NSPoint(x: vf.minX + margin, y: vf.maxY - margin)

        var x = tl.x
        var top = tl.y
        x = min(max(x, vf.minX + margin), vf.maxX - w - margin)
        top = min(max(top, vf.minY + h + margin), vf.maxY - margin)
        let origin = NSPoint(x: x, y: top - h)

        isProgrammaticMove = true
        panel.setFrame(NSRect(origin: origin, size: CGSize(width: w, height: h)), display: true, animate: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.isProgrammaticMove = false }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
