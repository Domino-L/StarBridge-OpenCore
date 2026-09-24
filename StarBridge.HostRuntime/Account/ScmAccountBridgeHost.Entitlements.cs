using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    public async Task<object> RedeemLegacyEntitlementsAsync(BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token)
    {
        if (payload.ValueKind != System.Text.Json.JsonValueKind.Object || payload.EnumerateObject().Count() != 2 ||
            !payload.TryGetProperty("schemaVersion", out var schema) || schema.ValueKind != System.Text.Json.JsonValueKind.Number || !schema.TryGetInt32(out var version) || version != 1 ||
            !payload.TryGetProperty("code", out var code) || code.ValueKind != System.Text.Json.JsonValueKind.String)
            throw new AccountBridgeHostException("bridge.invalid_envelope");
        var result = await RedeemLegacyEntitlementsAsync(context, code.GetString()!, token);
        return new { schemaVersion = 1, outcome = result.Outcome };
    }

    internal async Task<LegacyEntitlementResult> RedeemLegacyEntitlementsAsync(
        BridgeAccountContext context, string code, CancellationToken token)
    {
        if (!await _mutationGate.WaitAsync(0, token)) return new("busy");
        try
        {
            var generation = Generation;
            var credential = _legacySession;
            if (_disposed || _session is not null || credential is null || _legacyPasswordLogin is null ||
                _legacyRestoreUnavailable || _reauthorizationRequired || _credentialTemporarilyUnavailable || LegacyContext != context)
                return new("unsupported");
            var result = await _legacyPasswordLogin.RedeemEntitlementsAsync(credential, code, token);
            // Read back once after uncertainty; never replay the mutation or infer
            // redemption success just because this account already has a grant.
            var readback = result.Outcome == "uncertain"
                ? await _legacyPasswordLogin.ReadEntitlementsAsync(credential, token) : null;
            lock (_loginGate)
            {
                token.ThrowIfCancellationRequested();
                if (_disposed || generation != Generation || !ReferenceEquals(credential, _legacySession) || _session is not null)
                    return new("sessionChanged");
                if (result.Outcome == "redeemed" && result.Snapshot?.AccountId == credential.AccountId)
                    _legacyEntitlements = result.Snapshot;
                else if (readback?.Outcome == "ready" && readback.Snapshot?.AccountId == credential.AccountId)
                    _legacyEntitlements = readback.Snapshot;
                // Never retain grants after an explicit credential rejection.
                if (result.Outcome == "reauthorizationRequired" || readback?.Outcome == "reauthorizationRequired") _legacyEntitlements = null;
                return result;
            }
        }
        finally { if (!_disposed) _mutationGate.Release(); }
    }
}
