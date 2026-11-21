using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using StarBridge.Core.Events;
using StarBridge.HostRuntime.Achievements;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Support;

// Presentation only. Observe is memory-only even when called under the sampling lock.
// One device-owned instance serializes contract persistence and confirmed clears.
public sealed class LocalContractHistory(string dataRoot, Func<DateTimeOffset>? now = null) : IDisposable, IAsyncDisposable
{
    private const int Capacity = 256;
    private readonly string _root = Path.GetFullPath(dataRoot);
    private readonly Func<DateTimeOffset> _now = now ?? (() => DateTimeOffset.UtcNow);
    private readonly object _sync = new();
    private readonly SemaphoreSlim _persistGate = new(1, 1);
    private readonly Dictionary<(BridgeAccountContext, string), (string Name, string Issuer)> _names = [];
    private readonly Dictionary<(BridgeAccountContext, string, string), string> _objectiveTexts = [];
    private readonly HashSet<(BridgeAccountContext, string)> _seen = [];
    private readonly Queue<Pending> _pending = new();
    private Task? _worker;
    private bool _stopping, _overflowReported;
    private long _clearRevision;
    public long ClearRevision { get { lock (_sync) return _clearRevision; } }
    public string? LastWriteError { get; private set; }
    internal int OverflowDiagnostics { get; private set; }
    internal int RetryCount { get; private set; }
    internal int BackgroundFaultDiagnostics { get; private set; }
    internal Func<TimeSpan, Task> RetryDelay { get; set; } = Task.Delay;
    internal Action? BeforeObserve { get; set; }
    internal int PendingCount { get { lock (_sync) return _pending.Count; } }
    private sealed record Pending(BridgeAccountContext Owner, LocalEventEntry Entry, string AcceptedId,
        bool KnownName, long Revision, Func<bool> Current);

    public string? DirectoryFor(BridgeAccountContext? owner)
    {
        if (owner is null) return null;
        if (!owner.IsComplete || new[] { owner.Environment, owner.Authority, owner.Subject }
            .Any(s => s.Length > 2048 || s.Any(char.IsControl))) throw new InvalidDataException();
        var hash = Convert.ToHexString(SHA256.HashData(JsonSerializer.SerializeToUtf8Bytes(
            new[] { owner.Environment, owner.Authority, owner.Subject })));
        return Path.Combine(_root, "local-contract-history-v1", hash);
    }

    internal void Observe(BridgeAccountContext owner, FleetEvent evidence,
        ContractAchievementStore.Run run, Func<bool> current, bool live = true, long? expectedRevision = null)
    {
        if (evidence.Contract is not { } data || evidence.Timestamp is not { } at || !current()) return;
        BeforeObserve?.Invoke();
        lock (_sync)
        {
            if (_stopping) return;
            var key = (owner, data.MissionId);
            // Historical evidence supplies display metadata only, never an event or a start time.
            if (evidence.Type == FleetEventType.ContractAccepted)
            {
                _names[key] = Acceptance(data.Text);
                if (_names.Count > 8192) _names.Remove(_names.Keys.First());
            }
            if (!live || expectedRevision is { } revision && revision != _clearRevision) return;
            // Display metadata is independent of achievement eligibility and stage tracking.
            var objectiveKey = (owner, data.MissionId, data.ObjectiveId ?? "");
            if (evidence.Type == FleetEventType.ContractObjective && data.ObjectiveId is not null &&
                Clean(data.Text, 500) is { Length: > 0 } objectiveText)
            {
                _objectiveTexts.Remove(objectiveKey);
                _objectiveTexts[objectiveKey] = objectiveText;
                if (_objectiveTexts.Count > 4096) _objectiveTexts.Remove(_objectiveTexts.Keys.First());
            }
            var known = _names.TryGetValue(key, out var presentation);
            if (!known) presentation = ("未知合约", "");
            var acceptedId = Id(data.MissionId, "accepted");
            string title, detail = "", id;
            switch (evidence.Type)
            {
                case FleetEventType.ContractAccepted:
                    title = "接受合约：" + presentation.Name;
                    detail = presentation.Issuer;
                    id = acceptedId;
                    break;
                case FleetEventType.ContractObjective when data.State == "COMPLETED":
                    var goal = run.Objectives?.FirstOrDefault(g => g.Id == data.ObjectiveId);
                    var text = Clean(data.Text, 500);
                    // Achievement state outlives diagnostic clears; only live display
                    // metadata may supply missing text, never run.Objectives.
                    if (text.Length == 0) text = _objectiveTexts.GetValueOrDefault(objectiveKey) ?? "";
                    if (text.Length == 0) return;
                    title = "阶段目标完成：" + text;
                    detail = presentation.Name;
                    if (goal?.Travel == true && run.ArrivedAt == goal.CompletedAt)
                        detail += " · 已到达作战地点";
                    id = Id(data.MissionId, "objective|" + text.ToUpperInvariant());
                    break;
                case FleetEventType.ContractEnded:
                    var prefix = data.State switch {
                        "COMPLETED" => "合约完成：", "FAILED" => "合约失败：",
                        "WITHDRAWN" or "ABANDONED" => "放弃合约：", _ => null };
                    if (prefix is null) return;
                    title = prefix + presentation.Name;
                    if (data.State == "COMPLETED")
                    {
                        detail = presentation.Issuer;
                        if (run.AcceptedAt is { } start && start <= at)
                        {
                            var minutes = (long)(at - start).TotalMinutes;
                            detail = Join(detail, $"接单到完成 {minutes / 60} 小时 {minutes % 60} 分");
                        }
                    }
                    id = Id(data.MissionId, "ended");
                    break;
                default: return;
            }
            if (_seen.Contains((owner, id))) return;
            var entry = new LocalEventEntry(id, at, "contract", evidence.Type.ToString(), Clean(title, 180), Clean(detail, 500));
            if (_pending.Count == Capacity)
            {
                _pending.Dequeue();
                if (!_overflowReported)
                {
                    _overflowReported = true;
                    OverflowDiagnostics++;
                    LastWriteError = "合约日志待写队列已满，已丢弃最早的待写记录。";
                    System.Diagnostics.Trace.TraceWarning("Local contract history queue overflow; oldest pending entry dropped.");
                }
            }
            _pending.Enqueue(new(owner, entry, acceptedId, known, _clearRevision, current));
            _worker ??= Task.Run(DrainAsync);
        }
    }

    // Snapshot the current worker: all entries admitted before this call are covered.
    public Task FlushAsync() { lock (_sync) return _worker ?? Task.CompletedTask; }

    private async Task DrainAsync()
    {
        while (true)
        {
            Pending[] batch;
            lock (_sync)
            {
                if (_pending.Count == 0) { _worker = null; _overflowReported = false; return; }
                batch = _pending.ToArray(); _pending.Clear();
            }
            try
            {
                foreach (var group in batch.GroupBy(p => p.Owner))
                    await PersistAsync(group.ToArray()).ConfigureAwait(false);
            }
            catch (Exception)
            {
                // Observe the fault here, discard this batch, then drain later admissions.
                // The empty-queue branch resets _worker under the enqueue lock, including on shutdown.
                lock (_sync)
                {
                    BackgroundFaultDiagnostics++;
                    LastWriteError = "合约日志本批记录未能保存，后续记录会继续保存。";
                }
                System.Diagnostics.Trace.TraceWarning("Local contract history background batch failed and was discarded.");
            }
        }
    }

    private bool Admitted(Pending p)
    {
        if (!p.Current()) return false;
        lock (_sync) return p.Revision == _clearRevision && !_seen.Contains((p.Owner, p.Entry.Id));
    }

    private async Task PersistAsync(Pending[] batch)
    {
        // Retry outside the sampling thread and release the gate during backoff so clear can proceed.
        for (var attempt = 0; attempt < 6; attempt++)
        {
            await _persistGate.WaitAsync().ConfigureAwait(false);
            try
            {
                var active = batch.Where(Admitted).DistinctBy(p => p.Entry.Id).ToArray();
                if (active.Length == 0) return;
                using var store = new LocalContractHistoryStore(DirectoryFor(active[0].Owner)!, _now);
                var disk = store.Read();
                var rows = disk.Entries.ToList();
                foreach (var item in active)
                {
                    if (rows.Any(e => e.Id == item.Entry.Id)) continue;
                    var entry = item.Entry;
                    if (!item.KnownName && rows.FirstOrDefault(e => e.Id == item.AcceptedId &&
                        e.Title.StartsWith("接受合约：", StringComparison.Ordinal)) is { } acceptance)
                    {
                        var name = acceptance.Title["接受合约：".Length..];
                        entry = entry.EventType == nameof(FleetEventType.ContractObjective)
                            ? entry with { Detail = Clean(entry.Detail.Replace("未知合约", name), 500) }
                            : entry with { Title = Clean(entry.Title.Replace("未知合约", name), 180),
                                Detail = entry.Title.StartsWith("合约完成：", StringComparison.Ordinal)
                                    ? Clean(Join(acceptance.Detail, entry.Detail), 500) : entry.Detail };
                    }
                    rows.Add(entry);
                }
                // No successful clear can cross this gate. Account/cancellation are still checked at commit.
                bool Current() => active.All(p => p.Current()) && active.All(p => p.Revision == ClearRevision);
                if (!Current()) return;
                store.Save(rows, disk, Current);
                lock (_sync)
                {
                    foreach (var item in active) _seen.Add((item.Owner, item.Entry.Id));
                    while (_seen.Count > 20000) _seen.Remove(_seen.First());
                    LastWriteError = null;
                }
                return;
            }
            catch (OperationCanceledException) { return; }
            catch (Exception error) when (ContractRecordStore.IsStorageError(error))
            {
                LastWriteError = "合约日志未能保存，请稍后重试。";
                if (attempt == 5) return;
                RetryCount++;
            }
            finally { _persistGate.Release(); }
            await RetryDelay(TimeSpan.FromMilliseconds(100 * (1 << attempt))).ConfigureAwait(false);
        }
    }

    public async Task<LocalJournalClearResult> ClearAsync(BridgeAccountContext? owner,
        Func<bool> current, CancellationToken cancellation)
    {
        if (owner is null) return cancellation.IsCancellationRequested ? LocalJournalClearResult.Cancelled :
            current() ? LocalJournalClearResult.Cleared : LocalJournalClearResult.Failed;
        var acquired = false;
        try
        {
            await _persistGate.WaitAsync(cancellation).ConfigureAwait(false); acquired = true;
            await Task.Run(() =>
            {
                void Guard()
                {
                    cancellation.ThrowIfCancellationRequested();
                    if (!current()) throw new OperationCanceledException();
                }
                Guard();
                using var store = new LocalContractHistoryStore(DirectoryFor(owner)!, _now);
                store.Clear(Guard);
                lock (_sync)
                {
                    _clearRevision++;
                    foreach (var key in _objectiveTexts.Keys.Where(k => k.Item1 == owner).ToArray())
                        _objectiveTexts.Remove(key);
                }
            }, cancellation).ConfigureAwait(false);
            return LocalJournalClearResult.Cleared;
        }
        catch (OperationCanceledException) { return LocalJournalClearResult.Cancelled; }
        catch (Exception error) when (ContractRecordStore.IsStorageError(error)) { return LocalJournalClearResult.Failed; }
        finally { if (acquired) _persistGate.Release(); }
    }

    public async ValueTask DisposeAsync()
    {
        Task pending;
        lock (_sync) { _stopping = true; pending = _worker ?? Task.CompletedTask; }
        await pending.ConfigureAwait(false);
    }
    public void Dispose() => DisposeAsync().AsTask().GetAwaiter().GetResult();

    private static (string Name, string Issuer) Acceptance(string? text)
    {
        var value = Clean(text, 500);
        var markup = value.IndexOf('<');
        if (markup >= 0) value = value[..markup].TrimEnd();
        var open = value.IndexOf('[');
        var close = open < 0 ? -1 : value.IndexOf(']', open + 1);
        var issuer = open >= 0 && close > open ? value[(open + 1)..close].Trim() : "";
        var name = open >= 0 && close > open ? (open == 0 ? value[(close + 1)..] : value[..open]).Trim() : value;
        name = name.TrimEnd(' ', ':', '：');
        return (string.IsNullOrWhiteSpace(name) ? "未知合约" : name, issuer);
    }
    private static string Clean(string? text, int limit) => LocalGameEventJournal.NormalizeText(text, limit, "").TrimEnd(' ', ':', '：');
    private static string Join(string first, string second) => first.Length == 0 ? second : second.Length == 0 ? first : first + " · " + second;
    private static string Id(string mission, string kind) => "contract-" + Convert.ToHexString(
        SHA256.HashData(Encoding.UTF8.GetBytes(mission + "|" + kind)));
}
