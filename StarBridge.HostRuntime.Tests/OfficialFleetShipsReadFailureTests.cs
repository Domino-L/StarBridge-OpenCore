using System.Collections;
using System.Net;
using System.Reflection;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Communities;

internal static class OfficialFleetShipsReadFailureTests
{
    internal static async Task Run()
    {
        foreach (var mode in new[] { "503", "unavailable", "timeout", "descriptor", "session", "source", "generation" })
        {
            using var fixture = new OfficialFleetDiagnosticFixture();
            using var handler = new Handler();
            using var client = new CommunityClient(new Uri("https://ships.invalid/"), handler);
            fixture.Set("_communities", client);
            SetDescriptor(fixture);
            var opened = JsonSerializer.SerializeToElement(await fixture.Host.OfficialFleetCommunicationAsync(
                fixture.Owner, J(new { schemaVersion = 1, sourceRef = OfficialFleetDiagnosticFixture.Source, action = "open" }), default));
            var body = J(new { schemaVersion = 1, sourceRef = OfficialFleetDiagnosticFixture.Source,
                targetRef = opened.GetProperty("targetRef").GetString(), offset = 0 });
            var targets = (IDictionary)typeof(ScmAccountBridgeHost)
                .GetField("_fleetProfileTargets", BindingFlags.NonPublic | BindingFlags.Instance)!.GetValue(fixture.Host)!;
            var targetType = typeof(ScmAccountBridgeHost).GetNestedType("FleetProfileTarget", BindingFlags.NonPublic)!;
            targets.Add("former-target", Activator.CreateInstance(targetType,
                BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance, null,
                [fixture.Owner, fixture.Host.Generation, OfficialFleetDiagnosticFixture.Source, 43L, "fixture-member"], null));
            Check(targets.Count == 1, "test establishes a former profile target");
            handler.Mode = mode;
            if (mode == "descriptor") fixture.Set("_fleetPublicSource", null);
            if (mode == "session") handler.OnShips = () => fixture.Set("_session", null);
            if (mode == "source") handler.OnShips = () => fixture.Set("_fleetPublicSource", null);
            if (mode == "generation") handler.OnShips = () => fixture.Set("_generation", fixture.Host.Generation + 1);
            var error = await OfficialFleetDiagnosticFixture.Failure(() =>
                fixture.Host.ReadOfficialFleetShipsAsync(fixture.Owner, body, default));
            var code = (error as AccountBridgeHostException)?.Code;
            // Read failures say so; an account/session/generation change keeps its existing code
            // (reauthorization stays visible to the global session handling) and never reads as a read failure.
            var ok = mode is "503" or "unavailable" or "timeout"
                ? code == "communities.readUnavailable"
                : mode is "session" or "generation"
                    ? code is "communities.identityUnavailable" or AccountBridgeStableErrors.ReauthorizationRequired
                    : code == "communities.identityUnavailable";
            Check(ok, $"{mode}: got {error.GetType().Name}/{code}");
            Check(targets.Count == 0, mode + ": old profile targets cleared");
            if (mode == "descriptor") Check(handler.ShipCalls == 0, "descriptor mismatch rejects before reading");
            if (mode == "503") Check(fixture.Lines("official-ships-host").Any(line =>
                line.Contains("code=communities.readUnavailable")), "diagnostic allowlist preserves the read failure code");
        }
    }

    private static void SetDescriptor(OfficialFleetDiagnosticFixture fixture)
    {
        var type = typeof(ScmAccountBridgeHost).GetNestedType("FleetPublicSource", BindingFlags.NonPublic)!;
        fixture.Set("_fleetPublicSource", Activator.CreateInstance(type,
            BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic, null,
            [fixture.Owner, fixture.Host.Generation, OfficialFleetDiagnosticFixture.Source, "FIXTURE"], null));
    }

    private static JsonElement J(object value) => JsonSerializer.SerializeToElement(value);
    private static void Check(bool value, string message)
    {
        if (!value) throw new InvalidOperationException(message);
    }

    // Injected message handler only; no socket, partner request or real credentials.
    private sealed class Handler : HttpMessageHandler
    {
        internal string Mode = "503";
        internal Action? OnShips;
        internal int ShipCalls;
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            if (request.RequestUri!.AbsolutePath == "/api/official-fleets/context")
                return new(HttpStatusCode.OK) { Content = new StringContent(JsonSerializer.Serialize(new {
                    schemaVersion = 1, sourceRef = OfficialFleetDiagnosticFixture.Source,
                    fleetCode = OfficialFleetDiagnosticFixture.Source.ToUpperInvariant(), name = "Fixture fleet",
                    announcementsAvailable = false, chatAvailable = false, canSend = false,
                    readReceiptsAvailable = false, canManageAnnouncements = false, activityAvailable = false })) };
            Check(request.RequestUri.AbsolutePath == "/api/official-fleets/ships", "only the official ships route");
            ShipCalls++;
            OnShips?.Invoke();
            if (Mode == "unavailable") throw new AccountBridgeHostException("communities.unavailable");
            // Exercise the real linked read budget, without changing production timeouts.
            if (Mode == "timeout") await Task.Delay(Timeout.InfiniteTimeSpan, token);
            return new(HttpStatusCode.ServiceUnavailable) { Content = new StringContent("{}") };
        }
    }
}
