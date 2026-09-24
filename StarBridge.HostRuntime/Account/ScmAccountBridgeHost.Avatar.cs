using System.Text.Json;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    public async Task<object> UpdateAvatarAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token)
    {
        if (payload.ValueKind != JsonValueKind.Object || payload.EnumerateObject().Count() != 2 ||
            !payload.TryGetProperty("schemaVersion", out var schema) || !schema.TryGetInt32(out var version) || version != 1 ||
            !payload.TryGetProperty("imageData", out var image) || image.ValueKind != JsonValueKind.String)
            throw new AccountBridgeHostException("account.avatar_invalid");
        // SCM avatars belong to SCM. Do not route an SCM session into the
        // legacy account endpoint or manufacture a profile-write scope.
        if (_session is not null || _legacySession is not { } legacy || _legacyPasswordLogin is null)
            throw new AccountBridgeHostException("account.avatar_managed_by_scm");
        var generation = Generation;
        void Current()
        {
            token.ThrowIfCancellationRequested();
            if (_disposed || generation != Generation || context != CurrentContext ||
                _legacySession != legacy || _reauthorizationRequired || _credentialTemporarilyUnavailable || _legacyRestoreUnavailable)
                throw new AccountBridgeHostException("account.reauthorization_required");
        }
        Current();
        var confirmed = await _legacyPasswordLogin.UpdateAvatarAsync(legacy, image.GetString()!, Current, token);
        Current();
        _legacyAvatarImageData = confirmed;
        return new { schemaVersion = 1, imageData = confirmed };
    }
}
