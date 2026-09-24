using System.Text.Json;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    public async Task<object> LoginLegacyAsync(JsonElement payload, long generation, CancellationToken token)
    {
        if (_disposed || _legacyPasswordLogin is null)
            throw new AccountBridgeHostException("bridge.capability_unavailable");
        await EnsureRestoredAsync(token);
        if (!await _mutationGate.WaitAsync(0, token))
            return new LegacyPasswordLoginResult(1, "busy");
        using var operation = CancellationTokenSource.CreateLinkedTokenSource(token);
        operation.CancelAfter(TimeSpan.FromSeconds(25));
        try
        {
            lock (_loginGate)
            {
                if (_disposed || generation != Generation || _session is not null || _credentialTemporarilyUnavailable || _reauthorizationRequired)
                    return new LegacyPasswordLoginResult(1, "sessionChanged");
                _legacyLoginCancellation = operation;
            }
            var attempt = await _legacyPasswordLogin.VerifyAsync(payload, operation.Token);
            lock (_loginGate)
            {
                operation.Token.ThrowIfCancellationRequested();
                if (_disposed || generation != Generation || _session is not null)
                    return new LegacyPasswordLoginResult(1, "sessionChanged");
                // No await between the final context check and protected persistence.
                // Publish only the distinct Relay identity, never an SCM session or scope.
                var result = _legacyPasswordLogin.SaveVerified(attempt);
                if (result.Outcome == "verified" && attempt.Credential is not null)
                    PublishLegacySession(attempt.Credential, displayName: attempt.DisplayName, identity: attempt.Identity, avatarImageData: attempt.AvatarImageData, entitlements: attempt.Entitlements);
                return result;
            }
        }
        catch (OperationCanceledException) when (!token.IsCancellationRequested && !_disposed)
        { return new LegacyPasswordLoginResult(1, "unavailable"); }
        finally
        {
            lock (_loginGate)
            {
                if (ReferenceEquals(_legacyLoginCancellation, operation)) _legacyLoginCancellation = null;
                if (!_disposed) _mutationGate.Release();
            }
        }
    }
}
