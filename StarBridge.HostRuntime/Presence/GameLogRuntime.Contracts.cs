using StarBridge.Core.Events;
using StarBridge.HostRuntime.Achievements;
using StarBridge.NativeBridge;
using StarBridge.HostRuntime.Support;

namespace StarBridge.HostRuntime.Presence;

public sealed partial class GameLogRuntime
{
    internal Func<string, FleetEvent?>? EventParser { set => _session.EventParser = value; }
    private bool _contractReadFaulted;
    private ContractRunTracker? _contractTracker;
    private void ContractStep(Action action)
    {
        if (_contractReadFaulted) return;
        try { action(); IdentityGateJournal.Changed("gamelog-contract", "code=ok"); }
        catch (Exception error) { ContractReadFault(error, ""); }
    }
    private void ContractReadFault(Exception error, string line)
    {
        // Changed, not Event: a persistent fault would otherwise log every 0.5 s sample.
        IdentityGateJournal.Changed("gamelog-contract", $"code=contract exception={IdentityGateJournal.Type(error)}");
        if (_owner.Context is { } owner)
        {
            foreach (var (e, _) in _contractEvents)
                if (e.Contract is { } data) _contractUncertain.Add((owner, data.MissionId));
        }
        QuarantineContractLine(line);
        _contractReadFaulted = true;
        BreakContractReading();
    }
    private void QuarantineContractLine(string line)
    {
        if (_owner.Context is not { } owner) return;
        // Parsing may have failed before emitting an event. Quarantine GUIDs on
        // the bounded failed/skipped lines without logging any contents.
        for (var i = 0; i + 36 <= line.Length; i++)
            if (Guid.TryParseExact(line.AsSpan(i, 36), "D", out var id))
            { _contractUncertain.Add((owner, id.ToString("D"))); i += 35; }
    }
    private LocalContractHistory? _contractHistory;
    private LocalMissionRecords? _missionRecords;
    private bool _contractEvidenceSubscribed;
    private void SubscribeContractEvidence()
    {
        if (_contractEvidenceSubscribed) return;
        _session.ContractEvidence += AddContractEvidence;
        _contractEvidenceSubscribed = true;
    }
    internal void ConfigureMissionRecords(LocalMissionRecords records)
    {
        lock (_sync) { _missionRecords = records; SubscribeContractEvidence(); }
    }
    private void ObserveMissionRecords(BridgeAccountContext owner, Func<bool> current)
    {
        try { _missionRecords?.Observe(owner, _contractEvents, current, _reader.ContractPlayerId); }
        catch (Exception) { /* Mission storage never changes the existing evidence consumers. */ }
    }
    private long _contractHistoryRevision;
    private readonly List<(FleetEvent Event, bool Live)> _contractEvents = [];
    private readonly HashSet<(BridgeAccountContext Owner, string Mission)> _contractUncertain = [];
    private DateTimeOffset? _contractSampleAt;
    private CancellationToken _contractReadToken;
    internal event Action? ContractQueued;

    internal void ConfigureContracts(ContractAchievementStore store, ContractRecordStore? records = null,
        LocalContractHistory? history = null)
    {
        lock (_sync) {
            SubscribeContractEvidence();
            _contractHistory = history;
            _contractTracker = new(store, records: records, history: history); _contractSampleAt = null; _contractEvents.Clear();
        }
    }
    private void ContractHeartbeat()
    {
        var now = _time.GetUtcNow();
        // This is a reader heartbeat, never a Game.log silence timeout. Game restarts and
        // quiet logs are permitted while the Host's existing 500 ms sampler keeps running.
        if (_contractSampleAt is { } before && (now < before || now - before > TimeSpan.FromSeconds(10)))
            BreakContractReading();
        _contractSampleAt = now;
    }
    private void BreakContractReading()
    {
        try { _contractTracker?.Break(_owner.Context); }
        catch (Exception error) { IdentityGateJournal.Changed("gamelog-contract", $"code=break exception={IdentityGateJournal.Type(error)}"); }
        finally { _contractEvents.Clear(); }
    }
    private void AddContractEvidence(FleetEvent e, bool live)
    {
        if (_contractTracker is null && _missionRecords is null || _settings?.Channel != "LIVE") return;
        if (_contractReadFaulted)
        {
            if (_owner.Context is { } faultOwner && e.Contract is { } uncertain)
                _contractUncertain.Add((faultOwner, uncertain.MissionId));
            return;
        }
        if (_contractEvents.Count >= 8192)
        {
            if (_owner.Context is { } overflowOwner && e.Contract is { } overflow)
                _contractUncertain.Add((overflowOwner, overflow.MissionId));
            ContractReadFault(new InvalidDataException(), "");
            return;
        }
        _contractEvents.Add((e, live && !(e.Contract is { } data && _owner.Context is { } owner &&
            _contractUncertain.Contains((owner, data.MissionId)))));
    }
    private void CompleteContractSource(string? handle, bool complete, bool ownershipCovered)
        => ContractStep(() => PersistContractSource(handle, complete, ownershipCovered, continuationOnly: true));

    private void PersistContractSource(string? handle, bool complete, bool ownershipCovered, bool continuationOnly)
    {
        var owner = _owner;
        var expected = _verifiedHandle();
        var readToken = _contractReadToken;
        bool Current() => !readToken.IsCancellationRequested && !_disposed && AccountSlotCurrent() &&
            _owner == owner && string.Equals(expected, _verifiedHandle(), StringComparison.OrdinalIgnoreCase);
        if (!complete || handle is null || expected is null || !expected.Equals(handle, StringComparison.OrdinalIgnoreCase) ||
            !Current() || _settings?.Channel != "LIVE" || _error is not null || owner.Context is null)
        { BreakContractReading(); return; }
        try
        {
            ObserveMissionRecords(owner.Context, Current);
            var queued = _contractTracker?.Observe(owner.Context, FirstEntryObservation.HashHandle(expected),
                _contractEvents, Current, ownershipCovered, continuationOnly, _contractHistoryRevision) == true;
            _contractEvents.Clear();
            if (queued && Current()) ContractQueued?.Invoke();
        }
        catch (Exception error) { ContractReadFault(error, ""); }
    }
    private void CompleteContractRead(CancellationToken token, string? expected)
    {
        if (_contractTracker is null && _missionRecords is null) { _contractEvents.Clear(); return; }
        // A fully consumed SystemQuit is a normal session end, not an observation gap.
        // The identity is only used to finish this private batch; presence stays offline.
        if (_observation.State == "waiting" && _reader.CleanlyEndedContractHandle is { } endedHandle)
        { PersistContractSource(endedHandle, true, _reader.ContractOwnershipCovered, continuationOnly: false); return; }
        if (token.IsCancellationRequested || !AccountSlotCurrent() || _reader.IdentityInvalidated ||
            _error is not null || expected is null || _settings?.Channel != "LIVE" ||
            _observation.State is not ("identified" or "reading" or "notRunning"))
        { BreakContractReading(); return; }
        if (_observation.State == "reading") return; // Bounded identity catch-up has not finished.
        var owner = _owner;
        if (owner.Context is null || _contractEvents.Count == 0 && _contractTracker?.NeedsFlush(owner.Context) != true) return;
        bool Current() => !token.IsCancellationRequested && !_disposed && AccountSlotCurrent() &&
            _owner == owner && string.Equals(expected, _verifiedHandle(), StringComparison.OrdinalIgnoreCase);
        if (_observation.State != "identified" || !expected.Equals(_observation.Handle, StringComparison.OrdinalIgnoreCase))
        { if (_observation.State != "notRunning") BreakContractReading(); _contractEvents.Clear(); return; }
        var hash = FirstEntryObservation.HashHandle(expected);
        // SessionTracker admitted only events from a connected server and its local player.
        // Persist even a no-event heartbeat after a gap to invalidate active complete-run claims.
        try
        {
            ObserveMissionRecords(owner.Context, Current);
            var queued = _contractTracker?.Observe(owner.Context, hash, _contractEvents, Current, _reader.ContractOwnershipCovered, historyRevision: _contractHistoryRevision) == true;
            _contractEvents.Clear();
            if (queued && Current()) ContractQueued?.Invoke();
        }
        catch (Exception error) { ContractReadFault(error, ""); }
    }
}
