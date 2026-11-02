using System.Net;
using System.Net.Sockets;
using System.Net.WebSockets;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Privacy;

internal static class ScmSessionProbeTests
{
    internal static async Task Verify()
    {
        // The exact packaged runtime may include this optional, already-reviewed Adapter.
        // The regular test deps file does not list private packages; load this one explicit local assembly only.
        var privateAdapter = Path.Combine(AppContext.BaseDirectory, "HajiProgress.Client.dll");
        if (File.Exists(privateAdapter))
            System.Runtime.Loader.AssemblyLoadContext.Default.LoadFromAssemblyPath(privateAdapter);
        var original = HostDataRoot.CurrentRoot;
        var root = Directory.CreateTempSubdirectory("sb-session-probe-").FullName;
        HostDataRoot.UsePreparedRoot(root);
        try
        {
            for (var locations = 0; locations <= 15; locations++)
            {
                var snapshot = new GameIdSettingsSnapshot(1, 2, locations, true, "private-stamp");
                var text = ScmSessionProbeDiagnostics.FormatSnapshot(SessionProbeSnapshot.AcceptedByHost, snapshot);
                Require(text.Contains($"locations={locations} ") && !text.Contains("private-stamp"), "exact disclosure bits without identity stamp");
                ScmSessionProbeDiagnostics.Snapshot(SessionProbeSnapshot.AcceptedByHost, snapshot);
            }
            var textWithSecrets = ScmSessionProbeDiagnostics.FormatRealtime(SessionProbePhase.Connect,
                new Uri("wss://private-user:private-password" + "@private-host.invalid/private-path?ticket=private-ticket"),
                403, 2, new WebSocketException("private-error"));
            Require(!textWithSecrets.Contains("private-") && textWithSecrets.Contains("host=other status=403"), "strictly projected endpoint and error");
            var ticketFailure = ScmSessionProbeDiagnostics.FormatRealtime(SessionProbePhase.Ticket,
                new Uri("wss://scmk.flowcld.com/"), 0, 1, new HttpRequestException("private-error", null, HttpStatusCode.ServiceUnavailable));
            Require(ticketFailure.Contains("phase=ticket host=scmk.flowcld.com status=503"), "ticket HTTP status not misreported as handshake");
            await DeniedHandshake();
            var log = File.ReadAllText(Path.Combine(root, "scm-auth-diagnostics.log"));
            Require(log.Contains("kind=game-id stage=host-accepted") && log.Contains("phase=connect host=other status=401"), "real client path records denied upgrade, not only formatter");
            Require(!log.Contains("private-") && !log.Contains("synthetic-ticket") && !log.Contains("synthetic-subject") && !log.Contains("synthetic-access"), "journal has no secret or account fields");
            Console.WriteLine("PASS session probe: 16 disclosure masks, strict redaction, ticket status and actual denied WebSocket handshake");
            await GameIdSettingsTests.Run();
            await LegacyPasswordLoginTests.ScmHandlePrivacy();
            await ScmRealtimeLifecycleTests.Verify();
            Console.WriteLine("PASS affected game ID transport, account isolation, sharing queue and realtime lifecycle regressions");
        }
        finally { HostDataRoot.UsePreparedRoot(original); Directory.Delete(root, true); }
    }

    internal static Task VerifyDisabled()
    {
        var original = HostDataRoot.CurrentRoot;
        var root = Directory.CreateTempSubdirectory("sb-session-probe-disabled-").FullName;
        HostDataRoot.UsePreparedRoot(root);
        try
        {
            using var socket = new ClientWebSocket();
            ScmSessionProbeDiagnostics.Configure(socket);
            ScmSessionProbeDiagnostics.Snapshot(SessionProbeSnapshot.AcceptedByHost, new(1, 0, 0, false, "private-stamp"));
            ScmSessionProbeDiagnostics.Realtime(SessionProbePhase.Connect, new Uri("wss://scmk.flowcld.com/"), 401, 1, null);
            Require(!socket.Options.CollectHttpResponseDetails && Directory.GetFiles(root).Length == 0,
                "ordinary build has no extra response collection or diagnostic writes");
            Console.WriteLine("PASS ordinary build: session probe calls compiled out");
            return Task.CompletedTask;
        }
        finally { HostDataRoot.UsePreparedRoot(original); Directory.Delete(root, true); }
    }

    private static async Task DeniedHandshake()
    {
        using var ports = new TcpListener(IPAddress.Loopback, 0);
        ports.Start();
        var port = ((IPEndPoint)ports.LocalEndpoint).Port;
        ports.Stop();
        var endpoint = new Uri($"http://127.0.0.1:{port}/");
        using var listener = new HttpListener();
        listener.Prefixes.Add(endpoint.AbsoluteUri);
        listener.Start();
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        var session = new ScmOAuthSession("synthetic", "synthetic-subject", "Pilot", "synthetic-access",
            DateTimeOffset.UtcNow.AddHours(1), ["presence.write"]);
        var options = new ScmOAuthOptions("synthetic", endpoint, endpoint, endpoint, "test", "test", "presence.write", "/callback");
        await using var client = new ScmRealtimeClient(null!, options, "synthetic-device", (_, _) => { }, (_, _) => { },
            (_, _) => { }, (_, _, _, _) => { },
            issueTicket: _ => Task.FromResult(new ScmWebSocketTicketResult(new("synthetic-ticket", DateTimeOffset.UtcNow.AddMinutes(1)), session)));
        client.Start(session);
        var context = await listener.GetContextAsync().WaitAsync(timeout.Token);
        context.Response.StatusCode = 401;
        context.Response.Close();
        var path = Path.Combine(HostDataRoot.CurrentRoot, "scm-auth-diagnostics.log");
        while (!File.Exists(path) || !File.ReadAllText(path).Contains("phase=connect host=other status=401"))
            await Task.Delay(20, timeout.Token);
        client.Stop();
    }

    private static void Require(bool condition, string message)
    { if (!condition) throw new InvalidOperationException("Session probe: " + message); }
}
