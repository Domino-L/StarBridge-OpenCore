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
    private static void VerifyTradeCards()
    {
        foreach (var locale in new[] { "zh-CN", "zh-TW", "en-US" })
        foreach (var preview in new[] { "sourceOnly", "fullContent", "hiddenDetails" }) {
            var notice = new DesktopNotification(Guid.NewGuid(), false, 0, 0, preview, "bottomRight",
                locale, "dark", () => true, ReduceMotion: true,
                Trade: new("Trade shipped", "Aurora Â· K*****l"));
            var card = new TradeNotificationCard(notice, () => { }, () => { });
            card.Measure(new(380, 170)); card.Arrange(new(0, 0, 380, 170)); card.UpdateLayout();
            var summary = System.Windows.Automation.AutomationProperties.GetName(card);
            var hidden = preview == "hiddenDetails";
            if (summary.Contains("Trade shipped") == hidden || summary.Contains("Aurora") == hidden)
                throw new Exception("Trade title and item must render through the actual native card with the saved privacy mode.");
        }
        Console.WriteLine("PASS CX-T23 native trade card: 9 locale/preview combinations; no HWND");
        VerifyTradeCardLook();
    }

    // 10-29 approved look: crate + SCM market stamp + StarBridge star before the SCM wordmark;
    // a compact click-through card in game. Renders every kind in both themes for review.
    private static void VerifyTradeCardLook()
    {
        var output = Path.Combine(AppContext.BaseDirectory, "trade-cards");
        Directory.CreateDirectory(output);
        var kinds = new (string Kind, string Title, int Quantity, string Amount)[] {
            ("request", "新的购买申请", 2, "18,000"), ("approved", "交易申请已同意", 1, ""), ("shipped", "对方已发货", 1, "45,000"),
            ("receipt", "收货提醒", 0, ""), ("completed", "对方已确认收货", 10, "6,500"), ("cancelled", "交易已取消", 1, ""),
            ("review", "收到交易评价", 0, ""), ("update", "交易提醒", 0, ""), ("message", "新的交易私信 · Kestrel", 0, "") };
        var count = 0;
        foreach (var appearance in new[] { "dark", "light" })
        foreach (var reduce in new[] { true, false })
        foreach (var (kind, title, quantity, amount) in kinds)
        foreach (var preview in new[] { "fullContent", "hiddenDetails" }) {
            var hidden = preview == "hiddenDetails";
            var chat = kind == "message";
            var trade = hidden ? new TradeNotificationContent("", "") : new TradeNotificationContent(title, "body", kind,
                chat ? "" : "P4-AR 步枪", quantity, amount, chat ? "Kestrel" : "", chat ? "今晚 8 点在 Area18 交货可以吗？" : "");
            var notice = new DesktopNotification(Guid.NewGuid(), false, 0, 0, preview, "bottomRight", "zh-CN", appearance,
                () => true, ReduceMotion: reduce, Activated: () => { }, Trade: trade);
            var big = new TradeNotificationCard(notice, () => { }, () => { });
            big.Measure(new(380, 170)); big.Arrange(new(0, 0, 380, 170)); big.UpdateLayout();
            var compact = new CompactTradeNotificationCard(notice with { Trade = trade with { Compact = true } });
            compact.Measure(new(344, 88)); compact.Arrange(new(0, 0, 344, 88)); compact.UpdateLayout();
            foreach (FrameworkElement root in new FrameworkElement[] { big, compact }) {
                var parts = Descendants(root).OfType<FrameworkElement>().ToList();
                bool Has(string name) => parts.Any(p => p.Name == name);
                if (!Has("TradeStamp") || !Has("StarBridgeMark") || !Has("ScmWordmark"))
                    throw new Exception($"Trade card {kind}/{appearance}/{preview} must carry the stamp, StarBridge star and SCM wordmark.");
                if (Has("TradeCrate") == (chat && !hidden) || Has("TradePeerInitial") != (chat && !hidden))
                    throw new Exception("Trade events show the SCM crate; trade messages show the peer initial instead.");
                if (Has("TradeStatusBadge") == hidden)
                    throw new Exception("Status badge appears only when details are shown.");
                var stamp = parts.First(p => p.Name == "TradeStamp");
                if (stamp.IsHitTestVisible || stamp.Focusable)
                    throw new Exception("Stamp is decoration only.");
                if (reduce && (stamp.Opacity != 1 || stamp.HasAnimatedProperties))
                    throw new Exception("Reduced motion: the stamp is static.");
                if (!reduce && !stamp.HasAnimatedProperties)
                    throw new Exception("Normal motion: the stamp settles in.");
                var text = string.Join("|", parts.OfType<TextBlock>().Select(t => t.Text));
                if (hidden && (text.Contains("P4-AR") || text.Contains("Kestrel") || text.Contains("18,000") || !text.Contains("你有新的交易提醒")))
                    throw new Exception("Hidden details show only the generic trade line.");
                if (!hidden && !chat && amount.Length > 0 && !text.Contains(amount + " UEC"))
                    throw new Exception("Amount is shown in UEC.");
                if (!hidden && chat && (!text.Contains("Kestrel") || text.Contains("K*****l")))
                    throw new Exception("Trade messages show the verified handle in full.");
                if (text.Contains("房间"))
                    throw new Exception("Trade cards never use the room copy.");
            }
            if (compact.IsHitTestVisible || compact.Focusable)
                throw new Exception("In-game trade card is click-through.");
            if (Descendants(compact).OfType<Button>().Any())
                throw new Exception("In-game trade card has no buttons.");
            var action = Descendants(big).OfType<Button>().Select(b => b.Content as string).ToList();
            if (!action.Contains(hidden ? "打开应用 →" : chat ? "查看交易私信 →" : "查看交易 →"))
                throw new Exception("Trade action copy matches the destination.");
            if (reduce && preview == "fullContent") {
                foreach (var (element, w, h, name) in new[] { ((FrameworkElement)big, 380, 170, "big"), (compact, 344, 88, "compact") }) {
                    var bitmap = new RenderTargetBitmap(w * 2, h * 2, 192, 192, PixelFormats.Pbgra32); bitmap.Render(element);
                    var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
                    using var file = File.Create(Path.Combine(output, $"trade-{name}-{kind}-{appearance}.png")); encoder.Save(file);
                }
            }
            count++;
        }
        Console.WriteLine($"PASS trade card look: {count} kind/theme/motion/privacy combinations, big + compact; renders in trade-cards/");
        // User 10-29: only the app's switches decide. Windows DND / quiet time never block a trade alert;
        // locked or screen-saver (1), presentation (4), unknown shell states and an inactive desktop do.
        var combinations = 0;
        for (var state = -1; state <= 8; state++)
        foreach (var inactive in new[] { "", "inactive-desktop", "secure-desktop" }) {
            var reason = DesktopNotificationEnvironment.EvaluateTradeSuppression(state, () => inactive);
            var allowed = state is 2 or 3 or 5 or 6 or 7 && inactive.Length == 0;
            if ((reason.Length == 0) != allowed)
                throw new Exception($"Trade rule mismatch: state={state} inactive={inactive} -> {reason}");
            combinations++;
        }
        // CX-T32 P1: the presentation is decided before any gate; it only toggles Compact.
        var plain = new DesktopNotification(Guid.NewGuid(), false, 0, 0, "fullContent", "bottomRight", "zh-CN", "dark", () => true,
            Trade: new("t", "b", "shipped"));
        if (NativeDesktopNotificationRuntime.WithTradePresentation(plain, true).Trade is not { Compact: true, Kind: "shipped" } ||
            NativeDesktopNotificationRuntime.WithTradePresentation(plain, false).Trade is not { Compact: false } ||
            NativeDesktopNotificationRuntime.WithTradePresentation(plain with { Trade = null }, true).Trade is not null)
            throw new Exception("Trade presentation must be prepared without changing content.");
        Console.WriteLine($"PASS trade gate: {combinations} shell/desktop combinations (Windows DND and quiet time never block); compact flag set without changing content");
    }

    internal static void RunAll()
    {
        Exception? failure = null;
        var thread = new Thread(() => {
            try {
                VerifyTradeCards();
                VerifyBrandWatermarks();
                VerifyFreshCardLifetime();
                VerifyHangarCards();
                VerifyCompactHangarCards();
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
                ObserveFirstChangedFrame(
                    () => movement.X == 12 && activityMotion.Opacity == 0,
                    () => {
                        if (movement.X <= 0 || movement.X >= 12 || activityMotion.Opacity <= 0 || activityMotion.Opacity >= 1)
                            throw new Exception("Player entry must render intermediate translation and opacity frames");
                    });
                Pump(260);
                if (Math.Abs(movement.X) > 0.01 || activityMotion.Opacity != 1) throw new Exception("Player entry must settle");
                foreach (var toRight in new[] { false, true }) {
                    DesktopNotificationMotion.EnterActivity(activityMotion, toRight, false);
                    var exited = false;
                    DesktopNotificationMotion.ExitActivity(activityMotion, toRight, true, () => exited = true);
                    ObserveFirstChangedFrame(
                        () => ((TranslateTransform)activityMotion.RenderTransform).X == 0 && activityMotion.Opacity == 1 && !exited,
                        () => {
                            var exitX = ((TranslateTransform)activityMotion.RenderTransform).X;
                            if (Math.Abs(exitX) <= 0 || Math.Abs(exitX) >= 8 || (exitX > 0) != toRight ||
                                activityMotion.Opacity <= 0 || activityMotion.Opacity >= 1 || exited)
                                throw new Exception("Player exit must slide toward its edge and fade before removal");
                        });
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
    private static void VerifyHangarCards()
    {
        var notices = new List<string>();
        var expired = new DesktopNotification(Guid.NewGuid(), false, 0, 0, "sourceOnly", "bottomRight", "zh-CN", "dark", () => true) {
            PresentUntil = DateTimeOffset.UtcNow.AddSeconds(-1), Diagnostic = notices.Add
        };
        var runtime = System.Runtime.CompilerServices.RuntimeHelpers.GetUninitializedObject(typeof(NativeDesktopNotificationRuntime));
        typeof(NativeDesktopNotificationRuntime).GetField("_celebration", System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic)!
            .SetValue(runtime, StarBridge.HostRuntime.Achievements.AchievementCelebrationActivity.Shared);
        if ((bool)typeof(NativeDesktopNotificationRuntime).GetMethod("Show", System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic)!
            .Invoke(runtime, [expired])! || !notices.Contains("expired"))
            throw new Exception("A queued hangar card past its presentation deadline must expire before allocating a native window");
        var origin = new DateTimeOffset(2026, 10, 9, 0, 0, 0, TimeSpan.Zero);
        var config = new StarBridge.Core.Tools.ExecHangarConfig("fixture", "fixture", null, origin, 0, 65, 120, 0);
        foreach (var locale in new[] { "zh-CN", "zh-TW", "en-US" })
        foreach (var appearance in new[] { "dark", "light" })
        foreach (var opening in new[] { true, false }) {
            var boundary = origin.AddMinutes(opening ? 185 : 65); var muted = 0; var dismissed = 0;
            var card = new DesktopNotificationCard(new(Guid.NewGuid(), false, 0, 0, "sourceOnly", "bottomRight", locale, appearance,
                () => true, ReduceMotion: true, Activated: () => { }, ExecHangar: new(opening, false, boundary, config, boundary.AddMinutes(5), () => muted++)),
                () => { }, () => dismissed++);
            var panel = Descendants(card).OfType<ExecHangarNotificationPanel>().Single();
            panel.Update(boundary.AddSeconds(-40));
            card.Measure(new(380,264)); card.Arrange(new(0,0,380,264)); card.UpdateLayout();
            var remaining = Descendants(card).OfType<TextBlock>().Single(t => t.Name == "HangarRemaining");
            if (!opening) {
                var warning = Descendants(card).OfType<TextBlock>().Single(t => t.Name == "HangarTarget").Text;
                if (!warning.Contains(locale == "en-US" ? "Leave" : "離開") && !(locale == "zh-CN" && warning.Contains("离开")))
                    throw new Exception("All five lights off must explain the imminent clearance and ask users to leave");
                panel.Update(boundary.AddMinutes(-5).AddMilliseconds(-1));
                if (Descendants(card).OfType<TextBlock>().Single(t => t.Name == "HangarTarget").Text.Contains(locale == "en-US" ? "Leave" : locale == "zh-CN" ? "离开" : "離開"))
                    throw new Exception("Leave warning must not appear before the all-off phase");
                panel.Update(boundary.AddSeconds(-40));
            }
            if (!remaining.Text.Contains("40")) throw new Exception("Hangar card must count down to its monitored target in natural seconds");
            if (Descendants(card).OfType<System.Windows.Shapes.Ellipse>().Count() != 5)
                throw new Exception("Hangar card must show exactly five current phase lamps");
            var expected = locale == "en-US" ? opening ? "Opens" : "Closes" : opening ? "開" : "關";
            if (locale == "zh-CN") expected = opening ? "开" : "关";
            if (!remaining.Text.Contains(expected)) throw new Exception("Opening and closing targets must remain distinct");
            foreach (var scale in new[] { 1d, 1.25, 1.5, 2d }) {
                var bitmap = new RenderTargetBitmap((int)(380 * scale), (int)(264 * scale), 96 * scale, 96 * scale, PixelFormats.Pbgra32);
                bitmap.Render(card); var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
                using var file = File.Create(Path.Combine(AppContext.BaseDirectory, $"hangar-{locale}-{appearance}-{(opening ? "open" : "close")}-{scale * 100:0}.png")); encoder.Save(file);
            }
            panel.Update(boundary.AddSeconds(-39));
            if (!remaining.Text.Contains("39")) throw new Exception("Displayed hangar countdown must update without a replacement card");
            panel.Update(boundary.AddMilliseconds(100));
            var heading = Descendants(card).OfType<TextBlock>().Single(t => t.Name == "HangarTarget").Text;
            if (!heading.Contains(locale == "en-US" ? "is" : "已")) throw new Exception("Crossing the exact boundary must update card state");
            var mute = Descendants(card).OfType<Button>().Single(b => b.Name == "MuteHangarEvent");
            mute.RaiseEvent(new RoutedEventArgs(System.Windows.Controls.Primitives.ButtonBase.ClickEvent));
            if (muted != 1 || dismissed != 1) throw new Exception("Mute event must invoke its typed callback once and dismiss without activation");
            var hidden = new DesktopNotificationCard(new(Guid.NewGuid(), false, 0, 0, "hiddenDetails", "bottomRight", locale, appearance,
                () => true, ExecHangar: new(opening, false, boundary, config)), () => { }, () => { });
            if (hidden.Height != 170 || Descendants(hidden).OfType<ExecHangarNotificationPanel>().Any())
                throw new Exception("Hidden details must not expose hangar state, phase, countdown or mute action");
        }
        var sample = new DesktopNotificationCard(new(Guid.NewGuid(), false, 0, 0, "sourceOnly", "bottomRight", "zh-CN", "dark",
            () => true, ExecHangar: new(false, false, origin.AddMinutes(65), config, LeaveWarning: true, Test: true)), () => { }, () => { });
        var samplePanel = Descendants(sample).OfType<ExecHangarNotificationPanel>().Single();
        samplePanel.Update(origin.AddMinutes(62));
        if (!Descendants(sample).OfType<TextBlock>().Single(t => t.Name == "HangarTarget").Text.Contains("请立即离开机库"))
            throw new Exception("Test must preserve the same actual clearance warning as a real reminder");
        if (!Descendants(sample).OfType<TextBlock>().Single(t => t.Name == "HangarTarget").Text.Contains("测试") ||
            Descendants(sample).OfType<Button>().Any(b => b.Name == "MuteHangarEvent"))
            throw new Exception("Hangar sample must be explicitly marked and cannot suppress the real event");
        var openingTest = new DesktopNotificationCard(new(Guid.NewGuid(), false, 0, 0, "sourceOnly", "bottomRight", "zh-CN", "dark",
            () => true, ExecHangar: new(true, false, origin.AddMinutes(185), config, Test: true)), () => { }, () => { });
        Descendants(openingTest).OfType<ExecHangarNotificationPanel>().Single().Update(origin.AddMinutes(90));
        if (Descendants(openingTest).OfType<TextBlock>().Single(t => t.Name == "HangarTarget").Text != "等待行政机库开启 · 测试" ||
            !Descendants(openingTest).OfType<TextBlock>().Single(t => t.Name == "HangarRemaining").Text.Contains("1 小时 35 分钟"))
            throw new Exception("Opening test must preserve the real opening content and actual countdown");
        foreach (var (preview, name) in new[] { (openingTest, "opening"), (sample, "leave") }) {
            preview.Measure(new(380, preview.Height)); preview.Arrange(new(0, 0, 380, preview.Height)); preview.UpdateLayout();
            var bitmap = new RenderTargetBitmap(380, (int)preview.Height, 96, 96, PixelFormats.Pbgra32);
            bitmap.Render(preview); var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
            using var file = File.Create(Path.Combine(AppContext.BaseDirectory, $"hangar-compact-{name}.png")); encoder.Save(file);
        }
        Console.WriteLine("PASS live hangar notification: target, five lamps, timing, mute, privacy and 48 multi-DPI renders");
    }

    private static void VerifyCompactHangarCards()
    {
        var origin = new DateTimeOffset(2026,10,9,0,0,0,TimeSpan.Zero);
        var config = new StarBridge.Core.Tools.ExecHangarConfig("fixture", "fixture", null, origin, 0, 65, 120, 0);
        foreach (var locale in new[] { "zh-CN", "zh-TW", "en-US" })
        foreach (var appearance in new[] { "dark", "light" })
        foreach (var kind in new[] { "opening", "closing", "leave", "opened", "closed" }) {
            var opening = kind is "opening" or "opened";
            var boundary = origin.AddMinutes(opening ? 185 : 65);
            var notice = new DesktopNotification(Guid.NewGuid(),false,0,0,"sourceOnly","bottomRight",locale,appearance,()=>true,
                ExecHangar: new(opening, kind is "opened" or "closed", boundary, config, boundary.AddMinutes(5), () => throw new Exception("Passive card cannot mute"),
                    LeaveWarning: kind == "leave", Test: true) { Compact = true });
            var card = new CompactExecHangarNotificationCard(notice);
            var panel = Descendants(card).OfType<ExecHangarNotificationPanel>().Single();
            var now = boundary.AddSeconds(kind is "opened" or "closed" ? 1 : -40);
            panel.Update(now); card.Measure(new(344,88)); card.Arrange(new(0,0,344,88)); card.UpdateLayout();
            if (card.Width != 344 || card.Height != 88 || card.IsHitTestVisible || card.Focusable || Descendants(card).OfType<Button>().Any())
                throw new Exception("Compact hangar must match passive activity size and never capture input or expose actions");
            if (Descendants(card).OfType<System.Windows.Shapes.Ellipse>().Count() != 5)
                throw new Exception("Compact hangar must retain five accurate phase lamps");
            var title = Descendants(card).OfType<TextBlock>().Single(t=>t.Name == "HangarTarget");
            if (!title.Text.Contains(locale == "en-US" ? "Test" : locale == "zh-CN" ? "测试" : "測試"))
                throw new Exception("Compact tests must retain their explicit test marker");
            if (kind == "leave" && !title.Text.Contains(locale == "en-US" ? "Leave" : locale == "zh-CN" ? "离场" : "離場"))
                throw new Exception("Compact departure reminder must still tell the player to leave");
            var remaining = Descendants(card).OfType<TextBlock>().Single(t=>t.Name == "HangarRemaining");
            if (kind is "opening" or "closing" or "leave") {
                if (!remaining.Text.Contains("40")) throw new Exception("Compact timer must retain the actual target");
                panel.Update(now.AddSeconds(1));
                if (!remaining.Text.Contains("39")) throw new Exception("Compact timer must update in place");
            }
            if (Descendants(card).OfType<TextBlock>().Any(t => t.Name == "HangarMonitorEnd"))
                throw new Exception("Compact card must omit detailed monitoring controls");
            foreach (var text in Descendants(card).OfType<TextBlock>()) {
                var at = text.TranslatePoint(new(0,0), card);
                if (at.Y < 0 || at.Y + text.ActualHeight > 88 || text.TextWrapping != TextWrapping.NoWrap)
                    throw new Exception("Compact localized text must fit vertically without wrapping");
            }
            foreach (var scale in new[] { 1d,1.25,1.5,2d }) {
                var bitmap = new RenderTargetBitmap((int)(344*scale),(int)(88*scale),96*scale,96*scale,PixelFormats.Pbgra32);
                bitmap.Render(card); var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
                using var file = File.Create(Path.Combine(AppContext.BaseDirectory,$"hangar-passive-{locale}-{appearance}-{kind}-{scale*100:0}.png")); encoder.Save(file);
            }
            var hidden = new CompactExecHangarNotificationCard(notice with { Preview = "hiddenDetails" });
            if (Descendants(hidden).OfType<ExecHangarNotificationPanel>().Any() || Descendants(hidden).OfType<System.Windows.Shapes.Ellipse>().Any())
                throw new Exception("Hidden-details setting must remain private in compact hangar cards");
        }
        Console.WriteLine("PASS compact hangar: 88px, five lamps, live timing, input passthrough, privacy and 120 multi-DPI renders");
    }

    private static void VerifyFreshCardLifetime()
    {
        // Exercise the production timer without starting its thread. Simulate an
        // old dispatcher tick followed by a newly added card. Tick leaves a hidden
        // window's dwell untouched (a card retained across a celebration), so both
        // cards must really be visible; they are shown off screen, without focus.
        static Window OffScreen()
        {
            var window = new Window {
                WindowStyle = WindowStyle.None, ShowInTaskbar = false, ShowActivated = false,
                WindowStartupLocation = WindowStartupLocation.Manual,
                Left = -32000, Top = -32000, Width = 1, Height = 1
            };
            window.Show();
            return window;
        }
        var type = typeof(NativeDesktopNotificationRuntime);
        var runtime = System.Runtime.CompilerServices.RuntimeHelpers.GetUninitializedObject(type);
        const System.Reflection.BindingFlags flags = System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic;
        var entryType = type.GetNestedType("Entry", System.Reflection.BindingFlags.NonPublic)!;
        var notice = new DesktopNotification(Guid.NewGuid(), false, 0, 0, "fullContent", "bottomRight",
            "zh-CN", "dark", () => false, Activity: new("Pilot", "pilot", "Online", ""));
        // Expiration avoids native environment queries; elapsed accounting runs first.
        var entry = Activator.CreateInstance(entryType, flags | System.Reflection.BindingFlags.Public,
            null, new object[] { notice, OffScreen() }, null)!;
        var older = Activator.CreateInstance(entryType, flags | System.Reflection.BindingFlags.Public,
            null, new object[] { notice, OffScreen() }, null)!;
        entryType.GetField("LastTick", flags)?.SetValue(older,
            System.Diagnostics.Stopwatch.GetTimestamp() - 10 * System.Diagnostics.Stopwatch.Frequency);
        var list = (System.Collections.IList)Activator.CreateInstance(typeof(List<>).MakeGenericType(entryType))!;
        list.Add(entry);
        list.Add(older);
        type.GetField("_visible", flags)!.SetValue(runtime, list);
        type.GetField("_pending", flags)!.SetValue(runtime, new Queue<DesktopNotification>());
        type.GetField("_celebration", flags)!.SetValue(runtime, StarBridge.HostRuntime.Achievements.AchievementCelebrationActivity.Shared);
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

    private static void VerifyBrandWatermarks()
    {
        var origin = new DateTimeOffset(2026, 10, 10, 0, 0, 0, TimeSpan.Zero);
        var config = new StarBridge.Core.Tools.ExecHangarConfig("fixture", "fixture", null, origin, 0, 65, 120, 0);
        foreach (var locale in new[] { "zh-CN", "zh-TW", "en-US" })
        foreach (var appearance in new[] { "dark", "light" })
        foreach (var preview in new[] { "sourceOnly", "hiddenDetails" })
        {
            var notice = new DesktopNotification(Guid.NewGuid(), false, 0, 0, preview, "bottomRight", locale,
                appearance, () => true, ExecHangar: new(true, false, origin.AddMinutes(41), config, Test: true));
            var hangar = new CompactExecHangarNotificationCard(notice);
            Descendants(hangar).OfType<ExecHangarNotificationPanel>().SingleOrDefault()?.Update(origin);
            var activity = new PlayerActivityNotificationCard(notice with {
                ExecHangar = null, Activity = new("Fixture pilot", "fixture", "Online", "", Sources: ["friends"])
            });
            var notification = new DesktopNotificationCard(notice with { ExecHangar = null }, () => { }, () => { });
            var startup = new GameStartupHintCard(notice with {
                ExecHangar = null, GameStartupHint = new("Ctrl+Shift+Alt+M", 42)
            });
            // Its animated central mark is the brand; the accepted launch design has no duplicate watermark.
            if (Descendants(startup).OfType<FrameworkElement>().Any(e => e.Name == "NotificationBrandWatermark") ||
                startup.IsHitTestVisible || startup.Focusable)
                throw new Exception("Startup choreography must keep one passive central brand without a right watermark");
            foreach (var (card, kind) in new (FrameworkElement, string)[] {
                (hangar, "hangar"), (activity, "activity"), (notification, "notification") })
            {
                card.Measure(new(card.Width, card.Height)); card.Arrange(new(0, 0, card.Width, card.Height)); card.UpdateLayout();
                var mark = Descendants(card).OfType<FrameworkElement>().SingleOrDefault(e => e.Name == "NotificationBrandWatermark");
                if (mark is null || mark.IsHitTestVisible || mark.Focusable)
                    throw new Exception("Every notification card needs one decorative, non-interactive brand watermark");
                var at = mark.TranslatePoint(new(0, 0), card);
                if (at.X < card.Width * .65 || at.X + mark.ActualWidth > card.Width - 5 ||
                    at.Y < 0 || at.Y + mark.ActualHeight > card.Height)
                    throw new Exception("Watermark must remain contained on the right without adding a layout column");
                foreach (var scale in new[] { 1d, 1.25, 1.5, 2d })
                {
                    RenderTargetBitmap Render() {
                        var bitmap = new RenderTargetBitmap((int)(card.Width * scale), (int)(card.Height * scale),
                            96 * scale, 96 * scale, PixelFormats.Pbgra32);
                        bitmap.Render(card); return bitmap;
                    }
                    var branded = Render();
                    mark.Visibility = Visibility.Hidden; card.UpdateLayout(); var unbranded = Render();
                    mark.Visibility = Visibility.Visible; card.UpdateLayout();
                    var stride = branded.PixelWidth * 4;
                    var before = new byte[stride * branded.PixelHeight]; var after = new byte[before.Length];
                    unbranded.CopyPixels(before, stride, 0); branded.CopyPixels(after, stride, 0);
                    var changed = 0;
                    for (var y = 0; y < branded.PixelHeight; y++)
                    for (var x = 0; x < branded.PixelWidth; x++) {
                        var index = y * stride + x * 4;
                        for (var channel = 0; channel < 4; channel++) {
                            var difference = Math.Abs(after[index + channel] - before[index + channel]);
                            if (difference == 0) continue;
                            if (x < (at.X - 1) * scale || difference > 38)
                                throw new Exception("Watermark must stay low-contrast and leave the left-hand content unchanged");
                            changed++; break;
                        }
                    }
                    if (changed < 30) throw new Exception("Watermark must visibly render its real bundled artwork, not a blank placeholder");
                    if (scale == 1 && preview == "sourceOnly" && locale == "zh-CN" &&
                        Environment.GetEnvironmentVariable("STARBRIDGE_NOTIFICATION_BRAND_RENDER_OUTPUT") is { Length: > 0 } output) {
                        Directory.CreateDirectory(output);
                        var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(branded));
                        using var file = File.Create(Path.Combine(output, $"brand-{kind}-{appearance}.png")); encoder.Save(file);
                    }
                }
            }
        }
        Console.WriteLine("PASS notification brand: all card types, three locales, two themes, privacy, four DPI scales and no content/input changes");
    }

    private static IEnumerable<DependencyObject> Descendants(DependencyObject root) {
        for (var i = 0; i < VisualTreeHelper.GetChildrenCount(root); i++) {
            var child = VisualTreeHelper.GetChild(root, i); yield return child;
            foreach (var item in Descendants(child)) yield return item;
        }
    }
    private static void ObserveFirstChangedFrame(Func<bool> notStarted, Action assertIntermediate) {
        var frame = new DispatcherFrame();
        Exception? failure = null;
        var observed = false;
        var deadline = new DispatcherTimer { Interval = TimeSpan.FromSeconds(2) };
        void Observe(object? sender, EventArgs args) {
            // A pending animation is not an intermediate frame. Once it changes,
            // validate immediately: never wait past an invalid frame for a pass.
            try {
                if (notStarted()) return;
                assertIntermediate();
                observed = true;
            }
            catch (Exception error) { failure = error; }
            frame.Continue = false;
        }
        deadline.Tick += (_, _) => { deadline.Stop(); frame.Continue = false; };
        CompositionTarget.Rendering += Observe;
        try { deadline.Start(); Dispatcher.PushFrame(frame); }
        finally { deadline.Stop(); CompositionTarget.Rendering -= Observe; }
        if (failure is not null) throw failure;
        if (!observed) throw new TimeoutException("No intermediate animation frame within two seconds");
    }
    private static void Pump(int milliseconds) {
        var frame = new DispatcherFrame();
        var timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(milliseconds) };
        timer.Tick += (_, _) => { timer.Stop(); frame.Continue = false; };
        timer.Start(); Dispatcher.PushFrame(frame);
    }
}
