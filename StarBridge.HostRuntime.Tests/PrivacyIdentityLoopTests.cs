using System.Net;
using System.Text.Json;
using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Privacy;
using StarBridge.HostRuntime.Presence;
using StarBridge.NativeBridge;

internal static class PrivacyIdentityLoopTests
{
    internal static readonly (string Name, Func<Task> Run)[] Cases = [
        ("CX-ID-LOOP A clears once and keeps official heartbeats", ClearOnce),
        ("CX-ID-LOOP an acknowledged clear is confirmed again slowly", SlowReconfirm),
        ("CX-ID-LOOP failed clear preserves retry deadlines and recovery", FailedClear),
        ("CX-ID-LOOP B suppresses unchanged merged events", ColdIdentity),
        ("CX-ID-LOOP heartbeat timestamps stay fresh without UI events", HealthyHeartbeat),
        ("CX-ID-LOOP identity restoration resumes publication", IdentityRestoration),
        ("CX-ID-LOOP account generation and handle isolate acknowledgements", Ownership),
        ("CX-ID-LOOP scope revision requires a new clear", ScopeRevision),
        ("CX-ID-LOOP A to visibility suspension to B preserves recovery", Suspension),
        ("CX-ID-LOOP explicit pause retains the recovery barrier", ExplicitPause),
        ("CX-ID-LOOP real merged errors and recovery notify", ErrorChanges),
        ("CX-ID-LOOP consent withdrawal stays stopped", ConsentWithdrawal),
        ("CX-ID-LOOP official zero fields and missing app evidence", EvidenceMatrix)
    ];

    private static async Task ClearOnce()
    {
        using var f = new Fixture();
        await f.Start();
        f.Input = f.Input with { IdentityConfirmed = false };
        Check(await f.Round(overlap: true) == (1, 0, 0, 1), "Initial mismatch must clear ordinary and renew official");
        Check(f.Pair.Status.State == "identityRequired", "Mismatch remains visible");
        for (var i = 0; i < 8; i++)
        {
            Check(await f.Round() == (0, 0, 0, 1), "Acknowledged identity clear must not repeat");
            Check(f.Events == 0 && f.Diagnostics == 0, "Steady mismatch must not wake clients or logs");
        }
    }

    private static async Task SlowReconfirm()
    {
        using var f = new Fixture();
        await f.Start();
        f.Input = f.Input with { IdentityConfirmed = false };
        Check(await f.Round(seconds: 0, overlap: true) == (1, 0, 0, 1), "Initial mismatch clears");
        Check(await f.Round(seconds: 299) == (0, 0, 0, 1), "A success is trusted for five minutes");
        Check(await f.Round(seconds: 1) == (1, 0, 0, 1), "Then it is confirmed once, in case it did not take effect");
        Check(await f.Round() == (0, 0, 0, 1), "And trusted again");
        Check(f.Pair.Status.State == "identityRequired", "The mismatch stays visible throughout");
        Check(await f.Round(seconds: -3600) == (1, 0, 0, 1), "A clock set back must not stretch the five minutes");
        Check(await f.Round() == (0, 0, 0, 1), "And it is trusted from the new time");
    }

    private static async Task FailedClear()
    {
        using var f = new Fixture();
        await f.Start();
        f.Input = f.Input with { IdentityConfirmed = false };
        f.FailOrdinary = true;
        Check(await f.Round(seconds: 0) == (1, 0, 0, 1), "Initial privacy clear is immediate");
        Check(f.Pair.Status.ErrorCode is not null, "Failed clear must remain observable");
        Check(await f.Round(seconds: 59) == (0, 0, 0, 1), "Failed clear waits 60 seconds");
        f.FailOrdinary = true;
        Check(await f.Round(seconds: 1) == (1, 0, 0, 1), "First retry at 60 seconds");
        Check(await f.Round(seconds: 299) == (0, 0, 0, 1), "Second failure waits 300 seconds");
        f.FailOrdinary = true;
        Check(await f.Round(seconds: 1) == (1, 0, 0, 1), "Second retry at 300 seconds");
        Check(await f.Round(seconds: 899) == (0, 0, 0, 1), "Third failure waits 900 seconds");
        Check(await f.Round(seconds: 1) == (1, 0, 0, 1), "Compensating withdrawal succeeds at its deadline");
        // Existing recovery revalidates current consent, policy and identity after
        // a compensating withdrawal; it is distinct from a steady identity wait.
        Check(await f.Round() == (1, 0, 0, 1), "Recovery retains one fresh validation clear");
        for (var i = 0; i < 4; i++)
            Check(await f.Round() == (0, 0, 0, 1), "Successful recovery clear stops subsequent clears");
    }

    private static async Task ColdIdentity()
    {
        using var f = new Fixture();
        f.Input = f.Input with { IdentityConfirmed = false };
        await f.Start(warm: false);
        await f.Round();
        for (var i = 0; i < 6; i++)
        {
            var merged = f.Pair.Status;
            var receipt = f.Pair.OfficialStatus.AppliedAt;
            Check(await f.Round() == (0, 0, 0, 1), "Cold identity wait sends only official heartbeat");
            Check(f.Events == 0 && f.Diagnostics == 0 && merged == f.Pair.Status, "Unchanged merged record emits nothing");
            Check(f.Pair.OfficialStatus.AppliedAt > receipt, "Official receipt must advance");
        }
    }

    private static async Task HealthyHeartbeat()
    {
        using var f = new Fixture();
        await f.Start();
        var before = f.Pair.Status.AppliedAt;
        Check(await f.Round() == (0, 1, 0, 1), "Both healthy lanes keep sending");
        Check(f.Pair.Status.AppliedAt > before && f.Pair.OfficialStatus.AppliedAt == f.Now, "Live receipts stay current");
        Check(f.Events == 0 && f.Diagnostics == 0, "A timestamp alone does not invalidate UI state");
    }

    private static async Task IdentityRestoration()
    {
        using var f = new Fixture();
        await f.Start();
        f.Input = f.Input with { IdentityConfirmed = false };
        await f.Round();
        await f.Round();
        f.Input = f.Input with { IdentityConfirmed = true, GameVersion = "EPTU" };
        Check(await f.Round() == (0, 1, 0, 1), "Identity recovery automatically restores both lanes");
        Check(f.Pair.Status.State == "applied" && f.Events > 0 && f.Diagnostics > 0, "Real recovery must notify");
        Check(f.Sends.Where(s => s.Positive).All(s => s.Body.GetProperty("gameVersion").GetString() == "EPTU"), "Recovery rebuilds fresh game fields");
        f.Input = f.Input with { IdentityConfirmed = false };
        Check(await f.Round() == (1, 0, 0, 1), "A later identity loss owes a new clear");
        Check(await f.Round() == (0, 0, 0, 1), "The new acknowledgement also settles");
    }

    private static async Task Ownership()
    {
        foreach (var change in new[] { "owner", "generation", "handle" })
        {
            using var f = new Fixture();
            await f.Start();
            f.Input = f.Input with { IdentityConfirmed = false };
            await f.Round();
            f.Input = change switch {
                "owner" => f.Input with { Owner = new("test", "fixture.invalid", "synthetic-other") },
                "generation" => f.Input with { Generation = 2 },
                _ => f.Input with { Handle = "SyntheticOther" }
            };
            if (change == "owner") await f.SaveNewOwner();
            Check(await f.Round() == (0, 0, 0, 0), "Changed identity retires old active without sending as it");
            Check(f.Pair.Status.State == "inactive", "Old acknowledgement cannot leak to new identity");
            Check(await f.Round() == (0, 0, 0, 1), "New identity waits while official app heartbeat recovers");
            Check(f.Sends.All(s => s.Input.Owner == f.Input.Owner && s.Input.Generation == f.Input.Generation && s.Input.Handle == f.Input.Handle), "New session uses only new ownership");
            f.Input = f.Input with { IdentityConfirmed = true };
            Check(await f.Round() == (0, 1, 0, 1), "New identity resumes automatically");
            f.Input = f.Input with { IdentityConfirmed = false };
            Check(await f.Round() == (1, 0, 0, 1), "New identity cannot borrow the old clear acknowledgement");
        }
    }

    private static async Task ScopeRevision()
    {
        using var f = new Fixture();
        await f.Start();
        f.Input = f.Input with { IdentityConfirmed = false };
        await f.Round();
        f.ChangeScope();
        Check(await f.Round() == (1, 0, 0, 1), "Changed policy revision requires a new clear");
        Check(f.Pair.OrdinaryStatus.AppliedRevision == 2 && f.Events > 0, "New revision is acknowledged and notified");
        Check(await f.Round() == (0, 0, 0, 1), "New revision settles once");
    }

    private static async Task Suspension()
    {
        using var f = new Fixture();
        await f.Start();
        f.Input = f.Input with { IdentityConfirmed = false };
        await f.Round();
        Check(await f.Round() == (0, 0, 0, 1), "A has settled");
        f.Visibility = PlayerPresenceVisibilityMode.Invisible;
        f.VisibilityError = "privacy_publication.network_unavailable";
        f.Input = f.Input with { AppPresenceConfirmed = false };
        Check(await f.Round() == (1, 0, 1, 0), "Uncertain visibility still clears both lanes after identity acknowledgement");
        Check(f.Events > 0 && f.Pair.Status.ErrorCode == f.VisibilityError, "Suspension notifies");
        Check(await f.Round() == (0, 0, 0, 0), "Suspension barrier stops further sends");
        f.Visibility = PlayerPresenceVisibilityMode.Online;
        f.VisibilityError = null;
        f.Input = f.Input with { AppPresenceConfirmed = true };
        Check(await f.Round() == (0, 0, 0, 1), "Online evidence automatically restores official lane");
        for (var i = 0; i < 4; i++)
        {
            Check(await f.Round() == (0, 0, 0, 1), "A to B leaves only normal official heartbeats");
            Check(f.Events == 0 && f.Diagnostics == 0, "B is silent");
        }
        f.Input = f.Input with { IdentityConfirmed = true };
        Check(await f.Round() == (0, 1, 0, 1), "Identity recovery after B restores ordinary lane");
    }

    private static async Task ExplicitPause()
    {
        using var f = new Fixture();
        await f.Start();
        f.Input = f.Input with { IdentityConfirmed = false };
        await f.Round();
        f.Sends.Clear();
        Check(await f.Pair.ChangeVisibilityAsync(f.Input.Owner, f.Input.Generation, _ => Task.CompletedTask, default),
            "Explicit online action still gets both lane acknowledgements");
        Check(f.Sends.Count(s => !s.Official && !s.Positive) == 1,
            "Deferred explicit visibility action requires a fresh ordinary clear");
        Check(await f.Round() == (0, 0, 0, 1), "Explicit confirmation settles again");
        f.Visibility = PlayerPresenceVisibilityMode.Invisible;
        Check(await f.Round() == (1, 0, 1, 0), "Explicit invisibility still clears both lanes");
        Check(f.Pair.Status.State == "withdrawn", "Pause acknowledgement is visible");
        f.Visibility = PlayerPresenceVisibilityMode.Online;
        f.Input = f.Input with { IdentityConfirmed = true };
        Check(await f.Round() == (0, 0, 0, 0), "Online observation cannot bypass persisted pause");
        await f.Pair.ChangeVisibilityAsync(f.Input.Owner, f.Input.Generation, _ => Task.CompletedTask, default);
        Check(f.Pair.Status.State == "applied", "Explicit resume retains its existing recovery behavior");
    }

    private static async Task ErrorChanges()
    {
        using var f = new Fixture();
        f.Input = f.Input with { IdentityConfirmed = false };
        await f.Start(warm: false);
        await f.Round();
        f.FailOfficial = true;
        await f.Round();
        Check(f.Pair.Status.State == "reconnecting" && f.Events > 0 && f.Diagnostics > 0, "Official errors must override identity wait and notify");
        await f.Round(seconds: 60);
        Check(f.Pair.Status.State == "identityRequired" && f.Events > 0 && f.Diagnostics > 0, "Recovery changes merged status and notifies");
        await f.Round();
        Check(f.Events == 0 && f.Diagnostics == 0, "Recovered steady state is silent");
    }

    private static async Task ConsentWithdrawal()
    {
        using var f = new Fixture();
        await f.Start();
        f.Input = f.Input with { IdentityConfirmed = false };
        await f.Round();
        Check(await f.Pair.StopAsync(default, explicitRequest: true), "Explicit stop still clears both lanes");
        f.Input = f.Input with { IdentityConfirmed = true };
        Check(await f.Round() == (0, 0, 0, 0), "Identity restoration cannot undo withdrawal");
        Check(!f.Store.HasPublicationConsent(f.Input.Owner), "Consent remains withdrawn");
    }

    private static async Task EvidenceMatrix()
    {
        foreach (var fields in new[] { PlayerSharedStateFields.None, PlayerSharedStateFields.Presence })
        foreach (var app in new[] { false, true })
        {
            using var f = new Fixture(fields);
            await f.Start();
            f.Input = f.Input with { IdentityConfirmed = false, AppPresenceConfirmed = app };
            await f.Round();
            for (var i = 0; i < 3; i++)
            {
                // Missing app evidence still follows the official lane's existing
                // clear path; this fix changes only ordinary identity clears.
                var expected = fields == 0 || !app ? (0, 0, 1, 0) : (0, 0, 0, 1);
                Check(await f.Round() == expected, "Evidence matrix keeps allowed official renewal only");
                if (fields == 0 || app) Check(f.Events == 0 && f.Diagnostics == 0, "Steady allowed heartbeat is silent");
            }
        }
    }

    private sealed class Clock : TimeProvider
    {
        private DateTimeOffset _now = new(2026, 11, 1, 0, 0, 0, TimeSpan.Zero);
        public override DateTimeOffset GetUtcNow() => _now;
        internal void Advance(double seconds) => _now += TimeSpan.FromSeconds(seconds);
    }

    private sealed class Fixture : IDisposable
    {
        // No debug data-root dependency, real account, timer or HTTP transport.
        private readonly string _root = Directory.CreateTempSubdirectory("sb-identity-loop-").FullName;
        private readonly Clock _clock = new();
        private readonly LocalPrivacySettings _settings;
        private TaskCompletionSource? _holdClear;
        internal readonly LocalPrivacyStore Store;
        internal readonly PrivacyPublicationPair Pair;
        internal readonly List<(PrivacyPublicationInput Input, JsonElement Body, bool Official, bool Positive)> Sends = [];
        internal PrivacyPublicationInput Input = new(new("test", "fixture.invalid", "synthetic-loop"), 1,
            "SyntheticVerified", true, "LIVE", GameLogSessionSnapshot.Empty, AppPresenceConfirmed: true);
        internal PlayerPresenceVisibilityMode Visibility = PlayerPresenceVisibilityMode.Online;
        internal string? VisibilityError;
        internal bool FailOrdinary, FailOfficial;
        internal int Events, Diagnostics;
        internal DateTimeOffset Now => _clock.GetUtcNow();

        internal Fixture(PlayerSharedStateFields officialFields = PlayerSharedStateFields.Presence)
        {
            Store = new(_root);
            _settings = new(true, new(0, false, false, []), new(PlayerSharedStateFields.Presence, true), [],
                OfficialFleet: new(new("fixture", 1, "SYNTHETIC", "scm-observed-membership-row-v1:1"), officialFields,
                    "initial", Guid.NewGuid().ToString("N")));
            Store.Save(Input.Owner, 0, Guid.NewGuid().ToString("N"), _settings, () => true);
            Pair = new(Store, () => Input, Send, startTimer: false, timeProvider: _clock,
                visibilitySnapshot: () => new(Input.Owner, Input.Generation, "fixture", null, Visibility, VisibilityError));
            Pair.StatusChanged += () => Interlocked.Increment(ref Events);
            Pair.Diagnostic = (_, _) => Interlocked.Increment(ref Diagnostics);
        }

        internal async Task Start(bool warm = true)
        {
            if (warm) await Pair.ApplyAsync(Input.Owner, Input.Generation, 1, default);
            else await Store.SetPublicationConsentAsync(Input.Owner, 1, true, () => true, default);
        }

        internal async Task SaveNewOwner()
        {
            Store.Save(Input.Owner, 0, Guid.NewGuid().ToString("N"), _settings, () => true);
            await Store.SetPublicationConsentAsync(Input.Owner, 1, true, () => true, default);
        }

        internal void ChangeScope() => Store.Save(Input.Owner, 1, Guid.NewGuid().ToString("N"),
            _settings with { Room = new(PlayerSharedStateFields.Presence | PlayerSharedStateFields.Ship, true) }, () => true);

        private async Task Send(PrivacyPublicationInput input, JsonElement body, CancellationToken token)
        {
            var official = body.TryGetProperty("officialFleet", out _);
            var positive = body.GetProperty("online").GetBoolean();
            Sends.Add((input, body.Clone(), official, positive));
            if (!input.IdentityConfirmed)
            {
                Check(official || !positive, "Unconfirmed identity cannot publish ordinary positive fields");
                Check(body.GetProperty("gameVersion").ValueKind == JsonValueKind.Null &&
                    body.GetProperty("serverShard").ValueKind == JsonValueKind.Null &&
                    body.GetProperty("ship").GetString() == "Unknown" && body.GetProperty("location").GetString() == "Unknown",
                    "Unconfirmed identity must remove game data");
                Check(!PrivacyPublicationPayload.HasOriginalPositiveAudience(body), "Unconfirmed identity cannot retain original audiences");
                if (official) Check(!body.GetProperty("gameObserved").GetBoolean(), "Official mismatch payload is app-only");
            }
            if (official ? FailOfficial : FailOrdinary)
            {
                if (official) FailOfficial = false; else FailOrdinary = false;
                throw new HttpRequestException("Synthetic transport failure", null, official ? null : HttpStatusCode.ServiceUnavailable);
            }
            if (!official && !positive && _holdClear is not null) await _holdClear.Task.WaitAsync(token);
        }

        internal async Task<(int, int, int, int)> Round(double seconds = 5.7, bool overlap = false)
        {
            _clock.Advance(seconds);
            Sends.Clear(); Events = Diagnostics = 0;
            _holdClear = overlap ? new(TaskCreationOptions.RunContinuationsAsynchronously) : null;
            var tick = Pair.TickAsync();
            _holdClear?.TrySetResult();
            await tick;
            _holdClear = null;
            return (Sends.Count(s => !s.Official && !s.Positive), Sends.Count(s => !s.Official && s.Positive),
                Sends.Count(s => s.Official && !s.Positive), Sends.Count(s => s.Official && s.Positive));
        }

        public void Dispose() { Pair.Dispose(); Directory.Delete(_root, true); }
    }

    private static void Check(bool value, string message) { if (!value) throw new Exception(message); }
}
