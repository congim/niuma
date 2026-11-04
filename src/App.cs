using System;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;

[assembly: TargetFramework(".NETFramework,Version=v4.8", FrameworkDisplayName = ".NET Framework 4.8")]
[assembly: AssemblyTitle("牛马脱敏器")]
[assembly: AssemblyProduct("牛马脱敏器")]
[assembly: AssemblyVersion("1.0.0.0")]

namespace NiuMa
{
    public static class Program
    {
        [STAThread]
        public static void Main()
        {
            bool created;
            using (var mutex = new Mutex(true, "NiuMaTuoMinQi_SingleInstance", out created))
            {
                if (!created)
                {
                    Native.PostMessage((IntPtr)0xFFFF, Native.ShowMeMessage, IntPtr.Zero, IntPtr.Zero);
                    return;
                }
                var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
                app.DispatcherUnhandledException += (s, e) =>
                {
                    try { File.AppendAllText(Path.Combine(AppSettings.Dir, "error.log"), DateTime.Now + "  " + e.Exception + "\r\n\r\n"); } catch { }
                    e.Handled = true;
                };
                var win = new MainWindow(AppSettings.Load());
                win.Show();
                app.Run();
            }
        }
    }

    public static class Native
    {
        public static readonly int ShowMeMessage = RegisterWindowMessage("NiuMaTuoMinQi_ShowMe");

        [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int RegisterWindowMessage(string s);
        [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hWnd, int msg, IntPtr w, IntPtr l);
        [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr hWnd, int index);
        [DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr hWnd, int index, int value);
        [DllImport("user32.dll")] public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint mods, uint vk);
        [DllImport("user32.dll")] public static extern bool UnregisterHotKey(IntPtr hWnd, int id);

        public const int GWL_EXSTYLE = -20;
        public const int WS_EX_TRANSPARENT = 0x20;
        public const int WS_EX_TOOLWINDOW = 0x80;
        public const int WS_EX_LAYERED = 0x80000;
        public const int WM_HOTKEY = 0x0312;
        public const uint MOD_ALT = 1, MOD_CONTROL = 2, MOD_NOREPEAT = 0x4000;

        public static void SetExStyle(Window w, int flag, bool on)
        {
            var h = new WindowInteropHelper(w).Handle;
            if (h == IntPtr.Zero) return;
            int st = GetWindowLong(h, GWL_EXSTYLE);
            SetWindowLong(h, GWL_EXSTYLE, on ? (st | flag) : (st & ~flag));
        }
    }

    public static class Ui
    {
        public static readonly FontFamily Cn = new FontFamily("Microsoft YaHei UI, Microsoft YaHei, Segoe UI");
        public static readonly FontFamily Num = new FontFamily("Bahnschrift, Consolas, Segoe UI");
        public static readonly FontFamily Icon = new FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets");

        public static SolidColorBrush B(string hex)
        {
            var b = new SolidColorBrush((Color)ColorConverter.ConvertFromString(hex));
            b.Freeze();
            return b;
        }

        public static readonly Brush Ink = B("#2A2925");
        public static readonly Brush Sub = B("#6B665A");
        public static readonly Brush Carrot = B("#D2541E");
        public static readonly Brush Leaf = B("#4E7E32");
        public static readonly Brush Blue = B("#2D5592");
        public static readonly Brush Gray = B("#8A8579");

        public static TextBlock T(string text, double size, Brush fg, FontWeight? weight = null, FontFamily font = null)
        {
            return new TextBlock
            {
                Text = text, FontSize = size, Foreground = fg, FontFamily = font ?? Cn,
                FontWeight = weight ?? FontWeights.Normal, TextWrapping = TextWrapping.Wrap,
            };
        }

        public static Stream Res(string name)
        {
            return Assembly.GetExecutingAssembly().GetManifestResourceStream("NiuMa." + name);
        }

        public static BitmapSource LoadBackground(string path)
        {
            try
            {
                var bi = new BitmapImage();
                bi.BeginInit();
                bi.CacheOption = BitmapCacheOption.OnLoad;
                bi.DecodePixelWidth = 900;
                if (!string.IsNullOrEmpty(path) && File.Exists(path)) bi.UriSource = new Uri(path);
                else
                {
                    string local = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "beij.png");
                    if (File.Exists(local)) bi.UriSource = new Uri(local);
                    else bi.StreamSource = Res("beij.png");
                }
                bi.EndInit();
                bi.Freeze();
                return bi;
            }
            catch { return null; }
        }

        public static System.Drawing.Icon AppIcon()
        {
            try { using (var s = Res("app.ico")) return new System.Drawing.Icon(s); }
            catch { return System.Drawing.SystemIcons.Application; }
        }

        public static ImageSource AppIconImage()
        {
            try
            {
                var dec = new IconBitmapDecoder(Res("app.ico"), BitmapCreateOptions.None, BitmapCacheOption.OnLoad);
                BitmapFrame best = dec.Frames[0];
                foreach (var f in dec.Frames) if (f.PixelWidth >= 64 && f.PixelWidth < 256) best = f;
                return best;
            }
            catch { return null; }
        }

        public static Button IconButton(string glyph, string tip, Action onClick)
        {
            var b = new Button
            {
                Content = new TextBlock { Text = glyph, FontFamily = Icon, FontSize = 13, Foreground = Ink },
                ToolTip = tip, Width = 28, Height = 28, Cursor = System.Windows.Input.Cursors.Hand,
                Template = FlatTemplate(), Background = Brushes.Transparent,
            };
            b.Click += (s, e) => onClick();
            return b;
        }

        public static ControlTemplate FlatTemplate()
        {
            var t = new ControlTemplate(typeof(Button));
            var bd = new FrameworkElementFactory(typeof(Border));
            bd.Name = "bd";
            bd.SetValue(Border.CornerRadiusProperty, new CornerRadius(8));
            bd.SetBinding(Border.BackgroundProperty, new System.Windows.Data.Binding("Background") { RelativeSource = System.Windows.Data.RelativeSource.TemplatedParent });
            var cp = new FrameworkElementFactory(typeof(ContentPresenter));
            cp.SetValue(ContentPresenter.HorizontalAlignmentProperty, HorizontalAlignment.Center);
            cp.SetValue(ContentPresenter.VerticalAlignmentProperty, VerticalAlignment.Center);
            bd.AppendChild(cp);
            t.VisualTree = bd;
            var hover = new Trigger { Property = UIElement.IsMouseOverProperty, Value = true };
            hover.Setters.Add(new Setter(UIElement.OpacityProperty, 0.82));
            hover.Setters.Add(new Setter(Border.BackgroundProperty, B("#33000000"), "bd"));
            t.Triggers.Add(hover);
            var press = new Trigger { Property = System.Windows.Controls.Primitives.ButtonBase.IsPressedProperty, Value = true };
            press.Setters.Add(new Setter(UIElement.OpacityProperty, 0.65));
            t.Triggers.Add(press);
            return t;
        }
    }
}
