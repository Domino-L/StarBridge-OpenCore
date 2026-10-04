using System.Text.Json;
using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Privacy;
using StarBridge.HostRuntime.Presence;
using StarBridge.NativeBridge;
using StarBridge.HostRuntime.Account;

internal static class PrivacyPublicationRecoveryTests
{
    public static async Task AutomaticTimerRecovery()
    {
        var root = Directory.CreateTempSubdirectory("starbridge-auto-sharing-").FullName;
        try
        {
            var owner = new BridgeAccountContext("test", "presence.invalid", "timer-fixture");
            var input = new PrivacyPublicationInput(owner, 1, "Fixture", true, null, GameLogSessionSnapshot.Empty);
            var store = new LocalPrivacyStore(root);
            var saved = store.Save(owner, 0, Guid.NewGuid().ToString("N"), new(true,
                new(PlayerSharedStateFields.Presence, false, true, []), new(PlayerSharedStateFields.None, false)), () => true);
            store.SetPublicationConsent(owner, saved.Revision, true, () => true);
            var recovered = new TaskCompletionSource<JsonElement>(TaskCreationOptions.RunContinuationsAsynchronously);
            var attempts = 0;
            using var publication = new PrivacyPublication(store, () => input, (_, payload, _) => {
                if (!payload.GetProperty("online").GetBoolean()) return Task.CompletedTask;
                if (Interlocked.Increment(ref attempts) == 1) throw new HttpRequestException();
                recovered.TrySetResult(payload.Clone());
                return Task.CompletedTask;
            });
            // No ApplyAsync, TickAsync, page refresh or UI action: exercise the production timer.
            var result = await recovered.Task.WaitAsync(TimeSpan.FromSeconds(20));
            if (attempts != 2 || result.GetProperty("roomSharedStateFields").GetInt32() != 0 ||
                result.TryGetProperty("ownedShips", out _) || store.Read(owner) != saved || !store.HasPublicationConsent(owner))
                throw new Exception("Automatic recovery must reuse only remembered consent and unchanged saved scopes.");
            Console.WriteLine("PASS production timer resumes remembered sharing after transport failure without a user retry");
        }
        finally { Directory.Delete(root, true); }
    }

    public static async Task SilentHeartbeat()
    {
        await BusyPublicationRetainsLatestWake();
        await BusyPublicationHonorsQueuedStop();
        await TransientHeartbeatMustNotPublishExit();
        var root = Directory.CreateTempSubdirectory("starbridge-presence-heartbeat-").FullName;
        try
        {
            var owner = new BridgeAccountContext("test", "presence.invalid", "heartbeat");
            var input = new PrivacyPublicationInput(owner, 1, "Fixture", true, null, GameLogSessionSnapshot.Empty);
            var store = new LocalPrivacyStore(root);
            store.Save(owner, 0, Guid.NewGuid().ToString("N"), new(true,
                new(PlayerSharedStateFields.Presence, false, true, []),
                new(PlayerSharedStateFields.None, false)), () => true);
            TaskCompletionSource? pending = null;
            using var publication = new PrivacyPublication(store, () => input,
                (_, _, token) => pending?.Task.WaitAsync(token) ?? Task.CompletedTask, startTimer: false);
            await publication.ApplyAsync(owner, 1, 1, default);
            var confirmed = publication.Status;
            pending = new(TaskCreationOptions.RunContinuationsAsynchronously);
            var heartbeat = publication.TickAsync();
            try
            {
                if (publication.Status != confirmed)
                    throw new Exception($"Healthy heartbeat must retain acknowledged status while sending; observed {publication.Status.State}.");
            }
            finally { pending.SetResult(); await heartbeat; }
            if (publication.Status.State != "applied") throw new Exception("Heartbeat must remain applied.");

            pending = new(TaskCreationOptions.RunContinuationsAsynchronously);
            var explicitApply = publication.ApplyAsync(owner, 1, 1, default);
            try
            {
                if (publication.Status.State != "publishing")
                    throw new Exception("Explicit reapply must still expose progress.");
            }
            finally { pending.SetResult(); await explicitApply; }

            var previous = store.Read(owner);
            store.Save(owner, 1, Guid.NewGuid().ToString("N"), previous.Settings!, () => true);
            pending = new(TaskCreationOptions.RunContinuationsAsynchronously);
            var changedPolicy = publication.TickAsync();
            try
            {
                if (publication.Status.State != "publishing")
                    throw new Exception("A new policy revision must not reuse an old success receipt.");
            }
            finally { pending.SetResult(); await changedPolicy; }

            pending = new(TaskCreationOptions.RunContinuationsAsynchronously);
            var failedHeartbeat = publication.TickAsync();
            pending.SetException(new HttpRequestException());
            await failedHeartbeat;
            if (publication.Status.State != "reconnecting" || publication.Status.ErrorCode is null)
                throw new Exception("Real heartbeat failures must remain observable.");
        }
        finally { Directory.Delete(root, true); }
    }

    private static async Task BusyPublicationRetainsLatestWake()
    {
        foreach (var duringApply in new[] { false, true })
        {
            var root = Directory.CreateTempSubdirectory("starbridge-sharing-wake-").FullName;
            try
            {
                var owner = new BridgeAccountContext("test", "presence.invalid", "wake");
                var input = new PrivacyPublicationInput(owner, 1, "Fixture", true, "LIVE", GameLogSessionSnapshot.Empty);
                var store = new LocalPrivacyStore(root);
                store.Save(owner, 0, Guid.NewGuid().ToString("N"), new(true,
                    new(PlayerSharedStateFields.Presence, false, true, []),
                    new(PlayerSharedStateFields.None, false)), () => true);
                TaskCompletionSource? release = null;
                var sent = new List<string?>();
                var latest = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
                using var publication = new PrivacyPublication(store, () => input, async (_, payload, token) => {
                    var version = payload.GetProperty("gameVersion").GetString();
                    sent.Add(version);
                    if (version == "EPTU") latest.TrySetResult();
                    if (release is { } pending) await pending.Task.WaitAsync(token);
                }, startTimer: false);
                await publication.ApplyAsync(owner, 1, 1, default);
                release = new(TaskCreationOptions.RunContinuationsAsynchronously);
                var busy = duringApply ? publication.ApplyAsync(owner, 1, 1, default) : publication.TickAsync();
                input = input with { GameVersion = "EPTU" };
                // Real input-change callers must not need another timer/user action.
                for (var i = 0; i < 20; i++) await publication.TickAsync();
                release.SetResult();
                await busy;
                await latest.Task.WaitAsync(TimeSpan.FromSeconds(2));
                if (sent.Count != 3 || sent[^1] != "EPTU")
                    throw new Exception("Busy publication must coalesce all input wakes into one fresh trailing snapshot.");
            }
            finally { Directory.Delete(root, true); }
        }
    }

    private static async Task BusyPublicationHonorsQueuedStop()
    {
        var root = Directory.CreateTempSubdirectory("starbridge-sharing-wake-stop-").FullName;
        try
        {
            var owner = new BridgeAccountContext("test", "presence.invalid", "wake-stop");
            var input = new PrivacyPublicationInput(owner, 1, "Fixture", true, "LIVE", GameLogSessionSnapshot.Empty);
            var store = new LocalPrivacyStore(root);
            store.Save(owner, 0, Guid.NewGuid().ToString("N"), new(true,
                new(PlayerSharedStateFields.Presence, false, true, []),
                new(PlayerSharedStateFields.None, false)), () => true);
            TaskCompletionSource? release = null;
            var stopped = false;
            var resurrected = false;
            using var publication = new PrivacyPublication(store, () => input, async (_, payload, token) => {
                var online = payload.GetProperty("online").GetBoolean();
                if (!online) stopped = true;
                else if (stopped) resurrected = true;
                if (release is { } pending) await pending.Task.WaitAsync(token);
            }, startTimer: false);
            await publication.ApplyAsync(owner, 1, 1, default);
            release = new(TaskCreationOptions.RunContinuationsAsynchronously);
            var busy = publication.TickAsync();
            var stop = publication.StopAsync(default, explicitRequest: true);
            input = input with { GameVersion = "EPTU" };
            await publication.TickAsync();
            release.SetResult();
            await Task.WhenAll(busy, stop);
            await publication.TickAsync();
            if (!stopped || resurrected || store.HasPublicationConsent(owner) || publication.Status.State != "withdrawn")
                throw new Exception("A coalesced input wake must never resurrect sharing after an explicit stop.");
        }
        finally { Directory.Delete(root, true); }
    }

    private static async Task TransientHeartbeatMustNotPublishExit()
    {
        var root = Directory.CreateTempSubdirectory("starbridge-heartbeat-no-exit-").FullName;
        try {
            var owner = new BridgeAccountContext("test", "presence.invalid", "stable-game");
            var input = new PrivacyPublicationInput(owner, 1, "Fixture", true, "LIVE", GameLogSessionSnapshot.Empty);
            var store = new LocalPrivacyStore(root);
            store.Save(owner, 0, Guid.NewGuid().ToString("N"), new(true,
                new(PlayerSharedStateFields.Presence, false, true, []),
                new(PlayerSharedStateFields.None, false)), () => true);
            var accepted = new List<JsonElement>();
            var failNext = false;
            var clock = new SharingTestClock();
            using var publication = new PrivacyPublication(store, () => input, (_, payload, _) => {
                if (failNext) { failNext = false; throw new HttpRequestException(); }
                accepted.Add(payload.Clone()); return Task.CompletedTask;
            }, startTimer: false, timeProvider: clock);
            await publication.ApplyAsync(owner, 1, 1, default);
            var acknowledgedAt = publication.Status.AppliedAt;
            for (var attempt = 0; attempt < 3; attempt++) {
                clock.Advance(60);
                failNext = true;
                await publication.TickAsync();
                if (publication.Status.State != "reconnecting" || publication.Status.AppliedAt != acknowledgedAt)
                    throw new Exception("Failed heartbeats must report reconnecting without fabricating a fresh receipt.");
            }
            input = input with { GameVersion = "EPTU" };
            clock.Advance(60);
            await publication.TickAsync();
            if (accepted.Any(p => !p.GetProperty("online").GetBoolean() || p.GetProperty("liveStatus").GetString() != "InGame"))
                throw new Exception("A transient unchanged heartbeat published Offline between two InGame samples despite uninterrupted local gameplay.");
            if (publication.Status.State != "applied") throw new Exception("Heartbeat must resume without a new apply.");
            if (accepted[^1].GetProperty("gameVersion").GetString() != "EPTU")
                throw new Exception("Retry must rebuild current game evidence, not replay a cached heartbeat.");
        }
        finally { Directory.Delete(root, true); }
    }

    public static async Task RevokedConsentRestart()
    {
        foreach (var cause in new[] { "explicit-stop", "forbidden", "response_invalid" })
        {
            var root = Directory.CreateTempSubdirectory("starbridge-presence-revoked-restart-").FullName;
            try
            {
                var owner = new BridgeAccountContext("test", "presence.invalid", "revoked-restart");
                var input = new PrivacyPublicationInput(owner, 1, "Fixture", true, null, GameLogSessionSnapshot.Empty);
                var store = new LocalPrivacyStore(root);
                store.Save(owner, 0, Guid.NewGuid().ToString("N"), new(true,
                    new(PlayerSharedStateFields.Presence, false, true, []),
                    new(PlayerSharedStateFields.None, false)), () => true);
                var reject = false;
                var positiveSends = 0;
                Task Send(PrivacyPublicationInput _, JsonElement payload, CancellationToken token)
                {
                    if (payload.GetProperty("online").GetBoolean())
                    {
                        if (reject) throw new AccountBridgeHostException("privacy_publication." + cause);
                        positiveSends++;
                    }
                    return Task.CompletedTask;
                }
                using (var first = new PrivacyPublication(store, () => input, Send, startTimer: false))
                {
                    await first.ApplyAsync(owner, 1, 1, default);
                    if (cause == "explicit-stop") await first.StopAsync(default, explicitRequest: true);
                    else { reject = true; await first.TickAsync(); }
                }
                reject = false;
                input = input with { Generation = 2 };
                var before = positiveSends;
                using var restarted = new PrivacyPublication(new LocalPrivacyStore(root), () => input, Send, startTimer: false);
                await restarted.TickAsync();
                await restarted.TickAsync();
                if (positiveSends != before || store.HasPublicationConsent(owner))
                    throw new Exception("Restart must not bypass revoked consent or an authority rejection.");
                if (store.Read(owner).Settings?.PublicationEnabled != true)
                    throw new Exception("Publication failure must preserve the user's saved policy choice.");
                Console.WriteLine($"REPLAY {cause}: savedEnabled=true; consent=false; restartState={restarted.Status.State}; newOnlineSends={positiveSends - before}");
                var savedBefore = JsonSerializer.Serialize(store.Read(owner), LocalPrivacyStore.Json);
                await restarted.ApplyAsync(owner, 2, 1, default);
                if (restarted.Status.State != "applied" || positiveSends != before + 1 ||
                    !store.HasPublicationConsent(owner) ||
                    JsonSerializer.Serialize(store.Read(owner), LocalPrivacyStore.Json) != savedBefore)
                    throw new Exception("Explicit reapply must restore only the same saved scope and revision.");
                await restarted.StopAsync(default);
                input = input with { Generation = 3 };
                using var nextRestart = new PrivacyPublication(new LocalPrivacyStore(root), () => input, Send, startTimer: false);
                await nextRestart.TickAsync();
                if (nextRestart.Status.State != "applied" || positiveSends != before + 2)
                    throw new Exception("Confirmed reapply must resume after the next restart.");
            }
            finally { Directory.Delete(root, true); }
        }
    }

    public static async Task Restart()
    {
        var root = Directory.CreateTempSubdirectory("starbridge-presence-restart-").FullName;
        try
        {
            var owner = new BridgeAccountContext("test", "presence.invalid", "remembered");
            var input = new PrivacyPublicationInput(owner, 1, "Fixture", true, null, GameLogSessionSnapshot.Empty);
            var store = new LocalPrivacyStore(root);
            var settings = new LocalPrivacySettings(true, new(PlayerSharedStateFields.Presence, false, true, []),
                new(PlayerSharedStateFields.None, false));
            store.Save(owner, 0, Guid.NewGuid().ToString("N"), settings, () => true);
            var sent = new List<JsonElement>();
            Task Send(PrivacyPublicationInput _, JsonElement payload, CancellationToken token)
            { sent.Add(payload.Clone()); return Task.CompletedTask; }
            using (var first = new PrivacyPublication(store, () => input, Send, startTimer: false))
            {
                await first.TickAsync();
                if (sent.Count != 0) throw new Exception("A saved choice alone is not first consent.");
                await first.ApplyAsync(owner, 1, 1, default);
                await first.StopAsync(default); // Normal process shutdown, not revoke.
            }
            input = input with { Generation = 2 };
            using var restarted = new PrivacyPublication(new LocalPrivacyStore(root), () => input, Send, startTimer: false);
            await restarted.TickAsync();
            if (restarted.Status.State != "applied" || !sent[^1].GetProperty("online").GetBoolean())
                throw new Exception("Once-confirmed account must resume presence after restart without another apply.");
        }
        finally { Directory.Delete(root, true); }
    }

    public static async Task TransientDisconnect()
    {
        var root = Directory.CreateTempSubdirectory("starbridge-presence-recovery-").FullName;
        try
        {
            var owner = new BridgeAccountContext("test", "presence.invalid", "recovery");
            var input = new PrivacyPublicationInput(owner, 1, "Fixture", true, null, GameLogSessionSnapshot.Empty);
            var store = new LocalPrivacyStore(root);
            store.Save(owner, 0, Guid.NewGuid().ToString("N"), new(true,
                new(PlayerSharedStateFields.Presence, false, true, []),
                new(PlayerSharedStateFields.None, false)), () => true);
            var sent = new List<JsonElement>();
            var disconnected = false;
            var clock = new SharingTestClock();
            using var publication = new PrivacyPublication(store, () => input, (_, payload, _) =>
            {
                if (disconnected) return Task.FromException(new HttpRequestException());
                sent.Add(payload.Clone());
                return Task.CompletedTask;
            }, startTimer: false, timeProvider: clock);
            await publication.ApplyAsync(owner, 1, 1, default);
            if (publication.Status.State != "applied") throw new Exception("Fixture must publish before disconnect.");
            disconnected = true;
            await publication.TickAsync();
            if (publication.Status.State != "reconnecting") throw new Exception("Outage must report automatic recovery.");
            disconnected = false;
            clock.Advance(5);
            // A compensating withdrawal may precede resumption. No new apply,
            // changed settings, UI refresh or account authentication is supplied.
            await publication.TickAsync();
            await publication.TickAsync();
            if (publication.Status.State != "applied" || !sent[^1].GetProperty("online").GetBoolean())
                throw new Exception("Confirmed online presence must recover after a transient disconnect without manual apply.");
        }
        finally { Directory.Delete(root, true); }
    }

    public static async Task Guards()
    {
        foreach (var scenario in new[] { "stop", "account", "disabled", "identity", "invisible", "forbidden", "invalid", "timeout", "service" })
        {
            var root = Directory.CreateTempSubdirectory("starbridge-presence-guard-").FullName;
            try
            {
                var owner = new BridgeAccountContext("test", "presence.invalid", "guard");
                var input = new PrivacyPublicationInput(owner, 1, "Fixture", true, null, GameLogSessionSnapshot.Empty);
                var store = new LocalPrivacyStore(root);
                var settings = new LocalPrivacySettings(true,
                    new(PlayerSharedStateFields.Presence, false, true, []), new(PlayerSharedStateFields.None, false));
                store.Save(owner, 0, Guid.NewGuid().ToString("N"), settings, () => true);
                var sent = new List<JsonElement>();
                Exception? failure = null;
                var visibility = PlayerPresenceVisibilityMode.Online;
                var clock = new SharingTestClock();
                using var publication = new PrivacyPublication(store, () => input, (_, payload, _) =>
                {
                    if (failure is not null) return Task.FromException(failure);
                    sent.Add(payload.Clone());
                    return Task.CompletedTask;
                }, startTimer: false, visibility: () => visibility, timeProvider: clock);
                await publication.ApplyAsync(owner, 1, 1, default);
                failure = scenario switch {
                    "forbidden" => new AccountBridgeHostException("privacy_publication.forbidden"),
                    "invalid" => new AccountBridgeHostException("privacy_publication.response_invalid"),
                    "service" => new AccountBridgeHostException("privacy_publication.temporarily_unavailable"),
                    "timeout" => new TaskCanceledException(),
                    _ => new HttpRequestException()
                };
                await publication.TickAsync();
                failure = null;
                var start = sent.Count;
                switch (scenario)
                {
                    case "stop": await publication.StopAsync(default, explicitRequest: true); break;
                    case "account": input = input with { Owner = owner with { Subject = "other" }, Generation = 2 }; publication.Invalidate(); break;
                    case "disabled": store.Save(owner, 1, Guid.NewGuid().ToString("N"), settings with { PublicationEnabled = false }, () => true); break;
                    case "identity": input = input with { IdentityConfirmed = false }; break;
                    case "invisible":
                        await publication.ChangeVisibilityAsync(owner, 1, _ => { visibility = PlayerPresenceVisibilityMode.Invisible; return Task.CompletedTask; }, default);
                        break;
                }
                await publication.TickAsync();
                await publication.TickAsync();
                if (scenario is "timeout" or "service") {
                    clock.Advance(5);
                    await publication.TickAsync();
                }
                var online = sent.Skip(start).Any(p => p.GetProperty("online").GetBoolean());
                if (online != (scenario is "timeout" or "service"))
                    throw new Exception("Recovery must respect " + scenario);
                if (sent.Any(p => p.TryGetProperty("ownedShips", out _) || p.GetProperty("roomSharedStateFields").GetInt32() != 0))
                    throw new Exception("Recovery cannot broaden fields or touch inventory.");
                Console.WriteLine("PASS Recovery guard " + scenario);
            }
            finally { Directory.Delete(root, true); }
        }
    }
}
