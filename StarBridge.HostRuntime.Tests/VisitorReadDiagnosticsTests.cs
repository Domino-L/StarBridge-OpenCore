using System.Net;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Auth;

internal static class VisitorReadDiagnosticsTests
{
    internal static async Task Verify()
    {
        var originalRoot = HostDataRoot.CurrentRoot;
        var originalFlag = Environment.GetEnvironmentVariable(VisitorReadDiagnostics.EnvironmentKey);
        var root = Path.Combine(Path.GetTempPath(), "starbridge-visitor-diagnostic-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        var log = Path.Combine(root, "visitor-read-diagnostics.log");
        void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
        try
        {
            HostDataRoot.UsePreparedRoot(root);
            Environment.SetEnvironmentVariable(VisitorReadDiagnostics.EnvironmentKey, null);
            using (VisitorReadDiagnostics.Begin()) VisitorReadDiagnostics.Select(VisitorReadDiagnostics.Route.LegacyMember);
            Check(!File.Exists(log), "Diagnostics must default off");
            Environment.SetEnvironmentVariable(VisitorReadDiagnostics.EnvironmentKey, "1");
            var http = new ScmHttpClient(new FixtureHandler());
            using (VisitorReadDiagnostics.Begin())
            {
                VisitorReadDiagnostics.Select(VisitorReadDiagnostics.Route.LegacyMember);
                using var request = new HttpRequestMessage(HttpMethod.Get, "https://example.invalid/synthetic-private-identity");
                request.Options.Set(VisitorReadDiagnostics.VisitorRequest, true);
                using var response = await http.SendAsync(request);
                Check(response.StatusCode == HttpStatusCode.NotFound, "Diagnostic must preserve HTTP result");
                var count = File.ReadAllLines(log).Length;
                using var supporting = new HttpRequestMessage(HttpMethod.Get, "https://example.invalid/supporting");
                using var ignored = await http.SendAsync(supporting);
                Check(File.ReadAllLines(log).Length == count, "Supporting calls must not masquerade as visitor calls");
                VisitorReadDiagnostics.Write(VisitorReadDiagnostics.Phase.Failed, code: "profile.visitor_not_visible");
                using (VisitorReadDiagnostics.Begin()) VisitorReadDiagnostics.Select(VisitorReadDiagnostics.Route.ScmMember);
                VisitorReadDiagnostics.Write(VisitorReadDiagnostics.Phase.Completed);
            }
            var lines = File.ReadAllLines(log);
            Check(lines.Any(l => l.Contains("phase=Response http=404")), "HTTP response evidence missing");
            Check(lines.Last().Contains("route=LegacyMember phase=Completed"), "Nested context must restore route");
            Check(!string.Join('\n', lines).Contains("synthetic-private-identity"), "Identity leaked");
            var before = lines.Length;
            VisitorReadDiagnostics.Write(VisitorReadDiagnostics.Phase.Completed);
            Check(File.ReadAllLines(log).Length == before, "Disposed context leaked");
            await Task.WhenAll(Enumerable.Range(0, 8).Select(async i =>
            {
                using var scope = VisitorReadDiagnostics.Begin();
                VisitorReadDiagnostics.Select(i % 2 == 0 ? VisitorReadDiagnostics.Route.LegacyMember : VisitorReadDiagnostics.Route.ScmMember);
                await Task.Yield();
                VisitorReadDiagnostics.Write(VisitorReadDiagnostics.Phase.Completed);
            }));
            foreach (var group in File.ReadAllLines(log).Skip(before).GroupBy(l => l.Split(' ')[1]))
            {
                var selected = group.Single(l => l.Contains("phase=RouteSelected")).Split(' ')[2];
                Check(group.Single(l => l.Contains("phase=Completed")).Split(' ')[2] == selected,
                    "Concurrent observations mixed routes");
            }
            var safe = VisitorReadDiagnostics.Format(-1, (VisitorReadDiagnostics.Route)999,
                (VisitorReadDiagnostics.Phase)999, 999, "secret\nidentity-token-url");
            Check(safe.Contains("sample=0 route=Unresolved phase=Failed http=0 code=other") && !safe.Contains("secret"), "Non-allowlisted fields leaked");
            for (var i = 0; i < 300; i++) VisitorReadDiagnostics.Append(log, safe);
            Check(File.ReadAllLines(log).Length == 256, "Retention is not bounded");
            // Force logging IO to fail without changing the transport result.
            var blocked = Path.Combine(root, "not-a-directory");
            File.WriteAllText(blocked, "fixture");
            HostDataRoot.UsePreparedRoot(blocked);
            using (VisitorReadDiagnostics.Begin())
            {
                using var request = new HttpRequestMessage(HttpMethod.Get, "https://example.invalid/");
                request.Options.Set(VisitorReadDiagnostics.VisitorRequest, true);
                using var response = await http.SendAsync(request);
                Check(response.StatusCode == HttpStatusCode.NotFound, "IO failure changed HTTP result");
            }
        }
        finally
        {
            HostDataRoot.UsePreparedRoot(originalRoot);
            Environment.SetEnvironmentVariable(VisitorReadDiagnostics.EnvironmentKey, originalFlag);
            Directory.Delete(root, recursive: true);
        }
    }

    private sealed class FixtureHandler : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) =>
            Task.FromResult(new HttpResponseMessage(HttpStatusCode.NotFound));
    }
}
