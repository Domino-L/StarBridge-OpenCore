using System.Net;
using System.Text.Json;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Onboarding;
using StarBridge.NativeBridge;

internal static class FirstUseOnlineIdentityTests
{
    private static string Id() => Guid.NewGuid().ToString("N");
    private static void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
    private static async Task Case(string name, Func<Task> work)
    { await work(); Console.WriteLine("PASS first-use online identity: " + name); }
    private sealed class Clock : TimeProvider
    {
        internal DateTimeOffset Now = DateTimeOffset.UtcNow.AddSeconds(1);
        public override DateTimeOffset GetUtcNow() => Now;
    }
    internal static async Task Run()
    {
        await Case("sign-in is required without restoring cached credentials", BeforeLogin);
        await Case("review and explicit fresh readback do not activate or merge accounts", Matching);
        await Case("canonical and normalized-only Handles retain the confirmed local owner", Canonical);
        await Case("a mismatched Handle cannot confirm or switch the local profile", Mismatch);
        await Case("an unconfirmed selected log blocks even a verified server identity", NeedsLocal);
        await Case("all authoritative nonverified states remain blocked", VerificationStates);
        await Case("missing contradictory and malformed identity facts never use compatibility fallback", InvalidIdentity);
        await Case("confirmation rereads revocation and Handle changes", ChangedReadback);
        await Case("changed display facts require a new one-use review", ChangedDisplay);
        await Case("a new real OAuth owner requires a new identity review", ChangedAccount);
        await Case("local source changes invalidate both pending and confirmed reviews", ChangedSource);
        await Case("actual cancellation waits for an identity transport ignoring cancellation", CancelDrain);
        await Case("401 and service failure neither refresh selected credentials nor clear them", HttpFailure);
        await Case("newer same or different account credential versions prevent handoff", CredentialRace);
        await Case("expiry and backward clocks cannot extend confirmation", Expiry);
        await Case("overlapping reviews and used keys cannot authorize a second confirmation", ReviewAdmission);
        await Case("a cold owner cannot reuse a live candidate confirmation", Cold);
        await Case("damaged local identity storage preserves bytes and cannot authorize a review", DamagedLocal);
    }
    private static async Task Start(FirstUseOnlineReturnTests.Fixture f, bool login = true, TimeProvider? clock = null)
    {
        await f.Prepare(clock); f.Mode.RequestOnline(2, Id()); await f.Stage();
        if (login) Check((await f.Login().WaitAsync(TimeSpan.FromSeconds(3))).Response.Status == BridgeResponseStatuses.Ok,
            "Actual synthetic PKCE login must complete.");
    }
    private static Task<FirstUseOnlineIdentityObservation> Read(FirstUseOnlineReturnTests.Fixture f) =>
        f.Mode.ReadOnlineIdentityAsync(3);
    private static Task<FirstUseOnlineIdentityObservation> Confirm(FirstUseOnlineReturnTests.Fixture f,
        FirstUseOnlineIdentityObservation review) => f.Mode.ConfirmOnlineIdentityAsync(3, review.ConfirmationKey!);
    private static void Blocked(FirstUseOnlineReturnTests.Fixture f)
    {
        Check(!f.Mode.HasConfirmedOnlineIdentity(3) && f.Store.Read().Phase == "onlinePending" &&
            f.Mode.LocalMode().Active && f.Clock.Timers == 0, "Blocked review keeps the actual local owner and deferred business.");
    }
    private static async Task BeforeLogin()
    {
        using var f = new FirstUseOnlineReturnTests.Fixture(); await f.Prepare();
        Check((await f.Mode.ReadOnlineIdentityAsync(2)).State == "notStarted", "Local mode isn't an online candidate.");
        f.Vault.SaveRefreshToken("synthetic-old:other", "synthetic-old-refresh"); var bytes = File.ReadAllBytes(f.VaultPath);
        f.Mode.RequestOnline(2, Id());
        Check((await Read(f)).State == "signInRequired", "A phase alone is not authorization.");
        await f.Stage();
        Check((await Read(f)).State == "signInRequired" && f.Transport.Requests == 0 &&
            File.ReadAllBytes(f.VaultPath).SequenceEqual(bytes), "Identity review cannot restore or delete the old vault.");
        Blocked(f); f.Local.RequireLocalStateUnchanged();
    }
    private static async Task Matching()
    {
        using var f = new FirstUseOnlineReturnTests.Fixture(); await Start(f);
        var epoch = f.Mode.LocalMode(); var bytes = File.ReadAllBytes(f.VaultPath);
        var review = await Read(f);
        Check(review is { State: "reviewRequired", LocalHandle: "Pilot-Example", AuthoritativeHandle: "Pilot-Example",
            AccountDisplayName: "Synthetic Pilot", ConfirmationKey: not null } && f.Transport.IdentityRequests == 2,
            "Actual current identity, not the login snapshot, issues review.");
        Blocked(f);
        Check((await Confirm(f, review)).State == "confirmedForHandoff" && f.Transport.IdentityRequests == 3 &&
            f.Mode.HasConfirmedOnlineIdentity(3) && f.Mode.LocalMode() == epoch && f.Store.Read().Phase == "onlinePending" &&
            f.Clock.Timers == 0 && File.ReadAllBytes(f.VaultPath).SequenceEqual(bytes),
            "Fresh explicit confirmation is only a live precondition, never activation or association.");
        var wire = JsonSerializer.Serialize(review);
        foreach (var secret in new[] { "synthetic-access", "synthetic-refresh", "synthetic-subject", f.Local.Root,
            new LocalFirstUseStore(f.Local.Root).Read().ActiveProfileId! })
            Check(!wire.Contains(secret, StringComparison.Ordinal), "Display observation must not contain private owner facts.");
        var forbidden = await f.Candidate!.DispatchAsync(BridgeEnvelope.Request("account.getGameIdentityPolicy", Id(),
            f.Candidate.Generation, new { schemaVersion = 1 }));
        Check(forbidden.Response.Status != BridgeResponseStatuses.Ok, "Native review does not widen the auth-only dispatcher.");
        f.Local.RequireLocalStateUnchanged();
    }
    private static async Task Canonical()
    {
        foreach (var raw in new string?[] { "PILOT-EXAMPLE", null })
        {
            using var f = new FirstUseOnlineReturnTests.Fixture(); await Start(f);
            f.Transport.Handle = raw;
            var review = await Read(f);
            Check(review.State == "reviewRequired" && (await Confirm(f, review)).State == "confirmedForHandoff" &&
                f.Mode.HasConfirmedOnlineIdentity(3), "Canonical matching doesn't rename or replace the local owner.");
            f.Local.RequireLocalStateUnchanged();
        }
    }
    private static async Task Mismatch()
    {
        using var f = new FirstUseOnlineReturnTests.Fixture(); await Start(f);
        f.Transport.Handle = "Other-Pilot"; f.Transport.NormalizedHandle = "other-pilot";
        var result = await Read(f);
        Check(result is { State: "mismatch", ConfirmationKey: null, LocalHandle: "Pilot-Example", AuthoritativeHandle: "Other-Pilot" },
            "Mismatched accounts need their own explicit decision, not automatic profile selection.");
        Blocked(f); f.Local.RequireLocalStateUnchanged();
    }
    private static async Task NeedsLocal()
    {
        using var f = new FirstUseOnlineReturnTests.Fixture(); await Start(f);
        var store = new LocalFirstUseStore(f.Local.Root); var saved = store.Read();
        store.InvalidateSourceIdentity(saved.Revision, Id(), saved.SelectedSourceKey!, () => true);
        var requests = f.Transport.Requests;
        Check((await Read(f)).State == "needsLocalIdentity" && f.Transport.Requests == requests,
            "Verified server Handle cannot substitute for the selected local log proof.");
        Blocked(f);
    }
    private static async Task VerificationStates()
    {
        foreach (var pair in new[] { ("UNVERIFIED", "verificationRequired"), ("PENDING", "verificationPending"),
            ("REVERIFY_REQUIRED", "reverifyRequired"), ("REVOKED", "revoked"), ("UNKNOWN", "unavailable") })
        {
            using var f = new FirstUseOnlineReturnTests.Fixture();
            f.Transport.Capabilities = ["profile.read", "game_identity.verify"];
            await Start(f);
            f.Transport.IdentityStatus = pair.Item1; f.Transport.IdentityVerified = false;
            var result = await Read(f);
            Check(result.State == pair.Item2 && result.ConfirmationKey is null, "Nonverified authoritative state must not match.");
            Blocked(f); f.Local.RequireLocalStateUnchanged();
        }
    }
    private static async Task InvalidIdentity()
    {
        foreach (var mutate in new Action<FirstUseOnlineReturnTests.Transport>[] {
            t => t.IncludeIdentity = false, t => t.IdentityStatus = null, t => t.IdentityStatus = "NEW_STATUS",
            t => t.IdentityStatus = "UNKNOWN", t => t.IdentityVerified = false,
            t => t.Handle = "invalid handle", t => t.NormalizedHandle = "other-pilot",
            t => { t.Handle = null; t.NormalizedHandle = null; }, t => t.Subject = "synthetic-other-subject" })
        {
            using var f = new FirstUseOnlineReturnTests.Fixture(); await Start(f); mutate(f.Transport);
            var result = await Read(f);
            Check(result.State is "unavailable" or "reauthorizationRequired" && result.ConfirmationKey is null,
                "Unknown and contradictory authority facts must not reuse older verified facts.");
            Blocked(f); f.Local.RequireLocalStateUnchanged();
        }
    }
    private static async Task ChangedReadback()
    {
        foreach (var mismatch in new[] { false, true })
        {
            using var f = new FirstUseOnlineReturnTests.Fixture();
            f.Transport.Capabilities = ["profile.read", "game_identity.verify"];
            await Start(f); var review = await Read(f);
            if (mismatch) { f.Transport.Handle = "Other-Pilot"; f.Transport.NormalizedHandle = "other-pilot"; }
            else { f.Transport.IdentityStatus = "REVOKED"; f.Transport.IdentityVerified = false; }
            Check((await Confirm(f, review)).State == (mismatch ? "mismatch" : "revoked"),
                "Confirmation must observe current identity, not the issued snapshot.");
            Blocked(f); f.Local.RequireLocalStateUnchanged();
        }
    }
    private static async Task ChangedDisplay()
    {
        using var f = new FirstUseOnlineReturnTests.Fixture(); await Start(f); var old = await Read(f);
        f.Transport.DisplayName = "Changed Synthetic Pilot";
        var next = await Confirm(f, old);
        Check(next.State == "reviewRequired" && next.ConfirmationKey != old.ConfirmationKey &&
            next.AccountDisplayName == f.Transport.DisplayName, "Changed review facts need a new confirmation.");
        Blocked(f);
        Check((await Confirm(f, next)).State == "confirmedForHandoff", "The explicit new review may confirm the same owner.");
        f.Local.RequireLocalStateUnchanged();
    }
    private static void SwitchSource(FirstUseOnlineReturnTests.Fixture f)
    {
        var store = new LocalFirstUseStore(f.Local.Root); var saved = store.Read();
        store.SelectSource(saved.Revision, Id(), Path.Combine(f.Local.Root, "install", "PTU", "Game.log"), "PTU", () => true);
    }
    private static async Task ChangedAccount()
    {
        using var f = new FirstUseOnlineReturnTests.Fixture(); await Start(f); var review = await Read(f);
        var generation = f.Candidate!.Generation;
        f.Transport.Subject = "synthetic-second-subject";
        Check((await f.Login()).Response.Status == BridgeResponseStatuses.Ok && f.Candidate.Generation != generation,
            "The actual PKCE login must install a distinct authenticated generation.");
        var next = await Confirm(f, review);
        Check(next.State == "reviewRequired" && next.ConfirmationKey != review.ConfirmationKey,
            "Same Handle does not silently accept a different SCM subject or authorization lifecycle.");
        Blocked(f);
        Check((await Confirm(f, next)).State == "confirmedForHandoff", "Only the explicitly reviewed new owner may confirm.");
        f.Local.RequireLocalStateUnchanged();
    }
    private static async Task ChangedSource()
    {
        using (var f = new FirstUseOnlineReturnTests.Fixture())
        {
            await Start(f); var review = await Read(f); SwitchSource(f);
            await Expect("firstUse.context_changed", () => Confirm(f, review)); Blocked(f);
        }
        using (var f = new FirstUseOnlineReturnTests.Fixture())
        {
            await Start(f); var review = await Read(f); await Confirm(f, review); SwitchSource(f); Blocked(f);
        }
        using (var f = new FirstUseOnlineReturnTests.Fixture())
        {
            await Start(f); f.Transport.HoldIdentity = true; var read = Read(f);
            await f.Transport.IdentityEntered.Task.WaitAsync(TimeSpan.FromSeconds(3)); SwitchSource(f);
            f.Transport.ReleaseIdentity.TrySetResult();
            Check((await read).State == "contextChanged", "Late transport cannot authorize a new selected source."); Blocked(f);
        }
    }
    private static async Task CancelDrain()
    {
        using var f = new FirstUseOnlineReturnTests.Fixture(); await Start(f);
        f.Transport.HoldIdentity = true; var read = Read(f);
        await f.Transport.IdentityEntered.Task.WaitAsync(TimeSpan.FromSeconds(3)); var cancel = f.Cancel();
        Check(!cancel.IsCompleted && f.Transport.IdentityToken.IsCancellationRequested && f.Mode.LocalMode().Active,
            "Cancellation acknowledgment must await actual admitted identity transport exit.");
        f.Transport.ReleaseIdentity.TrySetResult();
        Check((await read.WaitAsync(TimeSpan.FromSeconds(3))).State == "contextChanged" &&
            (await cancel.WaitAsync(TimeSpan.FromSeconds(3))).State == "local" && !f.Mode.HasConfirmedOnlineIdentity(3) &&
            f.Vault.LoadActiveAccountKey() is null, "Late read cannot commit identity after actual candidate retirement.");
        f.Local.RequireLocalStateUnchanged();
    }
    private static async Task HttpFailure()
    {
        foreach (var status in new[] { HttpStatusCode.Unauthorized, HttpStatusCode.InternalServerError })
        {
            using var f = new FirstUseOnlineReturnTests.Fixture(); await Start(f);
            var tokens = f.Transport.TokenRequests; var bytes = File.ReadAllBytes(f.VaultPath);
            f.Transport.IdentityResponseStatus = status;
            Check((await Read(f)).State == (status == HttpStatusCode.Unauthorized ? "reauthorizationRequired" : "unavailable") &&
                f.Transport.TokenRequests == tokens && f.Transport.Revokes == 0 && File.ReadAllBytes(f.VaultPath).SequenceEqual(bytes),
                "Identity HTTP failure cannot replay a token refresh, revoke or delete credentials.");
            Blocked(f); f.Local.RequireLocalStateUnchanged();
        }
    }
    private static async Task CredentialRace()
    {
        foreach (var key in new[] { "synthetic-scm:synthetic-subject", "synthetic-other:other" })
        foreach (var hold in new[] { false, true })
        {
            using var f = new FirstUseOnlineReturnTests.Fixture(); await Start(f); var review = await Read(f);
            var before = f.Transport.IdentityRequests; Task<FirstUseOnlineIdentityObservation>? work = null;
            if (hold)
            {
                f.Transport.HoldIdentity = true; work = Confirm(f, review);
                await f.Transport.IdentityEntered.Task.WaitAsync(TimeSpan.FromSeconds(3));
            }
            f.Vault.SaveRefreshToken(key, "synthetic-newer-refresh"); var bytes = File.ReadAllBytes(f.VaultPath);
            Check(!f.Mode.HasConfirmedOnlineIdentity(3), "Changed actual Windows credential version invalidates the live precondition.");
            if (hold) f.Transport.ReleaseIdentity.TrySetResult(); else work = Confirm(f, review);
            Check((await work!).State == "reauthorizationRequired" && File.ReadAllBytes(f.VaultPath).SequenceEqual(bytes) &&
                f.Transport.TokenRequests == 1 && f.Transport.Revokes == 0 &&
                f.Transport.IdentityRequests == before + (hold ? 1 : 0),
                "Same/different account credential races never adopt, refresh or clear the newer writer.");
            Blocked(f); f.Local.RequireLocalStateUnchanged();
        }
        foreach (var key in new[] { "synthetic-scm:synthetic-subject", "synthetic-other:other" })
        {
            using var f = new FirstUseOnlineReturnTests.Fixture(); await Start(f); await Confirm(f, await Read(f));
            Check(f.Mode.HasConfirmedOnlineIdentity(3), "Actual current confirmation is required before testing invalidation.");
            f.Vault.SaveRefreshToken(key, "synthetic-later-refresh"); var bytes = File.ReadAllBytes(f.VaultPath);
            Blocked(f);
            Check(File.ReadAllBytes(f.VaultPath).SequenceEqual(bytes), "Invalidating a live proof does not clear the later credential.");
        }
    }
    private static async Task Expiry()
    {
        foreach (var backwards in new[] { false, true })
        {
            using var f = new FirstUseOnlineReturnTests.Fixture(); var clock = new Clock(); await Start(f, clock: clock);
            var review = await Read(f); var requests = f.Transport.Requests;
            clock.Now += backwards ? TimeSpan.FromTicks(-1) : TimeSpan.FromMinutes(2);
            Check((await Confirm(f, review)).State == "reviewExpired" && f.Transport.Requests == requests,
                "Expired or backward-clock review must require a new review before a readback."); Blocked(f);
        }
        using (var f = new FirstUseOnlineReturnTests.Fixture())
        {
            var clock = new Clock(); await Start(f, clock: clock); await Confirm(f, await Read(f));
            clock.Now += TimeSpan.FromMinutes(2); Blocked(f);
        }
        using (var f = new FirstUseOnlineReturnTests.Fixture())
        {
            var time = new FirstUseOnlineReturnTests.FrozenSessionTime(); f.SessionTime = time;
            f.Transport.TokenLifetimeSeconds = 1; await Start(f); time.Now += TimeSpan.FromMilliseconds(1100);
            var requests = f.Transport.Requests;
            Check((await Read(f)).State == "sessionExpired" && f.Transport.Requests == requests,
                "An expired candidate cannot restore a selected cached session."); Blocked(f);
        }
    }
    private static async Task ReviewAdmission()
    {
        using var f = new FirstUseOnlineReturnTests.Fixture(); await Start(f);
        f.Transport.HoldIdentity = true; var read = Read(f);
        await f.Transport.IdentityEntered.Task.WaitAsync(TimeSpan.FromSeconds(3));
        await Expect("firstUse.operation_in_progress", () => Read(f));
        f.Transport.ReleaseIdentity.TrySetResult(); var review = await read;
        await Confirm(f, review);
        await Expect("firstUse.context_changed", () => Confirm(f, review));
        Blocked(f); f.Local.RequireLocalStateUnchanged();
    }
    private static async Task Cold()
    {
        using var f = new FirstUseOnlineReturnTests.Fixture(); await Start(f); await Confirm(f, await Read(f));
        using var cold = await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Local.Root,
            _ => throw new InvalidOperationException("Cold review must never restore OAuth."));
        Check((await cold.FirstUseMode!.ReadOnlineIdentityAsync(3)).State == "signInRequired" &&
            !cold.FirstUseMode.HasConfirmedOnlineIdentity(3) && cold.FirstUseMode.LocalMode().Active,
            "An in-memory proof is not persisted authorization for another lifecycle.");
    }
    private static async Task DamagedLocal()
    {
        using var f = new FirstUseOnlineReturnTests.Fixture(); await Start(f);
        var path = Path.Combine(f.Local.Root, "local-first-use-v1", "state.bin");
        var original = File.ReadAllBytes(path);
        File.WriteAllBytes(path, [1, 2, 3]); // Only this test's checked GUID subtree.
        var requests = f.Transport.Requests;
        Check((await Read(f)).State == "unavailable" && !f.Mode.HasConfirmedOnlineIdentity(3) &&
            f.Transport.Requests == requests && File.ReadAllBytes(path).SequenceEqual(new byte[] { 1, 2, 3 }),
            "Unknown identity storage isn't empty or permission to substitute server Handle.");
        File.WriteAllBytes(path, original); // Restore only our original synthetic bytes.
        f.Local.RequireLocalStateUnchanged();
    }
    private static async Task Expect(string code, Func<Task> work)
    {
        try { await work(); } catch (LocalFirstUseException error) when (error.Code == code) { return; }
        throw new InvalidOperationException("Expected " + code);
    }
}
