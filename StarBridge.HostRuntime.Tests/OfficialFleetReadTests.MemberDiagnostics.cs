using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Privacy;
using D = OfficialFleetDiagnosticFixture;

internal static partial class OfficialFleetReadTests
{
    internal static IEnumerable<(string Name, Func<Task> Test)> MemberDiagnosticCases()
    {
        foreach (var runtime in new[] { false, true })
        {
            foreach (var (name, error, expected) in new (string, Exception, string)[] {
                ("timeout", new TimeoutException(D.Token), "timeout"),
                ("cancelled", new OperationCanceledException(D.Token), "timeout"),
                ("network", new HttpRequestException(D.Token), "transient"),
                ("io", new IOException(D.Reference), "transient"),
                ("data", new InvalidDataException(D.Name), "data-invalid"),
                ("unavailable", new AccountBridgeHostException("official_fleet.read_unavailable"), "unavailable"),
                ("host", new AccountBridgeHostException("host.unavailable"), "host-unavailable"),
                ("unknown", new ArgumentException(D.Token), "unclassified")
            })
                yield return ($"CX-MEMBER-DIAG {(runtime ? "runtime" : "members")} {name}", () => MemberFailure(runtime, error, expected));
            foreach (var (status, expected) in new[] { (400, "http-error"), (401, "reauthorization"),
                (403, "forbidden"), (408, "timeout"), (429, "transient"), (503, "transient"), (504, "timeout") })
                yield return ($"CX-MEMBER-DIAG {(runtime ? "runtime" : "members")} HTTP {status}", () => MemberStatus(runtime, status, expected));
            yield return ($"CX-MEMBER-DIAG {(runtime ? "runtime" : "members")} success recovery privacy", () => MemberRecovery(runtime));
            yield return ($"CX-MEMBER-DIAG {(runtime ? "runtime" : "members")} throwing journal", () => MemberJournalFailure(runtime));
            yield return ($"CX-MEMBER-DIAG {(runtime ? "runtime" : "members")} identity failure", () => MemberIdentityFailure(runtime));
            foreach (var changeAccount in new[] { false, true })
                yield return ($"CX-MEMBER-DIAG {(runtime ? "runtime" : "members")} generation isolation account={changeAccount}",
                    () => MemberGenerationIsolation(runtime, changeAccount));
            foreach (var sourceSwitch in new[] { false, true })
            foreach (var currentFails in new[] { false, true })
            foreach (var lateSuccess in sourceSwitch ? new[] { false } : new[] { false, true })
                yield return ($"CX-MEMBER-DIAG {(runtime ? "runtime" : "members")} late completion source={sourceSwitch} currentFails={currentFails} lateSuccess={lateSuccess}",
                    () => MemberLateFailure(runtime, sourceSwitch, currentFails, lateSuccess));
            yield return ($"CX-MEMBER-DIAG {(runtime ? "runtime" : "members")} source isolation", () => MemberSourceIsolation(runtime));
        }
        foreach (var (status, code) in new[] { (401, "reauthorization"), (403, "forbidden"), (404, "unavailable"),
            (408, "transient"), (503, "transient") })
            yield return ($"CX-MEMBER-DIAG runtime Relay HTTP {status}", () => RelayFailure(status, code));
        foreach (var code in new[] { "timeout", "transient", "data-invalid" })
            yield return ("CX-MEMBER-DIAG runtime Relay " + code, () => RelayFailure(200, code));
        yield return ("CX-MEMBER-DIAG runtime Relay recovery", RelayRecovery);
        yield return ("CX-MEMBER-DIAG independent member recovery and disabled runtime", IndependentRecovery);
        yield return ("CX-MEMBER-DIAG concurrent HTTP status isolation", ConcurrentStatus);
    }

    private sealed class MemberFixture : IDisposable
    {
        internal readonly D Storage = new();
        internal readonly Handler Scm = new();
        internal readonly D.Handler Relay = new();
        internal readonly PrivacyRelayWriter Writer;
        internal readonly ScmAccountBridgeHost Account;
        internal Exception? Error;
        internal int Status = 200;
        internal string FailurePath = "/member/page";
        internal readonly bool Runtime;
        internal long SourceId = 7;
        internal string Stage => Runtime ? "official-runtime-members" : "official-members";
        internal MemberFixture(bool runtime)
        {
            Runtime = runtime;
            Account = Host(Scm);
            Account.OfficialFleetDiagnostic = Storage.Journal.Record;
            Writer = new(new Uri("https://cxdiag.invalid/"), Relay);
            Account.ConfigurePrivacyWriter(Writer);
            // Only this in-memory, mocked test owner; no environment/product switches.
            Account.ConfigureOfficialRealtime(runtime);
            Relay.Body = JsonSerializer.Serialize(new { schemaVersion = 4, sourceRef = "officialFleet:7",
                coverage = "requestedOwners", requestedOwnerCount = 0, members = Array.Empty<object>(),
                supportedFilters = new[] { "all" }, runtimeCapabilities = new {
                    presence = true, server = true, ship = true, location = true, onlineCount = false, inGameCount = false } });
            Scm.Failure = (request, _) => {
                var path = request.RequestUri!.AbsolutePath;
                if (path.EndsWith("/bootstrap", StringComparison.Ordinal))
                {
                    var fleet = new StarBridge.HostRuntime.Auth.ScmBootstrapFleet(SourceId, "ASTER", D.Name, null, true, "Officer", 4, []);
                    return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = JsonContent.Create(
                        new StarBridge.HostRuntime.Auth.ScmBootstrapSnapshot(new(Account.CurrentContext!.Subject, "Pilot", null, false), new(false, null),
                            [fleet], fleet, 0, 1, new() { ["fleets"] = 1 }, DateTimeOffset.UtcNow, ["profile.read", "organizations.read"]), options: Json) });
                }
                if (path.EndsWith(FailurePath, StringComparison.Ordinal))
                {
                    if (Error is not null) return Task.FromException<HttpResponseMessage>(Error);
                    if (Status != 200) return Task.FromResult(new HttpResponseMessage((HttpStatusCode)Status) {
                        Content = JsonContent.Create(new { message = D.Name + D.Token, code = D.Reference }) });
                }
                if (path.EndsWith("/member/page", StringComparison.Ordinal))
                    return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = JsonContent.Create(new {
                        code = 0, data = new { total = 1, list = new[] { new { userId = 101, nickname = D.Name,
                            organizationRank = D.Reference, signInStatus = 2, lastTime = 999 } } } }) });
                if (runtime && path.EndsWith("/member-identities", StringComparison.Ordinal))
                {
                    var now = DateTimeOffset.UtcNow;
                    return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = JsonContent.Create(new {
                        schemaVersion = 2, sourceRef = "officialFleet:" + SourceId, members = new[] { new {
                            memberId = 101, state = "unlinked", identityObservedAtUtc = now.ToString("O"),
                            identityValidUntilUtc = now.AddSeconds(5).ToString("O") } } }) });
                }
                return null;
            };
        }
        internal Task<object> Read() => Runtime
            ? Account.GetOfficialFleetRuntimeMembersAsync(Account.CurrentContext!, Payload(2, SourceId), default)
            : Account.GetOfficialFleetMembersAsync(Account.CurrentContext!, Payload(1, SourceId), default);
        internal static JsonElement Payload(int version, long sourceId = 7) => JsonSerializer.SerializeToElement(new {
            schemaVersion = version, sourceRef = "officialFleet:" + sourceId, search = "CXDIAG_QUERY_SENTINEL",
            filter = "all", pageNumber = 1, pageSize = 50 });
        internal string[] Lines() => Storage.Lines(Stage);
        public void Dispose() { Account.Dispose(); Writer.Dispose(); Scm.Dispose(); Storage.Dispose(); }
    }

    private static async Task MemberFailure(bool runtime, Exception error, string code)
    {
        using var f = new MemberFixture(runtime) { Error = error };
        var original = await D.Failure(f.Read);
        CheckMemberLine(f, code, null, 1);
        if (error is AccountBridgeHostException or ArgumentException)
            D.Check(ReferenceEquals(original, error), "Unmapped original exceptions remain unchanged");
    }
    private static async Task MemberStatus(bool runtime, int status, string code)
    {
        using var f = new MemberFixture(runtime) { Status = status };
        await D.Failure(f.Read);
        CheckMemberLine(f, code, status, 1);
    }
    private static async Task MemberRecovery(bool runtime)
    {
        using var f = new MemberFixture(runtime);
        await f.Read(); await f.Read();
        D.Check(f.Lines().Length == 0, "Consecutive successes do not log");
        f.Status = 503;
        await D.Failure(f.Read); await D.Failure(f.Read);
        CheckMemberLine(f, "transient", 503, 2);
        f.Status = 200;
        var result = JsonSerializer.SerializeToElement(await f.Read(), Json);
        CheckMemberLine(f, "ok", 200, 3);
        await f.Read();
        D.Check(f.Lines().Length == 3, "Only the first recovery success is logged");
        var member = result.GetProperty("members")[0];
        D.Check(!f.Lines().Any(l => l.Contains(member.GetProperty("memberRef").GetString()!, StringComparison.Ordinal)),
            "Generated member references never enter diagnostics");
        D.Private(f.Lines());
        D.Check(f.Lines().All(l => !l.Contains("synthetic-access")), "Synthetic bearer never enters diagnostics");
    }
    private static async Task MemberJournalFailure(bool runtime)
    {
        using var f = new MemberFixture(runtime);
        f.Account.OfficialFleetDiagnostic = (_, _, _, _) => throw new IOException(D.Token);
        f.Error = new AccountBridgeHostException("official_fleet.read_unavailable");
        var error = await D.Failure(f.Read);
        D.Check(ReferenceEquals(error, f.Error), "Throwing observer preserves original failure");
        f.Error = null;
        var recovered = JsonSerializer.SerializeToElement(await f.Read(), Json);
        D.Check(recovered.GetProperty("members").GetArrayLength() == 1, "Throwing observer preserves recovery result");
        var blocked = Path.Combine(f.Storage.Root, "blocked");
        Directory.CreateDirectory(f.Storage.Root); File.WriteAllText(blocked, "fixture");
        f.Account.OfficialFleetDiagnostic = new CommunityReadJournal(blocked).Record;
        f.Status = 503; await D.Failure(f.Read);
        f.Status = 200; await f.Read();
        D.Check(File.ReadAllText(blocked) == "fixture", "Filesystem journal failure does not affect reads");
    }
    private static async Task MemberIdentityFailure(bool runtime)
    {
        using var f = new MemberFixture(runtime) { FailurePath = "/member-identities", Error = new TimeoutException(D.Token) };
        var error = await D.Failure(f.Read);
        D.Check(error is AccountBridgeHostException { Code: "official_fleet.identity_unavailable" },
            "Identity failure behavior remains unchanged");
        CheckMemberLine(f, "timeout", null, 1);
    }
    private static async Task RelayFailure(int status, string code)
    {
        using var f = new MemberFixture(true);
        f.Relay.Status = (HttpStatusCode)status;
        if (status == 200)
        {
            if (code == "data-invalid") f.Relay.Body = "CXDIAG_BODY_SENTINEL";
            else f.Relay.Error = code == "timeout" ? new OperationCanceledException(D.Token) : new IOException(D.Token);
        }
        await D.Failure(f.Read);
        CheckMemberLine(f, code, status == 200 && code != "data-invalid" ? null : status, 1);
        D.Check(f.Relay.Calls == 1, "Runtime diagnostic does not add a Relay request");
    }
    private static async Task RelayRecovery()
    {
        using var f = new MemberFixture(true);
        f.Relay.Status = HttpStatusCode.ServiceUnavailable;
        await D.Failure(f.Read);
        f.Relay.Status = HttpStatusCode.OK;
        await f.Read(); await f.Read();
        CheckMemberLine(f, "ok", 200, 2);
    }
    private static async Task IndependentRecovery()
    {
        using var f = new MemberFixture(false);
        await D.Failure(() => f.Account.GetOfficialFleetRuntimeMembersAsync(f.Account.CurrentContext!, MemberFixture.Payload(2), default));
        D.Check(f.Storage.Lines("official-runtime-members").Single().Contains(" code=unavailable status=none "), "Disabled runtime logged without enabling product flags");
        await f.Read();
        D.Check(f.Lines().Length == 0 && f.Storage.Lines("official-runtime-members").Length == 1, "A separate member success does not clear runtime failure");
    }
    private static async Task ConcurrentStatus()
    {
        using var first = new MemberFixture(false) { Status = 403 };
        using var second = new MemberFixture(true) { Status = 503 };
        await Task.WhenAll(D.Failure(first.Read), D.Failure(second.Read));
        CheckMemberLine(first, "forbidden", 403, 1);
        CheckMemberLine(second, "transient", 503, 1);
    }
    private static void RetireMemberGeneration(MemberFixture f, bool changeAccount)
    {
        var flags = System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic;
        var type = typeof(ScmAccountBridgeHost);
        type.GetField("_generation", flags)!.SetValue(f.Account, f.Account.Generation + 1);
        if (changeAccount)
        {
            var session = (StarBridge.HostRuntime.Auth.ScmOAuthSession)type.GetField("_session", flags)!.GetValue(f.Account)!;
            var replacement = session with { Subject = D.Reference };
            type.GetField("_session", flags)!.SetValue(f.Account, replacement);
            // Both layers normally install the replacement during login. This
            // fixture installs only synthetic in-memory sessions, without IO.
            var oauth = type.GetField("_oauth", flags)!.GetValue(f.Account)!;
            typeof(StarBridge.HostRuntime.Auth.OAuthPkceClient).GetField("_currentSession", flags)!.SetValue(oauth, replacement);
        }
    }
    private static async Task MemberGenerationIsolation(bool runtime, bool changeAccount)
    {
        using var f = new MemberFixture(runtime) { Status = 503 };
        await D.Failure(f.Read);
        RetireMemberGeneration(f, changeAccount);
        f.Status = 200; await f.Read();
        D.Check(f.Lines().Length == 1, "Another generation/account success is not recovery");
        D.Private(f.Lines());
    }
    private static async Task MemberLateFailure(bool runtime, bool sourceSwitch, bool currentFails, bool lateSuccess)
    {
        using var f = new MemberFixture(runtime);
        var started = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var release = new TaskCompletionSource<HttpResponseMessage>(TaskCreationOptions.RunContinuationsAsynchronously);
        var normal = f.Scm.Failure;
        var hold = true;
        f.Scm.Failure = (request, token) => {
            if (hold && request.RequestUri!.AbsolutePath.EndsWith("/member/page", StringComparison.Ordinal))
            { hold = false; started.SetResult(); return release.Task; }
            return normal!(request, token);
        };
        var oldRead = D.Failure(f.Read);
        await started.Task.WaitAsync(TimeSpan.FromSeconds(10));
        try
        {
            if (sourceSwitch)
            {
                f.SourceId = 8;
                f.Relay.Body = f.Relay.Body.Replace("officialFleet:7", "officialFleet:8", StringComparison.Ordinal);
            }
            else RetireMemberGeneration(f, true);
            if (currentFails) { f.Status = 503; await D.Failure(f.Read); }
            else await f.Read();
        }
        finally
        {
            if (lateSuccess) release.TrySetResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = JsonContent.Create(new {
                code = 0, data = new { total = 0, list = Array.Empty<object>() } }) });
            else release.TrySetException(new TimeoutException(D.Token));
        }
        await oldRead;
        var count = f.Lines().Length;
        f.Status = 200; await f.Read(); await f.Read();
        D.Check(f.Lines().Length == count + (currentFails ? 1 : 0) &&
            f.Lines().Count(l => l.Contains(" code=ok ")) == (currentFails ? 1 : 0), "Late failure cannot change the current owner/source recovery marker");
        D.Private(f.Lines());
    }
    private static async Task MemberSourceIsolation(bool runtime)
    {
        using var f = new MemberFixture(runtime) { Status = 503 };
        await D.Failure(f.Read);
        f.SourceId = 8;
        f.Relay.Body = f.Relay.Body.Replace("officialFleet:7", "officialFleet:8", StringComparison.Ordinal);
        f.Status = 200; await f.Read();
        D.Check(f.Lines().Length == 1, "Another source success is not recovery");
        f.SourceId = 7;
        f.Relay.Body = f.Relay.Body.Replace("officialFleet:8", "officialFleet:7", StringComparison.Ordinal);
        await f.Read();
        D.Check(f.Lines().Length == 1, "Returning to an earlier source does not revive its recovery marker");
        D.Private(f.Lines());
    }
    private static void CheckMemberLine(MemberFixture f, string code, int? status, int count)
    {
        var lines = f.Lines();
        D.Check(lines.Length == count && lines.Last().Contains($" stage={f.Stage} code={code} status={(status?.ToString() ?? "none")} elapsedMs="),
            $"Expected {f.Stage}/{code}/{status} diagnostic, count {count}");
        D.Private(lines);
    }
}
