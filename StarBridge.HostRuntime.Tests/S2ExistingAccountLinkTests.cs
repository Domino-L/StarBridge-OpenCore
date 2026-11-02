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
        using (var fixture = new Fixture())
        {
            using var runtime = new AccountBridgeRuntime(fixture.Host);
            BridgeEnvelope Request(string name, object payload) => BridgeEnvelope.Request(name,
                Guid.NewGuid().ToString("N"), fixture.Host.Generation, payload, fixture.Host.CurrentContext);
            var priorContext = fixture.Host.CurrentContext;
            Check((await runtime.DispatchAsync(Request("friends.read", new { schemaVersion = 1 }))).Response.Error is not null,
                "Unlinked SCM cannot borrow the stored old account's friends");
            Check((await runtime.DispatchAsync(Request("communities.read", new { schemaVersion = 1, view = "mine", query = "" }))).Response.Error is not null,
                "Unlinked SCM cannot borrow the stored old account's organization");
            Check(fixture.Host.CurrentContext == priorContext && fixture.Links.Consumes == 0,
                "Denied old business reads never invent binding or replace SCM login");
            var linked = await runtime.DispatchAsync(Request("account.linkLegacyAccount", new {
                schemaVersion = 1, credential = new { accountName = Credential.AccountName, password = Credential.Password } }));
            Check(linked.Response.Error is null, "Joint compatibility flow explicitly links first");
            var friends = await runtime.DispatchAsync(Request("friends.read", new { schemaVersion = 1 }));
            Check(friends.Response.Error is null && friends.Response.Payload.GetProperty("friends").GetArrayLength() == 3,
                "Same SCM session reads all three original legacy friends after binding");
            var groups = await runtime.DispatchAsync(Request("communities.read", new { schemaVersion = 1, view = "mine", query = "" }));
            Check(groups.Response.Error is null && groups.Response.Payload.GetProperty("items").GetArrayLength() == 1,
                "Same SCM session retains original organization");
            var organization = groups.Response.Payload.GetProperty("items")[0];
            var foreign = Request("friends.read", new { schemaVersion = 1 }) with {
                AccountContext = fixture.Host.CurrentContext! with { Subject = "another-scm-user" } };
            var reads = fixture.Business.Reads;
            Check((await runtime.DispatchAsync(foreign)).Response.Error is not null && fixture.Business.Reads == reads,
                "Different SCM account cannot reuse this account's linked business context");
            Check(organization.GetProperty("name").GetString() == "Original organization" &&
                organization.GetProperty("actions").EnumerateArray().Select(x => x.GetString()).SequenceEqual(["leave"]),
                "Binding preserves original member permissions without granting management");
            var forbidden = await runtime.DispatchAsync(Request("communities.execute", new { schemaVersion = 1,
                action = "join", targetRef = organization.GetProperty("targetRef").GetString() }));
            Check(forbidden.Response.Error is not null || forbidden.Response.Payload.GetProperty("status").GetString() == "rejected",
                "Unadvertised action cannot become permission after linking");
            fixture.Business.Revoked = true;
            Check((await runtime.DispatchAsync(Request("friends.read", new { schemaVersion = 1 }))).Response.Error is not null,
                "Revoked legacy visibility does not reuse previous friend list");
            Check((await runtime.DispatchAsync(Request("communities.read", new { schemaVersion = 1, view = "mine", query = "" }))).Response.Error is not null,
                "Revoked legacy visibility does not reuse previous organization");
            Check(fixture.Host.CurrentContext?.Subject == Session.Subject && fixture.Business.Writes == 0 &&
                fixture.Store.Saves == 0 && fixture.Store.Deletes == 0, "Compatibility reads never replace SCM or mutate old business data");
        }
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
        foreach (var failure in new[] { "password", "conflict", "unconfirmed", "expired", "proof-unavailable" })
        {
            using var fixture = new Fixture();
            fixture.Links.Failure = failure;
            await ExpectFailure(fixture.Host.LinkLegacyAccountAsync(fixture.Host.CurrentContext!, Credential, default), failure switch
            {
                "password" => AccountBridgeStableErrors.LegacyCredentialsRejected,
                "proof-unavailable" => "account.legacy_proof_unavailable",
                "conflict" => AccountBridgeStableErrors.CompatibilityConflict,
                "expired" => AccountBridgeStableErrors.CompatibilityProofRejected,
                _ => AccountBridgeStableErrors.CompatibilityWriteUnavailable
            });
            Check(fixture.Host.CurrentContext is not null && fixture.Relay.Calls == 0, "failure retains SCM and never grants Relay access");
            Check(fixture.Store.Deletes == 0, "failure keeps stored credential");
            if (failure == "proof-unavailable")
                Check(fixture.Links.Consumes == 0, "Proof outage never submits a link");
        }
        foreach (var status in new[] { HttpStatusCode.Conflict, HttpStatusCode.UnprocessableEntity, HttpStatusCode.OK, HttpStatusCode.ServiceUnavailable })
        {
            using var fixture = new Fixture();
            fixture.Links.WireStatus = status;
            using var runtime = new AccountBridgeRuntime(fixture.Host);
            var context = fixture.Host.CurrentContext;
            var generation = fixture.Host.Generation;
            var response = (await runtime.DispatchAsync(BridgeEnvelope.Request("account.linkLegacyAccount", "wire-link",
                generation, new { schemaVersion = 1, credential = new { accountName = Credential.AccountName, password = Credential.Password } },
                context))).Response;
            Check(response.Error?.Code == (status == HttpStatusCode.Conflict ? AccountBridgeStableErrors.CompatibilityConflict
                    : status == HttpStatusCode.UnprocessableEntity ? AccountBridgeStableErrors.CompatibilityProofRejected
                    : AccountBridgeStableErrors.CompatibilityWriteUnavailable), "wire status maps to safe Bridge code");
            Check(response.Error?.Retryable == (status != HttpStatusCode.Conflict), "only retryable failures offer retry");
            Check(fixture.Host.CurrentContext == context && fixture.Host.Generation == generation,
                "wire rejection retains SCM login and account generation");
            Check(fixture.Relay.Calls == 0 && fixture.Store.Deletes == 0 && fixture.Links.Consumes == 1,
                "wire rejection neither grants legacy access nor clears credential nor replays proof");
            var projection = await fixture.Host.GetCompatibilityStateAsync(context!, default);
            Check(projection.IdentityState == "unlinked", "wire conflict/error cannot overwrite mapping with success");
            if (status == HttpStatusCode.UnprocessableEntity)
            {
                fixture.Links.WireStatus = null;
                var retried = await fixture.Host.LinkLegacyAccountAsync(context!, Credential, default);
                Check(retried.IdentityState == "linked" && fixture.Links.PasswordProofs == 2 && fixture.Links.Challenges == 2,
                    "retry starts a fresh challenge and proof instead of replaying the rejected proof");
            }
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
        internal readonly BusinessHandler Business;
        private readonly ScmHttpClient _http = new();
        internal Fixture()
        {
            Business = new(Links);
            var coordinator = new ScmAccountCompatibilityCoordinator(new IdentityLinkCoordinator(Authorization, Links, Store), Links, Store);
            Host = new(new OAuthPkceClient(_http, new Vault(), ScmOAuthOptions.CreateDefault()), new ScmProfileCacheStore(),
                "development", () => null, initialSession: Session, compatibilityReader: new S2CompatibilityReader(coordinator, Relay),
                friends: new StarBridge.HostRuntime.Friends.FriendsReader(new Uri("https://synthetic.invalid"), Business),
                communities: new StarBridge.HostRuntime.Communities.CommunityClient(new Uri("https://synthetic.invalid"), Business));
        }
        public void Dispose() { Host.Dispose(); }
    }
    private sealed class BusinessHandler(Links links) : HttpMessageHandler
    {
        internal bool Revoked;
        internal int Writes;
        internal int Reads;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Check(request.Headers.Authorization?.Parameter == Session.AccessToken, "SCM remains business bearer after link");
            if (request.Method != HttpMethod.Get) { Writes++; throw new Exception("Unexpected business write"); }
            Reads++;
            if (Revoked || links.Consumes == 0) return Task.FromResult(new HttpResponseMessage(HttpStatusCode.Forbidden));
            object data = request.RequestUri!.AbsolutePath switch {
                "/api/friends" => new { friends = Enumerable.Range(1, 3).Select(i => new {
                    user = FriendsReaderTests.User("original-legacy-friend-" + i), relationshipUpdatedAt = FriendsReaderTests.Now }).ToArray(),
                    incomingRequests = Array.Empty<object>(), outgoingRequests = Array.Empty<object>(), blockedUsers = Array.Empty<object>(), refreshedAt = FriendsReaderTests.Now },
                "/api/fleets/directory" => new { schemaVersion = 1, membershipModelVersion = 2, directoryVersion = 2,
                    totalCount = 1, view = "mine", query = "", next = (string?)null, items = new[] { new {
                        code = "original-organization", name = "Original organization", description = "", language = "English",
                        activeTime = "", memberCount = 4, relationship = "member", joinMode = "direct", recruiting = false,
                        recruitingNote = "", actions = new[] { "leave" }, logoImageData = (string?)null } } },
                _ => throw new Exception("Unexpected business route: " + request.RequestUri.AbsolutePath)
            };
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = System.Net.Http.Json.JsonContent.Create(data) });
        }
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
        internal HttpStatusCode? WireStatus;
        internal int PasswordProofs, Consumes, Challenges;
        internal bool AllowStored;
        private bool _linked;
        public Task<ScmIdentityLinkProjection?> ResolveAsync(ScmOAuthSession session, CancellationToken token)
        {
            token.ThrowIfCancellationRequested();
            return Task.FromResult<ScmIdentityLinkProjection?>(_linked ? new("ACTIVE", "chosen-legacy") : null);
        }
        public Task<ScmIdentityLinkChallenge> CreateChallengeAsync(ScmOAuthSession session, CancellationToken token)
        {
            Challenges++;
            return Task.FromResult(new ScmIdentityLinkChallenge($"challenge-{Challenges}", "nonce", "audience", Session.AuthorityId, Session.Subject, DateTimeOffset.UtcNow.AddMinutes(1)));
        }
        public Task<SignedIdentityLinkProof> RequestLegacyProofAsync(ScmIdentityLinkChallenge challenge, LegacyMigrationCredential credential, CancellationToken token)
        {
            if (!AllowStored) throw new Exception("Manual choice must not use stored bearer");
            return Task.FromResult(new SignedIdentityLinkProof("synthetic-proof", "synthetic-signature"));
        }
        public Task<SignedIdentityLinkProof> RequestLegacyProofAsync(ScmIdentityLinkChallenge challenge, LegacyIdentityLinkPasswordCredential credential, CancellationToken token)
        {
            token.ThrowIfCancellationRequested(); PasswordProofs++; Password = credential.Password;
            if (Failure == "password") throw new HttpRequestException("Synthetic rejection", null, HttpStatusCode.Unauthorized);
            if (Failure == "proof-unavailable") throw new LegacyIdentityLinkProofUnavailableException();
            return Task.FromResult(new SignedIdentityLinkProof("synthetic-proof", "synthetic-signature"));
        }
        public async Task<ScmIdentityLinkResult> ConsumeProofAsync(ScmOAuthSession session, SignedIdentityLinkProof proof, CancellationToken token)
        {
            token.ThrowIfCancellationRequested(); Consumes++;
            if (Failure == "expired") throw new IdentityLinkProofRejectedException();
            if (WireStatus is { } status)
            {
                using var legacy = new HttpClient(new RejectUnexpectedProofHandler());
                var http = new ScmHttpClient(new LinkWireHandler(status));
                var client = new IdentityLinkClient(http, legacy, ScmOAuthOptions.CreateDefault(),
                    () => new Uri("http://127.0.0.1:18767/"));
                return await client.ConsumeProofAsync(session, proof, token);
            }
            _linked = Failure is null;
            return new ScmIdentityLinkResult(Failure == "conflict" ? "CONFLICT" : "LINKED", "chosen-legacy", null);
        }
        public Task<ScmIdentityLinkResult> ProvisionCompatibilityAccountAsync(ScmOAuthSession session, string commandId, CancellationToken token) =>
            throw new Exception("Provisioning is forbidden");
    }
    private sealed class LinkWireHandler(HttpStatusCode status) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Check(request.RequestUri?.AbsolutePath.EndsWith("/identity-link/consume", StringComparison.Ordinal) == true,
                "consume uses the SCM resource endpoint");
            var body = status == HttpStatusCode.Conflict
                ? "{\"status\":\"CONFLICT\",\"code\":\"IDENTITY_LINK_CONFLICT\",\"conflictId\":null,\"message\":\"untrusted detail\"}"
                : status == HttpStatusCode.UnprocessableEntity
                    ? "{\"code\":\"IDENTITY_LINK_REJECTED\",\"message\":\"untrusted detail\"}"
                    : status == HttpStatusCode.ServiceUnavailable ? "{\"message\":\"untrusted detail\"}"
                    : "{\"code\":401,\"data\":null,\"msg\":\"untrusted detail\"}";
            return Task.FromResult(new HttpResponseMessage(status) { Content = new StringContent(body,
                System.Text.Encoding.UTF8, "application/json") });
        }
    }
    private sealed class RejectUnexpectedProofHandler : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) =>
            throw new Exception("SCM failure must not fall back to legacy authentication");
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
