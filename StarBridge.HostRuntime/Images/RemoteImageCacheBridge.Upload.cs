using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Images;

internal sealed partial class RemoteImageCacheBridge
{
    private BridgeDispatchBatch BeginWrite(BridgeEnvelope request, Transfer transfer)
    {
        var body = request.Payload;
        var length = body.GetProperty("length").GetInt32();
        var digest = body.GetProperty("sha256").GetString();
        if (transfer.Lease.OfflineRevision is not null || transfer.Upload is not null ||
            length is <= 0 or > 4 * 1024 * 1024 || !Hash(digest)) return Error(request, "imageCache.invalid_request");
        var metadata = new RemoteImageDiskValue(transfer.Key, [],
            DateTimeOffset.FromUnixTimeMilliseconds(body.GetProperty("storedAtMs").GetInt64()),
            DateTimeOffset.FromUnixTimeMilliseconds(body.GetProperty("freshUntilMs").GetInt64()),
            body.GetProperty("maxAgeSeconds").GetInt32(), body.GetProperty("noCache").GetBoolean(),
            body.GetProperty("mustRevalidate").GetBoolean(), body.GetProperty("etag").GetString(),
            body.GetProperty("validatorTarget").GetString());
        // Reject here what the store would later refuse, so commit never throws.
        if (metadata.FreshUntilUtc < metadata.StoredAtUtc || metadata.FreshUntilUtc > metadata.StoredAtUtc.AddMinutes(5) ||
            metadata.MaxAgeSeconds is < 0 or > Account.OfflineAccountStore.RemoteImageMaxStoredAgeSeconds || metadata.ETag?.Length > 1024 ||
            metadata.ValidatorTarget is not null && !Hash(metadata.ValidatorTarget)) return Error(request, "imageCache.invalid_request");
        ReleaseDownload(transfer);
        if (_heldBytes + length > HeldByteLimit) return Error(request, "imageCache.busy");
        transfer.Metadata = metadata;
        transfer.Upload = new byte[length];
        transfer.UploadSha256 = digest;
        transfer.WriteOffset = 0;
        _heldBytes += length;
        return Ok(request, new { schemaVersion = 1, status = "writing", nextOffset = 0 });
    }
    private BridgeDispatchBatch Append(BridgeEnvelope request, Transfer transfer)
    {
        var body = request.Payload;
        var offset = body.GetProperty("offset").GetInt32();
        var encoded = body.GetProperty("chunk").GetString();
        if (transfer.Upload is not { } upload || offset != transfer.WriteOffset ||
            encoded is not { Length: > 0 and <= 349528 }) return Error(request, "imageCache.invalid_request");
        var bytes = Convert.FromBase64String(encoded);
        try
        {
            if (bytes.Length is <= 0 or > ChunkBytes || bytes.Length > upload.Length - offset)
                return Error(request, "imageCache.invalid_request");
            bytes.CopyTo(upload, offset);
            transfer.WriteOffset += bytes.Length;
        }
        finally { System.Security.Cryptography.CryptographicOperations.ZeroMemory(bytes); }
        return Ok(request, new { schemaVersion = 1, status = "writing", nextOffset = transfer.WriteOffset });
    }
}
