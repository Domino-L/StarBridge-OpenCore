using StarBridge.HostRuntime.Achievements;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Presence;
using StarBridge.NativeBridge;

internal static class AchievementRuntimeTests
{
    private static readonly BridgeAccountContext Owner = new("test", "scm", "synthetic-achievement-a");
    private sealed class Clock : TimeProvider
    {
        internal DateTimeOffset Now = DateTimeOffset.Parse("2026-09-04T12:00:30Z");
        public override DateTimeOffset GetUtcNow() => Now;
    }
    private sealed class Cloud : IAchievementRemote
    {
        internal readonly Dictionary<BridgeAccountContext, Dictionary<string, DateTimeOffset>> Saved = [];
        internal int Reports, Reads; internal bool Offline, LoseReceipt;
        internal Dictionary<string, int>? Progress;
        internal Action? BeforeReceipt;
        internal TaskCompletionSource? Reading, Release;
        public async Task<AchievementSnapshot> ReadAchievementsAsync(BridgeAccountContext owner, long generation, CancellationToken token)
        {
            Reads++;
            if (Reading is not null) { Reading.TrySetResult(); await Release!.Task; }
            if (Offline) throw new IOException("synthetic outage");
            return new(1, Saved.TryGetValue(owner, out var records) ? new(records) : [], Progress is null ? null : new(Progress));
        }
        public Task<AchievementReceipt> ObserveFirstEntryAsync(BridgeAccountContext owner, long generation, FirstEntryObservation observation, CancellationToken token)
        {
            if (Offline) throw new IOException("synthetic outage");
            Require(observation.IsValid, "Host sends only finite game entry evidence"); Reports++;
            if (!Saved.TryGetValue(owner, out var earned)) Saved[owner] = earned = [];
            var created = earned.TryAdd("first-entry", DateTimeOffset.Parse("2026-09-04T12:00:30Z"));
            BeforeReceipt?.Invoke();
            if (LoseReceipt) { LoseReceipt = false; throw new IOException("synthetic lost acknowledgement"); }
            return Task.FromResult(new AchievementReceipt(1, new(earned), created));
        }
    }
    private sealed class Harness : IDisposable
    {
        internal readonly string Root;
        internal string Log => Path.Combine(Root, "StarCitizen", "LIVE", "Game.log");
        internal readonly Clock Time = new(); internal readonly Cloud Remote;
        internal (BridgeAccountContext? Context, long Generation) Current = (Owner, 1);
        internal string Expected = "Pilot_A"; internal GameProcessSession Process;
        internal readonly GameLogRuntime Game; internal readonly AchievementRuntime Achievements;
        internal readonly StarBridge.HostRuntime.Account.OfflineAccountStore Cache;
        internal int Changes, Earned;
        internal Harness(Cloud? remote = null, string? root = null)
        {
            Root = root ?? Path.Combine(Path.GetTempPath(), "sb-achievement-tests-" + Guid.NewGuid().ToString("N"));
            Remote = remote ?? new(); Directory.CreateDirectory(Path.GetDirectoryName(Log)!);
            if (!File.Exists(Log)) File.WriteAllText(Log, Identity("Pilot_A"));
            Process = new("running", Log, Time.Now.AddSeconds(-30), "synthetic-process");
            Game = new(new GameLogSettingsStore(Root), () => Current, () => Expected,
                () => Process, Time, false, new GameLogLocator(() => [Path.Combine(Root, "StarCitizen")]));
            Cache = new(Root);
            Cache.Observe(Owner, "Synthetic Pilot", () => true);
            Achievements = new(new(Root), Remote, () => Current, Game.CaptureFirstEntry, _ => Changes++, Time, false, (_, _) => Earned++,
                confirmed: Cache.ObserveAchievements, cached: Cache.ReadSelectedAchievements);
            Game.PublicationChanged += () => Achievements.Observe(Game.CaptureFirstEntry());
        }
        internal void Select() => Game.Dispatch(BridgeEnvelope.Request("gameLog.select", Guid.NewGuid().ToString("N"),
            Current.Generation, new { schemaVersion = 1, path = Log }, Current.Context));
        internal void Enter() { File.AppendAllText(Log, "<2026-09-04T12:00:20Z> <Join PU> connected to shard[pub_sc_alpha_apse1_123]\n"); Game.Sample(); }
        internal Task<BridgeDispatchBatch> Read(string name = "achievements.read", object? payload = null) => Achievements.DispatchAsync(
            BridgeEnvelope.Request(name, Guid.NewGuid().ToString("N"), Current.Generation, payload ?? new { schemaVersion = 1 }, Current.Context), default);
        internal void Close() { Game.Dispose(); Achievements.Dispose(); }
        public void Dispose() { Close(); if (Directory.Exists(Root)) Directory.Delete(Root, true); }
    }
    private static string Identity(string handle) => $"<2026-09-04T12:00:10Z> [Notice] nickname=\"{handle}\" playerGEID=12345\n";
    private static void Require(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
    internal static async Task ConfirmedCacheNeverFlashesLocked()
    {
        using var h = new Harness();
        var at = DateTimeOffset.UtcNow.AddDays(-1);
        h.Remote.Saved[Owner] = new() { ["first-entry"] = at, ["hangar-home-1"] = at, ["hangar-home-2"] = at };
        h.Remote.Progress = new() { ["hangar-home"] = 4 };
        await h.Achievements.TickAsync(true);
        h.Remote.Offline = true;
        await h.Achievements.TickAsync(true);
        var retained = await h.Read();
        Require(retained.Response.Status == BridgeResponseStatuses.Ok &&
            retained.Response.Payload.GetProperty("earnedAt").TryGetProperty("first-entry", out _),
            "A refresh failure must not replace a confirmed earned image with a locked image");
        Require(h.Earned == 0, "Restoring cached collection never celebrates a new award");
        h.Remote.Offline = false;
        h.Remote.Saved[Owner].Clear();
        h.Remote.Progress["hangar-home"] = 2;
        await h.Achievements.TickAsync(true);
        Require((await h.Read()).Response.Payload.GetProperty("earnedAt").TryGetProperty("first-entry", out _),
            "A temporarily incomplete read cannot revoke a permanent confirmed milestone");
        Require((await h.Read()).Response.Payload.GetProperty("progress").GetProperty("hangar-home").GetInt32() == 4,
            "The server-confirmed historical peak cannot decrease during refresh");

        h.Close();
        using var restarted = new Harness(h.Remote, h.Root);
        restarted.Remote.Reading = new(); restarted.Remote.Release = new();
        try
        {
            var firstFrame = restarted.Read();
            await restarted.Remote.Reading.Task.WaitAsync(TimeSpan.FromSeconds(3));
            Require(firstFrame.IsCompletedSuccessfully &&
                (await firstFrame).Response.Payload.GetProperty("earnedAt").TryGetProperty("first-entry", out _),
                "Cold page entry serves the same-owner durable collection before the cloud completes");
            Require(restarted.Earned == 0, "Disk restoration is display-only and silent");
        }
        finally { restarted.Remote.Release.TrySetResult(); restarted.Remote.Reading = null; }
        restarted.Current = (Owner with { Subject = "different" }, 2);
        restarted.Achievements.Invalidate(2);
        Require(!(await restarted.Read()).Response.Payload.GetProperty("earnedAt").TryGetProperty("first-entry", out _),
            "A different account never inherits the prior account's cached artwork");
        restarted.Cache.ClearAchievements(Owner, () => true);
        Require(restarted.Cache.ReadSelectedAchievements(Owner, () => true) is null &&
            restarted.Cache.ReadSelectedDisplay(Owner, () => true) is not null,
            "Clearing achievement cache preserves other account display data");
    }
    internal static async Task RecognitionAndDevices()
    {
        using var h = new Harness(); h.Select();
        await h.Achievements.TickAsync(true); Require(h.Remote.Reports == 0, "Process and nickname alone are not entry");
        h.Enter(); Require(h.Game.CaptureFirstEntry() is not null, "Live matched PU server creates scoped entry evidence");
        await h.Achievements.TickAsync(true); var first = await h.Read();
        Require(first.Response.Payload.GetProperty("earnedAt").TryGetProperty("first-entry", out _), "Ordinary achievement read returns the cloud record");
        h.Enter(); await h.Achievements.TickAsync(true);
        Require(h.Remote.Reports == 1 && h.Changes == 2 && h.Earned == 1, "Repeated samples neither award nor invalidate nor celebrate again");
        using var otherDevice = new Harness(h.Remote); await otherDevice.Achievements.TickAsync(true);
        Require((await otherDevice.Read()).Response.Payload.GetProperty("earnedAt").GetProperty("first-entry").GetDateTimeOffset() ==
            first.Response.Payload.GetProperty("earnedAt").GetProperty("first-entry").GetDateTimeOffset(), "Same account restores on another device without running the game");
        Require(h.Remote.Reports == 1 && otherDevice.Earned == 0, "Restoration is a read, not another award or celebration");
        otherDevice.Cache.Pin(Owner, 5, () => true);
        Require(otherDevice.Cache.ReadAchievements(5)?.Collection.EarnedAt.ContainsKey("first-entry") == true,
            "Validated remote restoration is durably available offline without a new award");
        otherDevice.Cache.Observe(Owner, "Synthetic Pilot refreshed", () => true);
        otherDevice.Remote.Offline = true;
        await otherDevice.Achievements.TickAsync(true);
        otherDevice.Cache.Pin(Owner, 6, () => true);
        Require(otherDevice.Cache.ReadAchievements(6)?.Collection.EarnedAt.ContainsKey("first-entry") == true,
            "An outage and same-account profile refresh do not erase confirmed collection");
        otherDevice.Remote.Offline = false;
        otherDevice.Current = (Owner with { Subject = "synthetic-achievement-b" }, 2); otherDevice.Achievements.Invalidate(2);
        Require((await otherDevice.Read()).Response.Payload.GetProperty("earnedAt").EnumerateObject().Count() == 0, "Another account does not inherit collection");
        otherDevice.Cache.Observe(otherDevice.Current.Context!, "Other synthetic pilot", () => true);
        otherDevice.Cache.Pin(otherDevice.Current.Context!, 7, () => true);
        Require(otherDevice.Cache.ReadAchievements(7) is null, "Different account never inherits the previous collection");
    }
    internal static async Task InvalidGameEvidence()
    {
        using var h = new Harness(); File.WriteAllText(h.Log, Identity("Other_Pilot")); h.Select(); h.Enter();
        Require(h.Game.CaptureFirstEntry() is null, "Wrong game account cannot trigger");
        await h.Achievements.TickAsync(true); Require(h.Remote.Reports == 0, "Identity mismatch never reports");
        h.Process = new("notRunning"); h.Game.Sample();
        Require(h.Game.CaptureFirstEntry() is null, "Historical server and retained identity are not live evidence");
    }
    internal static async Task NewGrantSurvivesOutboxCleanupFailure()
    {
        using var h = new Harness(); h.Select(); h.Enter();
        FileStream? blocker = null;
        h.Remote.BeforeReceipt = () =>
        {
            var path = Directory.GetFiles(Path.Combine(h.Root, "achievements-pending-v1"), "*.json").Single();
            blocker = new FileStream(path, FileMode.Open, FileAccess.ReadWrite, FileShare.None);
        };
        try
        {
            await h.Achievements.TickAsync(true);
            Require(h.Remote.Reports == 1 && h.Remote.Saved[Owner].ContainsKey("first-entry"),
                "Cloud awarded and returned a valid new-grant receipt before the local cleanup failed");
            Require(h.Earned == 1,
                "Trusted new-grant celebration must survive local outbox cleanup failure");
        }
        finally { blocker?.Dispose(); h.Remote.BeforeReceipt = null; }
        await h.Achievements.TickAsync(true);
        Require(h.Earned == 1 && h.Remote.Reports == 1,
            "Cleanup retry restores the collection without replaying or re-awarding");
        using var saved = System.Text.Json.JsonDocument.Parse(File.ReadAllText(
            Directory.GetFiles(Path.Combine(h.Root, "achievements-pending-v1"), "*.json").Single()));
        Require(saved.RootElement.GetProperty("pending").ValueKind == System.Text.Json.JsonValueKind.Null,
            "Ordinary retry clears pending evidence after local storage is available again");
    }
    internal static async Task OfflineRestartAndLostAcknowledgement()
    {
        using var h = new Harness(); h.Select(); h.Remote.Offline = true; h.Enter();
        await h.Achievements.TickAsync(true);
        Require((await h.Read()).Response.Status == BridgeResponseStatuses.Error, "Offline unknown does not pretend earned or empty");
        Require(Directory.GetFiles(Path.Combine(h.Root, "achievements-pending-v1"), "*.json").Length == 1, "Entry evidence is durable before cloud IO");
        h.Close();
        using (var restarted = new Harness(h.Remote, h.Root)) {
            restarted.Process = new("notRunning"); h.Remote.Offline = false; h.Remote.LoseReceipt = true;
            await restarted.Achievements.TickAsync(true); Require(h.Remote.Reports == 1, "Pending entry survives exit and restart");
            await restarted.Achievements.TickAsync(true);
            Require((await restarted.Read()).Response.Status == BridgeResponseStatuses.Ok && h.Remote.Reports == 1,
                "Lost receipt is recovered by cloud read without a duplicate observation");
            using var saved = System.Text.Json.JsonDocument.Parse(File.ReadAllText(
                Directory.GetFiles(Path.Combine(h.Root, "achievements-pending-v1"), "*.json").Single()));
            Require(saved.RootElement.GetProperty("pending").ValueKind == System.Text.Json.JsonValueKind.Null, "Pending evidence clears only after cloud acknowledgement");
        }
    }
    internal static async Task AccountChangeDuringReadAndProtocol()
    {
        using var h = new Harness(); h.Remote.Reading = new(); h.Remote.Release = new(); h.Select(); h.Enter();
        var old = h.Achievements.TickAsync(true); await h.Remote.Reading.Task;
        h.Current = (Owner with { Subject = "new-account" }, 2); h.Achievements.Invalidate(2);
        h.Remote.Release.SetResult(); await old; h.Remote.Reading = null;
        Require(h.Remote.Reports == 0, "Late old-account read cannot start an observation write");
        Require((await h.Read()).Response.Payload.GetProperty("earnedAt").EnumerateObject().Count() == 0, "Old evidence cannot grant to a new account");
        var before = h.Remote.Reads;
        Require((await h.Read("achievements.award")).Response.Status == BridgeResponseStatuses.Error, "Flutter has no award command");
        Require((await h.Read(payload: new { schemaVersion = 1, subject = "forged" })).Response.Status == BridgeResponseStatuses.Error, "Client cannot select record owner");
        Require(h.Remote.Reads == before, "Invalid commands never reach remote collection");
    }
    internal static async Task ShortEntryAndRetryBackoff()
    {
        using var h = new Harness(); h.Select(); h.Remote.Offline = true; h.Enter();
        // The game may exit before the background cloud operation gets the gate.
        h.Process = new("notRunning"); h.Game.Sample();
        Require(h.Game.CaptureFirstEntry() is null, "Current game has already exited");
        await h.Achievements.TickAsync();
        var reads = h.Remote.Reads;
        h.Achievements.Wake(); await h.Achievements.TickAsync();
        Require(h.Remote.Reads == reads, "Game publication wakes respect offline retry backoff");
        h.Time.Now = h.Time.Now.AddSeconds(2); await h.Achievements.TickAsync();
        Require(h.Remote.Reads == reads + 1, "Elapsed retry deadline permits one more cloud attempt");
        h.Remote.Offline = false; h.Time.Now = h.Time.Now.AddSeconds(4);
        await h.Achievements.TickAsync();
        Require(h.Remote.Reports == 1 && h.Earned == 1,
            "Latched short entry is durably synchronized after the game exits");
        reads = h.Remote.Reads; h.Achievements.Wake(); await h.Achievements.TickAsync();
        Require(h.Remote.Reads == reads, "Ordinary publication wake does not defeat the cloud refresh interval");
    }
    internal static Task CorruptOutboxAndIsolation()
    {
        var root = Path.Combine(Path.GetTempPath(), "sb-achievement-storage-" + Guid.NewGuid().ToString("N"));
        try {
            var store = new AchievementOutbox(root); var evidence = new FirstEntryObservation(1, FirstEntryObservation.HashHandle("Pilot_A"), "LIVE");
            using (var lease = store.Open(Owner)) {
                lease.Save(evidence, () => true);
                try { using var duplicate = store.Open(Owner); throw new Exception("Two writers opened the same account"); } catch (IOException) { }
                try { lease.Save(null, () => false); throw new Exception("Stale commit succeeded"); } catch (OperationCanceledException) { }
                Require(lease.Read() == evidence, "Stale acknowledgement preserves pending evidence");
            }
            foreach (var other in new[] { Owner with { Subject = "other" }, Owner with { Authority = "other" }, Owner with { Environment = "other" } })
                using (var lease = store.Open(other)) Require(lease.Read() is null, "Environment, authority and subject isolate pending evidence");
            var data = Directory.GetFiles(Path.Combine(root, "achievements-pending-v1"), "*.json").Single(); File.WriteAllText(data, "{}");
            using (var lease = store.Open(Owner)) {
                try { lease.Save(evidence, () => true); throw new Exception("Damaged data overwritten"); } catch (System.Text.Json.JsonException) { } catch (InvalidDataException) { }
                Require(File.ReadAllText(data) == "{}", "Storage corruption remains explicit and original bytes survive");
            }
        } finally { Directory.Delete(root, true); }
        return Task.CompletedTask;
    }
}
