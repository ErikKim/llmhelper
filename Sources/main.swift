import Cocoa
import Carbon.HIToolbox
import ApplicationServices

// MARK: - Config

struct Config {
    var model: String = "qwen3:8b"
    var host: String = "http://localhost:11434"
    var prompts: [String: String] = Config.defaultPrompts

    // {text} 자리에 선택한 텍스트가 들어간다. config.json 에서 자유롭게 수정 가능.
    static let defaultPrompts: [String: String] = [
        "translate": "다음 텍스트를 번역해줘. 입력이 한국어면 자연스러운 영어로, 그 외 언어면 자연스러운 한국어로. 부연 설명 없이 번역문만 출력해.\n\n{text}",
        "explain":   "다음 내용을 핵심만 골라 아주 짧고 간결하게 한국어로 설명해줘. 2~3문장 이내로. 서론·군더더기·불필요한 예시 없이 바로 핵심만.\n\n{text}",
        "detail":    "다음 내용을 배경·핵심·함의까지 자세하고 정확하게 한국어로 설명해줘. 필요하면 항목으로 정리해도 좋아.\n\n{text}",
    ]

    func prompt(for mode: Mode, text: String) -> String {
        let tmpl = prompts[mode.rawValue] ?? Config.defaultPrompts[mode.rawValue] ?? "{text}"
        return tmpl.replacingOccurrences(of: "{text}", with: text)
    }

    static var path: String { ("~/.config/llmhelper/config.json" as NSString).expandingTildeInPath }

    static func load() -> Config {
        var cfg = Config()
        guard let data = FileManager.default.contents(atPath: path),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return cfg
        }
        if let m = obj["model"] as? String, !m.isEmpty { cfg.model = m }
        if let h = obj["host"] as? String, !h.isEmpty { cfg.host = h }
        if let p = obj["prompts"] as? [String: String] {
            for (k, v) in p where !v.isEmpty { cfg.prompts[k] = v }
        }
        return cfg
    }

    func save() {
        let dir = ("~/.config/llmhelper" as NSString).expandingTildeInPath
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let obj: [String: Any] = ["model": model, "host": host, "prompts": prompts]
        // JSONSerialization writes raw UTF-8 (Korean stays readable), pretty-printed for editing.
        if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: Config.path))
        }
    }
}

// MARK: - Modes

enum Mode: String {
    case translate, explain, detail

    var title: String {
        switch self {
        case .translate: return "번역"
        case .explain:   return "쉽게 설명"
        case .detail:    return "상세히"
        }
    }
}

// MARK: - Result Panel

final class ResultPanel: NSObject, NSWindowDelegate {
    private var panel: NSPanel!
    private var textView: NSTextView!
    private var headerLabel: NSTextField!
    private var copyButton: NSButton!
    private var spinner: NSProgressIndicator!
    private var streamTask: Task<Void, Never>?
    private var ignoreResignUntil = Date.distantPast

    static let shared = ResultPanel()

    private func buildIfNeeded() {
        guard panel == nil else { return }

        let rect = NSRect(x: 0, y: 0, width: 460, height: 360)
        panel = NSPanel(contentRect: rect,
                        styleMask: [.titled, .closable, .resizable, .utilityWindow, .fullSizeContentView],
                        backing: .buffered, defer: false)
        panel.title = "LLMHelper"
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.minSize = NSSize(width: 320, height: 220)

        let blur = NSVisualEffectView(frame: rect)
        blur.autoresizingMask = [.width, .height]
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        panel.contentView = blur

        headerLabel = NSTextField(labelWithString: "")
        headerLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        headerLabel.textColor = .secondaryLabelColor
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(headerLabel)

        spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(spinner)

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder

        textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 14)
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        scroll.documentView = textView
        blur.addSubview(scroll)

        copyButton = NSButton(title: "복사", target: self, action: #selector(copyAll))
        copyButton.bezelStyle = .rounded
        copyButton.keyEquivalent = "c"
        copyButton.keyEquivalentModifierMask = [.command]
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(copyButton)

        NSLayoutConstraint.activate([
            headerLabel.topAnchor.constraint(equalTo: blur.topAnchor, constant: 30),
            headerLabel.leadingAnchor.constraint(equalTo: blur.leadingAnchor, constant: 14),

            spinner.centerYAnchor.constraint(equalTo: headerLabel.centerYAnchor),
            spinner.leadingAnchor.constraint(equalTo: headerLabel.trailingAnchor, constant: 8),

            scroll.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: blur.leadingAnchor, constant: 12),
            scroll.trailingAnchor.constraint(equalTo: blur.trailingAnchor, constant: -12),
            scroll.bottomAnchor.constraint(equalTo: copyButton.topAnchor, constant: -8),

            copyButton.trailingAnchor.constraint(equalTo: blur.trailingAnchor, constant: -12),
            copyButton.bottomAnchor.constraint(equalTo: blur.bottomAnchor, constant: -12),
        ])
    }

    @objc private func copyAll() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(textView.string, forType: .string)
        copyButton.title = "복사됨 ✓"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.copyButton.title = "복사"
        }
    }

    private func positionNearCursor() {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main else { return }
        let mouse = NSEvent.mouseLocation
        var frame = panel.frame
        frame.origin = NSPoint(x: mouse.x + 16, y: mouse.y - frame.height - 16)
        let vis = screen.visibleFrame
        frame.origin.x = min(max(frame.origin.x, vis.minX), vis.maxX - frame.width)
        frame.origin.y = min(max(frame.origin.y, vis.minY), vis.maxY - frame.height)
        panel.setFrame(frame, display: true)
    }

    func showMessage(_ msg: String) {
        DispatchQueue.main.async {
            self.buildIfNeeded()
            self.streamTask?.cancel()
            self.headerLabel.stringValue = "LLMHelper"
            self.textView.string = msg
            self.spinner.stopAnimation(nil)
            self.positionNearCursor()
            self.panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            self.ignoreResignUntil = Date().addingTimeInterval(0.5)
        }
    }

    func start(mode: Mode, text: String, config: Config) {
        DispatchQueue.main.async {
            self.buildIfNeeded()
            self.streamTask?.cancel()
            self.headerLabel.stringValue = "\(mode.title)  ·  \(config.model)"
            self.textView.string = ""
            self.spinner.startAnimation(nil)
            self.positionNearCursor()
            self.panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            self.ignoreResignUntil = Date().addingTimeInterval(0.5)
            self.streamTask = Task { await self.stream(mode: mode, text: text, config: config) }
        }
    }

    private func append(_ s: String) {
        textView.textStorage?.append(NSAttributedString(
            string: s,
            attributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.labelColor]))
        textView.scrollToEndOfDocument(nil)
    }

    @MainActor
    private func stream(mode: Mode, text: String, config: Config) async {
        guard let url = URL(string: config.host + "/api/generate") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": config.model,
            "prompt": config.prompt(for: mode, text: text),
            "stream": true,
            "think": false,
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        var inThink = false
        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                append("⚠️ Ollama 응답 오류 (HTTP \(http.statusCode)). 모델 '\(config.model)' 이 설치돼 있는지 확인하세요.")
                spinner.stopAnimation(nil)
                return
            }
            for try await line in bytes.lines {
                if Task.isCancelled { break }
                guard let data = line.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                if var chunk = obj["response"] as? String, !chunk.isEmpty {
                    if inThink {
                        if let r = chunk.range(of: "</think>") { chunk = String(chunk[r.upperBound...]); inThink = false }
                        else { continue }
                    }
                    if let r = chunk.range(of: "<think>") {
                        let before = String(chunk[..<r.lowerBound])
                        if !before.isEmpty { append(before) }
                        inThink = true
                        continue
                    }
                    append(chunk)
                }
                if obj["done"] as? Bool == true { break }
            }
        } catch {
            if !Task.isCancelled {
                append("\n\n⚠️ 호출 실패: \(error.localizedDescription)\nOllama 가 실행 중인지(localhost:11434) 확인하세요.")
            }
        }
        spinner.stopAnimation(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        streamTask?.cancel()
        return true
    }

    // Close when the panel loses focus (clicked away), after a short grace period.
    func windowDidResignKey(_ notification: Notification) {
        guard Date() >= ignoreResignUntil else { return }
        streamTask?.cancel()
        panel.orderOut(nil)
    }
}

// MARK: - Global Hot Keys (Carbon)

final class HotKeys {
    typealias Handler = (Int) -> Void
    private let handler: Handler
    private var refs: [EventHotKeyRef?] = []

    init(handler: @escaping Handler) {
        self.handler = handler
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { (_, event, userData) -> OSStatus in
            guard let userData = userData, let event = event else { return noErr }
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            let me = Unmanaged<HotKeys>.fromOpaque(userData).takeUnretainedValue()
            me.handler(Int(hkID.id))
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
    }

    func register(id: UInt32, keyCode: UInt32, mods: UInt32) {
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: OSType(0x4C4C4D48), id: id) // 'LLMH'
        RegisterEventHotKey(keyCode, mods, hkID, GetApplicationEventTarget(), 0, &ref)
        refs.append(ref)
    }
}

// MARK: - Settings Window

final class SettingsWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow!
    private var hostField: NSTextField!
    private var modelPopup: NSPopUpButton!
    private var tvTranslate: NSTextView!
    private var tvExplain: NSTextView!
    private var tvDetail: NSTextView!
    private var onSave: ((Config) -> Void)?
    private var current = Config()

    private let W: CGFloat = 560, H: CGFloat = 620

    func show(config: Config, models: [String], onSave: @escaping (Config) -> Void) {
        self.onSave = onSave
        self.current = config
        buildIfNeeded()

        hostField.stringValue = config.host
        modelPopup.removeAllItems()
        var items = models
        if items.isEmpty { items = [config.model] }
        if !items.contains(config.model) { items.insert(config.model, at: 0) }
        modelPopup.addItems(withTitles: items)
        modelPopup.selectItem(withTitle: config.model)
        tvTranslate.string = config.prompts["translate"] ?? Config.defaultPrompts["translate"] ?? ""
        tvExplain.string   = config.prompts["explain"]   ?? Config.defaultPrompts["explain"]   ?? ""
        tvDetail.string    = config.prompts["detail"]    ?? Config.defaultPrompts["detail"]    ?? ""

        NSApp.setActivationPolicy(.regular)   // so text fields get proper focus
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private func label(_ s: String, _ y: CGFloat, size: CGFloat = 12, bold: Bool = false, h: CGFloat = 18) -> NSTextField {
        let f = NSTextField(labelWithString: s)
        f.font = bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size)
        if size <= 11 { f.textColor = .secondaryLabelColor }
        f.frame = NSRect(x: 16, y: H - y - h, width: W - 32, height: h)
        return f
    }

    private func editor(_ y: CGFloat, height: CGFloat) -> (NSScrollView, NSTextView) {
        let rect = NSRect(x: 16, y: H - y - height, width: W - 32, height: height)
        let scroll = NSScrollView(frame: rect)
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder
        let tv = NSTextView(frame: scroll.contentView.bounds)
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.containerSize = NSSize(width: scroll.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        tv.textContainer?.widthTracksTextView = true
        tv.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        tv.isRichText = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        scroll.documentView = tv
        return (scroll, tv)
    }

    private func button(_ title: String, x: CGFloat, w: CGFloat, action: Selector, key: String = "") -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .rounded
        b.frame = NSRect(x: x, y: 16, width: w, height: 30)
        b.keyEquivalent = key
        return b
    }

    private func buildIfNeeded() {
        guard window == nil else { return }
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: W, height: H),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "LLMHelper 설정"
        window.delegate = self
        window.isReleasedWhenClosed = false
        let c = NSView(frame: NSRect(x: 0, y: 0, width: W, height: H))

        hostField = NSTextField(frame: NSRect(x: 16, y: H - 60 - 24, width: W - 32, height: 24))
        modelPopup = NSPopUpButton(frame: NSRect(x: 16, y: H - 112 - 26, width: 260, height: 26))

        let (s1, t1) = editor(180, height: 80); tvTranslate = t1
        let (s2, t2) = editor(290, height: 80); tvExplain = t2
        let (s3, t3) = editor(400, height: 80); tvDetail = t3

        c.addSubview(label("Ollama 주소", 32, size: 11))
        c.addSubview(hostField)
        c.addSubview(label("모델", 84, size: 11))
        c.addSubview(modelPopup)
        c.addSubview(label("프롬프트  ·  선택한 텍스트는 {text} 자리에 들어갑니다", 146, size: 11))
        c.addSubview(label("번역", 162, size: 12, bold: true, h: 16))
        c.addSubview(s1)
        c.addSubview(label("쉽게 설명", 272, size: 12, bold: true, h: 16))
        c.addSubview(s2)
        c.addSubview(label("상세히", 382, size: 12, bold: true, h: 16))
        c.addSubview(s3)

        c.addSubview(button("기본값 복원", x: 16, w: 110, action: #selector(resetDefaults)))
        c.addSubview(button("저장", x: W - 16 - 90, w: 90, action: #selector(saveTapped), key: "\r"))
        c.addSubview(button("취소", x: W - 16 - 90 - 8 - 80, w: 80, action: #selector(cancelTapped), key: "\u{1b}"))

        window.contentView = c
    }

    @objc private func resetDefaults() {
        tvTranslate.string = Config.defaultPrompts["translate"] ?? ""
        tvExplain.string   = Config.defaultPrompts["explain"] ?? ""
        tvDetail.string    = Config.defaultPrompts["detail"] ?? ""
    }

    @objc private func cancelTapped() { window.close() }

    @objc private func saveTapped() {
        var cfg = current
        let host = hostField.stringValue.trimmingCharacters(in: .whitespaces)
        cfg.host = host.isEmpty ? "http://localhost:11434" : host
        if let m = modelPopup.titleOfSelectedItem { cfg.model = m }
        cfg.prompts["translate"] = tvTranslate.string
        cfg.prompts["explain"]   = tvExplain.string
        cfg.prompts["detail"]    = tvDetail.string
        onSave?(cfg)
        window.close()
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // back to menu-bar-only agent
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var config = Config.load()
    var statusItem: NSStatusItem!
    var hotKeys: HotKeys!
    var modelMenu: NSMenu!
    var models: [String] = []
    let settings = SettingsWindow()

    // Carbon modifier masks
    private let ctrl = UInt32(controlKey)
    private let opt  = UInt32(optionKey)
    // ANSI number key codes
    private let key1: UInt32 = 18, key2: UInt32 = 19, key3: UInt32 = 20

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        setupHotKeys()
        refreshModels()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = statusItem.button {
            btn.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "LLMHelper")
            btn.image?.isTemplate = true
        }
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(header("선택 후 ⌘C → 아래 클릭, 또는 단축키"))
        menu.addItem(.separator())
        menu.addItem(item("번역            ⌃⌥1", action: #selector(menuTranslate)))
        menu.addItem(item("쉽게 설명     ⌃⌥2", action: #selector(menuExplain)))
        menu.addItem(item("상세히         ⌃⌥3", action: #selector(menuDetail)))
        menu.addItem(.separator())

        modelMenu = NSMenu()
        let modelItem = NSMenuItem(title: "모델", action: nil, keyEquivalent: "")
        modelItem.submenu = modelMenu
        menu.addItem(modelItem)
        rebuildModelMenu()

        menu.addItem(.separator())
        menu.addItem(item("설정…", action: #selector(openSettings)))
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        statusItem.menu = menu
    }

    @objc private func openSettings() {
        settings.show(config: config, models: models) { [weak self] newCfg in
            guard let self = self else { return }
            self.config = newCfg
            self.config.save()
            self.rebuildModelMenu()
        }
    }

    // Refresh model list whenever the menu is opened.
    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === statusItem.menu { refreshModels() }
    }

    private func rebuildModelMenu() {
        modelMenu.removeAllItems()
        if models.isEmpty {
            modelMenu.addItem(header("불러오는 중… (Ollama 실행 확인)"))
            // make sure current model is still selectable even if list is empty
            let i = NSMenuItem(title: config.model, action: #selector(pickModel(_:)), keyEquivalent: "")
            i.target = self; i.state = .on
            modelMenu.addItem(i)
            return
        }
        for name in models {
            let i = NSMenuItem(title: name, action: #selector(pickModel(_:)), keyEquivalent: "")
            i.target = self
            i.state = (name == config.model) ? .on : .off
            modelMenu.addItem(i)
        }
    }

    @objc private func pickModel(_ sender: NSMenuItem) {
        config.model = sender.title
        config.save()
        rebuildModelMenu()
    }

    private func refreshModels() {
        guard let url = URL(string: config.host + "/api/tags") else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self = self, let data = data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let arr = obj["models"] as? [[String: Any]] else { return }
            let names = arr.compactMap { $0["name"] as? String }
                .filter { !$0.lowercased().contains("embed") }   // drop embedding models
                .sorted()
            DispatchQueue.main.async {
                self.models = names
                // if saved model is gone, fall back to first available
                if !names.isEmpty && !names.contains(self.config.model) {
                    self.config.model = names.first!
                    self.config.save()
                }
                self.rebuildModelMenu()
            }
        }.resume()
    }

    private func header(_ s: String) -> NSMenuItem {
        let i = NSMenuItem(title: s, action: nil, keyEquivalent: "")
        i.isEnabled = false
        return i
    }
    private func item(_ s: String, action: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: s, action: action, keyEquivalent: "")
        i.target = self
        return i
    }

    private func setupHotKeys() {
        hotKeys = HotKeys { [weak self] id in
            guard let self = self else { return }
            let mode: Mode = id == 1 ? .translate : (id == 2 ? .explain : .detail)
            self.triggerFromSelection(mode)
        }
        hotKeys.register(id: 1, keyCode: key1, mods: ctrl | opt)
        hotKeys.register(id: 2, keyCode: key2, mods: ctrl | opt)
        hotKeys.register(id: 3, keyCode: key3, mods: ctrl | opt)
    }

    // Menu bar path: act on whatever is already on the clipboard.
    @objc private func menuTranslate() { runFromClipboard(.translate) }
    @objc private func menuExplain()   { runFromClipboard(.explain) }
    @objc private func menuDetail()    { runFromClipboard(.detail) }

    private func runFromClipboard(_ mode: Mode) {
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ResultPanel.shared.showMessage("클립보드가 비어 있어요.\n텍스트를 선택하고 ⌘C 로 복사한 뒤 다시 시도하세요.")
        } else {
            ResultPanel.shared.start(mode: mode, text: text, config: config)
        }
    }

    // Hot-key path: auto-copy current selection (⌘C), then read clipboard.
    private func triggerFromSelection(_ mode: Mode) {
        if !AXIsProcessTrusted() {
            // trigger the system prompt + show guidance
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(opts)
            ResultPanel.shared.showMessage("손쉬운 사용(Accessibility) 권한이 필요해요.\n시스템 설정 ▸ 개인정보 보호 및 보안 ▸ 손쉬운 사용 에서 LLMHelper 를 켠 뒤 다시 시도하세요.\n\n(권한 없이 쓰려면: 텍스트 ⌘C 후 메뉴바 ✨ 아이콘에서 실행)")
            return
        }
        let before = NSPasteboard.general.changeCount
        simulateCmdC()
        pollClipboard(since: before, attempts: 8, mode: mode)
    }

    // Poll up to ~0.64s for ⌘C to land on the clipboard (apps vary in speed).
    private func pollClipboard(since before: Int, attempts: Int, mode: Mode) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self = self else { return }
            let pb = NSPasteboard.general
            let text = pb.string(forType: .string) ?? ""
            let changed = pb.changeCount != before
            if changed && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ResultPanel.shared.start(mode: mode, text: text, config: self.config)
            } else if attempts > 1 {
                self.pollClipboard(since: before, attempts: attempts - 1, mode: mode)
            } else if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // clipboard didn't change (no selection?), fall back to existing content
                ResultPanel.shared.start(mode: mode, text: text, config: self.config)
            } else {
                ResultPanel.shared.showMessage("선택된 텍스트를 못 읽었어요.\n텍스트를 선택한 상태에서 단축키를 누르거나, ⌘C 로 복사 후 메뉴바 ✨ 에서 실행하세요.")
            }
        }
    }

    private func simulateCmdC() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let cKey: CGKeyCode = 8 // 'c'
        let down = CGEvent(keyboardEventSource: src, virtualKey: cKey, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: src, virtualKey: cKey, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
