using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

// Resource bytes only. The caller must already own the original page's URL;
// neither this lease nor a cache hit is an account or media authorization.
internal sealed record RemoteImageReadLease(BridgeAccountContext Owner, long? OfflineRevision,
    Auth.ScmCredentialRetirementStamp? Credential, string Kind, string Epoch,
    string PublicationEpoch, IReadOnlyDictionary<string, string> Revisions);
internal sealed record RemoteImageDiskValue(string Key, byte[] Body, DateTimeOffset StoredAtUtc,
    DateTimeOffset FreshUntilUtc, int MaxAgeSeconds, bool NoCache, bool MustRevalidate,
    string? ETag, string? ValidatorTarget);

internal sealed partial class OfflineAccountStore
{
    private const int RemoteImageLimit = 6 * 1024 * 1024;
    private const long RemoteImageBudget = 64L * 1024 * 1024;
    private const int RemoteImageCount = 128;
    private static readonly string[] RemoteImageKinds = ["avatar", "ship", "organization", "other"];
    private static readonly byte[] RemoteImageEntropy = Encoding.UTF8.GetBytes("StarBridge.remote-images.v1");
    private string RemoteImagesPath => Path.Combine(Path.GetDirectoryName(_path)!, "remote-images-v1");
    private sealed record RemoteImageDocument(int SchemaVersion, BridgeAccountContext Owner, string Kind, string Epoch,
        string Revision, RemoteImageDiskValue Value);
    private sealed record RemoteImageEpochs(int SchemaVersion, string Avatar, string Ship, string Organization, string Other)
    {
        internal string For(string kind) => kind switch
        { "avatar" => Avatar, "ship" => Ship, "organization" => Organization, "other" => Other, _ => throw new InvalidDataException() };
    }

    internal RemoteImageReadLease? CaptureRemoteImageRead(BridgeAccountContext? selected, long? offlineRevision,
        string kind, Func<bool> current)
    {
        if (!RemoteImageKinds.Contains(kind) || !current()) return null;
        var account = Read();
        if (account is null || (offlineRevision is { } revision
            ? account.OfflineRevision != revision || selected is not null
            : selected is null || account.Owner != selected || account.OfflineRevision is not null)) return null;
        using var writer = RemoteImageWriter();
        var epochs = ReadRemoteImageEpochs();
        if (epochs is null)
        {
            epochs = new(1, NewRemoteImageEpoch(), NewRemoteImageEpoch(), NewRemoteImageEpoch(), NewRemoteImageEpoch());
            if (!PublishProtectedBytes(RemoteImageEpochPath, JsonSerializer.SerializeToUtf8Bytes(epochs, Json),
                    RemoteImageEntropy, 4096, current)) return null;
        }
        var index = ReadRemoteImageIndex();
        if (index is null)
        {
            index = new(1, NewRemoteImageEpoch(), 0, new(StringComparer.Ordinal));
            if (!PublishRemoteImageIndex(index, current)) return null;
        }
        var lease = new RemoteImageReadLease(account.Owner, account.OfflineRevision, account.OfflineCredential, kind,
            epochs.For(kind), index.Epoch, index.Entries.ToDictionary(row => row.Key, row => row.Value.Revision, StringComparer.Ordinal));
        return OwnsRemoteImageRead(lease, current) ? lease : null;
    }

    internal RemoteImageDiskValue? ReadRemoteImage(RemoteImageReadLease lease, string key, Func<bool> current)
    {
        RequireRemoteImageKey(key);
        if (!OwnsRemoteImageRead(lease, current)) return null;
        var id = RemoteImageResourceId(lease, key);
        var entry = RequireRemoteImageIndex().Entries.GetValueOrDefault(id);
        if (entry is not { HasBody: true }) return null;
        var path = RemoteImagePath(lease, key, entry.Revision);
        var clear = ReadProtectedBytes(path, RemoteImageEntropy, RemoteImageLimit);
        if (clear is null) return null;
        RemoteImageDocument? document;
        try { document = JsonSerializer.Deserialize<RemoteImageDocument>(clear, Json); }
        finally { CryptographicOperations.ZeroMemory(clear); }
        if (document is null || document.SchemaVersion != 1 || document.Owner != lease.Owner ||
            document.Kind != lease.Kind || document.Epoch != lease.Epoch || document.Revision != entry.Revision ||
            document.Value is null || document.Value.Key != key) return null;
        ValidateRemoteImageValue(document.Value);
        if (!RemoteImageEntryCurrent(lease, id, entry, current)) return null;
        // Recency is optional bookkeeping. A read remains usable if another
        // resource writer temporarily owns the lease; it never waits for auth.
        try
        {
            using var writer = RemoteImageWriter();
            Safe(path);
            if (RemoteImageEntryCurrent(lease, id, entry, current) && File.Exists(path)) File.SetLastWriteTimeUtc(path, DateTime.UtcNow);
        }
        catch (IOException) { }
        return RemoteImageEntryCurrent(lease, id, entry, current) ? document.Value : null;
    }

    internal bool PublishRemoteImage(RemoteImageReadLease lease, RemoteImageDiskValue value, Func<bool> current)
    {
        ValidateRemoteImageValue(value);
        // An offline selection can display retained resources, never publish a
        // network observation. A lease captured before cleanup cannot refill it.
        if (lease.OfflineRevision is not null || !OwnsRemoteImageRead(lease, current)) return false;
        using var writer = RemoteImageWriter();
        if (!OwnsRemoteImageRead(lease, current)) return false;
        var index = RequireRemoteImageIndex();
        if (!CanPublishRemoteImage(index, lease, value.Key)) return false;
        var id = RemoteImageResourceId(lease, value.Key);
        var previous = index.Entries.GetValueOrDefault(id);
        index = ReserveRemoteImageIndexSlot(index, id);
        var revision = NewRemoteImageEpoch();
        var path = RemoteImagePath(lease, value.Key, revision);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        Safe(path);
        var bytes = JsonSerializer.SerializeToUtf8Bytes(new RemoteImageDocument(1, lease.Owner, lease.Kind, lease.Epoch, revision, value), Json);
        var committed = false;
        try
        {
            if (bytes.Length > RemoteImageLimit - 1024) throw new InvalidDataException();
            // Reserve the conservative protected size before publication. A
            // failed eviction cannot leave a newly published over-budget file.
            TrimRemoteImages(lease, id, bytes.Length + 1024L, current, ref index);
            if (!PublishProtectedBytes(path, bytes, RemoteImageEntropy, RemoteImageLimit,
                    () => OwnsRemoteImageRead(lease, current))) return false;
            index = ChangeRemoteImageEntry(index, id, revision, true);
            if (!PublishRemoteImageIndex(index, () => OwnsRemoteImageRead(lease, current))) return false;
            committed = true;
            if (previous is { HasBody: true })
            {
                var oldPath = RemoteImagePath(lease, value.Key, previous.Revision);
                try { Safe(oldPath); if (File.Exists(oldPath)) File.Delete(oldPath); }
                catch (IOException) { } // An unreferenced complete blob is a later quota victim.
            }
        }
        finally
        {
            CryptographicOperations.ZeroMemory(bytes);
            if (!committed) { Safe(path); if (File.Exists(path)) File.Delete(path); }
        }
        return OwnsRemoteImageRead(lease, current);
    }

    internal bool RemoveRemoteImage(RemoteImageReadLease lease, string key, Func<bool> current)
    {
        RequireRemoteImageKey(key);
        using var writer = RemoteImageWriter();
        if (!OwnsRemoteImageRead(lease, current)) return false;
        var id = RemoteImageResourceId(lease, key);
        var index = RequireRemoteImageIndex();
        var previous = index.Entries.GetValueOrDefault(id);
        index = ReserveRemoteImageIndexSlot(index, id);
        index = ChangeRemoteImageEntry(index, id, NewRemoteImageEpoch(), false);
        if (!PublishRemoteImageIndex(index, () => OwnsRemoteImageRead(lease, current))) return false;
        if (previous is { HasBody: true })
        {
            var path = RemoteImagePath(lease, key, previous.Revision);
            Safe(path);
            if (File.Exists(path)) File.Delete(path);
        }
        return current();
    }

    // Matches the existing maintenance consent: regenerable ship/organization
    // images only. Avatar/other entries and all original/imported assets survive.
    internal int ClearDownloadableRemoteImages()
    {
        Safe(RemoteImagesPath);
        if (File.Exists(RemoteImagesPath)) throw new IOException("Remote image cache is not a directory.");
        if (!Directory.Exists(RemoteImagesPath)) { Safe(RemoteImagesPath); return 0; }
        using var writer = RemoteImageWriter();
        var old = ReadRemoteImageEpochs() ?? new(1, NewRemoteImageEpoch(), NewRemoteImageEpoch(), NewRemoteImageEpoch(), NewRemoteImageEpoch());
        var next = old with { Ship = NewRemoteImageEpoch(), Organization = NewRemoteImageEpoch() };
        if (!PublishProtectedBytes(RemoteImageEpochPath, JsonSerializer.SerializeToUtf8Bytes(next, Json),
                RemoteImageEntropy, 4096, () => true)) throw new IOException("Remote image fence was not published.");
        var index = ReadRemoteImageIndex();
        if (index is not null)
        {
            foreach (var row in index.Entries.Where(row => row.Value.HasBody &&
                         (row.Key.StartsWith("ship-", StringComparison.Ordinal) || row.Key.StartsWith("organization-", StringComparison.Ordinal))).ToArray())
                index = ChangeRemoteImageEntry(index, row.Key, NewRemoteImageEpoch(), false);
            if (!PublishRemoteImageIndex(index, () => true)) throw new IOException("Remote image index was not retired.");
        }
        var removed = 0;
        foreach (var kind in new[] { "ship", "organization" })
            foreach (var path in RemoteImageFiles(kind)) { Safe(path); File.Delete(path); removed++; }
        return removed;
    }

    private bool OwnsRemoteImageRead(RemoteImageReadLease lease, Func<bool> current)
    {
        if (!current() || !RemoteImageKinds.Contains(lease.Kind)) return false;
        var account = Read();
        return account is not null && account.Owner == lease.Owner && account.OfflineRevision == lease.OfflineRevision &&
            account.OfflineCredential == lease.Credential && ReadRemoteImageEpochs()?.For(lease.Kind) == lease.Epoch && current();
    }
    internal bool IsRemoteImageReadCurrent(RemoteImageReadLease lease, Func<bool> current) => OwnsRemoteImageRead(lease, current);
    private string RemoteImageEpochPath => Path.Combine(RemoteImagesPath, "epochs.bin");
    private RemoteImageEpochs? ReadRemoteImageEpochs()
    {
        var clear = ReadProtectedBytes(RemoteImageEpochPath, RemoteImageEntropy, 4096);
        if (clear is null) return null;
        try
        {
            var value = JsonSerializer.Deserialize<RemoteImageEpochs>(clear, Json);
            if (value is null || value.SchemaVersion != 1 || RemoteImageKinds.Any(kind =>
                    !Guid.TryParseExact(value.For(kind), "N", out _))) throw new InvalidDataException();
            return value;
        }
        finally { CryptographicOperations.ZeroMemory(clear); }
    }
    private static string NewRemoteImageEpoch() => Guid.NewGuid().ToString("N");
    private FileStream RemoteImageWriter()
    {
        var path = Path.Combine(RemoteImagesPath, "writer.lock");
        Safe(path);
        Directory.CreateDirectory(RemoteImagesPath);
        Safe(path);
        return new(path, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
    }
    private string RemoteImagePath(RemoteImageReadLease lease, string key, string revision)
    {
        RequireRemoteImageKey(key);
        if (!RemoteImageKinds.Contains(lease.Kind)) throw new InvalidDataException();
        if (!Guid.TryParseExact(revision, "N", out _)) throw new InvalidDataException();
        return Path.Combine(RemoteImagesPath, lease.Kind, RemoteImageOwnerKey(lease) + "-" + key + "-" + revision + ".bin");
    }
    private List<string> RemoteImageFiles(string kind)
    {
        var directory = Path.Combine(RemoteImagesPath, kind);
        Safe(directory);
        if (File.Exists(directory)) throw new IOException("Remote image kind cache is not a directory.");
        if (!Directory.Exists(directory)) return [];
        var files = new List<string>();
        foreach (var path in Directory.EnumerateFiles(directory, "*.bin", SearchOption.TopDirectoryOnly))
        {
            var name = Path.GetFileNameWithoutExtension(path);
            if (name.Length != 162 || name[64] != '-' || name[129] != '-' ||
                !IsRemoteImageKey(name[..64]) || !IsRemoteImageKey(name.Substring(65, 64)) || !Guid.TryParseExact(name[130..], "N", out _)) continue;
            Safe(path);
            files.Add(path);
            if (files.Count > 4096) throw new IOException("Remote image cache namespace exceeds its inspection bound.");
        }
        return files;
    }
    private static bool IsRemoteImageKey(string key) => key.Length == 64 &&
        key.All(value => value is >= '0' and <= '9' or >= 'a' and <= 'f');
    private static void RequireRemoteImageKey(string key)
    { if (!IsRemoteImageKey(key)) throw new InvalidDataException(); }
    // Original HTTP max-age (lossless up to one year); local freshness is capped by FreshUntilUtc.
    internal const int RemoteImageMaxStoredAgeSeconds = 31_536_000;
    private static void ValidateRemoteImageValue(RemoteImageDiskValue value)
    {
        RequireRemoteImageKey(value.Key);
        if (value.Body is not { Length: > 0 and <= 4 * 1024 * 1024 } ||
            value.StoredAtUtc <= DateTimeOffset.UnixEpoch || value.StoredAtUtc > DateTimeOffset.UtcNow.AddMinutes(5) ||
            value.FreshUntilUtc < value.StoredAtUtc || value.FreshUntilUtc > value.StoredAtUtc.AddMinutes(5) ||
            value.MaxAgeSeconds is < 0 or > RemoteImageMaxStoredAgeSeconds ||
            value.ETag is { } etag && (etag.Length is 0 or > 1024 ||
                !System.Text.RegularExpressions.Regex.IsMatch(etag, "^(?:W/)?\"[\\x21\\x23-\\x7E\\x80-\\xFF]*\"$")) ||
            value.ValidatorTarget is { } target && !IsRemoteImageKey(target)) throw new InvalidDataException();
    }
}
