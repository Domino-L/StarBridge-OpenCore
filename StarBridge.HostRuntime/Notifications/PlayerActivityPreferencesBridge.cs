using System.Text.Json;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Notifications;

// Do not register until Host has verified the original directory, single writer,
// and the delivery adapter. This adapter is not a notification implementation.
internal sealed class PlayerActivityPreferencesBridge(
    PlayerActivityPreferencesStore store, Func<long> generation,
    Func<bool> canWrite) : IBridgeRequestDispatcher
{
    private readonly object _gate = new();
    private bool _disposed;
    public static IReadOnlyList<string> Capabilities { get; } =
        ["playerActivity.read", "playerActivity.save"];
    public event Action<BridgeEnvelope>? EventReady { add { } remove { } }

    public ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken cancellationToken = default)
    {
        lock (_gate)
        {
            try
            {
                EnsureCurrent(request, cancellationToken);
                BridgeEnvelopeValidator.ValidateWireShape(request);
                BridgeEnvelopeValidator.RequireCurrentVersion(request);
                if (request.AccountContext is not null || request.MessageType != BridgeMessageTypes.Request ||
                    !Capabilities.Contains(request.Name)) return Error(request, "invalid_request");
                var save = request.Name == "playerActivity.save";
                var body = request.Payload;
                RequireFields(body, save
                    ? ["schemaVersion", "expectedRevision", "enabled", "scope", "position", "online", "offline", "startedGame", "stoppedGame", "backgroundOnly", "reduceInGame"]
                    : ["schemaVersion"]);
                if (body.GetProperty("schemaVersion").GetInt32() != 1) return Error(request, "invalid_request");
                PlayerActivityPreferencesSnapshot snapshot;
                if (save)
                {
                    if (!canWrite()) return Error(request, "not_ready");
                    var revision = body.GetProperty("expectedRevision").GetString();
                    if (revision is null || (revision != "missing" &&
                        (revision.Length != 64 || revision.Any(c => !char.IsAsciiHexDigit(c)))))
                        return Error(request, "invalid_request");
                    var value = new PlayerActivityPreferences(
                        body.GetProperty("enabled").GetBoolean(), body.GetProperty("scope").GetInt32(),
                        body.GetProperty("position").GetInt32(), body.GetProperty("online").GetBoolean(),
                        body.GetProperty("offline").GetBoolean(), body.GetProperty("startedGame").GetBoolean(),
                        body.GetProperty("stoppedGame").GetBoolean(), body.GetProperty("backgroundOnly").GetBoolean(),
                        body.GetProperty("reduceInGame").GetBoolean());
                    if (value.Scope is < 0 or > 7 || value.Position is < 0 or > 3) return Error(request, "invalid_request");
                    snapshot = store.Save(value, revision, () => {
                        EnsureCurrent(request, cancellationToken);
                        if (!canWrite()) throw new NotReadyException();
                    });
                }
                else snapshot = store.Read();
                EnsureCurrent(request, cancellationToken);
                var v = snapshot.Value;
                return ValueTask.FromResult(new BridgeDispatchBatch(BridgeEnvelope.Response(request,
                    new { schemaVersion = 1, snapshot.Revision, writable = canWrite(),
                        v.Enabled, v.Scope, v.Position, v.Online, v.Offline, v.StartedGame,
                        v.StoppedGame, v.BackgroundOnly, v.ReduceInGame }, preserveRequestAccountContext: false), []));
            }
            catch (PlayerActivityPreferencesConflictException) { return Error(request, "conflict"); }
            catch (NotReadyException) { return Error(request, "not_ready"); }
            catch (OperationCanceledException) { return ValueTask.FromResult(new BridgeDispatchBatch(BridgeEnvelope.CancelledResponse(request), [])); }
            catch (BridgeProtocolException e) { return ValueTask.FromResult(new BridgeDispatchBatch(BridgeEnvelope.ErrorResponse(request, new(e.Code, "Request rejected.")), [])); }
            catch (ObjectDisposedException) { return Error(request, "unavailable"); }
            catch (InvalidDataException) { return Error(request, "storage_unavailable"); }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException) { return Error(request, "storage_unavailable"); }
            catch (Exception e) when (e is JsonException or ArgumentException or InvalidOperationException or FormatException or OverflowException or KeyNotFoundException)
            { return Error(request, "invalid_request"); }
        }
    }
    private void EnsureCurrent(BridgeEnvelope request, CancellationToken token)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        token.ThrowIfCancellationRequested();
        if (request.SessionGeneration != generation())
            throw new BridgeStaleGenerationException(request.SessionGeneration, generation());
    }
    private static void RequireFields(JsonElement body, string[] expected)
    {
        if (body.ValueKind != JsonValueKind.Object) throw new ArgumentException();
        var names = body.EnumerateObject().Select(p => p.Name).ToArray();
        if (names.Length != expected.Length || names.Distinct(StringComparer.Ordinal).Count() != names.Length ||
            names.Except(expected).Any()) throw new ArgumentException();
    }
    private static ValueTask<BridgeDispatchBatch> Error(BridgeEnvelope request, string suffix) =>
        ValueTask.FromResult(new BridgeDispatchBatch(BridgeEnvelope.ErrorResponse(request,
            new("playerActivity." + suffix, "Player activity settings unavailable.")), []));
    public void Dispose() { lock (_gate) _disposed = true; }
    private sealed class NotReadyException : Exception;
}
