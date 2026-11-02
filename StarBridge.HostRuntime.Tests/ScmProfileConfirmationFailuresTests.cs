using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;

internal static partial class LegacyPasswordLoginTests
{
    // SCM avatar writes no longer exist (RSI avatar policy); only callsign writes are confirmed here.
    private static async Task ProfileConfirmationReauthorization()
    {
        using var transport = new ScmCallSignTransport { ConfirmationMode = "unauthorized" };
        var uri = new Uri("http://127.0.0.1:9/");
        var oauth = new OAuthPkceClient(new ScmHttpClient(transport), new ScmBackgroundVault(),
            new("synthetic", uri, uri, uri, "synthetic", "synthetic", "openid profile.read", "/callback"));
        using var host = new ScmAccountBridgeHost(oauth, new ScmProfileCacheStore(), "integration", () => null,
            initialSession: new("synthetic", "owner", "Pilot", "synthetic-read-token",
                DateTimeOffset.MaxValue, ["profile.read"]), profileAuthorization: new ScmBackgroundAuthorization());
        using var dispatcher = new AccountBridgeDispatcher(host);
        var generation = host.Generation;
        var request = BridgeEnvelope.Request("account.updateCallSign", "confirmation-401", generation,
            new { schemaVersion = 1, expectedCallSign = "Inherited", callSign = "Unconfirmed" }, host.CurrentContext);
        var result = await dispatcher.DispatchAsync(request);
        Check(result.Response.Error?.Code == "account.callsign_unconfirmed" && transport.Writes == 1,
            "post-write 401 cannot claim a confirmed mutation or replay it");
        Check(result.Events.Count == 0 && host.Generation == generation && host.CurrentContext is not null,
            "post-write resource 401 preserves the session without claiming mutation confirmation");
        var repeated = await dispatcher.DispatchAsync(request);
        Check(repeated.Response.Error is not null && transport.Writes == 1,
            "unconfirmed request cannot replay the mutation");
    }
}
