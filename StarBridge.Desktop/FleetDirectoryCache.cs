using System.IO;
using System.Text.Json;

namespace StarBridge.Desktop;

public sealed class FleetDirectoryCache
{
    private const int MaxCachedFleets = 200;
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);
    private readonly string _cachePath;

    private sealed record CacheEnvelope(
        DateTimeOffset WrittenAtUtc,
        NetworkFleetSnapshot[] Snapshots);

    public DateTimeOffset? LastLoadedWrittenAtUtc { get; private set; }

    public bool HasCachedFile => File.Exists(_cachePath);

    public FleetDirectoryCache(string? cachePath = null)
    {
        _cachePath = string.IsNullOrWhiteSpace(cachePath)
            ? Path.Combine(
                DesktopAppConfig.ConfigDirectory,
                "Cache",
                "fleet-directory.json")
            : cachePath;
    }

    public async Task<IReadOnlyList<NetworkFleetSnapshot>> LoadAsync()
    {
        try
        {
            if (!File.Exists(_cachePath))
            {
                return Array.Empty<NetworkFleetSnapshot>();
            }

            var payload = await File.ReadAllTextAsync(_cachePath);
            NetworkFleetSnapshot[]? snapshots;
            try
            {
                var envelope = JsonSerializer.Deserialize<CacheEnvelope>(payload, JsonOptions);
                snapshots = envelope?.Snapshots;
                LastLoadedWrittenAtUtc = envelope?.WrittenAtUtc.ToUniversalTime();
            }
            catch (JsonException)
            {
                // Legacy caches were a bare array and had no trustworthy write
                // timestamp. Preserve the data without inventing a date.
                snapshots = JsonSerializer.Deserialize<NetworkFleetSnapshot[]>(payload, JsonOptions);
                LastLoadedWrittenAtUtc = null;
            }
            return snapshots?
                .Where(snapshot => !string.IsNullOrWhiteSpace(snapshot.Name) && !string.IsNullOrWhiteSpace(snapshot.Code))
                .Select(snapshot => snapshot with { PublicProfileEnabled = true })
                .Take(MaxCachedFleets)
                .ToArray() ?? Array.Empty<NetworkFleetSnapshot>();
        }
        catch
        {
            LastLoadedWrittenAtUtc = null;
            return Array.Empty<NetworkFleetSnapshot>();
        }
    }

    public async Task SaveAsync(IEnumerable<NetworkFleetSnapshot> snapshots)
    {
        var directory = Path.GetDirectoryName(_cachePath);
        if (string.IsNullOrWhiteSpace(directory))
        {
            return;
        }

        var safeSnapshots = snapshots
            .Where(snapshot => !string.IsNullOrWhiteSpace(snapshot.Name) && !string.IsNullOrWhiteSpace(snapshot.Code))
            .Select(ToPublicCacheSnapshot)
            .Take(MaxCachedFleets)
            .ToArray();
        var temporaryPath = _cachePath + ".tmp";

        try
        {
            Directory.CreateDirectory(directory);
            await using (var stream = File.Create(temporaryPath))
            {
                await JsonSerializer.SerializeAsync(
                    stream,
                    new CacheEnvelope(DateTimeOffset.UtcNow, safeSnapshots),
                    JsonOptions);
            }

            File.Move(temporaryPath, _cachePath, overwrite: true);
        }
        catch
        {
            try
            {
                File.Delete(temporaryPath);
            }
            catch
            {
                // Cache cleanup is best effort only.
            }
        }
    }

    private static NetworkFleetSnapshot ToPublicCacheSnapshot(NetworkFleetSnapshot snapshot)
    {
        var publicShipCount = !string.Equals(snapshot.PublicShipScaleMode, "Hidden", StringComparison.OrdinalIgnoreCase)
            ? Math.Max(snapshot.PublicShipCount, snapshot.Ships?.Length ?? 0)
            : 0;
        return snapshot with
        {
            NoticeTitle = null,
            NoticeContent = null,
            NoticePublishedAt = null,
            CurrentTaskTitle = null,
            CurrentTaskBrief = null,
            CurrentTaskParticipants = null,
            CurrentTaskRally = null,
            CurrentTaskShip = null,
            CurrentTaskTime = null,
            ActionPlans = [],
            OwnerAccount = null,
            MemberPermissions = [],
            Members = [],
            EventLog = [],
            Ships = [],
            TaskHistory = [],
            Applications = [],
            Invites = [],
            CurrentTaskNoticeRevision = 0,
            EmailNotificationsEnabled = false,
            PublicProfileEnabled = true,
            PublicShipCount = publicShipCount,
            PublicShipTypeSummary = publicShipCount > 0 ? snapshot.PublicShipTypeSummary : null
        };
    }
}
