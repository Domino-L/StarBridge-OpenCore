using System.Text.Json;
using StarBridge.Core.Presence;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Settings;

// The coordinator callback is PrivacyPublication.ChangeVisibilityAsync, not a
// second publisher. Its change callback runs under the existing sender gate.
internal sealed class PresenceVisibilityBridge(
    PresenceVisibilityStore store,
    Func<(BridgeAccountContext? Owner, long Generation)> current,
    Func<BridgeAccountContext, long, Func<CancellationToken, Task>, CancellationToken, Task<bool>> coordinate,
    Func<BridgeAccountContext, long, PlayerPresenceVisibilityMode, CancellationToken, Task<PlayerPresenceVisibilityMode>> authority,
    Func<bool>? requiresSessionConfirmation = null)
    : IBridgeRequestDispatcher
{
    private readonly SemaphoreSlim _gate = new(1, 1);
    private volatile bool _disposed;
    private sealed record UncertainScope(BridgeAccountContext? Owner, long Generation);
    private UncertainScope? _uncertain;
    private sealed record ConfirmedScope(BridgeAccountContext? Owner, long Generation, string Revision);
    private ConfirmedScope? _confirmed;
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
    public PlayerPresenceVisibilityMode PublicationMode
    {
        get
        {
            if (_disposed || IsUncertain(current())) return PlayerPresenceVisibilityMode.Invisible;
            try {
                var saved = store.Read();
                return NeedsConfirmation(current(), saved.Revision) ? PlayerPresenceVisibilityMode.Invisible : saved.Mode;
            }
            catch (Exception e) when (StorageFailure(e)) { return PlayerPresenceVisibilityMode.Invisible; }
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
                try
                {
                    var completed = await coordinate(scope.Owner!, scope.Generation, async token =>
                    {
                        Ensure();
                        var confirmed = await authority(scope.Owner!, scope.Generation, mode.Value, token).ConfigureAwait(false);
                        Ensure();
                        if (confirmed != mode.Value) throw new InvalidOperationException();
                        saved = store.Save(confirmed, saved.Revision, Ensure);
                        // A device preference is not SCM authority. Confirmation is
                        // scoped to this successful write, account generation and revision.
                        Volatile.Write(ref _confirmed, new ConfirmedScope(scope.Owner, scope.Generation, saved.Revision));
                        // The existing publisher now evaluates this durable mode.
                        Volatile.Write(ref _uncertain, null);
                    }, cancellationToken).ConfigureAwait(false);
                    Ensure();
                    if (!completed) Volatile.Write(ref _uncertain, pendingScope);
                }
                catch
                {
                    Volatile.Write(ref _uncertain, current() == scope ? pendingScope : previousUncertain);
                    throw;
                }
            }
            Ensure();
            var state = IsUncertain(scope) || NeedsConfirmation(scope, saved.Revision) ? "unconfirmed" : "ready";
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
