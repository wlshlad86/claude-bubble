import SwiftUI
import AppKit
import Combine
import Carbon

// Path to the Claude Code CLI — this is the bubble's brain.
let CLAUDE_PATH = "\(NSHomeDirectory())/.local/bin/claude"

extension Notification.Name { static let toggleBubble = Notification.Name("ToggleBubble") }

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
    private var current: Process?

    func newChat() {
        current?.terminate()
        messages.removeAll()
        query = ""
        sessionId = UUID().uuidString
        hasSession = false
        loading = false
    }

    func ask() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !loading else { return }
        query = ""
        loading = true
        messages.append(Message(id: nextId, role: .you, text: q)); nextId += 1
        messages.append(Message(id: nextId, role: .claude, text: "")); nextId += 1
        buffer = Data()
        let resume = hasSession
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.run(prompt: q, resume: resume)
        }
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
        proc.standardOutput = pipe
        proc.standardError = Pipe()   // swallow stderr noise
        current = proc

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self = self else { return }
            let data = handle.availableData
            if data.isEmpty {                       // EOF
                handle.readabilityHandler = nil
                DispatchQueue.main.async { self.finalize() }
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

    private func finalize() {
        guard loading else { return }
        loading = false
        hasSession = true
        if let i = messages.indices.last, messages[i].role == .claude, messages[i].text.isEmpty {
            messages[i].text = "(no response — try again)"
        }
    }
}

// MARK: - UI

struct MessageRow: View {
    let msg: AppState.Message
    var body: some View {
        HStack(spacing: 0) {
            if msg.role == .you { Spacer(minLength: 28) }
            Text(msg.text.isEmpty ? "…" : msg.text)
                .font(.system(size: 12))
                .textSelection(.enabled)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(
                    msg.role == .you ? Color.accentColor.opacity(0.28) : Color.gray.opacity(0.18),
                    in: RoundedRectangle(cornerRadius: 12))
            if msg.role == .claude { Spacer(minLength: 28) }
        }
    }
}

struct BubbleView: View {
    @ObservedObject var state: AppState
    @State private var bob = false
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
            Image(systemName: state.loading ? "ellipsis" : "sparkles")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.white)
        }
        .scaleEffect(bob ? 1.05 : 0.96)
        .offset(y: bob ? -3 : 3)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { bob = true }
        }
        .onTapGesture { state.expanded.toggle() }
        .padding(8)
    }

    var chatPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Claude bubble").font(.caption.weight(.semibold)).foregroundColor(.secondary)
                Spacer()
                Button(action: { state.newChat() }) { Image(systemName: "square.and.pencil") }
                    .buttonStyle(.plain).help("New chat")
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if state.messages.isEmpty {
                            Text("Ask me anything.\n⌃⌥⌘B summons me from anywhere.\nPowered by Claude Code · Opus 4.8")
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
            HStack(spacing: 6) {
                TextField("Message…", text: $state.query)
                    .textFieldStyle(.roundedBorder)
                    .focused($inputFocused)
                    .onSubmit { state.ask() }
                Button(action: { state.ask() }) {
                    Image(systemName: "arrow.up.circle.fill").font(.title2)
                }
                .buttonStyle(.plain).disabled(state.loading)
            }
        }
        .padding(12)
        .frame(width: 336, height: 452, alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.15)))
    }
}

// MARK: - Floating panel + global hotkey

final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
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

final class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: KeyablePanel!
    let state = AppState()
    var cancellable: AnyCancellable?
    var hotKeyRef: EventHotKeyRef?

    func applicationDidFinishLaunching(_ note: Notification) {
        let hosting = NSHostingView(rootView: BubbleView(state: state))
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
        registerHotKey()
    }

    func registerHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotKeyHandler, 1, &spec, nil, nil)
        let id = EventHotKeyID(signature: fourCharCode("BUBL"), id: 1)
        // ⌃⌥⌘B
        RegisterEventHotKey(UInt32(kVK_ANSI_B),
                            UInt32(cmdKey | optionKey | controlKey),
                            id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func position(expanded: Bool) {
        guard let screen = NSScreen.main else { return }
        let vf = screen.visibleFrame
        let margin: CGFloat = 14
        let w: CGFloat = expanded ? 360 : 72
        let h: CGFloat = expanded ? 540 : 72
        let topY = vf.maxY - margin
        let origin = NSPoint(x: vf.minX + margin, y: topY - h)
        panel.setFrame(NSRect(origin: origin, size: CGSize(width: w, height: h)),
                       display: true, animate: true)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
