using System.Text;
using System.Text.Json;
using System.IO;
using StarBridge.Core.Events;

namespace StarBridge.Desktop;

internal static class LocalGameEventCategories
{
    public const string Session = "session";
    public const string Identity = "identity";
    public const string Server = "server";
    public const string Ship = "ship";
    public const string Location = "location";
    public const string Life = "life";
    public const string Other = "other";
}

internal sealed record LocalGameEventEntry(
    string Id,
    DateTimeOffset OccurredAt,
    string Category,
    string EventType,
    string Title,
    string Detail);

internal sealed class LocalGameEventJournal
{
    internal const int MaximumEntries = 3000;
    internal static readonly TimeSpan Retention = TimeSpan.FromDays(30);
    private static readonly TimeSpan DuplicateWindow = TimeSpan.FromSeconds(2);
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web)
    {
        WriteIndented = true
    };

    private readonly object _stateLock = new();
    private readonly SemaphoreSlim _persistGate = new(1, 1);
    private readonly Func<DateTimeOffset> _nowProvider;
    private readonly int _maximumEntries;
    private readonly TimeSpan _retention;
    private List<LocalGameEventEntry> _entries = [];

    public LocalGameEventJournal(
        string path,
        Func<DateTimeOffset>? nowProvider = null,
        int maximumEntries = MaximumEntries,
        TimeSpan? retention = null)
    {
        Path = path;
        _nowProvider = nowProvider ?? (() => DateTimeOffset.Now);
        _maximumEntries = Math.Max(1, maximumEntries);
        _retention = retention is { } configuredRetention && configuredRetention > TimeSpan.Zero
            ? configuredRetention
            : Retention;
    }

    public string Path { get; }
    public string? LastWriteError { get; private set; }
    public event EventHandler? Changed;

    public LocalGameEventEntry[] Entries
    {
        get
        {
            lock (_stateLock)
            {
                return _entries
                    .OrderByDescending(entry => entry.OccurredAt)
                    .ToArray();
            }
        }
    }

    public void Load()
    {
        var now = _nowProvider();
        var loaded = ReadEntries(Path) ?? ReadEntries($"{Path}.bak") ?? [];
        var shouldRewrite = false;
        lock (_stateLock)
        {
            _entries = Normalize(loaded, now);
            shouldRewrite = _entries.Count != loaded.Count;
        }
        Changed?.Invoke(this, EventArgs.Empty);
        if (shouldRewrite)
        {
            _ = PersistAsync();
        }
    }

    public LocalGameEventEntry Append(
        string category,
        string eventType,
        string title,
        string? detail = null,
        DateTimeOffset? occurredAt = null)
    {
        var timestamp = occurredAt ?? _nowProvider();
        var entry = new LocalGameEventEntry(
            Guid.NewGuid().ToString("N"),
            timestamp,
            NormalizeCategory(category),
            NormalizeText(eventType, 80, "Unknown"),
            NormalizeText(title, 180, "未命名事件"),
            NormalizeText(detail, 500, ""));
        var changed = false;
        lock (_stateLock)
        {
            _entries = Normalize(_entries, _nowProvider());
            var latest = _entries.OrderByDescending(candidate => candidate.OccurredAt).FirstOrDefault();
            if (latest is not null &&
                timestamp - latest.OccurredAt >= TimeSpan.Zero &&
                timestamp - latest.OccurredAt <= DuplicateWindow &&
                latest.Category.Equals(entry.Category, StringComparison.Ordinal) &&
                latest.EventType.Equals(entry.EventType, StringComparison.Ordinal) &&
                latest.Title.Equals(entry.Title, StringComparison.Ordinal) &&
                latest.Detail.Equals(entry.Detail, StringComparison.Ordinal))
            {
                return latest;
            }

            var latestIdentityState = FindLatestIdentityState(_entries, entry);
            if (latestIdentityState is not null &&
                latestIdentityState.EventType.Equals(entry.EventType, StringComparison.Ordinal))
            {
                return latestIdentityState;
            }

            _entries.Add(entry);
            _entries = Normalize(_entries, _nowProvider());
            changed = true;
        }

        if (changed)
        {
            Changed?.Invoke(this, EventArgs.Empty);
            _ = PersistAsync();
        }
        return entry;
    }

    public void Clear()
    {
        lock (_stateLock)
        {
            _entries.Clear();
        }
        Changed?.Invoke(this, EventArgs.Empty);
        _ = PersistAsync();
    }

    public async Task FlushAsync()
    {
        await _persistGate.WaitAsync();
        _persistGate.Release();
    }

    public static string Classify(FleetEventType eventType) => eventType switch
    {
        FleetEventType.PlayerOnline or FleetEventType.PlayerOffline => LocalGameEventCategories.Identity,
        FleetEventType.PlayerEnteredShip or FleetEventType.PlayerExitedShip or
            FleetEventType.PlayerControllingShip or FleetEventType.PlayerStoppedDrivingShip => LocalGameEventCategories.Ship,
        FleetEventType.PlayerLocationChanged or FleetEventType.PlayerNavigationTargetChanged => LocalGameEventCategories.Location,
        FleetEventType.PlayerDowned or FleetEventType.PlayerDied or
            FleetEventType.PlayerRevived or FleetEventType.PlayerRespawned => LocalGameEventCategories.Life,
        _ => LocalGameEventCategories.Other
    };

    public static string FormatExport(IEnumerable<LocalGameEventEntry> entries)
    {
        var builder = new StringBuilder();
        builder.AppendLine("星海舰桥本地事件日志");
        builder.AppendLine("仅包含应用已经识别的标准化事件，不包含完整 Game.log 原文。\n");
        foreach (var entry in entries.OrderBy(entry => entry.OccurredAt))
        {
            builder.Append(entry.OccurredAt.ToString("yyyy-MM-dd HH:mm:ss zzz"));
            builder.Append("  [").Append(entry.Category).Append("] ");
            builder.Append(entry.Title);
            if (!string.IsNullOrWhiteSpace(entry.Detail))
            {
                builder.Append(" · ").Append(entry.Detail);
            }
            builder.AppendLine();
        }
        return builder.ToString();
    }

    private async Task PersistAsync()
    {
        await _persistGate.WaitAsync();
        try
        {
            LocalGameEventEntry[] snapshot;
            lock (_stateLock)
            {
                snapshot = _entries.OrderBy(entry => entry.OccurredAt).ToArray();
            }

            var directory = System.IO.Path.GetDirectoryName(Path);
            if (!string.IsNullOrWhiteSpace(directory))
            {
                Directory.CreateDirectory(directory);
            }
            var temporaryPath = $"{Path}.tmp";
            await File.WriteAllTextAsync(
                temporaryPath,
                JsonSerializer.Serialize(snapshot, JsonOptions),
                new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
            if (File.Exists(Path))
            {
                File.Copy(Path, $"{Path}.bak", overwrite: true);
            }
            File.Move(temporaryPath, Path, overwrite: true);
            LastWriteError = null;
        }
        catch (Exception ex)
        {
            LastWriteError = UserFacingError.Describe(ex, "本地事件日志未能保存，请稍后重试。");
        }
        finally
        {
            _persistGate.Release();
        }
    }

    private static List<LocalGameEventEntry>? ReadEntries(string path)
    {
        try
        {
            if (!File.Exists(path))
            {
                return null;
            }
            return JsonSerializer.Deserialize<List<LocalGameEventEntry>>(File.ReadAllText(path), JsonOptions);
        }
        catch
        {
            return null;
        }
    }

    private List<LocalGameEventEntry> Normalize(
        IEnumerable<LocalGameEventEntry> entries,
        DateTimeOffset now)
    {
        var ordered = entries
            .Where(entry => !string.IsNullOrWhiteSpace(entry.Id) &&
                            entry.OccurredAt != default &&
                            now - entry.OccurredAt <= _retention &&
                            entry.OccurredAt <= now.AddMinutes(5))
            .GroupBy(entry => entry.Id, StringComparer.OrdinalIgnoreCase)
            .Select(group => group.OrderByDescending(entry => entry.OccurredAt).First())
            .OrderBy(entry => entry.OccurredAt);
        var normalized = new List<LocalGameEventEntry>();
        var identityStates = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var entry in ordered)
        {
            var identityKey = GetIdentityStateKey(entry);
            if (identityKey is not null)
            {
                if (identityStates.TryGetValue(identityKey, out var state) &&
                    state.Equals(entry.EventType, StringComparison.Ordinal))
                {
                    continue;
                }
                identityStates[identityKey] = entry.EventType;
            }
            normalized.Add(entry);
        }
        return normalized.TakeLast(_maximumEntries).ToList();
    }

    private static LocalGameEventEntry? FindLatestIdentityState(
        IEnumerable<LocalGameEventEntry> entries,
        LocalGameEventEntry candidate)
    {
        var identityKey = GetIdentityStateKey(candidate);
        return identityKey is null
            ? null
            : entries
                .Where(entry => entry.OccurredAt <= candidate.OccurredAt &&
                                identityKey.Equals(GetIdentityStateKey(entry), StringComparison.OrdinalIgnoreCase))
                .OrderByDescending(entry => entry.OccurredAt)
                .FirstOrDefault();
    }

    private static string? GetIdentityStateKey(LocalGameEventEntry entry)
    {
        if (!entry.Category.Equals(LocalGameEventCategories.Identity, StringComparison.Ordinal) ||
            string.IsNullOrWhiteSpace(entry.Detail))
        {
            return null;
        }
        return entry.Detail.Trim();
    }

    private static string NormalizeCategory(string? category) => category?.Trim().ToLowerInvariant() switch
    {
        LocalGameEventCategories.Session => LocalGameEventCategories.Session,
        LocalGameEventCategories.Identity => LocalGameEventCategories.Identity,
        LocalGameEventCategories.Server => LocalGameEventCategories.Server,
        LocalGameEventCategories.Ship => LocalGameEventCategories.Ship,
        LocalGameEventCategories.Location => LocalGameEventCategories.Location,
        LocalGameEventCategories.Life => LocalGameEventCategories.Life,
        _ => LocalGameEventCategories.Other
    };

    private static string NormalizeText(string? value, int maximumLength, string fallback)
    {
        var normalized = (value ?? "")
            .Replace('\r', ' ')
            .Replace('\n', ' ')
            .Trim();
        if (normalized.Length == 0)
        {
            return fallback;
        }
        return normalized.Length <= maximumLength ? normalized : normalized[..maximumLength];
    }
}
