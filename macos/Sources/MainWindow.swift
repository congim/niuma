import AppKit

enum Theme {
    static let ink = NSColor(srgbRed: 0.20, green: 0.22, blue: 0.18, alpha: 1)
    static let muted = NSColor(srgbRed: 0.41, green: 0.42, blue: 0.35, alpha: 1)
    static let paper = NSColor(srgbRed: 0.98, green: 0.96, blue: 0.88, alpha: 1)
    static let orange = NSColor(srgbRed: 0.80, green: 0.33, blue: 0.12, alpha: 1)
    static let green = NSColor(srgbRed: 0.33, green: 0.46, blue: 0.22, alpha: 1)
    static let blue = NSColor(srgbRed: 0.24, green: 0.39, blue: 0.44, alpha: 1)

    static func label(_ size: CGFloat, color: NSColor = ink, bold: Bool = false) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: "")
        label.font = .systemFont(ofSize: size, weight: bold ? .semibold : .regular)
        label.textColor = color
        label.maximumNumberOfLines = 3
        return label
    }
}

final class OdometerView: NSView {
    var settings = AppSettings()
    var value = 0.0
    var speed = 0.0
    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel("今日已赚")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        guard !settings.masked else { return }
        let text = String(format: "%.*f", settings.decimals, max(0, value))
        let digits = DigitRoller.offsets(value: value, decimals: settings.decimals, speed: speed)
        let content = settings.currency + " " + text
        let size = min(bounds.height * 0.76, bounds.width / max(1, CGFloat(content.count)) / 0.63)
        let font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .bold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: Theme.orange]
        let height = ceil(font.ascender - font.descender + 5)
        let digitWidth = ("0" as NSString).size(withAttributes: attributes).width
        let prefix = settings.currency + " "
        (prefix as NSString).draw(at: NSPoint(x: 0, y: 3), withAttributes: attributes)
        var x = (prefix as NSString).size(withAttributes: attributes).width
        if !settings.odometer || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            (text as NSString).draw(at: NSPoint(x: x, y: 3), withAttributes: attributes)
            return
        }
        let integerCount = digits.count - settings.decimals
        for (index, offset) in digits.enumerated() {
            if index == integerCount {
                ("." as NSString).draw(at: NSPoint(x: x, y: 3), withAttributes: attributes)
                x += ("." as NSString).size(withAttributes: attributes).width
            }
            NSGraphicsContext.saveGraphicsState()
            NSRect(x: x, y: 0, width: digitWidth, height: height).clip()
            let floorOffset = floor(offset)
            for position in 0...1 {
                let digit = Int(floorOffset + Double(position)) % 10
                let y = 3 + (CGFloat(floorOffset + Double(position) - offset) * height)
                (String(digit) as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: attributes)
            }
            NSGraphicsContext.restoreGraphicsState()
            x += digitWidth
        }
    }
}

final class MainView: NSView {
    let amount = OdometerView(frame: .zero)
    private var labels: [String: NSTextField] = [:]
    private var headerButtons: [NSButton] = []
    private let progress = NSProgressIndicator()
    private let quoteButton = NSButton()
    var settings = AppSettings()
    private var background: NSImage?
    private var backgroundPath: String?
    private var quoteIndex = 0
    private var quoteAt = Date.distantPast
    var makeMenu: (() -> NSMenu)?
    var toggleMini: (() -> Void)?
    var didDrag: (() -> Void)?
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    var visibleSalaryText: [String] {
        ["speed", "wish", "monthValue", "monthSub", "hourly", "mask"].compactMap { labels[$0]?.stringValue }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        appearance = NSAppearance(named: .aqua)
        addSubview(amount)
        progress.isIndeterminate = false
        progress.minValue = 0; progress.maxValue = 1
        progress.controlSize = .small
        progress.setAccessibilityLabel("今日计薪工时进度")
        addSubview(progress)
        quoteButton.isBordered = false
        quoteButton.target = self; quoteButton.action = #selector(nextQuote(_:))
        quoteButton.font = .systemFont(ofSize: 12)
        quoteButton.contentTintColor = Theme.green
        quoteButton.toolTip = "点击换一句"
        quoteButton.cell?.wraps = true
        addSubview(quoteButton)
        for (key, size, color, bold) in [
            ("title", 15.0, Theme.ink, true), ("clock", 12, Theme.muted, false),
            ("status", 25, Theme.blue, true), ("countdown", 13, Theme.ink, false),
            ("today", 12, Theme.muted, false), ("speed", 11, Theme.muted, false),
            ("wish", 13, Theme.ink, false), ("progress", 11, Theme.muted, false),
            ("hours", 11, Theme.muted, false), ("monthLabel", 13, Theme.ink, true),
            ("monthValue", 19, Theme.blue, true), ("monthSub", 11, Theme.muted, false),
            ("hourly", 12, Theme.muted, false), ("footer", 10, Theme.muted, false),
            ("mask", 36, Theme.orange, true)
        ] {
            let field = Theme.label(size, color: color, bold: bold)
            labels[key] = field; addSubview(field)
        }
        labels["monthValue"]?.alignment = .right
        labels["hours"]?.alignment = .right
        labels["footer"]?.alignment = .center
        labels["title"]?.maximumNumberOfLines = 1
        labels["title"]?.lineBreakMode = .byTruncatingTail
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configureActions(target: AnyObject) {
        for (symbol, help, action) in [
            ("eye.slash", "隐藏/显示全部金额 · ⌃⌥H", #selector(AppController.toggleMask(_:))),
            ("pin", "开关置顶", #selector(AppController.toggleTopmost(_:))),
            ("rectangle.compress.vertical", "迷你模式", #selector(AppController.toggleMini(_:))),
            ("gearshape", "设置", #selector(AppController.openSettings(_:))),
            ("minus", "隐藏到菜单栏 · ⌃⌥M", #selector(AppController.toggleVisible(_:)))
        ] {
            let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: help)!, target: target, action: action)
            button.bezelStyle = .inline; button.isBordered = false
            button.contentTintColor = Theme.muted; button.toolTip = help
            button.setAccessibilityLabel(help)
            addSubview(button); headerButtons.append(button)
        }
    }

    func apply(_ settings: AppSettings) {
        self.settings = settings
        amount.settings = settings
        if backgroundPath != settings.bgPath {
            backgroundPath = settings.bgPath
            background = settings.bgPath.isEmpty ? nil : NSImage(contentsOfFile: settings.bgPath)
            if background == nil, let url = Bundle.main.url(forResource: "beij", withExtension: "png") { background = NSImage(contentsOf: url) }
        }
        amount.isHidden = settings.masked
        labels["mask"]?.isHidden = !settings.masked
        labels["title"]?.stringValue = settings.appName
        labels["today"]?.stringValue = "今日已赚"
        labels["monthLabel"]?.stringValue = "本月累计"
        labels["footer"]?.stringValue = "双击切换迷你 · 右键菜单 · ⌃⌥M 显示 / 隐藏"
        for button in headerButtons { button.isHidden = settings.mini }
        progress.isHidden = settings.mini
        quoteButton.isHidden = settings.mini
        for (key, label) in labels where key != "mask" {
            label.isHidden = settings.mini && key != "status"
        }
        layoutContent()
        needsDisplay = true
    }

    func layoutContent() {
        func place(_ key: String, _ x: Double, _ y: Double, _ width: Double, _ height: Double) {
            labels[key]?.frame = NSRect(x: x, y: y, width: width, height: height)
        }
        if settings.mini {
            amount.frame = NSRect(x: 14, y: 9, width: 230, height: 38)
            place("mask", 14, 9, 225, 40)
            place("status", 254, 18, 88, 24)
            labels["status"]?.font = .systemFont(ofSize: 14, weight: .semibold)
            return
        }
        labels["status"]?.font = .systemFont(ofSize: 25, weight: .semibold)
        place("title", 20, 19, 177, 25)
        for (index, button) in headerButtons.enumerated() {
            button.frame = NSRect(x: 210 + index * 29, y: 17, width: 25, height: 26)
        }
        place("clock", 32, 72, 316, 18)
        place("status", 32, 99, 316, 33)
        place("countdown", 32, 137, 316, 21)
        place("today", 32, 171, 316, 17)
        amount.frame = NSRect(x: 32, y: 191, width: 316, height: 51)
        place("mask", 32, 191, 316, 51)
        place("speed", 32, 250, 316, 29)
        place("wish", 32, 283, 316, 35)
        place("progress", 32, 324, 158, 18)
        place("hours", 184, 324, 164, 18)
        progress.frame = NSRect(x: 32, y: 348, width: 316, height: 10)
        place("monthLabel", 32, 380, 116, 23)
        place("monthValue", 150, 375, 198, 30)
        place("monthSub", 32, 411, 316, 37)
        place("hourly", 32, 452, 316, 39)
        quoteButton.frame = NSRect(x: 24, y: 515, width: 332, height: 43)
        place("footer", 20, 612, 340, 17)
    }

    func update(_ snapshot: Snapshot, engine: Engine, at now: Date) {
        let week = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"][engine.calendar.component(.weekday, from: now) - 1]
        let clock = engine.calendar.dateComponents([.hour, .minute, .second], from: now)
        labels["clock"]?.stringValue = engine.dateKey(now) + "  " + week + String(format: "  %02d:%02d:%02d", clock.hour!, clock.minute!, clock.second!)
        labels["status"]?.stringValue = snapshot.state.rawValue
        labels["status"]?.textColor = snapshot.state == .working ? Theme.blue : snapshot.state == .overtime ? Theme.orange : Theme.green
        let countdown: String
        switch snapshot.state {
        case .beforeWork: countdown = "距离上班还有 " + Engine.duration(snapshot.secondsToNext)
        case .working: countdown = "距离下班还有 " + Engine.duration(snapshot.secondsToNext)
        case .lunch: countdown = "午休还剩 " + Engine.duration(snapshot.secondsToNext) + "，暂停计薪"
        case .overtime: countdown = "已加班 " + Engine.duration(snapshot.overtimeSeconds) + "，按 \(settings.overtimeRate) 倍计"
        case .afterWork: countdown = "今天的牛马已下线，快跑！"
        case .restDay: countdown = "今天不用当牛马，好好休息。"
        }
        labels["countdown"]?.stringValue = countdown
        func money(_ value: Double, _ decimals: Int = 2) -> String {
            settings.masked ? "****" : settings.currency + String(format: "%.*f", decimals, value)
        }
        labels["mask"]?.stringValue = settings.currency + " ****.**"
        labels["speed"]?.stringValue = settings.masked ? "当前赚钱速度  **** / 秒  ·  **** / 分钟" : snapshot.speed > 0
            ? "当前赚钱速度  \(money(snapshot.speed, settings.decimals)) / 秒\n\(money(snapshot.speed * 60)) / 分钟"
            : "当前赚钱速度  \(settings.currency)0 / 秒（暂停计薪）"
        labels["wish"]?.stringValue = settings.masked ? "金额已隐藏，安心搬砖。" : engine.wishText(settings, snapshot: snapshot)
        labels["progress"]?.stringValue = String(format: "今日工时进度 %.1f%%", snapshot.progress * 100)
        labels["hours"]?.stringValue = String(format: "%.2f / %.2f 小时", snapshot.paidElapsed / 3600, snapshot.paidSeconds / 3600)
        progress.doubleValue = snapshot.progress
        labels["monthValue"]?.stringValue = money(engine.monthEarned(settings, at: now, todayEarned: snapshot.earned))
        let payday = engine.daysToPayDay(settings, at: now)
        labels["monthSub"]?.stringValue = "历史工作日按满勤估算 · 本月约 \(money(engine.monthTotal(settings, at: now), 0))\n" + (payday == 0 ? "今天发工资！" : "距离发薪日还有 \(payday) 天")
        labels["hourly"]?.stringValue = "时薪 \(money(snapshot.hourlyPay))   ·   分薪 \(money(snapshot.hourlyPay / 60, 3))\n今日满勤可得 \(money(snapshot.dailyPay))"
        if now.timeIntervalSince(quoteAt) >= 600 { quoteIndex += 1; quoteAt = now }
        let quotes = settings.quoteList
        quoteButton.title = quotes.isEmpty ? "" : quotes[quoteIndex % quotes.count]
        updateAmount(snapshot)
    }

    func updateAmount(_ snapshot: Snapshot) {
        amount.value = snapshot.earned; amount.speed = snapshot.speed
        if !settings.masked {
            amount.setAccessibilityValue(settings.currency + String(format: "%.*f", settings.decimals, snapshot.earned))
            amount.needsDisplay = true
        } else { amount.setAccessibilityValue("金额已隐藏") }
    }

    @objc private func nextQuote(_ sender: Any?) {
        quoteIndex += 1; quoteAt = Date()
        let quotes = settings.quoteList
        quoteButton.title = quotes.isEmpty ? "" : quotes[quoteIndex % quotes.count]
    }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: bounds, xRadius: settings.mini ? 15 : 20, yRadius: settings.mini ? 15 : 20).addClip()
        Theme.paper.setFill(); bounds.fill()
        if !settings.mini, let image = background {
            let scale = max(bounds.width / image.size.width, bounds.height / image.size.height)
            let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: NSRect(x: (bounds.width - size.width) / 2, y: bounds.height - size.height,
                                  width: size.width, height: size.height), from: .zero, operation: .sourceOver,
                       fraction: settings.bgOpacity, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        }
        if !settings.mini {
            Theme.paper.withAlphaComponent(settings.panelOpacity).setFill()
            NSBezierPath(roundedRect: NSRect(x: 16, y: 58, width: 348, height: 443), xRadius: 14, yRadius: 14).fill()
            Theme.muted.withAlphaComponent(0.20).setFill()
            NSRect(x: 32, y: 368, width: 316, height: 1).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { toggleMini?(); return }
        window?.performDrag(with: event)
        didDrag?()
    }
    override func rightMouseDown(with event: NSEvent) {
        if let menu = makeMenu?() { NSMenu.popUpContextMenu(menu, with: event, for: self) }
    }
}

final class MainPanel: NSPanel {
    let mainView = MainView(frame: NSRect(x: 0, y: 0, width: 380, height: 640))
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(contentRect: mainView.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isOpaque = false; backgroundColor = .clear; hasShadow = true
        hidesOnDeactivate = false; isFloatingPanel = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = mainView
    }

    func apply(_ settings: AppSettings) {
        title = settings.appName
        level = settings.topmost ? .floating : .normal
        ignoresMouseEvents = settings.clickThrough
        alphaValue = settings.windowOpacity
        let workArea = (screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let natural = NSSize(width: settings.mini ? 355 : 380, height: settings.mini ? 58 : 640)
        let automatic = min(1.25, max(0.72, workArea.height * 0.55 / 640))
        let scale = min(automatic * settings.uiZoom, (workArea.width - 24) / natural.width, (workArea.height - 24) / natural.height)
        let top = frame.maxY
        setContentSize(NSSize(width: natural.width * scale, height: natural.height * scale))
        mainView.frame = NSRect(origin: .zero, size: frame.size)
        mainView.bounds = NSRect(origin: .zero, size: natural)
        setFrameOrigin(NSPoint(x: frame.minX, y: top - frame.height))
        mainView.apply(settings)
        keepOnScreen()
    }

    func keepOnScreen(snap: Bool = false) {
        let screen = NSScreen.screens.max { left, right in
            let a = left.visibleFrame.intersection(frame), b = right.visibleFrame.intersection(frame)
            return max(0, a.width) * max(0, a.height) < max(0, b.width) * max(0, b.height)
        } ?? NSScreen.main
        guard let area = screen?.visibleFrame else { return }
        var x = min(max(frame.minX, area.minX + 8), max(area.minX, area.maxX - frame.width - 8))
        var y = min(max(frame.minY, area.minY + 8), max(area.minY, area.maxY - frame.height - 8))
        if snap {
            if abs(x - area.minX) < 22 { x = area.minX + 8 }
            if abs(frame.maxX - area.maxX) < 22 { x = area.maxX - frame.width - 8 }
            if abs(y - area.minY) < 22 { y = area.minY + 8 }
            if abs(frame.maxY - area.maxY) < 22 { y = area.maxY - frame.height - 8 }
        }
        setFrameOrigin(NSPoint(x: x, y: y))
    }
}
