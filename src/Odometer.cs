using System;
using System.Collections.Generic;
using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace NiuMa
{
    // 机械滚轮式数字：每一位都是连续滚动的，低位进位时高位跟着平滑滚动
    public class Odometer : StackPanel
    {
        class Col { public Canvas Box; public TranslateTransform Tf; }

        readonly List<Col> _cols = new List<Col>();
        readonly List<UIElement> _items = new List<UIElement>();
        TextBlock _prefix, _plain;
        int _intDigits = -1, _decimals = -1;
        double _cellW, _cellH, _fontSize;
        FontFamily _font;
        Brush _brush;
        bool _rolling = true;
        string _currency = "¥";

        public Odometer(FontFamily font, double fontSize, Brush brush)
        {
            Orientation = Orientation.Horizontal;
            _font = font; _fontSize = fontSize; _brush = brush;
            var ft = new FormattedText("0", CultureInfo.InvariantCulture, FlowDirection.LeftToRight,
                new Typeface(font, FontStyles.Normal, FontWeights.Bold, FontStretches.Normal), fontSize, brush, 1.0);
            double w = 0;
            for (char c = '0'; c <= '9'; c++)
            {
                var f = new FormattedText(c.ToString(), CultureInfo.InvariantCulture, FlowDirection.LeftToRight,
                    new Typeface(font, FontStyles.Normal, FontWeights.Bold, FontStretches.Normal), fontSize, brush, 1.0);
                w = Math.Max(w, f.WidthIncludingTrailingWhitespace);
            }
            _cellW = Math.Ceiling(w);
            _cellH = Math.Ceiling(ft.Height);
            UseLayoutRounding = false;
        }

        TextBlock MakeText(string s)
        {
            return new TextBlock
            {
                Text = s, FontFamily = _font, FontSize = _fontSize, FontWeight = FontWeights.Bold,
                Foreground = _brush, VerticalAlignment = VerticalAlignment.Center, Height = _cellH,
            };
        }

        public void Configure(string currency, bool rolling)
        {
            if (currency == _currency && rolling == _rolling) return;
            _currency = currency; _rolling = rolling; _intDigits = -1;
        }

        void Rebuild(int intDigits, int decimals)
        {
            Children.Clear(); _cols.Clear(); _items.Clear();
            _intDigits = intDigits; _decimals = decimals;
            _prefix = MakeText(_currency);
            _prefix.Margin = new Thickness(0, 0, 4, 0);
            Children.Add(_prefix);
            if (!_rolling)
            {
                _plain = MakeText("");
                Children.Add(_plain);
                return;
            }
            int total = intDigits + decimals;
            for (int i = 0; i < total; i++)
            {
                if (i == intDigits)
                {
                    var dot = MakeText(".");
                    Children.Add(dot);
                }
                var box = new Canvas { Width = _cellW, Height = _cellH, ClipToBounds = true };
                var strip = new StackPanel();
                for (int d = 0; d <= 10; d++)
                {
                    var t = MakeText((d % 10).ToString());
                    t.Width = _cellW;
                    t.TextAlignment = TextAlignment.Center;
                    strip.Children.Add(t);
                }
                var tf = new TranslateTransform();
                strip.RenderTransform = tf;
                box.Children.Add(strip);
                Children.Add(box);
                _cols.Add(new Col { Box = box, Tf = tf });
            }
        }

        public void SetValue(double value, int decimals, double speed)
        {
            if (value < 0) value = 0;
            decimals = Math.Max(0, Math.Min(6, decimals));
            long ip = (long)Math.Floor(value);
            int intDigits = Math.Max(1, ip.ToString().Length);
            if (intDigits != _intDigits || decimals != _decimals) Rebuild(intDigits, decimals);

            if (!_rolling)
            {
                _plain.Text = value.ToString("F" + decimals, CultureInfo.InvariantCulture);
                return;
            }

            // 每一位独立计算：v = 该位的连续值。转得太快（肉眼看不清）的位直接显示真实数字，
            // 其余位在进位前约 0.25 秒内用缓动曲线滚到下一个数字，整体连续无跳变。
            // 先换算成「最小位的整数单位」，再除以 10 的整数次幂，避免 100 被算成 99.999… 显示成 000
            int n = _cols.Count;
            double scaledValue = value * Math.Pow(10, decimals);
            double scaledSpeed = speed * Math.Pow(10, decimals);
            for (int i = n - 1; i >= 0; i--)
            {
                int k = n - 1 - i;                          // 0 = 最低位
                double p10 = Math.Pow(10, k);
                double v = scaledValue / p10 + 1e-7;
                double fl = Math.Floor(v);
                int digit = (int)(fl % 10);
                double f = Math.Max(0, v - fl - 1e-7);
                double rate = scaledSpeed / p10;            // 该位每秒变化多少个数
                double offset = digit;
                if (rate > 0 && rate <= 12)
                {
                    double w = Math.Min(1.0, rate * 0.25);
                    double p = (f - (1 - w)) / w;
                    if (p > 0)
                    {
                        p = Math.Min(1, p);
                        offset += p * p * (3 - 2 * p);
                    }
                }
                _cols[i].Tf.Y = -offset * _cellH;
            }
        }
    }
}
