using System.Security.Cryptography;
using System.Text.Json;
using StarBridge.Core.Events;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Support;

public sealed class LocalMissionRecords(string dataRoot) : IAsyncDisposable
{
    private readonly string _root = Path.GetFullPath(dataRoot);
    private readonly SemaphoreSlim _gate = new(1, 1);
    private readonly object _sync = new();
    private readonly Dictionary<(BridgeAccountContext, string), MissionEvidence> _live = [];
    private Task _writer = Task.CompletedTask;
    private bool _stopping;
    internal int WriteFailures { get; private set; }

    public string? DirectoryFor(BridgeAccountContext? owner)
    {
        if (owner is null) return null;
        if (!owner.IsComplete || new[] { owner.Environment, owner.Authority, owner.Subject }
            .Any(s => s.Length > 2048 || s.Any(char.IsControl))) throw new InvalidDataException();
        var hash = Convert.ToHexString(SHA256.HashData(JsonSerializer.SerializeToUtf8Bytes(
            new[] { owner.Environment, owner.Authority, owner.Subject })));
        return Path.Combine(_root, "local-mission-records-v1", hash);
    }

    internal async Task<MissionRecordsSnapshot> ReadAsync(BridgeAccountContext owner, CancellationToken token = default)
    {
        await _gate.WaitAsync(token).ConfigureAwait(false);
        try { using var store = new LocalMissionRecordsStore(DirectoryFor(owner)!); return store.Read(); }
        finally { _gate.Release(); }
    }
    public async Task<MissionRecordsMergeResult> MergeAsync(BridgeAccountContext owner,
        IEnumerable<LocalMissionRecord> records, Func<bool> current, CancellationToken token = default)
    {
        await _gate.WaitAsync(token).ConfigureAwait(false);
        try
        {
            token.ThrowIfCancellationRequested();
            if (!current()) throw new OperationCanceledException();
            using var store = new LocalMissionRecordsStore(DirectoryFor(owner)!);
            return store.Merge(records, () => !token.IsCancellationRequested && current());
        }
        finally { _gate.Release(); }
    }

    public static IReadOnlyList<LocalMissionGroup> Summarize(IEnumerable<LocalMissionRecord> records) => records
        .Where(r => r.DefinitionId is not null || r.ContractCode is not null)
        .GroupBy(r => r.DefinitionId ?? "code:" + r.ContractCode, StringComparer.Ordinal)
        .Select(g => {
            double? Fastest(Func<LocalMissionRecord, bool> category) => g
                .Where(r => r.AcceptedAt is { } at && r.CompletedAt > at && category(r))
                .Select(r => (double?)(r.CompletedAt - r.AcceptedAt!.Value).TotalSeconds).Min();
            var solo = Fastest(r => r.Joined == false && r.Team == false);
            var team = Fastest(r => r.Joined == false && r.Team == true);
            return new LocalMissionGroup(g.Key, g.Select(r => r.DefinitionId).FirstOrDefault(d => d is not null),
                g.Select(r => r.ContractCode).OfType<string>().Order(StringComparer.Ordinal).FirstOrDefault(), g.Count(),
                new[] { solo, team }.Min(), g.Max(r => r.CompletedAt), solo, team,
                Fastest(r => r.Joined == true && r.JoinedFromStart == true),
                Fastest(r => r.Joined == true && r.JoinedFromStart == false));
        })
        .OrderBy(g => g.Key, StringComparer.Ordinal).ToArray();

    // Called only after GameLogRuntime has attributed a LIVE source to its account.
    // Disk work stays off the reader lock and cannot fault the existing consumers.
    internal void Observe(BridgeAccountContext owner, IEnumerable<(FleetEvent Event, bool Live)> events, Func<bool> current,
        string? selfPlayerId = null)
    {
        lock (_sync)
        {
            if (_stopping || !current()) return;
            var rows = new Dictionary<string, LocalMissionRecord>();
            foreach (var (e, live) in events)
            {
                if (!live || e.Contract is not { } data || !Guid.TryParse(data.MissionId, out var id) || id == Guid.Empty) continue;
                var key = (owner, id.ToString("D"));
                if (!_live.TryGetValue(key, out var evidence)) _live[key] = evidence = new();
                evidence.Observe(e);
                evidence.ForgetMarkers(); // live clients write HUD acceptance notices
                evidence.Identify(selfPlayerId);
                if (evidence.Record("live") is { } row) rows[row.MissionId] = row;
            }
            while (_live.Count > LocalMissionRecordsStore.MaximumRecords) _live.Remove(_live.Keys.First());
            if (rows.Count == 0) return;
            var before = _writer;
            _writer = Task.Run(async () => {
                await before.ConfigureAwait(false);
                try { await MergeAsync(owner, rows.Values, current).ConfigureAwait(false); }
                catch (OperationCanceledException) { }
                catch (Exception) { WriteFailures++; }
            });
        }
    }

    public Task FlushAsync() { lock (_sync) return _writer; }
    public async ValueTask DisposeAsync()
    {
        Task pending;
        lock (_sync) { _stopping = true; pending = _writer; _live.Clear(); }
        await pending.ConfigureAwait(false);
    }
}

// Shared event aggregation for live evidence and cross-file imports. No blueprint parsing.
internal sealed class MissionEvidence
{
    private string? _mission, _definition, _code;
    // CreateMarker times stand in for acceptance only in archive files without any HUD notification
    // line (2025 builds): there the first marker followed the share push in 240/240 joined runs, and in
    // later logs it matched the acceptance notice within 1 s (154 missions). Files that do write HUD
    // lines and live evidence drop markers, so a marker rebuilt after a reconnect never shortens a run.
    // Known limit (scheduler 11-13): a reconnect inside a 2025-build file whose original acceptance
    // file was deleted still times from the rebuilt marker; the remaining logs cannot tell them apart.
    private DateTimeOffset? _accepted, _completed;
    private readonly HashSet<DateTimeOffset> _markers = [];
    private readonly HashSet<DateTimeOffset> _shared = [];
    private readonly HashSet<(DateTimeOffset At, string Player, string? Self)> _players = [];
    private readonly HashSet<(DateTimeOffset At, string State, bool Created)> _objectives = [];

    // Repeated pushes are deduplicated. No count cap: truncation could drop the first
    // post-share objective or an early completion, and real missions carry few objectives.
    private void AddObjective((DateTimeOffset At, string State, bool Created) objective) => _objectives.Add(objective);

    internal void ForgetMarkers() => _markers.Clear();

    // Resolve identity before merging a file. GEIDs stay in transient evidence only.
    internal void Identify(string? selfPlayerId)
    {
        if (string.IsNullOrEmpty(selfPlayerId)) return;
        var unresolved = _players.Where(p => p.Self is null).ToArray();
        foreach (var player in unresolved)
        {
            _players.Remove(player);
            _players.Add((player.At, player.Player, selfPlayerId));
        }
    }
    internal void Merge(MissionEvidence other)
    {
        _mission ??= other._mission;
        static string? Choose(string? a, string? b) => a is null ? b : b is null ? a : string.CompareOrdinal(a, b) < 0 ? a : b;
        _definition = Choose(_definition, other._definition); _code = Choose(_code, other._code);
        if (other._accepted is { } accepted && (_accepted is null || accepted < _accepted)) _accepted = accepted;
        _markers.UnionWith(other._markers);
        if (other._completed is { } completed && (_completed is null || completed < _completed)) _completed = completed;
        _shared.UnionWith(other._shared);
        _players.UnionWith(other._players);
        foreach (var objective in other._objectives) AddObjective(objective);
    }
    internal void Observe(FleetEvent e)
    {
        if (e.Contract is not { } data || e.Timestamp is not { } at ||
            !Guid.TryParse(data.MissionId, out var id) || id == Guid.Empty) return;
        _mission = id.ToString("D");
        if (e.Type == FleetEventType.ContractShared) _shared.Add(at);
        if (e.Type == FleetEventType.ContractPlayerJoined && data.PlayerId is { Length: > 0 } player)
            _players.Add((at, player, null));
        // Only server ObjectiveUpserted pushes establish participation; HUD notices
        // and hidden phase_ objectives do not describe the visible starting state.
        if (e.Type == FleetEventType.ContractObjective && data.ObjectiveId is { } objective &&
            !objective.StartsWith("phase_", StringComparison.OrdinalIgnoreCase) &&
            (data.ObjectiveUpserted || e.SourceLine?.Contains("<ObjectiveUpserted>", StringComparison.Ordinal) == true) && data.State is { } state)
            AddObjective((at, state, data.Created));
        if (e.Type == FleetEventType.ContractAccepted && (_accepted is null || at < _accepted)) _accepted = at;
        if (e.Type == FleetEventType.ContractDefined)
        {
            _markers.Add(at);
            static string? Choose(string? a, string? b) => string.IsNullOrWhiteSpace(b) ? a :
                a is null || string.CompareOrdinal(b, a) < 0 ? b : a;
            _definition = Choose(_definition, data.DefinitionId);
            _code = Choose(_code, data.Contract);
        }
        if (e.Type == FleetEventType.ContractEnded && data.State == "COMPLETED" && (_completed is null || at < _completed))
            _completed = at;
    }
    internal LocalMissionRecord? Record(string source)
    {
        if (_mission is null || _completed is not { } end) return null;
        var sharedAt = _shared.Where(at => at <= end).Select(at => (DateTimeOffset?)at).Min();
        var joined = sharedAt is not null;
        // Joined runs time from joining: only markers at or after the share push qualify.
        var acceptedAt = _accepted ?? _markers.Where(at => at <= end && (sharedAt is not { } share || at >= share))
            .Select(at => (DateTimeOffset?)at).Min();
        var start = joined ? sharedAt : acceptedAt;
        var teammates = start is { } from ? _players.Where(p => p.Self is not null && p.Player != p.Self &&
            p.At >= from && p.At <= end).Select(p => p.Player).Distinct(StringComparer.Ordinal).Count() : 0;
        var first = _objectives.Where(o => sharedAt is { } share && o.At >= share && o.At <= end)
            .OrderBy(o => o.At).FirstOrDefault();
        bool? full = joined ? acceptedAt is { } accepted && first.State == "INPROGRESS" && first.Created &&
            !_objectives.Any(o => o.State == "COMPLETED" && o.At >= accepted && o.At <= accepted.AddSeconds(10) && o.At <= end) : null;
        return new(_mission, _definition, _code, acceptedAt, end, source, joined, !joined && teammates > 0, full, teammates);
    }
}
