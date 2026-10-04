using System.Text.Json;
using StarBridge.Core.Identity;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    private sealed record HandleIntent(string Id, long Generation, BridgeAccountContext Context,
        string Expected, string Detected, DateTimeOffset ExpiresAt);
    private HandleIntent? _handleIntent;
    // An uncertain write is not retryable. Only readback may resolve it.
    private HandleIntent? _uncertainHandleWrite;

    public async Task<object> PrepareHandleChangeAsync(BridgeAccountContext context, CancellationToken token)
    {
        var policy = ReadCurrentGameIdentityPolicy(context);
        object View(string state, string? id = null) => new {
            schemaVersion = 1, state, expectedHandle = policy.AuthoritativeHandle,
            detectedHandle = policy.DetectedHandle, scmBindingState = "unknown",
            mode = "legacyCompatibility", confirmationId = id
        };
        _handleIntent = null;
        if (_session is not null || _legacySession is not { } legacy || _legacyPasswordLogin is null)
            return View(policy.State == "match" ? "consistent" : "unknown");
        var generation = Generation;
        void Current() => RequireHandleOwner(context, generation, legacy, token);
        Current();
        var uncertain = _uncertainHandleWrite;
        if (uncertain is not null && (uncertain.Generation != generation || uncertain.Context != context))
            _uncertainHandleWrite = uncertain = null;
        // Pending outcome is checked even when the game observation disappeared.
        if (uncertain is not null)
        {
            var recovered = await _legacyPasswordLogin.ReadHandleAsync(legacy, Current, token);
            Current();
            if (SameHandle(recovered.Handle, uncertain.Detected)) {
                _uncertainHandleWrite = null;
                ApplyLegacyHandle(recovered);
                return View("consistent");
            }
            return View("outcomeUnknown");
        }
        if (policy.State == "match") return View("consistent");
        if (policy.State != "mismatch" || !IdentityBindingPolicy.IsValidGameName(policy.DetectedHandle) ||
            !IdentityBindingPolicy.IsValidGameName(policy.AuthoritativeHandle)) return View("observationRequired");
        var remote = await _legacyPasswordLogin.ReadHandleAsync(legacy, Current, token);
        Current();
        if (!SameHandle(remote.Handle, policy.AuthoritativeHandle)) {
            ApplyLegacyHandle(remote);
            return View("observationRequired");
        }
        var now = ReadCurrentGameIdentityPolicy(context);
        if (now.State != "mismatch" || !SameHandle(now.DetectedHandle, policy.DetectedHandle))
            throw new AccountBridgeHostException("identity.observation_changed");
        _handleIntent = new(Guid.NewGuid().ToString("N"), generation, context,
            policy.AuthoritativeHandle!, policy.DetectedHandle!, DateTimeOffset.UtcNow.AddMinutes(2));
        return View("ready", _handleIntent.Id);
    }

    public Task<object> CancelHandleChangeAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token)
    {
        token.ThrowIfCancellationRequested();
        var id = HandleConfirmationId(payload);
        if (_handleIntent is { } intent && intent.Id == id && intent.Context == context && intent.Generation == Generation)
            _handleIntent = null;
        return Task.FromResult<object>(new { schemaVersion = 1, cancelled = true });
    }

    public async Task<object> ConfirmHandleChangeAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token)
    {
        var id = HandleConfirmationId(payload);
        var intent = _handleIntent;
        if (intent is null || intent.Id != id || intent.Context != context || intent.Generation != Generation ||
            intent.ExpiresAt <= DateTimeOffset.UtcNow || _uncertainHandleWrite is not null ||
            _session is not null || _legacySession is not { } legacy || _legacyPasswordLogin is null)
            throw new AccountBridgeHostException("identity.confirmation_expired");
        // Consume before any await. Never reuse a confirmation after failure.
        _handleIntent = null;
        void Current() {
            RequireHandleOwner(context, intent.Generation, legacy, token);
            var policy = ReadCurrentGameIdentityPolicy(context);
            if (policy.State != "mismatch" || !SameHandle(policy.AuthoritativeHandle, intent.Expected) ||
                !SameHandle(policy.DetectedHandle, intent.Detected))
                throw new AccountBridgeHostException("identity.observation_changed");
        }
        Current();
        var remote = await _legacyPasswordLogin.ReadHandleAsync(legacy, Current, token);
        Current();
        if (!SameHandle(remote.Handle, intent.Expected)) {
            ApplyLegacyHandle(remote);
            throw new AccountBridgeHostException("identity.account_changed");
        }
        _uncertainHandleWrite = intent;
        try {
            var written = await _legacyPasswordLogin.WriteHandleAsync(legacy, intent.Detected, Current, token);
            Current();
            if (!SameHandle(written.Handle, intent.Detected)) throw new AccountBridgeHostException("identity.outcome_unknown");
            var readback = await _legacyPasswordLogin.ReadHandleAsync(legacy, Current, token);
            Current();
            if (!SameHandle(readback.Handle, intent.Detected)) throw new AccountBridgeHostException("identity.outcome_unknown");
            _uncertainHandleWrite = null;
            ApplyLegacyHandle(readback);
            return new { schemaVersion = 1, outcome = "confirmed" };
        } catch (AccountBridgeHostException error) when (error.Code == "identity.change_rejected") {
            _uncertainHandleWrite = null;
            throw;
        } catch {
            // Preserve the uncertainty for read-only reconciliation. Do not report
            // "unchanged" or resend after timeout, cancellation or malformed success.
            throw new AccountBridgeHostException("identity.outcome_unknown");
        }
    }

    private void RequireHandleOwner(BridgeAccountContext context, long generation,
        Auth.LegacyMigrationCredential legacy, CancellationToken token)
    {
        token.ThrowIfCancellationRequested();
        if (_disposed || _session is not null || Generation != generation || CurrentContext != context ||
            _legacySession != legacy || _reauthorizationRequired || _credentialTemporarilyUnavailable || _legacyRestoreUnavailable)
            throw new AccountBridgeHostException("account.reauthorization_required");
    }

    private void ApplyLegacyHandle(ScmGameIdentitySnapshot identity) =>
        PublishLegacySession(_legacySession!, displayName: _legacyDisplayName, identity: identity,
            avatarImageData: _legacyAvatarImageData, entitlements: _legacyEntitlements);

    private static bool SameHandle(string? a, string? b) =>
        !string.IsNullOrWhiteSpace(a) && !string.IsNullOrWhiteSpace(b) && string.Equals(a, b, StringComparison.OrdinalIgnoreCase);

    private static string HandleConfirmationId(JsonElement payload)
    {
        if (payload.ValueKind != JsonValueKind.Object || payload.EnumerateObject().Count() != 2 ||
            !payload.TryGetProperty("schemaVersion", out var schema) || !schema.TryGetInt32(out var version) || version != 1 ||
            !payload.TryGetProperty("confirmationId", out var id) || id.ValueKind != JsonValueKind.String ||
            !Guid.TryParseExact(id.GetString(), "N", out _))
            throw new AccountBridgeHostException("identity.confirmation_invalid");
        return id.GetString()!;
    }
}
