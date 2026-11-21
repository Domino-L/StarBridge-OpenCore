using System.Text.Json;
using StarBridge.Core.Profiles;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Presence;
using StarBridge.HostRuntime.Privacy;
using StarBridge.NativeBridge;

internal static class GameplayTransient073Tests
{
    private static readonly BridgeAccountContext Authentication = new("test", "scm", "synthetic-transient");
    private static readonly BridgeAccountContext Storage = new("test", "local", "synthetic-storage");
    private const long SeedSeconds = 623 * 3600;
    private sealed class Clock : TimeProvider
    {
        internal DateTimeOffset Now = DateTimeOffset.UnixEpoch;
        public override DateTimeOffset GetUtcNow() => Now;
    }
    private sealed class Remote : IGameplayHistoryRemote, IGameplayAccountTotalRemote
    {
        internal bool Fails;
        public Task<GameplayAccountTotal> ReadAccountTotalAsync(BridgeAccountContext owner, CancellationToken token) =>
            Fails ? throw new IOException("synthetic outage") : Task.FromResult(new GameplayAccountTotal("available", 900 * 3600));
        public Task<GameplayTimeResetState> ReadAsync(BridgeAccountContext owner, CancellationToken token) =>
            throw new InvalidOperationException("This test permits only the synthetic total read.");
        public Task<GameplayTimeResetResult> ResetAsync(BridgeAccountContext owner, GameplayTimeResetRequest request,
            CancellationToken token) => throw new InvalidOperationException("No reset during an outage.");
        public Task<bool> PublishGameplayStatisticsAsync(BridgeAccountContext owner,
            PersonalProfileGameplayStatisticsUpdateRequestContract update, CancellationToken token) =>
            throw new InvalidOperationException("No publication during an outage.");
    }
    private sealed class Harness : IDisposable
    {
        internal readonly string Root = Path.Combine(Path.GetTempPath(), "sb-transient-073-" + Guid.NewGuid().ToString("N"));
        internal readonly Clock Time = new();
        internal readonly Remote Remote = new();
        internal BridgeAccountContext? Auth = Authentication;
        internal BridgeAccountContext Owner = Storage;
        internal long Generation = 1;
        internal long Rejections;
        internal int OwnerResolutions, FailOwnerResolution;
        internal bool Available = true, NullGameplayOwner, Transition, Alias;
        internal string Identity = "match";
        internal GameplayTimeRuntime Runtime;
        internal readonly string OriginalFile;
        internal Harness()
        {
            var seed = new GameplayTimeStore(Root);
            using (var lease = seed.Open(Storage)) lease.Save(lease.Read(), GameplayRecordingConsent.Allowed, SeedSeconds, () => true);
            OriginalFile = Directory.GetFiles(Path.Combine(Root, "gameplay-time-local-v1"), "*.json").Single();
            // The unrelated authentication-named file is the historical zero-file trap.
            using (var lease = seed.Open(Authentication)) lease.Save(lease.Read(), GameplayRecordingConsent.Allowed, 0, () => true);
            var store = new GameplayTimeStore(Root) {
                ResolveOwner = auth => {
                    OwnerResolutions++;
                    if (OwnerResolutions == FailOwnerResolution)
                        throw new LocalPrivacyOwnerUnavailableException();
                    return Transition ? ScmAccountBridgeHost.ResolveTransitionOwner(auth, !Alias, Alias)
                        : Available ? Owner : throw new LocalPrivacyOwnerUnavailableException();
                }
            };
            Runtime = new(store, () => (NullGameplayOwner ? null : Auth, Generation),
                () => new(1, "running"), Time, startTimer: false,
                recordingAllowed: () => Available && Identity == "match", historyRemote: Remote,
                continuity: () => new(Auth, Generation, Available && !Transition, Identity,
                    Available && !Transition ? Time.Now : null, Rejections));
            Runtime.Sample();
            Advance(5);
        }
        internal void Advance(int seconds)
        {
            for (var elapsed = 0; elapsed < seconds; elapsed += 5)
            { Time.Now = Time.Now.AddSeconds(5); Runtime.Sample(); }
        }
        internal JsonElement Read(string command = "read", object? payload = null)
        {
            var response = Runtime.Dispatch(BridgeEnvelope.Request("gameplayTime." + command,
                Guid.NewGuid().ToString("N"), Generation, payload ?? new { schemaVersion = 1 }, Auth)).Response;
            Require(response.Status == "ok", "A scoped saved projection must remain readable.");
            return response.Payload;
        }
        internal long DiskSeconds()
        {
            using var document = JsonDocument.Parse(File.ReadAllBytes(OriginalFile));
            return document.RootElement.GetProperty("snapshot").GetProperty("seconds").GetInt64();
        }
        public void Dispose()
        {
            Runtime.Dispose();
            Directory.Delete(Root, true); // Only the unique synthetic directory created above.
        }
    }

    private sealed class ResetSpy : IGameplayTimeResetRemote
    {
        internal int Writes;
        public Task<GameplayTimeResetState> ReadAsync(BridgeAccountContext owner, CancellationToken token) =>
            Task.FromResult(new GameplayTimeResetState(1, 4, null, null, SeedSeconds, 0, null));
        public Task<GameplayTimeResetResult> ResetAsync(BridgeAccountContext owner, GameplayTimeResetRequest request,
            CancellationToken token)
        {
            Writes++;
            throw new InvalidOperationException("An old ticket must never submit a reset.");
        }
    }

    internal static async Task Run()
    {
        SameOwnerCommits();
        ChangedLoginDiscards(false);
        ChangedLoginDiscards(true);
        ExplicitIdentityDiscards();
        DifferentStorageDiscards();
        DeadlineRetainsOnlyThirtyMinutes();
        RecoveryCrossingDeadlineIsClamped();
        UnconfirmedLoadRetries(false);
        UnconfirmedLoadRetries(true);
        TransitionNeverOpensZeroFile(false);
        TransitionNeverOpensZeroFile(true);
        Require(ScmAccountBridgeHost.ResolveTransitionOwner(Authentication, false, false) == Authentication,
            "A genuinely never-bound unlinked account keeps its existing owner.");
        await ProjectionRetainsTotals();
        await RetirementNeverCommits();
        NullGameplayOwnerRetainsSameLogin();
        UnobservedRecoveryCommits();
        RecoveredMismatchStillDiscards();
        GameLogMatchIsRetainedAndMismatchWins();
        GameLogConflictCannotBeReconciled();
    }

    private static void SameOwnerCommits()
    {
        using var h = new Harness();
        var before = File.ReadAllBytes(h.OriginalFile);
        h.Available = false;
        h.Advance(300);
        Require(File.ReadAllBytes(h.OriginalFile).SequenceEqual(before), "Five outage minutes are memory-only.");
        Require(h.Read().GetProperty("seconds").GetInt64() == SeedSeconds + 305, "Read includes retained plus pending seconds.");
        h.Available = true;
        h.Advance(5);
        Require(h.DiskSeconds() == SeedSeconds + 310, "Same-owner recovery saves the complete observed running interval.");
        h.Available = false; h.Advance(60); h.Available = true; h.Advance(5);
        Require(h.DiskSeconds() == SeedSeconds + 375, "A later outage never duplicates the first committed interval.");
    }

    private static void ChangedLoginDiscards(bool generationOnly)
    {
        using var h = new Harness();
        h.Available = false; h.Advance(300);
        if (generationOnly) h.Generation++;
        else { h.Auth = Authentication with { Subject = "synthetic-other" }; h.Owner = h.Auth; }
        h.Runtime.Sample();
        Require(h.DiskSeconds() == SeedSeconds + 5, "A changed authentication fence discards pending time.");
        h.Available = true;
        h.Runtime.Sample(); h.Read();
        Require(h.Read().GetProperty("seconds").GetInt64() == (generationOnly ? SeedSeconds + 5 : 0),
            "Neither the original nor the new account inherits the unconfirmed interval.");
    }

    private static void ExplicitIdentityDiscards()
    {
        using var h = new Harness();
        h.Available = false; h.Advance(300);
        h.Identity = "identity"; // Mismatch, unverified Handle, or non-match account policy.
        h.Runtime.Sample();
        var refused = h.Read();
        Require(refused.GetProperty("pauseReason").GetString() == "identity", "A real identity refusal takes precedence.");
        Require(!refused.GetProperty("recording").GetBoolean() &&
            refused.GetProperty("error").GetString() == "gameplay.account_changed",
            "Identity refusal keeps the stopped-recording protocol.");
        Require(h.Read().GetProperty("seconds").GetInt64() == SeedSeconds + 5, "Mismatch immediately drops pending time.");
        h.Available = true; h.Identity = "match"; h.Runtime.Sample();
        Require(h.DiskSeconds() == SeedSeconds + 5, "Recovery cannot resurrect discarded seconds.");
    }

    private static void DifferentStorageDiscards()
    {
        using var h = new Harness();
        h.Available = false; h.Advance(300);
        h.Owner = Authentication; h.Available = true;
        h.Runtime.Sample(); h.Runtime.Sample();
        Require(h.DiskSeconds() == SeedSeconds + 5, "A confirmed different storage owner leaves the original untouched.");
        Require(h.Read().GetProperty("seconds").GetInt64() == 0, "The other file receives none of the pending interval.");
    }

    private static void DeadlineRetainsOnlyThirtyMinutes()
    {
        using var h = new Harness();
        h.Available = false; h.Advance(2100);
        var view = h.Read();
        Require(view.GetProperty("pauseReason").GetString() == "connectionPaused", "The deadline pauses recording.");
        Require(!view.GetProperty("recording").GetBoolean(), "Paused projection cannot report active recording.");
        Require(view.GetProperty("error").GetString() == "gameplay.account_changed",
            "Connection-paused retains the existing stopped-recording error.");
        Require(view.GetProperty("seconds").GetInt64() == SeedSeconds + 1805, "Only thirty minutes since confirmation accrue.");
        h.Read(); h.Advance(300);
        Require(h.Read().GetProperty("seconds").GetInt64() == SeedSeconds + 1805, "Polling cannot renew the allowance.");
        h.Available = true; h.Runtime.Sample();
        Require(h.DiskSeconds() == SeedSeconds + 1805, "The bounded interval is retained for eventual same-owner confirmation.");
    }

    private static void RecoveryCrossingDeadlineIsClamped()
    {
        using var h = new Harness();
        h.Available = false;
        h.Advance(1795);
        h.Time.Now = h.Time.Now.AddSeconds(3); h.Runtime.Sample(); // confirmation + 1798
        h.Time.Now = h.Time.Now.AddSeconds(5); h.Available = true; h.Runtime.Sample(); // + 1803
        Require(h.DiskSeconds() == SeedSeconds + 1805,
            "Recovery settles only through the old deadline, excluding the final three seconds.");
        h.Advance(5);
        Require(h.DiskSeconds() == SeedSeconds + 1810,
            "Ordinary recording starts again at recovery, without bridging the expired gap.");
    }

    private static void UnconfirmedLoadRetries(bool generationChanged)
    {
        using var h = new Harness();
        if (generationChanged) h.Generation++;
        else h.Runtime.Suspend();
        // Open resolves once and validates its new lease once; the third call is Read.
        h.FailOwnerResolution = h.OwnerResolutions + 3;
        h.Runtime.Sample();
        Require(h.OwnerResolutions == h.FailOwnerResolution,
            "The fixture fails Read ownership validation only after Open succeeded.");
        var failed = h.Read();
        Require(AbsentOrNull(failed, "pauseReason") &&
            failed.GetProperty("error").GetString() == "gameplay.unavailable",
            "Without a confirmation timestamp, Read failure must enter retry rather than connection continuity.");
        var resolutions = h.OwnerResolutions;
        h.Advance(25);
        Require(h.OwnerResolutions == resolutions, "Reload waits for the ordinary thirty-second backoff.");
        // A second temporary failure keeps the short fixed cycle instead of doubling to 60 seconds.
        h.FailOwnerResolution = h.OwnerResolutions + 3;
        h.Advance(5);
        Require(h.OwnerResolutions == h.FailOwnerResolution, "The first retry ran at 30 seconds and failed again.");
        resolutions = h.OwnerResolutions;
        h.Advance(25);
        Require(h.OwnerResolutions == resolutions, "The second retry still waits 30 seconds.");
        h.Advance(5);
        var recovered = h.Read();
        Require(AbsentOrNull(recovered, "pauseReason") &&
            AbsentOrNull(recovered, "error") &&
            recovered.GetProperty("recording").GetBoolean(), "A successful reload clears the pause and records again.");
        h.Advance(5);
        Require(h.DiskSeconds() == SeedSeconds + 10, "Only resumed samples are persisted after a failed reload.");
    }

    private static void TransitionNeverOpensZeroFile(bool alias)
    {
        using var h = new Harness();
        h.Transition = true; h.Alias = alias; h.Advance(60);
        Require(h.Read().GetProperty("seconds").GetInt64() == SeedSeconds + 65,
            "A null-session/null-reader transition with a binding or alias cannot select the zero file.");
        h.Transition = false; h.Runtime.Sample();
        Require(h.DiskSeconds() == SeedSeconds + 65, "The original storage lease is used after transition.");
    }

    private static async Task ProjectionRetainsTotals()
    {
        using var h = new Harness();
        await h.Runtime.RefreshAccountTotalAsync();
        h.Remote.Fails = true;
        await h.Runtime.RefreshAccountTotalAsync();
        h.Available = false; h.Advance(60);
        var view = h.Read();
        Require(view.GetProperty("pauseReason").GetString() == "connection", "Connection has its own UI reason.");
        Require(view.GetProperty("recording").GetBoolean() &&
            AbsentOrNull(view, "error"),
            "Connection recording obeys the original recording/error protocol invariant.");
        Require(view.GetProperty("seconds").GetInt64() == SeedSeconds + 65, "Local time never switches to zero.");
        Require(view.GetProperty("savedSeconds").GetInt64() == SeedSeconds + 5, "Saved and provisional seconds stay distinct.");
        Require(view.GetProperty("accountTotalSeconds").GetInt64() == 900 * 3600 &&
            view.GetProperty("accountTotalStale").GetBoolean(), "Last account total is retained and marked stale.");
        var before = File.ReadAllBytes(h.OriginalFile);
        h.Read("setConsent", new { schemaVersion = 1, allowed = false });
        h.Read("setVisibility", new { schemaVersion = 1, showOnProfile = false });
        Require(File.ReadAllBytes(h.OriginalFile).SequenceEqual(before), "Connection continuity grants no command write permission.");
    }

    private static async Task RetirementNeverCommits()
    {
        using var h = new Harness();
        h.Available = false; h.Advance(300);
        await h.Runtime.RetireAsync();
        Require(h.DiskSeconds() == SeedSeconds + 5, "Retire/Dispose never persist unconfirmed time.");
    }

    private static void NullGameplayOwnerRetainsSameLogin()
    {
        using var h = new Harness();
        h.Available = false; h.NullGameplayOwner = true; h.Advance(300);
        Require(h.Read().GetProperty("seconds").GetInt64() == SeedSeconds + 305,
            "A missing gameplay owner under the same authentication keeps the projection and memory interval.");
        h.Auth = null; h.Generation++; h.Runtime.Sample();
        Require(h.DiskSeconds() == SeedSeconds + 5, "Logout discards rather than commits.");
    }

    private static void UnobservedRecoveryCommits()
    {
        using var h = new Harness();
        h.Available = false; h.Identity = "not-observed"; h.Advance(300);
        h.Available = true; h.Runtime.Sample();
        Require(h.DiskSeconds() == SeedSeconds + 305, "A retained Match with no observed mismatch can be reconciled.");
    }

    private static void RecoveredMismatchStillDiscards()
    {
        using var h = new Harness();
        h.Available = false; h.Advance(300);
        // Game.log samples faster than playtime: a mismatch may already be
        // corrected by the next five-second playtime sample.
        h.Rejections++; h.Available = true; h.Runtime.Sample();
        Require(h.DiskSeconds() == SeedSeconds + 5,
            "A mismatch observed between playtime ticks still invalidates the entire pending interval.");
    }

    private static void GameLogMatchIsRetainedAndMismatchWins()
    {
        var root = Path.Combine(Path.GetTempPath(), "sb-transient-log-" + Guid.NewGuid().ToString("N"));
        var path = Path.Combine(root, "StarCitizen", "LIVE", "Game.log");
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var time = new Clock { Now = DateTimeOffset.Parse("2026-09-04T12:00:30Z") };
        var confirmed = time.Now;
        var available = true;
        long generation = 1;
        try
        {
            File.WriteAllText(path, "<2026-09-04T12:00:10Z> [Notice] nickname=\"SyntheticPilot\" playerGEID=12345\n");
            var store = new GameLogSettingsStore(root) {
                ResolveOwner = _ => available ? Storage : throw new LocalPrivacyOwnerUnavailableException()
            };
            using var log = new GameLogRuntime(store, () => (available ? Authentication : null, generation),
                () => "SyntheticPilot", () => new("running", path, confirmed.AddSeconds(-30), "synthetic-process"),
                time, startTimer: false, continuity: () => new(Authentication, generation, available, "match", confirmed));
            var selected = log.Dispatch(BridgeEnvelope.Request("gameLog.select", "synthetic-select", 1,
                new { schemaVersion = 1, path }, Authentication));
            Require(selected.Response.Status == "ok" && log.IdentityPolicyState == StarBridge.Core.Identity.LocalIdentityCheckState.Match,
                "Synthetic live log establishes the initial Match.");
            available = false; time.Now = time.Now.AddMinutes(5); log.Sample();
            Require(log.IdentityPolicyState == StarBridge.Core.Identity.LocalIdentityCheckState.Match,
                "An unavailable owner does not demote the confirmed log Match.");
            time.Now = confirmed.AddMinutes(31); log.Sample();
            Require(log.IdentityPolicyState == StarBridge.Core.Identity.LocalIdentityCheckState.NotObserved,
                "The log's retained Match expires after thirty minutes.");
            File.AppendAllText(path, "<2026-09-04T12:31:31Z> [Notice] nickname=\"DifferentPilot\" playerGEID=54321\n");
            time.Now = confirmed.AddMinutes(32);
            Require(GameLogIdentityReader.Read(path,
                new("running", path, confirmed.AddSeconds(-30), "synthetic-process"), time.Now).State == "ambiguous",
                "Two different current-session identities produce ambiguous, not identified.");
            var version = log.IdentityRejectionVersion;
            log.Sample();
            Require(log.IdentityRejectionVersion == version + 1, "Ambiguous conflicting Handles advance the rejection fence.");
            Require(log.IdentityPolicyState == StarBridge.Core.Identity.LocalIdentityCheckState.Mismatch,
                "A newly observed mismatch wins even while the owner is unavailable.");
            generation++;
            Require(log.IdentityPolicyState == StarBridge.Core.Identity.LocalIdentityCheckState.NotObserved,
                "Log evidence cannot cross a generation fence.");
        }
        finally { Directory.Delete(root, true); }
    }

    private static void GameLogConflictCannotBeReconciled()
    {
        var root = Path.Combine(Path.GetTempPath(), "sb-transient-linked-" + Guid.NewGuid().ToString("N"));
        var path = Path.Combine(root, "StarCitizen", "LIVE", "Game.log");
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var time = new Clock { Now = DateTimeOffset.Parse("2026-09-04T12:00:30Z") };
        var started = time.Now.AddSeconds(-30);
        var available = true;
        const string original = "<2026-09-04T12:00:10Z> [Notice] nickname=\"SyntheticPilot\" playerGEID=12345\n";
        try
        {
            File.WriteAllText(path, original);
            var logStore = new GameLogSettingsStore(root) {
                ResolveOwner = _ => available ? Storage : throw new LocalPrivacyOwnerUnavailableException()
            };
            using var log = new GameLogRuntime(logStore, () => (available ? Authentication : null, 1L),
                () => "SyntheticPilot", () => new("running", path, started, "synthetic-process"),
                time, startTimer: false, continuity: () => new(Authentication, 1, available, "match", started.AddSeconds(30)));
            Require(log.Dispatch(BridgeEnvelope.Request("gameLog.select", "synthetic-linked", 1,
                new { schemaVersion = 1, path }, Authentication)).Response.Status == "ok",
                "The linked fixture selects its synthetic log.");
            var store = new GameplayTimeStore(root);
            using (var lease = store.Open(Storage))
                lease.Save(lease.Read(), GameplayRecordingConsent.Allowed, SeedSeconds, () => true);
            var file = Directory.GetFiles(Path.Combine(root, "gameplay-time-local-v1"), "*.json").Single();
            store.ResolveOwner = _ => available ? Storage : throw new LocalPrivacyOwnerUnavailableException();
            string Identity() => log.IdentityPolicyState switch {
                StarBridge.Core.Identity.LocalIdentityCheckState.Match => "match",
                StarBridge.Core.Identity.LocalIdentityCheckState.Mismatch => "identity",
                _ => "not-observed"
            };
            using var gameplay = new GameplayTimeRuntime(store, () => (Authentication, 1L),
                () => new(1, "running"), time, startTimer: false,
                recordingAllowed: () => available && Identity() == "match",
                continuity: () => new(Authentication, 1, available, Identity(),
                    available ? time.Now : null, log.IdentityRejectionVersion));
            gameplay.Sample();
            time.Now = time.Now.AddSeconds(5); gameplay.Sample();
            var before = File.ReadAllBytes(file);
            available = false;
            for (var i = 0; i < 60; i++)
            { time.Now = time.Now.AddSeconds(5); log.Sample(); gameplay.Sample(); }
            var version = log.IdentityRejectionVersion;
            // Two IDs for the same Handle fill the reader's bounded dictionary.
            // The third valid identity must still produce rejection evidence.
            File.AppendAllText(path,
                "<2026-09-04T12:05:30Z> [Notice] nickname=\"SyntheticPilot\" playerGEID=67890\n" +
                "<2026-09-04T12:05:31Z> [Notice] nickname=\"DifferentPilot\" playerGEID=54321\n");
            var reader = new GameLogIdentityReader();
            Require(reader.ReadCurrent(path, new("running", path, started, "synthetic-process"), time.Now).State == "ambiguous" &&
                reader.HasObservedOtherHandle("SyntheticPilot"), "Ambiguous snapshots retain conflicting Handle evidence beyond two IDs.");
            log.Sample();
            Require(log.IdentityRejectionVersion == version + 1 &&
                Identity() == "identity", "The actual log producer publishes a sticky rejection.");
            File.WriteAllText(path, original); log.Sample();
            Require(log.IdentityRejectionVersion == version + 1 && Identity() == "identity",
                "Removing the conflict line cannot revoke the outage rejection.");
            // No gameplay tick saw Mismatch: it must consume the producer's version.
            available = true; log.Sample(); gameplay.Sample();
            Require(File.ReadAllBytes(file).SequenceEqual(before),
                "Even a recovered Match cannot write the rejected transient interval.");
        }
        finally { Directory.Delete(root, true); }
    }

    internal static async Task OwnerRecoveryNotifications()
    {
        foreach (var changeGeneration in new[] { false, true })
        {
            using var h = new Harness();
            h.Runtime.Suspend();
            h.Available = false;
            h.Runtime.Sample();
            Require(h.Read().GetProperty("error").GetString() == "gameplay.unavailable",
                "An unconfirmed owner uses retry, not the transient window.");
            if (changeGeneration) h.Generation++;
            h.Available = true;
            h.Runtime.Sample(); // No clock advance: the notification must bypass the retry deadline.
            var recovered = h.Read();
            Require(AbsentOrNull(recovered, "error") &&
                recovered.GetProperty("consent").GetString() == "allowed" &&
                recovered.GetProperty("seconds").GetInt64() == SeedSeconds + 5,
                "Owner availability or a new generation immediately reloads saved consent and time.");
        }

        foreach (var changeAccount in new[] { false, true })
        {
            using var h = new Harness();
            var remote = new ResetSpy();
            BridgeEnvelope Request(string command, object body) => BridgeEnvelope.Request(
                "gameplayTime." + command, Guid.NewGuid().ToString("N"), h.Generation, body, h.Auth);
            var preview = await h.Runtime.DispatchResetAsync(
                Request("resetPreview", new { schemaVersion = 1 }), remote);
            Require(preview.Response.Payload.GetProperty("state").GetString() == "ready",
                "The old login must have a real reset ticket before changing ownership.");
            var previewId = preview.Response.Payload.GetProperty("previewId").GetString()!;
            var started = await h.Runtime.DispatchHistoryAsync(Request("historyScanStart", new { schemaVersion = 1 }));
            Require(started.Response.Payload.GetProperty("state").GetString() == "scanning",
                "The old login must have a real scan before changing ownership.");
            var scanId = started.Response.Payload.GetProperty("scanId").GetString()!;
            var query = new { schemaVersion = 1, scanId };
            var oldScan = started;
            for (var i = 0; i < 100 && oldScan.Response.Payload.GetProperty("state").GetString() == "scanning"; i++)
            {
                await Task.Delay(10);
                oldScan = await h.Runtime.DispatchHistoryAsync(Request("historyScanRead", query));
            }
            Require(oldScan.Response.Payload.GetProperty("state").GetString() == "identityRequired",
                "The real scan has a readable completed result before the login changes.");
            const long nextSeed = 17;
            var nextOwner = Authentication with { Subject = "synthetic-next" };
            var filesBefore = Directory.GetFiles(Path.Combine(h.Root, "gameplay-time-local-v1"), "*.json");
            string currentFile = h.OriginalFile;
            if (changeAccount)
            {
                using (var lease = new GameplayTimeStore(h.Root).Open(nextOwner))
                    lease.Save(lease.Read(), GameplayRecordingConsent.Allowed, nextSeed, () => true);
                currentFile = Directory.GetFiles(Path.Combine(h.Root, "gameplay-time-local-v1"), "*.json")
                    .Except(filesBefore).Single();
            }
            h.Available = false;
            h.Advance(60);
            Require(h.Read().GetProperty("seconds").GetInt64() == SeedSeconds + 65,
                "The old login has a real transient interval to discard.");
            if (changeAccount) { h.Auth = nextOwner; h.Owner = nextOwner; }
            else h.Generation++;
            h.Available = true;
            // No sample/read first: admission must not depend on the old entry's confirmation.
            var reset = await h.Runtime.DispatchResetAsync(
                Request("resetConfirm", new { schemaVersion = 1, previewId }), remote);
            Require(reset.Response.Payload.GetProperty("state").GetString() == "previewExpired",
                "The new login reaches ticket isolation without accepting an old confirmation.");
            var scan = await h.Runtime.DispatchHistoryAsync(
                Request("historyScanRead", query));
            Require(scan.Response.Payload.GetProperty("state").GetString() == "previewExpired",
                "The new login reaches scan isolation without reading a previous scan.");
            Require(remote.Writes == 0, "The old reset ticket never submits a reset.");
            h.Runtime.Sample();
            Require(h.DiskSeconds() == SeedSeconds + 5, "Admission never commits the previous login's transient time.");
            var expected = changeAccount ? nextSeed : SeedSeconds + 5;
            Require(h.Read().GetProperty("seconds").GetInt64() == expected,
                "The current login's projection excludes the previous transient interval.");
            using var currentDocument = JsonDocument.Parse(File.ReadAllBytes(currentFile));
            var snapshot = currentDocument.RootElement.GetProperty("snapshot");
            Require(snapshot.GetProperty("seconds").GetInt64() == expected && AbsentOrNull(snapshot, "pendingReset"),
                "The current login's file contains neither old transient time nor a pending reset.");
        }
    }

    internal static Task OwnerProbeReadFailureBackoff()
    {
        var root = Path.Combine(Path.GetTempPath(), "sb-owner-probe-" + Guid.NewGuid().ToString("N"));
        try
        {
            var time = new Clock();
            var resolutions = 0;
            var failures = 0;
            var untilFailure = 3;
            var failReads = true;
            var store = new GameplayTimeStore(root) {
                ResolveOwner = owner => {
                    resolutions++;
                    // Open resolves and validates, then Read validates again.
                    // Allow the resolver probe too for the one early reload below.
                    if (failReads && --untilFailure == 0)
                    {
                        failures++;
                        untilFailure = 3;
                        throw new LocalPrivacyOwnerUnavailableException();
                    }
                    return owner;
                }
            };
            using var runtime = new GameplayTimeRuntime(store, () => (Authentication, 1),
                () => new(1, "running"), time, startTimer: false);
            void Read() => runtime.Dispatch(BridgeEnvelope.Request("gameplayTime.read",
                Guid.NewGuid().ToString("N"), 1, new { schemaVersion = 1 }, Authentication));
            runtime.Sample();
            Require(failures == 1 && resolutions == 3, "Initial Open succeeds but Read validation fails.");
            untilFailure = 4; // Successful probe, successful Open, failing Read.
            Read();
            Require(failures == 2 && resolutions == 7, "One successful probe permits an early reload.");
            for (var second = 1; second < 30; second++)
            {
                time.Now = DateTimeOffset.UnixEpoch.AddSeconds(second);
                runtime.Sample(); Read();
            }
            Require(failures == 2 && resolutions == 7, "Polling cannot bypass backoff after the early reload fails.");
            for (var cycle = 1; cycle <= 3; cycle++)
            {
                time.Now = DateTimeOffset.UnixEpoch.AddSeconds(cycle * 30);
                runtime.Sample();
                Require(failures == cycle + 2 && resolutions == 7 + cycle * 3,
                    "Persistent Read failure reloads only at each normal retry deadline.");
                for (var poll = 0; poll < 10; poll++) { Read(); runtime.Sample(); }
                Require(failures == cycle + 2 && resolutions == 7 + cycle * 3,
                    "A scheduled failed reload does not rearm early recovery probes.");
            }
            failReads = false;
            time.Now = time.Now.AddSeconds(30);
            runtime.Sample();
            var recovered = runtime.Dispatch(BridgeEnvelope.Request("gameplayTime.read",
                Guid.NewGuid().ToString("N"), 1, new { schemaVersion = 1 }, Authentication)).Response;
            Require(recovered.Status == "ok" && AbsentOrNull(recovered.Payload, "error"),
                "Successful Read eventually recovers through the ordinary retry.");
        }
        finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
        return Task.CompletedTask;
    }

    private static bool AbsentOrNull(JsonElement body, string name) =>
        !body.TryGetProperty(name, out var value) || value.ValueKind == JsonValueKind.Null;

    private static void Require(bool condition, string message)
    { if (!condition) throw new InvalidOperationException(message); }
}
