import Foundation

struct SettingsError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct AppSettings: Codable, Equatable {
    var appName = "牛马脱敏器"
    var salaryConfigured = false
    var salaryMode = 0
    var amount = 100.0
    var monthDays = 21.75
    var startTime = "10:00"
    var endTime = "19:00"
    var lunchEnabled = false
    var lunchStart = "12:00"
    var lunchEnd = "13:00"
    var workDays = [1, 2, 3, 4, 5] // Sunday is 0, matching the Windows version.
    var decimals = 5
    var currency = "¥"
    var bgOpacity = 1.0
    var panelOpacity = 0.55
    var windowOpacity = 1.0
    var uiZoom = 1.0
    var topmost = true
    var clickThrough = false
    var mini = false
    var masked = false
    var odometer = true
    var overtime = false
    var overtimeRate = 1.5
    var payDay = 10
    var offWorkNotify = false
    var bgPath = ""
    var windowX: Double?
    var windowY: Double?
    var overrideDate = ""
    var overrideMode = 0
    var wishlist = "一瓶可乐=3\n一个煎饼果子=8\n一杯奶茶=15\n一份猪脚饭=22\n一杯咖啡=30\n一张电影票=45\n一件T恤=79\n一顿火锅=120\n一双球鞋=399"
    var quotes = "摸鱼不是偷懒，是在给老板省电。\n工资不多，但每一秒都在到账。\n上班是为了下班，下班是为了明天还能上班。\n今天的你，又为老板的新车贡献了一个轮毂。\n别慌，钱在路上，人在工位。\n带薪如厕，是打工人最后的倔强。\n只要我不努力，老板就过不上他想要的生活。\n工作是老板的，命是自己的。\n再坚持一下，离下班又近了一秒。\n今日份的牛马已上线，正在稳定产出。"

    var dailyPay: Double { salaryMode == 1 ? (monthDays > 0 ? amount / monthDays : 0) : amount }
    var quoteList: [String] { quotes.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
    var wishItems: [(name: String, price: Double)] {
        wishlist.components(separatedBy: .newlines).compactMap { line in
            let line = line.replacingOccurrences(of: "＝", with: "=")
            guard let split = line.lastIndex(of: "=") else { return nil }
            let name = String(line[..<split]).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, let price = Double(line[line.index(after: split)...].trimmingCharacters(in: .whitespaces)),
                  price.isFinite, price > 0 else { return nil }
            return (name, price)
        }.sorted { $0.price < $1.price }
    }

    static func seconds(_ text: String) -> Double? {
        let parts = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "：", with: ":")
            .split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let hours = Int(parts[0]), let minutes = Int(parts[1]),
              (0...23).contains(hours), (0...59).contains(minutes) else { return nil }
        return Double(hours * 3600 + minutes * 60)
    }

    func validated() throws -> AppSettings {
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw SettingsError(message: message) }
        }
        try require((0...1).contains(salaryMode), "请选择日薪或月薪")
        try require(amount.isFinite && (0...1e9).contains(amount), "薪资金额应在 0～10 亿之间")
        try require(monthDays.isFinite && monthDays > 0 && monthDays <= 31, "月计薪天数应大于 0 且不超过 31")
        try require(dailyPay.isFinite && dailyPay <= 1e9, "折算日薪不能超过 10 亿，请检查薪资与月计薪天数")
        guard let start = Self.seconds(startTime), let end = Self.seconds(endTime), end > start else {
            throw SettingsError(message: "上下班时间应为 HH:mm，且下班晚于上班（不支持跨夜班次）")
        }
        if lunchEnabled {
            guard let from = Self.seconds(lunchStart), let to = Self.seconds(lunchEnd),
                  from >= start, to <= end, to > from, to - from < end - start else {
                throw SettingsError(message: "午休需位于上班时段内，且不能占满整个计薪时段")
            }
        }
        try require(workDays.allSatisfy { (0...6).contains($0) }, "工作日不正确")
        try require(overtimeRate.isFinite && (0...10).contains(overtimeRate), "加班倍率应在 0～10 之间")
        try require((1...31).contains(payDay), "发薪日应在 1～31 之间")
        try require((2...6).contains(decimals), "小数位数应在 2～6 之间")
        for value in [bgOpacity, panelOpacity] { try require(value.isFinite && (0...1).contains(value), "透明度应在 0～100% 之间") }
        try require(windowOpacity.isFinite && (0.2...1).contains(windowOpacity), "整体透明度应在 20～100% 之间")
        try require(uiZoom.isFinite && (0.5...2).contains(uiZoom), "界面大小应在 50～200% 之间")
        try require((0...2).contains(overrideMode), "调休模式不正确")
        for coordinate in [windowX, windowY].compactMap({ $0 }) {
            try require(coordinate.isFinite && abs(coordinate) < 1e7, "窗口位置不正确")
        }
        var result = self
        result.appName = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.appName.isEmpty { result.appName = "牛马脱敏器" }
        result.currency = String(currency.trimmingCharacters(in: .whitespaces).prefix(8))
        result.workDays = Array(Set(workDays)).sorted()
        for key in [\AppSettings.startTime, \.endTime, \.lunchStart, \.lunchEnd] {
            if let seconds = Self.seconds(result[keyPath: key]) {
                result[keyPath: key] = String(format: "%02d:%02d", Int(seconds) / 3600, Int(seconds) % 3600 / 60)
            }
        }
        return result
    }
}

struct SettingsStore {
    let directory: URL
    var fileURL: URL { directory.appendingPathComponent("settings.json") }

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NiuMaTuoMinQi", isDirectory: true)
    }

    func load() throws -> AppSettings {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return AppSettings() }
        let data = try Data(contentsOf: fileURL)
        guard data.count <= 1_048_576,
              let saved = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let defaults = try JSONSerialization.jsonObject(with: JSONEncoder().encode(AppSettings())) as? [String: Any] else {
            throw SettingsError(message: "设置文件格式不正确：\(fileURL.path)")
        }
        var merged = defaults.merging(saved) { _, new in new }
        if saved["salaryConfigured"] == nil { merged["salaryConfigured"] = true }
        return try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: merged)).validated()
    }

    func save(_ settings: AppSettings) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(settings.validated())
        guard data.count <= 1_048_576 else { throw SettingsError(message: "设置内容超过 1 MB，请缩短语录、心愿单或名称") }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}
