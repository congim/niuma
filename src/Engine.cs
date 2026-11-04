using System;
using System.Collections.Generic;

namespace NiuMa
{
    public enum WorkState { RestDay, BeforeWork, Working, Lunch, AfterWork, Overtime }

    public class Snapshot
    {
        public WorkState State;
        public double Earned;          // 今日已赚
        public double Speed;           // 元/秒
        public double DailyPay;
        public double HourlyPay;
        public double PaidSeconds;     // 今日应计薪秒数
        public double PaidElapsed;     // 今日已计薪秒数
        public double OvertimeSeconds;
        public double SecondsToNext;   // 距离下一个节点（上班/下班/午休结束）
        public double Progress;        // 0..1
    }

    public static class Engine
    {
        public static string DateKey(DateTime d) { return d.ToString("yyyy-MM-dd"); }

        public static bool IsWorkDay(AppSettings s, DateTime date)
        {
            if (s.OverrideMode != 0 && s.OverrideDate == DateKey(date)) return s.OverrideMode == 2;
            return s.WorkDaySet()[(int)date.DayOfWeek];
        }

        static double Overlap(double a, double b, double t)
        {
            return Math.Max(0, Math.Min(b, t) - a);
        }

        struct Sched { public double S, E, LS, LE; public bool Lunch; }

        static Sched GetSched(AppSettings s)
        {
            var sc = new Sched();
            sc.S = AppSettings.Time(s.StartTime, new TimeSpan(10, 0, 0)).TotalSeconds;
            sc.E = AppSettings.Time(s.EndTime, new TimeSpan(19, 0, 0)).TotalSeconds;
            if (sc.E <= sc.S) sc.E = sc.S + 1;
            if (s.LunchEnabled)
            {
                sc.LS = Math.Max(sc.S, AppSettings.Time(s.LunchStart, new TimeSpan(12, 0, 0)).TotalSeconds);
                sc.LE = Math.Min(sc.E, AppSettings.Time(s.LunchEnd, new TimeSpan(13, 0, 0)).TotalSeconds);
                sc.Lunch = sc.LE > sc.LS && (sc.LE - sc.LS) < (sc.E - sc.S);
            }
            return sc;
        }

        static double PaidUntil(Sched sc, double t)
        {
            double v = Math.Min(Overlap(sc.S, sc.E, t), sc.E - sc.S);
            if (sc.Lunch) v -= Math.Min(Overlap(sc.LS, sc.LE, t), sc.LE - sc.LS);
            return Math.Max(0, v);
        }

        public static double PaidSecondsPerDay(AppSettings s)
        {
            var sc = GetSched(s);
            return PaidUntil(sc, 86400);
        }

        public static Snapshot Compute(AppSettings s, DateTime now)
        {
            var r = new Snapshot();
            var sc = GetSched(s);
            double t = (now - now.Date).TotalSeconds;
            r.DailyPay = s.DailyPay();
            r.PaidSeconds = PaidUntil(sc, 86400);
            double rate = r.PaidSeconds > 0 ? r.DailyPay / r.PaidSeconds : 0;
            r.HourlyPay = rate * 3600;

            if (!IsWorkDay(s, now))
            {
                r.State = WorkState.RestDay;
                return r;
            }

            r.PaidElapsed = PaidUntil(sc, t);
            r.Earned = rate * r.PaidElapsed;
            r.Progress = r.PaidSeconds > 0 ? r.PaidElapsed / r.PaidSeconds : 0;

            if (t < sc.S)
            {
                r.State = WorkState.BeforeWork;
                r.SecondsToNext = sc.S - t;
            }
            else if (sc.Lunch && t >= sc.LS && t < sc.LE)
            {
                r.State = WorkState.Lunch;
                r.SecondsToNext = sc.LE - t;
            }
            else if (t < sc.E)
            {
                r.State = WorkState.Working;
                r.Speed = rate;
                r.SecondsToNext = sc.E - t;
            }
            else if (s.Overtime)
            {
                r.State = WorkState.Overtime;
                r.OvertimeSeconds = t - sc.E;
                r.Speed = rate * s.OvertimeRate;
                r.Earned += r.OvertimeSeconds * r.Speed;
            }
            else
            {
                r.State = WorkState.AfterWork;
            }
            return r;
        }

        // 剩余计薪秒数（用于心愿单预估）
        public static double PaidRemaining(Snapshot r) { return Math.Max(0, r.PaidSeconds - r.PaidElapsed); }

        public static double MonthEarned(AppSettings s, DateTime now, double todayEarned)
        {
            double sum = 0, daily = s.DailyPay();
            for (var d = new DateTime(now.Year, now.Month, 1); d < now.Date; d = d.AddDays(1))
                if (IsWorkDay(s, d)) sum += daily;
            return sum + todayEarned;
        }

        public static double MonthTotal(AppSettings s, DateTime now)
        {
            double sum = 0, daily = s.DailyPay();
            int days = DateTime.DaysInMonth(now.Year, now.Month);
            for (int i = 1; i <= days; i++)
                if (IsWorkDay(s, new DateTime(now.Year, now.Month, i))) sum += daily;
            return sum;
        }

        public static int DaysToPayDay(AppSettings s, DateTime now)
        {
            int pd = Math.Max(1, Math.Min(31, s.PayDay));
            var today = now.Date;
            var target = new DateTime(today.Year, today.Month, Math.Min(pd, DateTime.DaysInMonth(today.Year, today.Month)));
            if (target < today)
            {
                var nm = today.AddMonths(1);
                target = new DateTime(nm.Year, nm.Month, Math.Min(pd, DateTime.DaysInMonth(nm.Year, nm.Month)));
            }
            return (int)(target - today).TotalDays;
        }

        public static string Duration(double sec, bool withSeconds)
        {
            if (sec < 0) sec = 0;
            long total = (long)Math.Floor(sec);
            long h = total / 3600, m = total % 3600 / 60, ss = total % 60;
            if (withSeconds)
            {
                if (h > 0) return h + "小时" + m.ToString("00") + "分" + ss.ToString("00") + "秒";
                if (m > 0) return m + "分" + ss.ToString("00") + "秒";
                return ss + "秒";
            }
            if (h > 0) return h + " 小时 " + m + " 分";
            if (m > 0) return m + " 分钟";
            return "不到 1 分钟";
        }

        public static string WishText(AppSettings s, Snapshot r)
        {
            var items = s.WishItems();
            if (items.Count == 0) return "";
            string best = null, next = null;
            double nextPrice = 0;
            foreach (var it in items)
            {
                if (it.Value <= r.Earned) best = it.Key;
                else { next = it.Key; nextPrice = it.Value; break; }
            }
            string bestOfDay = null;
            foreach (var it in items) if (it.Value <= r.DailyPay) bestOfDay = it.Key;

            switch (r.State)
            {
                case WorkState.RestDay:
                    return "休息日，花钱的事交给明天的自己。";
                case WorkState.BeforeWork:
                    return bestOfDay != null ? "今天搬完砖，能换" + bestOfDay + "。" : "今天也是为梦想窝囊的一天。";
                case WorkState.Working:
                case WorkState.Lunch:
                case WorkState.Overtime:
                    if (next != null && r.Speed > 0)
                    {
                        double need = (nextPrice - r.Earned) / r.Speed;
                        if (r.State == WorkState.Overtime || need <= PaidRemaining(r))
                            return "再过 " + Duration(need, false) + "，" + next + "就赚回来了。";
                    }
                    if (best != null) return "今天已经赚到" + best + "了，稳住。";
                    if (next != null) return "离" + next + "还差 " + s.Currency + (nextPrice - r.Earned).ToString("0.00") + "。";
                    return "";
                default:
                    return best != null ? "今天赚到了" + best + "，收工！" : "今天收工，辛苦了。";
            }
        }
    }
}
