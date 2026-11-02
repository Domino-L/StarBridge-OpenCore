using StarBridge.Core.ShipMedia;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    // Native callers only. The eventual Bridge projection must remove ownership,
    // storage IDs and paths, and accept only a Host-prepared image selection.
    internal Task<ShipMediaSummaryContract[]> ReadOwnHangarMediaAsync(BridgeAccountContext context, CancellationToken token) =>
        ExecuteHangarMediaAsync(context, (bearer, owner, current, ct) => _hangarMedia!.ReadAsync(bearer, owner, current, ct), token);

    internal Task<ShipMediaSummaryContract> UploadOwnHangarMediaAsync(BridgeAccountContext context,
        ShipMediaUploadRequestContract prepared, CancellationToken token) =>
        ExecuteHangarMediaAsync(context, (bearer, owner, current, ct) => _hangarMedia!.UploadAsync(bearer, owner, prepared, current, ct), token);

    internal Task<bool> DeleteOwnHangarMediaAsync(BridgeAccountContext context, string preparedMediaId, CancellationToken token) =>
        ExecuteHangarMediaAsync(context, async (bearer, owner, current, ct) =>
        {
            var catalog = await _hangarMedia!.ReadAsync(bearer, owner, current, ct);
            if (!catalog.Any(row => row.MediaId == preparedMediaId)) throw new AccountBridgeHostException("hangar.image_not_allowed");
            await _hangarMedia.DeleteAsync(bearer, preparedMediaId, current, ct);
            return true;
        }, token);

    private async Task<T> ExecuteHangarMediaAsync<T>(BridgeAccountContext context,
        Func<string, string, Action, CancellationToken, Task<T>> execute, CancellationToken token)
    {
        if (_hangarMedia is null) throw new AccountBridgeHostException("hangar.image_unavailable");
        if (_reauthorizationRequired || _credentialTemporarilyUnavailable)
            throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
        var session = await ReadDirectRelaySessionAsync(context, token).ConfigureAwait(false);
        var generation = Generation;
        void Current()
        {
            if (_disposed || generation != Generation) throw new BridgeStaleGenerationException(generation, Generation);
            RequireSameRelaySession(session, RequireRelaySession(context));
        }
        string owner;
        if (session.Legacy is { } legacy) owner = legacy.AccountId;
        else
        {
            var compatibility = _compatibilityReader ?? throw new AccountBridgeHostException("hangar.image_unavailable");
            var link = await compatibility.ReadAsync(session.Scm!, token);
            Current();
            owner = SelectHangarMediaOwner(link) ?? "";
            if (owner.Length == 0)
            {
                var identity = await _oauth.LoadBusinessIdentityAsync(session.Scm!, token);
                Current();
                RequireSameSession(session.Scm!, identity.ActiveSession);
                _session = identity.ActiveSession;
                session = RequireRelaySession(context);
                owner = identity.BusinessSubjectId;
            }
        }
        Current(); token.ThrowIfCancellationRequested();
        // The media client does not automatically replay a write after an uncertain
        // response. Callers retain the prepared operation ID for explicit recovery.
        var result = await execute(session.AccessToken, owner, Current, token);
        Current(); token.ThrowIfCancellationRequested();
        return result;
    }

    internal static string? SelectHangarMediaOwner(AccountBridgeCompatibilityProjection link) => link.IdentityState switch
    {
        "unlinked" => null,
        "linked" when link.RelayState == "ready" && !string.IsNullOrWhiteSpace(link.LegacyAccountId) => link.LegacyAccountId,
        _ => throw new AccountBridgeHostException("hangar.image_unavailable")
    };
}
