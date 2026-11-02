using System.Text.Json;
using StarBridge.Core.Presence;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Settings;

internal sealed record PublicationVisibilitySnapshot(BridgeAccountContext? Owner, long Generation,
    string Revision, int? Observation, PlayerPresenceVisibilityMode Mode, string? SuspensionError);

// The coordinator callback is PrivacyPublication.ChangeVisibilityAsync, not a
// second publisher. Its change callback runs under the existing sender gate.
internal sealed class PresenceVisibilityBridge(
    PresenceVisibilityStore store,
    Func<(BridgeAccountContext? Owner, long Generation)> current,
    Func<BridgeAccountContext, long, Func<CancellationToken, Task>, CancellationToken, Task<bool>> coordinate,
    Func<BridgeAccountContext, long, PlayerPresenceVisibilityMode, CancellationToken, Task<PlayerPresenceVisibilityMode>> authority,
    Func<bool>? requiresSessionConfirmation = null,
    Func<int?>? realtimeStatus = null,
    Action<PublicationVisibilitySnapshot, bool>? observeVisibility = null)
    : IBridgeRequestDispatcher
{
    private readonly SemaphoreSlim _gate = new(1, 1);
    private volatile bool _disposed;
    private sealed record UncertainScope(BridgeAccountContext? Owner, long Generation);
    private UncertainScope? _uncertain;
    private sealed record ConfirmedScope(BridgeAccountContext? Owner, long Generation, string Revision);
    private ConfirmedScope? _confirmed;
    private ConfirmedScope? _explicitOnlineResume;
    private ConfirmedScope? _awaitingOnlineObservation;
    // Deterministic barrier after the one observation read, before projection.
    internal Action? SnapshotCaptured { get; set; }
    internal bool ConsumeExplicitOnlineResume(BridgeAccountContext owner, long generation)
    {
        var resume = Interlocked.Exchange(ref _explicitOnlineResume, null);
        return resume is not null && resume.Owner == owner && resume.Generation == generation &&
            current() == (owner, generation) && resume.Revision == store.Read().Revision;
    }
    private bool AwaitingOnlineObservation((BridgeAccountContext? Owner, long Generation) scope, string revision, int? observed)
    {
        var pending = Volatile.Read(ref _awaitingOnlineObservation);
        if (pending is null || pending.Owner != scope.Owner || pending.Generation != scope.Generation || pending.Revision != revision)
            return false;
        if (observed is null or 0 or 3) return true;
        if (observed is 1 or 2) Interlocked.CompareExchange(ref _awaitingOnlineObservation, null, pending);
        return false;
    }
    private bool NeedsConfirmation((BridgeAccountContext? Owner, long Generation) scope, string revision)
    {
        if (requiresSessionConfirmation?.Invoke() != true) return false;
        var confirmed = Volatile.Read(ref _confirmed);
        return confirmed is null || confirmed.Owner != scope.Owner || confirmed.Generation != scope.Generation || confirmed.Revision != revision;
    }
    private bool IsUncertain((BridgeAccountContext? Owner, long Generation) scope)
    {
        var pending = Volatile.Read(ref _uncertain);
        return pending is not null && pending.Owner == scope.Owner && pending.Generation == scope.Generation;
    }
    public event Action<BridgeEnvelope>? EventReady { add { } remove { } }
    internal void ConfirmObservedModeForExplicitSharing(BridgeAccountContext owner, long generation)
    {
        // A sharing action (including restoration of account-scoped consent)
        // may use current server evidence, never a stored preference alone.
        // This confirms observation only; it never issues a remote PUT.
        var scope = current();
        if (_disposed || scope.Owner != owner || scope.Generation != generation || IsUncertain(scope) ||
            requiresSessionConfirmation?.Invoke() != true) return;
        try
        {
            var saved = store.Read();
            var snapshot = ReadPublicationSnapshot(wakePublication: false, captureForPublication: false);
            var observed = snapshot.Observation;
            if (saved.Mode == PlayerPresenceVisibilityMode.Invisible || observed is not (1 or 2)) return;
            if (saved.Mode == PlayerPresenceVisibilityMode.InGame && observed != 2) return;
            if (current() != scope || IsUncertain(scope)) return;
            Volatile.Write(ref _confirmed, new ConfirmedScope(owner, generation, saved.Revision));
        }
        catch (Exception error) when (StorageFailure(error)) { /* Publication remains blocked. */ }
    }
    public PlayerPresenceVisibilityMode PublicationMode => ReadPublicationSnapshot().Mode;
    internal PublicationVisibilitySnapshot ReadPublicationSnapshot(bool wakePublication = true, bool captureForPublication = true)
    {
        var scope = current();
        PublicationVisibilitySnapshot Result(string revision, int? observation, PlayerPresenceVisibilityMode mode, string? error)
        {
            var snapshot = new PublicationVisibilitySnapshot(scope.Owner, scope.Generation, revision, observation, mode, error);
            observeVisibility?.Invoke(snapshot, wakePublication);
            return snapshot;
        }
        const PlayerPresenceVisibilityMode invisible = PlayerPresenceVisibilityMode.Invisible;
        if (_disposed) return Result("", null, invisible, "privacy_publication.account_changed");
        string capturedRevision = "";
        int? capturedObservation = null;
        try
        {
            var saved = store.Read();
            capturedRevision = saved.Revision;
            var requiresConfirmation = requiresSessionConfirmation?.Invoke() == true;
            var observed = realtimeStatus?.Invoke();
            capturedObservation = observed;
            var awaiting = AwaitingOnlineObservation(scope, saved.Revision, observed);
            var uncertain = IsUncertain(scope);
            var needsConfirmation = NeedsConfirmation(scope, saved.Revision);
            if (captureForPublication) SnapshotCaptured?.Invoke();
            if (_disposed || current() != scope || store.Read().Revision != saved.Revision)
                return Result(saved.Revision, observed, invisible, "privacy_publication.account_changed");
            string? error = null;
            var mode = saved.Mode;
            if (mode != invisible)
            {
                if (awaiting) error = observed is null or 0 ? "privacy_publication.network_unavailable" : "privacy_publication.identity_pending";
                else if (requiresConfirmation && observed == 3) mode = invisible;
                else if (uncertain) error = "privacy_publication.identity_pending";
                else if (requiresConfirmation && realtimeStatus is not null && observed is not (1 or 2))
                    error = observed is null or 0 ? "privacy_publication.network_unavailable" : "privacy_publication.response_invalid";
                else if (needsConfirmation) error = "privacy_publication.identity_pending";
            }
            return Result(saved.Revision, observed, error is null ? mode : invisible, error);
        }
        catch (Exception error) when (StorageFailure(error))
        {
            // A later settings read may fail after observing a definite 3.
            // Preserve that evidence; the observer independently validates owner.
            return Result(capturedRevision, capturedObservation, invisible,
                error is IOException io && (io.HResult & 0xffff) is 32 or 33
                    ? "privacy_local.read_unavailable" : "privacy_local.read_failed");
        }
    }
    public async ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken cancellationToken = default)
    {
        await _gate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            BridgeEnvelopeValidator.ValidateWireShape(request);
            BridgeEnvelopeValidator.RequireCurrentVersion(request);
            var scope = current();
            void Ensure()
            {
                ObjectDisposedException.ThrowIf(_disposed, this);
                cancellationToken.ThrowIfCancellationRequested();
                if (scope.Owner is null || current() != scope || request.AccountContext != scope.Owner ||
                    request.SessionGeneration != scope.Generation) throw new PresenceAccountChangedException();
            }
            Ensure();
            if (request.MessageType != BridgeMessageTypes.Request || request.Name is not ("presence.read" or "presence.set"))
                return Error(request, "invalid_request");
            var setting = request.Name == "presence.set";
            var expected = setting ? new[] { "schemaVersion", "expectedRevision", "mode" } : ["schemaVersion"];
            var body = request.Payload;
            if (body.ValueKind != JsonValueKind.Object || body.GetRawText().Length > 512) return Error(request, "invalid_request");
            var names = body.EnumerateObject().Select(p => p.Name).ToArray();
            if (names.Length != expected.Length || names.Distinct().Count() != names.Length || names.Except(expected).Any() ||
                body.GetProperty("schemaVersion").GetInt32() != 1) return Error(request, "invalid_request");
            var saved = store.Read();
            if (setting)
            {
                var revision = body.GetProperty("expectedRevision").GetString();
                if (revision != saved.Revision) return Error(request, "conflict");
                var mode = ParseMode(body.GetProperty("mode").GetString());
                if (mode is null) return Error(request, "invalid_request");
                var previousUncertain = Volatile.Read(ref _uncertain);
                var pendingScope = new UncertainScope(scope.Owner, scope.Generation);
                Volatile.Write(ref _uncertain, pendingScope); // Block positive sends until confirmed.
                var authorityCommitted = false;
                try
                {
                    var completed = await coordinate(scope.Owner!, scope.Generation, async token =>
                    {
                        void EnsureChange() { token.ThrowIfCancellationRequested(); Ensure(); }
                        EnsureChange();
                        var confirmed = await authority(scope.Owner!, scope.Generation, mode.Value, token).ConfigureAwait(false);
                        EnsureChange();
                        if (confirmed != mode.Value) throw new InvalidOperationException();
                        saved = store.Save(confirmed, saved.Revision, EnsureChange);
                        // A device preference is not SCM authority. Confirmation is
                        // scoped to this successful write, account generation and revision.
                        Volatile.Write(ref _confirmed, new ConfirmedScope(scope.Owner, scope.Generation, saved.Revision));
                        var online = confirmed is PlayerPresenceVisibilityMode.Online or PlayerPresenceVisibilityMode.InGame;
                        var resume = online ? new ConfirmedScope(scope.Owner, scope.Generation, saved.Revision) : null;
                        Volatile.Write(ref _explicitOnlineResume, resume);
                        Volatile.Write(ref _awaitingOnlineObservation, requiresSessionConfirmation?.Invoke() == true ? resume : null);
                        // The existing publisher now evaluates this durable mode.
                        Volatile.Write(ref _uncertain, null);
                        authorityCommitted = true;
                    }, cancellationToken).ConfigureAwait(false);
                    Ensure();
                    if (!completed && !authorityCommitted) Volatile.Write(ref _uncertain, pendingScope);
                }
                catch (Exception error)
                {
                    if (!authorityCommitted)
                        Volatile.Write(ref _uncertain, error is OperationCanceledException or TimeoutException || current() != scope
                            ? previousUncertain : pendingScope);
                    throw;
                }
            }
            Ensure();
            var state = IsUncertain(scope) || NeedsConfirmation(scope, saved.Revision) ? "unconfirmed" : "ready";
            if (realtimeStatus is not null && requiresSessionConfirmation?.Invoke() == true)
            {
                var snapshot = ReadPublicationSnapshot();
                return new(BridgeEnvelope.Response(request, new { schemaVersion = 1, state,
                    revision = saved.Revision, mode = WireMode(saved.Mode), realtimeStatus = snapshot.Observation }), []);
            }
            return new(BridgeEnvelope.Response(request, new { schemaVersion = 1, state,
                revision = saved.Revision, mode = WireMode(saved.Mode) }), []);
        }
        catch (PresenceAccountChangedException) { return Error(request, "account_changed"); }
        catch (PresenceVisibilityConflictException) { return Error(request, "conflict"); }
        catch (OperationCanceledException) { return new(BridgeEnvelope.CancelledResponse(request), []); }
        catch (BridgeProtocolException e) { return new(BridgeEnvelope.ErrorResponse(request, new(e.Code, "Request rejected.")), []); }
        catch (Exception e) when (StorageFailure(e)) { return Error(request, "storage_unavailable"); }
        catch (Exception) { return Error(request, "unavailable"); }
        finally { _gate.Release(); }
    }
    private static bool StorageFailure(Exception e) => e is IOException or InvalidDataException or UnauthorizedAccessException or JsonException or System.Security.SecurityException;
    internal static string WireMode(PlayerPresenceVisibilityMode mode) => mode switch {
        PlayerPresenceVisibilityMode.Online => "online", PlayerPresenceVisibilityMode.InGame => "inGame",
        PlayerPresenceVisibilityMode.Invisible => "invisible", _ => throw new InvalidDataException()
    };
    private static PlayerPresenceVisibilityMode? ParseMode(string? mode) => mode switch {
        "online" => PlayerPresenceVisibilityMode.Online, "inGame" => PlayerPresenceVisibilityMode.InGame,
        "invisible" => PlayerPresenceVisibilityMode.Invisible, _ => null
    };
    private static BridgeDispatchBatch Error(BridgeEnvelope request, string code) =>
        new(BridgeEnvelope.ErrorResponse(request, new("presence." + code, "Presence could not be updated.")), []);
    public void Dispose() { _disposed = true; }
    private sealed class PresenceAccountChangedException : Exception;
}

