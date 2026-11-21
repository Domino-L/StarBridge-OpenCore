using System.Diagnostics;
using StarBridge.HostRuntime.Notifications;
using StarBridge.NativeBridge;

internal static class PlayerActivityOfflineSettleTests
{
    private sealed class Sink(Func<double> seconds) : IDesktopNotificationSink
    {
        private readonly List<(DesktopNotification Notice, double At)> _seen = [];
        internal (DesktopNotification Notice, double At)[] Seen { get { lock (_seen) return _seen.ToArray(); } }
        public ValueTask<bool> TryPresentAsync(DesktopNotification notice, CancellationToken token)
        {
            lock (_seen) _seen.Add((notice, seconds()));
            return ValueTask.FromResult(true);
        }
        public void Clear() { }
        public void Dispose() { }
    }

    private sealed class Fixture : IAsyncDisposable
    {
        internal readonly string Root = Path.Combine(Path.GetTempPath(), "activity-settle-" + Guid.NewGuid().ToString("N"));
        internal readonly CelebrationTestClock Clock = new();
        internal readonly PlayerActivityPreferencesStore Store;
        internal readonly Sink Cards;
        internal readonly PlayerActivityRuntime Runtime;
        internal long Generation = 1;
        internal bool Current = true;
        internal PlayerActivityEnvironment Environment = new(true, true, false, false);
        private long _sequence;
        internal Fixture()
        {
            Directory.CreateDirectory(Root);
            Store = new(Root);
            Store.Save(new(Enabled: true, Scope: 4, Offline: true, StoppedGame: true), Store.Read().Revision);
            Cards = new(() => (double)Clock.GetTimestamp() / Clock.TimestampFrequency);
            Runtime = new(Root, () => Generation, Cards, () => Environment,
                () => (long)((double)Clock.GetTimestamp() / Clock.TimestampFrequency * Stopwatch.Frequency), Clock);
        }
        internal Task Observe(params string[] states) => Runtime.ObserveAsync(new(Generation, "fixture", "friends", "friends",
            ++_sequence, true, states.Select((state, index) => new PlayerActivityObservedMember(
                "peer" + index, "Peer" + index, "fixture" + index, state, false, true)).ToArray(), () => Current));
        internal async Task Offline(params string[] states)
        {
            await Observe(states);
            await CelebrationTestClock.Until(() => Clock.Waiting(TimeSpan.FromSeconds(20)));
        }
        internal void Advance(int seconds) => Clock.Advance(TimeSpan.FromSeconds(seconds));
        internal Task WaitCount(int count) => CelebrationTestClock.Until(() => Cards.Seen.Length >= count);
        internal void Kinds(params string[] kinds) => Check(Cards.Seen.Select(n => n.Notice.Activity?.Kind).SequenceEqual(kinds),
            "Expected exactly: " + string.Join(",", kinds));
        public async ValueTask DisposeAsync()
        {
            Runtime.Dispose();
            await Runtime.RetireAccountActivityAsync();
            Directory.Delete(Root, true);
        }
    }

    internal static async Task Run()
    {
        await ShortReturn();
        await LongOfflineAndReturn();
        await ExpiryWhileEnvironmentUnknown();
        await IndependentMembers();
        await RealGameChanges();
        await Invalidations();
        await GroupedOffline();
        await TestCardIsImmediate();
    }

    private static async Task ShortReturn()
    {
        foreach (var state in new[] { "online", "away" })
        {
            await using var f = new Fixture();
            await f.Observe("online");
            await f.Offline("offline");
            f.Kinds(); f.Advance(5);
            await f.Observe(state);
            f.Advance(20);
            await f.Runtime.OfflineSettleWork.WaitAsync(TimeSpan.FromSeconds(2));
            f.Kinds();
        }
        // Recovery time is the social read time, even when the native environment is unknown.
        await using var unknown = new Fixture();
        await unknown.Observe("online"); await unknown.Offline("offline");
        unknown.Advance(5); unknown.Environment = new(false, true, false, false);
        await unknown.Observe("online");
        unknown.Advance(20); unknown.Environment = new(true, true, false, false);
        await unknown.Observe("online");
        await unknown.Runtime.OfflineSettleWork.WaitAsync(TimeSpan.FromSeconds(2)); unknown.Kinds();
    }

    // Review R P2: a hold that expires while the native environment is momentarily unknown is
    // parked, not lost; once the environment is known again the member still offline gets one card.
    private static async Task ExpiryWhileEnvironmentUnknown()
    {
        await using var f = new Fixture();
        await f.Observe("online"); await f.Offline("offline");
        f.Environment = new(false, true, false, false);
        f.Advance(20);
        await f.Runtime.OfflineSettleWork.WaitAsync(TimeSpan.FromSeconds(2));
        f.Kinds();
        f.Environment = new(true, true, false, false);
        await f.Observe("offline");
        await f.WaitCount(1);
        f.Kinds("Offline");
        await f.Observe("offline");
        f.Kinds("Offline");
    }

    private static async Task LongOfflineAndReturn()
    {
        await using var f = new Fixture();
        await f.Observe("online"); await f.Offline("offline");
        f.Advance(19); f.Kinds();
        f.Advance(1); await f.WaitCount(1);
        f.Kinds("Offline");
        Check(f.Cards.Seen.Single().At >= 20, "Offline must never appear before 20 seconds");
        f.Advance(5); await f.Observe("offline");
        f.Kinds("Offline");
        await f.Observe("online"); f.Kinds("Offline", "Online");
    }

    private static async Task IndependentMembers()
    {
        foreach (var bothReturn in new[] { true, false })
        {
            await using var f = new Fixture();
            await f.Observe("online", "online"); await f.Offline("offline", "offline");
            f.Advance(5); await f.Observe("online", bothReturn ? "online" : "offline");
            f.Kinds(); f.Advance(20);
            if (!bothReturn)
            {
                await f.WaitCount(1); f.Kinds("Offline");
                Check(f.Cards.Seen.Single().Notice.Activity?.MemberKey == "peer1", "Only the absent member may notify");
            }
            await f.Runtime.OfflineSettleWork.WaitAsync(TimeSpan.FromSeconds(2));
            f.Kinds(bothReturn ? [] : ["Offline"]);
        }
    }

    private static async Task RealGameChanges()
    {
        foreach (var (before, after, expected) in new[] {
            ("online", "inGame", "StartedGame"), ("inGame", "online", "StoppedGame"),
            ("inGame", "inGame", ""), ("away", "inGame", ""), ("inGame", "away", "") })
        {
            await using var f = new Fixture();
            await f.Observe(before); await f.Offline("offline");
            f.Advance(5); await f.Observe(after);
            f.Kinds(expected.Length == 0 ? [] : [expected]);
            f.Advance(20); await f.Runtime.OfflineSettleWork.WaitAsync(TimeSpan.FromSeconds(2));
            f.Kinds(expected.Length == 0 ? [] : [expected]);
        }
        await using var disabled = new Fixture();
        disabled.Store.Save(disabled.Store.Read().Value with { StartedGame = false }, disabled.Store.Read().Revision);
        await disabled.Observe("online"); await disabled.Offline("offline");
        disabled.Advance(5); await disabled.Observe("inGame");
        await disabled.Runtime.RetireAccountActivityAsync(); disabled.Kinds();
    }

    private static async Task Invalidations()
    {
        foreach (var change in new[] { "settings", "dnd", "logout", "generation", "newGeneration", "account", "dispose", "missing", "privacy", "lease", "policy" })
        {
            await using var f = new Fixture();
            var owner = new BridgeAccountContext("fixture", "fixture", "owner");
            var policies = new NotificationPolicyStore(f.Root);
            if (change == "policy") f.Runtime.ConfigurePolicyOwner(() => owner);
            await f.Observe("online"); await f.Offline("offline");
            var settled = f.Runtime.OfflineSettleWork;
            f.Advance(5);
            switch (change)
            {
                case "settings": f.Store.Save(f.Store.Read().Value with { Offline = false }, f.Store.Read().Revision); break;
                case "dnd":
                    var path = Path.Combine(f.Root, "notification.settings.json");
                    var json = System.Text.Json.Nodes.JsonNode.Parse(File.ReadAllText(path))!.AsObject();
                    json["DoNotDisturb"] = true;
                    File.WriteAllText(path, json.ToJsonString()); break;
                case "logout": await f.Runtime.RetireAccountActivityAsync(); break;
                case "generation": f.Generation++; break;
                case "newGeneration": f.Generation++; await f.Observe("offline"); break;
                case "account": f.Runtime.Reset(); break;
                case "dispose": f.Runtime.Dispose(); break;
                case "missing": await f.Observe(); break;
                case "privacy":
                    await f.Runtime.ObserveAsync(new(1, "fixture", "friends", "friends", 3, true,
                        [new("peer0", "Peer0", "fixture0", "offline", false, false)], () => true)); break;
                case "lease": f.Current = false; break;
                case "policy": policies.Save(owner, policies.Read(owner).Revision, Guid.NewGuid().ToString("N"),
                    [new("friends", NotificationSourceMode.DoNotDisturb)], () => true); break;
            }
            f.Advance(20);
            // Wait for the actual due-time checks; retiring here would mask guard failures.
            await settled.WaitAsync(TimeSpan.FromSeconds(2));
            f.Kinds();
        }
    }

    private static async Task GroupedOffline()
    {
        var hold = PlayerActivityRuntime.GroupHold;
        PlayerActivityRuntime.GroupHold = TimeSpan.FromMilliseconds(20);
        try
        {
            await using var f = new Fixture();
            await f.Observe("online", "online", "online");
            await f.Offline("offline", "offline", "offline");
            f.Advance(19); f.Kinds();
            f.Advance(1); await f.WaitCount(1);
            f.Kinds("Offline");
            var card = f.Cards.Seen.Single();
            Check(card.At >= 20 && card.Notice.Activity?.GroupNames?.Length == 3 &&
                card.Notice.Activity.OnlineNow == 0, "Three settled departures share one card with current counts");
        }
        finally { PlayerActivityRuntime.GroupHold = hold; }
    }

    private static async Task TestCardIsImmediate()
    {
        await using var f = new Fixture();
        await f.Observe("online"); await f.Offline("offline");
        var request = BridgeEnvelope.Request("playerActivity.test", Guid.NewGuid().ToString("N"), 1, new { schemaVersion = 1 });
        await f.Runtime.DispatchAsync(request);
        Check(f.Cards.Seen.Length == 1 && f.Cards.Seen[0].Notice.Test && f.Cards.Seen[0].At == 0,
            "Device test card is not delayed by pending offline activity");
    }

    private static void Check(bool value, string message) { if (!value) throw new Exception(message); }
}
