using StarBridge.HostRuntime.Account;
using StarBridge.NativeBridge;
using D = OfficialFleetDiagnosticFixture;

internal static class OfficialFleetEntryDiagnosticTests
{
    internal static IEnumerable<(string Name, Func<Task> Test)> Cases()
    {
        foreach (var code in new[] { "no-session", "no-relay-session", "reauthorization-required", "credential-unavailable",
            "communities-unavailable", "stale-generation", "relay-send-failed", "reached-client" })
            yield return ("CX-MEMBER-DIAG hangar entry " + code, () => Entry(code));
        yield return ("CX-MEMBER-DIAG hangar entry observer failure", ObserverFailure);
    }
    private static async Task Entry(string code)
    {
        using var f = new D(session: code != "no-session", client: code != "communities-unavailable", expired: code == "relay-send-failed");
        switch (code)
        {
            case "no-relay-session": f.Set("_disposed", true); break;
            case "reauthorization-required": f.Set("_reauthorizationRequired", true); break;
            case "credential-unavailable": f.Set("_credentialTemporarilyUnavailable", true); break;
            case "stale-generation": f.Relay.Status = System.Net.HttpStatusCode.ServiceUnavailable; f.Relay.OnSend = () => f.Set("_generation", 2L); break;
        }
        var error = await D.Failure(() => f.Host.ReadOfficialFleetHangarSharingAsync(f.Owner, D.Open, default));
        if (code == "stale-generation") D.Check(error is BridgeStaleGenerationException, "Retirement exception preserved");
        if (code is "no-session" or "no-relay-session" or "reauthorization-required" or "credential-unavailable")
            D.Check(error is AccountBridgeHostException { Code: AccountBridgeStableErrors.ReauthorizationRequired }, "Authorization error unchanged");
        if (code == "communities-unavailable")
            D.Check(error is AccountBridgeHostException { Code: "communities.unavailable" }, "Missing client behavior unchanged");
        var lines = f.Lines("official-hangar-entry");
        D.Check(lines.Length == 1 && lines[0].Contains($" stage=official-hangar-entry code={code} status=none elapsedMs="),
            "Exactly one entry classification: " + code);
        if (code is not ("stale-generation" or "reached-client")) D.Check(f.Relay.Calls == 0, "Pre-client failures do not send");
        D.Private(lines);
    }
    private static async Task ObserverFailure()
    {
        using var f = new D(session: false);
        f.Host.OfficialFleetDiagnostic = (_, _, _, _) => throw new IOException(D.Token);
        var error = await D.Failure(() => f.Host.ReadOfficialFleetHangarSharingAsync(f.Owner, D.Open, default));
        D.Check(error is AccountBridgeHostException { Code: AccountBridgeStableErrors.ReauthorizationRequired }, "Observer does not replace entry error");
    }
}