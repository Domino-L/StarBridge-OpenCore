using System.Text.Json;
using StarBridge.Core.TrustSafety;
using StarBridge.HostRuntime.Account;

internal static class AccountSafetyRequestTests
{
    internal static Task Verify()
    {
        AccountSafetyRequest.Read(JsonSerializer.SerializeToElement(new { schemaVersion = 1 }));
        foreach (var json in new[] { "{}", "null", "[]", "{\"schemaVersion\":2}",
            "{\"schemaVersion\":1,\"schemaVersion\":1}", "{\"schemaVersion\":1,\"accountId\":\"other\"}" })
        {
            using var document = JsonDocument.Parse(json);
            Reject(() => AccountSafetyRequest.Read(document.RootElement));
        }
        var id = "retry-ticket";
        JsonElement Appeal(string details, string sanction = " sanction ") => JsonSerializer.SerializeToElement(new {
            schemaVersion = 1, sanctionId = sanction, details, clientRequestId = id
        });
        var request = AccountSafetyRequest.Appeal(Appeal("  explanation\nsecond line  "));
        Check(request.SanctionId == "sanction" && request.Details == "explanation\nsecond line", "S2 normalization and multiline explanation preserved.");
        Check(request.ClientRequestId == id, "Caller retry identity must be preserved, not regenerated.");
        AccountSafetyRequest.Appeal(Appeal(new string('a', SanctionAppealValidation.MaximumDetailsLength)));
        Reject(() => AccountSafetyRequest.Appeal(Appeal(new string('a', SanctionAppealValidation.MaximumDetailsLength + 1))));
        Reject(() => AccountSafetyRequest.Appeal(Appeal(" ")));
        Reject(() => AccountSafetyRequest.Appeal(Appeal("reason", "bad\nid")));
        Reject(() => AccountSafetyRequest.Appeal(JsonSerializer.SerializeToElement(new {
            schemaVersion = 1, sanctionId = "sanction", details = "reason", clientRequestId = id, reviewer = "admin"
        })));
        Reject(() => AccountSafetyRequest.Appeal(JsonSerializer.SerializeToElement(new {
            schemaVersion = 1, sanctionId = "sanction", details = 12, clientRequestId = id
        })));
        return Task.CompletedTask;
    }

    private static void Reject(Action action)
    {
        try { action(); throw new Exception("Invalid request accepted."); }
        catch (AccountBridgeHostException error) { Check(error.Code == "accountSafety.invalid_request", "Stable bridge error."); }
    }
    private static void Check(bool condition, string message) { if (!condition) throw new Exception(message); }
}
