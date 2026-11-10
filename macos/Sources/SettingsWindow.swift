import AppKit
import ServiceManagement
import UniformTypeIdentifiers

private final class FlippedForm: NSView { override var isFlipped: Bool { true } }

final class SettingsWindow: NSWindowController, NSWindowDelegate {
    private var original: AppSettings
    private let onSave: (AppSettings, Bool) throws -> Void
    var onClose: (() -> Void)?
    private(set) var fields: [String: NSTextField] = [:]
    private var checks: [String: NSButton] = [:]
    private var sliders: [String: NSSlider] = [:]
    private var workdays: [NSButton] = []
    private var texts: [String: NSTextView] = [:]
    private let salaryMode = NSPopUpButton()
    private let decimals = NSPopUpButton()
    private let errorLabel = Theme.label(12, color: .systemRed)
    private let preview = Theme.label(12, color: Theme.blue)
    private let form = FlippedForm()
    private var cursor = 18.0
    private let formWidth = 680.0

    init(settings: AppSettings, onSave: @escaping (AppSettings, Bool) throws -> Void) {
        original = settings; self.onSave = onSave
        let area = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: formWidth, height: min(760, area.height - 64)),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "设置 · " + settings.appName
        window.isReleasedWhenClosed = false; window.delegate = self
        window.appearance = NSAppearance(named: .aqua)
        window.level = .floating
        window.center()
        build()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func field(_ key: String, _ value: String, width: CGFloat? = nil) -> NSTextField {
        let field = NSTextField(string: value)
        field.font = .systemFont(ofSize: 13)
        field.setAccessibilityLabel(["appName": "软件名称", "amount": "薪资金额", "currency": "货币符号",
                                     "monthDays": "月计薪天数", "startTime": "上班时间", "endTime": "下班时间",
                                     "lunchStart": "午休开始", "lunchEnd": "午休结束", "overtimeRate": "加班倍率",
                                     "payDay": "发薪日", "bgPath": "背景图片路径"][key] ?? key)
        field.target = self; field.action = #selector(updatePreview(_:))
        fields[key] = field
        if let width = width { field.widthAnchor.constraint(equalToConstant: width).isActive = true }
        return field
    }

    private func check(_ key: String, _ title: String, _ value: Bool) -> NSButton {
        let button = NSButton(checkboxWithTitle: title, target: self, action: #selector(updatePreview(_:)))
        button.state = value ? .on : .off; checks[key] = button
        return button
    }

    private func horizontal(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal; stack.alignment = .centerY; stack.spacing = 8
        return stack
    }

    private func section(_ title: String) {
        let label = Theme.label(15, color: Theme.green, bold: true)
        label.stringValue = title
        label.frame = NSRect(x: 24, y: cursor + 10, width: 610, height: 24)
        form.addSubview(label); cursor += 45
    }

    private func row(_ title: String, _ control: NSView, height: Double = 30, detail: String? = nil) {
        let label = Theme.label(13)
        label.stringValue = title
        label.frame = NSRect(x: 24, y: cursor + 3, width: 112, height: 24)
        form.addSubview(label)
        control.frame = NSRect(x: 146, y: cursor, width: formWidth - 174, height: height)
        control.setAccessibilityLabel(title)
        form.addSubview(control)
        cursor += height + 10
        if let detail = detail {
            let hint = Theme.label(11, color: Theme.muted)
            hint.stringValue = detail
            hint.frame = NSRect(x: 146, y: cursor - 4, width: formWidth - 174, height: 30)
            form.addSubview(hint); cursor += 30
        }
    }

    private func slider(_ key: String, _ value: Double, _ min: Double, _ max: Double) -> NSView {
        let slider = NSSlider(value: value, minValue: min, maxValue: max, target: self, action: #selector(updatePreview(_:)))
        slider.widthAnchor.constraint(equalToConstant: formWidth - 234).isActive = true
        slider.setAccessibilityLabel(["bgOpacity": "背景图透明度", "panelOpacity": "信息卡底色",
                                      "windowOpacity": "整体透明度", "uiZoom": "界面大小"][key])
        sliders[key] = slider
        let label = Theme.label(12, color: Theme.muted)
        label.identifier = NSUserInterfaceItemIdentifier(key + "Value")
        label.stringValue = String(format: "%.0f%%", value * 100)
        label.widthAnchor.constraint(equalToConstant: 52).isActive = true
        return horizontal([slider, label])
    }

    private func editor(_ key: String, _ content: String) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: formWidth - 194, height: 100))
        text.isRichText = false; text.font = .systemFont(ofSize: 13)
        text.string = content; text.isHorizontallyResizable = false; text.isVerticallyResizable = true
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        text.setAccessibilityLabel(key == "wishlist" ? "心愿单，每行名称等于价格" : "鼓励语录，每行一句")
        scroll.documentView = text; texts[key] = text
        return scroll
    }

    private func build() {
        guard let root = window?.contentView else { return }
        let s = original
        section("薪资与作息")
        row("软件名称", field("appName", s.appName))
        salaryMode.removeAllItems()
        salaryMode.addItems(withTitles: ["日薪", "月薪"])
        salaryMode.selectItem(at: s.salaryMode)
        salaryMode.target = self; salaryMode.action = #selector(updatePreview(_:))
        row("薪资", horizontal([salaryMode, field("amount", String(s.amount), width: 125),
                                ThemeLabel("货币"), field("currency", s.currency, width: 62)]))
        row("月计薪天数", field("monthDays", String(s.monthDays)), detail: "月薪 ÷ 计薪天数 = 日薪；不按自然月的工作日重新分摊。")
        row("上下班时间", horizontal([field("startTime", s.startTime, width: 92), ThemeLabel("至"),
                                    field("endTime", s.endTime, width: 92)]))
        row("午休", horizontal([check("lunchEnabled", "暂停计薪", s.lunchEnabled),
                                field("lunchStart", s.lunchStart, width: 82), ThemeLabel("至"),
                                field("lunchEnd", s.lunchEnd, width: 82)]))
        let names = ["日", "一", "二", "三", "四", "五", "六"]
        for index in 0...6 {
            let button = NSButton(checkboxWithTitle: names[index], target: nil, action: nil)
            button.state = s.workDays.contains(index) ? .on : .off
            button.setAccessibilityLabel("星期" + names[index])
            workdays.append(button)
        }
        row("每周工作日", horizontal(workdays))
        row("加班", horizontal([check("overtime", "下班后继续计薪", s.overtime), ThemeLabel("倍率"),
                                field("overtimeRate", String(s.overtimeRate), width: 76)]))
        row("每月发薪日", field("payDay", String(s.payDay)), detail: "1～31 号；当月没有该日期时按当月最后一天计算。")
        row("计算预览", preview, height: 44)
        section("显示")
        decimals.removeAllItems()
        decimals.addItems(withTitles: ["2 位", "3 位", "4 位", "5 位", "6 位"])
        decimals.selectItem(at: s.decimals - 2)
        row("小数位数", decimals)
        row("数字样式", check("odometer", "滚轮翻牌（系统减少动态效果时自动停用）", s.odometer))
        row("背景图透明度", slider("bgOpacity", s.bgOpacity, 0, 1))
        row("信息卡底色", slider("panelOpacity", s.panelOpacity, 0, 1))
        row("整体透明度", slider("windowOpacity", s.windowOpacity, 0.2, 1))
        row("界面大小", slider("uiZoom", s.uiZoom, 0.5, 2), detail: "100% 按当前屏幕自动适配；保存后应用。")
        let background = field("bgPath", s.bgPath, width: 330)
        background.isEditable = false
        background.lineBreakMode = .byTruncatingMiddle
        let choose = NSButton(title: "选择…", target: self, action: #selector(chooseBackground(_:)))
        let reset = NSButton(title: "默认", target: self, action: #selector(resetBackground(_:)))
        row("背景图片", horizontal([background, choose, reset]))
        row("悬浮窗口", check("topmost", "窗口始终置顶", s.topmost))
        section("其他")
        row("通知", check("offWorkNotify", "上下班提醒（启用后请求系统通知权限）", s.offWorkNotify))
        row("登录启动", check("autoStart", "登录 Mac 后自动启动", SMAppService.mainApp.status == .enabled),
            detail: "建议先将应用移至「应用程序」。若系统要求批准，请到系统设置 → 通用 → 登录项。")
        row("心愿单", editor("wishlist", s.wishlist), height: 110, detail: "每行一个：名称=价格；忽略格式错误、非正数价格。")
        row("鼓励语录", editor("quotes", s.quotes), height: 110, detail: "每行一句，每 10 分钟轮换；点击主窗口语录手动更换。")
        let keys = Theme.label(12, color: Theme.muted)
        keys.stringValue = "⌃⌥M 显示/隐藏　⌃⌥H 隐藏金额　⌃⌥T 鼠标穿透\n双击切换迷你模式，右键打开菜单。穿透后从菜单栏恢复。"
        row("快捷键", keys, height: 48)
        form.frame = NSRect(x: 0, y: 0, width: formWidth, height: cursor + 12)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 82, width: formWidth, height: root.bounds.height - 82))
        scroll.hasVerticalScroller = true; scroll.documentView = form
        scroll.contentView.scroll(to: .zero)
        root.addSubview(scroll)
        errorLabel.frame = NSRect(x: 24, y: 10, width: 632, height: 29)
        root.addSubview(errorLabel)
        let restore = NSButton(title: "恢复默认", target: self, action: #selector(restoreDefaults(_:)))
        restore.frame = NSRect(x: 20, y: 43, width: 100, height: 28)
        let cancel = NSButton(title: "取消", target: self, action: #selector(cancel(_:)))
        cancel.frame = NSRect(x: 470, y: 43, width: 90, height: 28); cancel.keyEquivalent = "\u{1b}"
        let save = NSButton(title: "保存", target: self, action: #selector(save(_:)))
        save.frame = NSRect(x: 566, y: 43, width: 90, height: 28); save.keyEquivalent = "\r"
        for button in [restore, cancel, save] { button.bezelStyle = .rounded; root.addSubview(button) }
        updatePreview(nil)
    }

    private func collect() throws -> AppSettings {
        var result = original
        func number(_ key: String, _ name: String) throws -> Double {
            guard let text = fields[key]?.stringValue.trimmingCharacters(in: .whitespaces), let value = Double(text), value.isFinite else {
                throw SettingsError(message: name + "应为有效数字")
            }
            return value
        }
        result.appName = fields["appName"]!.stringValue
        result.salaryMode = salaryMode.indexOfSelectedItem
        result.amount = try number("amount", "薪资")
        result.monthDays = try number("monthDays", "计薪天数")
        result.currency = fields["currency"]!.stringValue
        result.startTime = fields["startTime"]!.stringValue; result.endTime = fields["endTime"]!.stringValue
        result.lunchEnabled = checks["lunchEnabled"]!.state == .on
        result.lunchStart = fields["lunchStart"]!.stringValue; result.lunchEnd = fields["lunchEnd"]!.stringValue
        result.workDays = workdays.enumerated().compactMap { $0.element.state == .on ? $0.offset : nil }
        result.overtime = checks["overtime"]!.state == .on
        result.overtimeRate = try number("overtimeRate", "加班倍率")
        guard let payday = Int(fields["payDay"]!.stringValue) else { throw SettingsError(message: "发薪日应为整数") }
        result.payDay = payday; result.decimals = decimals.indexOfSelectedItem + 2
        result.odometer = checks["odometer"]!.state == .on
        result.bgOpacity = sliders["bgOpacity"]!.doubleValue
        result.panelOpacity = sliders["panelOpacity"]!.doubleValue
        result.windowOpacity = sliders["windowOpacity"]!.doubleValue
        result.uiZoom = sliders["uiZoom"]!.doubleValue
        result.bgPath = fields["bgPath"]!.stringValue
        result.topmost = checks["topmost"]!.state == .on
        result.offWorkNotify = checks["offWorkNotify"]!.state == .on
        result.wishlist = texts["wishlist"]!.string; result.quotes = texts["quotes"]!.string
        if !result.bgPath.isEmpty && NSImage(contentsOfFile: result.bgPath) == nil { throw SettingsError(message: "背景图片不存在或无法读取，请重新选择") }
        return try result.validated()
    }

    @objc private func updatePreview(_ sender: Any?) {
        for (key, slider) in sliders {
            (slider.superview?.subviews.first { $0.identifier?.rawValue == key + "Value" } as? NSTextField)?.stringValue = String(format: "%.0f%%", slider.doubleValue * 100)
        }
        guard let settings = try? collect() else { preview.stringValue = "保存前请检查薪资与作息格式。"; return }
        let snapshot = Engine().compute(settings, at: Date())
        preview.stringValue = String(format: "日薪 %@%.2f · 每天计薪 %.2f 小时\n时薪 %@%.2f · 每秒 %@%.6f",
                                     settings.currency, settings.dailyPay, snapshot.paidSeconds / 3600,
                                     settings.currency, snapshot.hourlyPay, settings.currency, snapshot.hourlyPay / 3600)
    }

    @discardableResult func saveDraft() -> Bool {
        do {
            try onSave(collect(), checks["autoStart"]!.state == .on)
            close(); return true
        } catch { errorLabel.stringValue = error.localizedDescription; return false }
    }
    @objc private func save(_ sender: Any?) { saveDraft() }
    @objc private func cancel(_ sender: Any?) { close() }
    @objc private func chooseBackground(_ sender: Any?) {
        let dialog = NSOpenPanel()
        dialog.allowedContentTypes = [.png, .jpeg, .tiff, .gif, .bmp]
        dialog.allowsMultipleSelection = false; dialog.canChooseDirectories = false
        guard let window = window else { return }
        dialog.beginSheetModal(for: window) { [weak self] response in
            if response == .OK { self?.fields["bgPath"]?.stringValue = dialog.url?.path ?? "" }
        }
    }
    @objc private func resetBackground(_ sender: Any?) { fields["bgPath"]?.stringValue = "" }
    @objc private func restoreDefaults(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "恢复默认设置？"; alert.informativeText = "保存后生效；关闭设置窗口会放弃修改。"
        alert.addButton(withTitle: "恢复默认"); alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        window?.contentView?.subviews.forEach { $0.removeFromSuperview() }
        form.subviews.forEach { $0.removeFromSuperview() }; cursor = 18
        fields.removeAll(); checks.removeAll(); sliders.removeAll(); texts.removeAll(); workdays.removeAll()
        original = AppSettings()
        build()
    }
    func windowWillClose(_ notification: Notification) { onClose?() }
}

private func ThemeLabel(_ value: String) -> NSTextField {
    let label = Theme.label(12, color: Theme.muted)
    label.stringValue = value
    label.setContentHuggingPriority(.required, for: .horizontal)
    return label
}
