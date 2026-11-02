using System.Text.Json;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class AccountBridgeDispatcher
{
    private static void ValidateRestoreDisplayOption(BridgeEnvelope request)
    {
        if (!request.Payload.TryGetProperty("restoreDisplayProgress", out var display)) return;
        RejectUnknownProperties(request.Payload, "schemaVersion", "restoreDisplayProgress");
        var fields = request.Payload.EnumerateObject().Select(p => p.Name).ToArray();
        if (display.ValueKind is not (JsonValueKind.True or JsonValueKind.False) || request.AccountContext is not null ||
            fields.Length != fields.Distinct(StringComparer.Ordinal).Count())
            throw new BridgeProtocolException(BridgeErrorCodes.InvalidEnvelope, "Account display option is invalid.");
    }
}
