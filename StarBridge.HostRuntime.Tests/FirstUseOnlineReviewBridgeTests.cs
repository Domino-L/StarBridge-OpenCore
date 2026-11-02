using System.Text.Json;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Onboarding;
using StarBridge.HostRuntime.Settings;
using StarBridge.NativeBridge;

internal static class FirstUseOnlineReviewBridgeTests
{
    private static string Id() => Guid.NewGuid().ToString("N");
    private static void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
    private static async Task Case(string name, Func<Task> work)
    { await work(); Console.WriteLine("PASS first-use online review bridge: " + name); }
    private static Task<BridgeDispatchBatch> Send(FirstUseOnlineReturnTests.Fixture f, string name,
        object? payload = null, long? generation = null) => f.Local.Runtime.FirstUseOnlineReviewDispatcher!
        .DispatchAsync(BridgeEnvelope.Request(name, Id(), generation ?? f.Local.Runtime.Generation,
            payload ?? new { schemaVersion = 1 })).AsTask();
    private static JsonElement Identity(BridgeDispatchBatch batch)
    {
        Check(batch.Response.Status == BridgeResponseStatuses.Ok && batch.Response.AccountContext is null && batch.Events.Count == 0,
            "Subset returns only installed-generation display facts, never staged account context or events.");
        return batch.Response.Payload.GetProperty("identity");
    }
    private static async Task Begin(FirstUseOnlineReturnTests.Fixture f)
    {
        await f.Prepare();
        var result = await Send(f, FirstUseOnlineReviewBridgeDispatcher.BeginRequest, new { schemaVersion = 1, revision = 2 });
        Check(result.Response.Payload.GetProperty("revision").GetInt64() == 3 &&
            Identity(result).GetProperty("state").GetString() == "signInRequired", "Explicit local selection creates pending intent only.");
    }
    private static async Task<JsonElement> Login(FirstUseOnlineReturnTests.Fixture f)
    {
        var result = await Send(f, FirstUseOnlineReviewBridgeDispatcher.LoginRequest, new { schemaVersion = 1, revision = 3 });
        if (f.Callback is not null) await f.Callback.WaitAsync(TimeSpan.FromSeconds(3));
        return Identity(result);
    }
    internal static async Task Run()
    {
        await Case("side-effect-free reads never start authentication or restore a previous credential", Read);
        await Case("real PKCE login, review, polling and confirmation keep the installed local owner", Matching);
        await Case("strict wire rejects stale revisions, generations, contexts and invented actions", Strict);
        await Case("fresh confirmation observes actual revocation and never grants online completion", Revoked);
        await Case("cancel waits for actual OAuth exit and preserves independent local data", Drain);
        await Case("cold started candidates expose recovery, not a fresh-login or cleanup receipt", Cold);
        await Case("a replaced login invalidates previous review before authorization begins", ReplacedLogin);
        await Case("real Composite routing retains device preferences and sanitizes display-only facts", Composite);
    }
    private static async Task Read()
    {
        using var f = new FirstUseOnlineReturnTests.Fixture(); await f.Prepare();
        f.Vault.SaveRefreshToken("synthetic-prior:owner", "synthetic-prior-refresh"); var before = File.ReadAllBytes(f.VaultPath);
        var read = await Send(f, FirstUseOnlineReviewBridgeDispatcher.ReadRequest);
        Check(Identity(read).GetProperty("state").GetString() == "notStarted" && f.Candidate is null &&
            f.Transport.Requests == 0 && File.ReadAllBytes(f.VaultPath).SequenceEqual(before), "Read is not a mode change or authorization.");
        f.Local.RequireLocalStateUnchanged();
    }
    private static async Task Matching()
    {
        using var f = new FirstUseOnlineReturnTests.Fixture(); await Begin(f);
        var generation = f.Local.Runtime.Generation; var localMode = f.Mode.LocalMode();
        var identity = await Login(f); var key = identity.GetProperty("confirmationKey").GetString();
        Check(identity.GetProperty("state").GetString() == "reviewRequired" && key is not null &&
            f.Transport.IdentityRequests == 2 && f.Candidate!.Generation > generation, "Login uses actual staged PKCE, then a fresh identity read.");
        var poll = Identity(await Send(f, FirstUseOnlineReviewBridgeDispatcher.ReadRequest));
        Check(poll.GetProperty("confirmationKey").GetString() == key && f.Transport.IdentityRequests == 2,
            "Polling does not consume, replace, refresh or silently accept a review.");
        var confirmation = Identity(await Send(f, FirstUseOnlineReviewBridgeDispatcher.ConfirmRequest,
            new { schemaVersion = 1, revision = 3, confirmationKey = key }));
        Check(confirmation.GetProperty("state").GetString() == "confirmedForHandoff" &&
            f.Mode.HasConfirmedOnlineIdentity(3) && f.Local.Runtime.Generation == generation && f.Mode.LocalMode() == localMode &&
            f.Store.Read().Phase == "onlinePending" && f.Clock.Timers == 0 && f.Transport.IdentityRequests == 3,
            "Identity confirmation never activates consumers, merges profiles or completes the guide.");
        var duplicate = await Send(f, FirstUseOnlineReviewBridgeDispatcher.ConfirmRequest,
            new { schemaVersion = 1, revision = 3, confirmationKey = key });
        Check(duplicate.Response.Status != BridgeResponseStatuses.Ok, "Consumed review keys are not completion receipts.");
        f.Local.RequireLocalStateUnchanged();
    }
    private static async Task Strict()
    {
        using var f = new FirstUseOnlineReturnTests.Fixture(); await f.Prepare();
        var dispatcher = f.Local.Runtime.FirstUseOnlineReviewDispatcher!;
        var generation = f.Local.Runtime.Generation;
        foreach (var request in new[] {
            BridgeEnvelope.Request(FirstUseOnlineReviewBridgeDispatcher.ReadRequest, Id(), generation, new { schemaVersion = 1, token = "private" }),
            BridgeEnvelope.Request(FirstUseOnlineReviewBridgeDispatcher.ReadRequest, Id(), generation, new { schemaVersion = true }),
            BridgeEnvelope.Request(FirstUseOnlineReviewBridgeDispatcher.ReadRequest, Id(), generation, JsonDocument.Parse("{\"schemaVersion\":1,\"schemaVersion\":1}").RootElement),
            BridgeEnvelope.Request(FirstUseOnlineReviewBridgeDispatcher.BeginRequest, Id(), generation, new { schemaVersion = 1, revision = 1 }),
            BridgeEnvelope.Request(FirstUseOnlineReviewBridgeDispatcher.LoginRequest, Id(), generation, new { schemaVersion = 1, revision = 2 }),
            BridgeEnvelope.Request(FirstUseOnlineReviewBridgeDispatcher.ReadRequest, Id(), generation + 1, new { schemaVersion = 1 }),
            BridgeEnvelope.Request(FirstUseOnlineReviewBridgeDispatcher.ReadRequest, Id(), generation, new { schemaVersion = 1 }, new("private", "private", "private")),
            BridgeEnvelope.Request("onboarding.onlineReview.finish", Id(), generation, new { schemaVersion = 1 }),
        }) {
            var result = await dispatcher.DispatchAsync(request);
            Check(result.Response.Status != BridgeResponseStatuses.Ok && result.Response.AccountContext is null,
                "Malformed/stale/uninstalled account requests must not leak context or create a candidate.");
        }
        Check(f.Store.Read().Phase == "local" && f.Transport.Requests == 0 && f.Candidate is null,
            "Rejected envelopes never mutate mode or authenticate.");
    }
    private static async Task Revoked()
    {
        using var f = new FirstUseOnlineReturnTests.Fixture();
        f.Transport.Capabilities = ["profile.read", "game_identity.verify"];
        await Begin(f); var identity = await Login(f);
        f.Transport.IdentityStatus = "REVOKED"; f.Transport.IdentityVerified = false;
        var result = Identity(await Send(f, FirstUseOnlineReviewBridgeDispatcher.ConfirmRequest,
            new { schemaVersion = 1, revision = 3, confirmationKey = identity.GetProperty("confirmationKey").GetString() }));
        Check(result.GetProperty("state").GetString() == "revoked" && !f.Mode.HasConfirmedOnlineIdentity(3) &&
            f.Transport.IdentityRequests == 3 && f.Mode.LocalMode().Active && f.Clock.Timers == 0,
            "Revocation is read from original OAuth owner, not inferred from the login snapshot.");
    }
    private static async Task Drain()
    {
        using var f = new FirstUseOnlineReturnTests.Fixture(); await Begin(f); f.Transport.HoldToken = true;
        var login = Send(f, FirstUseOnlineReviewBridgeDispatcher.LoginRequest, new { schemaVersion = 1, revision = 3 });
        await f.Transport.TokenEntered.Task.WaitAsync(TimeSpan.FromSeconds(3));
        var cancel = Send(f, FirstUseOnlineReviewBridgeDispatcher.CancelRequest, new { schemaVersion = 1, revision = 3 });
        Check(!cancel.IsCompleted && f.Mode.LocalMode().Active && f.Store.Read().Phase == "onlinePending",
            "Cancellation requested is not actual OAuth exit.");
        f.Transport.ReleaseToken.TrySetResult();
        Check((await login.WaitAsync(TimeSpan.FromSeconds(3))).Response.Status != BridgeResponseStatuses.Ok,
            "The retired login must not publish late success.");
        var returned = await cancel.WaitAsync(TimeSpan.FromSeconds(3));
        Check(returned.Response.Payload.GetProperty("modeState").GetString() == "local" &&
            Identity(returned).GetProperty("state").GetString() == "notStarted" && f.Store.Read().Phase == "local" &&
            f.Clock.Timers == 0, "Only original candidate cleanup can acknowledge local return.");
        f.Local.RequireLocalStateUnchanged();
    }
    private static async Task Cold()
    {
        using var f = new FirstUseOnlineReturnTests.Fixture(); await Begin(f); await f.Stage();
        using var cold = await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Local.Root,
            _ => throw new InvalidOperationException("Cold review must not restore authentication."));
        var request = BridgeEnvelope.Request(FirstUseOnlineReviewBridgeDispatcher.ReadRequest, Id(), cold.Generation, new { schemaVersion = 1 });
        var read = Identity(await cold.FirstUseOnlineReviewDispatcher!.DispatchAsync(request));
        Check(read.GetProperty("state").GetString() == "recoveryRequired" && f.Transport.Requests == 0,
            "A lost started owner cannot be replaced or claimed as cleaned up.");
        var cancel = await cold.FirstUseOnlineReviewDispatcher.DispatchAsync(BridgeEnvelope.Request(
            FirstUseOnlineReviewBridgeDispatcher.CancelRequest, Id(), cold.Generation, new { schemaVersion = 1, revision = 3 }));
        Check(cancel.Response.Payload.GetProperty("modeState").GetString() == "recoveryRequired" &&
            Identity(cancel).GetProperty("state").GetString() == "recoveryRequired" && f.Store.Read().Phase == "onlinePending",
            "Recovery failures cannot be overwritten by the ordinary pending-mode projection.");
    }
    private static async Task ReplacedLogin()
    {
        using var f = new FirstUseOnlineReturnTests.Fixture(); await Begin(f); var review = await Login(f);
        Identity(await Send(f, FirstUseOnlineReviewBridgeDispatcher.ConfirmRequest,
            new { schemaVersion = 1, revision = 3, confirmationKey = review.GetProperty("confirmationKey").GetString() }));
        Check(f.Mode.HasConfirmedOnlineIdentity(3), "Initial identity precondition must be real.");
        f.Transport.HoldToken = true;
        var replacement = Send(f, FirstUseOnlineReviewBridgeDispatcher.LoginRequest, new { schemaVersion = 1, revision = 3 });
        await f.Transport.TokenEntered.Task.WaitAsync(TimeSpan.FromSeconds(3));
        var poll = Identity(await Send(f, FirstUseOnlineReviewBridgeDispatcher.ReadRequest));
        Check(!f.Mode.HasConfirmedOnlineIdentity(3) && poll.GetProperty("state").GetString() == "authorizing" &&
            poll.GetProperty("confirmationKey").ValueKind == JsonValueKind.Null, "Replacement clears prior proof before its real auth transport.");
        f.Transport.ReleaseToken.TrySetResult(); await replacement.WaitAsync(TimeSpan.FromSeconds(3));
        Check(!f.Mode.HasConfirmedOnlineIdentity(3), "New authorization requires another explicit review, never reuses the old confirmation.");
    }
    private static async Task Composite()
    {
        using var f = new FirstUseOnlineReturnTests.Fixture(); await f.Prepare();
        using var prefs = new ApplicationPreferencesBridgeDispatcher(f.Local.Root, () => f.Local.Runtime.Generation);
        using var lifecycle = new HostBridgeDispatcher(Id(), () => f.Local.Runtime.Generation, []);
        using var composite = new CompositeBridgeDispatcher(lifecycle, f.Local.Runtime, prefs,
            firstUseOnlineReview: f.Local.Runtime.FirstUseOnlineReviewDispatcher);
        var read = await composite.DispatchAsync(BridgeEnvelope.Request(FirstUseOnlineReviewBridgeDispatcher.ReadRequest,
            Id(), f.Local.Runtime.Generation, new { schemaVersion = 1 })); Identity(read);
        var device = await composite.DispatchAsync(BridgeEnvelope.Request(ApplicationPreferencesRequestNames.Get,
            Id(), f.Local.Runtime.Generation, new { schemaVersion = 1 }));
        Check(device.Response.Status == BridgeResponseStatuses.Ok, "Narrow routing preserves existing device functions.");
        f.Mode.RequestOnline(2, Id()); f.Transport.DisplayName = "Synthetic\nPilot";
        var identity = await Login(f);
        Check(identity.GetProperty("accountDisplayName").ValueKind == JsonValueKind.Null, "Unbounded/control display text stays off this narrow wire.");
        var wire = identity.GetRawText();
        foreach (var secret in new[] { "synthetic-subject", "synthetic-access", "synthetic-refresh", f.Local.Root })
            Check(!wire.Contains(secret, StringComparison.Ordinal), "Tokens, subjects and filesystem paths must not appear in display projections.");
    }
}
