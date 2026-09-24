using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.LegacyRelay;
using StarBridge.Core.Profiles;
using StarBridge.NativeBridge;

internal static class S2CompatibilityReadTests
{
    internal static async Task Verify()
    {
        var session = new ScmOAuthSession("scm-development", "synthetic", "Synthetic",
            "synthetic-bearer", DateTimeOffset.UtcNow.AddMinutes(5), []);
        foreach (var state in new[] { LegacyRelayAccessState.Ready, LegacyRelayAccessState.AccountMismatch,
                     LegacyRelayAccessState.AuthorizationRequired, LegacyRelayAccessState.Unavailable })
        {
            var coordinator = new Coordinator(); var relay = new Relay { State = state };
            using var reader = new S2CompatibilityReader(coordinator, relay);
            using var host = Host(session, reader);
            var result = await host.GetCompatibilityStateAsync(host.CurrentContext!, default);
            Check(result.LegacyFeaturesAvailable == (state == LegacyRelayAccessState.Ready), "lease state");
            Check(ReferenceEquals(relay.Session, session), "same SCM session must reach Relay");
            Check(!result.AvailableActions.Contains("createCompatibilityIdentity"), "no provisioning");
            Check(coordinator.Writes == 0, "read must not mutate identity");
        }
        {
            var coordinator = new Coordinator { Linked = false }; var relay = new Relay();
            using var reader = new S2CompatibilityReader(coordinator, relay);
            using var host = Host(session, reader);
            using var runtime = new AccountBridgeRuntime(host);
            var result = await runtime.DispatchAsync(BridgeEnvelope.Request("account.getCompatibilityState",
                "s2-read", host.Generation, new { schemaVersion = 1 }, host.CurrentContext));
            Check(result.Response.Status == BridgeResponseStatuses.Ok, "runtime read route");
            Check(relay.Calls == 0, "unlinked account cannot establish Relay identity");
            Check(!result.Response.Payload.TryGetProperty("legacyAccountId", out _), "internal ID stays in Host");
            Check(result.Response.Payload.GetProperty("availableActions").GetArrayLength() == 1, "existing-account action only");
            foreach (var name in new[] { "account.createCompatibilityIdentity" })
            {
                var denied = await runtime.DispatchAsync(BridgeEnvelope.Request(name, name,
                    host.Generation, new { schemaVersion = 1 }, host.CurrentContext));
                Check(denied.Response.Error?.Code == BridgeErrorCodes.CapabilityUnavailable, "writes stay closed");
            }
        }
        {
            var coordinator = new Coordinator { Failure = true };
            using var reader = new S2CompatibilityReader(coordinator, new Relay());
            using var host = Host(session, reader);
            try { await host.GetCompatibilityStateAsync(host.CurrentContext!, default); throw new Exception("Missing failure"); }
            catch (AccountBridgeHostException e) { Check(e.Code == AccountBridgeStableErrors.CompatibilityReadUnavailable, "local failure"); }
            Check(host.CurrentContext is not null, "SCM context survives compatibility outage");
        }
        {
            var coordinator = new Coordinator { Pending = new(TaskCreationOptions.RunContinuationsAsynchronously) };
            using var reader = new S2CompatibilityReader(coordinator, new Relay());
            using var host = Host(session, reader);
            var pending = host.GetCompatibilityStateAsync(host.CurrentContext!, default);
            host.Dispose();
            coordinator.Pending.SetResult(Coordinator.LinkedProjection);
            try { await pending; throw new Exception("Late response escaped"); }
            catch (AccountBridgeHostException) { }
        }
    }
    private static ScmAccountBridgeHost Host(ScmOAuthSession session, S2CompatibilityReader reader) => new(
        new OAuthPkceClient(new ScmHttpClient(), new Vault(), ScmOAuthOptions.CreateDefault()),
        new ScmProfileCacheStore(), "development", () => null, initialSession: session, compatibilityReader: reader);
    private static void Check(bool ok, string message) { if (!ok) throw new Exception(message); }
    private sealed class Vault : ITokenVault
    {
        public void SaveRefreshToken(string a, string b) => throw new Exception("Unexpected write");
        public string? LoadRefreshToken(string a) => null;
        public string? LoadActiveAccountKey() => null;
        public void DeleteRefreshToken(string a) => throw new Exception("Unexpected delete");
    }
    private sealed class Coordinator : IAccountCompatibilityCoordinator
    {
        internal static AccountBridgeCompatibilityProjection LinkedProjection => new("linked", "notEstablished", false, false, [], "synthetic-legacy");
        internal bool Linked = true, Failure;
        internal int Writes;
        internal TaskCompletionSource<AccountBridgeCompatibilityProjection>? Pending;
        public Task<AccountBridgeCompatibilityProjection> ReadAsync(ScmOAuthSession s, CancellationToken t) =>
            Failure ? Task.FromException<AccountBridgeCompatibilityProjection>(new HttpRequestException()) :
            Pending?.Task ?? Task.FromResult(Linked ? LinkedProjection : new("unlinked", "notApplicable", false, false,
                ["linkExistingAccount", "createCompatibilityIdentity"], null));
        public Task<AccountBridgeCompatibilityProjection> LinkExistingAsync(ScmOAuthSession s, LegacyIdentityLinkPasswordCredential? c, CancellationToken t)
        { Writes++; throw new Exception("Unexpected link"); }
        public Task<AccountBridgeCompatibilityProjection> CreateCompatibilityIdentityAsync(ScmOAuthSession s, CancellationToken t)
        { Writes++; throw new Exception("Unexpected provision"); }
    }
    private sealed class Relay : ILegacyRelayAccountPort
    {
        internal LegacyRelayAccessState State = LegacyRelayAccessState.Ready;
        internal int Calls; internal ScmOAuthSession? Session;
        public Task<LegacyRelayAccessState> EstablishAsync(ScmOAuthSession s, string id, CancellationToken t)
        { t.ThrowIfCancellationRequested(); Calls++; Session = s; return Task.FromResult(State); }
        public Task<LegacyRelayProfileReadResult> ReadOwnProfileAsync(ScmOAuthSession s, string id, CancellationToken t) => throw new Exception("Unexpected profile read");
        public void Reset() { }
    }
}
