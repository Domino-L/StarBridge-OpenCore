using System.Net;
using System.Net.Http.Json;
using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Privacy;
using StarBridge.HostRuntime.Presence;
using StarBridge.HostRuntime.Support;
using StarBridge.NativeBridge;

internal static class OwnerGate073DiagnosticsTests
{
    internal static Task ChangedUsesInjectedSink()
    {
        var entries = new List<(string Stage, string Code)>();
        using (IdentityGateJournal.Capture((s, c) => entries.Add((s, c))))
        {
            IdentityGateJournal.Changed("cx073-journal", "code=initial");
            IdentityGateJournal.Changed("cx073-journal", "code=initial");
            IdentityGateJournal.Changed("cx073-journal", "code=changed");
            IdentityGateJournal.Event("cx073-journal", "code=event");
        }
        if (entries.Count != 3) throw new Exception("Changed must deduplicate values while Event preserves occurrences.");
        using (IdentityGateJournal.Capture((_, _) => throw new TimeoutException()))
            IdentityGateJournal.Event("cx073-journal", "code=sink-failure");
        return Task.CompletedTask;
    }

    internal static async Task LegacyHttpCodesAreWhitelisted()
    {
        foreach (var membershipFails in new[] { true, false })
        {
            var entries = new List<(string Stage, string Code)>();
            var receipts = new List<(string Code, int? Status)>();
            using var capture = IdentityGateJournal.Capture((s, c) => entries.Add((s, c)));
            using var writer = new PrivacyRelayWriter(new Uri("https://relay.example.invalid/"), new Failure(membershipFails));
            writer.PublicationDiagnostic = (_, code, status, _) => receipts.Add((code, status));
            var owner = new BridgeAccountContext("test", "fixture", "synthetic-owner");
            var input = new PrivacyPublicationInput(owner, 1, "Synthetic", true, null, GameLogSessionSnapshot.Empty);
            var payload = PrivacyPublicationPayload.Build(input, new(true,
                new(PlayerSharedStateFields.Presence, false, true, []), new(0, false)), false);
            try { await writer.SendAsync("synthetic-bearer-never-log", payload, default); throw new Exception("Expected HTTP rejection."); }
            catch (AccountBridgeHostException) { }
            var code = membershipFails ? "scm_identity_unavailable" : "unclassified";
            var status = membershipFails ? 403 : 428;
            if (receipts.Count != 1 || receipts[0] != (code, status) ||
                !entries.Any(e => e.Stage == "publication-http" && e.Code == $"code={code} status={status}") ||
                entries.Any(e => e.Code.Contains("synthetic-bearer", StringComparison.Ordinal) ||
                    e.Code.Contains("private-response", StringComparison.Ordinal) || e.Code.Contains("https:", StringComparison.Ordinal)))
                throw new Exception("Legacy routes must emit only HTTP status and allowlisted codes through the injected sink.");
        }
    }

    private sealed class Failure(bool membershipFails) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellation)
        {
            var membership = request.Method == HttpMethod.Get;
            return Task.FromResult(membership && !membershipFails
                ? new HttpResponseMessage(HttpStatusCode.OK) { Content = JsonContent.Create(new { fleetCode = (string?)null }) }
                : new HttpResponseMessage(membership ? HttpStatusCode.Forbidden : (HttpStatusCode)428) {
                    Content = JsonContent.Create(new { code = membership ? "SCM_IDENTITY_UNAVAILABLE" : "private-response" }) });
        }
    }
}
