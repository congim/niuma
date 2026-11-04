using System;
using System.Globalization;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;
using Microsoft.Win32;

namespace NiuMa
{
    public class SettingsWindow : Window
    {
        readonly AppSettings _orig;
        readonly AppSettings _s;
        readonly MainWindow _main;
        TextBox _name, _amount, _monthDays, _start, _end, _lunchS, _lunchE, _currency, _otRate, _payDay, _wish, _quotes, _bgPath;
        ComboBox _mode, _decimals;
        CheckBox _lunch, _topmost, _odometer, _overtime, _notify, _autostart;
        CheckBox[] _days = new CheckBox[7];
        Slider _bgOp, _panelOp, _winOp, _scale;
        TextBlock _error, _preview;
        bool _saved, _ready;

        const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
        const string RunName = "NiuMaTuoMinQi";

        public SettingsWindow(AppSettings s, MainWindow main)
        {
            _s = s; _main = main; _orig = main.Current.Clone();
            Title = "设置 - " + s.AppName;
            Icon = Ui.AppIconImage();
            Width = 520;
            Height = Math.Min(760, SystemParameters.WorkArea.Height * 0.9);
            MinWidth = 440; MinHeight = 420;
            WindowStartupLocation = WindowStartupLocation.CenterScreen;
            Topmost = main.Topmost;
            FontFamily = Ui.Cn;
            FontSize = 13;
            Background = Ui.B("#F7F3E6");
            UseLayoutRounding = true;
            Build();
            _ready = true;
            Closed += (o, e) => { if (!_saved) _main.ApplySettings(_orig, false); };
        }

        TextBox Box(string text, double width = double.NaN)
        {
            var t = new TextBox { Text = text, Width = width, Padding = new Thickness(4, 3, 4, 3), VerticalContentAlignment = VerticalAlignment.Center };
            t.TextChanged += (o, e) => Changed();
            return t;
        }

        CheckBox Check(string text, bool value)
        {
            var c = new CheckBox { Content = text, IsChecked = value, Margin = new Thickness(0, 0, 14, 0), VerticalAlignment = VerticalAlignment.Center };
            c.Click += (o, e) => Changed();
            return c;
        }

        Slider MakeSlider(double min, double max, double value, string fmt, Panel host)
        {
            var label = Ui.T("", 12, Ui.Sub, null, Ui.Num);
            label.Width = 46; label.TextAlignment = TextAlignment.Right; label.VerticalAlignment = VerticalAlignment.Center;
            var sl = new Slider { Minimum = min, Maximum = max, Value = value, Width = 220, VerticalAlignment = VerticalAlignment.Center, IsMoveToPointEnabled = true };
            Action upd = () => label.Text = sl.Value.ToString(fmt);
            upd();
            sl.ValueChanged += (o, e) => { upd(); Changed(); };
            host.Children.Add(sl);
            host.Children.Add(label);
            return sl;
        }

        Grid _grid;
        int _row;

        void Section(string title)
        {
            _grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            var t = Ui.T(title, 14, Ui.Ink, FontWeights.Bold);
            t.Margin = new Thickness(0, _row == 0 ? 0 : 16, 0, 6);
            Grid.SetRow(t, _row); Grid.SetColumnSpan(t, 2);
            _grid.Children.Add(t);
            _row++;
        }

        void Row(string label, UIElement control, string hint = null)
        {
            _grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            var l = Ui.T(label, 13, Ui.Sub);
            l.VerticalAlignment = VerticalAlignment.Center;
            l.Margin = new Thickness(0, 4, 12, 4);
            Grid.SetRow(l, _row);
            _grid.Children.Add(l);
            UIElement c = control;
            if (hint != null)
            {
                var sp = new StackPanel();
                sp.Children.Add(control);
                var h = Ui.T(hint, 11, Ui.Gray);
                h.Margin = new Thickness(0, 2, 0, 0);
                sp.Children.Add(h);
                c = sp;
            }
            ((FrameworkElement)c).Margin = new Thickness(0, 4, 0, 4);
            Grid.SetRow(c, _row); Grid.SetColumn(c, 1);
            _grid.Children.Add(c);
            _row++;
        }

        static StackPanel H(params UIElement[] items)
        {
            var sp = new StackPanel { Orientation = Orientation.Horizontal };
            foreach (var i in items) sp.Children.Add(i);
            return sp;
        }

        static TextBlock L(string s)
        {
            var t = Ui.T(s, 13, Ui.Sub);
            t.VerticalAlignment = VerticalAlignment.Center;
            t.Margin = new Thickness(6, 0, 6, 0);
            return t;
        }

        static string D(double v) { return v.ToString("0.##", CultureInfo.InvariantCulture); }
        void Build()
        {
            _grid = new Grid { Margin = new Thickness(20, 16, 20, 16) };
            _grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(110) });
            _grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

            Section("基本");
            _name = Box(_s.AppName);
            Row("软件名称", _name, "显示在窗口标题、托盘和战报里");

            Section("薪资");
            _mode = new ComboBox { Width = 90, SelectedIndex = _s.SalaryMode };
            _mode.Items.Add("日薪"); _mode.Items.Add("月薪");
            _mode.SelectionChanged += (o, e) => Changed();
            _amount = Box(D(_s.Amount), 110);
            _currency = Box(_s.Currency, 40);
            Row("薪资", H(_mode, L(""), _amount, L("货币符号"), _currency));
            _monthDays = Box(D(_s.MonthDays), 70);
            Row("月计薪天数", H(_monthDays, L("天")), "月薪模式下：日薪 = 月薪 ÷ 计薪天数（法定 21.75）");
            _preview = Ui.T("", 12, Ui.Blue);
            Row("换算", _preview);

            Section("上班时间");
            _start = Box(_s.StartTime, 70);
            _end = Box(_s.EndTime, 70);
            Row("上下班", H(_start, L("至"), _end), "24 小时制，例如 10:00 / 19:00");
            _lunch = Check("扣除午休（午休不计薪）", _s.LunchEnabled);
            _lunchS = Box(_s.LunchStart, 70);
            _lunchE = Box(_s.LunchEnd, 70);
            var lunchRow = new StackPanel();
            lunchRow.Children.Add(_lunch);
            var lr = H(_lunchS, L("至"), _lunchE);
            lr.Margin = new Thickness(0, 4, 0, 0);
            lunchRow.Children.Add(lr);
            Row("午休", lunchRow);
            var days = new WrapPanel();
            string[] names = { "日", "一", "二", "三", "四", "五", "六" };
            var set = _s.WorkDaySet();
            int[] order = { 1, 2, 3, 4, 5, 6, 0 };
            foreach (int d in order)
            {
                _days[d] = Check("周" + names[d], set[d]);
                _days[d].Margin = new Thickness(0, 2, 10, 2);
                days.Children.Add(_days[d]);
            }
            Row("工作日", days, "单次调休可在主窗口右键 → 今天请假 / 今天要上班");
            _overtime = Check("下班后继续计薪（加班）", _s.Overtime);
            _otRate = Box(D(_s.OvertimeRate), 50);
            Row("加班", H(_overtime, L("倍率"), _otRate));
            _payDay = Box(_s.PayDay.ToString(), 50);
            Row("发薪日", H(L("每月"), _payDay, L("号")));

            Section("显示");
            _decimals = new ComboBox { Width = 70 };
            for (int i = 2; i <= 6; i++) _decimals.Items.Add(i.ToString());
            _decimals.SelectedIndex = Math.Max(0, Math.Min(4, _s.Decimals - 2));
            _decimals.SelectionChanged += (o, e) => Changed();
            Row("小数位数", H(_decimals, L("位")));
            _odometer = Check("滚轮翻牌效果（关闭则为普通数字）", _s.Odometer);
            Row("数字样式", _odometer);
            var p1 = new StackPanel { Orientation = Orientation.Horizontal };
            _bgOp = MakeSlider(0, 1, _s.BgOpacity, "P0", p1);
            Row("背景图透明度", p1);
            var p2 = new StackPanel { Orientation = Orientation.Horizontal };
            _panelOp = MakeSlider(0, 1, _s.PanelOpacity, "P0", p2);
            Row("信息卡底色", p2, "调低可以让背景图更透出来");
            var p3 = new StackPanel { Orientation = Orientation.Horizontal };
            _winOp = MakeSlider(0.2, 1, _s.WindowOpacity, "P0", p3);
            Row("整体透明度", p3);
            var p4 = new StackPanel { Orientation = Orientation.Horizontal };
            _scale = MakeSlider(0.5, 2.0, _s.UiZoom, "P0", p4);
            var autoBtn = new Button { Content = "重置 100%", Padding = new Thickness(8, 2, 8, 2), Margin = new Thickness(8, 0, 0, 0) };
            autoBtn.Click += (o, e) => _scale.Value = 1.0;
            p4.Children.Add(autoBtn);
            Row("界面大小", p4, "100% = 按屏幕自动适配（约占屏幕高度一半）；任何分辨率都不会超出屏幕");
            _bgPath = Box(_s.BgPath);
            _bgPath.IsReadOnly = true;
            var pick = new Button { Content = "选择…", Padding = new Thickness(8, 2, 8, 2), Margin = new Thickness(6, 0, 0, 0) };
            pick.Click += (o, e) =>
            {
                var dlg = new OpenFileDialog { Filter = "图片|*.png;*.jpg;*.jpeg;*.bmp;*.gif|所有文件|*.*" };
                if (dlg.ShowDialog(this) == true) _bgPath.Text = dlg.FileName;
            };
            var reset = new Button { Content = "默认", Padding = new Thickness(8, 2, 8, 2), Margin = new Thickness(6, 0, 0, 0) };
            reset.Click += (o, e) => _bgPath.Text = "";
            var bgRow = new DockPanel();
            DockPanel.SetDock(reset, Dock.Right); DockPanel.SetDock(pick, Dock.Right);
            bgRow.Children.Add(reset); bgRow.Children.Add(pick); bgRow.Children.Add(_bgPath);
            Row("背景图片", bgRow, "留空使用默认的 beij.png");

            Section("其他");
            _topmost = Check("窗口始终置顶", _s.Topmost);
            _notify = Check("上下班时托盘提醒", _s.OffWorkNotify);
            _autostart = Check("开机自动启动", IsAutoStart());
            var others = new WrapPanel();
            others.Children.Add(_topmost); others.Children.Add(_notify); others.Children.Add(_autostart);
            Row("选项", others);
            _wish = Box(_s.Wishlist);
            _wish.AcceptsReturn = true; _wish.Height = 110; _wish.TextWrapping = TextWrapping.NoWrap;
            _wish.VerticalScrollBarVisibility = ScrollBarVisibility.Auto;
            Row("心愿单", _wish, "每行一个：名称=价格，用来提示「再过多久就能买到」");
            _quotes = Box(_s.Quotes);
            _quotes.AcceptsReturn = true; _quotes.Height = 110; _quotes.TextWrapping = TextWrapping.Wrap;
            _quotes.VerticalScrollBarVisibility = ScrollBarVisibility.Auto;
            Row("鼓励语录", _quotes, "每行一句，每 10 分钟轮换，点击语录可手动换");
            var keys = Ui.T("Ctrl+Alt+M 显示/隐藏    Ctrl+Alt+H 隐藏金额    Ctrl+Alt+T 鼠标穿透\n双击窗口切换迷你模式，拖动窗口靠近屏幕边缘会自动吸附", 12, Ui.Gray);
            Row("快捷键", keys);

            var scroll = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Content = _grid };

            _error = Ui.T("", 12, Ui.Carrot);
            _error.VerticalAlignment = VerticalAlignment.Center;
            var ok = new Button { Content = "保存", Width = 84, Height = 30, IsDefault = true, Margin = new Thickness(8, 0, 0, 0) };
            ok.Click += (o, e) => Save();
            var cancel = new Button { Content = "取消", Width = 84, Height = 30, IsCancel = true, Margin = new Thickness(8, 0, 0, 0) };
            var restore = new Button { Content = "恢复默认", Height = 30, Padding = new Thickness(10, 0, 10, 0) };
            restore.Click += (o, e) => RestoreDefaults();
            var bar = new DockPanel { Margin = new Thickness(20, 10, 20, 12), LastChildFill = true };
            DockPanel.SetDock(cancel, Dock.Right); DockPanel.SetDock(ok, Dock.Right); DockPanel.SetDock(restore, Dock.Left);
            bar.Children.Add(cancel); bar.Children.Add(ok); bar.Children.Add(restore);
            _error.Margin = new Thickness(10, 0, 0, 0);
            bar.Children.Add(_error);

            var root = new DockPanel();
            var barHost = new Border { Child = bar, BorderBrush = Ui.B("#1F000000"), BorderThickness = new Thickness(0, 1, 0, 0), Background = Ui.B("#EFE9D6") };
            DockPanel.SetDock(barHost, Dock.Bottom);
            root.Children.Add(barHost);
            root.Children.Add(scroll);
            Content = root;
            UpdatePreview();
        }
        static bool Num(TextBox t, out double v)
        {
            return double.TryParse(t.Text.Trim(), NumberStyles.Float, CultureInfo.InvariantCulture, out v);
        }

        // 把界面上的值写入 target，返回错误信息（null 表示全部有效）
        string Collect(AppSettings t)
        {
            double v;
            TimeSpan ts, te;
            t.AppName = _name.Text.Trim().Length == 0 ? "牛马脱敏器" : _name.Text.Trim();
            t.SalaryMode = _mode.SelectedIndex < 0 ? 0 : _mode.SelectedIndex;
            if (!Num(_amount, out v) || v < 0 || v > 1e9) return "薪资金额不正确";
            t.Amount = v;
            if (!Num(_monthDays, out v) || v <= 0 || v > 31) return "月计薪天数应在 1~31 之间";
            t.MonthDays = v;
            t.Currency = _currency.Text.Trim();
            if (!AppSettings.TryParseTime(_start.Text, out ts) || !AppSettings.TryParseTime(_end.Text, out te)) return "上下班时间格式应为 HH:mm";
            if (te <= ts) return "下班时间要晚于上班时间";
            t.StartTime = ts.ToString(@"hh\:mm"); t.EndTime = te.ToString(@"hh\:mm");
            t.LunchEnabled = _lunch.IsChecked == true;
            TimeSpan ls, le;
            if (!AppSettings.TryParseTime(_lunchS.Text, out ls) || !AppSettings.TryParseTime(_lunchE.Text, out le))
            {
                if (t.LunchEnabled) return "午休时间格式应为 HH:mm";
            }
            else
            {
                if (t.LunchEnabled && (le <= ls || ls < ts || le > te)) return "午休时间需在上班时段内，且结束晚于开始";
                t.LunchStart = ls.ToString(@"hh\:mm"); t.LunchEnd = le.ToString(@"hh\:mm");
            }
            var days = new System.Collections.Generic.List<string>();
            for (int i = 0; i < 7; i++) if (_days[i].IsChecked == true) days.Add(i.ToString());
            t.WorkDays = string.Join(",", days);
            t.Overtime = _overtime.IsChecked == true;
            if (!Num(_otRate, out v) || v < 0 || v > 10) return "加班倍率应在 0~10 之间";
            t.OvertimeRate = v;
            int pd;
            if (!int.TryParse(_payDay.Text.Trim(), out pd) || pd < 1 || pd > 31) return "发薪日应在 1~31 之间";
            t.PayDay = pd;
            t.Decimals = _decimals.SelectedIndex + 2;
            t.Odometer = _odometer.IsChecked == true;
            t.BgOpacity = Math.Round(_bgOp.Value, 2);
            t.PanelOpacity = Math.Round(_panelOp.Value, 2);
            t.WindowOpacity = Math.Round(_winOp.Value, 2);
            t.UiZoom = Math.Round(_scale.Value, 2);
            t.BgPath = _bgPath.Text.Trim();
            t.Topmost = _topmost.IsChecked == true;
            t.OffWorkNotify = _notify.IsChecked == true;
            t.Wishlist = _wish.Text.Replace("\r", "");
            t.Quotes = _quotes.Text.Replace("\r", "");
            return null;
        }

        // 实时预览：每次改动都应用到主窗口，取消时回滚
        void Changed()
        {
            if (!_ready) return;
            var err = Collect(_s);
            _error.Text = err ?? "";
            UpdatePreview();
            if (err == null)
            {
                var keep = _main.Current;
                _s.Left = keep.Left; _s.Top = keep.Top; _s.Mini = keep.Mini; _s.Masked = keep.Masked;
                _s.ClickThrough = keep.ClickThrough; _s.OverrideDate = keep.OverrideDate; _s.OverrideMode = keep.OverrideMode;
                _main.ApplySettings(_s.Clone(), false);
                Title = "设置 - " + _s.AppName;
            }
        }

        void UpdatePreview()
        {
            if (_preview == null) return;
            var tmp = _s.Clone();
            Collect(tmp);
            double daily = tmp.DailyPay();
            double sec = Engine.PaidSecondsPerDay(tmp);
            double hourly = sec > 0 ? daily / sec * 3600 : 0;
            _preview.Text = "日薪 " + tmp.Currency + daily.ToString("F2") + "  ·  每天计薪 " + (sec / 3600).ToString("0.##") + " 小时  ·  时薪 " + tmp.Currency + hourly.ToString("F2") +
                "\n每秒 " + tmp.Currency + (sec > 0 ? daily / sec : 0).ToString("F6");
        }

        void Save()
        {
            var err = Collect(_s);
            if (err != null) { _error.Text = err; return; }
            var keep = _main.Current;
            _s.Left = keep.Left; _s.Top = keep.Top; _s.Mini = keep.Mini; _s.Masked = keep.Masked;
            _s.ClickThrough = keep.ClickThrough; _s.OverrideDate = keep.OverrideDate; _s.OverrideMode = keep.OverrideMode;
            SetAutoStart(_autostart.IsChecked == true);
            _saved = true;
            _main.ApplySettings(_s.Clone(), true);
            Close();
        }

        void RestoreDefaults()
        {
            if (MessageBox.Show(this, "把所有设置恢复为默认值？（保存后生效）", "恢复默认", MessageBoxButton.OKCancel, MessageBoxImage.Question) != MessageBoxResult.OK) return;
            var d = new AppSettings();
            _ready = false;
            _name.Text = d.AppName; _mode.SelectedIndex = d.SalaryMode; _amount.Text = D(d.Amount); _currency.Text = d.Currency;
            _monthDays.Text = D(d.MonthDays); _start.Text = d.StartTime; _end.Text = d.EndTime;
            _lunch.IsChecked = d.LunchEnabled; _lunchS.Text = d.LunchStart; _lunchE.Text = d.LunchEnd;
            var set = d.WorkDaySet();
            for (int i = 0; i < 7; i++) _days[i].IsChecked = set[i];
            _overtime.IsChecked = d.Overtime; _otRate.Text = D(d.OvertimeRate); _payDay.Text = d.PayDay.ToString();
            _decimals.SelectedIndex = d.Decimals - 2; _odometer.IsChecked = d.Odometer;
            _bgOp.Value = d.BgOpacity; _panelOp.Value = d.PanelOpacity; _winOp.Value = d.WindowOpacity; _scale.Value = d.UiZoom;
            _bgPath.Text = d.BgPath; _topmost.IsChecked = d.Topmost; _notify.IsChecked = d.OffWorkNotify;
            _wish.Text = d.Wishlist; _quotes.Text = d.Quotes;
            _ready = true;
            Changed();
        }

        static string ExePath { get { return System.Reflection.Assembly.GetExecutingAssembly().Location; } }

        static bool IsAutoStart()
        {
            try
            {
                using (var k = Registry.CurrentUser.OpenSubKey(RunKey))
                {
                    var v = k == null ? null : k.GetValue(RunName) as string;
                    return v != null && v.Trim('"').Equals(ExePath, StringComparison.OrdinalIgnoreCase);
                }
            }
            catch { return false; }
        }

        static void SetAutoStart(bool on)
        {
            try
            {
                using (var k = Registry.CurrentUser.CreateSubKey(RunKey))
                {
                    if (on) k.SetValue(RunName, "\"" + ExePath + "\"");
                    else if (k.GetValue(RunName) != null) k.DeleteValue(RunName);
                }
            }
            catch { }
        }
    }
}
