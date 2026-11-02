using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Onboarding;

public sealed partial class FirstUseOnlineReviewBridgeDispatcher
{
    public const string GameIdentityCapability = "onboarding.onlineReview.gameIdentity.v1";
    public const string GameIdentityRequestCode = "onboarding.onlineReview.gameIdentity.requestCode";
    public const string GameIdentityVerify = "onboarding.onlineReview.gameIdentity.verify";
    public const string GameIdentityOpenProfile = "onboarding.onlineReview.gameIdentity.openRsiProfile";
    private static bool IsGameIdentityRequest(string name) => name is GameIdentityRequestCode or GameIdentityVerify or GameIdentityOpenProfile;

    private async Task<BridgeDispatchBatch> DispatchGameIdentityAsync(BridgeEnvelope request, Func<bool> current,
        CancellationToken token)
    {
        if (request.MessageType != BridgeMessageTypes.Request || request.AccountContext is not null ||
            request.Payload.ValueKind != JsonValueKind.Object) return Error(request, "firstUse.invalid_request");
        var fields = request.Payload.EnumerateObject().ToArray();
        if (fields.Count(field => field.Name == "revision") != 1 ||
            !request.Payload.GetProperty("revision").TryGetInt64(out var revision))
            return Error(request, "firstUse.invalid_request");
        var command = request.Name switch
        {
            GameIdentityRequestCode => GameIdentityBridge.RequestCode,
            GameIdentityVerify => GameIdentityBridge.Verify,
            _ => GameIdentityBridge.OpenProfile
        };
        // Validate with the account-page contract after removing only revision.
        if (fields.Select(field => field.Name).Distinct(StringComparer.Ordinal).Count() != fields.Length)
            return Error(request, "firstUse.invalid_request");
        var payload = JsonSerializer.SerializeToElement(fields.Where(field => field.Name != "revision")
            .ToDictionary(field => field.Name, field => field.Value));
        try { ScmAccountBridgeHost.ValidateGameIdentityPayload(command, payload); }
        catch (AccountBridgeHostException) { return Error(request, "firstUse.invalid_request"); }
        if (revision != _mode.Current.Revision) return Error(request, "firstUse.context_changed");
        var result = await _mode.FirstUseGameIdentityAsync(revision, command, payload, current, token).ConfigureAwait(false);
        token.ThrowIfCancellationRequested();
        if (!current() || revision != _mode.Current.Revision) return Error(request, "firstUse.context_changed");
        return new(BridgeEnvelope.Response(request, result, preserveRequestAccountContext: false), []);
    }
}
