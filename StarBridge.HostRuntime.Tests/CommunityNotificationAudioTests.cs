using StarBridge.HostRuntime.Notifications;
using StarBridge.HostRuntime.Communities;
using StarBridge.NativeBridge;

internal static class CommunityNotificationAudioTests
{
    private sealed class Clock : TimeProvider {
        internal long Seconds;
        public override long TimestampFrequency => 1;
        public override long GetTimestamp() => Seconds;
    }
    private sealed class Output : INotificationAudioOutput {
        internal int Plays; internal byte[]? Last;
        public bool TryPlay(byte[] wave) { Plays++; Last = wave; return true; }
        public void Stop() { }
        public void Dispose() { }
    }
    private sealed class Reader : ICommunityNotificationReader {
        internal CommunityNotificationFeed Feed = new(DateTimeOffset.UtcNow, []);
        internal bool Fail;
        internal TaskCompletionSource<CommunityNotificationFeed>? Pending;
        public Task<CommunityNotificationFeed> ReadNotificationsAsync(BridgeAccountContext _, long generation, CancellationToken token) =>
            Pending?.Task ?? (Fail ? Task.FromException<CommunityNotificationFeed>(new IOException("synthetic unavailable")) : Task.FromResult(Feed));
    }
    internal static async Task Run()
    {
        await PendingWork();
        var root = Path.Combine(Path.GetTempPath(), "sb-community-audio-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try {
            var wave = NotificationAudioTests.Wave();
            File.WriteAllBytes(Path.Combine(root, "soft.wav"), wave);
            File.WriteAllText(Path.Combine(root, "cue-catalog.v1.json"), NotificationAudioTests.Manifest(wave));
            var settings = new NotificationAudioSettingsStore(root); settings.Save(0, true, .5);
            var clock = new Clock(); var output = new Output(); var allowed = true; var current = true;
            var owner = new BridgeAccountContext("fixture", "fixture", "owner");
            var now = DateTimeOffset.UtcNow;
            var key = NotificationPolicyStore.Organization("SYNTHETIC", now.AddDays(-1));
            var policies = new NotificationPolicyStore(root);
            using var audio = new NotificationAudioBridgeDispatcher(root, NotificationAudioCatalog.Load(root), output, () => 1,
                () => allowed, clock, canPlaySocial: () => allowed);
            var source = new CommunityNotificationSource("source", "Fleet", now.AddDays(-1), true, null, true, [], key);
            CommunityNotificationNotice Notice(NotificationEventKind kind) => new(owner, source, kind, () => current);
            Check(audio.TryPlayCommunity(Notice(NotificationEventKind.OrganizationManagement)), "Fresh authorized management event plays.");
            Check(output.Last!.SequenceEqual(NotificationWaveGain.Apply(wave, .5)), "Community sound applies the configured gain exactly once.");
            Check(!audio.TryPlayCommunity(Notice(NotificationEventKind.OrganizationChat)), "Community sounds share the one-second cooldown.");
            clock.Seconds = 2;
            policies.Save(owner, 0, Guid.NewGuid().ToString("N"), [new(key, NotificationSourceMode.ImportantOnly)], () => true);
            Check(!audio.TryPlayCommunity(Notice(NotificationEventKind.OrganizationChat)) &&
                audio.TryPlayCommunity(Notice(NotificationEventKind.OrganizationManagement)), "Important-only keeps applications but suppresses ordinary chat.");
            clock.Seconds = 4;
            policies.Save(owner, 1, Guid.NewGuid().ToString("N"), [new(key, NotificationSourceMode.DoNotDisturb)], () => true);
            Check(!audio.TryPlayCommunity(Notice(NotificationEventKind.OrganizationManagement)), "Source DND suppresses sound.");
            policies.Save(owner, 2, Guid.NewGuid().ToString("N"), [], () => true);
            current = false; Check(!audio.TryPlayCommunity(Notice(NotificationEventKind.OrganizationManagement)), "Stale accounts cannot play.");
            current = true; allowed = false; Check(!audio.TryPlayCommunity(Notice(NotificationEventKind.OrganizationManagement)), "Environment suppression remains authoritative.");
            allowed = true; settings.Save(settings.Read().Revision, false, .5);
            Check(!audio.TryPlayCommunity(Notice(NotificationEventKind.OrganizationManagement)), "Disabled sound cannot play.");
            settings.Save(settings.Read().Revision, true, 0);
            Check(!audio.TryPlayCommunity(Notice(NotificationEventKind.OrganizationManagement)), "Zero volume stays silent.");
            settings.Save(settings.Read().Revision, true, .5);
            Check(!audio.TryPlayCommunity(Notice(NotificationEventKind.OrganizationManagement) with { Source = source with { ManagementAvailable = false } }), "Missing management permission cannot sound.");
            Check(!audio.TryPlayCommunity(Notice(NotificationEventKind.OrganizationManagement) with { Source = source with { PolicyKey = "" } }), "No source policy identity means no sound.");
            // Exercise the actual continuous feed observer, not merely the output helper.
            var reader = new Reader();
            using var runtime = new CommunityNotificationRuntime(reader, () => (owner, 1), (notice, _) => {
                audio.TryPlayCommunity(notice); return ValueTask.CompletedTask;
            }, clock);
            CommunityNotificationFeed Feed(int second, string task) => new(now.AddSeconds(second), [source with {
                Tasks = [new(task, now.AddSeconds(second))]
            }]);
            reader.Feed = Feed(0, "old"); await runtime.TickAsync(); var baseline = output.Plays;
            clock.Seconds = 10; reader.Feed = Feed(10, "new"); await runtime.TickAsync();
            Check(output.Plays == baseline + 1, "New join-management task in the continuous feed reaches sound.");
            await runtime.TickAsync(); Check(output.Plays == baseline + 1, "Repeated feed does not replay.");
            policies.Save(owner, 3, Guid.NewGuid().ToString("N"), [new(key, NotificationSourceMode.DoNotDisturb)], () => true);
            clock.Seconds = 12; reader.Feed = Feed(12, "muted"); await runtime.TickAsync();
            policies.Save(owner, 4, Guid.NewGuid().ToString("N"), [], () => true);
            clock.Seconds = 14; reader.Feed = Feed(14, "muted"); await runtime.TickAsync();
            Check(output.Plays == baseline + 1, "Unmuting cannot replay an event consumed under DND.");
            var officialKey = NotificationPolicyStore.OfficialFleet("officialFleet:7");
            CommunityNotificationFeed Official(int second, long sequence, bool incoming = true) => new(now.AddSeconds(second), [
                new("official", "Official fleet", null, true,
                    new(sequence, 1, incoming, now.AddSeconds(second), now.AddSeconds(second), "", "Fixture message"),
                    false, [], officialKey, SourceKind: OrganizationNotificationSourceKind.OfficialFleet)
            ]);
            clock.Seconds = 16; reader.Feed = Official(16, 1); await runtime.TickAsync();
            var officialBaseline = output.Plays;
            clock.Seconds = 18; reader.Feed = Official(18, 2); await runtime.TickAsync();
            Check(output.Plays == officialBaseline + 1, "same organization runtime delivers fresh official chat through the existing audio owner");
            policies.Save(owner, policies.Read(owner).Revision, Guid.NewGuid().ToString("N"), [new(officialKey, NotificationSourceMode.DoNotDisturb)], () => true);
            clock.Seconds = 20; reader.Feed = Official(20, 3); await runtime.TickAsync();
            policies.Save(owner, policies.Read(owner).Revision, Guid.NewGuid().ToString("N"), [], () => true);
            clock.Seconds = 22; reader.Feed = Official(22, 3); await runtime.TickAsync();
            Check(output.Plays == officialBaseline + 1, "official source DND consumes audio events without replay on unmute");
            clock.Seconds = 24; reader.Feed = Official(24, 4, false); await runtime.TickAsync();
            Check(output.Plays == officialBaseline + 1, "own official messages are quiet before audio output");
            clock.Seconds = 26; reader.Feed = Official(26, 5); await runtime.TickAsync();
            Check(output.Plays == officialBaseline + 2, "next fresh incoming official message can sound");
            allowed = false; clock.Seconds = 28; reader.Feed = Official(28, 6); await runtime.TickAsync();
            allowed = true; clock.Seconds = 30; reader.Feed = Official(30, 6); await runtime.TickAsync();
            Check(output.Plays == officialBaseline + 2, "suppressed official sound cannot replay after environment becomes eligible");
            File.WriteAllBytes(Path.Combine(root, "soft.wav"), [0]); clock.Seconds = 32;
            Check(!audio.TryPlayCommunity(Notice(NotificationEventKind.OrganizationManagement)), "Modified cue fails integrity checks.");
            Console.WriteLine("PASS organization management sound policy, gain, freshness and deduplication");
        } finally { Directory.Delete(root, true); }
    }
    private static void Check(bool value, string message) { if (!value) throw new Exception(message); }
    private static async Task PendingWork() {
        var now = DateTimeOffset.UtcNow;
        var owner = new BridgeAccountContext("test", "test", "pending-fixture");
        long generation = 1;
        var source = new CommunityNotificationSource("fixture", "Synthetic", now, false, null, true,
            [new("old", now.AddHours(-1))]);
        var reader = new Reader { Feed = new(now, [source]) };
        var counts = new List<int>();
        var popups = 0;
        using var runtime = new CommunityNotificationRuntime(reader, () => (owner, generation),
            (_, _) => { popups++; return ValueTask.CompletedTask; },
            pendingManagement: (_, count) => counts.Add(count));
        await runtime.TickAsync();
        Check(counts.SequenceEqual([1]) && popups == 0, "Startup pending work must highlight without replaying historical popups.");
        reader.Feed = new(now.AddMilliseconds(1), [source with { ManagementAvailable = false, ManagementConfirmed = false, Tasks = [] }]);
        await runtime.TickAsync();
        Check(counts.Last() == 1, "Partial unavailable management read is not confirmed empty work.");
        reader.Fail = true; await runtime.TickAsync();
        Check(counts.Count == 2 && counts.Last() == 1, "A network failure cannot claim pending work is empty.");
        reader.Fail = false; reader.Feed = new(now.AddSeconds(1), [source with { Tasks = [] }]);
        await runtime.TickAsync(); Check(counts.Last() == 0, "Confirmed completion clears pending work.");
        reader.Pending = new();
        var pending = runtime.TickAsync();
        generation++; runtime.Invalidate();
        reader.Pending.SetResult(new(now.AddSeconds(2), [source]));
        await pending;
        Check(counts.Last() == 0, "Old account in-flight reads cannot restore old taskbar attention.");
        Console.WriteLine("PASS pending management baseline, completion, failure retention and account fencing");
    }
}
