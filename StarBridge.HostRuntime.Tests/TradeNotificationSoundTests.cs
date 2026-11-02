using System.Security.Cryptography;
using System.Text.Json;
using StarBridge.HostRuntime.Notifications;
using StarBridge.NativeBridge;

// The trade cue: which events sound, what gates them, and which file plays.
internal static class TradeNotificationSoundTests
{
    private static int _checks;
    private static void Check(bool value, string message) {
        if (!value) throw new InvalidOperationException(message);
        _checks++;
    }
    private sealed class Desktop : IDesktopNotificationSink {
        internal readonly List<DesktopNotification> Notices = [];
        public ValueTask<bool> TryPresentAsync(DesktopNotification notice, CancellationToken token) {
            Notices.Add(notice); return ValueTask.FromResult(true);
        }
        public void Clear() { }
        public void Dispose() { }
    }
    private sealed class Output : INotificationAudioOutput {
        internal readonly List<byte[]> Played = [];
        public bool TryPlay(byte[] wave) { Played.Add(wave); return true; }
        public void Stop() { }
        public void Dispose() { }
    }
    private sealed class Clock : TimeProvider {
        private long _ticks;
        public override long TimestampFrequency => TimeSpan.TicksPerSecond;
        public override long GetTimestamp() => _ticks;
        internal void Advance(TimeSpan time) => _ticks += time.Ticks;
    }

    internal static async Task<int> Run()
    {
        _checks = 0;
        await Observer();
        Playback();
        Console.WriteLine($"PASS trade notification sound assertions: {_checks} passed, 0 failed");
        return _checks;
    }

    private static TradeNotificationEvent Order(string key) => new(key, false, null, 4, "", "Aurora", "", "");
    private static TradeNotificationEvent Chat(string key) => new(key, true, new string('a', 32), 0, "", "", "Kestrel", "");

    private static async Task Observer()
    {
        var root = Directory.CreateTempSubdirectory("trade-sound-observer-").FullName;
        NotificationSettingsBridgeDispatcher? settings = null;
        try {
            var owner = new BridgeAccountContext("fixture", "scm", "synthetic-owner");
            var sink = new Desktop();
            var plays = new List<bool>();
            Func<bool>? lastCurrent = null;
            var throwing = false;
            var gateFree = true;
            settings = new NotificationSettingsBridgeDispatcher(root, () => 1, () => true, desktop: sink,
                playTrade: (chat, current) => {
                    // Audio's gate is taken before the settings gate elsewhere, so this must not hold it.
                    gateFree &= Task.Run(async () => await settings!.DispatchAsync(BridgeEnvelope.Request(
                        "notificationSettings.read", Guid.NewGuid().ToString("N"), 1, new { schemaVersion = 1 }))).Wait(TimeSpan.FromSeconds(10));
                    plays.Add(chat); lastCurrent = current;
                    if (throwing) throw new IOException("Synthetic audio failure");
                    return true;
                });
            void Save(bool master, bool trade) => File.WriteAllText(Path.Combine(root, "notification-settings.v1.json"),
                JsonSerializer.Serialize(new LocalNotificationSettings(WindowsEnabled: master, TradeWindowsEnabled: trade), BridgeProtocol.JsonOptions));
            Task Present(TradeNotificationEvent item, bool source = true) => settings.PresentTradeAsync(owner, 1, item, () => source);

            await Present(Order("a"));
            Check(plays.SequenceEqual([false]) && sink.Notices.Count == 0, "Sound does not depend on the Windows card master");
            Check(gateFree, "The cue is requested outside the settings gate");
            await Present(Order("a"));
            Check(plays.Count == 1, "A duplicate event sounds once");
            await Present(Chat("b"));
            Check(plays.SequenceEqual([false, true]), "Chat events are identified to the audio side");
            await Present(Order("c"), source: false);
            Check(plays.Count == 2, "A stale source is silent");

            Save(true, false);
            await Present(Order("d"));
            Check(plays.Count == 2 && sink.Notices.Count == 0, "The trade switch silences the sound and the card");

            Save(true, true);
            await Present(Order("e"));
            Check(plays.Count == 3 && sink.Notices.Count == 1, "Sound and card both follow one fresh event");
            Check(lastCurrent!(), "A fresh event is current");
            settings.InvalidateTrade();
            Check(!lastCurrent!(), "Invalidation makes a deferred cue stale");

            throwing = true;
            await Present(Order("f"));
            Check(plays.Count == 4 && sink.Notices.Count == 2, "A failed cue does not block the card");
        }
        finally { settings?.Dispose(); Directory.Delete(root, true); }
    }

    private static void Playback()
    {
        var root = Directory.CreateTempSubdirectory("trade-sound-playback-").FullName;
        try {
            var trade = NotificationAudioTests.Wave(16);
            var soft = NotificationAudioTests.Wave(24);
            File.WriteAllBytes(Path.Combine(root, "trade.wav"), trade);
            File.WriteAllBytes(Path.Combine(root, "soft.wav"), soft);
            File.WriteAllText(Path.Combine(root, "cue-catalog.v1.json"), JsonSerializer.Serialize(new { schemaVersion = 1, assets = new[] {
                new { assetId = "trade", cueId = NotificationAudioCueIds.Trade, fileName = "trade.wav", tier = "approved", priority = 320, sha256 = Convert.ToHexString(SHA256.HashData(trade)) },
                new { assetId = "soft", cueId = NotificationAudioCueIds.Soft, fileName = "soft.wav", tier = "approved", priority = 320, sha256 = Convert.ToHexString(SHA256.HashData(soft)) }
            }}));
            var output = new Output(); var time = new Clock(); var social = true;
            var celebration = new StarBridge.HostRuntime.Achievements.AchievementCelebrationActivity();
            var store = new NotificationAudioSettingsStore(root);
            using var audio = new NotificationAudioBridgeDispatcher(root, NotificationAudioCatalog.Load(root), output, () => 1,
                time: time, canPlaySocial: () => social, celebration: celebration);
            void Next() => time.Advance(TimeSpan.FromSeconds(2));

            store.Save(0, false, 1);
            Check(!audio.TryPlayTrade(false, () => true), "The sound switch silences trade");
            store.Save(1, true, 0);
            Check(!audio.TryPlayTrade(false, () => true), "Zero volume silences trade");
            store.Save(2, true, 1);
            Check(!audio.TryPlayTrade(false, () => false), "A stale event is silent");
            social = false;
            Check(!audio.TryPlayTrade(false, () => true), "Windows quiet mode silences trade");
            social = true;
            Check(output.Played.Count == 0, "Nothing played while gated");

            Check(audio.TryPlayTrade(false, () => true) && output.Played.Last().SequenceEqual(trade), "An order event plays the trade cue");
            Check(!audio.TryPlayTrade(false, () => true) && output.Played.Count == 1, "A burst plays once per second");
            Next();
            Check(audio.TryPlayTrade(true, () => true) && output.Played.Last().SequenceEqual(soft), "Trade chat plays the ordinary message cue");
            Next();
            celebration.Report(true);
            Check(!audio.TryPlayTrade(false, () => true) && output.Played.Count == 2, "A celebration holds the cue");
            celebration.Report(false);
            audio.DrainDeferred();
            Check(output.Played.Count == 3 && output.Played.Last().SequenceEqual(trade), "The held cue plays afterwards");
            Next();
            File.Delete(Path.Combine(root, "trade.wav"));
            Check(audio.TryPlayTrade(false, () => true) && output.Played.Last().SequenceEqual(soft), "A missing trade file falls back to the message cue");
        }
        finally { Directory.Delete(root, true); }
    }
}
