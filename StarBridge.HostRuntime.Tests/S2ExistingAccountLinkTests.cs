using System.Net;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.LegacyRelay;
using StarBridge.NativeBridge;

internal static class S2ExistingAccountLinkTests
{
    private static readonly ScmOAuthSession Session = new("scm-development", "synthetic", "Synthetic",
        "synthetic-bearer", DateTimeOffset.UtcNow.AddMinutes(5), []);
    private static readonly AccountBridgeLegacyCredential Credential = new("chosen@example.invalid", " synthetic password ");

    internal static async Task Verify()
    {
        // Existing WPF callers omit the new option: their saved-credential flow remains unchanged.
        using (var fixture = new Fixture())
        {
            fixture.Store.AccountId = "chosen-legacy";
            fixture.Store.AllowDelete = true;
            fixture.Links.AllowStored = true;
            var result = await new IdentityLinkCoordinator(fixture.Authorization, fixture.Links, fixture.Store)
                .EnsureLinkedAsync(Session, default);
            Check(result.Outcome == IdentityLinkOutcome.Linked && fixture.Store.Deletes == 1, "WPF default still clears confirmed migration credential");
            Check(fixture.Links.PasswordProofs == 0, "WPF stored-credential path does not require a new password");
        }
        using (var fixture = new Fixture())
        {
            using var runtime = new AccountBridgeRuntime(fixture.Host);
            var response = (await runtime.DispatchAsync(BridgeEnvelope.Request("account.linkLegacyAccount", "link",
                fixture.Host.Generation, new { schemaVersion = 1, credential = new { accountName = Credential.AccountName, password = Credential.Password } },
                fixture.Host.CurrentContext))).Response;
            Check(response.Status == BridgeResponseStatuses.Ok, "existing link route");
            Check(response.Payload.GetProperty("legacyFeaturesAvailable").GetBoolean(), "verified Relay lease");
            Check(!response.Payload.TryGetProperty("legacyAccountId", out _), "internal identity stays in Host");
            Check(fixture.Links.PasswordProofs == 1 && fixture.Links.Consumes == 1 && fixture.Relay.Calls == 1, "reused proof/consume/lease chain");
            Check(fixture.Links.Password == Credential.Password, "password must not be trimmed");
            Check(fixture.Store.Deletes == 0 && fixture.Store.Saves == 0, "manual proof leaves stored credentials untouched");
            Check(fixture.Host.Generation == 0 && fixture.Host.CurrentContext?.Subject == Session.Subject, "link does not replace SCM login");
            var denied = await runtime.DispatchAsync(BridgeEnvelope.Request("account.createCompatibilityIdentity", "provision",
                fixture.Host.Generation, new { schemaVersion = 1 }, fixture.Host.CurrentContext));
            Check(denied.Response.Error?.Code == BridgeErrorCodes.CapabilityUnavailable, "provisioning remains closed");
        }
        foreach (var failure in new[] { "password", "conflict", "unconfirmed" })
        {
            using var fixture = new Fixture();
            fixture.Links.Failure = failure;
            await ExpectFailure(fixture.Host.LinkLegacyAccountAsync(fixture.Host.CurrentContext!, Credential, default), failure switch
            {
                "password" => AccountBridgeStableErrors.LegacyCredentialsRejected,
                "conflict" => AccountBridgeStableErrors.CompatibilityConflict,
                _ => AccountBridgeStableErrors.CompatibilityWriteUnavailable
            });
            Check(fixture.Host.CurrentContext is not null && fixture.Relay.Calls == 0, "failure retains SCM and never grants Relay access");
            Check(fixture.Store.Deletes == 0, "failure keeps stored credential");
        }
        using (var fixture = new Fixture())
        {
            await ExpectFailure(fixture.Host.LinkLegacyAccountAsync(fixture.Host.CurrentContext!, null, default),
                AccountBridgeStableErrors.LegacyCredentialsRequired);
            Check(fixture.Links.PasswordProofs == 0 && fixture.Authorization.Calls == 0, "missing credential does not open authorization");
        }
        using (var fixture = new Fixture())
        {
            fixture.Authorization.Wait = true;
            using var cancellation = new CancellationTokenSource();
            var pending = fixture.Host.LinkLegacyAccountAsync(fixture.Host.CurrentContext!, Credential, cancellation.Token);
            await fixture.Authorization.Started.Task;
            await ExpectFailure(fixture.Host.LinkLegacyAccountAsync(fixture.Host.CurrentContext!, Credential, default),
                AccountBridgeStableErrors.OperationInProgress);
            cancellation.Cancel();
            try { await pending; throw new Exception("Cancellation ignored"); }
            catch (OperationCanceledException) { }
            Check(fixture.Links.Consumes == 0, "cancelled authorization never consumes a proof");
            fixture.Authorization.Wait = false;
            var retried = await fixture.Host.LinkLegacyAccountAsync(fixture.Host.CurrentContext!, Credential, default);
            Check(retried.IdentityState == "linked", "cancel releases the mutation gate for retry");
        }
        using (var fixture = new Fixture())
        {
            fixture.Authorization.Wait = true;
            var pending = fixture.Host.LinkLegacyAccountAsync(fixture.Host.CurrentContext!, Credential, default);
            await fixture.Authorization.Started.Task;
            fixture.Host.Dispose();
            await ExpectFailure(pending, AccountBridgeStableErrors.CompatibilityWriteUnavailable);
            Check(fixture.Links.Consumes == 0, "closing host prevents a late proof write");
        }
    }

    private static async Task ExpectFailure(Task<AccountBridgeCompatibilityProjection> pending, string code)
    {
        try { await pending; throw new Exception("Expected guarded failure"); }
        catch (AccountBridgeHostException error) { Check(error.Code == code, "stable failure code"); }
    }
    private static void Check(bool value, string message) { if (!value) throw new Exception(message); }

    private sealed class Fixture : IDisposable
    {
        internal readonly Links Links = new();
        internal readonly Store Store = new();
        internal readonly Authorization Authorization = new();
        internal readonly Relay Relay = new();
        internal readonly ScmAccountBridgeHost Host;
        private readonly ScmHttpClient _http = new();
        internal Fixture()
        {
            var coordinator = new ScmAccountCompatibilityCoordinator(new IdentityLinkCoordinator(Authorization, Links, Store), Links, Store);
            Host = new(new OAuthPkceClient(_http, new Vault(), ScmOAuthOptions.CreateDefault()), new ScmProfileCacheStore(),
                "development", () => null, initialSession: Session, compatibilityReader: new S2CompatibilityReader(coordinator, Relay));
        }
        public void Dispose() { Host.Dispose(); }
    }
    private sealed class Authorization : IIdentityLinkAuthorizationClient
    {
        internal bool Wait;
        internal int Calls;
        internal TaskCompletionSource Started = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public async Task<ScmOAuthSession> AuthorizeIdentityLinkAsync(ScmOAuthSession session, CancellationToken token, Action<string>? progress = null)
        {
            Calls++; Started.TrySetResult();
            if (Wait) await Task.Delay(Timeout.Infinite, token);
            token.ThrowIfCancellationRequested();
            Check(ReferenceEquals(session, Session), "same SCM session for authorization");
            return session;
        }
    }
    private sealed class Store : ILegacyMigrationCredentialStore
    {
        internal int Saves, Deletes;
        internal string AccountId = "other-stored-account";
        internal bool AllowDelete;
        public LegacyMigrationCredential? Load() => new(AccountId, "other@example.invalid", "synthetic-stored", DateTimeOffset.UtcNow);
        public void Save(LegacyMigrationCredential credential) { Saves++; throw new Exception("Unexpected credential save"); }
        public void Delete() { Deletes++; if (!AllowDelete) throw new Exception("Manual link must not delete another stored credential"); }
    }
    private sealed class Links : IIdentityLinkClient
    {
        internal string? Failure, Password;
        internal int PasswordProofs, Consumes;
        internal bool AllowStored;
        public Task<ScmIdentityLinkProjection?> ResolveAsync(ScmOAuthSession session, CancellationToken token)
        {
            token.ThrowIfCancellationRequested();
            return Task.FromResult<ScmIdentityLinkProjection?>(Consumes > 0 && Failure != "unconfirmed" ? new("ACTIVE", "chosen-legacy") : null);
        }
        public Task<ScmIdentityLinkChallenge> CreateChallengeAsync(ScmOAuthSession session, CancellationToken token) =>
            Task.FromResult(new ScmIdentityLinkChallenge("challenge", "nonce", "audience", Session.AuthorityId, Session.Subject, DateTimeOffset.UtcNow.AddMinutes(1)));
        public Task<SignedIdentityLinkProof> RequestLegacyProofAsync(ScmIdentityLinkChallenge challenge, LegacyMigrationCredential credential, CancellationToken token)
        {
            if (!AllowStored) throw new Exception("Manual choice must not use stored bearer");
            return Task.FromResult(new SignedIdentityLinkProof("synthetic-proof", "synthetic-signature"));
        }
        public Task<SignedIdentityLinkProof> RequestLegacyProofAsync(ScmIdentityLinkChallenge challenge, LegacyIdentityLinkPasswordCredential credential, CancellationToken token)
        {
            token.ThrowIfCancellationRequested(); PasswordProofs++; Password = credential.Password;
            if (Failure == "password") throw new HttpRequestException("Synthetic rejection", null, HttpStatusCode.Unauthorized);
            return Task.FromResult(new SignedIdentityLinkProof("synthetic-proof", "synthetic-signature"));
        }
        public Task<ScmIdentityLinkResult> ConsumeProofAsync(ScmOAuthSession session, SignedIdentityLinkProof proof, CancellationToken token)
        {
            token.ThrowIfCancellationRequested(); Consumes++;
            return Task.FromResult(new ScmIdentityLinkResult(Failure == "conflict" ? "CONFLICT" : "LINKED", "chosen-legacy", null));
        }
        public Task<ScmIdentityLinkResult> ProvisionCompatibilityAccountAsync(ScmOAuthSession session, string commandId, CancellationToken token) =>
            throw new Exception("Provisioning is forbidden");
    }
    private sealed class Relay : ILegacyRelayAccountPort
    {
        internal int Calls;
        public Task<LegacyRelayAccessState> EstablishAsync(ScmOAuthSession session, string id, CancellationToken token)
        { token.ThrowIfCancellationRequested(); Calls++; Check(id == "chosen-legacy", "confirmed identity only"); return Task.FromResult(LegacyRelayAccessState.Ready); }
        public Task<LegacyRelayProfileReadResult> ReadOwnProfileAsync(ScmOAuthSession session, string id, CancellationToken token) => throw new Exception("Unexpected profile read");
        public void Reset() { }
    }
    private sealed class Vault : ITokenVault
    {
        public void SaveRefreshToken(string a, string b) => throw new Exception("Unexpected login replacement");
        public string? LoadRefreshToken(string a) => null;
        public string? LoadActiveAccountKey() => null;
        public void DeleteRefreshToken(string a) => throw new Exception("Unexpected logout");
    }
}
