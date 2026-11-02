using System.Text.Json;
using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Privacy;
using StarBridge.HostRuntime.Presence;
using StarBridge.NativeBridge;

internal static class PrivacyLaneRecoveryTests
{
    private static readonly BridgeAccountContext Owner = new("test", "fixture.invalid", "synthetic-owner");
    private static PrivacyPublicationInput Input => new(Owner, 1, "Fixture", true, "LIVE", GameLogSessionSnapshot.Empty, AppPresenceConfirmed: true);
    private static LocalPrivacySettings Settings => new(true, new(0, false, false, []),
        new(CommunityRealtimeScope.SupportedFields, true),
        [new("SYNTHETIC", DateTimeOffset.UtcNow.AddDays(-1), CommunityRealtimeScope.SupportedFields, false, true, [], null)],
        OfficialFleet: new(new("fixture", 1, "SYNTHETIC", "scm-observed-membership-row-v1:1"), CommunityRealtimeScope.SupportedFields, "initial", Guid.NewGuid().ToString("N")));
    internal static async Task Isolation()
    {
        var root = Directory.CreateTempSubdirectory("sb-lane-fixture-").FullName;
        var store = new LocalPrivacyStore(root);
        var settings = Settings;
        store.Save(Owner, 0, Guid.NewGuid().ToString("N"), settings, () => true);
        var bodies = new List<JsonElement>();
        using var publisher = new PrivacyPublicationPair(store, () => Input, (_, data, _) => { bodies.Add(data.Clone()); return Task.CompletedTask; }, startTimer: false);
        await publisher.ApplyAsync(Owner, 1, 1, default);
        Check(bodies.Count == 2, "Each saved audience must have its own publication lane");
        Check(bodies.Count(p => p.TryGetProperty("officialFleet", out _)) == 1, "Only one official payload");
        var official = bodies.Single(p => p.TryGetProperty("officialFleet", out _));
        Check(!PrivacyPublicationPayload.HasOriginalPositiveAudience(official), "Official payload must not carry community or room audiences");
        bodies.Clear();
        store.Save(Owner, 1, Guid.NewGuid().ToString("N"), settings with { OfficialFleet = null }, () => true);
        await publisher.ApplyAsync(Owner, 1, 2, default);
        Check(bodies.Any(p => p.TryGetProperty("officialFleet", out _) && !p.GetProperty("online").GetBoolean()),
            "Removing official choice must withdraw its prior publication");
        Check(bodies.Any(p => !p.TryGetProperty("officialFleet", out _) && p.GetProperty("online").GetBoolean()),
            "Removing official choice preserves ordinary publication");
        Console.WriteLine("PASS publication lane isolation and removed choice withdrawal");
    }
    internal static async Task OwnerRecovery()
    {
        var root = Directory.CreateTempSubdirectory("sb-owner-fixture-").FullName;
        var store = new LocalPrivacyStore(root);
        var settings = Settings with { OfficialFleet = null };
        store.Save(Owner, 0, Guid.NewGuid().ToString("N"), settings, () => true);
        bool available = true, failOnce = true;
        store.ResolveOwner = o => available ? o : throw new LocalPrivacyOwnerUnavailableException();
        using var publisher = new PrivacyPublicationPair(store, () => Input, (_, data, _) => {
            if (data.GetProperty("online").GetBoolean() && failOnce) {
                failOnce = false; available = false; throw new LocalPrivacyOwnerUnavailableException();
            }
            return Task.CompletedTask;
        }, startTimer: false);
        try { await publisher.ApplyAsync(Owner, 1, 1, default); } catch (LocalPrivacyOwnerUnavailableException) { }; available = true;
        await publisher.TickAsync(); await publisher.TickAsync();
        Check(publisher.Status.State == "applied", "Owner recovery must restore saved consent without manual apply: " + publisher.Status.State);
        Check(store.Read(Owner).Revision == 1, "Recovery never saves over existing choices");
        Console.WriteLine("PASS owner recovery");
    }
    internal static async Task FailureAndPrivacy()
    {
        foreach (var failedOfficial in new[] { true, false }) {
            var root = Directory.CreateTempSubdirectory("sb-isolation-fixture-").FullName;
            var store = new LocalPrivacyStore(root);
            store.Save(Owner, 0, Guid.NewGuid().ToString("N"), Settings, () => true);
            var positive = new int[2]; var clears = new int[2]; bool fail = true;
            var visibility = PlayerPresenceVisibilityMode.Online;
            using var publisher = new PrivacyPublicationPair(store, () => Input, (_, data, _) => {
                var official = data.TryGetProperty("officialFleet", out _); var lane = official ? 1 : 0;
                if (data.GetProperty("online").GetBoolean()) {
                    positive[lane]++;
                    if (fail && official == failedOfficial) throw new AccountBridgeHostException("privacy_publication.forbidden", httpStatus: System.Net.HttpStatusCode.Forbidden);
                } else clears[lane]++;
                return Task.CompletedTask;
            }, startTimer: false, visibility: () => visibility);
            await publisher.ApplyAsync(Owner, 1, 1, default);
            var healthy = failedOfficial ? 0 : 1; var broken = 1 - healthy;
            Check(positive[healthy] == 1 && positive[broken] == 1, "Both lanes get a chance despite rejection");
            Check(clears[healthy] == 0 && clears[broken] == 1, "Compensating clear affects only failed lane");
            Check(publisher.Status.ErrorCode == "privacy_publication.forbidden", "403 is permissions, never local corruption");
            await publisher.TickAsync();
            Check(positive[healthy] == 2 && positive[broken] == 1, "Healthy heartbeat continues while rejected lane backs off");
            visibility = PlayerPresenceVisibilityMode.Invisible;
            await publisher.TickAsync();
            Check(clears[healthy] > 0 && clears[broken] > 1, "Invisible drains both independent lanes");
            var count = positive.Sum(); fail = false;
            await publisher.TickAsync();
            Check(positive.Sum() == count, "No positive send while invisible");
            Check(store.IsPublicationPaused(Owner), "Invisible is durable, never auto-resumed on recovery");
        }
        foreach (var kind in new[] { "owner-before", "sharing-lock", "corrupt", "revoked" }) {
            var root = Directory.CreateTempSubdirectory("sb-policy-fixture-").FullName;
            var store = new LocalPrivacyStore(root); bool available = true; var positives = 0;
            store.Save(Owner, 0, Guid.NewGuid().ToString("N"), Settings, () => true);
            using var publisher = new PrivacyPublicationPair(store, () => Input, (_, data, _) => {
                if (data.GetProperty("online").GetBoolean()) positives++; return Task.CompletedTask;
            }, startTimer: false);
            await publisher.ApplyAsync(Owner, 1, 1, default);
            var path = Directory.GetFiles(Path.Combine(root, "privacy-local-v1"), "*.json").Single();
            var original = File.ReadAllBytes(path);
            store.ResolveOwner = o => available ? o : throw new LocalPrivacyOwnerUnavailableException();
            if (kind == "owner-before" || kind == "revoked") available = false;
            if (kind == "corrupt") File.WriteAllText(path, "{broken}");
            using (var locked = kind == "sharing-lock" ? new FileStream(path, FileMode.Open, FileAccess.ReadWrite, FileShare.None) : null)
                await publisher.TickAsync();
            available = true;
            var before = positives;
            if (kind == "revoked") await publisher.StopAsync(default, explicitRequest: true);
            await publisher.TickAsync(); await publisher.TickAsync();
            if (kind is "corrupt" or "revoked") Check(positives == before, "Corruption or revoke never auto-publishes");
            else { Check(positives > before && publisher.Status.ErrorCode is null, "Temporary local read recovers without apply");
                Check(original.SequenceEqual(File.ReadAllBytes(path)), "Recovery is read-only for saved policy"); }
            if (kind == "corrupt") Check(File.ReadAllText(path) == "{broken}", "Damaged file is untouched");
        }
        Console.WriteLine("PASS independent failure, invisible, locked file, corrupted file and revoke boundaries");
    }
    internal static async Task ExplicitResume()
    {
        var root = Directory.CreateTempSubdirectory("sb-resume-fixture-").FullName;
        var store = new LocalPrivacyStore(root); store.Save(Owner, 0, Guid.NewGuid().ToString("N"), Settings, () => true);
        var mode = PlayerPresenceVisibilityMode.Online; var sends = 0; var consume = false;
        PrivacyPublicationPair? pair = null;
        using var publisher = pair = new PrivacyPublicationPair(store, () => Input, (i, body, _) => {
            if (body.GetProperty("online").GetBoolean()) {
                pair!.RequireNoObservedPause(i);
                Check(pair.IsPositivePublicationAllowed(Owner, 1), "Shared admission denies stale pause"); sends++;
            }
            return Task.CompletedTask;
        }, startTimer: false, visibility: () => mode, consumeExplicitOnlineResume: (_, _) => { var once = consume; consume = false; return once; });
        await publisher.ApplyAsync(Owner, 1, 1, default);
        mode = PlayerPresenceVisibilityMode.Invisible;
        publisher.ObserveVisibility(new(Owner, 1, "fixture", 3, mode, null));
        await publisher.TickAsync();
        Check(sends == 2, "Invisible emits no positive updates");
        var resumed = await publisher.ChangeVisibilityAsync(Owner, 1, _ => { mode = PlayerPresenceVisibilityMode.Online; consume = true; return Task.CompletedTask; }, default);
        Check(resumed && publisher.OrdinaryStatus.State == "applied" && publisher.OfficialStatus.State == "applied", "One explicit resume must resume both lanes without a false failure");
        Check(sends == 4 && !store.IsPublicationPaused(Owner), "Exactly one fresh positive per lane after explicit resume");
        Console.WriteLine("PASS shared explicit visibility resume");
    }
    private static void Check(bool condition, string message) { if (!condition) throw new Exception(message); }
}







