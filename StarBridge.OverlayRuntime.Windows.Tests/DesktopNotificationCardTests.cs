namespace StarBridge.Desktop.Tests;

using StarBridge.HostRuntime.Notifications;
// Same regression runs against both the internal client and the independent renderer.
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

internal static class DesktopNotificationCardTests
{
    internal static void RunAll()
    {
        Exception? failure = null;
        var thread = new Thread(() => {
            try {
                // Capture the actual native card without ever opening a feature-client window.
                foreach (var locale in new[] { "zh-CN", "zh-TW", "en-US" })
                foreach (var appearance in new[] { "dark", "light" }) {
                    var passive = new PlayerActivityNotificationCard(new(Guid.NewGuid(), false, 0, 0, "fullContent", "bottomRight", locale, appearance, () => true,
                        Activity: new("Pilot", "pilot", "StartedGame", "", Sources: ["friends", "organization:Example Fleet", "room"])));
                    passive.Measure(new(344,88)); passive.Arrange(new(0,0,344,88)); passive.UpdateLayout();
                    if (passive.IsHitTestVisible || passive.Focusable || Descendants(passive).OfType<Button>().Any())
                        throw new Exception("Player activity must be passive without any action buttons");
                    var sourceLine = Descendants(passive).OfType<TextBlock>().Single(t => t.Name == "PlayerSources");
                    if (!sourceLine.Text.Contains("Example Fleet") || !sourceLine.Text.Contains(" · "))
                        throw new Exception("Player sources must be merged on a separate line");
                    var activityBitmap = new RenderTargetBitmap(688,176,192,192,PixelFormats.Pbgra32); activityBitmap.Render(passive);
                    var activityEncoder = new PngBitmapEncoder(); activityEncoder.Frames.Add(BitmapFrame.Create(activityBitmap));
                    using (var activityFile = File.Create(Path.Combine(AppContext.BaseDirectory, $"player-activity-{locale}-{appearance}.png"))) activityEncoder.Save(activityFile);
                    var card = new DesktopNotificationCard(new(Guid.NewGuid(), false, 12, 3, "fullContent", "bottomRight", locale, appearance, () => true, ReduceMotion: true), () => { }, () => { });
                    card.Measure(new(380,170)); card.Arrange(new(0,0,380,170)); card.UpdateLayout();
                    foreach (var scale in new[] { 1.0, 1.25, 1.5, 2.0 }) {
                        var actualSize = new RenderTargetBitmap((int)(380 * scale), (int)Math.Ceiling(170 * scale), 96 * scale, 96 * scale, PixelFormats.Pbgra32);
                        actualSize.Render(card);
                        var dpiEncoder = new PngBitmapEncoder(); dpiEncoder.Frames.Add(BitmapFrame.Create(actualSize));
                        using var dpiFile = File.Create(Path.Combine(AppContext.BaseDirectory, $"notification-{locale}-{appearance}-{scale * 100:0}dpi.png"));
                        dpiEncoder.Save(dpiFile);
                    }
                    var brand = Descendants(card).OfType<System.Windows.Controls.Image>().Single();
                    if (RenderOptions.GetBitmapScalingMode(brand) != BitmapScalingMode.HighQuality)
                        throw new Exception("Notification brand must use area-filtered downsampling: the 1254px master loses its rays at 24px with default filtering");
                    var bitmap = new RenderTargetBitmap(760,340,192,192,PixelFormats.Pbgra32); bitmap.Render(card);
                    var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
                    var path = Path.Combine(AppContext.BaseDirectory, $"notification-{locale}-{appearance}.png");
                    using var file = File.Create(path); encoder.Save(file);
                    Console.WriteLine("CARD_RENDER=" + path);
                    card.SetHovered(true);
                    if (!Descendants(card).OfType<TextBlock>().Any(t => t.Text is "已暂停自动收起" or "已暫停自動收起" or "Auto-dismiss paused"))
                        throw new Exception("Hover must visibly explain paused dismissal");
                    var close = Descendants(card).OfType<Button>().Single(b => b.Name == "DismissNotification");
                    var hover = close.Template.Triggers.OfType<Trigger>().Single(t => t.Property == UIElement.IsMouseOverProperty);
                    var foreground = (SolidColorBrush)hover.Setters.OfType<Setter>().Single(s => s.Property == Control.ForegroundProperty).Value;
                    if (foreground.Color.R <= foreground.Color.B) throw new Exception("Close hover must use semantic red, not Windows blue");
                    // Render the production template's declared hover setters without moving the user's mouse.
                    foreach (var setter in hover.Setters.OfType<Setter>()) close.SetValue(setter.Property, setter.Value);
                    card.UpdateLayout();
                    var hoverBitmap = new RenderTargetBitmap(760,340,192,192,PixelFormats.Pbgra32); hoverBitmap.Render(card);
                    var hoverEncoder = new PngBitmapEncoder(); hoverEncoder.Frames.Add(BitmapFrame.Create(hoverBitmap));
                    using var hoverFile = File.Create(Path.Combine(AppContext.BaseDirectory, $"notification-{locale}-{appearance}-hover.png"));
                    hoverEncoder.Save(hoverFile);
                    card.SetHovered(false);
                }
                var animated = new Border { Opacity = 0 };
                if (DesktopNotificationMotion.Enabled(false) != UiMotion.IsEnabled)
                    throw new Exception("Notifications must respect the canonical motion capability gate");
                var activityMotion = new Border();
                DesktopNotificationMotion.EnterActivity(activityMotion, true, true);
                var movement = (TranslateTransform)activityMotion.RenderTransform;
                Pump(65);
                if (movement.X <= 0 || movement.X >= 12 || activityMotion.Opacity <= 0 || activityMotion.Opacity >= 1)
                    throw new Exception("Player entry must render intermediate translation and opacity frames");
                Pump(260);
                if (Math.Abs(movement.X) > 0.01 || activityMotion.Opacity != 1) throw new Exception("Player entry must settle");
                foreach (var toRight in new[] { false, true }) {
                    DesktopNotificationMotion.EnterActivity(activityMotion, toRight, false);
                    var exited = false;
                    DesktopNotificationMotion.ExitActivity(activityMotion, toRight, true, () => exited = true);
                    Pump(65);
                    var exitX = ((TranslateTransform)activityMotion.RenderTransform).X;
                    if (Math.Abs(exitX) <= 0 || Math.Abs(exitX) >= 8 || (exitX > 0) != toRight ||
                        activityMotion.Opacity <= 0 || activityMotion.Opacity >= 1 || exited)
                        throw new Exception("Player exit must slide toward its edge and fade before removal");
                    Pump(220);
                    if (!exited || activityMotion.Opacity != 0) throw new Exception("Player exit must finish before removal");
                }
                var reducedExit = false;
                DesktopNotificationMotion.EnterActivity(activityMotion, false, true);
                DesktopNotificationMotion.ExitActivity(activityMotion, false, false, () => reducedExit = true);
                if (!reducedExit || activityMotion.Opacity != 0 || ((TranslateTransform)activityMotion.RenderTransform).X != 0)
                    throw new Exception("Reduced player exit must interrupt entry immediately");
                DesktopNotificationMotion.EnterActivity(activityMotion, false, false);
                if (((TranslateTransform)activityMotion.RenderTransform).X != 0 || activityMotion.Opacity != 1)
                    throw new Exception("Reduced motion must present a settled card immediately");
                foreach (var light in new[] { true, false }) {
                    var tones = new[] { "Online", "Offline", "StartedGame", "StoppedGame" }.Select(kind => PlayerActivityNotificationCard.EventColor(kind, light));
                    if (tones.Distinct().Count() != 4) throw new Exception("All four activity events need distinct colors");
                }
                if (DesktopNotificationEnvironment.UserReason("do-not-disturb") != "doNotDisturb" ||
                    DesktopNotificationEnvironment.UserReason("shell-suppressed-2") != "systemBusy" ||
                    DesktopNotificationEnvironment.UserReason("shell-suppressed-3") != "fullScreen" ||
                    DesktopNotificationEnvironment.UserReason("notification-mode-unsupported") != "unsupported" ||
                    DesktopNotificationEnvironment.UserReason("unexpected-native-details") != "unavailable")
                    throw new Exception("Native suppression projects only stable public reason codes");
                DesktopNotificationMotion.Fade(animated, 1, 180, true);
                Pump(65);
                if (animated.Opacity <= 0 || animated.Opacity >= 1) throw new Exception("Entry must contain intermediate opacity frames");
                var before = animated.Opacity; var finished = false;
                DesktopNotificationMotion.Fade(animated, 0, 120, true, () => finished = true);
                if (Math.Abs(animated.Opacity - before) > 0.15) throw new Exception("Interrupted entry must not flash to full opacity");
                Pump(210);
                if (!finished || animated.Opacity != 0) throw new Exception("Exit completion must remove the card after fading");
                DesktopNotificationMotion.Fade(animated, 1, 180, false);
                if (animated.Opacity != 1 || DesktopNotificationMotion.Enabled(true)) throw new Exception("Reduced motion must be immediate");
                var staleCompletion = false;
                DesktopNotificationMotion.Fade(animated, 0, 120, true, () => staleCompletion = true);
                DesktopNotificationMotion.Cancel(animated);
                Pump(180);
                if (staleCompletion) throw new Exception("Immediate invalidation must cancel delayed animation completion");
                var hidden = new DesktopNotificationCard(new(Guid.NewGuid(), false, 12, 3, "hiddenDetails", "bottomRight", "zh-CN", "dark", () => true), () => { }, () => { });
                var summary = System.Windows.Automation.AutomationProperties.GetName(hidden);
                if (summary.Contains("12") || summary.Contains("房间")) throw new Exception("Hidden preview leaked to accessibility summary");
                Console.WriteLine("SYSTEM_SUPPRESSION=" + DesktopNotificationEnvironment.SuppressionReason());
                Console.WriteLine("NOTIFICATION_MODE=" + DesktopNotificationEnvironment.ReadNotificationModeReason());
            } catch (Exception e) { failure = e; }
        });
        thread.SetApartmentState(ApartmentState.STA); thread.Start(); thread.Join();
        if (failure != null) throw failure;
    }

    private static IEnumerable<DependencyObject> Descendants(DependencyObject root) {
        for (var i = 0; i < VisualTreeHelper.GetChildrenCount(root); i++) {
            var child = VisualTreeHelper.GetChild(root, i); yield return child;
            foreach (var item in Descendants(child)) yield return item;
        }
    }
    private static void Pump(int milliseconds) {
        var frame = new DispatcherFrame();
        var timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(milliseconds) };
        timer.Tick += (_, _) => { timer.Stop(); frame.Continue = false; };
        timer.Start(); Dispatcher.PushFrame(frame);
    }
}
