using System.Reflection;
using StarBridge.Core.Identity;
using StarBridge.Core.Presence;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Privacy;
using StarBridge.HostRuntime.Settings;

internal static partial class SharingReviewRegressionTests
{
    internal static async Task M04g()
    {
        var failures = new List<string>();
        var tests = new List<(string Name, Func<Task> Run)>();
        foreach (int? missing in new int?[] { null, 0 })
        {
            foreach (var point in new[] { "input", "account", "room", "final", "storageFailure" })
            foreach (var empty in new[] { false, true })
                tests.Add(($"{point} emptyHandle={empty} 3 then {missing?.ToString() ?? "null"}", () => RuntimeInvisible(empty, missing, point)));
        }
        tests.Add(("null positive input retains owner and withdrawal", NullInputOwner));
        tests.Add(("foreign owner and generation cannot latch pause", ForeignObservation));
        tests.Add(("private raw access and mutation guard", VisibilityReadArchitecture));
        foreach (var (name, run) in tests)
        {
            try { await run(); Console.WriteLine("PASS M04g " + name); }
            catch (Exception error) { failures.Add(name); Console.WriteLine("FAIL M04g " + name + ": " + error.Message); }
        }
        Console.WriteLine($"M04g cases: {tests.Count - failures.Count} passed, {failures.Count} failed");
        if (failures.Count > 0) throw new Exception(string.Join("; ", failures));
    }

    private static readonly BindingFlags PrivateInstance = BindingFlags.Instance | BindingFlags.NonPublic;

    // Real runtime composition and SCM observation storage; all publication HTTP
    // goes through an in-memory handler. The fake clock never starts background IO.
    private static async Task RuntimeInvisible(bool emptyHandle, int? missing, string point)
    {
        using var f = new Fixture();
        using var handler = new AdmissionHandler(emptyHandle ? "official" : "ordinary");
        handler.Release.TrySetResult();
        using var writer = new PrivacyRelayWriter(new Uri("https://sharing.invalid"), handler);
        using var authHandler = new M04fHandler();
        var session = new ScmOAuthSession("fixture-scm", "fixture-subject", "Fixture", "synthetic-only",
            DateTimeOffset.UtcNow.AddMinutes(5), [], GameIdentityHandle: emptyHandle ? null : "Fixture",
            GameIdentityStatus: emptyHandle ? ScmGameIdentityStatus.Unverified : ScmGameIdentityStatus.Verified);
        using var host = new ScmAccountBridgeHost(
            new OAuthPkceClient(new ScmHttpClient(authHandler), new NoM04gVault(), ScmOAuthOptions.CreateDefault()),
            new ScmProfileCacheStore(), "fixture", () => null, initialSession: session);
        var owner = host.GameplayTimeContext!;
        var choice = handler.Choice;
        var settings = emptyHandle ? f.Settings with {
            Fleet = new(PlayerSharedStateFields.None, false, false, []), Communities = [], OfficialFleet = choice
        } : f.Settings;
        f.Store.Save(owner, 0, Guid.NewGuid().ToString("N"), settings, () => true);
        SetM04gObservation(host, 1);
        using var runtime = new AccountBridgeRuntime(host, privacy: f.Store,
            visibility: new(f.Root), backgroundTime: new SharingTestClock());
        var publication = emptyHandle ? PrivacyPublicationTestAccess.Official(runtime) : PrivacyPublicationTestAccess.Ordinary(runtime);
        var bridge = (PresenceVisibilityBridge)typeof(AccountBridgeRuntime).GetField("_presenceVisibility", PrivateInstance)!.GetValue(runtime)!;
        // Preserve production input and observer wiring; only replace the IO sink.
        var raceArmed = false;
        void ArmInvisible()
        {
            SetM04gObservation(host, 3);
            bridge.SnapshotCaptured = () => {
                SetM04gObservation(host, missing); bridge.SnapshotCaptured = null;
                if (point == "storageFailure") throw new IOException("Synthetic post-sample settings failure");
            };
        }
        typeof(PrivacyPublication).GetField("_send", PrivateInstance)!.SetValue(publication,
            new Func<PrivacyPublicationInput, System.Text.Json.JsonElement, CancellationToken, Task>((input, body, ct) => {
                // The real runtime final callback first validates Online, then
                // PublicationInput samples 3, whose capture hook replaces it by
                // null/0 before the callback can finish. Game identity remains valid.
                var callbackInput = input with { RequirePositiveAdmission = () => {
                    input.RequirePositiveAdmission?.Invoke();
                    if (raceArmed) { raceArmed = false; ArmInvisible(); }
                } };
                return writer.SendAsync("synthetic-only", body, ct,
                    () => runtime.RequireCurrentPrivacyPublication(callbackInput, body, ct),
                    allowOfficialPositive: true, admission: input.PositiveAdmission);
            }));
        await publication.ApplyAsync(owner, host.Generation, 1, default);
        Check(handler.PositiveWrites == 1, "initial runtime sharing must be active");
        // The original sample must be latched even if transport changes before
        // the queued tick. This is the actual runtime input getter, not f.Input.
        if (point == "final") { raceArmed = true; await publication.TickAsync(); }
        else
        {
            ArmInvisible();
            switch (point)
            {
                case "input":
                case "storageFailure": _ = typeof(AccountBridgeRuntime).GetMethod("PublicationInput", PrivateInstance)!.Invoke(runtime, null); break;
                case "account": Check(!host.HasObservedAppPresence(new(owner, host.Generation, "", false, null,
                    StarBridge.HostRuntime.Presence.GameLogSessionSnapshot.Empty)), "account bridge rejects captured invisible"); break;
                case "room":
                    var member = new StarBridge.HostRuntime.PartyRooms.RoomMemberView("Fixture", "", true, "", "Unknown", "Unknown", "Unknown");
                    Check(host.ProjectRoomSelfPresence(member, owner, host.Generation, true).PresenceKey == "presence.invisible", "room projects exact captured 3");
                    break;
            }
        }
        SetM04gObservation(host, missing);
        await publication.TickAsync();
        Check(new LocalPrivacyStore(f.Root).IsPublicationPaused(owner), "runtime read of 3 must persist pause");
        Check(handler.Clears > 0, "owner-valid empty input must still withdraw");
        SetM04gObservation(host, 1);
        await publication.TickAsync(); await publication.TickAsync();
        Check(handler.PositiveWrites == 1, "later online cannot resume or escape final admission");
        var before = handler.PositiveWrites;
        var restoredInput = (PrivacyPublicationInput)typeof(AccountBridgeRuntime).GetMethod("PublicationInput", PrivateInstance)!.Invoke(runtime, null)!;
        using var restarted = new PrivacyPublication(new(f.Root), () => restoredInput, (input, body, ct) =>
            writer.SendAsync("synthetic-only", body, ct, input.RequirePositiveAdmission, allowOfficialPositive: true,
                admission: input.PositiveAdmission), startTimer: false);
        await restarted.TickAsync();
        Check(handler.PositiveWrites == before, "pause survives store and publisher reconstruction");
    }

    private static async Task NullInputOwner()
    {
        foreach (var consent in new[] { false, true })
        {
        using var f = new Fixture();
        if (consent) f.Store.SetPublicationConsent(f.Owner, 1, true, () => true);
        var before = Directory.GetFiles(f.Root, "*.json", SearchOption.AllDirectories).ToDictionary(path => path, File.ReadAllBytes);
        var owned = f.Input with { Handle = "", IdentityConfirmed = false, AppPresenceConfirmed = false };
        int? observed = 3;
        var clears = 0;
        using var p = new PrivacyPublication(f.Store, () => null, (_, body, _) => {
            Check(!body.GetProperty("online").GetBoolean(), "null input never sends positives"); clears++; return Task.CompletedTask;
        }, startTimer: false, currentOwner: () => owned,
            visibilitySnapshot: () => new(f.Owner, 1, "fixture", observed, observed == 1 ? PlayerPresenceVisibilityMode.Online : PlayerPresenceVisibilityMode.Invisible, null));
        await p.TickAsync();
        observed = 1; await p.TickAsync();
        if (consent)
            Check(f.Store.IsPublicationPaused(f.Owner) && clears == 1, "cold consented null input must persist and withdraw exactly once");
        else
            Check(!f.Store.IsPublicationPaused(f.Owner) && clears == 0 &&
                before.Count == Directory.GetFiles(f.Root, "*.json", SearchOption.AllDirectories).Length &&
                before.All(pair => pair.Value.SequenceEqual(File.ReadAllBytes(pair.Key))),
                "cold unconfirmed null input stays read-only without a fabricated withdrawal");
        }
    }

    private static async Task ForeignObservation()
    {
        using var f = new Fixture();
        using var p = new PrivacyPublication(f.Store, () => f.Input, (_, _, _) => Task.CompletedTask, startTimer: false);
        p.ObserveVisibility(new(f.Owner with { Subject = "other" }, 1, "fixture", 3, PlayerPresenceVisibilityMode.Invisible, null));
        p.ObserveVisibility(new(f.Owner, 2, "fixture", 3, PlayerPresenceVisibilityMode.Invisible, null));
        await p.TickAsync();
        Check(!f.Store.IsPublicationPaused(f.Owner), "foreign snapshots cannot pause current owner");
    }

    private static void SetM04gObservation(ScmAccountBridgeHost host, int? value)
    {
        var observationType = typeof(ScmAccountBridgeHost).GetNestedType("RealtimeObservation", BindingFlags.NonPublic)!;
        var observation = value is null ? null : Activator.CreateInstance(observationType,
            host.Generation, value.Value, DateTimeOffset.UtcNow.AddMinutes(1));
        var gate = typeof(ScmAccountBridgeHost).GetField("_realtimeGate", PrivateInstance)!.GetValue(host)!;
        lock (gate)
            typeof(ScmAccountBridgeHost).GetMethod("SetRealtimeObservation", PrivateInstance)!.Invoke(host, [observation]);
    }

    private sealed class NoM04gVault : ITokenVault
    {
        public void SaveRefreshToken(string a, string b) => throw new Exception("Unexpected credential IO");
        public string? LoadRefreshToken(string a) => throw new Exception("Unexpected credential IO");
        public string? LoadActiveAccountKey() => throw new Exception("Unexpected credential IO");
        public void DeleteRefreshToken(string a) => throw new Exception("Unexpected credential IO");
    }
}


