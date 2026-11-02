using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Presence;

public sealed partial class GameplayTimeRuntime
{
    private readonly object _historyScanSync = new();
    private HistoryScan? _historyScan;

    // Only aggregate progress crosses Bridge: no filenames, paths, log lines or Handle.
    private sealed class HistoryScan(BridgeAccountContext owner, long generation)
    {
        internal readonly string Id = Guid.NewGuid().ToString("N");
        internal readonly BridgeAccountContext Owner = owner;
        internal readonly long Generation = generation;
        internal readonly CancellationTokenSource Cancellation = new();
        internal readonly TaskCompletionSource<BridgeDispatchBatch> Result = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal GameplayHistoryProgress Progress = new("checking", 0, 0, 0, 0);
        internal bool Cancelled;
        internal void Cancel()
        {
            Cancelled = true;
            try { Cancellation.Cancel(); } catch (ObjectDisposedException) { }
        }
    }

    private Task<BridgeDispatchBatch> DispatchHistoryScanAsync(BridgeEnvelope request, CancellationToken cancellation)
    {
        cancellation.ThrowIfCancellationRequested();
        try
        {
            BridgeEnvelopeValidator.ValidateWireShape(request);
            BridgeEnvelopeValidator.RequireCurrentVersion(request);
            var owner = _current();
            if (!OwnerIsCurrent(owner, cancellation) || owner.Context is null ||
                request.MessageType != BridgeMessageTypes.Request || request.AccountContext != owner.Context ||
                request.SessionGeneration != owner.Generation)
                return Task.FromResult(HistoryResponse(request, "accountChanged"));
            var body = request.Payload;
            Profiles.LocalPersonalProfileStore.RejectDuplicates(body);
            var starting = request.Name == "gameplayTime.historyScanStart";
            if (body.GetRawText().Length > 512 || body.GetProperty("schemaVersion").GetInt32() != 1 ||
                body.EnumerateObject().Any(p => p.Name != "schemaVersion" && (!starting && p.Name != "scanId" || starting)))
                return Task.FromResult(Error(request, "gameplay.invalid_request"));
            var scanId = starting ? null : body.GetProperty("scanId").GetString();
            if (!starting && (scanId is null || !Guid.TryParseExact(scanId, "N", out _)))
                return Task.FromResult(Error(request, "gameplay.invalid_request"));

            lock (_historyScanSync)
            {
                if (!OwnerIsCurrent(owner, cancellation))
                    return Task.FromResult(HistoryResponse(request, "accountChanged"));
                if (starting)
                {
                    if (_historyScan is { } active && !active.Result.Task.IsCompleted)
                    {
                        if (active.Owner != owner.Context || active.Generation != owner.Generation) active.Cancel();
                        return Task.FromResult(HistoryResponse(request, "busy"));
                    }
                    var created = new HistoryScan(owner.Context, owner.Generation);
                    _historyScan = created;
                    // Actual work admission and retirement remain owned by RunHistoryAsync.
                    _ = Task.Run(() => RunHistoryScanAsync(created, request));
                }
                var scan = _historyScan;
                if (scan is null || scan.Owner != owner.Context || scan.Generation != owner.Generation ||
                    (!starting && scan.Id != scanId))
                    return Task.FromResult(HistoryResponse(request, "previewExpired"));
                if (request.Name == "gameplayTime.historyScanCancel") scan.Cancel();
                if (scan.Result.Task.IsCompletedSuccessfully)
                {
                    if (scan.Cancelled) return Task.FromResult(HistoryResponse(request, "cancelled"));
                    return Task.FromResult(new BridgeDispatchBatch(
                        BridgeEnvelope.Response(request, scan.Result.Task.Result.Response.Payload), []));
                }
                return Task.FromResult(new BridgeDispatchBatch(BridgeEnvelope.Response(request, new {
                    schemaVersion = 1, state = "scanning", scanId = scan.Id,
                    phase = scan.Cancelled ? "cancelling" : scan.Progress.Phase,
                    processedFiles = scan.Progress.ProcessedFiles, totalFiles = scan.Progress.TotalFiles,
                    readBytes = scan.Progress.ReadBytes, totalBytes = scan.Progress.TotalBytes
                }), []));
            }
        }
        catch (Exception e) when (e is System.Text.Json.JsonException or InvalidOperationException or
            KeyNotFoundException or FormatException or ArgumentException or BridgeProtocolException)
        { return Task.FromResult(Error(request, "gameplay.invalid_request")); }
    }

    private async Task RunHistoryScanAsync(HistoryScan scan, BridgeEnvelope start)
    {
        BridgeDispatchBatch result;
        try
        {
            result = await RunHistoryAsync(start with { Name = "gameplayTime.historyPreview" }, scan.Cancellation.Token,
                value => { lock (_historyScanSync) scan.Progress = value; }).ConfigureAwait(false);
        }
        catch (OperationCanceledException) { result = HistoryResponse(start, "cancelled"); }
        catch (Exception) { result = HistoryResponse(start, "unavailable"); }
        lock (_historyScanSync)
        {
            scan.Result.TrySetResult(result);
            scan.Cancellation.Dispose();
        }
    }
}
