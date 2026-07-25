using System.IO;
using System.Text.Json;

namespace StarBridge.Desktop;

public sealed class FleetDirectoryCache
{
    private const int MaxCachedFleets = 200;
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);
    private readonly string _cachePath;

    public FleetDirectoryCache(string? cachePath = null)
    {
        _cachePath = string.IsNullOrWhiteSpace(cachePath)
            ? Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "StarBridge",
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

            await using var stream = File.OpenRead(_cachePath);
            var snapshots = await JsonSerializer.DeserializeAsync<NetworkFleetSnapshot[]>(stream, JsonOptions);
            return snapshots?
                .Where(snapshot => !string.IsNullOrWhiteSpace(snapshot.Name) && !string.IsNullOrWhiteSpace(snapshot.Code))
                .Select(snapshot => snapshot with { PublicProfileEnabled = true })
                .Take(MaxCachedFleets)
                .ToArray() ?? Array.Empty<NetworkFleetSnapshot>();
        }
        catch
        {
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
                await JsonSerializer.SerializeAsync(stream, safeSnapshots, JsonOptions);
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
            Squads = [],
            CurrentTaskNoticeRevision = 0,
            EmailNotificationsEnabled = false,
            PublicProfileEnabled = true,
            PublicShipCount = publicShipCount,
            PublicShipTypeSummary = publicShipCount > 0 ? snapshot.PublicShipTypeSummary : null
        };
    }
}
