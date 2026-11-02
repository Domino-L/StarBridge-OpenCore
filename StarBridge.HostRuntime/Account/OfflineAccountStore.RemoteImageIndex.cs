using System.Security.Cryptography;
using System.Text.Json;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class OfflineAccountStore
{
    private sealed record RemoteImageIndexEntry(string Revision, bool HasBody, long Sequence);
    private sealed record RemoteImageIndex(int SchemaVersion, string Epoch, long Sequence,
        Dictionary<string, RemoteImageIndexEntry> Entries);
    private string RemoteImageIndexPath => Path.Combine(RemoteImagesPath, "index.bin");
    private const int RemoteImageIndexLimit = 192 * 1024;

    private RemoteImageIndex? ReadRemoteImageIndex()
    {
        var clear = ReadProtectedBytes(RemoteImageIndexPath, RemoteImageEntropy, RemoteImageIndexLimit);
        if (clear is null) return null;
        try
        {
            var index = JsonSerializer.Deserialize<RemoteImageIndex>(clear, Json);
            if (index is null || index.SchemaVersion != 1 || !Guid.TryParseExact(index.Epoch, "N", out _) ||
                index.Sequence < 0 || index.Entries is null || index.Entries.Count > 512 ||
                index.Entries.Any(row => !IsRemoteImageResourceId(row.Key) || row.Value is null ||
                    !Guid.TryParseExact(row.Value.Revision, "N", out _) ||
                    row.Value.Sequence is <= 0 || row.Value.Sequence > index.Sequence)) throw new InvalidDataException();
            return index;
        }
        finally { CryptographicOperations.ZeroMemory(clear); }
    }
    private bool PublishRemoteImageIndex(RemoteImageIndex index, Func<bool> current) =>
        PublishProtectedBytes(RemoteImageIndexPath, JsonSerializer.SerializeToUtf8Bytes(index, Json),
            RemoteImageEntropy, RemoteImageIndexLimit, current);

    private RemoteImageIndex RequireRemoteImageIndex() =>
        ReadRemoteImageIndex() ?? throw new InvalidDataException();

    private static bool IsRemoteImageResourceId(string id)
    {
        var split = id.IndexOf('-');
        return split > 0 && RemoteImageKinds.Contains(id[..split]) && id.Length - split - 1 == 129 &&
            id[split + 65] == '-' && IsRemoteImageKey(id.Substring(split + 1, 64)) && IsRemoteImageKey(id[(split + 66)..]);
    }
    private string RemoteImageResourceId(RemoteImageReadLease lease, string key) =>
        lease.Kind + "-" + RemoteImageOwnerKey(lease) + "-" + key;

    private static string RemoteImageOwnerKey(RemoteImageReadLease lease) =>
        Convert.ToHexString(SHA256.HashData(JsonSerializer.SerializeToUtf8Bytes(lease.Owner, Json))).ToLowerInvariant();

    private static RemoteImageIndex ChangeRemoteImageEntry(RemoteImageIndex index, string id, string revision, bool body)
    {
        var sequence = checked(index.Sequence + 1);
        var entries = new Dictionary<string, RemoteImageIndexEntry>(index.Entries, StringComparer.Ordinal)
        { [id] = new(revision, body, sequence) };
        return index with { Sequence = sequence, Entries = entries };
    }
    private static RemoteImageIndex ReserveRemoteImageIndexSlot(RemoteImageIndex index, string id)
    {
        if (index.Entries.ContainsKey(id) || index.Entries.Count < 512) return index;
        var entries = new Dictionary<string, RemoteImageIndexEntry>(index.Entries, StringComparer.Ordinal);
        // At most 128 current bodies exist. Retired history is retained beyond
        // body eviction, then compacted in a batch. Rotating admission epoch
        // prevents an old MISS lease becoming valid after its tombstone leaves.
        var retired = entries.Where(row => !row.Value.HasBody).OrderBy(row => row.Value.Sequence).Take(256).ToArray();
        if (retired.Length == 0) throw new InvalidDataException();
        foreach (var row in retired) entries.Remove(row.Key);
        return index with { Epoch = NewRemoteImageEpoch(), Entries = entries };
    }
    private bool CanPublishRemoteImage(RemoteImageIndex index, RemoteImageReadLease lease, string key)
    {
        var id = RemoteImageResourceId(lease, key);
        lease.Revisions.TryGetValue(id, out var captured);
        return index.Epoch == lease.PublicationEpoch && index.Entries.GetValueOrDefault(id)?.Revision == captured;
    }
    private bool RemoteImageEntryCurrent(RemoteImageReadLease lease, string id, RemoteImageIndexEntry entry,
        Func<bool> current) => OwnsRemoteImageRead(lease, current) &&
        ReadRemoteImageIndex()?.Entries.GetValueOrDefault(id) == entry && current();

    private void TrimRemoteImages(RemoteImageReadLease lease, string incomingId, long reservedBytes,
        Func<bool> current, ref RemoteImageIndex index)
    {
        var files = RemoteImageKinds.SelectMany(kind => RemoteImageFiles(kind).Select(path => (Kind: kind, File: new FileInfo(path))))
            .OrderBy(row => row.File.LastWriteTimeUtc).ThenBy(row => row.File.FullName, StringComparer.Ordinal).ToArray();
        var total = files.Sum(row => row.File.Length) + reservedBytes;
        var count = files.Length + 1;
        foreach (var row in files)
        {
            if (count <= RemoteImageCount && total <= RemoteImageBudget) break;
            var stem = Path.GetFileNameWithoutExtension(row.File.Name);
            var id = row.Kind + "-" + stem[..129];
            if (id == incomingId) continue; // Keep the old complete body until commit.
            if (index.Entries.TryGetValue(id, out var entry) && entry.HasBody && entry.Revision == stem[130..])
            {
                index = ChangeRemoteImageEntry(index, id, NewRemoteImageEpoch(), false);
                if (!PublishRemoteImageIndex(index, () => OwnsRemoteImageRead(lease, current)))
                    throw new OperationCanceledException();
            }
            Safe(row.File.FullName);
            File.Delete(row.File.FullName);
            total -= row.File.Length;
            count--;
        }
        if (count > RemoteImageCount || total > RemoteImageBudget) throw new IOException("Remote image capacity could not be reserved.");
    }
}
