using System.Net;
using System.Text;
using StarBridge.HostRuntime.Realtime;

// 2026-10-21 (relay r11 deployed, no client ticket200 seen): the reconnect loop
// caught only a few exception types. Any other failure inside one attempt - a
// malformed ticket reply (FormatException), a body cut off by a relay restart
// (an IOException) - ended the background loop silently with the state left at
// Connecting, so the Host never asked for a ticket again until its credential
// changed or it restarted, and every wait fell back to the HTTP long poll.
internal static class RealtimeClientRecoveryTests
{
    internal static async Task Verify()
    {
        var handler = new TicketHandler();
        using var client = new RelayRealtimeClient(new Uri("https://relay.invalid/"), handler);
        var records = new List<string>();
        client.Diagnostic = (kind, value) => { lock (records) records.Add($"{kind}={value}"); };
        var served = await client.TryWaitAsync("synthetic-bearer", false, "", -1, TimeSpan.Zero, CancellationToken.None);
        if (served is not null) throw new InvalidOperationException("A connecting client must leave the wait to HTTP.");
        var deadline = DateTime.UtcNow.AddSeconds(5);
        while (handler.Tickets < 2 && DateTime.UtcNow < deadline) await Task.Delay(20);
        if (handler.Tickets < 2)
            throw new InvalidOperationException("A malformed ticket reply ends the reconnect loop for good.");
        deadline = DateTime.UtcNow.AddSeconds(2);
        while (client.CurrentState != RelayRealtimeClient.State.Unsupported && DateTime.UtcNow < deadline) await Task.Delay(20);
        if (client.CurrentState != RelayRealtimeClient.State.Unsupported)
            throw new InvalidOperationException("The retried attempt must reach its real outcome.");
        // The local journal tells whether the Host asked, and what it was told.
        string[] expected = ["ticket=200", "attempt=FormatException", "state=backoff", "ticket=404", "state=unsupported"];
        lock (records)
            if (!records.SequenceEqual(expected))
                throw new InvalidOperationException("Gateway diagnostics: " + string.Join(", ", records));
        JournalAcceptsOnlyLifecycleCodes();
        Console.WriteLine("PASS realtime client retries after an unexpected attempt failure and records only lifecycle codes");
    }

    private static void JournalAcceptsOnlyLifecycleCodes()
    {
        var root = Path.Combine(Path.GetTempPath(), "starbridge-gateway-journal-" + Guid.NewGuid().ToString("N"));
        try
        {
            var journal = new RealtimeGatewayJournal(root);
            journal.Record("ticket", "200");
            journal.Record("state", "connected");
            journal.Record("ticket", "Bearer secret-token");
            journal.Record("ticket", "https://relay.invalid/api/realtime/v1/ws?ticket=t");
            journal.Record("token", "abc");
            var lines = File.ReadAllLines(Path.Combine(root, "realtime-gateway-diagnostics.log"));
            if (lines.Length != 2 || !lines[0].EndsWith(" ticket=200", StringComparison.Ordinal) ||
                !lines[1].EndsWith(" state=connected", StringComparison.Ordinal))
                throw new InvalidOperationException("The gateway journal accepted content beyond lifecycle codes.");
        }
        finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
    }

    private sealed class TicketHandler : HttpMessageHandler
    {
        internal int Tickets;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            // First reply: a protocol number that does not fit an int (FormatException).
            // Then: the route is absent, a known outcome that parks the loop.
            var response = Interlocked.Increment(ref Tickets) == 1
                ? new HttpResponseMessage(HttpStatusCode.OK)
                {
                    Content = new StringContent("{\"protocol\":99999999999,\"ticket\":\"t\",\"gateway\":\"/ws\"}",
                        Encoding.UTF8, "application/json")
                }
                : new HttpResponseMessage(HttpStatusCode.NotFound);
            return Task.FromResult(response);
        }
    }
}
