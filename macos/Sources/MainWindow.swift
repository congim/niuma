import AppKit

enum Theme {
    static let ink = NSColor(srgbRed: 0.20, green: 0.22, blue: 0.18, alpha: 1)
    static let muted = NSColor(srgbRed: 0.41, green: 0.42, blue: 0.35, alpha: 1)
    static let paper = NSColor(srgbRed: 0.97, green: 0.96, blue: 0.92, alpha: 1)
    static let orange = NSColor(srgbRed: 0.80, green: 0.33, blue: 0.12, alpha: 1)
    static let green = NSColor(srgbRed: 0.19, green: 0.37, blue: 0.29, alpha: 1)
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
    private let setupButton = NSButton()
    private let copyButton = NSButton()
    private var reportIsCopied = false
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
        progress.minValue = 0
        progress.maxValue = 1
        progress.controlSize = .small
        progress.setAccessibilityLabel("今日计薪工时进度")
        addSubview(progress)
        quoteButton.isBordered = false
        quoteButton.target = self
        quoteButton.action = #selector(nextQuote(_:))
        quoteButton.font = .systemFont(ofSize: 12)
        quoteButton.contentTintColor = Theme.green
        quoteButton.toolTip = "点击换一句"
        quoteButton.cell?.wraps = true
        addSubview(quoteButton)
        setupButton.title = "设置我的薪资"
        setupButton.bezelStyle = .rounded
        setupButton.contentTintColor = Theme.green
        addSubview(setupButton)
        copyButton.title = "复制今日战报"
        copyButton.bezelStyle = .inline
        copyButton.isBordered = false
        copyButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        copyButton.imagePosition = .imageLeft
        copyButton.font = .systemFont(ofSize: 11)
        copyButton.contentTintColor = Theme.green
        addSubview(copyButton)
        for (key, size, color, bold) in [
            ("title", 15.0, Theme.ink, true), ("clock", 11, Theme.muted, false),
            ("status", 12, Theme.green, true), ("countdown", 20, Theme.ink, true),
            ("today", 12, Theme.muted, false), ("speed", 11, Theme.muted, false),
            ("wish", 13, Theme.green, true), ("progress", 11, Theme.muted, false),
            ("hours", 11, Theme.muted, false), ("monthLabel", 12, Theme.muted, false),
            ("monthValue", 20, Theme.green, true), ("monthSub", 10, Theme.muted, false),
            ("hourly", 11, Theme.muted, false), ("footer", 10, Theme.muted, false),
            ("estimate", 10, Theme.muted, false), ("mask", 44, Theme.orange, true)
        ] {
            let field = Theme.label(size, color: color, bold: bold)
            labels[key] = field
            addSubview(field)
        }
        labels["monthValue"]?.alignment = .right
        labels["hours"]?.alignment = .right
        labels["status"]?.alignment = .center
        labels["footer"]?.alignment = .right
        labels["title"]?.maximumNumberOfLines = 1
        labels["title"]?.lineBreakMode = .byTruncatingTail
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configureActions(target: AnyObject) {
        for (symbol, help, action) in [
            ("eye", "隐藏全部金额 · ⌃⌥H", #selector(AppController.toggleMask(_:))),
            ("pin.fill", "关闭置顶", #selector(AppController.toggleTopmost(_:))),
            ("rectangle.compress.vertical", "切换迷你模式", #selector(AppController.toggleMini(_:))),
            ("gearshape", "设置", #selector(AppController.openSettings(_:))),
            ("minus", "隐藏到菜单栏 · ⌃⌥M", #selector(AppController.toggleVisible(_:)))
        ] {
            let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: help)!, target: target, action: action)
            button.bezelStyle = .inline
            button.isBordered = false
            button.contentTintColor = Theme.muted
            button.toolTip = help
            button.setAccessibilityLabel(help)
            addSubview(button)
            headerButtons.append(button)
        }
        setupButton.target = target
        setupButton.action = #selector(AppController.openSettings(_:))
        copyButton.target = target
        copyButton.action = #selector(AppController.copyReport(_:))
    }

    func apply(_ settings: AppSettings) {
        self.settings = settings
        amount.settings = settings
        if backgroundPath != settings.bgPath {
            backgroundPath = settings.bgPath
            background = settings.bgPath.isEmpty ? nil : NSImage(contentsOfFile: settings.bgPath)
            if background == nil, let url = Bundle.main.url(forResource: "beij", withExtension: "png") {
                background = NSImage(contentsOf: url)
            }
        }
        amount.isHidden = settings.masked
        amount.setAccessibilityLabel(settings.salaryConfigured ? "今日已赚" : "示例今日已赚")
        labels["mask"]?.isHidden = !settings.masked
        labels["title"]?.stringValue = settings.appName
        labels["today"]?.stringValue = settings.salaryConfigured ? "今日已赚" : "今日已赚 · 示例薪资"
        labels["monthLabel"]?.stringValue = "本月预估"
        labels["estimate"]?.stringValue = "按你的薪资与作息实时估算"
        labels["footer"]?.stringValue = "双击切换迷你 · 右键更多"
        for button in headerButtons { button.isHidden = settings.mini }
        if headerButtons.count >= 2 {
            let eye = headerButtons[0]
            let eyeHelp = settings.masked ? "显示全部金额 · ⌃⌥H" : "隐藏全部金额 · ⌃⌥H"
            eye.image = NSImage(systemSymbolName: settings.masked ? "eye.slash.fill" : "eye", accessibilityDescription: eyeHelp)
            eye.contentTintColor = settings.masked ? Theme.orange : Theme.muted
            eye.toolTip = eyeHelp
            eye.setAccessibilityLabel(eyeHelp)
            let pin = headerButtons[1]
            let pinHelp = settings.topmost ? "已置顶 · 点击关闭" : "未置顶 · 点击开启"
            pin.image = NSImage(systemSymbolName: settings.topmost ? "pin.fill" : "pin", accessibilityDescription: pinHelp)
            pin.contentTintColor = settings.topmost ? Theme.green : Theme.muted
            pin.toolTip = pinHelp
            pin.setAccessibilityLabel(pinHelp)
        }
        progress.isHidden = settings.mini
        quoteButton.isHidden = settings.mini
        copyButton.isHidden = settings.mini
        setupButton.isHidden = settings.mini || settings.salaryConfigured
        for (key, label) in labels where key != "mask" {
            label.isHidden = settings.mini && key != "status"
        }
        labels["estimate"]?.isHidden = settings.mini || !settings.salaryConfigured
        layoutContent()
        needsDisplay = true
    }

    func layoutContent() {
        func place(_ key: String, _ x: Double, _ y: Double, _ width: Double, _ height: Double) {
            labels[key]?.frame = NSRect(x: x, y: y, width: width, height: height)
        }
        if settings.mini {
            amount.frame = NSRect(x: 14, y: 10, width: 196, height: 38)
            place("mask", 14, 10, 196, 38)
            place("status", 216, 11, 126, 38)
            labels["status"]?.font = .systemFont(ofSize: 12, weight: .medium)
            labels["mask"]?.font = .monospacedDigitSystemFont(ofSize: 25, weight: .bold)
            return
        }
        labels["status"]?.font = .systemFont(ofSize: 12, weight: .semibold)
        labels["mask"]?.font = .monospacedDigitSystemFont(ofSize: 44, weight: .bold)
        place("title", 22, 18, 176, 24)
        for (index, button) in headerButtons.enumerated() {
            button.frame = NSRect(x: 205 + index * 29, y: 17, width: 25, height: 26)
        }
        place("clock", 22, 46, 330, 18)
        place("today", 32, 92, 214, 18)
        place("status", 260, 91, 84, 20)
        amount.frame = NSRect(x: 30, y: 118, width: 320, height: 66)
        place("mask", 30, 118, 320, 66)
        place("speed", 32, 190, 316, 20)
        place("hourly", 32, 214, 316, 28)
        setupButton.frame = NSRect(x: 26, y: 243, width: 140, height: 28)
        place("estimate", 32, 249, 316, 18)
        place("countdown", 32, 297, 316, 29)
        place("progress", 32, 337, 168, 18)
        place("hours", 204, 337, 144, 18)
        progress.frame = NSRect(x: 32, y: 360, width: 316, height: 8)
        place("wish", 32, 399, 316, 36)
        place("monthLabel", 32, 461, 112, 22)
        place("monthValue", 150, 456, 198, 30)
        place("monthSub", 32, 491, 316, 32)
        quoteButton.frame = NSRect(x: 22, y: 530, width: 226, height: 34)
        copyButton.frame = NSRect(x: 22, y: 568, width: 126, height: 24)
        place("footer", 153, 574, 200, 16)
    }

    func update(_ snapshot: Snapshot, engine: Engine, at now: Date) {
        let week = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"][engine.calendar.component(.weekday, from: now) - 1]
        labels["clock"]?.stringValue = engine.dateKey(now) + "  " + week
        var status = snapshot.state.rawValue
        let countdown: String
        switch snapshot.state {
        case .beforeWork: countdown = "距上班 " + Engine.duration(snapshot.secondsToNext)
        case .working:
            countdown = "距下班 " + Engine.duration(snapshot.secondsToNext)
            if settings.mini { status = Engine.duration(snapshot.secondsToNext, precise: false) + "后下班" }
        case .lunch: countdown = "午休还有 " + Engine.duration(snapshot.secondsToNext)
        case .overtime: countdown = "已加班 " + Engine.duration(snapshot.overtimeSeconds)
        case .afterWork: countdown = "今日收工，辛苦了。"
        case .restDay: countdown = "今天，好好休息。"
        }
        if settings.mini && reportIsCopied { status = "战报已复制" }
        if settings.mini && !settings.salaryConfigured { status = "示例 · " + status }
        labels["status"]?.stringValue = status
        labels["status"]?.textColor = snapshot.state == .overtime ? Theme.orange : Theme.green
        labels["countdown"]?.stringValue = countdown
        func money(_ value: Double, _ decimals: Int = 2) -> String {
            settings.masked ? "****" : settings.currency + String(format: "%.*f", decimals, value)
        }
        labels["mask"]?.stringValue = settings.currency + " ****.**"
        labels["speed"]?.stringValue = snapshot.speed > 0
            ? "每秒 \(money(snapshot.speed, settings.decimals))  ·  每分钟 \(money(snapshot.speed * 60))"
            : "当前暂停计薪"
        labels["wish"]?.stringValue = settings.masked ? "金额已隐藏，安心搬砖。" : engine.wishText(settings, snapshot: snapshot)
        labels["progress"]?.stringValue = String(format: "今日工时 %.1f%%", snapshot.progress * 100)
        labels["hours"]?.stringValue = String(format: "%.2f / %.2f 小时", snapshot.paidElapsed / 3600, snapshot.paidSeconds / 3600)
        progress.doubleValue = snapshot.progress
        labels["monthValue"]?.stringValue = money(engine.monthEarned(settings, at: now, todayEarned: snapshot.earned))
        let payday = engine.daysToPayDay(settings, at: now)
        labels["monthSub"]?.stringValue = "本月满勤约 \(money(engine.monthTotal(settings, at: now), 0)) · " + (payday == 0 ? "今天发工资" : "\(payday) 天后发薪") + "\n历史工作日按满勤估算"
        labels["hourly"]?.stringValue = "时薪 \(money(snapshot.hourlyPay)) · 今日满勤 \(money(snapshot.dailyPay))" + (snapshot.state == .overtime ? "\n加班按 \(settings.overtimeRate) 倍计薪" : "")
        if now.timeIntervalSince(quoteAt) >= 600 { quoteIndex += 1; quoteAt = now }
        let quotes = settings.quoteList
        quoteButton.title = quotes.isEmpty ? "" : quotes[quoteIndex % quotes.count]
        updateAmount(snapshot)
    }

    func updateAmount(_ snapshot: Snapshot) {
        amount.value = snapshot.earned
        amount.speed = snapshot.speed
        if !settings.masked {
            amount.setAccessibilityValue(settings.currency + String(format: "%.*f", settings.decimals, snapshot.earned))
            amount.needsDisplay = true
        } else { amount.setAccessibilityValue("金额已隐藏") }
    }

    func setReportCopied(_ copied: Bool) {
        reportIsCopied = copied
        copyButton.title = copied ? "战报已复制" : "复制今日战报"
    }

    @objc private func nextQuote(_ sender: Any?) {
        quoteIndex += 1
        quoteAt = Date()
        let quotes = settings.quoteList
        quoteButton.title = quotes.isEmpty ? "" : quotes[quoteIndex % quotes.count]
    }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath(roundedRect: bounds, xRadius: settings.mini ? 15 : 20, yRadius: settings.mini ? 15 : 20).addClip()
        Theme.paper.setFill()
        bounds.fill()
        guard !settings.mini else { return }
        if let image = background {
            if settings.bgPath.isEmpty {
                let headerSource = NSRect(x: 0, y: image.size.height * 0.78, width: image.size.width, height: image.size.width * 70 / 380)
                image.draw(in: NSRect(x: 0, y: 0, width: 380, height: 70), from: headerSource,
                           operation: .sourceOver, fraction: settings.bgOpacity * 0.22, respectFlipped: true, hints: nil)
                let source = NSRect(x: image.size.width * 0.08, y: image.size.height * 0.18,
                                    width: image.size.width * 0.88, height: image.size.height * 0.44)
                let width = 52 * source.width / source.height
                image.draw(in: NSRect(x: 304 - width / 2, y: 520, width: width, height: 52), from: source,
                           operation: .sourceOver, fraction: settings.bgOpacity * 0.78, respectFlipped: true,
                           hints: [.interpolation: NSImageInterpolation.high])
            } else {
                let scale = max(bounds.width / image.size.width, bounds.height / image.size.height)
                let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
                image.draw(in: NSRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2,
                                      width: size.width, height: size.height), from: .zero,
                           operation: .sourceOver, fraction: settings.bgOpacity, respectFlipped: true,
                           hints: [.interpolation: NSImageInterpolation.high])
                Theme.paper.withAlphaComponent(0.82).setFill()
                bounds.fill()
                Theme.paper.withAlphaComponent(0.94).setFill()
                NSBezierPath(roundedRect: NSRect(x: 16, y: 76, width: 348, height: 448), xRadius: 17, yRadius: 17).fill()
            }
        }
        NSColor.white.withAlphaComponent(settings.panelOpacity).setFill()
        NSBezierPath(roundedRect: NSRect(x: 16, y: 76, width: 348, height: 200), xRadius: 17, yRadius: 17).fill()
        Theme.green.withAlphaComponent(0.08).setFill()
        NSBezierPath(roundedRect: NSRect(x: 254, y: 86, width: 94, height: 28), xRadius: 14, yRadius: 14).fill()
        NSBezierPath(roundedRect: NSRect(x: 16, y: 386, width: 348, height: 58), xRadius: 13, yRadius: 13).fill()
        Theme.muted.withAlphaComponent(0.18).setFill()
        NSRect(x: 32, y: 527, width: 316, height: 1).fill()
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
    let mainView = MainView(frame: NSRect(x: 0, y: 0, width: 380, height: 600))
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
        let natural = NSSize(width: settings.mini ? 355 : 380, height: settings.mini ? 58 : 600)
        let automatic = min(1.25, max(0.72, workArea.height * 0.55 / 600))
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
