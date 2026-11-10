import AppKit

@main
struct AppTests {
    static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("niuma-app-test-" + UUID().uuidString)
        let store = SettingsStore(directory: directory)
        let controller = AppController(store: store)
        defer {
            controller.shutdown()
            try? FileManager.default.removeItem(at: directory)
        }
        controller.start()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        func check(_ condition: Bool, _ message: String) {
            guard condition else { fatalError("FAIL: \(message)") }
        }
        check(controller.panel.isVisible, "main panel visible")
        check(controller.panel.level == .floating, "floating panel")
        controller.toggleMini(nil)
        check(controller.settings.mini && controller.panel.frame.height < 150, "mini action changes actual window")
        controller.toggleMini(nil)
        check(!controller.settings.mini && controller.panel.frame.height > 200, "full mode restored")
        controller.toggleMask(nil)
        check(controller.panel.mainView.amount.isHidden, "privacy removes actual amount view")
        check(controller.panel.mainView.visibleSalaryText.allSatisfy { !$0.contains("¥100") && !$0.contains("11.11") }, "privacy covers related salary fields")
        controller.toggleClickThrough(nil)
        check(controller.panel.ignoresMouseEvents, "click-through enabled")
        controller.openSettings(nil)
        guard let editor = controller.settingsWindow else { fatalError("missing settings window") }
        func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
        editor.window!.contentView!.layoutSubtreeIfNeeded()
        let sliders = descendants(editor.window!.contentView!).compactMap { $0 as? NSSlider }
        check(sliders.count == 4 && sliders.allSatisfy { $0.frame.width > 200 }, "all setting sliders have usable tracks")
        check(editor.fields["bgPath"]!.frame.width > 200, "background path field remains visible")
        check(!editor.window!.ignoresMouseEvents, "settings stays clickable during click-through")
        editor.fields["amount"]!.stringValue = "not a number"
        check(!editor.saveDraft(), "invalid settings rejected")
        check(controller.settings.amount == 100, "invalid settings don't affect live salary")
        editor.fields["amount"]!.stringValue = "999"
        editor.close()
        let cancelled = try store.load()
        check(controller.settings.amount == 100 && cancelled.amount == 100, "cancel preserves both live and saved settings")
        controller.openSettings(nil)
        controller.settingsWindow!.fields["amount"]!.stringValue = "222"
        check(controller.settingsWindow!.saveDraft(), "valid settings save")
        let saved = try store.load()
        check(controller.settings.amount == 222 && saved.amount == 222, "save applies and persists")
        check(controller.settings.masked && controller.settings.clickThrough, "saving retains runtime toggles")
        controller.toggleClickThrough(nil)
        check(!controller.panel.ignoresMouseEvents, "menu can recover click-through")
        controller.toggleVisible(nil)
        check(!controller.panel.isVisible, "hide action")
        controller.toggleVisible(nil)
        check(controller.panel.isVisible, "menu restores hidden panel")
        controller.resetPosition(nil)
        check(NSScreen.screens.contains { $0.visibleFrame.contains(controller.panel.frame) }, "panel kept within screen")
        check(controller.makeMenu().items.contains { $0.action == #selector(AppController.toggleClickThrough(_:)) }, "recovery action present in menu")
        controller.shutdown()
        let area = NSScreen.main!.visibleFrame
        for mini in [true, false] {
            var restored = try store.load()
            restored.mini = mini
            restored.windowX = area.minX + 60
            restored.windowY = area.minY + 36
            try store.save(restored)
            let reopened = AppController(store: store)
            reopened.start()
            defer { reopened.shutdown() }
            check(abs(reopened.panel.frame.minX - restored.windowX!) < 1 && abs(reopened.panel.frame.minY - restored.windowY!) < 1,
                  "relaunch preserves saved origin in \(mini ? "mini" : "full") mode")
        }
        print("PASS: native window, mini, privacy, click-through, settings validation/save/cancel, visibility, screen and menu checks")
    }
}
