using StarBridge.HostRuntime.Tools;
using StarBridge.OverlayRuntime.Windows;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;

internal static class ExecHangarGameOverlayTests
{
    internal static void Run()
    {
        var checks = 0;
        void Check(bool value, string why) { checks++; if (!value) throw new Exception(why); }
        foreach (var area in new[] { new System.Drawing.Rectangle(0, 0, 1920, 1080), new(-1920, 120, 1920, 1080), new(300, 200, 1100, 600), new(0, 0, 160, 80) })
        foreach (var dpi in new uint[] { 96, 120, 144, 192 })
        foreach (var position in ExecHangarGameOverlay.Positions)
        {
            var bounds = ExecHangarGameOverlayPlacement.ForGame(area, dpi, position);
            Check(area.Contains(bounds), "Every position fits the actual game client at every DPI, including negative monitors");
            if (position.EndsWith("Center", StringComparison.Ordinal)) Check(Math.Abs(bounds.Left + bounds.Width / 2d - area.Left - area.Width / 2d) <= .5, "Top/bottom centers are centered to the game, not the main screen");
        }
        Exception? failure = null;
        var thread = new Thread(() =>
        {
            try
            {
                foreach (var locale in new[] { "zh-CN", "zh-TW", "en-US" })
                foreach (var stage in new[] { "open", "closed", "leave" })
                foreach (var dpi in new[] { 96, 144, 192 })
                {
                    var now = new DateTimeOffset(2026, 10, 10, 0, 0, 0, TimeSpan.Zero);
                    var frame = new ExecHangarGameOverlayFrame(now, now.AddMinutes(12), stage != "closed", stage == "open" ? 5 : 0, stage == "closed" ? 5 : 0, "topLeft");
                    var card = new ExecHangarGameOverlayCard(); card.Update(frame, locale);
                    Check(card.Width > 100 && card.Width < 200 && card.Height == 52 && !card.IsHitTestVisible, "Game card fits its two-line content rather than reserving a blank right column");
                    card.Measure(new(card.Width, card.Height)); card.Arrange(new Rect(0, 0, card.Width, card.Height)); card.UpdateLayout();
                    var bitmap = new RenderTargetBitmap((int)(card.Width * dpi / 96d), (int)(card.Height * dpi / 96d), dpi, dpi, PixelFormats.Pbgra32); bitmap.Render(card);
                    var pixels = new byte[bitmap.PixelWidth * bitmap.PixelHeight * 4]; bitmap.CopyPixels(pixels, bitmap.PixelWidth * 4, 0);
                    Check(pixels[3] == 0 && pixels[^1] == 0 && Enumerable.Range(0, pixels.Length / 4).Any(i => pixels[i * 4 + 3] > 0), "Real renderer has a fully transparent background and visible text/lamps");
                    var rightmost = Enumerable.Range(0, pixels.Length / 4).Where(i => pixels[i * 4 + 3] > 0).Max(i => i % bitmap.PixelWidth);
                    Check(bitmap.PixelWidth - 1 - rightmost <= 8 * dpi / 96d, "Actual rendered content uses the width with only a small edge inset");
                    var right = ExecHangarGameOverlayPlacement.ForGame(new(0, 0, 1920, 1080), (uint)dpi, "topRight", card.Width);
                    Check(right.Right == 1920 - (int)Math.Round(16 * dpi / 96d), "Right anchor follows content width without a blank fixed-width column");
                    Check(ExecHangarGameOverlayCard.Countdown(frame) == "00:12:00", "Boundary countdown retains exact time");
                    if (Environment.GetEnvironmentVariable("STARBRIDGE_HANGAR_GAME_RENDER_OUTPUT") is { Length: > 0 } output)
                    {
                        Directory.CreateDirectory(output); var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
                        using var file = File.Create(Path.Combine(output, $"hangar-game-{locale}-{stage}-{dpi}.png")); encoder.Save(file);
                    }
                }
            }
            catch (Exception e) { failure = e; }
        });
        thread.SetApartmentState(ApartmentState.STA); thread.Start(); thread.Join();
        if (failure is not null) throw failure;
        var foreground = GetForegroundWindow();
        using (var sink = new NativeExecHangarGameOverlay(() => false, () => "zh-CN"))
        {
            Check(sink.Available, "Native STA owns its hidden surface");
            var field = typeof(NativeExecHangarGameOverlay).GetField("_window", System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic)!;
            var window = (Window)field.GetValue(sink)!;
            var handle = window.Dispatcher.Invoke(() => new System.Windows.Interop.WindowInteropHelper(window).Handle);
            var styles = GetWindowLongPtr(handle, -20).ToInt64();
            Check((styles & 0x08000000L) != 0 && (styles & 0x20L) != 0 && (styles & 0x80L) != 0, "Real HWND is no-activate, click-through, and absent from taskbar");
            Check(SendMessage(handle, 0x84, IntPtr.Zero, IntPtr.Zero) == new IntPtr(-1), "Hit tests pass through the real native window");
            Check(SendMessage(handle, 0x21, IntPtr.Zero, IntPtr.Zero) == new IntPtr(3), "Mouse activation is explicitly refused");
            Check(!IsWindowVisible(handle), "No visible window without an explicit display grant");
            Check(GetForegroundWindow() == foreground, "Hidden runtime creation never steals focus");
        }
        Check(GetForegroundWindow() == foreground, "Disposal preserves foreground");
        Console.WriteLine($"PASS native game hangar overlay: {checks} assertions; transparent render, six positions, multi-DPI, passive HWND and no focus changes");
    }
    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr hwnd);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")] private static extern IntPtr GetWindowLongPtr(IntPtr hwnd, int index);
    [DllImport("user32.dll")] private static extern IntPtr SendMessage(IntPtr hwnd, int message, IntPtr w, IntPtr l);
}
