using System.Text.Json;
using StarBridge.HostRuntime.Presence;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Support;

internal sealed class MissionRecordsRuntime(LocalMissionRecords store,
    Func<(BridgeAccountContext? Context, long Generation)> current,
    Func<string?> unavailableReason, Func<string?> verifiedHandle, Func<string?> boundLiveLog) : IAsyncDisposable
{
    private readonly object _sync = new();
    private bool _disposed;
    private Scan? _scan;
    internal Func<string, string, CancellationToken, Action<GameplayHistoryProgress>, MissionArchiveResult> Scanner { get; set; } =
        (path, handle, token, report) => GameplayHistoryScanner.ScanMissions(path, handle, token, report);
    private sealed class Scan(BridgeAccountContext owner, long generation, string handle)
    {
        internal readonly string Id = Guid.NewGuid().ToString("N");
        internal readonly BridgeAccountContext Owner = owner;
        internal readonly long Generation = generation;
        internal readonly string Handle = handle;
        internal readonly CancellationTokenSource Cancellation = new();
        internal GameplayHistoryProgress Progress = new("discovering", 0, 0, 0, 0);
        internal string Phase = "discovering";
        internal MissionRecordsImportResult? Result;
        internal Task Worker = Task.CompletedTask;
        internal bool Finished;
    }
    internal static bool Handles(string name) => name is "missionRecords.summary" or "missionRecords.importStart" or
        "missionRecords.importRead" or "missionRecords.importCancel";

    internal static string? ValidateRequest(BridgeEnvelope request)
    {
        BridgeEnvelopeValidator.ValidateWireShape(request);
        BridgeEnvelopeValidator.RequireCurrentVersion(request);
        var body = request.Payload;
        Profiles.LocalPersonalProfileStore.RejectDuplicates(body);
        var needsId = request.Name is "missionRecords.importRead" or "missionRecords.importCancel";
        if (!Handles(request.Name) || request.MessageType != BridgeMessageTypes.Request || body.GetRawText().Length > 512 ||
            body.GetProperty("schemaVersion").GetInt32() != 1 ||
            body.EnumerateObject().Any(p => p.Name != "schemaVersion" && !(needsId && p.Name == "scanId")))
            throw new ArgumentException("Invalid mission records request.");
        var id = needsId ? body.GetProperty("scanId").GetString() : null;
        if (needsId && !Guid.TryParseExact(id, "N", out _)) throw new ArgumentException("Invalid scan id.");
        return id;
    }

    internal async Task<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken token = default)
    {
        try
        {
            token.ThrowIfCancellationRequested();
            var id = ValidateRequest(request);
            var owner = current();
            bool Current() => !_disposed && !token.IsCancellationRequested && current() == owner;
            if (!Current() || request.MessageType != BridgeMessageTypes.Request ||
                request.AccountContext != owner.Context || request.SessionGeneration != owner.Generation)
                return Error(request, "accountChanged");
            if (request.Name == "missionRecords.summary")
            {
                var snapshot = owner.Context is null ? new MissionRecordsSnapshot([]) :
                    await store.ReadAsync(owner.Context, token).ConfigureAwait(false);
                var reason = unavailableReason();
                if (!Current()) return Error(request, "accountChanged");
                var payload = new Dictionary<string, object?> {
                    ["schemaVersion"] = 1, ["groups"] = LocalMissionRecords.Summarize(snapshot.Records),
                    ["total"] = snapshot.Records.Length, ["importAvailable"] = reason is null,
                    // Records from before the role split; a reimport classifies them.
                    ["unclassified"] = snapshot.Records.Count(r => r.Joined is null)
                };
                if (reason is not null) payload["importUnavailableReason"] = reason;
                return Reply(request, payload);
            }
            lock (_sync)
            {
                if (!Current()) return Error(request, "accountChanged");
                if (request.Name == "missionRecords.importStart")
                {
                    var reason = unavailableReason();
                    if (reason is not null) return Error(request, "unavailable", reason);
                    if (_scan is { Finished: false } active)
                    {
                        if (active.Owner != owner.Context || active.Generation != owner.Generation) active.Cancellation.Cancel();
                        return Error(request, "busy");
                    }
                    if (owner.Context is null || verifiedHandle() is not { Length: > 0 } handle)
                        return Error(request, "unavailable", "identityUnverified");
                    _scan?.Cancellation.Dispose();
                    var scan = new Scan(owner.Context, owner.Generation, handle);
                    _scan = scan;
                    scan.Worker = Task.Run(() => RunAsync(scan));
                    return Reply(request, new { scanId = scan.Id });
                }
                var found = _scan;
                if (found is null || found.Id != id || found.Owner != owner.Context || found.Generation != owner.Generation)
                    return Error(request, "scanNotFound");
                if (request.Name == "missionRecords.importCancel")
                {
                    if (!found.Finished) found.Cancellation.Cancel();
                    return Reply(request, new { cancelled = true });
                }
                return Reply(request, new { phase = found.Phase, filesTotal = found.Progress.TotalFiles,
                    filesDone = found.Progress.ProcessedFiles, bytesTotal = found.Progress.TotalBytes,
                    bytesDone = found.Progress.ReadBytes, result = found.Result });
            }
        }
        catch (OperationCanceledException) { return new(BridgeEnvelope.CancelledResponse(request), []); }
        catch (Exception e) when (e is JsonException or InvalidOperationException or KeyNotFoundException or
            FormatException or ArgumentException or BridgeProtocolException)
        { return Error(request, "invalidRequest"); }
        catch (Exception) { return Error(request, "storageUnavailable"); }
    }

    private async Task RunAsync(Scan scan)
    {
        var token = scan.Cancellation.Token;
        bool Current() => !_disposed && !token.IsCancellationRequested && current() == (scan.Owner, scan.Generation) &&
            string.Equals(verifiedHandle(), scan.Handle, StringComparison.OrdinalIgnoreCase) && unavailableReason() is null;
        void Guard() { if (!Current()) throw new OperationCanceledException(); }
        void Report(GameplayHistoryProgress progress)
        {
            Guard();
            lock (_sync) { scan.Progress = progress; scan.Phase = progress.Phase; }
        }
        try
        {
            Guard();
            var path = boundLiveLog();
            if (string.IsNullOrWhiteSpace(path)) throw new IOException();
            var archives = Scanner(path, scan.Handle, token, Report);
            Guard();
            var merged = await store.MergeAsync(scan.Owner, archives.Records, Current, token).ConfigureAwait(false);
            lock (_sync)
            {
                // A completed atomic commit wins a racing cancel; never report a
                // cancelled scan after reporting that it committed no records.
                scan.Result = new(archives.FilesScanned, archives.FilesSkipped, archives.Records.Length,
                    merged.Added, merged.AlreadyKnown);
                scan.Phase = "done";
            }
        }
        catch (OperationCanceledException) { lock (_sync) scan.Phase = "cancelled"; }
        catch (Exception) { lock (_sync) scan.Phase = "failed"; }
        finally { lock (_sync) scan.Finished = true; }
    }

    private static BridgeDispatchBatch Reply(BridgeEnvelope request, object value) => new(BridgeEnvelope.Response(request, value), []);
    internal static BridgeDispatchBatch Error(BridgeEnvelope request, string code, string? reason = null)
    {
        var response = BridgeEnvelope.ErrorResponse(request, new("missionRecords." + code, "Local mission records operation unavailable.", true));
        if (reason is not null) response = response with { Payload = BridgePayload.From(new { schemaVersion = 1, reason }) };
        return new(response, []);
    }

    public async ValueTask DisposeAsync()
    {
        Task pending;
        lock (_sync)
        {
            _disposed = true;
            if (_scan is { Finished: false } scan) scan.Cancellation.Cancel();
            pending = _scan?.Worker ?? Task.CompletedTask;
        }
        await pending.ConfigureAwait(false);
        lock (_sync) _scan?.Cancellation.Dispose();
        await store.DisposeAsync().ConfigureAwait(false);
    }
}
