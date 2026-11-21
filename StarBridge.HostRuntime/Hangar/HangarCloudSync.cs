using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Hangar;

/// <summary>
/// Keeps the account copy of the local hangar (always on, user 11-05: "存到账号应该是必须的"). Rules for 0.7.3:
/// a non-empty local hangar is the source and is uploaded a few seconds after each local save;
/// the account copy is restored only into an account that has never saved a local hangar.
/// There is no switch; nothing is uploaded before the server has answered. SCM sign-in only.
/// Bridge requests: hangarReader.cloudRead, hangarReader.cloudAcknowledge.
/// </summary>
internal sealed class HangarCloudSync : IDisposable
{
    private sealed record Owner(BridgeAccountContext Account, long Generation);

    private readonly LocalHangarStore _store;
    private readonly HangarCloudSettingsStore _settings;
    private readonly IHangarArchiveRemote _remote;
    private readonly Func<HangarAccountIdentity?> _current;
    private readonly Action<long> _changed;
    private readonly Func<TimeSpan, CancellationToken, Task> _delay;
    private readonly TimeSpan _debounce;
    private readonly object _gate = new();
    private readonly SemaphoreSlim _io = new(1, 1);
    private CancellationTokenSource _lifetime = new();
    private CancellationTokenSource? _pendingUpload;
    private Owner? _restoreChecked;
    // Per current owner, reset on account change. Never persisted, never contains hangar data.
    private Owner? _stateOwner;
    private string _lastResult = "idle";
    private DateTimeOffset? _lastSyncedAt;
    private int? _restoredCount;
    // The server has answered for this owner (build 65: an unasked server read as available, so the
    // switch showed before the 404 arrived). Unknown and 404 both show "this computer only".
    private Owner? _confirmed;
    // The first check of this owner (one read of the account copy, then restore or upload).
    private Task? _check;
    private bool _disposed;

    internal HangarCloudSync(LocalHangarStore store, HangarCloudSettingsStore settings, IHangarArchiveRemote remote,
        Func<HangarAccountIdentity?> current, Action<long> changed,
        Func<TimeSpan, CancellationToken, Task>? delay = null, TimeSpan? debounce = null)
    {
        _store = store; _settings = settings; _remote = remote; _current = current; _changed = changed;
        _delay = delay ?? Task.Delay;
        _debounce = debounce ?? TimeSpan.FromSeconds(5);
    }

    private Owner? CurrentOwner() => _current() is { } identity ? new(identity.Account, identity.Generation) : null;

    private bool Supported(Owner owner) => _remote.Supports(owner.Account, owner.Generation);

    private void ResetStateFor(Owner owner)
    {
        if (_stateOwner == owner) return;
        _stateOwner = owner; _lastResult = "idle"; _lastSyncedAt = null; _restoredCount = null; _confirmed = null;
    }

    /// <summary>A real answer (not a 404) from the account copy endpoint for this owner.</summary>
    private void Confirm(Owner owner, HangarArchiveOutcome outcome)
    {
        if (outcome is not (HangarArchiveOutcome.Ok or HangarArchiveOutcome.Conflict)) return;
        bool first;
        lock (_gate)
        {
            if (_disposed || CurrentOwner() != owner) return;
            ResetStateFor(owner);
            first = _confirmed != owner;
            _confirmed = owner;
        }
        if (first) _changed(owner.Generation); // the hangar page reads again and shows the switch
    }

    /// <summary>After any committed local hangar change. Uploads the latest local state once, a few seconds later.</summary>
    internal void LocalSaved(BridgeAccountContext account, long generation)
    {
        var owner = new Owner(account, generation);
        CancellationTokenSource pending;
        lock (_gate)
        {
            if (_disposed || CurrentOwner() != owner || !Supported(owner)) return;
            _pendingUpload?.Cancel();
            pending = _pendingUpload = CancellationTokenSource.CreateLinkedTokenSource(_lifetime.Token);
        }
        _ = Task.Run(async () =>
        {
            try
            {
                await _delay(_debounce, pending.Token).ConfigureAwait(false);
                await UploadAsync(owner, pending.Token).ConfigureAwait(false);
            }
            catch (OperationCanceledException) when (!pending.IsCancellationRequested)
            { Record(owner, "failed"); } // the request budget ran out; the next save or sign-in tries again
            catch (OperationCanceledException) { }
        });
    }

    /// <summary>
    /// On sign-in, account switch or the first hangar open: one read of the account copy tells whether the server
    /// holds it (404 = not yet), then restores into a never-saved local hangar or uploads an existing one.
    /// A second call while the first runs gets the same task.
    /// </summary>
    internal Task RestoreIfEmptyAsync(CancellationToken token = default)
    {
        var owner = CurrentOwner();
        if (owner is null) return Task.CompletedTask;
        lock (_gate)
        {
            if (_disposed || !Supported(owner)) return Task.CompletedTask;
            if (_restoreChecked == owner) return _check ?? Task.CompletedTask;
            _restoreChecked = owner;
            return _check = Task.Run(() => CheckAsync(owner, token));
        }
    }

    private async Task CheckAsync(Owner owner, CancellationToken token)
    {
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(token, _lifetime.Token);
        await _io.WaitAsync(linked.Token).ConfigureAwait(false);
        try
        {
            var read = await _remote.ReadArchiveAsync(owner.Account, owner.Generation, linked.Token).ConfigureAwait(false);
            if (read.Outcome != HangarArchiveOutcome.Ok)
            {
                Record(owner, Name(read.Outcome));
                // A 404 stays for this session; anything else is asked again on the next open or sign-in.
                if (read.Outcome != HangarArchiveOutcome.Unsupported)
                    lock (_gate) if (_restoreChecked == owner) _restoreChecked = null;
                return;
            }
            Confirm(owner, read.Outcome);
            if (_store.Read(owner.Account).Revision != 0)
            {
                // Signed in with a hangar already on this computer (including users upgrading from 0.7.2):
                // make sure the account copy is current once per sign-in, then keep following saves.
                LocalSaved(owner.Account, owner.Generation);
                return;
            }
            if (!read.Exists || read.Archive is not { } archive) return;
            var document = HangarArchive.Parse(archive);
            if (document.Ships.Count == 0 && (document.FormerShips?.Count ?? 0) == 0) return;
            var restored = _store.RestoreFromArchive(owner.Account, document, Guid.NewGuid().ToString("N"),
                () => !linked.IsCancellationRequested && CurrentOwner() == owner);
            if (restored is null) return;
            lock (_gate)
            {
                if (_disposed || CurrentOwner() != owner) return;
                ResetStateFor(owner);
                _restoredCount = restored.Ships.Count;
                _lastResult = "restored";
            }
            _changed(owner.Generation);
        }
        catch (Exception error) when (error is not OperationCanceledException and not OutOfMemoryException)
        {
            lock (_gate)
            {
                // A network failure is retried when the hangar is next opened or on the next sign-in; an
                // unusable account copy is not downloaded again in this session. Never blocks the hangar.
                var unusable = error is LocalHangarStoreException { Code: "hangar.archive_invalid" };
                if (_restoreChecked == owner && !unusable) _restoreChecked = null;
                if (CurrentOwner() == owner) { ResetStateFor(owner); _lastResult = unusable ? "archiveInvalid" : "restoreFailed"; }
            }
        }
        catch (OperationCanceledException)
        {
            lock (_gate)
            {
                if (_restoreChecked == owner) _restoreChecked = null;
                // The request budget ran out (not a cancel by the caller or shutdown): say so.
                if (!token.IsCancellationRequested && !_lifetime.IsCancellationRequested && CurrentOwner() == owner)
                { ResetStateFor(owner); _lastResult = "restoreFailed"; }
            }
        }
        finally { _io.Release(); }
    }

    private async Task UploadAsync(Owner owner, CancellationToken token)
    {
        await _io.WaitAsync(token).ConfigureAwait(false);
        try
        {
            if (CurrentOwner() != owner) return;
            var snapshot = _store.Read(owner.Account);
            // Nothing saved locally yet: never upload an empty hangar over an account copy.
            if (snapshot.Revision == 0 || snapshot.Ships.Count == 0 && (snapshot.FormerShips?.Count ?? 0) == 0) return;
            var bytes = HangarArchive.Serialize(HangarArchive.FromSnapshot(snapshot));
            if (bytes.Length > HangarArchive.MaximumBytes) { Record(owner, "tooLarge"); return; }
            var read = await _remote.ReadArchiveAsync(owner.Account, owner.Generation, token).ConfigureAwait(false);
            if (read.Outcome != HangarArchiveOutcome.Ok) { Record(owner, Name(read.Outcome)); return; }
            Confirm(owner, read.Outcome);
            var write = await _remote.WriteArchiveAsync(owner.Account, owner.Generation, read.Revision, bytes, token).ConfigureAwait(false);
            if (write.Outcome == HangarArchiveOutcome.Conflict)
                // Another device wrote in between. In 0.7.3 a non-empty local hangar wins: one retry at the newer revision.
                write = await _remote.WriteArchiveAsync(owner.Account, owner.Generation, write.Revision, bytes, token).ConfigureAwait(false);
            if (write.Outcome == HangarArchiveOutcome.Ok)
            {
                var firstUpload = false;
                lock (_gate)
                {
                    if (_disposed || CurrentOwner() != owner) return;
                    ResetStateFor(owner);
                    _lastResult = "saved";
                    _lastSyncedAt = DateTimeOffset.UtcNow;
                    _confirmed = owner;
                }
                var settings = _settings.Read(owner.Account);
                if (!settings.NoticeShown) firstUpload = true;
                if (firstUpload) _changed(owner.Generation);
                return;
            }
            Record(owner, Name(write.Outcome));
        }
        catch (Exception error) when (error is not OperationCanceledException and not OutOfMemoryException)
        { Record(owner, "failed"); }
        finally { _io.Release(); }
    }

    private void Record(Owner owner, string result)
    {
        lock (_gate)
        {
            if (CurrentOwner() != owner) return;
            ResetStateFor(owner);
            _lastResult = result;
        }
    }

    private static string Name(HangarArchiveOutcome outcome) => outcome switch
    {
        HangarArchiveOutcome.Unsupported => "unsupported",
        HangarArchiveOutcome.RateLimited => "rateLimited",
        HangarArchiveOutcome.Invalid => "invalid",
        HangarArchiveOutcome.Conflict => "conflict",
        _ => "failed"
    };

    internal async Task<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken token)
    {
        try
        {
            BridgeEnvelopeValidator.ValidateWireShape(request);
            BridgeEnvelopeValidator.RequireCurrentVersion(request);
            var owner = CurrentOwner();
            if (request.MessageType != BridgeMessageTypes.Request || owner is null ||
                request.AccountContext != owner.Account || request.SessionGeneration != owner.Generation)
                return Error(request, "hangar.account_changed");
            var body = request.Payload;
            if (body.ValueKind != JsonValueKind.Object || body.GetRawText().Length > 1024 ||
                !body.TryGetProperty("schemaVersion", out var schema) || schema.ValueKind != JsonValueKind.Number ||
                !schema.TryGetInt32(out var version) || version != 1)
                return Error(request, "hangar.invalid_request");
            var fields = body.EnumerateObject().Select(p => p.Name).ToArray();
            if (fields.Distinct(StringComparer.Ordinal).Count() != fields.Length) return Error(request, "hangar.invalid_request");
            switch (request.Name)
            {
                case "hangarReader.cloudRead":
                    if (fields.Any(f => f != "schemaVersion")) return Error(request, "hangar.invalid_request");
                    // First open: wait briefly for the server's answer so the page shows one state, not two.
                    var check = RestoreIfEmptyAsync();
                    if (Unknown(owner)) await Task.WhenAny(check, Task.Delay(ProbeWait, token)).ConfigureAwait(false);
                    return View(request, owner);
                case "hangarReader.cloudAcknowledge":
                    if (fields.Any(f => f is not ("schemaVersion" or "notice")) || !body.TryGetProperty("notice", out var noticeValue) ||
                        noticeValue.ValueKind != JsonValueKind.String) return Error(request, "hangar.invalid_request");
                    var notice = noticeValue.GetString();
                    if (notice == "firstUpload")
                        _settings.Update(owner.Account, current => current with { NoticeShown = true });
                    else if (notice == "restored") { lock (_gate) if (_stateOwner == owner) _restoredCount = null; }
                    else return Error(request, "hangar.invalid_request");
                    return View(request, owner);
                default:
                    return Error(request, BridgeErrorCodes.CapabilityUnavailable);
            }
        }
        catch (OperationCanceledException) { throw; }
        catch (LocalHangarStoreException error) { return Error(request, error.Code); }
        catch (AccountBridgeHostException) { return Error(request, "hangar.account_changed"); }
        catch (Exception error) when (error is HttpRequestException or IOException or ScmApiUnavailableException or
                                         ScmApiProtocolException or ScmApiForbiddenException or JsonException or
                                         InvalidOperationException or KeyNotFoundException)
        {
            return Error(request, "hangar.invalid_request");
        }
    }

    private BridgeDispatchBatch View(BridgeEnvelope request, Owner owner)
    {
        var settings = _settings.Read(owner.Account);
        string result; DateTimeOffset? synced; int? restored; bool confirmed;
        lock (_gate)
        {
            if (_stateOwner != owner) ResetStateFor(owner);
            result = _lastResult; synced = _lastSyncedAt; restored = _restoredCount; confirmed = _confirmed == owner;
        }
        // Only after the server answered: before the HK release a 404 (or no answer yet) means no account copy.
        var available = Supported(owner) && confirmed && result != "unsupported";
        return new(BridgeEnvelope.Response(request, new
        {
            schemaVersion = 1,
            available,
            firstUploadNotice = available && !settings.NoticeShown && result == "saved",
            restoredShips = restored,
            lastResult = result,
            lastSavedAt = synced
        }), []);
    }

    private static readonly TimeSpan ProbeWait = TimeSpan.FromSeconds(3);

    /// <summary>The server has not answered for this owner yet (neither confirmed nor 404).</summary>
    private bool Unknown(Owner owner)
    {
        lock (_gate)
        {
            if (_disposed || !Supported(owner)) return false;
            if (_stateOwner != owner) ResetStateFor(owner);
            return _confirmed != owner && _lastResult != "unsupported";
        }
    }

    private static BridgeDispatchBatch Error(BridgeEnvelope request, string code) =>
        new(BridgeEnvelope.ErrorResponse(request, new(code, "The account hangar copy request failed.")), []);

    internal void Invalidate(long _ = 0)
    {
        lock (_gate)
        {
            _pendingUpload?.Cancel();
            _pendingUpload = null;
            _restoreChecked = null;
            _stateOwner = null;
            _confirmed = null;
            _check = null;
        }
    }

    public void Dispose()
    {
        lock (_gate)
        {
            if (_disposed) return;
            _disposed = true;
            _pendingUpload?.Cancel();
            _lifetime.Cancel();
        }
    }
}
