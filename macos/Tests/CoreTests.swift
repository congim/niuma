import Foundation

@main
struct CoreTests {
    static var checks = 0

    static func check(_ condition: Bool, _ message: String) {
        checks += 1
        guard condition else { fatalError("FAIL: \(message)") }
    }

    static func near(_ actual: Double, _ expected: Double, _ message: String) {
        check(abs(actual - expected) < 0.00001, "\(message): \(actual) != \(expected)")
    }

    static func date(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: value + "+08:00")!
    }

    static func main() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let engine = Engine(calendar: calendar)
        var settings = AppSettings()
        settings.amount = 800
        settings.startTime = "09:00"
        settings.endTime = "18:00"
        settings.lunchEnabled = true

        let cases: [(String, WorkState, Double, Double)] = [
            ("2026-11-10T08:59:59", .beforeWork, 0, 0),
            ("2026-11-10T09:00:00", .working, 0, 0),
            ("2026-11-10T11:00:00", .working, 200, 0.25),
            ("2026-11-10T12:00:00", .lunch, 300, 0.375),
            ("2026-11-10T12:59:59", .lunch, 300, 0.375),
            ("2026-11-10T13:00:00", .working, 300, 0.375),
            ("2026-11-10T18:00:00", .afterWork, 800, 1),
            ("2026-11-14T11:00:00", .restDay, 0, 0)
        ]
        for (time, state, earned, progress) in cases {
            let snapshot = engine.compute(settings, at: date(time))
            check(snapshot.state == state, "state at \(time)")
            near(snapshot.earned, earned, "earned at \(time)")
            near(snapshot.progress, progress, "progress at \(time)")
        }
        settings.overtime = true
        let overtime = engine.compute(settings, at: date("2026-11-10T20:00:00"))
        check(overtime.state == .overtime, "overtime state")
        near(overtime.earned, 1100, "overtime multiplier")
        near(overtime.progress, 1, "overtime doesn't inflate progress")
        settings.salaryMode = 1
        settings.amount = 17400
        near(settings.dailyPay, 800, "monthly salary uses configured 21.75 days")
        settings.overrideDate = "2026-11-14"
        settings.overrideMode = 2
        check(engine.compute(settings, at: date("2026-11-14T11:00:00")).state == .working, "makeup workday")
        check(engine.compute(settings, at: date("2026-11-15T11:00:00")).state == .restDay, "override expires")
        settings.overrideMode = 1
        settings.overrideDate = "2026-11-10"
        check(engine.compute(settings, at: date("2026-11-10T11:00:00")).state == .restDay, "leave day")

        settings = AppSettings()
        near(engine.monthEarned(settings, at: date("2026-11-10T14:00:00"), todayEarned: 50), 650, "past workdays assumed full attendance")
        near(engine.monthTotal(settings, at: date("2026-11-10T14:00:00")), 2100, "November 2026 has 21 weekdays")
        settings.payDay = 31
        check(engine.daysToPayDay(settings, at: date("2024-02-28T20:00:00")) == 1, "leap February payday")
        check(engine.daysToPayDay(settings, at: date("2023-02-28T20:00:00")) == 0, "short month payday")
        settings.payDay = 10
        check(engine.daysToPayDay(settings, at: date("2026-12-31T20:00:00")) == 10, "payday crosses year")
        check(engine.daysToPayDay(settings, at: date("2026-11-10T23:59:59")) == 0, "payday ignores time of day")
        settings.wishlist = "咖啡=30\n坏数据=nan\n负数=-2\n可乐＝3\n无限=infinity"
        check(settings.wishItems.map(\.name) == ["可乐", "咖啡"], "wishlist sorts finite positive prices")
        let snapshot = engine.compute(settings, at: date("2026-11-10T14:00:00"))
        check(engine.wishText(settings, snapshot: snapshot).contains("咖啡"), "achieved wish")
        settings.masked = true
        let report = engine.report(settings, at: date("2026-11-10T14:00:00"))
        check(report.contains("****") && !report.contains("44.44") && !report.contains("11.11"), "private report hides salary values")

        var invalid = AppSettings()
        for amount in [-1, Double.nan, Double.infinity, 1_000_000_001] {
            invalid.amount = amount
            check((try? invalid.validated()) == nil, "reject invalid salary \(amount)")
        }
        invalid = AppSettings()
        invalid.monthDays = 0
        check((try? invalid.validated()) == nil, "reject zero monthly divisor")
        invalid.monthDays = 1e-308
        invalid.salaryMode = 1
        check((try? invalid.validated()) == nil, "reject derived salary overflow")
        invalid = AppSettings()
        invalid.endTime = "09:00"
        check((try? invalid.validated()) == nil, "reject overnight schedule")
        invalid = AppSettings()
        invalid.lunchEnabled = true
        invalid.lunchEnd = "23:00"
        check((try? invalid.validated()) == nil, "reject lunch outside shift")
        invalid = AppSettings()
        invalid.lunchStart = invalid.startTime
        invalid.lunchEnd = invalid.endTime
        invalid.lunchEnabled = true
        check((try? invalid.validated()) == nil, "reject lunch consuming entire paid day")
        invalid = AppSettings()
        invalid.startTime = " 9：05 "
        check(try invalid.validated().startTime == "09:05", "normalize fullwidth colon")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SettingsStore(directory: directory)
        check(try store.load() == AppSettings(), "missing file loads defaults")
        let freshJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(store.load())) as! [String: Any]
        check(freshJSON["salaryConfigured"] as? Bool == false, "first launch explicitly marks example salary")
        var example = AppSettings()
        example.windowX = 120
        try store.save(example)
        check(try !store.load().salaryConfigured, "position persistence keeps example salary unconfigured")
        check(engine.report(example, at: date("2026-11-10T14:00:00")).contains("示例战报"), "example report identifies example salary")
        example.salaryConfigured = true
        check(!engine.report(example, at: date("2026-11-10T14:00:00")).contains("示例"), "configured report has no example marker")
        example.amount = 800
        example.startTime = "09:00"
        example.endTime = "18:00"
        example.lunchEnabled = true
        example.wishlist = "小目标=400"
        let beforeLunch = engine.compute(example, at: date("2026-11-10T11:50:00"))
        let wish = engine.wishText(example, snapshot: beforeLunch)
        check(wish.contains("再计薪") && !wish.contains("再过"), "wish crossing lunch explicitly describes paid time")
        settings.appName = "牛马 🫏 = 测试"
        settings.quotes = "反斜杠\\和等号=\n第二句"
        try store.save(settings)
        check(try store.load() == settings, "settings survive UTF8 and newline roundtrip")
        let original = try Data(contentsOf: store.fileURL)
        invalid.amount = .nan
        do { try store.save(invalid); fatalError("invalid save accepted") } catch {}
        check(try Data(contentsOf: store.fileURL) == original, "failed save preserves previous data")
        try Data("{\"amount\":200}".utf8).write(to: store.fileURL)
        check(try store.load().amount == 200 && store.load().decimals == 5, "missing fields get defaults")
        let legacyJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(store.load())) as! [String: Any]
        check(legacyJSON["salaryConfigured"] as? Bool == true, "legacy settings count as configured salary")
        let corrupt = Data("not JSON".utf8)
        try corrupt.write(to: store.fileURL)
        do { _ = try store.load(); fatalError("corrupt file accepted") } catch {}
        check(try Data(contentsOf: store.fileURL) == corrupt, "load never overwrites corrupt settings")

        check(DigitRoller.offsets(value: 100, decimals: 2, speed: 0) == [1, 0, 0, 0, 0], "exact 100 carry")
        let rolling = DigitRoller.offsets(value: 9.999, decimals: 2, speed: 0.01)
        check(rolling[0] > 9 && rolling[0] <= 10, "nine rolls toward zero at carry")
        check(DigitRoller.offsets(value: 123.45, decimals: 2, speed: 0) == [1, 2, 3, 4, 5], "paused digits are exact")
        settings = AppSettings()
        settings.overtime = true
        settings.wishlist = "大目标=1e308"
        let largeWish = engine.compute(settings, at: date("2026-11-10T20:00:00"))
        check(!engine.wishText(settings, snapshot: largeWish).isEmpty, "huge finite wish doesn't overflow duration")
        print("PASS: \(checks) core checks")
    }
}
