namespace StarBridge.HostRuntime.Support;

using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using StarBridge.NativeBridge;

public sealed class LocalEventHistoryBridgeDispatcher(LocalEventJournalReader reader,
    Func<long> generation) : IBridgeRequestDispatcher
{
    public const string RequestName = "diagnostics.getLocalEvents";
    public static IReadOnlyList<string> AdvertisedCapabilities { get; } = ["diagnostics.localEvents"];
    private static readonly HashSet<string> Categories = new(StringComparer.Ordinal)
        { "all", "session", "identity", "server", "ship", "location", "life", "other" };
    private volatile bool _disposed;
    public event Action<BridgeEnvelope>? EventReady { add { } remove { } }

    public ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request,
        CancellationToken cancellationToken = default)
    {
        try
        {
            cancellationToken.ThrowIfCancellationRequested();
            BridgeEnvelopeValidator.ValidateWireShape(request);
            BridgeEnvelopeValidator.RequireCurrentVersion(request);
            if (_disposed || generation() != request.SessionGeneration) return Failure(request, "localEvents.unavailable");
            var p = request.Payload;
            if (request.MessageType != BridgeMessageTypes.Request || request.Name != RequestName ||
                request.AccountContext is not null || p.ValueKind != JsonValueKind.Object ||
                p.EnumerateObject().Count() != 5 ||
                !p.TryGetProperty("schemaVersion", out var schema) || !Integer(schema, 1, 1, out _) ||
                !p.TryGetProperty("category", out var categoryValue) || categoryValue.ValueKind != JsonValueKind.String ||
                !Categories.Contains(categoryValue.GetString()!) ||
                !p.TryGetProperty("offset", out var offsetValue) || !Integer(offsetValue, 0, 3000, out var offset) ||
                !p.TryGetProperty("pageSize", out var pageValue) || !Integer(pageValue, 1, 100, out var pageSize) ||
                offset % pageSize != 0 || !p.TryGetProperty("revision", out var rev) ||
                rev.ValueKind is not (JsonValueKind.Null or JsonValueKind.String))
                return Failure(request, BridgeErrorCodes.InvalidEnvelope);
            var expected = rev.ValueKind == JsonValueKind.Null ? null : rev.GetString();
            if (expected is not null && (expected.Length != 64 || !Regex.IsMatch(expected, "^[0-9A-F]{64}$")) ||
                offset > 0 && expected is null) return Failure(request, BridgeErrorCodes.InvalidEnvelope);
            var snapshot = reader.Read();
            cancellationToken.ThrowIfCancellationRequested();
            if (_disposed || generation() != request.SessionGeneration) return Failure(request, "localEvents.unavailable");
            var revision = snapshot.ContentRevision is null ? null : Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(
                snapshot.State + "|" + snapshot.ContentRevision + "|" + string.Join("|", snapshot.Entries.Select(e => e.Id)))));
            // Includes the retained view, so expiry as well as file changes invalidates pagination.
            if (expected is not null && expected != revision) return Failure(request, "localEvents.historyChanged");
            var filtered = snapshot.Available ? LocalEventJournalReader.Filter(snapshot, categoryValue.GetString()!) : [];
            var page = filtered.Skip(offset).Take(pageSize).Select(e => new
            {
                id = e.Id, occurredAt = e.OccurredAt.ToString("O"), category = e.Category,
                eventType = e.EventType, title = e.Title, detail = e.Detail
            }).ToArray();
            return ValueTask.FromResult(new BridgeDispatchBatch(BridgeEnvelope.Response(request,
                new Dictionary<string, object?>
                {
                    ["schemaVersion"] = 1, ["state"] = snapshot.State,
                    ["totalCount"] = snapshot.Entries.Count, ["filteredCount"] = filtered.Count,
                    ["offset"] = offset, ["pageSize"] = pageSize, ["revision"] = revision,
                    ["hasMore"] = offset + page.Length < filtered.Count, ["entries"] = page
                }, preserveRequestAccountContext: false), []));
        }
        catch (OperationCanceledException) { return ValueTask.FromResult(new BridgeDispatchBatch(BridgeEnvelope.CancelledResponse(request), [])); }
        catch { return Failure(request, "localEvents.unavailable"); }
    }

    private static bool Integer(JsonElement value, int min, int max, out int number)
    {
        number = 0;
        return value.ValueKind == JsonValueKind.Number && value.TryGetInt32(out number) && number >= min && number <= max;
    }
    private static ValueTask<BridgeDispatchBatch> Failure(BridgeEnvelope request, string code) => ValueTask.FromResult(
        new BridgeDispatchBatch(BridgeEnvelope.ErrorResponse(request,
            new BridgeError(code, "Local event history could not be read.", code != BridgeErrorCodes.InvalidEnvelope)), []));
    public void Dispose() => _disposed = true;
}
