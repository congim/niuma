import Foundation

enum WorkState: String {
    case beforeWork = "还没上班", working = "上班中", lunch = "午休中"
    case overtime = "加班中", afterWork = "已下班", restDay = "休息日"
}

struct Snapshot {
    var state: WorkState = .beforeWork
    var earned = 0.0
    var dailyPay = 0.0
    var hourlyPay = 0.0
    var speed = 0.0
    var paidSeconds = 0.0
    var paidElapsed = 0.0
    var progress = 0.0
    var secondsToNext = 0.0
    var overtimeSeconds = 0.0
}

struct Engine {
    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }()

    func dateKey(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    func isWorkDay(_ settings: AppSettings, _ date: Date) -> Bool {
        if settings.overrideMode != 0 && settings.overrideDate == dateKey(date) { return settings.overrideMode == 2 }
        return settings.workDays.contains(calendar.component(.weekday, from: date) - 1)
    }

    func compute(_ settings: AppSettings, at date: Date) -> Snapshot {
        let start = AppSettings.seconds(settings.startTime) ?? 36_000
        let end = max(start + 1, AppSettings.seconds(settings.endTime) ?? 68_400)
        let lunchStart = max(start, AppSettings.seconds(settings.lunchStart) ?? 43_200)
        let lunchEnd = min(end, AppSettings.seconds(settings.lunchEnd) ?? 46_800)
        let lunch = settings.lunchEnabled && lunchEnd > lunchStart && lunchEnd - lunchStart < end - start
        func overlap(_ from: Double, _ to: Double, _ until: Double) -> Double { max(0, min(to, until) - from) }
        func paid(_ until: Double) -> Double {
            max(0, overlap(start, end, until) - (lunch ? overlap(lunchStart, lunchEnd, until) : 0))
        }
        let clock = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        let time = Double(clock.hour! * 3600 + clock.minute! * 60 + clock.second!) + Double(clock.nanosecond ?? 0) / 1e9
        var result = Snapshot()
        result.dailyPay = settings.dailyPay
        result.paidSeconds = paid(86_400)
        let rate = result.paidSeconds > 0 ? result.dailyPay / result.paidSeconds : 0
        result.hourlyPay = rate * 3600
        guard isWorkDay(settings, date) else { result.state = .restDay; return result }
        result.paidElapsed = paid(time)
        result.earned = rate * result.paidElapsed
        result.progress = result.paidSeconds > 0 ? result.paidElapsed / result.paidSeconds : 0
        if time < start {
            result.state = .beforeWork; result.secondsToNext = start - time
        } else if lunch && time >= lunchStart && time < lunchEnd {
            result.state = .lunch; result.secondsToNext = lunchEnd - time
        } else if time < end {
            result.state = .working; result.speed = rate; result.secondsToNext = end - time
        } else if settings.overtime {
            result.state = .overtime; result.overtimeSeconds = time - end
            result.speed = rate * settings.overtimeRate
            result.earned += result.overtimeSeconds * result.speed
        } else {
            result.state = .afterWork
        }
        return result
    }

    func monthEarned(_ settings: AppSettings, at date: Date, todayEarned: Double) -> Double {
        guard let first = calendar.dateInterval(of: .month, for: date)?.start else { return todayEarned }
        var day = first, total = todayEarned
        while day < calendar.startOfDay(for: date) {
            if isWorkDay(settings, day) { total += settings.dailyPay }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return total
    }

    func monthTotal(_ settings: AppSettings, at date: Date) -> Double {
        guard let interval = calendar.dateInterval(of: .month, for: date) else { return 0 }
        var day = interval.start, total = 0.0
        while day < interval.end {
            if isWorkDay(settings, day) { total += settings.dailyPay }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return total
    }

    func daysToPayDay(_ settings: AppSettings, at date: Date) -> Int {
        let today = calendar.startOfDay(for: date)
        func payday(in month: Date) -> Date {
            var parts = calendar.dateComponents([.year, .month], from: month)
            parts.day = min(max(1, settings.payDay), calendar.range(of: .day, in: .month, for: month)!.count)
            return calendar.date(from: parts)!
        }
        var target = payday(in: today)
        if target < today { target = payday(in: calendar.date(byAdding: .month, value: 1, to: today)!) }
        return calendar.dateComponents([.day], from: today, to: target).day ?? 0
    }

    static func duration(_ seconds: Double, precise: Bool = true) -> String {
        guard seconds.isFinite, seconds < Double(Int.max) else { return "很久" }
        let total = Int(max(0, seconds).rounded(.down)), hours = total / 3600
        let minutes = total % 3600 / 60, remainder = total % 60
        if precise {
            if hours > 0 { return String(format: "%d小时%02d分%02d秒", hours, minutes, remainder) }
            return minutes > 0 ? String(format: "%d分%02d秒", minutes, remainder) : "\(remainder)秒"
        }
        if hours > 0 { return "\(hours) 小时 \(minutes) 分" }
        return minutes > 0 ? "\(minutes) 分钟" : "不到 1 分钟"
    }

    func wishText(_ settings: AppSettings, snapshot: Snapshot) -> String {
        let items = settings.wishItems
        guard !items.isEmpty else { return "" }
        let best = items.last { $0.price <= snapshot.earned }
        let next = items.first { $0.price > snapshot.earned }
        switch snapshot.state {
        case .restDay: return "休息日，花钱的事交给明天的自己。"
        case .beforeWork:
            return items.last(where: { $0.price <= snapshot.dailyPay }).map { "今天搬完砖，能换\($0.name)。" } ?? "今天也是为梦想窝囊的一天。"
        case .working, .lunch, .overtime:
            if let next = next, snapshot.speed > 0 {
                let need = (next.price - snapshot.earned) / snapshot.speed
                if snapshot.state == .overtime || need <= max(0, snapshot.paidSeconds - snapshot.paidElapsed) {
                    return "再计薪 \(Self.duration(need, precise: false))，\(next.name)就赚回来了。"
                }
            }
            if let best = best { return "今天已经赚到\(best.name)了，稳住。" }
            return next.map { "离\($0.name)还差 \(settings.currency)\(String(format: "%.2f", $0.price - snapshot.earned))。" } ?? ""
        case .afterWork: return best.map { "今天赚到了\($0.name)，收工！" } ?? "今天收工，辛苦了。"
        }
    }

    func report(_ settings: AppSettings, at date: Date) -> String {
        let snapshot = compute(settings, at: date)
        func money(_ value: Double) -> String { settings.masked ? "****" : settings.currency + String(format: "%.2f", value) }
        let title = settings.salaryConfigured ? "今日战报" : "示例战报 · 尚未设置薪资"
        return "【\(settings.appName) · \(title)】\(dateKey(date))\n状态：\(snapshot.state.rawValue)\n今日已赚：\(money(snapshot.earned)) / \(money(snapshot.dailyPay))（进度 \(String(format: "%.1f", snapshot.progress * 100))%）\n时薪：\(money(snapshot.hourlyPay))" + (settings.masked ? "" : "\n" + wishText(settings, snapshot: snapshot))
    }
}
