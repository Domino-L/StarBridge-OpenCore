using System.Text.Json;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Storage;

/// <summary>Advertise only when composition supplies a complete trusted offline
/// handoff. The UI can choose and confirm a ticket, never submit filesystem paths.</summary>
public sealed class StorageMigrationBridgeDispatcher(StorageMigrationSelection selection,
    Func<long> generation) : IBridgeRequestDispatcher
{
    public const string ChooseRequest = "dataLocation.chooseMigration";
    public const string ConfirmRequest = "dataLocation.confirmMigration";
    public const string ResultRequest = "dataLocation.getMigrationResult";
    public const string AcknowledgeRequest = "dataLocation.acknowledgeMigrationResult";
    private readonly StorageMigrationResultStore? _results;
    private bool _disposed;
    public StorageMigrationBridgeDispatcher(StorageMigrationSelection selection, Func<long> generation,
        StorageMigrationResultStore? results = null) : this(selection, generation)
        => _results = results;
    public event Action<BridgeEnvelope>? EventReady { add { } remove { } }

    public async ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken cancellationToken = default)
    {
        try
        {
            cancellationToken.ThrowIfCancellationRequested();
            BridgeEnvelopeValidator.ValidateWireShape(request);
            BridgeEnvelopeValidator.RequireCurrentVersion(request);
            bool Current() => !_disposed && request.SessionGeneration == generation();
            if (!Current() || request.MessageType != BridgeMessageTypes.Request || request.AccountContext is not null ||
                request.Name is not (ChooseRequest or ConfirmRequest or ResultRequest or AcknowledgeRequest) || request.Payload.ValueKind != JsonValueKind.Object ||
                request.Payload.EnumerateObject().Count() != (request.Name is ChooseRequest or ResultRequest ? 1 : 2) ||
                !request.Payload.TryGetProperty("schemaVersion", out var schema) || schema.ValueKind != JsonValueKind.Number ||
                !schema.TryGetInt32(out var version) || version != 1) return Error(request);
            if (request.Name == ResultRequest)
            {
                var result = _results?.Read();
                return new(BridgeEnvelope.Response(request, new { schemaVersion = 1, state = result?.State ?? "none",
                    nonce = result?.Nonce, source = result?.Source, destination = result?.Destination,
                    completedAt = result?.CompletedAt }, preserveRequestAccountContext: false), []);
            }
            if (request.Name == ChooseRequest)
            {
                var choice = await selection.ChooseAsync(Current, cancellationToken);
                return new(BridgeEnvelope.Response(request, new { schemaVersion = 1,
                    state = choice is null ? "unchanged" : "confirmation-required", ticket = choice?.Ticket,
                    source = choice?.Source, destination = choice?.Destination }, preserveRequestAccountContext: false), []);
            }
            var key = request.Name == ConfirmRequest ? "ticket" : "nonce";
            if (!request.Payload.TryGetProperty(key, out var field) || field.ValueKind != JsonValueKind.String ||
                !Guid.TryParseExact(field.GetString(), "N", out _)) return Error(request);
            if (request.Name == AcknowledgeRequest)
            {
                if (_results is null) return Error(request);
                _results.Acknowledge(field.GetString()!);
                return new(BridgeEnvelope.Response(request, new { schemaVersion = 1, acknowledged = true }, preserveRequestAccountContext: false), []);
            }
            await selection.ConfirmAsync(field.GetString()!, Current, cancellationToken);
            return new(BridgeEnvelope.Response(request, new { schemaVersion = 1, accepted = true }, preserveRequestAccountContext: false), []);
        }
        catch (OperationCanceledException) { return new(BridgeEnvelope.CancelledResponse(request), []); }
        catch (StorageMigrationWpfRunningException)
        {
            return new(BridgeEnvelope.ErrorResponse(request,
                new BridgeError("dataLocation.wpf_running", "Close the WPF client before moving local data.")), []);
        }
        catch { return Error(request); }
    }
    private static BridgeDispatchBatch Error(BridgeEnvelope request) => new(BridgeEnvelope.ErrorResponse(request,
        new BridgeError("dataLocation.migration_unavailable", "Storage migration could not be prepared.")), []);
    public void Dispose() => _disposed = true;
}
