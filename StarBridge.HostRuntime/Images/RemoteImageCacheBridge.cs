using System.Security.Cryptography;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Lifecycle;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Images;

// Supplied only by the original runtime owner. The closure must describe the
// account/mode lifetime, not the cancellation token of the opening request.
internal sealed record RemoteImageCacheOwner(BridgeAccountContext? Selected, long? OfflineRevision,
    long Generation, Func<bool> Current, Func<bool>? Verify = null);

internal sealed partial class RemoteImageCacheBridge(OfflineAccountStore store,
    Func<RemoteImageCacheOwner?> owner, TimeProvider? time = null) : IBridgeRequestDispatcher, IAsyncDisposable
{
    internal static readonly string[] Requests = ["imageCache.open", "imageCache.read", "imageCache.beginWrite",
        "imageCache.append", "imageCache.commit", "imageCache.reject", "imageCache.close"];
    internal const int ChunkBytes = 256 * 1024;
    public event Action<BridgeEnvelope>? EventReady { add { } remove { } }
    private const int HeldByteLimit = 16 * 1024 * 1024;
    private readonly TimeProvider _time = time ?? TimeProvider.System;
    private readonly AsyncWorkRetirement _work = new();
    private readonly SemaphoreSlim _gate = new(1, 1);
    private readonly Dictionary<string, Transfer> _transfers = new(StringComparer.Ordinal);
    private readonly object _retireGate = new();
    private Task? _retirement;
    private int _queued, _heldBytes;
    private sealed class Transfer(RemoteImageCacheOwner owner, RemoteImageReadLease lease, string key, long created)
    {
        internal RemoteImageCacheOwner Owner { get; } = owner;
        internal RemoteImageReadLease Lease { get; } = lease;
        internal string Key { get; } = key;
        internal long Created { get; } = created;
        internal byte[]? Download, Upload;
        internal int ReadOffset, WriteOffset;
        internal string? UploadSha256;
        internal RemoteImageDiskValue? Metadata;
    }

    public async ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken cancellationToken = default)
    {
        AsyncWorkRetirement.Lease? work;
        try { work = _work.Enter(cancellationToken); }
        catch (OperationCanceledException) { return new(BridgeEnvelope.CancelledResponse(request), []); }
        if (work is null) return Error(request, "imageCache.unavailable");
        using (work)
        {
            if (Interlocked.Increment(ref _queued) > 8)
            { Interlocked.Decrement(ref _queued); return Error(request, "imageCache.busy"); }
            var entered = false;
            try
            {
                await _gate.WaitAsync(work.Token).ConfigureAwait(false);
                entered = true;
                // DPAPI/file IO stays off the pipe dispatcher's caller thread,
                // and uses its own small resource queue, never account-current.
                return await Task.Run(() => DispatchCore(request, work.Token), work.Token).ConfigureAwait(false);
            }
            catch (OperationCanceledException) { return new(BridgeEnvelope.CancelledResponse(request), []); }
            catch (BridgeProtocolException) { return Error(request, "imageCache.invalid_request"); }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException or CryptographicException or
                JsonException or ArgumentException or InvalidOperationException or KeyNotFoundException or FormatException or OverflowException)
            { return Error(request, "imageCache.unavailable"); }
            finally { if (entered) _gate.Release(); Interlocked.Decrement(ref _queued); }
        }
    }

    private BridgeDispatchBatch DispatchCore(BridgeEnvelope request, CancellationToken token)
    {
        BridgeEnvelopeValidator.ValidateWireShape(request);
        BridgeEnvelopeValidator.RequireCurrentVersion(request);
        if (request.MessageType != BridgeMessageTypes.Request || request.AccountContext is not null ||
            !Requests.Contains(request.Name) || request.Payload.ValueKind != JsonValueKind.Object)
            return Error(request, "imageCache.invalid_request");
        var body = request.Payload;
        var fields = body.EnumerateObject().Select(property => property.Name).ToArray();
        string[] allowed = request.Name switch
        {
            "imageCache.open" => ["schemaVersion", "key", "kind"],
            "imageCache.read" => ["schemaVersion", "cacheToken", "offset"],
            "imageCache.beginWrite" => ["schemaVersion", "cacheToken", "length", "sha256", "storedAtMs", "freshUntilMs", "maxAgeSeconds", "noCache", "mustRevalidate", "etag", "validatorTarget"],
            "imageCache.append" => ["schemaVersion", "cacheToken", "offset", "chunk"],
            _ => ["schemaVersion", "cacheToken"]
        };
        if (fields.Length != allowed.Length || fields.Distinct(StringComparer.Ordinal).Count() != fields.Length ||
            fields.Except(allowed, StringComparer.Ordinal).Any() || body.GetProperty("schemaVersion").GetInt32() != 1)
            return Error(request, "imageCache.invalid_request");
        foreach (var expired in _transfers.Where(row => _time.GetElapsedTime(row.Value.Created) >= TimeSpan.FromSeconds(30) ||
                     !row.Value.Owner.Current()).Select(row => row.Key).ToArray()) Drop(expired);
        var current = owner();
        bool Current() => !token.IsCancellationRequested && !_work.IsClosed && current is not null && current.Current();
        if (!Current() || current is null || current.Generation != request.SessionGeneration ||
            current.Selected is null && current.OfflineRevision is null) return Error(request, "imageCache.unavailable");
        if (request.Name == "imageCache.open") return Open(request, current, Current);
        var id = body.GetProperty("cacheToken").GetString();
        if (id is null || !Guid.TryParseExact(id, "N", out _) || !_transfers.TryGetValue(id, out var transfer))
            return Error(request, "imageCache.unavailable");
        // Releasing a receipt never requires reading an unusable cache file.
        if (request.Name == "imageCache.close") { Drop(id); return Ok(request, new { schemaVersion = 1, status = "closed" }); }
        bool Owns() => Current() && transfer.Owner.Current() && transfer.Owner.Generation == current.Generation &&
            transfer.Owner.Selected == current.Selected && transfer.Owner.OfflineRevision == current.OfflineRevision &&
            store.IsRemoteImageReadCurrent(transfer.Lease, Current);
        if (!Owns()) { Drop(id); return Error(request, "imageCache.unavailable"); }
        BridgeDispatchBatch result;
        switch (request.Name)
        {
            case "imageCache.read": result = ReadChunk(request, id, transfer); break;
            case "imageCache.beginWrite": result = BeginWrite(request, transfer); break;
            case "imageCache.append": result = Append(request, transfer); break;
            case "imageCache.commit": result = Commit(request, id, transfer, Owns); break;
            case "imageCache.reject":
                if (transfer.Lease.OfflineRevision is not null) return Error(request, "imageCache.unavailable");
                try
                {
                    var removed = store.RemoveRemoteImage(transfer.Lease, transfer.Key, Owns);
                    result = Ok(request, new { schemaVersion = 1, status = removed ? "removed" : "superseded" });
                }
                finally { Drop(id); }
                break;
            default: Drop(id); result = Ok(request, new { schemaVersion = 1, status = "closed" }); break;
        }
        if (!Owns() || current.Verify?.Invoke() == false || !Owns()) { Drop(id); return Error(request, "imageCache.unavailable"); }
        return result;
    }

    private BridgeDispatchBatch Open(BridgeEnvelope request, RemoteImageCacheOwner current, Func<bool> valid)
    {
        var body = request.Payload;
        var key = body.GetProperty("key").GetString();
        var kind = body.GetProperty("kind").GetString();
        if (!Hash(key) || kind is not ("avatar" or "ship" or "organization" or "other")) return Error(request, "imageCache.invalid_request");
        if (_transfers.Count >= 64) return Error(request, "imageCache.busy");
        var lease = store.CaptureRemoteImageRead(current.Selected, current.OfflineRevision, kind, valid);
        if (lease is null) return Error(request, "imageCache.unavailable");
        var value = store.ReadRemoteImage(lease, key!, valid);
        if (!valid()) return Error(request, "imageCache.unavailable");
        if (_heldBytes + (value?.Body.Length ?? 0) > HeldByteLimit) return Error(request, "imageCache.busy");
        var id = Guid.NewGuid().ToString("N");
        _transfers.Add(id, new(current, lease, key!, _time.GetTimestamp())
        { Download = value?.Body, Metadata = value is null ? null : value with { Body = [] } });
        _heldBytes += value?.Body.Length ?? 0;
        var result = Ok(request, new
        {
            schemaVersion = 1, status = value is null ? "miss" : "ready", cacheToken = id,
            length = value?.Body.Length ?? 0,
            sha256 = value is null ? null : Convert.ToHexString(SHA256.HashData(value.Body)).ToLowerInvariant(),
            storedAtMs = value?.StoredAtUtc.ToUnixTimeMilliseconds(), freshUntilMs = value?.FreshUntilUtc.ToUnixTimeMilliseconds(),
            maxAgeSeconds = value?.MaxAgeSeconds, noCache = value?.NoCache, mustRevalidate = value?.MustRevalidate,
            etag = value?.ETag, validatorTarget = value?.ValidatorTarget
        });
        if (!valid() || current.Verify?.Invoke() == false || !store.IsRemoteImageReadCurrent(lease, valid))
        { Drop(id); return Error(request, "imageCache.unavailable"); }
        return result;
    }
    private BridgeDispatchBatch ReadChunk(BridgeEnvelope request, string id, Transfer transfer)
    {
        var offset = request.Payload.GetProperty("offset").GetInt32();
        if (transfer.Download is not { } body || offset != transfer.ReadOffset || offset < 0 || offset >= body.Length)
            return Error(request, "imageCache.invalid_request");
        var length = Math.Min(ChunkBytes, body.Length - offset);
        var chunk = Convert.ToBase64String(body, offset, length);
        transfer.ReadOffset += length;
        var done = transfer.ReadOffset == body.Length;
        if (done) ReleaseDownload(transfer);
        return Ok(request, new { schemaVersion = 1, cacheToken = id, offset, chunk, nextOffset = offset + length, done });
    }
    private BridgeDispatchBatch Commit(BridgeEnvelope request, string id, Transfer transfer, Func<bool> current)
    {
        if (transfer.Upload is not { } bytes || transfer.Metadata is null || transfer.WriteOffset != bytes.Length ||
            Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant() != transfer.UploadSha256)
        { Drop(id); return Error(request, "imageCache.invalid_request"); }
        try
        {
            var stored = store.PublishRemoteImage(transfer.Lease, transfer.Metadata with { Body = bytes }, current);
            return Ok(request, new { schemaVersion = 1, status = stored ? "stored" : "superseded" });
        }
        finally { Drop(id); }
    }
    private void ReleaseDownload(Transfer transfer)
    {
        if (transfer.Download is not { } bytes) return;
        transfer.Download = null; _heldBytes -= bytes.Length;
        CryptographicOperations.ZeroMemory(bytes);
    }
    private void Drop(string id)
    {
        if (!_transfers.Remove(id, out var transfer)) return;
        ReleaseDownload(transfer);
        if (transfer.Upload is { } bytes) { _heldBytes -= bytes.Length; CryptographicOperations.ZeroMemory(bytes); transfer.Upload = null; }
    }
    private static bool Hash(string? value) => value is { Length: 64 } && value.All(c => c is >= '0' and <= '9' or >= 'a' and <= 'f');
    private static BridgeDispatchBatch Ok(BridgeEnvelope request, object value) => new(BridgeEnvelope.Response(request, value), []);
    private static BridgeDispatchBatch Error(BridgeEnvelope request, string code) =>
        new(BridgeEnvelope.ErrorResponse(request with { AccountContext = null }, new(code, "Image cache is unavailable.", true)), []);
    public Task RetireAsync()
    {
        lock (_retireGate) return _retirement ??= RetireCore();
    }
    private async Task RetireCore()
    {
        await _work.Close().ConfigureAwait(false);
        foreach (var id in _transfers.Keys.ToArray()) Drop(id);
        _gate.Dispose();
    }
    public ValueTask DisposeAsync() => new(RetireAsync());
    public void Dispose() => _ = RetireAsync();
}
