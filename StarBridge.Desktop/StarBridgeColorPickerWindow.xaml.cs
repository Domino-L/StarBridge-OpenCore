using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Color = System.Windows.Media.Color;
using Button = System.Windows.Controls.Button;
using KeyEventArgs = System.Windows.Input.KeyEventArgs;
using MouseEventArgs = System.Windows.Input.MouseEventArgs;
using Point = System.Windows.Point;

namespace StarBridge.Desktop;

public partial class StarBridgeColorPickerWindow : Window
{
    private const int FieldPixelWidth = 278;
    private const int FieldPixelHeight = 210;
    private bool _isUpdatingControls;
    private bool _isDraggingColorField;
    private double _hue;
    private double _saturation;
    private double _value;

    public StarBridgeColorPickerWindow(Color initialColor, bool useChinese)
    {
        InitializeComponent();
        ApplyLanguage(useChinese);
        SetFromColor(initialColor, updateHue: true);
    }

    public Color SelectedColor { get; private set; }

    private void ApplyLanguage(bool zh)
    {
        Title = zh ? "准星颜色" : "Crosshair color";
        DialogTitleText.Text = Title;
        SpectrumLabelText.Text = zh ? "连续色域" : "COLOR FIELD";
        HueLabelText.Text = zh ? "色相" : "HUE";
        SpectrumHintText.Text = zh ? "拖动定位颜色；色相轨道用于切换主色域。" : "Drag to locate a color; use the hue rail to change its range.";
        SignalPreviewLabelText.Text = zh ? "信号预览" : "SIGNAL PREVIEW";
        PaletteLabelText.Text = zh ? "色板" : "PALETTE";
        FooterHintText.Text = zh ? "应用后将自动关闭主题跟随，使用此固定颜色。" : "Applying this color disables theme color following.";
        CancelButton.Content = zh ? "取消" : "Cancel";
        ApplyButton.Content = zh ? "应用颜色" : "Apply color";
    }

    private void SetFromColor(Color color, bool updateHue)
    {
        SelectedColor = Color.FromRgb(color.R, color.G, color.B);
        RgbToHsv(SelectedColor, out var hue, out var saturation, out var value);
        if (updateHue || saturation > 0.001)
        {
            _hue = hue;
        }

        _saturation = saturation;
        _value = value;
        UpdateControls(renderField: true);
    }

    private void SetFromHsv(bool renderField)
    {
        SelectedColor = HsvToColor(_hue, _saturation, _value);
        UpdateControls(renderField);
    }

    private void UpdateControls(bool renderField)
    {
        _isUpdatingControls = true;
        try
        {
            if (renderField)
            {
                RenderColorField();
            }

            var hueChannel = Math.Clamp((int)Math.Round(_hue / 360.0 * 255.0), 0, 255);
            HueSlider.Value = hueChannel;
            HueValueText.Text = hueChannel.ToString();
            RedSlider.Value = SelectedColor.R;
            GreenSlider.Value = SelectedColor.G;
            BlueSlider.Value = SelectedColor.B;
            RedValueText.Text = SelectedColor.R.ToString();
            GreenValueText.Text = SelectedColor.G.ToString();
            BlueValueText.Text = SelectedColor.B.ToString();
            var hex = $"#{SelectedColor.R:X2}{SelectedColor.G:X2}{SelectedColor.B:X2}";
            HexColorBox.Text = hex;
            PreviewHexText.Text = hex;
            SelectedColorPreview.Background = new SolidColorBrush(SelectedColor);
            Canvas.SetLeft(ColorFieldMarker, Math.Clamp(_saturation * FieldPixelWidth - ColorFieldMarker.Width / 2, 0, FieldPixelWidth - ColorFieldMarker.Width));
            Canvas.SetTop(ColorFieldMarker, Math.Clamp((1 - _value) * FieldPixelHeight - ColorFieldMarker.Height / 2, 0, FieldPixelHeight - ColorFieldMarker.Height));
        }
        finally
        {
            _isUpdatingControls = false;
        }
    }

    private void RenderColorField()
    {
        var pixels = new byte[FieldPixelWidth * FieldPixelHeight * 4];
        var index = 0;
        for (var y = 0; y < FieldPixelHeight; y++)
        {
            var value = 1.0 - y / (double)(FieldPixelHeight - 1);
            for (var x = 0; x < FieldPixelWidth; x++)
            {
                var saturation = x / (double)(FieldPixelWidth - 1);
                var color = HsvToColor(_hue, saturation, value);
                pixels[index++] = color.B;
                pixels[index++] = color.G;
                pixels[index++] = color.R;
                pixels[index++] = 255;
            }
        }

        var bitmap = new WriteableBitmap(FieldPixelWidth, FieldPixelHeight, 96, 96, PixelFormats.Bgra32, null);
        bitmap.WritePixels(new Int32Rect(0, 0, FieldPixelWidth, FieldPixelHeight), pixels, FieldPixelWidth * 4, 0);
        bitmap.Freeze();
        ColorFieldImage.Source = bitmap;
    }

    private void UpdateFromColorField(Point point)
    {
        _saturation = Math.Clamp(point.X / FieldPixelWidth, 0, 1);
        _value = 1 - Math.Clamp(point.Y / FieldPixelHeight, 0, 1);
        SetFromHsv(renderField: false);
    }

    private void ColorField_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        _isDraggingColorField = true;
        ((UIElement)sender).CaptureMouse();
        UpdateFromColorField(e.GetPosition((IInputElement)sender));
        e.Handled = true;
    }

    private void ColorField_MouseMove(object sender, MouseEventArgs e)
    {
        if (_isDraggingColorField && e.LeftButton == MouseButtonState.Pressed)
        {
            UpdateFromColorField(e.GetPosition((IInputElement)sender));
        }
    }

    private void ColorField_MouseLeftButtonUp(object sender, MouseButtonEventArgs e)
    {
        _isDraggingColorField = false;
        ((UIElement)sender).ReleaseMouseCapture();
        e.Handled = true;
    }

    private void HueSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (_isUpdatingControls)
        {
            return;
        }

        _hue = Math.Clamp(e.NewValue, 0, 255) / 255.0 * 360.0;
        SetFromHsv(renderField: true);
    }

    private void RgbSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (_isUpdatingControls || RedSlider is null || GreenSlider is null || BlueSlider is null)
        {
            return;
        }

        SetFromColor(Color.FromRgb(
            (byte)Math.Round(RedSlider.Value),
            (byte)Math.Round(GreenSlider.Value),
            (byte)Math.Round(BlueSlider.Value)),
            updateHue: false);
    }

    private void SwatchButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: string value } && TryParseHexColor(value, out var color))
        {
            SetFromColor(color, updateHue: true);
        }
    }

    private void HexColorBox_LostKeyboardFocus(object sender, KeyboardFocusChangedEventArgs e)
    {
        CommitHexColor();
    }

    private void HexColorBox_PreviewKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Enter)
        {
            CommitHexColor();
            Keyboard.ClearFocus();
            e.Handled = true;
        }
    }

    private void CommitHexColor()
    {
        if (_isUpdatingControls)
        {
            return;
        }

        if (TryParseHexColor(HexColorBox.Text, out var color))
        {
            SetFromColor(color, updateHue: true);
        }
        else
        {
            UpdateControls(renderField: false);
        }
    }

    private static bool TryParseHexColor(string? value, out Color color)
    {
        color = default;
        var normalized = value?.Trim();
        if (normalized is null || !normalized.StartsWith('#') || normalized.Length != 7)
        {
            return false;
        }

        return byte.TryParse(normalized.AsSpan(1, 2), System.Globalization.NumberStyles.HexNumber, null, out var red) &&
               byte.TryParse(normalized.AsSpan(3, 2), System.Globalization.NumberStyles.HexNumber, null, out var green) &&
               byte.TryParse(normalized.AsSpan(5, 2), System.Globalization.NumberStyles.HexNumber, null, out var blue) &&
               SetParsedColor(red, green, blue, out color);
    }

    private static bool SetParsedColor(byte red, byte green, byte blue, out Color color)
    {
        color = Color.FromRgb(red, green, blue);
        return true;
    }

    private static void RgbToHsv(Color color, out double hue, out double saturation, out double value)
    {
        var red = color.R / 255.0;
        var green = color.G / 255.0;
        var blue = color.B / 255.0;
        var max = Math.Max(red, Math.Max(green, blue));
        var min = Math.Min(red, Math.Min(green, blue));
        var delta = max - min;

        hue = 0;
        if (delta > 0.0001)
        {
            if (Math.Abs(max - red) < 0.0001)
            {
                hue = 60 * (((green - blue) / delta) % 6);
            }
            else if (Math.Abs(max - green) < 0.0001)
            {
                hue = 60 * ((blue - red) / delta + 2);
            }
            else
            {
                hue = 60 * ((red - green) / delta + 4);
            }
        }

        if (hue < 0)
        {
            hue += 360;
        }

        saturation = max <= 0 ? 0 : delta / max;
        value = max;
    }

    private static Color HsvToColor(double hue, double saturation, double value)
    {
        hue = ((hue % 360) + 360) % 360;
        saturation = Math.Clamp(saturation, 0, 1);
        value = Math.Clamp(value, 0, 1);
        var chroma = value * saturation;
        var x = chroma * (1 - Math.Abs((hue / 60) % 2 - 1));
        var match = value - chroma;
        var (red, green, blue) = hue switch
        {
            < 60 => (chroma, x, 0.0),
            < 120 => (x, chroma, 0.0),
            < 180 => (0.0, chroma, x),
            < 240 => (0.0, x, chroma),
            < 300 => (x, 0.0, chroma),
            _ => (chroma, 0.0, x)
        };

        return Color.FromRgb(
            (byte)Math.Round((red + match) * 255),
            (byte)Math.Round((green + match) * 255),
            (byte)Math.Round((blue + match) * 255));
    }

    private void Header_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (e.LeftButton == MouseButtonState.Pressed)
        {
            DragMove();
        }
    }

    private void ApplyButton_Click(object sender, RoutedEventArgs e)
    {
        CommitHexColor();
        DialogResult = true;
    }

    private void CancelButton_Click(object sender, RoutedEventArgs e) => DialogResult = false;

    private void CloseButton_Click(object sender, RoutedEventArgs e) => DialogResult = false;

    private void Window_PreviewKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Escape)
        {
            DialogResult = false;
            e.Handled = true;
        }
    }
}
