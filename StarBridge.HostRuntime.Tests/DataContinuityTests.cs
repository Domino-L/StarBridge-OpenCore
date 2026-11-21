using System.Text.Json;
using StarBridge.Core.Profiles;
using StarBridge.HostRuntime.Onboarding;
using StarBridge.HostRuntime.Presence;
using StarBridge.NativeBridge;

internal static class DataContinuityTests
{
    private static readonly BridgeAccountContext Owner = new("test", "scm", "synthetic-continuity");
    internal static async Task Run()
    {
        IdentityPendingProjection();
        await IdentityVerificationSequence();
        foreach (var choice in new[] { GameplayRecordingConsent.Declined, GameplayRecordingConsent.Allowed })
        {
            await Consent(choice, GameplayRecordingConsent.Unknown, choice);
            Console.WriteLine("PASS continuity: Unknown adopts setup " + choice);
        }
        await Consent(null, GameplayRecordingConsent.Declined, GameplayRecordingConsent.Declined);
        Console.WriteLine("PASS continuity: existing decline survives legacy default");
        await Consent(null, GameplayRecordingConsent.Unknown, GameplayRecordingConsent.Allowed);
        Console.WriteLine("PASS continuity: never chosen keeps legacy default");
        await Consent(GameplayRecordingConsent.Declined, GameplayRecordingConsent.Allowed, GameplayRecordingConsent.Allowed);
        Console.WriteLine("PASS continuity: existing allow survives local decline");
        await Consent(GameplayRecordingConsent.Declined, GameplayRecordingConsent.Unknown, GameplayRecordingConsent.Allowed, "OtherPilot");
        Console.WriteLine("PASS continuity: setup A decline cannot become account B consent");
        foreach (var handle in new string?[] { null, "", "syntheticpilot" })
        {
            await Consent(GameplayRecordingConsent.Declined, GameplayRecordingConsent.Unknown,
                string.IsNullOrWhiteSpace(handle) ? GameplayRecordingConsent.Unknown : GameplayRecordingConsent.Declined, handle);
            Console.WriteLine("PASS continuity: missing verified identity waits; same identity ignores case");
        }
        foreach (var status in Enum.GetValues<StarBridge.Core.Identity.ScmGameIdentityStatus>())
        {
            // Exercise the same verified-identity filter used by GameplayHandle.
            var handle = StarBridge.Core.Hangar.RsiHangarIdentityPolicy.DisplayHandle(
                new(status, "SyntheticPilot", "syntheticpilot"));
            await Consent(GameplayRecordingConsent.Declined, GameplayRecordingConsent.Unknown,
                status == StarBridge.Core.Identity.ScmGameIdentityStatus.Verified
                    ? GameplayRecordingConsent.Declined : GameplayRecordingConsent.Unknown, handle);
            Console.WriteLine("PASS continuity: account identity status " + status);
        }
        await PublicationFailureKeepsTotal();
        await Totals();
        await NoFileOnLoginRead();
        await ObservationFailureKeepsPublisher();
        await AccountSwitchDiscardsLateTotal();
        await SetupDecisionAfterSamplerLoad();
        await SlowTotalReadCannotBlockDecline();
        await SupplementalReadCancellationInvalidatesTotal();
    }

    private sealed class Clock : TimeProvider
    {
        internal DateTimeOffset Now = DateTimeOffset.UnixEpoch;
        public override DateTimeOffset GetUtcNow() => Now;
    }

    private static void IdentityPendingProjection()
    {
        foreach (var setup in Enum.GetValues<GameplayRecordingConsent>())
        foreach (var explicitChoice in new bool?[] { null, false, true })
        {
            var root = Root();
            try
            {
                SeedSetup(root, setup);
                string? handle = null;
                using var runtime = new GameplayTimeRuntime(new(root), () => (Owner, 1),
                    startTimer: false, verifiedHandle: () => handle);
                var waiting = Read(runtime);
                var hasMarker = waiting.TryGetProperty("consentPending", out var pending);
                Check(waiting.GetProperty("consent").GetString() == "unknown" &&
                    (setup == GameplayRecordingConsent.Unknown ? !hasMarker :
                        hasMarker && pending.GetString() == "identity"),
                    "Only a saved setup choice awaiting identity may expose consentPending=identity.");
                if (explicitChoice is { } allowed)
                {
                    var chosen = runtime.Dispatch(BridgeEnvelope.Request("gameplayTime.setConsent",
                        Guid.NewGuid().ToString("N"), 1, new { schemaVersion = 1, allowed }, Owner)).Response.Payload;
                    Check(!chosen.TryGetProperty("consentPending", out _) &&
                        chosen.GetProperty("consent").GetString() == (allowed ? "allowed" : "declined"),
                        "An explicit settings choice must immediately replace the pending setup choice.");
                }
                handle = "SyntheticPilot";
                var confirmed = Read(runtime);
                var expected = explicitChoice is { } selected ? selected ? "allowed" : "declined" :
                    setup.ToString().ToLowerInvariant();
                Check(!confirmed.TryGetProperty("consentPending", out _) &&
                    confirmed.GetProperty("consent").GetString() == expected,
                    "Confirmed identity removes the marker; unanswered setup remains ordinary Unknown.");
            }
            finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
        }
        var damagedRoot = Root();
        try
        {
            SeedSetup(damagedRoot, GameplayRecordingConsent.Declined);
            var path = Directory.GetFiles(Path.Combine(damagedRoot, "local-gameplay-time-v1"), "*.bin").Single();
            File.WriteAllBytes(path, [0]);
            using var runtime = new GameplayTimeRuntime(new(damagedRoot), () => (Owner, 1), startTimer: false);
            var unchanged = Read(runtime);
            Check(unchanged.GetProperty("consent").GetString() == "unknown" &&
                !unchanged.TryGetProperty("consentPending", out _) && !unchanged.TryGetProperty("error", out _),
                "A failed optional choice lookup must preserve ordinary Unknown while identity is unverified.");
        }
        finally { if (Directory.Exists(damagedRoot)) Directory.Delete(damagedRoot, true); }
        Console.WriteLine("PASS continuity: identity pending marker, other Unknown, confirmation and explicit choices");
    }

    private static async Task IdentityVerificationSequence()
    {
        foreach (var verified in new[] { "SyntheticPilot", "OtherPilot" })
        foreach (var trigger in new[] { "sample", "read" })
        foreach (var existing in new[] { false, true })
        {
            var root = Root();
            try
            {
                SeedSetup(root, GameplayRecordingConsent.Declined);
                var store = new GameplayTimeStore(root);
                GameplayTimeSaved original = new(0, GameplayRecordingConsent.Unknown, 0);
                if (existing)
                {
                    using var lease = store.Open(Owner);
                    original = lease.Save(lease.Read(), original with { Seconds = 900 }, () => true);
                }
                var remote = new Remote { RemoteSeconds = 0 };
                var clock = new Clock();
                string? handle = null; // Unverified; identity updates keep the same owner/generation.
                var observations = 0;
                using (var runtime = new GameplayTimeRuntime(store, () => (Owner, 1),
                    presence: () => { observations++; return new(1, "running"); }, time: clock,
                    startTimer: false, verifiedHandle: () => handle, historyRemote: remote))
                {
                    runtime.Sample();
                    clock.Now = clock.Now.AddSeconds(5);
                    runtime.Sample();
                    var waiting = Read(runtime);
                    Check(waiting.GetProperty("consent").GetString() == "unknown" &&
                        waiting.GetProperty("seconds").GetInt64() == original.Seconds &&
                        !waiting.GetProperty("recording").GetBoolean() && observations == 0,
                        "Unverified identity must retain Unknown without sampling or accumulation.");
                    await runtime.PublishCurrentGameplayAsync();
                    Check(remote.Uploads == 0, "Pending identity must not publish gameplay statistics.");
                    var onlineDirectory = Path.Combine(root, "gameplay-time-local-v1");
                    var files = Directory.GetFiles(onlineDirectory, "*.json");
                    Check(existing ? files.Length == 1 : files.Length == 0,
                        "Waiting for identity must not materialize an online record.");
                    if (existing)
                    {
                        using var document = JsonDocument.Parse(File.ReadAllText(files.Single()));
                        var snapshot = document.RootElement.GetProperty("snapshot");
                        Check(snapshot.GetProperty("revision").GetInt64() == original.Revision &&
                            snapshot.GetProperty("consent").GetInt32() == (int)GameplayRecordingConsent.Unknown,
                            "Waiting must not rewrite an existing Unknown record or its defaults.");
                    }
                    handle = verified;
                    if (trigger == "sample") runtime.Sample();
                    var resolved = Read(runtime);
                    var expected = verified == "SyntheticPilot" ? "declined" : "allowed";
                    Check(resolved.GetProperty("consent").GetString() == expected &&
                        resolved.GetProperty("seconds").GetInt64() == original.Seconds,
                        "The next existing entry point must reload the newly verified identity without backfill.");
                    await runtime.PublishCurrentGameplayAsync();
                    Check(remote.Uploads == (expected == "allowed" ? 1 : 0),
                        "Only a resolved allow may use the original publication path.");
                }
                using var persisted = store.Open(Owner);
                Check(persisted.Read().Consent == (verified == "SyntheticPilot"
                    ? GameplayRecordingConsent.Declined : GameplayRecordingConsent.Allowed),
                    "Resolved consent must be durable.");
                Console.WriteLine($"PASS continuity: Unverified -> {verified}, reload by {trigger}, existing={existing}");
            }
            finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
        }
        await Consent(null, GameplayRecordingConsent.Unknown, GameplayRecordingConsent.Allowed, verifiedHandle: null);
        Console.WriteLine("PASS continuity: no confirmed local profile and Unverified keeps legacy allow");
    }

    private static async Task SupplementalReadCancellationInvalidatesTotal()
    {
        foreach (var timeout in new[] { false, true })
        {
            var root = Root();
            try
            {
                var remote = new Remote { Revision = 1, RemoteSeconds = 600 };
                using var runtime = new GameplayTimeRuntime(new(root), () => (Owner, 1),
                    startTimer: false, historyRemote: remote);
                await runtime.PublishCurrentGameplayAsync();
                Check(Read(runtime).GetProperty("accountTotalSeconds").GetInt64() == 600,
                    "The earlier authoritative read must expose 600 seconds.");
                var uploads = remote.Uploads;
                remote.Revision = 0;
                using var cancellation = new CancellationTokenSource();
                remote.ReadTotal = async token => {
                    if (!timeout) cancellation.Cancel();
                    await Task.Delay(Timeout.InfiniteTimeSpan, token);
                    throw new InvalidOperationException("Cancelled supplemental read cannot succeed.");
                };
                await runtime.PublishCurrentGameplayAsync(cancellation.Token).WaitAsync(TimeSpan.FromSeconds(25));
                var view = Read(runtime);
                // 11-14 f90dd7c0 (30-min grace, user "30-min hold"): an unconfirmed read keeps the last account
                // total for display, marked stale ("updates later"), like the failed-GET case below. Still one GET, no PUT.
                Check(remote.TotalReads == 1 && view.GetProperty("accountTotalState").GetString() == "available" &&
                    view.GetProperty("accountTotalSeconds").GetInt64() == 600 &&
                    view.GetProperty("accountTotalStale").GetBoolean() &&
                    remote.Uploads == uploads,
                    "A timed-out/cancelled supplemental GET keeps the last 600 seconds as stale and must not PUT.");
                Console.WriteLine("PASS continuity: supplemental GET marks the total stale after " + (timeout ? "15s budget timeout" : "caller cancellation"));
            }
            finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
        }
    }

    private static string Root() => Path.Combine(Path.GetTempPath(), "starbridge-continuity-" + Guid.NewGuid().ToString("N"));
    private static void SeedSetup(string root, GameplayRecordingConsent choice)
    {
        var live = Path.Combine(root, "game", "LIVE");
        Directory.CreateDirectory(live);
        var path = Path.Combine(live, "Game.log");
        File.WriteAllText(path, "");
        var identities = new LocalFirstUseStore(root);
        var selected = identities.SelectSource(0, Guid.NewGuid().ToString("N"), path, "LIVE", () => true);
        var confirmed = identities.ConfirmIdentity(selected.Revision, Guid.NewGuid().ToString("N"),
            new(selected.SelectedSourceKey!, new string('a', 64), "SyntheticPilot", DateTimeOffset.UtcNow,
                "current", true, false), () => true);
        if (choice == GameplayRecordingConsent.Unknown) return;
        var statistics = new LocalGameplayTimeStore(root);
        using var lease = statistics.Open(confirmed.ActiveProfileId!, () => true);
        var old = statistics.Read(confirmed.ActiveProfileId!);
        lease.Save(old, old with { Consent = choice }, () => true);
    }

    private static async Task Consent(GameplayRecordingConsent? setup, GameplayRecordingConsent online, GameplayRecordingConsent expected,
        string? verifiedHandle = "SyntheticPilot")
    {
        var root = Root();
        try
        {
            if (setup is { } chosen) SeedSetup(root, chosen);
            var store = new GameplayTimeStore(root);
            using (var lease = store.Open(Owner))
            {
                var old = lease.Read();
                lease.Save(old, old with { Consent = online, Seconds = 900, ShowOnProfile = true }, () => true);
            }
            var remote = new Remote();
            using var runtime = new GameplayTimeRuntime(store, () => (Owner, 1), startTimer: false,
                verifiedHandle: () => verifiedHandle, historyRemote: remote);
            var view = Read(runtime);
            Check(view.GetProperty("consent").GetString() == expected.ToString().ToLowerInvariant(), "Setup decision must win over Unknown.");
            Check(view.GetProperty("seconds").GetInt64() == 900, "Choice cannot migrate or replace totals.");
            if (expected == GameplayRecordingConsent.Declined)
            {
                await runtime.PublishCurrentGameplayAsync();
                Check(remote.Uploads == 0 && remote.Reads == 1, "Declined still reads, never uploads.");
                Check(Read(runtime).GetProperty("seconds").GetInt64() == 900, "Read cannot change local total.");
            }
        }
        finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
    }

    private static async Task PublicationFailureKeepsTotal()
    {
        foreach (var revision in new long[] { 0, 1 })
        {
            var root = Root();
            try
            {
                var store = new GameplayTimeStore(root);
                using (var lease = store.Open(Owner))
                {
                    var old = lease.Read();
                    lease.Save(old, old with { Consent = GameplayRecordingConsent.Allowed, Seconds = 900 }, () => true);
                }
                var remote = new Remote { Revision = revision, RemoteSeconds = 600,
                    Total = new("available", 600), ThrowPublish = true };
                using var runtime = new GameplayTimeRuntime(store, () => (Owner, 1), startTimer: false, verifiedHandle: () => "SyntheticPilot", historyRemote: remote);
                await runtime.PublishCurrentGameplayAsync();
                var view = Read(runtime);
                Check(remote.Uploads == 1 && view.GetProperty("accountTotalState").GetString() == "available" &&
                    view.GetProperty("accountTotalSeconds").GetInt64() == 600 && view.GetProperty("seconds").GetInt64() == 900,
                    "A failed PUT must retain this round's successful GET and local seconds.");
                remote.ThrowRead = true;
                await runtime.PublishCurrentGameplayAsync();
                var stale = Read(runtime);
                Check(remote.Uploads == 1 && stale.GetProperty("accountTotalState").GetString() == "available" &&
                    stale.GetProperty("accountTotalSeconds").GetInt64() == 600 && stale.GetProperty("accountTotalStale").GetBoolean(),
                    "A failed GET retains the last display value as stale and must not PUT.");
                Console.WriteLine("PASS continuity: PUT failure retains GET; GET failure marks total stale, revision " + revision);
            }
            finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
        }
    }

    private static async Task Totals()
    {
        var root = Root();
        try
        {
            SeedSetup(root, GameplayRecordingConsent.Declined);
            var remote = new Remote();
            using var runtime = new GameplayTimeRuntime(new(root), () => (Owner, 1), startTimer: false, verifiedHandle: () => "SyntheticPilot", historyRemote: remote);
            foreach (var total in new[] { new GameplayAccountTotal("available", 86400), new("empty"), new("unavailable") })
            {
                remote.Total = total;
                remote.Throw = total.State == "unavailable";
                await runtime.RefreshAccountTotalAsync();
                var view = Read(runtime);
                Check(view.GetProperty("accountTotalState").GetString() == total.State, "Account total has three states.");
                Check(total.Seconds is { } seconds
                    ? view.GetProperty("accountTotalSeconds").GetInt64() == seconds
                    : !view.TryGetProperty("accountTotalSeconds", out var value) || value.ValueKind == JsonValueKind.Null,
                    "Unavailable/empty has no zero fallback.");
                Check(view.GetProperty("seconds").GetInt64() == 0 && remote.Uploads == 0, "Account total is read-only.");
                Console.WriteLine("PASS continuity: account total " + total.State + ", declined, no upload/local rewrite");
            }
            remote.Throw = false;
            remote.Total = new("available", 0);
            await runtime.RefreshAccountTotalAsync();
            Check(Read(runtime).GetProperty("accountTotalSeconds").GetInt64() == 0, "Confirmed zero remains available.");
            var calls = remote.TotalReads;
            await runtime.RefreshAccountTotalAsync(once: true);
            Check(remote.TotalReads == calls, "One initial read per account generation.");
            Console.WriteLine("PASS continuity: confirmed zero and login read coalescing");
        }
        finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
    }

    private static async Task NoFileOnLoginRead()
    {
        var root = Root();
        try
        {
            var remote = new Remote();
            using var runtime = new GameplayTimeRuntime(new(root), () => (Owner, 1), startTimer: false, verifiedHandle: () => "SyntheticPilot", historyRemote: remote);
            await runtime.RefreshAccountTotalAsync(once: true);
            Check(!Directory.Exists(root), "Login total read must not materialize an Unknown online consent.");
            SeedSetup(root, GameplayRecordingConsent.Declined);
            Check(Read(runtime).GetProperty("consent").GetString() == "declined", "Setup choice after login read still wins.");
            Check(remote.Uploads == 0, "Login read cannot upload.");
            Console.WriteLine("PASS continuity: login read before setup does not preempt choice");
        }
        finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
    }

    private static async Task ObservationFailureKeepsPublisher()
    {
        var root = Root();
        try
        {
            var store = new GameplayTimeStore(root);
            using (var lease = store.Open(Owner))
            {
                var old = lease.Read();
                lease.Save(old, old with { Consent = GameplayRecordingConsent.Allowed, Seconds = 900, ShowOnProfile = true }, () => true);
            }
            var remote = new Remote { Revision = 0, RemoteSeconds = 600, Throw = true };
            using var runtime = new GameplayTimeRuntime(store, () => (Owner, 1), startTimer: false, verifiedHandle: () => "SyntheticPilot", historyRemote: remote);
            await runtime.PublishCurrentGameplayAsync();
            Check(remote.Uploads == 1 && remote.PublishedSeconds == 900, "Optional display failure cannot change original max publication.");
            Check(Read(runtime).GetProperty("accountTotalState").GetString() == "unavailable", "Failed observation never claims zero.");
            Check(Read(runtime).GetProperty("seconds").GetInt64() == 900, "Publication cannot write account total to local total.");
            Console.WriteLine("PASS continuity: optional read failure preserves original max publisher");
        }
        finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
    }
    private static async Task AccountSwitchDiscardsLateTotal()
    {
        var root = Root();
        try
        {
            var pending = new TaskCompletionSource<GameplayAccountTotal>(TaskCreationOptions.RunContinuationsAsynchronously);
            var remote = new Remote { PendingTotal = pending.Task };
            (BridgeAccountContext? Context, long Generation) current = (Owner, 1);
            using var runtime = new GameplayTimeRuntime(new(root), () => current, startTimer: false, verifiedHandle: () => "SyntheticPilot", historyRemote: remote);
            var read = runtime.RefreshAccountTotalAsync(once: true);
            current = (Owner with { Subject = "other-synthetic-owner" }, 2);
            runtime.Suspend();
            pending.SetResult(new("available", 99999));
            await read;
            JsonElement View() => runtime.Dispatch(BridgeEnvelope.Request("gameplayTime.read",
                Guid.NewGuid().ToString("N"), 2, new { schemaVersion = 1 }, current.Context)).Response.Payload;
            Check(View().GetProperty("accountTotalState").GetString() == "unavailable", "Late old-account totals must be discarded.");
            remote.PendingTotal = null;
            remote.Total = new("available", 7200);
            await runtime.RefreshAccountTotalAsync(once: true);
            await runtime.RefreshAccountTotalAsync(once: true);
            Check(View().GetProperty("accountTotalSeconds").GetInt64() == 7200 &&
                View().GetProperty("seconds").GetInt64() == 0 && remote.TotalReads == 2 && remote.Uploads == 0,
                "New generation reads once without modifying its counter.");
            Console.WriteLine("PASS continuity: account switch discards late total and reads once for new owner");
        }
        finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
    }
    private static async Task SetupDecisionAfterSamplerLoad()
    {
        var root = Root();
        try
        {
            SeedSetup(root, GameplayRecordingConsent.Unknown);
            var remote = new Remote();
            using var runtime = new GameplayTimeRuntime(new(root), () => (Owner, 1), startTimer: false, verifiedHandle: () => "SyntheticPilot", historyRemote: remote);
            runtime.Sample();
            Check(Read(runtime).GetProperty("consent").GetString() == "unknown", "A pending setup step must not persist a legacy allow.");
            await runtime.PublishCurrentGameplayAsync();
            Check(remote.Uploads == 0, "An unanswered existing setup choice cannot upload.");
            var profile = new LocalFirstUseStore(root).Read().ActiveProfileId!;
            var local = new LocalGameplayTimeStore(root);
            using (var lease = local.Open(profile, () => true))
            {
                var old = local.Read(profile);
                lease.Save(old, old with { Consent = GameplayRecordingConsent.Declined }, () => true);
            }
            runtime.Sample();
            Check(Read(runtime).GetProperty("consent").GetString() == "declined", "The late setup choice must be adopted while online remains Unknown.");
            await runtime.PublishCurrentGameplayAsync();
            Check(remote.Uploads == 0, "The late decline remains upload-free.");
            Console.WriteLine("PASS continuity: sampler before setup decision cannot preempt later decline");
        }
        finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
    }
    private static async Task SlowTotalReadCannotBlockDecline()
    {
        var root = Root();
        try
        {
            var pending = new TaskCompletionSource<GameplayAccountTotal>(TaskCreationOptions.RunContinuationsAsynchronously);
            var remote = new Remote { PendingTotal = pending.Task };
            using var runtime = new GameplayTimeRuntime(new(root), () => (Owner, 1), startTimer: false, verifiedHandle: () => "SyntheticPilot", historyRemote: remote);
            var observation = runtime.RefreshAccountTotalAsync(once: true);
            var stopped = runtime.Dispatch(BridgeEnvelope.Request("gameplayTime.setConsent",
                Guid.NewGuid().ToString("N"), 1, new { schemaVersion = 1, allowed = false }, Owner)).Response;
            Check(!observation.IsCompleted && stopped.Status == "ok" &&
                stopped.Payload.GetProperty("consent").GetString() == "declined",
                "Consent must settle while the unrelated read remains pending.");
            pending.SetResult(new("available", 36000));
            await observation;
            var view = Read(runtime);
            Check(view.GetProperty("consent").GetString() == "declined" &&
                view.GetProperty("seconds").GetInt64() == 0 &&
                view.GetProperty("accountTotalSeconds").GetInt64() == 36000 && remote.Uploads == 0,
                "Completing the read cannot undo the immediate decline.");
            Console.WriteLine("PASS continuity: slow account read cannot block or overwrite decline");
        }
        finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
    }
    private static JsonElement Read(GameplayTimeRuntime runtime) => runtime.Dispatch(
        BridgeEnvelope.Request("gameplayTime.read", Guid.NewGuid().ToString("N"), 1, new { schemaVersion = 1 }, Owner)).Response.Payload;
    private static void Check(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }

    private sealed class Remote : IGameplayHistoryRemote, IGameplayAccountTotalRemote
    {
        internal GameplayAccountTotal Total = new("available", 86400);
        internal bool Throw, ThrowRead, ThrowPublish;
        internal Task<GameplayAccountTotal>? PendingTotal;
        internal Func<CancellationToken, Task<GameplayAccountTotal>>? ReadTotal;
        internal int Uploads, Reads, TotalReads;
        internal long Revision = 1, RemoteSeconds = 86400;
        internal long? PublishedSeconds;
        public Task<GameplayAccountTotal> ReadAccountTotalAsync(BridgeAccountContext owner, CancellationToken token)
        {
            TotalReads++;
            if (ReadTotal is not null) return ReadTotal(token);
            if (PendingTotal is not null) return PendingTotal;
            return Throw ? Task.FromException<GameplayAccountTotal>(new IOException("synthetic failure")) : Task.FromResult(Total);
        }
        public Task<GameplayTimeResetState> ReadAsync(BridgeAccountContext owner, CancellationToken token)
        {
            Reads++;
            if (ThrowRead) return Task.FromException<GameplayTimeResetState>(new IOException("synthetic GET failure"));
            return Task.FromResult(new GameplayTimeResetState(1, Revision, null, null, RemoteSeconds, 0, null));
        }
        public Task<GameplayTimeResetResult> ResetAsync(BridgeAccountContext owner, GameplayTimeResetRequest request, CancellationToken token) =>
            throw new InvalidOperationException("Read-only regression cannot reset.");
        public Task<bool> PublishGameplayStatisticsAsync(BridgeAccountContext owner, PersonalProfileGameplayStatisticsUpdateRequestContract update, CancellationToken token)
        {
            Uploads++; PublishedSeconds = update.PlayTimeSeconds;
            return ThrowPublish ? Task.FromException<bool>(new IOException("synthetic PUT failure")) : Task.FromResult(true);
        }
    }
}
