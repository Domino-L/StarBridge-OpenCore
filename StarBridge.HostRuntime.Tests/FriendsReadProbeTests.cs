using System.Net;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Friends;

internal static class FriendsReadProbeTests
{
    private const string Marker = "[DEBUG-friends-read-20261011]";
    internal static Task Verify()
    {
#if !STARBRIDGE_SESSION_PROBE
        // Conditional probe calls are compiled out of ordinary builds, so log
        // assertions are meaningful only with the same opt-in symbol as HostRuntime.
        Console.WriteLine("SKIP friends probe: needs StarBridgeSessionProbeEnabled=true build");
        return Task.CompletedTask;
#else
        return VerifyEnabled();
#endif
    }

    private static async Task VerifyEnabled()
    {
        LoadPrivateAdapter();
        var previous = HostDataRoot.CurrentRoot;
        var root = System.IO.Directory.CreateTempSubdirectory("sb-friends-probe-").FullName;
        HostDataRoot.UsePreparedRoot(root);
        try
        {
            var redacted = FriendsReadProbeDiagnostics.Format(FriendsProbePhase.HostBoundary, 0,
                new AccountBridgeHostException("secret-code"));
            Require(!redacted.Contains("secret-") && redacted.Contains("code=other"), "unknown codes are not logged verbatim");
            await ExpectRelay(HttpStatusCode.ServiceUnavailable, "secret-upstream-body", "friends.read_transient",
                "phase=relay-http status=503 code=friends.read_transient");
            await ExpectRelay(HttpStatusCode.OK, "{}", "friends.data_invalid",
                "phase=relay-projection status=200 code=friends.data_invalid");
            using (var reader = new FriendsReader(new Uri("https://probe.invalid/"), new Handler((_, _) =>
                       Task.FromException<HttpResponseMessage>(new HttpRequestException("secret-network-error")))))
            {
                try { await reader.ReadAsync("secret-bearer", null, default); throw new Exception("Expected transport rejection."); }
                catch (AccountBridgeHostException error) { Require(error.Code == "friends.read_transient", "transport semantics preserved"); }
                Require(Log().Contains("phase=relay-http status=none code=friends.read_unavailable error=http"), "transport type without exception message");
            }
            var scmId = "scm-v1:" + new string('a', 64);
            using (var reader = new FriendsReader(new Uri("https://probe.invalid/"), new Handler((_, _) =>
                       Task.FromResult(Directory(scmId)))))
            {
                try { await reader.ReadScmDirectoryAsync("secret-bearer", (_, _) =>
                    Task.FromException<FriendView>(new AccountBridgeHostException("friends.forbidden")),
                    default, "secret-scope", false, () => { }); throw new Exception("Expected identity rejection."); }
                catch (AccountBridgeHostException error) { Require(error.Code == "friends.forbidden", "identity semantics preserved"); }
                Require(Log().Contains("phase=scm-identity status=none code=friends.forbidden"), "identity boundary distinguishable");
            }
            var requests = 0;
            using (var reader = new FriendsReader(new Uri("https://probe.invalid/"), new Handler((_, _) =>
                       Task.FromResult(++requests == 1 ? Directory("secret-legacy-id") : new HttpResponseMessage(HttpStatusCode.ServiceUnavailable)))))
            {
                try { await reader.ReadScmDirectoryAsync("secret-bearer", (_, _) => throw new Exception("Legacy identity queried."),
                    default, "secret-scope", false, () => { }); throw new Exception("Expected recheck rejection."); }
                catch (AccountBridgeHostException error) { Require(error.Code == "friends.read_unavailable", "recheck semantics preserved"); }
                Require(requests == 2 && Log().Contains("phase=relationship-recheck status=none code=friends.read_unavailable"), "recheck boundary distinguishable");
            }
            requests = 0;
            using (var reader = new FriendsReader(new Uri("https://probe.invalid/"), new Handler((_, _) =>
                       Task.FromResult(Directory(++requests == 1 ? "secret-before-id" : "secret-after-id")))))
            {
                try { await reader.ReadScmDirectoryAsync("secret-bearer", (_, _) => throw new Exception("Legacy identity queried."),
                    default, "secret-scope", false, () => { }); throw new Exception("Expected changed relationship rejection."); }
                catch (AccountBridgeHostException error) { Require(error.Code == "friends.read_unavailable", "relationship safety preserved"); }
                Require(Log().Contains("phase=directory-projection status=none code=friends.read_unavailable"), "projection boundary distinguishable");
            }
            var log = Log();
            Require(!log.Contains("secret-") && !log.Contains(scmId) && !log.Contains("probe.invalid"), "only fixed phases and errors are logged");
            await FriendsReaderTests.Projection();
            await FriendsReaderTests.HttpAndRequest();
            await LegacyPasswordLoginTests.ScmFriendDiscovery();
            Console.WriteLine("PASS friends probe: HTTP versus payload, SCM identity, recheck, relationship race, redaction and existing read/identity regressions");
        }
        finally { HostDataRoot.UsePreparedRoot(previous); System.IO.Directory.Delete(root, true); }
    }

    internal static Task VerifyDisabled()
    {
#if STARBRIDGE_SESSION_PROBE
        // An enabled diagnostic build intentionally writes logs and cannot prove
        // that the ordinary build compiles out its probe calls.
        Console.WriteLine("SKIP friends probe disabled: needs StarBridgeSessionProbeEnabled=false build");
        return Task.CompletedTask;
#else
        return VerifyOrdinaryBuild();
#endif
    }

    private static async Task VerifyOrdinaryBuild()
    {
        var previous = HostDataRoot.CurrentRoot;
        var root = System.IO.Directory.CreateTempSubdirectory("sb-friends-probe-off-").FullName;
        HostDataRoot.UsePreparedRoot(root);
        try
        {
            using var reader = new FriendsReader(new Uri("https://probe.invalid/"), new Handler((_, _) =>
                Task.FromResult(new HttpResponseMessage(HttpStatusCode.ServiceUnavailable))));
            try { await reader.ReadAsync("secret-bearer", null, default); throw new InvalidOperationException("Expected ordinary read rejection."); }
            catch (AccountBridgeHostException error) { Require(error.Code == "friends.read_transient" && error.Retryable, "ordinary error unchanged"); }
            Require(System.IO.Directory.GetFiles(root).Length == 0, "ordinary build does not write probe logs");
            Console.WriteLine("PASS ordinary build: friends probe calls compiled out");
        }
        finally { HostDataRoot.UsePreparedRoot(previous); System.IO.Directory.Delete(root, true); }
    }

    private static async Task ExpectRelay(HttpStatusCode status, string body, string code, string marker)
    {
        using var reader = new FriendsReader(new Uri("https://probe.invalid/"), new Handler((request, _) =>
        {
            Require(request.Method == HttpMethod.Get && request.Content is null, "probe does not add requests or writes");
            return Task.FromResult(new HttpResponseMessage(status) { Content = new StringContent(body) });
        }));
        try { await reader.ReadAsync("secret-bearer", null, default); throw new Exception("Expected Relay rejection."); }
        catch (AccountBridgeHostException error) { Require(error.Code == code, "original failure code preserved"); }
        Require(Log().Contains(Marker + " " + marker), "actual read failure recorded: " + marker);
    }
    private static HttpResponseMessage Directory(string id) => new(HttpStatusCode.OK)
        { Content = new ByteArrayContent(FriendsReaderTests.Directory(FriendsReaderTests.User(id))) };
    private static string Log()
    {
        var path = Path.Combine(HostDataRoot.CurrentRoot, "scm-auth-diagnostics.log");
        return File.Exists(path) ? File.ReadAllText(path) : "";
    }
    private static void LoadPrivateAdapter()
    {
        var path = Path.Combine(AppContext.BaseDirectory, "HajiProgress.Client.dll");
        if (File.Exists(path)) System.Runtime.Loader.AssemblyLoadContext.Default.LoadFromAssemblyPath(path);
    }
    private static void Require(bool condition, string message)
    { if (!condition) throw new InvalidOperationException("Friends probe: " + message); }
    private sealed class Handler(Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> send) : HttpMessageHandler
    { protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) => send(request, token); }
}
