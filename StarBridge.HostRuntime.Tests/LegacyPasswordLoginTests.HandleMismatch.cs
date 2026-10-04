using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;
using StarBridge.Core.Identity;

internal static partial class LegacyPasswordLoginTests
{
    internal static async Task HandleMismatchProjection()
    {
        using var transport = new Transport { Body = Transport.Valid.TrimEnd('}') +
            ",\"gameName\":\"Pilot_Alpha\",\"identityBindingRequired\":true}" };
        using var client = new LegacyPasswordLoginClient(new Uri("https://example.invalid/"), new Store(), transport);
        string? observed = "Pilot-Alpha";
        using var host = new ScmAccountBridgeHost(
            new OAuthPkceClient(new ScmHttpClient(), new Vault(), ScmOAuthOptions.CreateDefault()),
            new ScmProfileCacheStore(), "development", () => observed, legacyPasswordLogin: client,
            lastGameIdentityCheck: () => LocalIdentityCheckState.Mismatch);
        using var runtime = new AccountBridgeRuntime(host);
        await host.LoginLegacyAsync(BridgePayload.From(new { schemaVersion = 1, email = "old@example.invalid", password = "synthetic" }), 0, default);
        var response = await runtime.DispatchAsync(BridgeEnvelope.Request("gameIdentity.getPolicy", "handle-difference",
            host.Generation, new { schemaVersion = 1 }, host.CurrentContext));
        Check(response.Response.Status == "ok", "identity policy must be readable");
        var value = response.Response.Payload;
        Check(value.GetProperty("state").GetString() == "mismatch", "underscore and hyphen remain distinct");
        Check(!value.GetProperty("sensitiveWritesAllowed").GetBoolean(), "mismatch must keep sensitive writes blocked");
        Check(value.TryGetProperty("detectedHandle", out var detected) && detected.GetString() == "Pilot-Alpha",
            "mismatch policy must expose the current observed Handle for a persistent actionable comparison");
        Check(value.TryGetProperty("scmBindingState", out var binding) && binding.GetString() == "unknown",
            "legacy login alone must not be described as definitively SCM unbound");
        Check(value.GetProperty("authoritativeHandle").GetString() == "Pilot_Alpha", "observation does not overwrite the account");
        var notificationPolicy = await runtime.ReadGameIdentityNotificationPolicyAsync(host.CurrentContext!, default);
        Check(runtime.IsGameIdentityNotificationCurrent(host.CurrentContext!, notificationPolicy),
            "the real account owner validates its current mismatch without I/O");
        Check(!runtime.IsGameIdentityNotificationCurrent(host.CurrentContext! with { Subject = "other-synthetic" }, notificationPolicy),
            "synchronous presentation checks reject a different account owner");
        var preparation = await runtime.DispatchAsync(BridgeEnvelope.Request("gameIdentity.prepareHandleChange", "handle-prepare",
            host.Generation, new { schemaVersion = 1 }, host.CurrentContext));
        Check(preparation.Response.Status == "ok" && preparation.Response.Payload.GetProperty("state").GetString() == "ready",
            "compatibility legacy mismatch must offer an explicit confirmation without requiring SCM integration");
        Check(preparation.Response.Payload.GetProperty("mode").GetString() == "legacyCompatibility" &&
            preparation.Response.Payload.GetProperty("scmBindingState").GetString() == "unknown" &&
            preparation.Response.Payload.GetProperty("confirmationId").GetString()?.Length == 32,
            "legacy-only ticket is not a claim of authoritative SCM unbound status");
        var read = BridgeEnvelope.Request("gameIdentity.prepareHandleChange", "handling-repeat",
            host.Generation, new { schemaVersion = 1 }, host.CurrentContext);
        foreach (var invalid in new[] {
            read with { SessionGeneration = host.Generation - 1 },
            read with { AccountContext = null },
            read with { AccountContext = host.CurrentContext! with { Subject = "other-synthetic" } },
            read with { Payload = BridgePayload.From(new { schemaVersion = 1, gameName = "Forged-Handle" }) },
            read with { Payload = BridgePayload.From(new { schemaVersion = 1, scmBindingState = "unbound" }) }
        }) Check((await runtime.DispatchAsync(invalid)).Response.Status == "error", "stale, wrong-owner and client-supplied authority are rejected");
        using (var duplicate = System.Text.Json.JsonDocument.Parse("{\"schemaVersion\":1,\"schemaVersion\":1}"))
            Check((await runtime.DispatchAsync(read with { Payload = duplicate.RootElement })).Response.Status == "error", "duplicate fields rejected");
        Check((await runtime.DispatchAsync(read with { Name = "gameIdentity.confirmHandleChange" })).Response.Status == "error",
            "confirmation without a Host-issued opaque ticket is rejected");
        observed = null;
        Check(!runtime.IsGameIdentityNotificationCurrent(host.CurrentContext!, notificationPolicy),
            "loss of current game observation immediately revokes the old desktop card");
        var stopped = await host.GetGameIdentityPolicyAsync(host.CurrentContext!, default);
        Check(stopped.State == "mismatch" && !stopped.SensitiveWritesAllowed && stopped.DetectedHandle is null,
            "game exit does not erase persisted mismatch or reuse a stale Handle");
        var waiting = await runtime.DispatchAsync(read);
        Check(waiting.Response.Payload.GetProperty("state").GetString() == "observationRequired", "handling requires a fresh observation");
        observed = "PILOT_ALPHA";
        Check(!runtime.IsGameIdentityNotificationCurrent(host.CurrentContext!, notificationPolicy),
            "a recovered game identity revokes the old desktop card before another bridge poll");
        var matching = await runtime.DispatchAsync(read);
        Check(matching.Response.Payload.GetProperty("state").GetString() == "consistent", "only an exact case-insensitive match resolves the mismatch");
        Check(host.HangarIdentity?.Identity.Handle == "Pilot_Alpha", "no read or dismissal renames the account");
        Check(transport.Calls >= 1, "synthetic authenticated preflight completed without account writes");
        using var scm = new ScmAccountBridgeHost(
            new OAuthPkceClient(new ScmHttpClient(), new Vault(), ScmOAuthOptions.CreateDefault()),
            new ScmProfileCacheStore(), "development", () => "Pilot-Alpha",
            initialSession: new ScmOAuthSession("synthetic-scm", "subject", "Synthetic", "synthetic-token",
                DateTimeOffset.UtcNow.AddHours(1), [], GameIdentityVerified: true, GameIdentityHandle: "Pilot_Alpha"));
        var scmPolicy = await scm.GetGameIdentityPolicyAsync(scm.CurrentContext!, default);
        Check(scmPolicy.State == "mismatch" && scmPolicy.ScmBindingState == "unknown" && !scmPolicy.SensitiveWritesAllowed,
            "an SCM session is identity authority, not reverse legacy-link proof");
        Console.WriteLine("PASS Handle mismatch projection and legacy-only compatibility preparation");
    }
}
