using StarBridge.HostRuntime.Updates;

internal static class FlutterStartupReceiptTests
{
    internal static Task Verify()
    {
        var nonce = new string('A', 64);
        var valid = new FlutterUpdateStartupReceipt(nonce, "0.7.0", 1, 123, 456, true, true);
        FlutterStartupReceiptValidator.RequireMatch(valid, nonce, "0.7.0", 123);
        var invalid = new[]
        {
            valid with { Nonce = new string('B', 64) },
            valid with { Version = "0.7.1" },
            valid with { Version = "invalid" },
            valid with { BridgeProtocol = 2 },
            valid with { ClientProcessId = 124 },
            valid with { HostProcessId = 0 },
            valid with { HostProcessId = -1 },
            valid with { HostProcessId = 123 },
            valid with { FirstFrameRendered = false },
            valid with { HostReady = false }
        };
        foreach (var receipt in invalid)
            Reject(() => FlutterStartupReceiptValidator.RequireMatch(receipt, nonce, "0.7.0", 123));
        Reject(() => FlutterStartupReceiptValidator.RequireMatch(valid, "", "0.7.0", 123));
        Reject(() => FlutterStartupReceiptValidator.RequireMatch(valid, new string('Z', 64), "0.7.0", 123));
        Reject(() => FlutterStartupReceiptValidator.RequireMatch(valid, nonce, "unknown", 123));
        Reject(() => FlutterStartupReceiptValidator.RequireMatch(valid, nonce, "0.7.0", 0));
        // Missing fields in legacy/incomplete JSON must fail closed, not grant readiness.
        var incomplete = System.Text.Json.JsonSerializer.Deserialize<FlutterUpdateStartupReceipt>("{}")!;
        Reject(() => FlutterStartupReceiptValidator.RequireMatch(incomplete, nonce, "0.7.0", 123));
        return Task.CompletedTask;
    }

    private static void Reject(Action action)
    {
        try { action(); }
        catch (InvalidDataException) { return; }
        throw new Exception("Invalid startup evidence was accepted.");
    }
}
