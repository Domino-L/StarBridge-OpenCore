using System.Net;
using System.Reflection;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Communities;
using StarBridge.HostRuntime.Privacy;
using StarBridge.NativeBridge;

internal sealed class OfficialFleetDiagnosticFixture : IDisposable
{
    internal const string Name = "CXDIAG_MEMBER_NAME_SENTINEL";
    internal const string Reference = "CXDIAG_MEMBER_REFERENCE_SENTINEL";
    internal const string Token = "CXDIAG_FAKE_TOKEN_SENTINEL";
    internal const string Source = "officialFleet:70007";
    internal static JsonElement J(object value) => JsonSerializer.SerializeToElement(value);
    internal static JsonElement Open => J(new { schemaVersion = 1, sourceRef = Source });
    internal static JsonElement Activation => J(new { schemaVersion = 1, sourceRef = Source,
        operationId = Reference, expectedPolicyRevision = 2 });
    internal readonly string Root;
    internal readonly CommunityReadJournal Journal;
    internal readonly Handler Relay = new();
    internal readonly CommunityClient Client;
    internal readonly ScmAccountBridgeHost Host;
    internal readonly BridgeAccountContext Owner;

    internal OfficialFleetDiagnosticFixture(bool session = true, bool client = true, bool expired = false)
    {
        Root = Path.GetFullPath(Path.Combine(Directory.GetCurrentDirectory(), "StarBridge.HostRuntime.Tests",
            ".codex-build", "cases", Guid.NewGuid().ToString("N")));
        Journal = new(Root);
        Client = new(new Uri("https://cxdiag.invalid/"), Relay) { ReadDiagnostic = Journal.Record };
        var options = new ScmOAuthOptions("synthetic-scm", new("http://127.0.0.1:3000/"),
            new("http://127.0.0.1:18080/"), new("http://127.0.0.1:18082/"),
            "starbridge-desktop", "starbridge-api", "profile.read organizations.read", "/oauth/callback");
        var initial = new ScmOAuthSession("synthetic-scm", Reference, Name, Token,
            DateTimeOffset.UtcNow.AddHours(expired ? -1 : 1), ["profile.read", "organizations.read"]);
        Host = new(new OAuthPkceClient(new ScmHttpClient(new RejectNetwork()), new NoVault(), options),
            new ScmProfileCacheStore(Root), "fixture", () => null,
            initialSession: session ? initial : null, initialGeneration: 1, communities: client ? Client : null);
        Host.OfficialFleetDiagnostic = Journal.Record;
        Owner = session ? Host.CurrentContext! : new("fixture", initial.AuthorityId, initial.Subject);
    }

    internal void Set(string field, object? value) =>
        typeof(ScmAccountBridgeHost).GetField(field, BindingFlags.Instance | BindingFlags.NonPublic)!.SetValue(Host, value);
    internal void Support()
    {
        var type = typeof(ScmAccountBridgeHost).GetNestedType("GovernanceSupport", BindingFlags.NonPublic)!;
        Set("_governanceSupport", Activator.CreateInstance(type, BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic,
            null, [Host.Generation, Source], null));
    }
    internal string[] Lines(string stage) => File.Exists(Path.Combine(Root, "community-read-diagnostics.log"))
        ? File.ReadAllLines(Path.Combine(Root, "community-read-diagnostics.log")).Where(l => l.Contains(" stage=" + stage + " ")).ToArray() : [];
    internal static void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
    internal static void Private(IEnumerable<string> lines)
    {
        foreach (var line in lines)
        foreach (var sentinel in new[] { Name, Reference, Token, Source, "CXDIAG_BODY_SENTINEL", "CXDIAG_QUERY_SENTINEL",
            "scopeKey", "sourceRef", "operationId", "http://", "https://", "cxdiag.invalid" })
            Check(!line.Contains(sentinel, StringComparison.Ordinal), "Diagnostic leaked a sentinel or request field");
    }
    internal static async Task<Exception> Failure(Func<Task<object>> action)
    {
        try { await action(); }
        catch (Exception error) { return error; }
        throw new InvalidOperationException("Expected original failure");
    }
    public void Dispose()
    {
        Host.Dispose(); Client.Dispose();
        var expected = Path.GetFullPath(Path.Combine(Directory.GetCurrentDirectory(), "StarBridge.HostRuntime.Tests", ".codex-build", "cases")) + Path.DirectorySeparatorChar;
        if (Directory.Exists(Root) && Root.StartsWith(expected, StringComparison.OrdinalIgnoreCase)) Directory.Delete(Root, true);
    }
    internal sealed class Handler : HttpMessageHandler
    {
        internal string Body = "{}";
        internal HttpStatusCode Status = HttpStatusCode.OK;
        internal Exception? Error;
        internal Action? OnSend;
        internal int Calls;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Calls++; OnSend?.Invoke();
            if (Error is not null) return Task.FromException<HttpResponseMessage>(Error);
            return Task.FromResult(new HttpResponseMessage(Status) {
                Content = new StringContent(Body, System.Text.Encoding.UTF8, "application/json") });
        }
    }
    private sealed class RejectNetwork : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) =>
            throw new InvalidOperationException("No network is permitted in diagnostic fixtures");
    }
    private sealed class NoVault : ITokenVault
    {
        public string? LoadRefreshToken(string key) => null;
        public string? LoadActiveAccountKey() => null;
        public void SaveRefreshToken(string key, string value) => throw new InvalidOperationException("No vault writes");
        public void DeleteRefreshToken(string key) => throw new InvalidOperationException("No vault deletes");
    }
}