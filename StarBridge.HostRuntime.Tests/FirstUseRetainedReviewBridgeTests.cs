using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Onboarding;
using StarBridge.NativeBridge;

internal static partial class FirstUseBusinessOwnerTests
{
    private const string ReviewV2 = "onboarding.onlineReview.v2.";
    private static Task<BridgeDispatchBatch> ResumeWire(FirstUseOnlineReturnTests.Fixture f, string action,
        long? revision = null, string? key = null, int schema = 2)
    {
        var payload = new Dictionary<string, object?> { ["schemaVersion"] = schema };
        if (action != "read") payload["revision"] = revision ?? f.Store.Read().Revision;
        if (action == "confirm") payload["confirmationKey"] = key;
        return f.Local.Runtime.FirstUseOnlineReviewDispatcher!.DispatchAsync(BridgeEnvelope.Request(
            ReviewV2 + action, Id(), f.Mode.ControlGeneration, payload)).AsTask();
    }
    private static void RetainedWire(BridgeDispatchBatch batch, string mode, string identity)
    {
        Check(batch.Response.Status == BridgeResponseStatuses.Ok && batch.Response.AccountContext is null &&
            batch.Events.Count == 0 && batch.Response.Payload.GetProperty("schemaVersion").GetInt32() == 2 &&
            batch.Response.Payload.GetProperty("retainsSession").GetBoolean() &&
            batch.Response.Payload.GetProperty("modeState").GetString() == mode &&
            batch.Response.Payload.GetProperty("identity").GetProperty("state").GetString() == identity,
            "Versioned retained route returns display facts, not staged account authority.");
    }
    private static async Task RunRetainedReviewBridge()
    {
        await Case("v2 retained review crosses real refresh and identity owners without browser or activation", RetainedBridgeReview);
        await Case("v2 retained cancel waits actual held refresh and retains credentials", RetainedBridgeDrain);
        await Case("old and contradictory review wires cannot stage retained authentication", RetainedBridgeStrict);
        await Case("v2 resume cannot replace a fresh login with implicit credential restore", FreshBridgeNoResume);
    }
    private static async Task RetainedBridgeReview()
    {
        using var f = new Fixture(); f.Original.Clock.AllowTimers = true; await f.Start();
        await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime); await EnterOffline(f, native);
        var requests = f.Original.Transport.Requests; var first = f.Original.Candidate;
        var bytes = File.ReadAllBytes(f.Original.VaultPath);
        Check((await f.Original.Local.Runtime.FirstUseOnlineReviewDispatcher!.DispatchAsync(BridgeEnvelope.Request(
            ReviewV2 + "read", Id(), f.Original.Local.Runtime.Generation, new { schemaVersion = 2 }))).Response.Error?.Code == "firstUse.context_changed",
            "The retired root's lower generation cannot reuse current retained review control.");
        RetainedWire(await ResumeWire(f.Original, "read"), "offline", "notStarted");
        RetainedWire(await ResumeWire(f.Original, "begin"), "signInRequired", "signInRequired");
        Check(f.Original.Transport.Requests == requests && ReferenceEquals(first, f.Original.Candidate) &&
            bytes.SequenceEqual(File.ReadAllBytes(f.Original.VaultPath)), "Read/begin never refresh or change stored credentials.");
        var review = await ResumeWire(f.Original, "resume");
        RetainedWire(review, "signInRequired", "reviewRequired");
        Check(f.Original.Transport.LastGrant!.Contains("grant_type=refresh_token") && f.Original.BrowserOpens == 1 &&
            f.Original.Host!.BusinessStartupDeferred && f.Original.Mode.LocalMode().Active,
            "Resume explicitly refreshes a unique auth-only owner, with no second browser or online publication.");
        var key = review.Response.Payload.GetProperty("identity").GetProperty("confirmationKey").GetString();
        RetainedWire(await ResumeWire(f.Original, "confirm", key: key), "signInRequired", "confirmedForHandoff");
        var wire = review.Response.Payload.GetRawText();
        foreach (var secret in new[] { "synthetic-subject", "synthetic-access", "synthetic-refresh", f.Original.Local.Root })
            Check(!wire.Contains(secret, StringComparison.Ordinal), "Retained projection cannot expose private owner/session/storage facts.");
        RetainedWire(await ResumeWire(f.Original, "cancel"), "offline", "notStarted");
        Check(f.Original.Transport.Revokes == 0 && f.Original.Vault.LoadActiveAccountKey() is not null &&
            f.Original.Mode.LocalMode().Active, "Review confirmation remains separate from installation and cancel preserves sign-in.");
    }
    private static async Task RetainedBridgeDrain()
    {
        using var f = new Fixture(); f.Original.Clock.AllowTimers = true; await f.Start();
        await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime); await EnterOffline(f, native);
        await ResumeWire(f.Original, "begin"); f.Original.Transport.HoldToken = true;
        var bytes = File.ReadAllBytes(f.Original.VaultPath);
        var resume = ResumeWire(f.Original, "resume"); await WaitRefresh(f);
        var cancel = ResumeWire(f.Original, "cancel");
        try
        {
            Check(!cancel.IsCompleted, "Bridge cancellation waits the actual original refresh request.");
            f.Original.Transport.ReleaseToken.TrySetResult();
            var late = await Finish(resume);
            Check(late.Response.Status != BridgeResponseStatuses.Ok ||
                late.Response.Payload.GetProperty("identity").GetProperty("state").GetString() == "contextChanged" &&
                late.Response.Payload.GetProperty("identity").GetProperty("confirmationKey").ValueKind == System.Text.Json.JsonValueKind.Null,
                "Late resume can report lost context, never publish a stale review.");
            RetainedWire(await Finish(cancel), "offline", "notStarted");
        }
        finally
        {
            f.Original.Transport.ReleaseToken.TrySetResult();
            await Finish(resume); await Finish(cancel);
        }
        Check(bytes.SequenceEqual(File.ReadAllBytes(f.Original.VaultPath)) && f.Original.Transport.Revokes == 0 &&
            f.Original.Mode.LocalMode().Active, "Actual cancellation retains original credential and local readiness.");
    }
    private static async Task RetainedBridgeStrict()
    {
        using var f = new Fixture(); f.Original.Clock.AllowTimers = true; await f.Start();
        await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime); await EnterOffline(f, native);
        var before = f.Original.Transport.Requests; var first = f.Original.Candidate;
        var old = await f.Original.Local.Runtime.FirstUseOnlineReviewDispatcher!.DispatchAsync(BridgeEnvelope.Request(
            FirstUseOnlineReviewBridgeDispatcher.ReadRequest, Id(), f.Original.Local.Runtime.Generation, new { schemaVersion = 1 }));
        Check(old.Response.Status != BridgeResponseStatuses.Ok, "v1 cannot reinterpret offline as browser login.");
        Check((await ResumeWire(f.Original, "begin", schema: 1)).Response.Status != BridgeResponseStatuses.Ok &&
            (await ResumeWire(f.Original, "begin", revision: 5)).Response.Status != BridgeResponseStatuses.Ok,
            "v2 requires its exact schema and current mode revision.");
        await ResumeWire(f.Original, "begin");
        Check((await ResumeWire(f.Original, "login")).Response.Status != BridgeResponseStatuses.Ok &&
            (await ResumeWire(f.Original, "resumeAnything")).Response.Status != BridgeResponseStatuses.Ok &&
            ReferenceEquals(first, f.Original.Candidate) && f.Original.Transport.Requests == before,
            "Wrong action cannot construct or authenticate a retained candidate.");
        RetainedWire(await ResumeWire(f.Original, "cancel"), "offline", "notStarted");
    }
    private static async Task FreshBridgeNoResume()
    {
        using var f = new FirstUseOnlineReturnTests.Fixture(); await f.Prepare();
        var begun = await ResumeWire(f, "begin");
        Check(begun.Response.Status == BridgeResponseStatuses.Ok &&
            !begun.Response.Payload.GetProperty("retainsSession").GetBoolean(), "v2 preserves the explicit fresh-login route.");
        Check((await ResumeWire(f, "resume")).Response.Status != BridgeResponseStatuses.Ok &&
            f.Candidate is null && f.Transport.Requests == 0, "Fresh selection cannot restore an unrelated prior credential.");
        Check((await ResumeWire(f, "login")).Response.Payload.GetProperty("identity").GetProperty("state").GetString() == "reviewRequired" &&
            f.BrowserOpens == 1 && f.Transport.LastGrant!.Contains("grant_type=authorization_code"), "Fresh v2 login still uses real explicit PKCE.");
        Check((await ResumeWire(f, "cancel")).Response.Payload.GetProperty("modeState").GetString() == "local" &&
            f.Vault.LoadActiveAccountKey() is null, "Fresh v2 cancellation retains its strict credential cleanup.");
    }
}
