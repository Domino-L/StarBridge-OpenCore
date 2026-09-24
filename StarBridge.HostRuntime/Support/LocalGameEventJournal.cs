using System.Text.Json;
using System.IO;
using StarBridge.Core.Events;

namespace StarBridge.HostRuntime.Support;

public static class LocalGameEventCategories
{
    public const string Session = "session";
    public const string Identity = "identity";
    public const string Server = "server";
    public const string Ship = "ship";
    public const string Location = "location";
    public const string Life = "life";
    public const string Other = "other";
}

public sealed class LocalGameEventJournal : IDisposable
{
    public const int MaximumEntries = LocalEventJournalReader.MaximumEntries;
    public static readonly TimeSpan Retention = LocalEventJournalReader.Retention;
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
    private List<LocalEventEntry> _entries = [];
    private FileStream? _writeLease;
    private bool _loaded, _disposed;
    private long _clearRevision;
    public long ClearRevision { get { lock (_stateLock) return _clearRevision; } }
    private LocalEventJournalReader Reader => new(System.IO.Path.GetDirectoryName(Path)!, _nowProvider);
    public bool IsWritable { get { lock (_stateLock) return _loaded && !_disposed && _writeLease is not null; } }

    public LocalGameEventJournal(
        string path,
        Func<DateTimeOffset>? nowProvider = null,
        int maximumEntries = MaximumEntries,
        TimeSpan? retention = null)
    {
        if (!System.IO.Path.IsPathFullyQualified(path) ||
            System.IO.Path.GetFileName(path) != "local-event-log.json")
            throw new ArgumentException("The configured local event journal path is required.");
        Path = System.IO.Path.GetFullPath(path);
        _nowProvider = nowProvider ?? (() => DateTimeOffset.Now);
        _maximumEntries = Math.Max(1, maximumEntries);
        _retention = retention is { } configuredRetention && configuredRetention > TimeSpan.Zero
            ? configuredRetention
            : Retention;
    }

    public string Path { get; }
    public string? LastWriteError { get; private set; }
    public event EventHandler? Changed;
    private Action<LocalEventEntry>? _appended;

    // Subscribe to new accepted entries only. Loading, reading, clearing and
    // duplicate suppression never publish an entry. Capture listeners under the
    // append lock so a later subscription cannot receive an earlier append.
    internal IDisposable SubscribeNewEntries(Action<LocalEventEntry> listener)
    {
        lock (_stateLock)
        {
            ObjectDisposedException.ThrowIf(_disposed, this);
            _appended += listener;
        }
        return new EntrySubscription(this, listener);
    }

    private sealed class EntrySubscription(LocalGameEventJournal owner, Action<LocalEventEntry> listener) : IDisposable
    {
        public void Dispose() { lock (owner._stateLock) owner._appended -= listener; }
    }

    public LocalEventEntry[] Entries
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
        lock (_stateLock)
        {
            if (_disposed || _loaded) return;
            try
            {
                var directory = System.IO.Path.GetDirectoryName(Path)!;
                CheckDirectory(directory);
                Directory.CreateDirectory(directory);
                _writeLease ??= new FileStream(Path + ".lock", FileMode.OpenOrCreate,
                    FileAccess.ReadWrite, FileShare.None, 1, FileOptions.DeleteOnClose);
                var snapshot = Reader.Read();
                if (!snapshot.Available) throw new IOException();
                _entries = Normalize(snapshot.Entries, _nowProvider());
                _loaded = true;
                LastWriteError = null;
            }
            catch
            {
                _writeLease?.Dispose();
                _writeLease = null;
                LastWriteError = "本地事件日志暂不可用，请关闭其他客户端后重试。";
            }
        }
        NotifyChanged();
    }

    public LocalEventEntry Append(
        string category,
        string eventType,
        string title,
        string? detail = null,
        DateTimeOffset? occurredAt = null,
        long? expectedClearRevision = null,
        Func<bool>? canAppend = null)
    {
        var timestamp = occurredAt ?? _nowProvider();
        var entry = new LocalEventEntry(
            Guid.NewGuid().ToString("N"),
            timestamp,
            NormalizeCategory(category),
            NormalizeText(eventType, 80, "Unknown"),
            NormalizeText(title, 180, "未命名事件"),
            NormalizeText(detail, 500, ""));
        var changed = false;
        Action<LocalEventEntry>? listeners = null;
        lock (_stateLock)
        {
            if ((expectedClearRevision is not null && expectedClearRevision != _clearRevision) ||
                canAppend?.Invoke() == false) return entry;
            if (!_loaded || _disposed || _writeLease is null)
            {
                LastWriteError = "本地事件日志暂不可用，未保存新记录。";
                return entry;
            }
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
            listeners = _appended;
        }

        if (changed)
        {
            // A consumer failure must never break the existing local journal.
            if (listeners is not null)
                foreach (Action<LocalEventEntry> listener in listeners.GetInvocationList())
                    try { listener(entry); } catch { }
            NotifyChanged();
            _ = PersistAsync();
        }
        return entry;
    }

    /// <summary>One writer and the original persistence gate cover append and clear.
    /// No UI reports success until both primary and backup have been committed.</summary>
    public async Task<LocalJournalClearResult> ClearAsync(
        Func<bool>? canCommit = null, CancellationToken cancellation = default)
    {
        bool acquired = false, changed = false;
        LocalJournalClearResult result;
        try
        {
            await _persistGate.WaitAsync(cancellation);
            acquired = true;
            lock (_stateLock)
            {
                void Guard()
                {
                    cancellation.ThrowIfCancellationRequested();
                    if (!_loaded || _disposed || _writeLease is null || canCommit?.Invoke() == false)
                        throw new InvalidOperationException();
                }
                Guard();
                var disk = Reader.Read();
                if (!disk.Available) throw new IOException();
                CheckDirectory(System.IO.Path.GetDirectoryName(Path)!);
                // For a backup-only source, retain a readable primary before
                // clearing backup. A partial failure must not erase the only copy.
                if (disk.State == "recovered") WriteAtomic(Path, _entries.ToArray());
                Guard();
                WriteAtomic(Path + ".bak", []);
                Guard();
                WriteAtomic(Path, []);
                _clearRevision++;
                _entries.Clear();
                LastWriteError = null;
                changed = true;
                result = LocalJournalClearResult.Cleared;
            }
        }
        catch (OperationCanceledException) { result = LocalJournalClearResult.Cancelled; }
        catch
        {
            LastWriteError = "未能完成清空，请重试。";
            result = LocalJournalClearResult.Failed;
        }
        finally { if (acquired) _persistGate.Release(); }
        if (changed) NotifyChanged();
        return result;
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

    public static string FormatExport(IEnumerable<LocalEventEntry> entries) =>
        LocalEventJournalReader.FormatExport(new("ready", entries.ToArray()));

    private async Task PersistAsync()
    {
        await _persistGate.WaitAsync();
        try
        {
            lock (_stateLock)
            {
                if (!_loaded || _disposed || _writeLease is null) return;
                CheckDirectory(System.IO.Path.GetDirectoryName(Path)!);
                var disk = Reader.Read();
                if (!disk.Available) throw new IOException();
                // Never rotate a corrupt primary over the only valid backup.
                if (disk.State == "ready") WriteAtomic(Path + ".bak", disk.Entries.ToArray());
                WriteAtomic(Path, _entries.OrderBy(entry => entry.OccurredAt).ToArray());
                LastWriteError = null;
            }
        }
        catch { LastWriteError = "本地事件日志未能保存，请稍后重试。"; }
        finally { _persistGate.Release(); }
    }

    private static void WriteAtomic(string path, LocalEventEntry[] entries)
    {
        var temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write,
                FileShare.None, 4096, FileOptions.WriteThrough))
            {
                JsonSerializer.Serialize(stream, entries, JsonOptions);
                stream.Flush(true);
            }
            File.Move(temporary, path, overwrite: true);
        }
        finally
        {
            try { File.Delete(temporary); }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
        }
    }

    private static void CheckDirectory(string path)
    {
        for (var directory = new DirectoryInfo(path); directory is not null; directory = directory.Parent)
            if (directory.Exists && directory.Attributes.HasFlag(FileAttributes.ReparsePoint))
                throw new IOException();
    }

    private void NotifyChanged()
    {
        // A presentation listener must not turn a confirmed disk commit into failure.
        try { Changed?.Invoke(this, EventArgs.Empty); } catch { }
    }

    public void Dispose()
    {
        lock (_stateLock)
        {
            if (_disposed) return;
            _disposed = true;
            _writeLease?.Dispose();
            _writeLease = null;
        }
    }

    private List<LocalEventEntry> Normalize(
        IEnumerable<LocalEventEntry> entries,
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
        var normalized = new List<LocalEventEntry>();
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

    private static LocalEventEntry? FindLatestIdentityState(
        IEnumerable<LocalEventEntry> entries,
        LocalEventEntry candidate)
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

    private static string? GetIdentityStateKey(LocalEventEntry entry)
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

    internal static string NormalizeText(string? value, int maximumLength, string fallback)
    {
        var normalized = (value ?? "")
            .Replace('\r', ' ')
            .Replace('\n', ' ')
            .Trim();
        normalized = new string(normalized.Select(c => char.IsControl(c) ? ' ' : c).ToArray());
        if (normalized.Length == 0)
        {
            return fallback;
        }
        return normalized.Length <= maximumLength ? normalized : normalized[..maximumLength];
    }
}

public enum LocalJournalClearResult { Cleared, Cancelled, Failed }
