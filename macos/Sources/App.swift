import AppKit
import Carbon
import ServiceManagement
import UserNotifications

final class HotKeys {
    private var handler: EventHandlerRef?
    private var registrations: [EventHotKeyRef] = []
    var action: ((UInt32) -> Void)?

    func register() -> [String] {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event = event, let context = context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard status == noErr else { return status }
            Unmanaged<HotKeys>.fromOpaque(context).takeUnretainedValue().action?(identifier.id)
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else { return ["全局快捷键注册失败（\(status)）"] }
        var failures: [String] = []
        for (id, key, label) in [(UInt32(1), kVK_ANSI_M, "⌃⌥M"), (2, kVK_ANSI_H, "⌃⌥H"), (3, kVK_ANSI_T, "⌃⌥T")] {
            var reference: EventHotKeyRef?
            let result = RegisterEventHotKey(UInt32(key), UInt32(controlKey | optionKey),
                                            EventHotKeyID(signature: 0x4E49554D, id: id), GetApplicationEventTarget(), 0, &reference)
            if result == noErr, let reference = reference { registrations.append(reference) }
            else { failures.append("\(label) 被占用或无法注册（\(result)）") }
        }
        return failures
    }

    func unregister() {
        registrations.forEach { UnregisterEventHotKey($0) }
        registrations.removeAll()
        if let handler = handler { RemoveEventHandler(handler) }
        handler = nil
    }
    deinit { unregister() }
}

final class AppController: NSObject, NSApplicationDelegate, NSMenuDelegate, UNUserNotificationCenterDelegate {
    let store: SettingsStore
    private(set) var settings = AppSettings()
    let panel = MainPanel()
    var settingsWindow: SettingsWindow?
    private var statusItem: NSStatusItem?
    private let hotkeys = HotKeys()
    private var tickTimer: Timer?
    private var animationTimer: Timer?
    private var lastState: WorkState?
    private var loadError: Error?
    private var observers: [NSObjectProtocol] = []
    private var failures: [String] = []
    private var isShuttingDown = false
    private var reportCopiedUntil = Date.distantPast

    init(store: SettingsStore = SettingsStore()) { self.store = store; super.init() }

    func applicationDidFinishLaunching(_ notification: Notification) { start() }

    func start() {
        let firstLaunch = !FileManager.default.fileExists(atPath: store.fileURL.path)
        do { settings = try store.load() } catch { loadError = error }
        panel.mainView.configureActions(target: self)
        panel.mainView.makeMenu = { [weak self] in self?.makeMenu() ?? NSMenu() }
        panel.mainView.toggleMini = { [weak self] in self?.toggleMini(nil) }
        panel.mainView.didDrag = { [weak self] in
            guard let self = self else { return }
            self.panel.apply(self.settings); self.panel.keepOnScreen(snap: true); self.savePosition()
        }
        if let x = settings.windowX, let y = settings.windowY { panel.setFrameOrigin(NSPoint(x: x, y: y)) }
        panel.apply(settings)
        if let x = settings.windowX, let y = settings.windowY {
            panel.setFrameOrigin(NSPoint(x: x, y: y)); panel.keepOnScreen()
        } else { resetPosition(nil) }
        panel.orderFrontRegardless()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "banknote", accessibilityDescription: settings.appName)
        item.button?.toolTip = settings.appName + " · 点击恢复窗口或关闭穿透"
        let menu = NSMenu(); menu.delegate = self; item.menu = menu
        statusItem = item
        installAppMenu()
        if settings.offWorkNotify { UNUserNotificationCenter.current().delegate = self }
        hotkeys.action = { [weak self] id in
            switch id {
            case 1: self?.toggleVisible(nil)
            case 2: self?.toggleMask(nil)
            case 3: self?.toggleClickThrough(nil)
            default: break
            }
        }
        failures = hotkeys.register()
        tick()
        tickTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        animationTimer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            guard let self = self, self.panel.isVisible, !self.settings.masked,
                  self.settings.odometer, self.lastState == .working || self.lastState == .overtime else { return }
            self.panel.mainView.updateAmount(Engine().compute(self.settings, at: Date()))
        }
        if let timer = tickTimer { RunLoop.main.add(timer, forMode: .common) }
        if let timer = animationTimer { RunLoop.main.add(timer, forMode: .common) }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            self.panel.apply(self.settings)
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification,
                                                                           object: nil, queue: .main) { [weak self] _ in self?.tick() })
        if let error = loadError {
            DispatchQueue.main.async { [weak self] in
                self?.showError("无法读取已有设置", "\(error.localizedDescription)\n暂用默认配置，原文件不会被自动覆盖。在设置中保存时会先保留原文件备份。")
            }
        } else if firstLaunch {
            openSettings(nil)
        }
    }

    private func tick() {
        let now = Date(), engine = Engine(), snapshot = engine.compute(settings, at: now)
        let copied = now < reportCopiedUntil
        statusItem?.button?.image = NSImage(systemSymbolName: copied ? "checkmark.circle.fill" : "banknote",
                                          accessibilityDescription: copied ? "战报已复制" : settings.appName)
        statusItem?.button?.toolTip = copied ? "战报已复制" : settings.appName + " · 点击恢复窗口或关闭穿透"
        panel.mainView.setReportCopied(copied)
        if panel.isVisible { panel.mainView.update(snapshot, engine: engine, at: now) }
        if let previous = lastState, previous != snapshot.state, settings.offWorkNotify {
            if snapshot.state == .afterWork || (snapshot.state == .overtime && previous == .working) {
                notify("下班啦！", text: settings.masked ? "牛马可以下线了。" : "今天赚到 \(settings.currency)\(String(format: "%.2f", snapshot.earned))，牛马可以下线了。")
            } else if snapshot.state == .working && previous == .beforeWork {
                notify("开始计薪", text: "新的一天，钱开始到账了。")
            }
        }
        lastState = snapshot.state
    }

    private func persist() {
        guard loadError == nil else { return }
        do { try store.save(settings) } catch { showError("设置未能保存", error.localizedDescription) }
    }

    private func change(_ update: (inout AppSettings) -> Void) {
        update(&settings)
        panel.apply(settings); tick(); persist()
    }

    @objc func toggleVisible(_ sender: Any?) {
        if panel.isVisible { savePosition(); panel.orderOut(nil) }
        else { panel.keepOnScreen(); panel.orderFrontRegardless(); tick() }
    }
    @objc func toggleMini(_ sender: Any?) { change { $0.mini.toggle() }; savePosition() }
    @objc func toggleMask(_ sender: Any?) { change { $0.masked.toggle() } }
    @objc func toggleTopmost(_ sender: Any?) { change { $0.topmost.toggle() } }
    @objc func toggleClickThrough(_ sender: Any?) { change { $0.clickThrough.toggle() } }
    @objc func resetPosition(_ sender: Any?) {
        guard let area = NSScreen.main?.visibleFrame else { return }
        panel.setFrameOrigin(NSPoint(x: area.maxX - panel.frame.width - 24, y: area.maxY - panel.frame.height - 36))
        panel.keepOnScreen()
    }
    private func savePosition() {
        settings.windowX = panel.frame.minX; settings.windowY = panel.frame.minY; persist()
    }

    @objc func openSettings(_ sender: Any?) {
        if settingsWindow == nil {
            let editor = SettingsWindow(settings: settings) { [weak self] draft, autoStart in
                guard let self = self else { return }
                var draft = draft
                draft.mini = self.settings.mini; draft.masked = self.settings.masked
                draft.clickThrough = self.settings.clickThrough
                draft.windowX = self.panel.frame.minX; draft.windowY = self.panel.frame.minY
                draft.overrideDate = self.settings.overrideDate; draft.overrideMode = self.settings.overrideMode
                if self.loadError != nil, FileManager.default.fileExists(atPath: self.store.fileURL.path) {
                    let backup = self.store.directory.appendingPathComponent("settings.invalid-\(UUID().uuidString).json")
                    try FileManager.default.copyItem(at: self.store.fileURL, to: backup)
                }
                let service = SMAppService.mainApp
                let wasEnabled = service.status == .enabled
                if autoStart != wasEnabled {
                    do {
                        if autoStart { try service.register() } else { try service.unregister() }
                    } catch { throw SettingsError(message: "登录启动设置失败：\(error.localizedDescription)。请先将应用移至「应用程序」，并检查系统登录项。") }
                }
                do { try self.store.save(draft) }
                catch {
                    if autoStart != wasEnabled {
                        do { if wasEnabled { try service.register() } else { try service.unregister() } }
                        catch { NSLog("恢复登录启动状态失败：%@", error.localizedDescription) }
                    }
                    throw error
                }
                let enableNotifications = draft.offWorkNotify && !self.settings.offWorkNotify
                self.loadError = nil; self.settings = draft
                self.panel.apply(draft); self.tick()
                self.statusItem?.button?.toolTip = draft.appName
                if enableNotifications { self.requestNotifications() }
            }
            editor.onClose = { [weak self] in self?.settingsWindow = nil }
            settingsWindow = editor
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.showWindow(nil); settingsWindow?.window?.makeKeyAndOrderFront(nil)
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu(title: settings.appName)
        func add(_ title: String, _ action: Selector, checked: Bool? = nil) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            if let checked = checked { item.state = checked ? .on : .off }
            menu.addItem(item)
        }
        add(panel.isVisible ? "隐藏窗口  ⌃⌥M" : "显示窗口  ⌃⌥M", #selector(toggleVisible(_:)))
        add("设置…", #selector(openSettings(_:)))
        menu.addItem(.separator())
        add("迷你模式", #selector(toggleMini(_:)), checked: settings.mini)
        add("隐藏全部金额  ⌃⌥H", #selector(toggleMask(_:)), checked: settings.masked)
        add("窗口置顶", #selector(toggleTopmost(_:)), checked: settings.topmost)
        add("鼠标穿透  ⌃⌥T", #selector(toggleClickThrough(_:)), checked: settings.clickThrough)
        add("将窗口移回主屏幕", #selector(resetPosition(_:)))
        menu.addItem(.separator())
        add("今天请假 / 休息", #selector(restToday(_:)), checked: settings.overrideMode == 1 && settings.overrideDate == Engine().dateKey(Date()))
        add("今天补班", #selector(workToday(_:)), checked: settings.overrideMode == 2 && settings.overrideDate == Engine().dateKey(Date()))
        add("恢复正常作息", #selector(clearOverride(_:)))
        add("复制今日战报", #selector(copyReport(_:)))
        if !failures.isEmpty {
            menu.addItem(.separator())
            for failure in failures { let item = NSMenuItem(title: failure, action: nil, keyEquivalent: ""); item.isEnabled = false; menu.addItem(item) }
        }
        menu.addItem(.separator())
        add("退出 " + settings.appName, #selector(quit(_:)))
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let updated = makeMenu()
        for item in updated.items { updated.removeItem(item); menu.addItem(item) }
    }
    @objc private func restToday(_ sender: Any?) { change { $0.overrideDate = Engine().dateKey(Date()); $0.overrideMode = 1 } }
    @objc private func workToday(_ sender: Any?) { change { $0.overrideDate = Engine().dateKey(Date()); $0.overrideMode = 2 } }
    @objc private func clearOverride(_ sender: Any?) { change { $0.overrideDate = ""; $0.overrideMode = 0 } }
    @objc func copyReport(_ sender: Any?) {
        NSPasteboard.general.clearContents()
        if NSPasteboard.general.setString(Engine().report(settings, at: Date()), forType: .string) {
            reportCopiedUntil = Date().addingTimeInterval(3)
            tick()
        } else {
            showError("战报未能复制", "请稍后再试。")
        }
    }
    @objc private func quit(_ sender: Any?) { NSApp.terminate(nil) }

    private func installAppMenu() {
        let main = NSMenu(), appItem = NSMenuItem(), appMenu = NSMenu()
        main.addItem(appItem); appItem.submenu = appMenu
        let settingsItem = NSMenuItem(title: "设置…", action: #selector(openSettings(_:)), keyEquivalent: ",")
        settingsItem.target = self; appMenu.addItem(settingsItem)
        let quit = NSMenuItem(title: "退出", action: #selector(quit(_:)), keyEquivalent: "q")
        quit.target = self; appMenu.addItem(quit)
        let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: ""), edit = NSMenu(title: "编辑")
        editItem.submenu = edit; main.addItem(editItem)
        for (title, action, key) in [("剪切", #selector(NSText.cut(_:)), "x"), ("复制", #selector(NSText.copy(_:)), "c"),
                                    ("粘贴", #selector(NSText.paste(_:)), "v"), ("全选", #selector(NSText.selectAll(_:)), "a")] {
            edit.addItem(NSMenuItem(title: title, action: action, keyEquivalent: key))
        }
        NSApp.mainMenu = main
    }

    private func requestNotifications() {
        let center = UNUserNotificationCenter.current(); center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            if !granted {
                DispatchQueue.main.async { self?.showError("通知尚未启用", error?.localizedDescription ?? "请到系统设置 → 通知中允许牛马脱敏器发送提醒。") }
            }
        }
    }
    private func notify(_ title: String, text: String) {
        let content = UNMutableNotificationContent(); content.title = title; content.body = text
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "work-state", content: content, trigger: nil)) { error in
            if let error = error { NSLog("通知发送失败：%@", error.localizedDescription) }
        }
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
    private func showError(_ title: String, _ text: String) {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = text
        alert.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true); alert.runModal()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panel.orderFrontRegardless(); tick(); return true
    }
    func shutdown() {
        guard !isShuttingDown else { return }; isShuttingDown = true
        savePosition()
        tickTimer?.invalidate(); animationTimer?.invalidate()
        tickTimer = nil; animationTimer = nil
        hotkeys.unregister()
        observers.forEach { NotificationCenter.default.removeObserver($0); NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
        settingsWindow?.onClose = nil; settingsWindow?.close(); settingsWindow = nil
        panel.orderOut(nil); panel.close()
        if let item = statusItem { NSStatusBar.system.removeStatusItem(item) }; statusItem = nil
    }
    func applicationWillTerminate(_ notification: Notification) { shutdown() }
}

#if !APP_TESTS
@main
enum NiuMa {
    static func main() {
        let app = NSApplication.shared
        if let identifier = Bundle.main.bundleIdentifier,
           let existing = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            existing.activate(options: [.activateIgnoringOtherApps])
            NSWorkspace.shared.openApplication(at: existing.bundleURL!, configuration: NSWorkspace.OpenConfiguration())
            return
        }
        app.setActivationPolicy(.accessory)
        let controller = AppController()
        app.delegate = controller
        withExtendedLifetime(controller) { app.run() }
    }
}
#endif
