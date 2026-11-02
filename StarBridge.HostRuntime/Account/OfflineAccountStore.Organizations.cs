using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed record OfflineOrganizationObservation(string Code, string Name, string? LogoImageData, bool LogoDeferred);
internal sealed record OfflineOrganizationRow(string Id, string Name, string? LogoImageData, DateTimeOffset? LogoCachedAtUtc);
internal sealed record OfflineOrganizationDirectory(string Version, DateTimeOffset CachedAtUtc, bool Complete,
    IReadOnlyList<OfflineOrganizationRow> Items);

internal sealed partial class OfflineAccountStore
{
    private string OrganizationsPath => Path.Combine(Path.GetDirectoryName(_path)!, "organizations.bin");
    private static readonly byte[] OrganizationsEntropy = Encoding.UTF8.GetBytes("StarBridge.offline-account.organizations.v1");
    private const int OrganizationLimit = 4 * 1024 * 1024;
    private const int OrganizationLogoChars = 3 * 1024 * 1024;
    private const int OrganizationRows = 256;
    private sealed record OrganizationsDocument(int SchemaVersion, BridgeAccountContext Owner, string Version,
        DateTimeOffset CachedAtUtc, bool Complete, OfflineOrganizationRow[] Items, string? MetadataVersion = null);
    private sealed record OrganizationCursor(BridgeAccountContext Owner, long Generation, string? Next, string Version, bool Truncated, string? MetadataVersion = null);
    private readonly object _organizationsGate = new();
    private OrganizationCursor? _organizationCursor;
    private (long Length, DateTime LastWrite)? _organizationsStamp;
    private OrganizationsDocument? _organizationsMemory;

    internal static string OrganizationDisplayId(BridgeAccountContext owner, string code) =>
        Convert.ToHexString(SHA256.HashData(JsonSerializer.SerializeToUtf8Bytes(new[] {
            owner.Environment, owner.Authority, owner.Subject, code.ToUpperInvariant() }))).ToLowerInvariant();

    internal void ObserveOrganizations(BridgeAccountContext owner, long generation, string? after, string? next,
        IReadOnlyList<OfflineOrganizationObservation> observed, Func<bool> current, OfflineOrganizationReadLease? lease = null)
    {
        if (!current()) return;
        using var writer = OrganizationWriter();
        if (!OnlineOrganizationOwner(owner, current)) return;
        if (lease is not null && !OwnsOrganizationRead(lease)) return;
        var imagesCurrent = lease is null || lease.ImageEpoch == ReadOrganizationPolicy()?.ImageEpoch;
        OrganizationsDocument? old;
        try { old = ReadOrganizations(); }
        catch (Exception error) when (error is IOException or JsonException or CryptographicException or InvalidOperationException or ArgumentException)
        { old = null; } // A fresh, authorized first page can replace an unusable display file.
        if (old is not null && (lease is not null ? old.Version != ReadOrganizationPolicy()?.CandidateVersion :
            !OrganizationPolicyAllows(ReadOrganizationPolicy(), old))) old = null;
        OrganizationCursor? cursor;
        lock (_organizationsGate) cursor = _organizationCursor;
        if (after is not null && (old is null || old.Owner != owner || cursor is null || cursor.Owner != owner || cursor.Generation != generation ||
            cursor.Next != after || cursor.Version != old.Version && cursor.MetadataVersion != (old.MetadataVersion ?? old.Version))) return;
        var rows = after is null ? new List<OfflineOrganizationRow>() : old!.Items.ToList();
        var remaining = OrganizationRows - rows.Count;
        var truncated = observed.Count > remaining || after is not null && cursor!.Truncated;
        var ids = rows.Select(row => row.Id).ToHashSet(StringComparer.Ordinal);
        var now = DateTimeOffset.UtcNow;
        foreach (var item in observed.Take(remaining))
        {
            if (!DisplayText(item.Code, 256) || !DisplayText(item.Name, 512)) throw new InvalidDataException();
            var id = OrganizationDisplayId(owner, item.Code);
            if (!ids.Add(id)) throw new InvalidDataException();
            var image = imagesCurrent ? PartyRooms.RoomAvatarProjection.Normalize(item.LogoImageData, 512 * 1024) : null;
            var previous = imagesCurrent && old?.Owner == owner ? old.Items.FirstOrDefault(row => row.Id == id) : null;
            rows.Add(new(id, item.Name, image ?? (item.LogoDeferred ? previous?.LogoImageData : null),
                image is not null ? now : item.LogoDeferred ? previous?.LogoCachedAtUtc : null));
        }
        var complete = next is null && !truncated;
        TrimOrganizationImages(rows);
        var document = new OrganizationsDocument(1, owner, Guid.NewGuid().ToString("N"), now, complete, rows.ToArray());
        if (!PublishOrganizations(document, () => OnlineOrganizationOwner(owner, current), lease)) return;
        lock (_organizationsGate) _organizationCursor = new(owner, generation, next, document.Version, truncated, document.MetadataVersion ?? document.Version);
    }

    internal void ObserveOrganizationLogo(BridgeAccountContext owner, string code, string? image, Func<bool> current,
        OfflineOrganizationImageRead? imageRead = null)
    {
        if (!current()) return;
        using var writer = OrganizationWriter();
        if (!OnlineOrganizationOwner(owner, current)) return;
        if (imageRead is not null && (imageRead.Owner != owner || imageRead.Epoch != ReadOrganizationPolicy()?.ImageEpoch)) return;
        var old = ReadOrganizations();
        if (old?.Owner != owner || !OrganizationPolicyAllows(ReadOrganizationPolicy(), old)) return;
        var id = OrganizationDisplayId(owner, code);
        var index = Array.FindIndex(old.Items, row => row.Id == id);
        if (index < 0) return;
        var normalized = PartyRooms.RoomAvatarProjection.Normalize(image, 512 * 1024);
        if (image is not null && normalized is null) return;
        if (old.Items[index].LogoImageData == normalized) return;
        var rows = old.Items.ToList();
        rows[index] = rows[index] with { LogoImageData = normalized, LogoCachedAtUtc = normalized is null ? null : DateTimeOffset.UtcNow };
        TrimOrganizationImages(rows);
        var next = old with { Version = Guid.NewGuid().ToString("N"), Items = rows.ToArray(), MetadataVersion = old.MetadataVersion ?? old.Version };
        if (PublishOrganizations(next, () => OnlineOrganizationOwner(owner, current)))
            lock (_organizationsGate)
                if (_organizationCursor is { } cursor && cursor.Owner == owner && cursor.Version == old.Version)
                    _organizationCursor = cursor with { Version = next.Version };
    }

    internal OfflineOrganizationDirectory? ReadOfflineOrganizations(long revision, Func<bool> current) =>
        ReadScopedOrganizations(null, revision, current);
    internal OfflineOrganizationDirectory? ReadSelectedOrganizations(BridgeAccountContext owner, Func<bool> current) =>
        ReadScopedOrganizations(owner, null, current);

    private OfflineOrganizationDirectory? ReadScopedOrganizations(BridgeAccountContext? selected, long? revision, Func<bool> current)
    {
        if (!current()) return null;
        var account = Read();
        if (account is null || (revision is { } expected ? account.OfflineRevision != expected :
            account.Owner != selected || account.OfflineRevision is not null)) return null;
        var policy = ReadOrganizationPolicy();
        var data = ReadOrganizations();
        var after = current() ? Read() : null;
        if (data is null || after is null || data.Owner != account.Owner || after.Owner != account.Owner || after.OfflineRevision != account.OfflineRevision ||
            after.OfflineCredential != account.OfflineCredential || !OrganizationPolicyAllows(policy, data) ||
            ReadOrganizationPolicy() != policy || !current()) return null;
        return new(data.Version, data.CachedAtUtc, data.Complete, Array.AsReadOnly(data.Items));
    }

    internal void ClearOrganizations(BridgeAccountContext owner, Func<bool> current)
    {
        if (!current()) return;
        using var writer = OrganizationWriter();
        if (Read()?.Owner != owner || ReadOrganizations()?.Owner != owner || !current()) return;
        var blocked = new OrganizationReadPolicy(1, owner, Guid.NewGuid().ToString("N"), null, null, [], ImageEpoch: Guid.NewGuid().ToString("N"));
        if (!PublishOrganizationPolicy(blocked, current)) return;
        Safe(OrganizationsPath);
        if (File.Exists(OrganizationsPath)) File.Delete(OrganizationsPath);
        lock (_organizationsGate) { _organizationsMemory = null; _organizationsStamp = null; _organizationCursor = null; }
    }

    private bool OnlineOrganizationOwner(BridgeAccountContext owner, Func<bool> current) =>
        current() && Read() is { OfflineRevision: null } account && account.Owner == owner && current();

    private FileStream OrganizationWriter()
    {
        Safe(_path); Safe(_path + ".lock"); Safe(OrganizationsPath);
        Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
        // All display files share the existing account writer lease. The
        // companion cannot select an owner or race a completed offline pin.
        return new(_path + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
    }

    private bool PublishOrganizations(OrganizationsDocument document, Func<bool> current, OfflineOrganizationReadLease? lease = null)
    {
        var before = ReadOrganizationPolicy();
        if (lease is null && before is { Pending.Length: > 0 }) return false;
        var published = PublishProtectedBytes(OrganizationsPath, JsonSerializer.SerializeToUtf8Bytes(document, Json),
            OrganizationsEntropy, OrganizationLimit, current);
        lock (_organizationsGate) { _organizationsMemory = null; _organizationsStamp = null; }
        if (!published) return false;
        if (lease is not null)
        {
            var policy = ReadOrganizationPolicy()!;
            return PublishOrganizationPolicy(policy with { CandidateVersion = document.Version }, current);
        }
        return PublishOrganizationPolicy(new(1, document.Owner, Guid.NewGuid().ToString("N"), document.Version, document.Version, [], ImageEpoch: before?.ImageEpoch), current);
    }

    private OrganizationsDocument? ReadOrganizations()
    {
        Safe(OrganizationsPath);
        var before = OrganizationStamp();
        if (before is null)
        {
            lock (_organizationsGate) { _organizationsMemory = null; _organizationsStamp = null; }
            return null;
        }
        lock (_organizationsGate) if (_organizationsStamp == before && _organizationsMemory is { } cached) return cached;
        var clear = ReadProtectedBytes(OrganizationsPath, OrganizationsEntropy, OrganizationLimit);
        if (clear is null) return null;
        OrganizationsDocument data;
        try
        {
            using var json = JsonDocument.Parse(clear, new JsonDocumentOptions { MaxDepth = 16 });
            UniqueOrganizationProperties(json.RootElement);
            data = json.RootElement.Deserialize<OrganizationsDocument>(Json) ?? throw new InvalidDataException();
            if (data.SchemaVersion != 1 || data.Owner is null || !DisplayText(data.Owner.Environment, 256) ||
                !DisplayText(data.Owner.Authority, 2048) || !DisplayText(data.Owner.Subject, 4096) ||
                !Guid.TryParseExact(data.Version, "N", out _) || !OrganizationTime(data.CachedAtUtc) ||
                data.MetadataVersion is { } metadataVersion && !Guid.TryParseExact(metadataVersion, "N", out _) ||
                data.Items is null || data.Items.Length > OrganizationRows) throw new InvalidDataException();
            var ids = new HashSet<string>(StringComparer.Ordinal);
            var chars = 0;
            foreach (var row in data.Items)
            {
                if (row is null || row.Id is not { Length: 64 } || row.Id.Any(ch => ch is not (>= '0' and <= '9' or >= 'a' and <= 'f')) ||
                    !ids.Add(row.Id) || !DisplayText(row.Name, 512)) throw new InvalidDataException();
                if (row.LogoImageData is { } image)
                {
                    if (row.LogoCachedAtUtc is not { } at || !OrganizationTime(at) ||
                        PartyRooms.RoomAvatarProjection.Normalize(image, 512 * 1024) != image) throw new InvalidDataException();
                    chars += image.Length;
                }
                else if (row.LogoCachedAtUtc is not null) throw new InvalidDataException();
            }
            if (chars > OrganizationLogoChars) throw new InvalidDataException();
        }
        finally { CryptographicOperations.ZeroMemory(clear); }
        if (OrganizationStamp() != before) throw new IOException("Organization display changed while reading.");
        lock (_organizationsGate) { _organizationsStamp = before; _organizationsMemory = data; }
        return data;
    }

    private (long Length, DateTime LastWrite)? OrganizationStamp()
    {
        var file = new FileInfo(OrganizationsPath);
        return file.Exists ? (file.Length, file.LastWriteTimeUtc) : null;
    }
    private static bool DisplayText(string? text, int max) => !string.IsNullOrWhiteSpace(text) && text.Length <= max && !text.Any(char.IsControl);
    private static bool OrganizationTime(DateTimeOffset time) => time.Offset == TimeSpan.Zero && time > DateTimeOffset.UnixEpoch && time <= DateTimeOffset.UtcNow.AddMinutes(5);
    private static void TrimOrganizationImages(List<OfflineOrganizationRow> rows)
    {
        var chars = rows.Sum(row => row.LogoImageData?.Length ?? 0);
        foreach (var row in rows.Where(row => row.LogoImageData is not null).OrderBy(row => row.LogoCachedAtUtc).ToArray())
        {
            if (chars <= OrganizationLogoChars) break;
            chars -= row.LogoImageData!.Length;
            var index = rows.IndexOf(row);
            rows[index] = row with { LogoImageData = null, LogoCachedAtUtc = null };
        }
    }
    private static void UniqueOrganizationProperties(JsonElement value)
    {
        if (value.ValueKind == JsonValueKind.Object)
        {
            var names = new HashSet<string>(StringComparer.Ordinal);
            foreach (var property in value.EnumerateObject())
            { if (!names.Add(property.Name)) throw new InvalidDataException(); UniqueOrganizationProperties(property.Value); }
        }
        else if (value.ValueKind == JsonValueKind.Array)
            foreach (var item in value.EnumerateArray()) UniqueOrganizationProperties(item);
    }
}
