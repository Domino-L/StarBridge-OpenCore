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
                VerifyFreshCardLifetime();
                var pixels = new byte[320 * 320 * 4];
                new Random(731).NextBytes(pixels);
                var source = BitmapSource.Create(320, 320, 96, 96, PixelFormats.Bgra32, null, pixels, 320 * 4);
                var avatarEncoder = new PngBitmapEncoder();
                avatarEncoder.Frames.Add(BitmapFrame.Create(source));
                using var encoded = new MemoryStream();
                avatarEncoder.Save(encoded);
                var largeAvatar = "data:image/png;base64," + Convert.ToBase64String(encoded.ToArray());
                if (largeAvatar.Length <= 350000 || encoded.Length > 512 * 1024)
                    throw new Exception("Large avatar fixture must cross old card limit but stay within directory contract");
                if (DesktopNotificationCard.PlayerAvatar(largeAvatar) is not { PixelWidth: 84 })
                    throw new Exception("A directory-approved large avatar must decode to a bounded native thumbnail");
                var activityWithAvatar = new PlayerActivityNotificationCard(new(Guid.NewGuid(), false, 0, 0,
                    "fullContent", "bottomRight", "zh-CN", "dark", () => true,
                    Activity: new("Pilot", "pilot", "Online", "", largeAvatar, Sources: ["friends"])));
                activityWithAvatar.Measure(new(344, 88));
                activityWithAvatar.Arrange(new(0, 0, 344, 88));
                activityWithAvatar.UpdateLayout();
                if (Descendants(activityWithAvatar).OfType<System.Windows.Controls.Image>().SingleOrDefault()?.Source
                    is not BitmapSource { PixelWidth: 84 })
                    throw new Exception("The actual activity card must show the large permitted avatar, not initials");
                // Capture the actual native card without ever opening a feature-client window.
                foreach (var preview in new[] { "sourceOnly", "fullContent", "hiddenDetails" }) {
                    var direct = new DesktopNotificationCard(new(Guid.NewGuid(), false, 0, 0, preview, "bottomRight",
                        "zh-CN", "dark", () => true, DirectMessage: new("Pilot", "Message", 1)), () => { }, () => { });
                    direct.Measure(new(380,170)); direct.Arrange(new(0,0,380,170)); direct.UpdateLayout();
                    var avatars = Descendants(direct).OfType<Border>().Count(b => b.Name == "SenderAvatar");
                    if (avatars != (preview == "hiddenDetails" ? 0 : 1))
                        throw new Exception("Direct reminder needs a sender avatar fallback unless identity is hidden.");
                }
                foreach (var locale in new[] { "zh-CN", "zh-TW", "en-US" })
                foreach (var appearance in new[] { "dark", "light" }) {
                    var identity = new DesktopNotificationCard(new(Guid.NewGuid(), false, 0, 0, "sourceOnly", "bottomRight",
                        locale, appearance, () => true, ReduceMotion: true, Activated: () => { }, GameIdentityMismatch: true), () => { }, () => { });
                    identity.Measure(new(380,170)); identity.Arrange(new(0,0,380,170)); identity.UpdateLayout();
                    var identitySummary = System.Windows.Automation.AutomationProperties.GetName(identity);
                    var expectedIdentityText = locale switch {
                        "zh-CN" => "游戏身份与应用记录不一致，请打开应用核对。",
                        "zh-TW" => "遊戲身分與應用程式記錄不一致，請開啟應用程式核對。",
                        _ => "Your game identity differs from the app record. Open the app to review."
                    };
                    if (!identitySummary.Contains(expectedIdentityText) || identitySummary.Contains("SCM") ||
                        identitySummary.Contains("绑定") || identitySummary.Contains("房间"))
                        throw new Exception("Typed identity warning must use neutral Host-owned text without claiming SCM binding or room actions");
                    var hiddenIdentity = new DesktopNotificationCard(new(Guid.NewGuid(), false, 0, 0, "hiddenDetails", "bottomRight",
                        locale, appearance, () => true, GameIdentityMismatch: true), () => { }, () => { });
                    var hiddenIdentitySummary = System.Windows.Automation.AutomationProperties.GetName(hiddenIdentity);
                    if (hiddenIdentitySummary.Contains("身份") || hiddenIdentitySummary.Contains("身分") ||
                        hiddenIdentitySummary.Contains("identity", StringComparison.OrdinalIgnoreCase))
                        throw new Exception("Hidden identity preview must not expose the source through accessibility text");
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

    private static void VerifyFreshCardLifetime()
    {
        // Exercise the production timer without starting its thread or showing a
        // window. Simulate an old dispatcher tick followed by a newly added card.
        var type = typeof(NativeDesktopNotificationRuntime);
        var runtime = System.Runtime.CompilerServices.RuntimeHelpers.GetUninitializedObject(type);
        const System.Reflection.BindingFlags flags = System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic;
        var entryType = type.GetNestedType("Entry", System.Reflection.BindingFlags.NonPublic)!;
        var notice = new DesktopNotification(Guid.NewGuid(), false, 0, 0, "fullContent", "bottomRight",
            "zh-CN", "dark", () => false, Activity: new("Pilot", "pilot", "Online", ""));
        // Expiration avoids native environment queries; elapsed accounting runs first.
        var entry = Activator.CreateInstance(entryType, flags | System.Reflection.BindingFlags.Public,
            null, new object[] { notice, new Window() }, null)!;
        var older = Activator.CreateInstance(entryType, flags | System.Reflection.BindingFlags.Public,
            null, new object[] { notice, new Window() }, null)!;
        entryType.GetField("LastTick", flags)?.SetValue(older,
            System.Diagnostics.Stopwatch.GetTimestamp() - 10 * System.Diagnostics.Stopwatch.Frequency);
        var list = (System.Collections.IList)Activator.CreateInstance(typeof(List<>).MakeGenericType(entryType))!;
        list.Add(entry);
        list.Add(older);
        type.GetField("_visible", flags)!.SetValue(runtime, list);
        type.GetField("_pending", flags)!.SetValue(runtime, new Queue<DesktopNotification>());
        type.GetField("_tick", flags)?.SetValue(runtime,
            System.Diagnostics.Stopwatch.GetTimestamp() - 10 * System.Diagnostics.Stopwatch.Frequency);
        type.GetMethod("Tick", flags)!.Invoke(runtime, null);
        var remaining = (TimeSpan)entryType.GetField("Remaining", flags)!.GetValue(entry)!;
        if (remaining < TimeSpan.FromSeconds(4))
            throw new Exception("A new activity card must not consume dispatcher time from before it existed");
        if ((TimeSpan)entryType.GetField("Remaining", flags)!.GetValue(older)! > TimeSpan.Zero)
            throw new Exception("An older card must still consume its own elapsed display time");
        if (list.Count != 0)
            throw new Exception("Invalidated cards must be removed immediately regardless of remaining display time");
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
