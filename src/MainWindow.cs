using System;
using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;
using Forms = System.Windows.Forms;

namespace NiuMa
{
    public partial class MainWindow : Window
    {
        AppSettings _s;
        Border _root, _panel, _barFill, _mini, _miniDot;
        Grid _barTrack;
        Border _bg;
        ImageBrush _bgBrush;
        FrameworkElement _full;
        TextBlock _title, _clock, _status, _countdown, _speed, _wish, _progressText, _hoursText,
                  _month, _monthSub, _hourly, _quote, _mask, _miniMask, _miniStatus;
        Odometer _odo, _miniOdo;
        Button _eyeBtn, _pinBtn;
        ScaleTransform _scale = new ScaleTransform(1, 1);
        Forms.NotifyIcon _tray;
        Stopwatch _sw = Stopwatch.StartNew();
        DateTime _base = DateTime.Now;
        WorkState? _lastState;
        long _lastSecond = -1;
        int _quoteIdx;
        DateTime _quoteAt = DateTime.MinValue;
        DispatcherTimer _timer;
        SettingsWindow _settingsWin;
        bool _exiting;
        Snapshot _snap;

        public MainWindow(AppSettings s)
        {
            _s = s;
            WindowStyle = WindowStyle.None;
            AllowsTransparency = true;
            Background = Brushes.Transparent;
            ResizeMode = ResizeMode.NoResize;
            ShowInTaskbar = false;
            SizeToContent = SizeToContent.WidthAndHeight;
            UseLayoutRounding = true;
            TextOptions.SetTextFormattingMode(this, TextFormattingMode.Ideal);
            Icon = Ui.AppIconImage();
            _quoteIdx = new Random().Next(1000);

            BuildUi();
            BuildTray();
            ApplySettings(_s, false);

            SourceInitialized += OnSourceInitialized;
            Loaded += (o, e) => PlaceWindow();
            // 换分辨率、换系统缩放、拖到别的屏幕时自动重新适配
            DpiChanged += (o, e) => Dispatcher.BeginInvoke(new Action(ApplyScale), DispatcherPriority.Background);
            Microsoft.Win32.SystemEvents.DisplaySettingsChanged += (o, e) => Dispatcher.BeginInvoke(new Action(ApplyScale), DispatcherPriority.Background);
            CompositionTarget.Rendering += OnRender;
            _timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
            _timer.Tick += (o, e) => Tick(true);
            _timer.Start();
            Closing += (o, e) => { if (!_exiting) { e.Cancel = true; HideToTray(); } };
        }

        public DateTime Now()
        {
            var t = _base + _sw.Elapsed;
            var real = DateTime.Now;
            if (Math.Abs((real - t).TotalSeconds) > 0.5) { _base = real; _sw.Restart(); t = real; }
            return t;
        }

        void OnSourceInitialized(object sender, EventArgs e)
        {
            var src = HwndSource.FromHwnd(new WindowInteropHelper(this).Handle);
            src.AddHook(WndProc);
            var h = src.Handle;
            uint mods = Native.MOD_CONTROL | Native.MOD_ALT | Native.MOD_NOREPEAT;
            Native.RegisterHotKey(h, 1, mods, (uint)'M');
            Native.RegisterHotKey(h, 2, mods, (uint)'T');
            Native.RegisterHotKey(h, 3, mods, (uint)'H');
            Native.SetExStyle(this, Native.WS_EX_TOOLWINDOW, true);
            Native.SetExStyle(this, Native.WS_EX_TRANSPARENT, _s.ClickThrough);
        }

        IntPtr WndProc(IntPtr hwnd, int msg, IntPtr w, IntPtr l, ref bool handled)
        {
            if (msg == Native.WM_HOTKEY)
            {
                int id = w.ToInt32();
                if (id == 1) ToggleVisible();
                else if (id == 2) ToggleClickThrough();
                else if (id == 3) ToggleMask();
                handled = true;
            }
            else if (msg == Native.ShowMeMessage)
            {
                ShowFromTray();
                handled = true;
            }
            return IntPtr.Zero;
        }

        void PlaceWindow()
        {
            ApplyScale();
            UpdateLayout();
            var wa = CurrentWorkArea();
            double vl = SystemParameters.VirtualScreenLeft, vt = SystemParameters.VirtualScreenTop;
            double vr = vl + SystemParameters.VirtualScreenWidth, vb = vt + SystemParameters.VirtualScreenHeight;
            bool valid = !double.IsNaN(_s.Left) && !double.IsNaN(_s.Top)
                && _s.Left + 60 < vr && _s.Left + ActualWidth - 60 > vl
                && _s.Top >= vt - 10 && _s.Top + 40 < vb;
            if (valid) { Left = _s.Left; Top = _s.Top; }
            else
            {
                Left = wa.Right - ActualWidth - 24;
                Top = wa.Top + 24;
            }
        }

        void SavePosition()
        {
            _s.Left = Left; _s.Top = Top;
            _s.Save();
        }

        // 窗口所在显示器的工作区（WPF 设备无关单位），多屏、不同 DPI 都按当前屏计算
        Rect CurrentWorkArea()
        {
            var h = new WindowInteropHelper(this).Handle;
            var src = PresentationSource.FromVisual(this);
            if (h == IntPtr.Zero || src == null || src.CompositionTarget == null) return SystemParameters.WorkArea;
            var wa = Forms.Screen.FromHandle(h).WorkingArea;
            var m = src.CompositionTarget.TransformFromDevice;
            return new Rect(m.Transform(new Point(wa.Left, wa.Top)), m.Transform(new Point(wa.Right, wa.Bottom)));
        }

        // 自动缩放：完整窗口高度约占屏幕工作区的一半，再乘以用户设置的「界面大小」
        // 无论 1080p / 2K / 4K、任何系统缩放比例，看起来的比例都一致
        const double RefHeight = 1050;

        double EffectiveScale()
        {
            var wa = CurrentWorkArea();
            double auto = Math.Max(0.6, Math.Min(3.0, wa.Height / RefHeight));
            double sc = auto * Math.Max(0.5, Math.Min(2.0, _s.UiZoom));
            // 无论怎么放大，都不超出屏幕（只影响显示，不写回设置）
            var c = (UIElement)Content;
            if (c != null && _scale.ScaleY > 0)
            {
                c.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
                double natW = c.DesiredSize.Width / _scale.ScaleX, natH = c.DesiredSize.Height / _scale.ScaleY;
                if (natH > 0) sc = Math.Min(sc, wa.Height * 0.94 / natH);
                if (natW > 0) sc = Math.Min(sc, wa.Width * 0.94 / natW);
            }
            return Math.Max(0.3, sc);
        }

        void ApplyScale()
        {
            double sc = Math.Round(EffectiveScale(), 3);
            if (Math.Abs(_scale.ScaleX - sc) < 0.001) return;
            _scale.ScaleX = sc; _scale.ScaleY = sc;
            if (!IsLoaded) return;
            UpdateLayout();
            KeepOnScreen();
        }

        void KeepOnScreen()
        {
            var wa = CurrentWorkArea();
            if (Left + ActualWidth > wa.Right) Left = Math.Max(wa.Left, wa.Right - ActualWidth);
            if (Top + ActualHeight > wa.Bottom) Top = Math.Max(wa.Top, wa.Bottom - ActualHeight);
            if (Left < wa.Left) Left = wa.Left;
            if (Top < wa.Top) Top = wa.Top;
        }
        static readonly Thickness RowGap = new Thickness(0, 0, 0, 6);

        void BuildUi()
        {
            _root = new Border
            {
                CornerRadius = new CornerRadius(16), Background = Ui.B("#F3ECD3"),
                BorderBrush = Ui.B("#40000000"), BorderThickness = new Thickness(1), Margin = new Thickness(12),
                Effect = new System.Windows.Media.Effects.DropShadowEffect { BlurRadius = 16, ShadowDepth = 3, Opacity = 0.28 },
            };
            var layers = new Grid { ClipToBounds = true };
            // 背景用画刷绘制，不参与布局，窗口大小只由内容决定
            _bg = new Border();
            RenderOptions.SetBitmapScalingMode(_bg, BitmapScalingMode.HighQuality);
            layers.Children.Add(_bg);
            _root.SizeChanged += (o, e) =>
            {
                layers.Clip = new RectangleGeometry(new Rect(0, 0, _root.ActualWidth - 2, _root.ActualHeight - 2), 15, 15);
            };

            var content = new Grid();
            content.Children.Add(BuildFull());
            content.Children.Add(BuildMini());
            layers.Children.Add(content);
            _root.Child = layers;
            _root.LayoutTransform = _scale;
            Content = _root;

            _root.MouseLeftButtonDown += (o, e) =>
            {
                if (e.ClickCount == 2) { ToggleMini(); return; }
                try { DragMove(); } catch { }
                SnapToEdges();
                SavePosition();
            };
            _root.ContextMenu = BuildMenu();
        }

        FrameworkElement BuildFull()
        {
            var sp = new StackPanel { Width = 330, Margin = new Thickness(14, 10, 14, 14) };

            var header = new DockPanel { LastChildFill = true, Margin = new Thickness(0, 0, 0, 8) };
            var btns = new StackPanel { Orientation = Orientation.Horizontal };
            _eyeBtn = Ui.IconButton(((char)0xE7B3).ToString(), "老板来了：隐藏金额 (Ctrl+Alt+H)", ToggleMask);
            _pinBtn = Ui.IconButton(((char)0xE718).ToString(), "窗口置顶", () => { _s.Topmost = !_s.Topmost; ApplyVisual(_s); _s.Save(); });
            btns.Children.Add(_eyeBtn);
            btns.Children.Add(_pinBtn);
            btns.Children.Add(Ui.IconButton(((char)0xE73F).ToString(), "迷你模式 (双击窗口也可切换)", ToggleMini));
            btns.Children.Add(Ui.IconButton(((char)0xE713).ToString(), "设置", OpenSettings));
            btns.Children.Add(Ui.IconButton(((char)0xE921).ToString(), "隐藏到托盘 (Ctrl+Alt+M)", HideToTray));
            DockPanel.SetDock(btns, Dock.Right);
            header.Children.Add(btns);
            var logo = new Image { Source = Ui.AppIconImage(), Width = 24, Height = 24, Margin = new Thickness(0, 0, 8, 0) };
            header.Children.Add(logo);
            _title = Ui.T("", 15, Ui.Ink, FontWeights.Bold);
            _title.TextWrapping = TextWrapping.NoWrap;
            _title.TextTrimming = TextTrimming.CharacterEllipsis;
            _title.VerticalAlignment = VerticalAlignment.Center;
            header.Children.Add(_title);
            sp.Children.Add(header);

            _panel = new Border { CornerRadius = new CornerRadius(12), Padding = new Thickness(16, 14, 16, 14) };
            var card = new StackPanel();
            _panel.Child = card;
            sp.Children.Add(_panel);

            _clock = Ui.T("", 13, Ui.Sub, null, Ui.Num);
            _clock.Margin = new Thickness(0, 0, 0, 8);
            card.Children.Add(_clock);
            _status = Ui.T("", 24, Ui.Blue, FontWeights.Bold);
            card.Children.Add(_status);
            _countdown = Ui.T("", 14, Ui.Ink);
            _countdown.Margin = new Thickness(0, 2, 0, 12);
            card.Children.Add(_countdown);

            card.Children.Add(Ui.T("今日已赚", 12, Ui.Sub));
            var amountHost = new Grid { Margin = new Thickness(0, 2, 0, 2), Height = 54 };
            _odo = new Odometer(Ui.Num, 40, Ui.Carrot) { VerticalAlignment = VerticalAlignment.Center };
            _mask = Ui.T("", 40, Ui.Carrot, FontWeights.Bold, Ui.Num);
            _mask.VerticalAlignment = VerticalAlignment.Center;
            amountHost.Children.Add(_odo);
            amountHost.Children.Add(_mask);
            card.Children.Add(amountHost);
            _speed = Ui.T("", 12, Ui.Sub);
            _speed.Margin = RowGap;
            card.Children.Add(_speed);
            _wish = Ui.T("", 13, Ui.Ink);
            _wish.Margin = new Thickness(0, 0, 0, 12);
            card.Children.Add(_wish);

            var pg = new DockPanel();
            _progressText = Ui.T("", 12, Ui.Sub);
            _hoursText = Ui.T("", 12, Ui.Sub, null, Ui.Num);
            DockPanel.SetDock(_hoursText, Dock.Right);
            pg.Children.Add(_hoursText);
            pg.Children.Add(_progressText);
            card.Children.Add(pg);
            _barTrack = new Grid { Height = 8, Margin = new Thickness(0, 6, 0, 14) };
            _barTrack.Children.Add(new Border { CornerRadius = new CornerRadius(4), Background = Ui.B("#22000000") });
            _barFill = new Border { CornerRadius = new CornerRadius(4), HorizontalAlignment = HorizontalAlignment.Left, Width = 0,
                Background = new LinearGradientBrush((Color)ColorConverter.ConvertFromString("#5E9A3A"), (Color)ColorConverter.ConvertFromString("#E0702E"), 0) };
            _barTrack.Children.Add(_barFill);
            card.Children.Add(_barTrack);

            card.Children.Add(new Border { Height = 1, Background = Ui.B("#1F000000"), Margin = new Thickness(0, 0, 0, 10) });
            var mrow = new DockPanel();
            _month = Ui.T("", 18, Ui.Blue, FontWeights.Bold, Ui.Num);
            DockPanel.SetDock(_month, Dock.Right);
            mrow.Children.Add(_month);
            var ml = Ui.T("本月累计", 13, Ui.Ink, FontWeights.SemiBold);
            ml.VerticalAlignment = VerticalAlignment.Center;
            mrow.Children.Add(ml);
            card.Children.Add(mrow);
            _monthSub = Ui.T("", 11, Ui.Gray);
            _monthSub.Margin = new Thickness(0, 2, 0, 10);
            card.Children.Add(_monthSub);
            _hourly = Ui.T("", 12, Ui.Sub);
            _hourly.LineHeight = 20;
            card.Children.Add(_hourly);

            _quote = Ui.T("", 12, Ui.Leaf, null);
            _quote.FontStyle = FontStyles.Italic;
            _quote.Margin = new Thickness(2, 10, 2, 0);
            _quote.TextAlignment = TextAlignment.Center;
            _quote.Cursor = Cursors.Hand;
            _quote.ToolTip = "点我换一句";
            _quote.MouseLeftButtonDown += (o, e) => { _quoteIdx++; _quoteAt = Now(); UpdateQuote(true); e.Handled = true; };
            sp.Children.Add(_quote);

            _full = sp;
            return sp;
        }

        FrameworkElement BuildMini()
        {
            var row = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
            _miniDot = new Border { Width = 8, Height = 8, CornerRadius = new CornerRadius(4), Margin = new Thickness(0, 0, 8, 0), VerticalAlignment = VerticalAlignment.Center };
            row.Children.Add(_miniDot);
            var host = new Grid();
            _miniOdo = new Odometer(Ui.Num, 24, Ui.Carrot) { VerticalAlignment = VerticalAlignment.Center };
            _miniMask = Ui.T("", 24, Ui.Carrot, FontWeights.Bold, Ui.Num);
            host.Children.Add(_miniOdo);
            host.Children.Add(_miniMask);
            row.Children.Add(host);
            _miniStatus = Ui.T("", 12, Ui.Sub);
            _miniStatus.VerticalAlignment = VerticalAlignment.Center;
            _miniStatus.Margin = new Thickness(10, 0, 0, 0);
            row.Children.Add(_miniStatus);
            _mini = new Border
            {
                Child = row, Padding = new Thickness(14, 8, 14, 8), CornerRadius = new CornerRadius(15),
                ToolTip = "双击展开 · 右键菜单",
            };
            return _mini;
        }
        static string Glyph(int code) { return ((char)code).ToString(); }

        MenuItem Item(string header, Action a)
        {
            var m = new MenuItem { Header = header };
            m.Click += (o, e) => a();
            return m;
        }

        ContextMenu BuildMenu()
        {
            var cm = new ContextMenu();
            cm.Opened += (o, e) =>
            {
                cm.Items.Clear();
                cm.Items.Add(Item("设置…", OpenSettings));
                cm.Items.Add(Item(_s.Mini ? "展开完整面板" : "切换迷你模式", ToggleMini));
                cm.Items.Add(Item(_s.Masked ? "显示金额" : "老板来了（隐藏金额）", ToggleMask));
                cm.Items.Add(new MenuItem { Header = "窗口置顶", IsCheckable = true, IsChecked = _s.Topmost });
                ((MenuItem)cm.Items[3]).Click += (a, b) => { _s.Topmost = !_s.Topmost; ApplyVisual(_s); _s.Save(); };
                cm.Items.Add(Item("鼠标穿透（Ctrl+Alt+T 取消）", ToggleClickThrough));
                cm.Items.Add(new Separator());
                bool work = Engine.IsWorkDay(_s, Now());
                cm.Items.Add(Item(work ? "今天请假/休息（不计薪）" : "今天要上班（计薪）", () =>
                {
                    bool normal = _s.WorkDaySet()[(int)Now().DayOfWeek];
                    bool target = !work;
                    _s.OverrideDate = Engine.DateKey(Now());
                    _s.OverrideMode = target == normal ? 0 : (target ? 2 : 1);
                    _s.Save(); _lastState = null; Tick(true);
                }));
                cm.Items.Add(Item("复制今日战报", CopyReport));
                cm.Items.Add(new Separator());
                cm.Items.Add(Item("隐藏到托盘", HideToTray));
                cm.Items.Add(Item("退出", ExitApp));
            };
            cm.Items.Add(new MenuItem());
            return cm;
        }

        void BuildTray()
        {
            _tray = new Forms.NotifyIcon { Icon = Ui.AppIcon(), Visible = true };
            var m = new Forms.ContextMenuStrip();
            m.Items.Add("显示 / 隐藏", null, (o, e) => ToggleVisible());
            m.Items.Add("设置…", null, (o, e) => OpenSettings());
            m.Items.Add("鼠标穿透 开/关", null, (o, e) => ToggleClickThrough());
            m.Items.Add("复制今日战报", null, (o, e) => CopyReport());
            m.Items.Add("-");
            m.Items.Add("退出", null, (o, e) => ExitApp());
            _tray.ContextMenuStrip = m;
            _tray.MouseClick += (o, e) => { if (e.Button == Forms.MouseButtons.Left) ToggleVisible(); };
        }

        public void ApplySettings(AppSettings s, bool save)
        {
            _s = s;
            var img = Ui.LoadBackground(_s.BgPath);
            _bgBrush = img == null ? null : new ImageBrush(img) { Stretch = Stretch.UniformToFill, AlignmentY = AlignmentY.Bottom };
            _bg.Background = _bgBrush;
            _odo.Configure(_s.Currency, _s.Odometer);
            _miniOdo.Configure(_s.Currency, _s.Odometer);
            ApplyVisual(_s);
            if (IsLoaded) Native.SetExStyle(this, Native.WS_EX_TRANSPARENT, _s.ClickThrough);
            _lastState = null;
            _lastSecond = -1;
            Tick(true);
            if (save) _s.Save();
        }

        public void ApplyVisual(AppSettings s)
        {
            string name = string.IsNullOrWhiteSpace(s.AppName) ? "牛马脱敏器" : s.AppName.Trim();
            Title = name;
            _title.Text = name;
            if (_tray != null) _tray.Text = name.Length > 60 ? name.Substring(0, 60) : name;
            _bg.Opacity = Math.Max(0, Math.Min(1, s.BgOpacity));
            byte a = (byte)Math.Round(Math.Max(0, Math.Min(1, s.PanelOpacity)) * 255);
            _panel.Background = new SolidColorBrush(Color.FromArgb(a, 0xFB, 0xF7, 0xEA));
            _mini.Background = new SolidColorBrush(Color.FromArgb((byte)Math.Max(a, (byte)120), 0xFB, 0xF7, 0xEA));
            Opacity = Math.Max(0.2, Math.Min(1, s.WindowOpacity));
            Topmost = s.Topmost;
            _pinBtn.Opacity = s.Topmost ? 1 : 0.35;
            _full.Visibility = s.Mini ? Visibility.Collapsed : Visibility.Visible;
            _mini.Visibility = s.Mini ? Visibility.Visible : Visibility.Collapsed;
            _root.CornerRadius = new CornerRadius(s.Mini ? 15 : 16);
            ApplyMask();
            ApplyScale();
        }

        void ApplyMask()
        {
            bool m = _s.Masked;
            _odo.Visibility = m ? Visibility.Hidden : Visibility.Visible;
            _miniOdo.Visibility = m ? Visibility.Hidden : Visibility.Visible;
            _mask.Text = m ? _s.Currency + " ****.**" : "";
            _miniMask.Text = _mask.Text;
            _mask.Visibility = _miniMask.Visibility = m ? Visibility.Visible : Visibility.Collapsed;
            ((TextBlock)_eyeBtn.Content).Text = Glyph(m ? 0xED1A : 0xE7B3);
        }

        void OnRender(object sender, EventArgs e)
        {
            if (!IsVisible || _snap == null) return;
            var now = Now();
            var r = Engine.Compute(_s, now);
            _snap = r;
            if (_s.Masked) return;
            if (_s.Mini) _miniOdo.SetValue(r.Earned, _s.Decimals, r.Speed);
            else
            {
                _odo.SetValue(r.Earned, _s.Decimals, r.Speed);
                if (_barTrack.ActualWidth > 0) _barFill.Width = _barTrack.ActualWidth * Math.Max(0, Math.Min(1, r.Progress));
            }
        }
        static readonly string[] Week = { "周日", "周一", "周二", "周三", "周四", "周五", "周六" };

        void Tick(bool force)
        {
            var now = Now();
            long sec = (long)(now - DateTime.MinValue).TotalSeconds;
            if (!force && sec == _lastSecond) return;
            _lastSecond = sec;
            var r = Engine.Compute(_s, now);
            _snap = r;
            string c = _s.Currency;

            _clock.Text = now.ToString("yyyy-MM-dd") + "  " + Week[(int)now.DayOfWeek] + "  " + now.ToString("HH:mm:ss");
            string st, cd, mini;
            Brush color;
            switch (r.State)
            {
                case WorkState.RestDay: st = "休息日"; color = Ui.Leaf; cd = "今天不用当牛马，好好休息。"; mini = "休息"; break;
                case WorkState.BeforeWork: st = "还没上班"; color = Ui.Gray; cd = "距离上班还有 " + Engine.Duration(r.SecondsToNext, true); mini = "未上班"; break;
                case WorkState.Lunch: st = "午休中"; color = Ui.Leaf; cd = "午休还剩 " + Engine.Duration(r.SecondsToNext, true) + "，暂停计薪"; mini = "午休"; break;
                case WorkState.Working: st = "上班中"; color = Ui.Blue; cd = "距离下班还有 " + Engine.Duration(r.SecondsToNext, true); mini = Engine.Duration(r.SecondsToNext, false) + "后下班"; break;
                case WorkState.Overtime: st = "加班中"; color = Ui.Carrot; cd = "已加班 " + Engine.Duration(r.OvertimeSeconds, true) + "，按 " + _s.OvertimeRate + " 倍计"; mini = "加班中"; break;
                default: st = "已下班"; color = Ui.Leaf; cd = "今天的牛马已下线，快跑！"; mini = "已下班"; break;
            }
            _status.Text = st; _status.Foreground = color; _countdown.Text = cd;
            _miniStatus.Text = mini; _miniDot.Background = color;

            int dec = Math.Max(2, Math.Min(6, _s.Decimals));
            _speed.Text = r.Speed > 0 ? "当前赚钱速度  " + c + r.Speed.ToString("F" + dec) + " / 秒  ·  " + c + (r.Speed * 60).ToString("F2") + " / 分钟" : "当前赚钱速度  " + c + "0 / 秒（暂停计薪）";
            _wish.Text = Engine.WishText(_s, r);
            _progressText.Text = "今日工时进度 " + (r.Progress * 100).ToString("F1") + "%";
            _hoursText.Text = (r.PaidElapsed / 3600).ToString("F2") + " / " + (r.PaidSeconds / 3600).ToString("F2") + " 小时";
            _barTrack.Visibility = r.State == WorkState.RestDay ? Visibility.Collapsed : Visibility.Visible;

            double month = Engine.MonthEarned(_s, now, r.Earned);
            double monthTotal = Engine.MonthTotal(_s, now);
            _month.Text = _s.Masked ? c + "****" : c + month.ToString("N2");
            int pd = Engine.DaysToPayDay(_s, now);
            _monthSub.Text = "已过的工作日按满勤计，本月满勤约 " + (_s.Masked ? "****" : c + monthTotal.ToString("N0")) + "  ·  " + (pd == 0 ? "今天发工资！" : "距离发薪日还有 " + pd + " 天");
            _hourly.Text = "时薪 " + c + r.HourlyPay.ToString("F2") + "   ·   分薪 " + c + (r.HourlyPay / 60).ToString("F3") +
                "\n今日满勤可得 " + (_s.Masked ? "****" : c + r.DailyPay.ToString("F2")) + (_s.SalaryMode == 1 ? "（月薪 " + (_s.Masked ? "****" : c + _s.Amount.ToString("N0")) + " ÷ " + _s.MonthDays + " 天）" : "");
            UpdateQuote(false);

            if (_lastState.HasValue && _lastState != r.State && _s.OffWorkNotify)
            {
                if (r.State == WorkState.AfterWork || (r.State == WorkState.Overtime && _lastState == WorkState.Working))
                    Notify("下班啦！", "今天赚到 " + c + r.Earned.ToString("F2") + "，牛马可以下线了。");
                else if (r.State == WorkState.Working && _lastState == WorkState.BeforeWork)
                    Notify("开始计薪", "新的一天，钱开始到账了。");
            }
            _lastState = r.State;
            if (_s.Masked) { _mask.Text = c + " ****.**"; _miniMask.Text = _mask.Text; }
            OnRender(null, null);
        }

        void UpdateQuote(bool force)
        {
            var q = _s.QuoteList();
            if (q.Length == 0) { _quote.Visibility = Visibility.Collapsed; return; }
            _quote.Visibility = Visibility.Visible;
            var now = Now();
            if (force || (now - _quoteAt).TotalMinutes >= 10 || string.IsNullOrEmpty(_quote.Text))
            {
                if (!force) { _quoteIdx++; _quoteAt = now; }
                _quote.Text = "“" + q[((_quoteIdx % q.Length) + q.Length) % q.Length] + "”";
            }
        }

        void Notify(string title, string text)
        {
            try { _tray.ShowBalloonTip(5000, title, text, Forms.ToolTipIcon.Info); } catch { }
        }

        void SnapToEdges()
        {
            // 拖到另一块屏幕后按那块屏重新计算大小
            ApplyScale();
            var wa = CurrentWorkArea();
            const double d = 18;
            if (Math.Abs(Left - wa.Left) < d) Left = wa.Left;
            if (Math.Abs(Top - wa.Top) < d) Top = wa.Top;
            if (Math.Abs(Left + ActualWidth - wa.Right) < d) Left = wa.Right - ActualWidth;
            if (Math.Abs(Top + ActualHeight - wa.Bottom) < d) Top = wa.Bottom - ActualHeight;
        }

        void ToggleMini()
        {
            double right = Left + ActualWidth;
            _s.Mini = !_s.Mini;
            ApplyVisual(_s);
            Tick(true);
            UpdateLayout();
            // 窗口贴在右侧时，以右边缘为锚点收放
            if (right >= CurrentWorkArea().Right - 30) Left = right - ActualWidth;
            KeepOnScreen();
            SavePosition();
        }

        void ToggleMask() { _s.Masked = !_s.Masked; ApplyMask(); Tick(true); _s.Save(); }

        void ToggleClickThrough()
        {
            _s.ClickThrough = !_s.ClickThrough;
            Native.SetExStyle(this, Native.WS_EX_TRANSPARENT, _s.ClickThrough);
            _s.Save();
            Notify(_s.ClickThrough ? "鼠标穿透已开启" : "鼠标穿透已关闭",
                _s.ClickThrough ? "窗口不再响应鼠标，按 Ctrl+Alt+T 或托盘菜单恢复。" : "可以拖动和点击窗口了。");
        }

        void ToggleVisible() { if (IsVisible) HideToTray(); else ShowFromTray(); }
        void HideToTray() { Hide(); }

        void ShowFromTray()
        {
            Show();
            if (WindowState == WindowState.Minimized) WindowState = WindowState.Normal;
            Activate();
            Tick(true);
        }

        void OpenSettings()
        {
            if (_settingsWin != null) { _settingsWin.Activate(); return; }
            _settingsWin = new SettingsWindow(_s.Clone(), this);
            _settingsWin.Closed += (o, e) => _settingsWin = null;
            _settingsWin.Show();
            _settingsWin.Activate();
        }

        public AppSettings Current { get { return _s; } }

        void CopyReport()
        {
            var now = Now();
            var r = Engine.Compute(_s, now);
            string c = _s.Currency;
            string txt = "【" + _title.Text + " · 今日战报】" + now.ToString("yyyy-MM-dd") + "\n" +
                "状态：" + _status.Text + "\n今日已赚：" + c + r.Earned.ToString("F2") + " / " + c + r.DailyPay.ToString("F2") +
                "（进度 " + (r.Progress * 100).ToString("F1") + "%）\n" + "时薪：" + c + r.HourlyPay.ToString("F2") + "\n" + _wish.Text;
            try { Clipboard.SetText(txt); Notify("战报已复制", "可以直接粘贴给同事了。"); } catch { }
        }

        void ExitApp()
        {
            _exiting = true;
            SavePosition();
            _tray.Visible = false;
            _tray.Dispose();
            var h = new WindowInteropHelper(this).Handle;
            for (int i = 1; i <= 3; i++) Native.UnregisterHotKey(h, i);
            Application.Current.Shutdown();
        }
    }
}
