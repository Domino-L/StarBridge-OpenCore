using System.Text.Json;
using StarBridge.Core.Friends;
using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Account;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Privacy;

internal sealed class FriendSharingRuntime : IDisposable
{
    private readonly IFriendSharingRemote _remote;
    private readonly Func<PrivacyPublicationInput?> _current;
    private readonly Func<bool> _allowed;
    private readonly Func<PlayerPresenceVisibilityMode> _visibility;
    private readonly SemaphoreSlim _gate = new(1, 1);
    private readonly CancellationTokenSource _lifetime = new();
    private readonly ITimer? _timer;
    private FriendSharingPublication _publisher;
    private FriendSharingRemoteSnapshot? _saved;
    private PrivacyPublicationInput? _owner;
    private DateTimeOffset _lastRead;
    private int _paused;
    private bool _shutdown, _disposed;
    internal string State { get; private set; } = "inactive";

    internal FriendSharingRuntime(IFriendSharingRemote remote, Func<PrivacyPublicationInput?> current,
        Func<bool> allowed, Func<PlayerPresenceVisibilityMode> visibility, bool startTimer = true)
    {
        _remote = remote; _current = current; _allowed = allowed; _visibility = visibility;
        _publisher = CreatePublisher();
        if (startTimer) _timer = TimeProvider.System.CreateTimer(_ => _ = TickAsync(), null,
            TimeSpan.FromSeconds(5), TimeSpan.FromSeconds(5));
    }
    private FriendSharingPublication CreatePublisher() => new(Snapshot,
        (value, ct) => _remote.WriteFriendLiveAsync(value.Input, "start", value.Revision, null, 0, null, ct),
        async (value, session, sequence, source, ct) => { await _remote.WriteFriendLiveAsync(value.Input, "publish", value.Revision, session, sequence, source, ct); },
        async (value, session, ct) => { await _remote.WriteFriendLiveAsync(value.Input, _shutdown ? "offline" : "stop", value.Revision, session, 0, null, ct); });
    private FriendSharingPublicationSnapshot? Snapshot()
    {
        var input = _current();
        if (_disposed || input is null || _saved?.Fields is not { } fields || _owner is null ||
            input.Owner != _owner.Owner || input.Generation != _owner.Generation) return null;
        return new(input, _saved.Revision, fields, !_shutdown && _paused == 0 && _allowed() &&
            DateTimeOffset.UtcNow - _lastRead < TimeSpan.FromSeconds(20), _visibility());
    }
    internal void Pause() => Interlocked.Increment(ref _paused);
    internal void Resume() => Interlocked.Decrement(ref _paused);
    internal async Task<bool> StopAsync(CancellationToken token, bool shutdown = false)
    {
        if (shutdown) _shutdown = true;
        await _gate.WaitAsync(token);
        try { await _publisher.StopAsync(token); State = "inactive"; return true; }
        catch { State = "unconfirmed"; return false; }
        finally { _gate.Release(); }
    }
    internal async Task TickAsync()
    {
        if (_disposed || !await _gate.WaitAsync(0)) return;
        try
        {
            var input = _current();
            if (_owner is not null && (input is null || input.Owner != _owner.Owner || input.Generation != _owner.Generation))
            {
                // Old credentials must never be substituted with the new login.
                // Its unrenewed source is bounded by the server's 45-second lease.
                _publisher = CreatePublisher(); _saved = null; _lastRead = default; _shutdown = false;
            }
            _owner = input;
            if (input is null) { State = "inactive"; return; }
            if (_paused != 0 || _shutdown || !_allowed() || !input.IdentityConfirmed)
            { await _publisher.StopAsync(_lifetime.Token); State = "inactive"; return; }
            if (_saved is null || DateTimeOffset.UtcNow - _lastRead >= TimeSpan.FromSeconds(15))
            {
                _saved = null;
                var value = await _remote.ReadFriendSharingAsync(input.Owner, input.Generation, _lifetime.Token);
                if (_current() is not { } current || current.Owner != input.Owner || current.Generation != input.Generation) return;
                _saved = value; _lastRead = DateTimeOffset.UtcNow;
            }
            await _publisher.TickAsync(_lifetime.Token);
            State = Snapshot()?.Enabled == true ? "active" : "inactive";
        }
        catch
        {
            _saved = null; _lastRead = default; State = "unconfirmed";
            try { await _publisher.StopAsync(_lifetime.Token); } catch { }
        }
        finally { _gate.Release(); }
    }
    internal async Task<FriendSharingRemoteSnapshot> ReadAsync(BridgeAccountContext owner, long generation, CancellationToken token) =>
        await _remote.ReadFriendSharingAsync(owner, generation, token);
    internal async Task<FriendSharingRemoteSnapshot> SaveAsync(BridgeAccountContext owner, long generation,
        long revision, string operation, FriendSharedFields fields, CancellationToken token)
    {
        Pause();
        try
        {
            await _gate.WaitAsync(token);
            try
            {
            _saved = null; _lastRead = default;
            // Remote narrowing must remain possible even when withdrawal failed.
            try { await _publisher.StopAsync(token); } catch (Exception e) when (e is not OperationCanceledException) { }
            var result = await _remote.SaveFriendSharingAsync(owner, generation, revision, operation, fields, token);
            State = "inactive";
            return result;
            }
            finally { _gate.Release(); }
        }
        finally { Resume(); }
    }
    public void Dispose() { _disposed = true; _timer?.Dispose(); _lifetime.Cancel(); }
}

internal sealed class FriendSharingDispatcher(FriendSharingRuntime runtime, Func<(BridgeAccountContext? Context, long Generation)> current)
{
    internal async Task<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken token)
    {
        try
        {
            BridgeEnvelopeValidator.ValidateWireShape(request); BridgeEnvelopeValidator.RequireCurrentVersion(request);
            var owner = current();
            if (owner.Context is null || request.AccountContext != owner.Context || request.SessionGeneration != owner.Generation)
                throw new AccountBridgeHostException("friendsSharing.account_changed");
            var body = request.Payload;
            LocalPrivacyStore.RejectDuplicates(body);
            if (request.MessageType != BridgeMessageTypes.Request || body.GetRawText().Length > 2048 || body.GetProperty("schemaVersion").GetInt32() != 1) throw new JsonException();
            FriendSharingRemoteSnapshot result;
            if (request.Name == "friendSharing.read" && body.EnumerateObject().Count() == 1)
                result = await runtime.ReadAsync(owner.Context, owner.Generation, token);
            else if (request.Name == "friendSharing.save")
            {
                var keys = body.EnumerateObject().Select(p => p.Name).ToArray();
                if (keys.Length != 4 || keys.Any(key => key is not ("schemaVersion" or "expectedRevision" or "operationId" or "fields"))) throw new JsonException();
                var revision = body.GetProperty("expectedRevision").GetInt64();
                var operation = body.GetProperty("operationId").GetString();
                var fields = (FriendSharedFields)body.GetProperty("fields").GetInt32();
                if (revision < 0 || revision == long.MaxValue || !Guid.TryParseExact(operation, "N", out _)) throw new JsonException();
                new FriendSharingPreferences(fields).Validate();
                result = await runtime.SaveAsync(owner.Context, owner.Generation, revision, operation!, fields, token);
            }
            else throw new JsonException();
            if (owner != current()) throw new AccountBridgeHostException("friendsSharing.account_changed");
            return new(BridgeEnvelope.Response(request, new { snapshot = result, state = runtime.State }), []);
        }
        catch (OperationCanceledException) { return new(BridgeEnvelope.CancelledResponse(request), []); }
        catch (AccountBridgeHostException e) { return Error(e.Code); }
        catch (Exception e) when (e is JsonException or ArgumentException or InvalidOperationException or KeyNotFoundException or FormatException)
        { return Error("friendsSharing.invalid_response"); }
        catch (HttpRequestException) { return Error("friendsSharing.temporarily_unavailable"); }
        BridgeDispatchBatch Error(string code) => new(BridgeEnvelope.ErrorResponse(request, new(code, "Friend sharing is unavailable.", true)), []);
    }
}
