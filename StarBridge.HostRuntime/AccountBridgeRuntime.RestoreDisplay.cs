using System.Collections.Concurrent;
using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.HostRuntime.Account;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime;

public sealed partial class AccountBridgeRuntime
{
    private readonly AsyncLocal<RestoreDisplayTransaction?> _restoreDisplayRequest = new();
    private readonly ConcurrentDictionary<string, RestoreDisplayTransaction> _restoreDisplays = new(StringComparer.Ordinal);

    private sealed class RestoreDisplayTransaction(AccountBridgeRuntime owner, BridgeEnvelope request,
        CancellationToken token, RestoreDisplayTransaction? previous, bool requested) : IDisposable
    {
        internal readonly BridgeEnvelope Request = request;
        internal AccountRestoreDisplayScope? Scope;
        internal string? ReadId;
        internal IDisposable? Observation;
        private int _closed;
        private readonly Onboarding.FirstUseModeRuntime? _mode = requested ? owner.FirstUseMode : null;
        private readonly long? _modeRevision = requested ? owner.FirstUseMode?.Current.Revision : null;
        internal bool Current => requested && Volatile.Read(ref _closed) == 0 && !token.IsCancellationRequested &&
            !owner._disposed && !owner._firstUseCandidate && !owner._requestRetirement.IsClosed &&
            ReferenceEquals(_mode, owner.FirstUseMode) && (_mode is null ||
                _mode.Current is { State: "online", ActiveMode: "online" } observed && observed.Revision == _modeRevision);
        public void Dispose()
        {
            if (Interlocked.Exchange(ref _closed, 1) != 0) return;
            if (ReadId is { } id) owner._restoreDisplays.TryRemove(id, out _);
            Observation?.Dispose();
            Scope?.Dispose();
            if (ReferenceEquals(owner._restoreDisplayRequest.Value, this)) owner._restoreDisplayRequest.Value = previous;
        }
    }

    private RestoreDisplayTransaction? EnterRestoreDisplay(BridgeEnvelope request, CancellationToken token)
    {
        if (_firstUseCandidate || request.Name != AccountBridgeRequestNames.GetCurrent ||
            _host is not ScmAccountBridgeHost { MayPrepareRestoreDisplay: true } scm) return null;
        var requested = _offlineAccount is not null && request.AccountContext is null &&
            request.Payload.ValueKind == JsonValueKind.Object &&
            request.Payload.TryGetProperty("restoreDisplayProgress", out var progress) && progress.ValueKind == JsonValueKind.True;
        var next = new RestoreDisplayTransaction(this, request, token, _restoreDisplayRequest.Value, requested);
        _restoreDisplayRequest.Value = next;
        next.Observation = scm.BeginRestoreDisplayObservation(requested ? PrepareRestoreDisplay : null);
        return next;
    }

    private void PrepareRestoreDisplay(AccountRestoreDisplayScope scope)
    {
        var transaction = _restoreDisplayRequest.Value;
        if (transaction is null || !transaction.Current || transaction.Scope is not null ||
            transaction.Request.SessionGeneration != scope.InitialGeneration || _offlineAccount is null)
        { return; }
        transaction.Scope = scope;
        bool Current() => transaction.Current && scope.ReadCurrent() is not null;
        try
        {
            var selected = _offlineAccount.ReadSelectedDisplayOwner(scope.Owner, Current);
            if (selected is not { } snapshot || !Current()) return;
            scope.BindStorageFence(() =>
            {
                if (!scope.HasAuthenticatedOwner) return true;
                try
                {
                    if (_host.ResolveLocalDataOwner(scope.Owner) == snapshot.StorageOwner) return true;
                    // A confirmed different local owner must never be revived
                    // later as merely "not ready" or inherited by this read ID.
                    scope.Dispose();
                    return false;
                }
                catch (Privacy.LocalPrivacyOwnerUnavailableException) { return true; }
                catch (Privacy.LocalPrivacyException) { scope.Dispose(); return false; }
            });
            if (!Current()) return;
            var display = snapshot.Display;
            var id = Guid.NewGuid().ToString("N");
            if (!_restoreDisplays.TryAdd(id, transaction)) return;
            transaction.ReadId = id;
            var previous = Volatile.Read(ref _retainedDataSelection);
            var receipt = scope.ReadCurrent();
            var payload = new
            {
                schemaVersion = 1, rootCorrelationId = transaction.Request.CorrelationId,
                retainedDisplay = new
                {
                    displayName = display.DisplayName, cachedAtUtc = display.CachedAtUtc, readId = id,
                    previousReadId = previous is not null && previous.Generation == scope.InitialGeneration &&
                        previous.Owner == scope.Owner && previous.Credential == receipt ? previous.ReadId : null,
                    avatarImageData = display.AvatarImageData, avatarCachedAtUtc = display.AvatarCachedAtUtc
                }
            };
            // Progress is independently sequenced by the original dispatcher;
            // the root response still precedes its queued account.changed event.
            _dispatcher.PublishRestoreDisplayProgress(transaction.Request.SessionGeneration, payload, Current);
        }
        catch (Exception error) when (CacheFailure(error)) { }
    }

    private (BridgeAccountContext Owner, Func<bool> Current)? ResolveRetainedRead(
        string id, BridgeEnvelope request, CancellationToken token)
    {
        if (_restoreDisplays.TryGetValue(id, out var restore) && restore.Scope is { } scope)
        {
            // The opaque selection is a child of this still-pending root. Only
            // its own authenticated restore may advance its Native binding;
            // no ordinary old-generation account request gets this exception.
            bool Current() => !token.IsCancellationRequested && restore.Current &&
                request.SessionGeneration == restore.Request.SessionGeneration &&
                _restoreDisplays.TryGetValue(id, out var current) && ReferenceEquals(current, restore) &&
                scope.ReadCurrent() is not null;
            return (scope.Owner, Current);
        }
        var access = Volatile.Read(ref _retainedDataSelection);
        if (access is null || access.ReadId != id || _host is not ScmAccountBridgeHost scm) return null;
        bool RetainedCurrent() => !token.IsCancellationRequested && !_disposed &&
            request.SessionGeneration == Generation && access.Generation == Generation &&
            ReferenceEquals(access, Volatile.Read(ref _retainedDataSelection)) &&
            scm.ReadOfflineDisplaySelection() == (access.Owner, access.Credential);
        return (access.Owner, RetainedCurrent);
    }

    private BridgeEnvelope CompleteRestoreDisplay(RestoreDisplayTransaction? restore, BridgeEnvelope response)
    {
        if (restore?.Scope is not { } scope || restore.ReadId is not { } id || !restore.Current ||
            response.Status != "ok" || scope.ReadCurrent() is not { } credential) return response;
        var payload = JsonNode.Parse(response.Payload.GetRawText())!.AsObject();
        if (response.AccountContext == scope.Owner &&
            response.Payload.TryGetProperty("state", out var state) && state.GetString() == "signedIn")
            payload["restoreDisplayReadId"] = id; // continuity only; this read ID is retired on return
        else if (response.AccountContext is null && payload["retainedDisplay"] is JsonObject retained &&
            Volatile.Read(ref _retainedDataSelection) is { } current && current.Owner == scope.Owner &&
            current.Credential == credential)
            payload["restoreDisplayReadId"] = id; // preserve the original retained predecessor for older clients
        else return response;
        return response with { Payload = JsonSerializer.SerializeToElement(payload) };
    }
}
