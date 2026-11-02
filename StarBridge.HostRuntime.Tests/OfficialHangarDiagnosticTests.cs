using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.RegularExpressions;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Communities;
using StarBridge.HostRuntime.Hangar;
using StarBridge.HostRuntime.Privacy;

internal static class OfficialHangarDiagnosticTests
{
    internal static readonly (string Name, Func<Task> Test)[] Cases = [
        ("CX-HANGARDIAG five successful read stages and privacy", Success),
        ("CX-HANGARDIAG HTTP network and IO exceptions preserve identity", Transport),
        ("CX-HANGARDIAG parse failures and HTTP error behavior", ParseAndStatus),
        ("CX-HANGARDIAG projection failure and diagnostic isolation", Projection),
        ("CX-HANGARDIAG stage and code allowlists", Allowlists)
    ];

    private static readonly string[] Stages = ["official-hangar-current-http", "official-hangar-current-parse",
        "official-hangar-intents-http", "official-hangar-intents-parse", "official-hangar-project"];
    private static readonly object Target = new { authorityNamespace = "https://private-authority.invalid/?query=private-query",
        organizationId = 70007, sid = "DIAGTEST", membershipEpoch = "scm-observed-membership-row-v1:70007" };
    private static readonly string Revision = new('b', 32);
    private static JsonElement J(object value) => JsonSerializer.SerializeToElement(value);
    private static object Current() => new { schemaVersion = 1, target = Target, intentRevision = Revision,
        sharing = new { state = "available", version = new string('a', 64), strategy = "notShared", instanceRefs = Array.Empty<string>() } };
    private static object Intents(string? revision = null) => new { schemaVersion = 1,
        intents = new { state = "available", totalCount = 1, offset = 0, limit = 20, hasMore = false,
            items = new[] { new { target = Target, revision = revision ?? Revision, strategy = "notShared", selectedCount = 0, instanceRefs = Array.Empty<string>() } } } };
    private static HttpResponseMessage Reply(object body) => new(HttpStatusCode.OK) { Content = JsonContent.Create(body) };
    private static bool IsIntents(HttpRequestMessage request) => request.RequestUri!.AbsolutePath.EndsWith("/intents", StringComparison.Ordinal);

    private sealed class Fixture(Func<HttpRequestMessage, HttpResponseMessage>? respond = null) : IDisposable
    {
        internal readonly string Root = Path.Combine(Path.GetTempPath(), "sb-hangardiag-" + Guid.NewGuid().ToString("N"));
        internal CommunityClient Client { get; private set; } = null!;
        internal Fixture Start()
        {
            Client = new(new Uri("https://private-relay.invalid"), new Handler(request =>
                respond?.Invoke(request) ?? Reply(IsIntents(request) ? Intents() : Current()))) {
                ReadDiagnostic = new CommunityReadJournal(Root).Record
            };
            return this;
        }
        internal Task<object> Open(object? body = null, Action? current = null) => Client.ReadOfficialHangarSharingAsync(
            "private-bearer-token", J(body ?? new { schemaVersion = 1, sourceRef = "officialFleet:70007" }), "private-account-scope",
            current ?? (() => { }), () => new LocalHangarSnapshot(1, DateTimeOffset.UtcNow, "private-operation", []), default);
        internal string[] Lines() => File.ReadAllLines(Path.Combine(Root, "community-read-diagnostics.log"));
        public void Dispose() { Client?.Dispose(); if (Directory.Exists(Root)) Directory.Delete(Root, true); }
    }

    private static async Task Success()
    {
        using var fixture = new Fixture().Start();
        var result = J(await fixture.Open());
        Check(result.GetProperty("canGrant").GetBoolean(), "successful projection is unchanged");
        var lines = fixture.Lines();
        Check(lines.Length == 6, "five read stages and one response shape diagnostic");
        var readLines = lines.Where(l => !l.Contains("stage=official-hangar-shape ")).ToArray();
        for (var i = 0; i < Stages.Length; i++)
            Check(readLines[i].Contains($"stage={Stages[i]} code=ok status={(i == 4 ? "none" : "200")}"), "success stage order");
        Check(lines.Any(l => l.Contains("stage=official-hangar-shape code=draft-fields-invalid status=none")), "Plain V1 null imageFeatures is omitted by the wire serializer; remaining image fields are diagnosed without correction");
        AssertPrivate(lines, result.GetProperty("scopeRef").GetString()!, result.GetProperty("editRef").GetString()!);
    }

    private static async Task Transport()
    {
        foreach (var intents in new[] { false, true })
        foreach (var error in new Exception[] { new HttpRequestException("private-exception https://private-message.invalid/?query=private-query"),
            new IOException("private-exception private-account-scope"), new UnauthorizedAccessException("private-exception") })
        {
            using var fixture = new Fixture(request => IsIntents(request) == intents ? throw error : Reply(Current())).Start();
            try { await fixture.Open(); throw new Exception("Expected transport failure"); }
            catch (Exception actual) when (ReferenceEquals(actual, error)) { }
            var lines = fixture.Lines();
            Check(lines.Last().Contains($"stage=official-hangar-{(intents ? "intents" : "current")}-http code=network status=none"), "raw transport error recorded at GET boundary");
            AssertPrivate(lines);
        }
        foreach (var intents in new[] { false, true })
        {
            var error = new IOException("private-exception private-response-body");
            using var fixture = new Fixture(request => IsIntents(request) == intents
                ? new(HttpStatusCode.OK) { Content = new FailedContent(error) } : Reply(Current())).Start();
            try { await fixture.Open(); throw new Exception("Expected body IO failure"); }
            catch (IOException actual) when (ReferenceEquals(actual, error)) { }
            Check(fixture.Lines().Last().Contains($"stage=official-hangar-{(intents ? "intents" : "current")}-parse code=network status=200"), "body IO retains status and exception");
            AssertPrivate(fixture.Lines());
        }
    }

    private static async Task ParseAndStatus()
    {
        foreach (var intents in new[] { false, true })
        foreach (var malformed in new[] { true, false })
        {
            using var fixture = new Fixture(request => IsIntents(request) == intents
                ? malformed ? new(HttpStatusCode.OK) { Content = new StringContent("<html>private-response-body private-bearer-token</html>") }
                    : Reply(new { schemaVersion = 1, privateBody = "private-response-body" })
                : Reply(Current())).Start();
            await Reject(() => fixture.Open(), "communities.dataInvalid");
            var lines = fixture.Lines();
            Check(lines.Last().Contains($"stage=official-hangar-{(intents ? "intents" : "current")}-parse code=communities.dataInvalid status=200"), "malformed JSON and shape both diagnosed");
            AssertPrivate(lines);
        }
        foreach (var intents in new[] { false, true })
        foreach (var status in new[] { HttpStatusCode.Unauthorized, HttpStatusCode.ServiceUnavailable })
        {
            using var fixture = new Fixture(request => IsIntents(request) == intents
                ? new(status) { Content = new StringContent("private-response-body") }
                : Reply(IsIntents(request) ? Intents() : Current())).Start();
            if (status == HttpStatusCode.Unauthorized || intents)
                await Reject(() => fixture.Open(), status == HttpStatusCode.Unauthorized ? "communities.identityUnavailable" : "communities.unavailable");
            else Check(J(await fixture.Open()).GetProperty("state").GetString() == "unavailable", "current outage still projects unavailable");
            var lines = fixture.Lines();
            Check(lines.Any(line => line.Contains($"stage=official-hangar-{(intents ? "intents" : "current")}-http code=http-error status={(int)status}")), "HTTP error status retained");
            if (status == HttpStatusCode.Unauthorized || intents)
                Check(lines.Any(line => line.Contains("code=" + (status == HttpStatusCode.Unauthorized ? "communities.identityUnavailable" : "communities.unavailable"))), "stable error survives allowlist");
            AssertPrivate(lines);
        }
    }

    private static async Task Projection()
    {
        using (var fixture = new Fixture(request => Reply(IsIntents(request) ? Intents(new string('c', 32)) : Current())).Start())
        {
            await Reject(() => fixture.Open(), "communities.refreshRequired");
            Check(fixture.Lines().Last().Contains("stage=official-hangar-project code=communities.refreshRequired status=none"), "revision mismatch diagnosed without refresh change");
            AssertPrivate(fixture.Lines());
        }
        using (var fixture = new Fixture().Start())
        {
            var error = new IOException("private-exception"); var calls = 0;
            try { await fixture.Open(current: () => { if (++calls == 3) throw error; }); throw new Exception("Expected projection failure"); }
            catch (IOException actual) when (ReferenceEquals(actual, error)) { }
            Check(fixture.Lines().Last().Contains("stage=official-hangar-project code=network"), "unmapped projection IO is observable");
        }
        using (var fixture = new Fixture().Start())
        {
            fixture.Client.ReadDiagnostic = (_, _, _, _) => throw new IOException("private-exception");
            Check(J(await fixture.Open()).GetProperty("canGrant").GetBoolean(), "throwing observer cannot break success");
            await Reject(() => fixture.Open(new { schemaVersion = 1, scopeRef = new string('f', 32) }), "communities.refreshRequired");
        }
    }

    private static Task Allowlists()
    {
        using var fixture = new Fixture().Start();
        var journal = new CommunityReadJournal(fixture.Root);
        var codes = new[] { "ok", "network", "http-error", "communities.dataInvalid", "communities.refreshRequired", "communities.unavailable", "communities.identityUnavailable" };
        foreach (var stage in Stages)
        foreach (var code in codes) journal.Record(stage, code, 200, 1);
        journal.Record("private-stage\nURL", "ok", 200, 1);
        journal.Record(Stages[0], "private-exception\nprivate-response-body", 200, 1);
        var lines = fixture.Lines();
        Check(lines.Length == Stages.Length * codes.Length + 1, "unknown stages discarded");
        foreach (var stage in Stages)
        foreach (var code in codes) Check(lines.Any(line => line.Contains($"stage={stage} code={code} ")), "new code and stage allowlists agree");
        Check(lines.Last().Contains("code=unclassified"), "arbitrary codes filtered");
        AssertPrivate(lines);
        return Task.CompletedTask;
    }

    private static async Task Reject(Func<Task<object>> read, string code)
    {
        try { await read(); }
        catch (AccountBridgeHostException error) when (error.Code == code) { return; }
        throw new Exception("Expected " + code);
    }
    internal static void AssertPrivate(IEnumerable<string> lines, params string[] extra)
    {
        foreach (var line in lines)
        {
            Check(Regex.IsMatch(line, @"^\S+ \[DEBUG-community-read\] stage=[a-z-]+ code=[a-zA-Z._-]+ status=(none|[1-5][0-9]{2}) elapsedMs=[0-9]+( contentType=(json|html|text|other|none) bodyLength=(none|[0-9]+))?( mismatchField=(name|online|ship|location|liveStatus|visibilityScope|roomVisibilityScope|fleetSharedStateFields|roomSharedStateFields|fleetAdministratorsCanView|fleetMembersCanView|roomMembersCanView|friendsCanViewPresence|fleetVisibilityGroupIds|roomVisibilityGroupIds|serverShard|serverRegion))?$"), "only fixed diagnostic fields");
            foreach (var value in new[] { "https://", "http://", "?", "query=", "private-", "DIAGTEST", "officialFleet:", "membershipEpoch", "organizationId", "scopeRef", "response-body", "exception", Revision }.Concat(extra))
                Check(!line.Contains(value, StringComparison.Ordinal), "sensitive values excluded from every line");
        }
    }
    private static void Check(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
    private sealed class Handler(Func<HttpRequestMessage, HttpResponseMessage> respond) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) => Task.FromResult(respond(request));
    }
    private sealed class FailedContent(IOException error) : HttpContent
    {
        protected override Task<Stream> CreateContentReadStreamAsync() => Task.FromException<Stream>(error);
        protected override Task SerializeToStreamAsync(Stream stream, TransportContext? context) => Task.FromException(error);
        protected override bool TryComputeLength(out long length) { length = 0; return false; }
    }
}
