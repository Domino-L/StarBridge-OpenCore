namespace StarBridge.HostRuntime.Account;

using System.Text.Json;
using StarBridge.Core.TrustSafety;

// The bridge validates its envelope; S2 remains the owner of appeal validation.
internal static class AccountSafetyRequest
{
    internal static void Read(JsonElement payload) => ValidateEnvelope(payload, false);

    internal static CreateSanctionAppealRequestContract Appeal(JsonElement payload)
    {
        ValidateEnvelope(payload, true);
        try
        {
            var request = new CreateSanctionAppealRequestContract(
                payload.GetProperty("sanctionId").GetString()?.Trim() ?? "",
                payload.GetProperty("details").GetString()?.Trim() ?? "",
                payload.GetProperty("clientRequestId").GetString()?.Trim() ?? "");
            if (SanctionAppealValidation.Validate(request) is not null ||
                request.SanctionId.Any(char.IsControl) || request.ClientRequestId.Any(char.IsControl))
                throw Invalid();
            return request;
        }
        catch (Exception error) when (error is InvalidOperationException or KeyNotFoundException or JsonException)
        { throw Invalid(); }
    }

    private static void ValidateEnvelope(JsonElement payload, bool appeal)
    {
        try
        {
            var names = payload.EnumerateObject().Select(property => property.Name).ToArray();
            if (names.Distinct(StringComparer.Ordinal).Count() != names.Length ||
                names.Length != (appeal ? 4 : 1) ||
                names.Any(name => name != "schemaVersion" &&
                    !(appeal && name is "sanctionId" or "details" or "clientRequestId")) ||
                payload.GetProperty("schemaVersion").GetInt32() != 1)
                throw Invalid();
        }
        catch (Exception error) when (error is InvalidOperationException or KeyNotFoundException or FormatException or JsonException)
        { throw Invalid(); }
    }

    private static AccountBridgeHostException Invalid() => new("accountSafety.invalid_request");
}
