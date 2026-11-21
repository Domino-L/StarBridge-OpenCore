using System.Net;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using StarBridge.Core.Identity;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Communities;
using StarBridge.HostRuntime.LegacyRelay;
using StarBridge.HostRuntime.Support;
using StarBridge.NativeBridge;

// Account plan item 9: migration entry and result (migration-entry-073/PLAN.md),
// plus the SCM re-confirmation of a migrated owner's disband (plan item 13 follow-up).
// Fixtures use example.invalid hosts and synthetic IDs only.
internal static class MigrationEntry073Tests
{
    private const string LegacyId = "Synthetic-Legacy-ID";

    internal static async Task<int> Run()
    {
        var failures = 0;
        var cases = new (string, Func<Task>)[] {
            ("ClientReadsStatusAndRetry", ClientReadsStatusAndRetry),
            ("ClientRejectsMalformedStatus", ClientRejectsMalformedStatus),
            ("MarksKeepOnlyHashes", MarksKeepOnlyHashes),
            ("HostShowsResultOnceAndAgainAfterRollback", HostShowsResultOnceAndAgainAfterRollback),
            ("HostReportsSwitchOffAndRecovery", HostReportsSwitchOffAndRecovery),
            ("RefreshRunsCompatibilityReadFirst", RefreshRunsCompatibilityReadFirst),
            ("DisbandScmRevalidationSendsNoPassword", DisbandScmRevalidationSendsNoPassword),
        };
        foreach (var (name, run) in cases)
        {
            try
            {
                using (IdentityGateJournal.Capture((_, _) => { })) await run();
                Console.WriteLine("PASS MIGRATE073 " + name);
            }
            catch (Exception error) { failures++; Console.WriteLine("FAIL MIGRATE073 " + name + " " + error.GetType().Name + " " + error.Message); }
        }
        Console.WriteLine($"MIGRATE073 migration entry: {cases.Length - failures} passed, {failures} failed");
        return failures;
    }

    private static async Task ClientReadsStatusAndRetry()
    {
        var relay = new StatusRelay();
        using var client = new LegacyMigrationClient(new Uri("https://relay.example.invalid/"), relay);
        relay.Reply = (HttpStatusCode.NotFound, "");
        Check(await client.ReadAsync("bearer", default) is null, "404 means the switch is off");
        relay.Reply = (HttpStatusCode.OK, Status("completed", LegacyId, 12, 3, 2));
        var completed = await client.ReadAsync("bearer", default);
        Check(completed is { State: "completed", LegacyAccountId: LegacyId, Friends: 12, Communities: 3, Merged: 2 }, "completed status");
        relay.Reply = (HttpStatusCode.OK, Status("failed", null, 0, 0, 0, "migration_recovery_required"));
        Check((await client.RetryAsync("bearer", default))?.Reason == "migration_recovery_required", "retry answers like the status");
        relay.Reply = (HttpStatusCode.Conflict, "{\"code\":\"account_migrating\"}");
        Check((await client.ReadAsync("bearer", default))?.State == "migrating", "409 account_migrating is migrating");
        relay.Reply = (HttpStatusCode.Unauthorized, "");
        await Error(() => client.ReadAsync("bearer", default), AccountBridgeStableErrors.ReauthorizationRequired);
        relay.Reply = (HttpStatusCode.Conflict, "{\"code\":\"other\"}");
        await Error(() => client.ReadAsync("bearer", default), "account.migration_unavailable");
        Check(relay.Requests.Select(r => r.Path).Distinct().SequenceEqual([
            "GET /api/auth/legacy-migration/status", "POST /api/auth/legacy-migration/retry"]), "only the two migration routes");
        Check(relay.Requests.All(r => r.Version == RelayClientVersion.Value && r.Bearer == "bearer"), "every request carries the version and bearer");
    }

    private static async Task ClientRejectsMalformedStatus()
    {
        var relay = new StatusRelay();
        using var client = new LegacyMigrationClient(new Uri("https://relay.example.invalid/"), relay);
        foreach (var body in new[] {
            "{\"schemaVersion\":2,\"state\":\"none\"}",
            "{\"schemaVersion\":1,\"state\":\"done\"}",
            "{\"schemaVersion\":1,\"state\":\"completed\"}",
            "{\"schemaVersion\":1,\"state\":\"none\",\"legacyAccountId\":\"x\"}",
            "{\"schemaVersion\":1,\"state\":\"completed\",\"legacyAccountId\":\"x\",\"counts\":{\"friends\":-1}}",
            "{\"schemaVersion\":1,\"state\":\"completed\",\"legacyAccountId\":\"x\",\"counts\":[]}",
            "[]", "not json",
            "{\"schemaVersion\":1,\"state\":\"none\",\"pad\":\"" + new string('x', 17000) + "\"}",
        })
        {
            relay.Reply = (HttpStatusCode.OK, body);
            await Error(() => client.ReadAsync("bearer", default), "account.migration_data_invalid");
        }
    }

    private static Task MarksKeepOnlyHashes()
    {
        var root = Directory.CreateTempSubdirectory("sb-migrate073-marks-").FullName;
        try
        {
            var scm = new BridgeAccountContext("development", "fixture-scm", "fixture-subject");
            var other = scm with { Subject = "other-subject" };
            var marks = new LegacyMigrationResultMarks(root);
            Check(!marks.Shown(scm, LegacyId), "nothing shown yet");
            marks.MarkShown(scm, LegacyId);
            marks.MarkShown(other, LegacyId);
            Check(marks.Shown(scm, LegacyId.ToUpperInvariant()), "old account IDs compare ignoring case, like the relay");
            var text = File.ReadAllText(Path.Combine(root, LegacyMigrationResultMarks.FileName));
            Check(!text.Contains(LegacyId, StringComparison.OrdinalIgnoreCase) && !text.Contains("fixture-subject"), "no ID is stored");
            marks.Forget(scm);
            Check(!marks.Shown(scm, LegacyId) && marks.Shown(other, LegacyId), "forgetting is per SCM identity");
            File.WriteAllText(Path.Combine(root, LegacyMigrationResultMarks.FileName), "{corrupt");
            Check(!new LegacyMigrationResultMarks(root).Shown(other, LegacyId), "unreadable marks only mean showing once more");
            return Task.CompletedTask;
        }
        finally { Directory.Delete(root, true); }
    }

    private static async Task HostShowsResultOnceAndAgainAfterRollback()
    {
        var root = Directory.CreateTempSubdirectory("sb-migrate073-host-").FullName;
        try
        {
            var relay = new StatusRelay { Reply = (HttpStatusCode.OK, Status("completed", LegacyId, 12, 3, 2)) };
            using var host = Host(relay, root, LegacyRelayAccessState.Migrated);
            var context = host.CurrentContext!;
            var first = await Read(host, context);
            Check(first.GetProperty("available").GetBoolean() && first.GetProperty("state").GetString() == "completed" &&
                first.GetProperty("friends").GetInt32() == 12 && first.GetProperty("merged").GetInt32() == 2,
                "completed reading with counts");
            Check(first.GetProperty("localData").GetString() == "linked", "the alias was written by the compatibility read");
            Check(first.GetProperty("resultPending").GetBoolean(), "result not shown yet");
            Check(!first.GetRawText().Contains(LegacyId, StringComparison.OrdinalIgnoreCase), "no account ID reaches Flutter");
            await host.AcknowledgeLegacyMigrationAsync(context, Payload(), default);
            Check(!(await Read(host, context)).GetProperty("resultPending").GetBoolean(), "shown once");
            relay.Reply = (HttpStatusCode.OK, Status("none", null, 0, 0, 0));
            Check((await Read(host, context)).GetProperty("state").GetString() == "none", "rolled back");
            relay.Reply = (HttpStatusCode.OK, Status("completed", LegacyId, 12, 3, 2));
            Check((await Read(host, context)).GetProperty("resultPending").GetBoolean(), "a new migration shows its result again");
        }
        finally { Directory.Delete(root, true); }
    }

    private static async Task HostReportsSwitchOffAndRecovery()
    {
        var root = Directory.CreateTempSubdirectory("sb-migrate073-off-").FullName;
        try
        {
            var relay = new StatusRelay { Reply = (HttpStatusCode.NotFound, "") };
            using var host = Host(relay, root, LegacyRelayAccessState.Ready);
            var context = host.CurrentContext!;
            Check(!(await Read(host, context)).GetProperty("available").GetBoolean(), "switch off is not offered");
            relay.Reply = (HttpStatusCode.OK, Status("failed", null, 0, 0, 0, "migration_recovery_required"));
            var recovery = await Read(host, context);
            Check(recovery.GetProperty("state").GetString() == "failed" && recovery.GetProperty("recoveryRequired").GetBoolean(),
                "recovery is told apart from a retryable failure");
            relay.Reply = (HttpStatusCode.OK, Status("failed", null, 0, 0, 0, "legacy_already_migrated"));
            var failed = JsonSerializer.SerializeToElement(await host.RetryLegacyMigrationAsync(context, Payload(), default), Wire);
            Check(!failed.GetProperty("recoveryRequired").GetBoolean() && !failed.GetRawText().Contains("legacy_already_migrated"),
                "the reason code stays in the Host");
            await Error(() => host.ReadLegacyMigrationAsync(context, JsonSerializer.SerializeToElement(
                new { schemaVersion = 1, refresh = true, extra = 1 }), default), "account.migration_request_invalid");
        }
        finally { Directory.Delete(root, true); }
    }

    private static async Task RefreshRunsCompatibilityReadFirst()
    {
        var root = Directory.CreateTempSubdirectory("sb-migrate073-refresh-").FullName;
        try
        {
            var relay = new StatusRelay { Reply = (HttpStatusCode.OK, Status("none", null, 0, 0, 0)) };
            var compatibility = new SessionRelay { State = LegacyRelayAccessState.Ready };
            using var host = Host(relay, root, compatibility);
            var context = host.CurrentContext!;
            await Read(host, context, refresh: false);
            Check(compatibility.Reads == 0, "a plain read does not run the session read");
            await Read(host, context, refresh: true);
            Check(compatibility.Reads == 1, "a refresh runs the session read that lets the relay migrate");
        }
        finally { Directory.Delete(root, true); }
    }

    private static async Task DisbandScmRevalidationSendsNoPassword()
    {
        string? sentPassword = null;
        var mode = "scmRevalidation";
        using var handler = new Lambda(async request =>
        {
            if (request.RequestUri!.AbsolutePath == "/api/fleets/directory") return Json(new
            {
                schemaVersion = 1, membershipModelVersion = 2, view = "mine", query = "", next = (string?)null,
                items = new[] { new { code = "A", name = "Organization A", description = "", language = "", activeTime = "",
                    memberCount = 2, relationship = "owner", joinMode = "direct", actions = new[] { "leave" }, logoImageData = (string?)null } }
            });
            if (request.Method == HttpMethod.Get) return Json(new
            {
                schemaVersion = 1, code = "A", name = "Organization A", memberCount = 2, version = new string('a', 64),
                canDisband = true, credentialMode = mode
            });
            sentPassword = (await request.Content!.ReadFromJsonAsync<JsonElement>()).GetProperty("password").GetString();
            return Json(new { schemaVersion = 1, status = "accepted" });
        });
        using var client = new CommunityClient(new Uri("https://community.example.invalid"), handler);
        var target = (await client.ReadAsync("bearer", new("mine", "", null, null), "scope", default)).Items[0].TargetRef;
        async Task<string> Preview() => JsonSerializer.SerializeToElement(await client.ReadDisbandAsync("bearer",
            JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef = target }), "scope", () => { }, default))
            .GetProperty("confirmationRef").GetString()!;
        JsonElement Body(string confirmation, string password) => JsonSerializer.SerializeToElement(
            new { schemaVersion = 1, targetRef = target, confirmationRef = confirmation, password });
        var preview = JsonSerializer.SerializeToElement(await client.ReadDisbandAsync("bearer",
            JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef = target }), "scope", () => { }, default));
        Check(preview.GetProperty("credentialMode").GetString() == "scmRevalidation", "the mode reaches Flutter");
        await Error(() => client.DisbandAsync("bearer", Body(preview.GetProperty("confirmationRef").GetString()!, "a-password"),
            "scope", () => { }, default), "communities.dataInvalid");
        var accepted = (CommunityCommand)await client.DisbandAsync("bearer", Body(await Preview(), ""), "scope", () => { }, default);
        Check(accepted.Status == "accepted" && sentPassword == "", "SCM re-confirmation sends an empty password");
        mode = "legacyPassword";
        var legacyConfirmation = await Preview();
        await Error(() => client.DisbandAsync("bearer", Body(legacyConfirmation, ""), "scope", () => { }, default), "communities.dataInvalid");
        CommunityClient.ValidateDisband(Body(new string('b', 32), "x"));
        await Error(() => Task.Run(() => CommunityClient.ValidateDisband(Body(new string('b', 32), ""))), "communities.dataInvalid");
    }

    private static async Task<JsonElement> Read(ScmAccountBridgeHost host, BridgeAccountContext context, bool refresh = true) =>
        JsonSerializer.SerializeToElement(await host.ReadLegacyMigrationAsync(context, Payload(refresh), default), Wire);

    // The bridge writes payloads in camelCase (BridgeProtocol).
    private static readonly JsonSerializerOptions Wire = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };

    private static JsonElement Payload(bool? refresh = null) => refresh is null
        ? JsonSerializer.SerializeToElement(new { schemaVersion = 1 })
        : JsonSerializer.SerializeToElement(new { schemaVersion = 1, refresh });

    private static string Status(string state, string? legacy, int friends, int communities, int merged, string? reason = null) =>
        JsonSerializer.Serialize(new { schemaVersion = 1, state, legacyAccountId = legacy,
            counts = new { friends, communities, merged }, reason });

    private static ScmAccountBridgeHost Host(StatusRelay relay, string root, LegacyRelayAccessState state) =>
        Host(relay, root, new SessionRelay { State = state });

    private static ScmAccountBridgeHost Host(StatusRelay relay, string root, SessionRelay session)
    {
        var legacy = new LegacyPasswordLoginClient(new Uri("https://relay.example.invalid/"), new NoCredentials(), new Offline());
        var reader = new S2CompatibilityReader(new Coordinator(), session);
        return new(
            new OAuthPkceClient(new ScmHttpClient(new Offline()), new Vault(), ScmOAuthOptions.CreateDefault()),
            new ScmProfileCacheStore(), "development", () => null,
            initialSession: new("fixture-scm", "fixture-subject", "Fixture", "synthetic-token",
                DateTimeOffset.UtcNow.AddMinutes(5), [], GameIdentityHandle: "FixturePilot",
                GameIdentityStatus: ScmGameIdentityStatus.Verified),
            compatibilityReader: reader, legacyPasswordLogin: legacy)
        {
            LocalOwnerAliases = new LocalOwnerAliasStore(root),
            LegacyMigration = new LegacyMigrationClient(new Uri("https://relay.example.invalid/"), relay),
            MigrationResultMarks = new LegacyMigrationResultMarks(root)
        };
    }

    private static HttpResponseMessage Json(object value) => new(HttpStatusCode.OK) { Content = JsonContent.Create(value) };

    private static void Check(bool ok, string message) { if (!ok) throw new Exception(message); }

    private static async Task Error(Func<Task> action, string code)
    {
        try { await action(); throw new Exception("Expected " + code); }
        catch (AccountBridgeHostException e) when (e.Code == code) { }
    }

    private sealed class StatusRelay : HttpMessageHandler
    {
        internal (HttpStatusCode Status, string Body) Reply = (HttpStatusCode.NotFound, "");
        internal readonly List<(string Path, string? Version, string? Bearer)> Requests = [];
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Requests.Add((request.Method + " " + request.RequestUri!.AbsolutePath,
                request.Headers.TryGetValues(RelayClientVersion.HeaderName, out var v) ? v.Single() : null,
                request.Headers.Authorization?.Parameter));
            return Task.FromResult(new HttpResponseMessage(Reply.Status)
                { Content = new StringContent(Reply.Body, Encoding.UTF8, "application/json") });
        }
    }

    private sealed class Lambda(Func<HttpRequestMessage, Task<HttpResponseMessage>> send) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) => send(request);
    }

    private sealed class Offline : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) =>
            Task.FromResult(new HttpResponseMessage(HttpStatusCode.ServiceUnavailable));
    }

    private sealed class NoCredentials : ILegacyMigrationCredentialStore
    {
        public LegacyMigrationCredential? Load() => null;
        public void Save(LegacyMigrationCredential credential) => throw new Exception("Unexpected credential write");
        public void Delete() => throw new Exception("Unexpected credential delete");
    }

    private sealed class Vault : ITokenVault
    {
        public void SaveRefreshToken(string a, string b) => throw new Exception("Unexpected write");
        public string? LoadRefreshToken(string a) => null;
        public string? LoadActiveAccountKey() => null;
        public void DeleteRefreshToken(string a) => throw new Exception("Unexpected delete");
    }

    private sealed class Coordinator : IAccountCompatibilityCoordinator
    {
        public Task<AccountBridgeCompatibilityProjection> ReadAsync(ScmOAuthSession s, CancellationToken t) =>
            Task.FromResult(new AccountBridgeCompatibilityProjection("linked", "notEstablished", false, false, [], LegacyId));
        public Task<AccountBridgeCompatibilityProjection> LinkExistingAsync(ScmOAuthSession s, LegacyIdentityLinkPasswordCredential? c, CancellationToken t) =>
            throw new Exception("Unexpected link");
        public Task<AccountBridgeCompatibilityProjection> CreateCompatibilityIdentityAsync(ScmOAuthSession s, CancellationToken t) =>
            throw new Exception("Unexpected provision");
    }

    private sealed class SessionRelay : ILegacyRelayAccountPort
    {
        internal LegacyRelayAccessState State = LegacyRelayAccessState.Ready;
        internal int Reads;
        public Task<LegacyRelayAccessState> EstablishAsync(ScmOAuthSession s, string id, CancellationToken t)
        {
            Reads++;
            return Task.FromResult(State);
        }
        public Task<LegacyRelayProfileReadResult> ReadOwnProfileAsync(ScmOAuthSession s, string id, CancellationToken t) =>
            throw new Exception("Unexpected profile read");
        public void Reset() { }
    }
}
