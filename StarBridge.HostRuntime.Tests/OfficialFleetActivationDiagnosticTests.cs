using System.Net;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.NativeBridge;
using D = OfficialFleetDiagnosticFixture;

internal static class OfficialFleetActivationDiagnosticTests
{
    private const string Stage = "official-governance-activation";
    internal static IEnumerable<(string Name, Func<Task> Test)> Cases()
    {
        foreach (var (status, state) in new[] { (200, "accepted"), (200, "duplicate"), (400, "invalid"),
            (401, "identityUnavailable"), (403, "notAllowed"), (409, "conflict"), (503, "unavailable"),
            (503, "storageLimitReached"), (202, "operationOutcomeUnknown") })
        foreach (var activate in new[] { true, false })
            yield return ($"CX-MEMBER-DIAG activation {(activate ? "activate" : "revoke")} {state}",
                () => Response(status, state, activate));
        foreach (var code in new[] { "no-session", "no-relay-session", "reauthorization-required", "credential-unavailable",
            "communities-unavailable", "stale-generation", "upgrade-required", "data-invalid", "not-sent" })
            yield return ("CX-MEMBER-DIAG activation guard " + code, () => Guard(code));
        foreach (var code in new[] { "timeout", "transient" })
            yield return ("CX-MEMBER-DIAG activation transport " + code, () => Transport(code));
        yield return ("CX-MEMBER-DIAG activation unknown state code and malformed body", Unclassified);
        yield return ("CX-MEMBER-DIAG activation local observer cannot alter one-shot outcomes", ObserverFailure);
        yield return ("CX-MEMBER-DIAG activation unpaired surrogate preserves original outcome", UnpairedSurrogate);
    }
    private static async Task Response(int status, string state, bool activate)
    {
        using var f = new D();
        f.Support(); f.Relay.Status = (HttpStatusCode)status;
        f.Relay.Body = JsonSerializer.Serialize(new { schemaVersion = 1, state, operationId = D.Reference,
            policyRevision = 3, auditSequence = 8 });
        var result = (JsonElement)await (activate
            ? f.Host.ActivateOfficialFleetGovernanceAsync(f.Owner, D.Activation, default)
            : f.Host.RevokeOfficialFleetGovernanceActivationAsync(f.Owner, D.Activation, default));
        D.Check(result.GetProperty("state").GetString() == (state == "operationOutcomeUnknown" ? "outcomeUnknown" : state),
            "Original fixed-state projection preserved");
        Line(f, state, status);
        D.Check(f.Relay.Calls == 1, "Activation/revocation sends exactly once");
    }
    private static async Task Guard(string code)
    {
        using var f = new D(session: code != "no-session", client: code != "communities-unavailable");
        f.Support();
        switch (code)
        {
            case "no-relay-session": f.Set("_disposed", true); break;
            case "reauthorization-required": f.Set("_reauthorizationRequired", true); break;
            case "credential-unavailable": f.Set("_credentialTemporarilyUnavailable", true); break;
            case "upgrade-required": f.Set("_governanceSupport", null); break;
            case "stale-generation": f.Relay.OnSend = () => f.Set("_generation", 2L); break;
        }
        using var cancelled = new CancellationTokenSource();
        if (code == "not-sent") cancelled.Cancel();
        var error = await D.Failure(() => f.Host.ActivateOfficialFleetGovernanceAsync(f.Owner,
            code == "data-invalid" ? D.J(new { schemaVersion = 1, sourceRef = D.Source, operationId = D.Reference }) : D.Activation,
            cancelled.Token));
        if (code == "upgrade-required") D.Check(error is AccountBridgeHostException { Code: "communities.upgradeRequired" }, "Original upgrade guard preserved");
        if (code == "data-invalid") D.Check(error is AccountBridgeHostException { Code: "communities.dataInvalid" }, "Original validation preserved");
        if (code == "not-sent") D.Check(error is OperationCanceledException, "Original cancellation preserved");
        if (code == "stale-generation") D.Check(error is BridgeStaleGenerationException, "Original retirement preserved");
        Line(f, code, code == "stale-generation" ? 200 : null);
        D.Check(f.Relay.Calls == (code == "stale-generation" ? 1 : 0), "Guard does not cause an extra send");
    }
    private static async Task Transport(string code)
    {
        using var f = new D(); f.Support();
        f.Relay.Error = code == "timeout" ? new OperationCanceledException(D.Token) : new HttpRequestException(D.Token);
        var result = (JsonElement)await f.Host.ActivateOfficialFleetGovernanceAsync(f.Owner, D.Activation, default);
        D.Check(result.GetProperty("state").GetString() == "outcomeUnknown" && f.Relay.Calls == 1, "Uncertain outcome remains one-shot");
        Line(f, code, null);
    }
    private static async Task Unclassified()
    {
        foreach (var body in new[] { "{}", "CXDIAG_BODY_SENTINEL", JsonSerializer.Serialize(new { schemaVersion = 1, state = D.Token }),
            JsonSerializer.Serialize(new { schemaVersion = 1, code = D.Reference }), "null", "[]" })
        {
            using var f = new D(); f.Support(); f.Relay.Status = HttpStatusCode.ServiceUnavailable; f.Relay.Body = body;
            await f.Host.ActivateOfficialFleetGovernanceAsync(f.Owner, D.Activation, default);
            Line(f, "unclassified", 503);
            D.Check(f.Relay.Calls == 1, "Unknown response does not retry");
        }
        using (var f = new D())
        {
            f.Support(); f.Relay.Status = HttpStatusCode.Forbidden;
            f.Relay.Body = "{\"code\":\"notAllowed\",\"message\":\"CXDIAG_BODY_SENTINEL\"}";
            await f.Host.ActivateOfficialFleetGovernanceAsync(f.Owner, D.Activation, default);
            Line(f, "notAllowed", 403);
        }
    }
    private static async Task ObserverFailure()
    {
        foreach (var state in new[] { "accepted", "notAllowed" })
        {
            using var f = new D(); f.Support();
            f.Host.OfficialFleetDiagnostic = (_, _, _, _) => throw new IOException(D.Token);
            f.Relay.Status = state == "accepted" ? HttpStatusCode.OK : HttpStatusCode.Forbidden;
            f.Relay.Body = JsonSerializer.Serialize(new { schemaVersion = 1, state, operationId = D.Reference, policyRevision = 3, auditSequence = 8 });
            var result = (JsonElement)await f.Host.ActivateOfficialFleetGovernanceAsync(f.Owner, D.Activation, default);
            D.Check(result.GetProperty("state").GetString() == state && f.Relay.Calls == 1, "Throwing Host journal preserves write result");
        }
        using (var f = new D())
        {
            f.Client.ReadDiagnostic = (_, _, _, _) => throw new IOException(D.Token);
            f.Relay.Body = "{\"schemaVersion\":1,\"state\":\"accepted\",\"operationId\":\"" + D.Reference + "\",\"policyRevision\":3,\"auditSequence\":8}";
            var result = (JsonElement)await f.Client.WriteGovernanceActivationAsync(D.Token, D.Activation, true, () => { }, default);
            D.Check(result.GetProperty("state").GetString() == "accepted" && f.Relay.Calls == 1, "Throwing client journal preserves write result");
        }
    }
    private static async Task UnpairedSurrogate()
    {
        foreach (var activate in new[] { true, false })
        {
            using var f = new D(); f.Support();
            f.Relay.Body = "{\"schemaVersion\":1,\"state\":\"\\uD800\"}";
            var result = (JsonElement)await (activate
                ? f.Host.ActivateOfficialFleetGovernanceAsync(f.Owner, D.Activation, default)
                : f.Host.RevokeOfficialFleetGovernanceActivationAsync(f.Owner, D.Activation, default));
            D.Check(result.GetProperty("state").GetString() == "outcomeUnknown", "Original broad fallback preserved");
            D.Check(f.Relay.Calls == 1, "Classification decoding never retries the write");
            Line(f, "unclassified", 200);
        }
    }
    private static void Line(D f, string code, int? status)
    {
        var lines = f.Lines(Stage);
        D.Check(lines.Length == 1 && lines[0].Contains($" stage={Stage} code={code} status={(status?.ToString() ?? "none")} elapsedMs="),
            "Exactly one activation classification: " + code);
        D.Private(lines);
    }
}
