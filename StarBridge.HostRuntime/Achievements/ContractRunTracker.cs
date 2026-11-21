using StarBridge.Core.Achievements;
using StarBridge.Core.Events;
using StarBridge.NativeBridge;
using StarBridge.HostRuntime.Support;
using static StarBridge.HostRuntime.Achievements.ContractAchievementStore;

namespace StarBridge.HostRuntime.Achievements;

// A rule seam for verified template stages. Empty RequiredStages deliberately means
// first created objective + uninterrupted reading, not all 38 observed dynamic IDs.
internal sealed record ContractRequiredStage(string[] Texts, bool RequireCompleted);
internal sealed record ContractStageRule(string[] TravelTexts, ContractRequiredStage[] RequiredStages)
{
    internal static ContractStageRule? For(string? contract) => ContractAchievementPolicy.TsgContracts.Contains(contract)
        ? new(["前往 QV 采矿站", "Go to QV Mining Station"], []) : null;
    internal bool IsTravel(string? text) => text is not null && TravelTexts.Any(t =>
        text.TrimEnd(' ', ':', '：').Equals(t, StringComparison.OrdinalIgnoreCase));
}

internal sealed class ContractRunTracker(ContractAchievementStore store, Func<string?, ContractStageRule?>? rules = null,
    ContractRecordStore? records = null, LocalContractHistory? history = null)
{
    private readonly Func<string?, ContractStageRule?> _rules = rules ?? ContractStageRule.For;
    private readonly Guid _readingPeriod = Guid.NewGuid();
    private readonly HashSet<BridgeAccountContext> _broken = [];
    private bool _historyFailed;
    internal bool NeedsFlush(BridgeAccountContext owner) => _broken.Contains(owner);
    internal void Break(BridgeAccountContext? owner)
    {
        if (owner is not null) _broken.Add(owner);
    }

    internal bool Observe(BridgeAccountContext owner, string handleHash, IReadOnlyList<(FleetEvent Event, bool Live)> events,
        Func<bool> current, bool ownershipCovered = false, bool continuationOnly = false, long? historyRevision = null)
    {
        _historyFailed = false;
        try { return ObserveRuns(owner, handleHash, events, current, ownershipCovered, continuationOnly, historyRevision); }
        catch
        {
            Break(owner);
            // Display history has its own durable queue. An unavailable achievement
            // journal cannot stop it; replay is idempotent in LocalContractHistory.
            foreach (var (e, live) in events)
                if (e.Contract is { } data)
                    ObserveHistory(owner, e, new Run(data.MissionId, handleHash, _readingPeriod), current,
                        live && !(continuationOnly && e.Type == FleetEventType.ContractAccepted), historyRevision);
            throw;
        }
    }

    private bool ObserveRuns(BridgeAccountContext owner, string handleHash, IReadOnlyList<(FleetEvent Event, bool Live)> events,
        Func<bool> current, bool ownershipCovered, bool continuationOnly, long? historyRevision)
    {
        using var lease = store.Open(owner);
        var state = lease.Read(); var runs = state.Runs.ToDictionary(r => r.MissionId);
        var broken = _broken.Contains(owner); var changed = false; var queued = false;
        if (broken)
            foreach (var (id, run) in runs.ToArray())
                if (run.AcceptedAt is not null && run.Outcome is null && !run.Gap)
                { runs[id] = run with { Gap = true }; changed = true; }
        foreach (var (e, live) in events)
        {
            if (!current()) throw new OperationCanceledException();
            if (e.Timestamp is not { } at || at.Offset != TimeSpan.Zero) continue;
            if (e.Type is FleetEventType.PlayerDied or FleetEventType.PlayerRespawned)
            {
                foreach (var (id, run) in runs.ToArray())
                {
                    if (run.AcceptedAt is null || at < run.AcceptedAt || run.Outcome is not null || run.HandleHash != handleHash ||
                        (!live && run.ReadingPeriod != _readingPeriod) || at <= run.LastDeathAt) continue;
                    // Died then Respawned is one death; a parser-confirmed respawn without a preceding
                    // Died is itself death evidence. Downed/Revived never enter this branch.
                    var deaths = run.Deaths + (e.Type == FleetEventType.PlayerDied ? (run.Dead ? 0 : 1) : (run.Dead ? 0 : 1));
                    runs[id] = run with { Deaths = deaths, Dead = e.Type == FleetEventType.PlayerDied, LastDeathAt = at };
                    changed = true;
                }
                continue;
            }
            if (e.Contract is not { } data) continue;
            var exists = runs.TryGetValue(data.MissionId, out var prior);
            var runState = prior ?? new Run(data.MissionId, handleHash, _readingPeriod);
            if (runState.HandleHash != handleHash) continue;
            if (continuationOnly && prior?.AcceptedAt is null)
            {
                ObserveHistory(owner, e, runState, current, live && e.Type != FleetEventType.ContractAccepted, historyRevision);
                continue; // Achievement continuation admission remains unchanged.
            }
            // Startup replay can disprove ownership. It can never grant it.
            if (e.Type == FleetEventType.ContractShared && runState.Outcome is null)
            {
                runs[data.MissionId] = runState with { Shared = true, Owner = false };
                changed = true;
                continue;
            }
            // Historical startup acceptance only blocks a later repeated HUD acceptance. It never
            // supplies an acceptedAt, ownership, stages, or an upload. A run accepted live in this
            // Host may continue across game/process/log rotation, including its catch-up lines.
            if (!live && (runState.AcceptedAt is null || runState.ReadingPeriod != _readingPeriod))
            {
                ObserveHistory(owner, e, runState, current, false, historyRevision);
                if (!exists && e.Type is FleetEventType.ContractAccepted or FleetEventType.ContractEnded)
                { runs[data.MissionId] = runState with { Historical = true }; changed = true; }
                continue;
            }
            if (runState.Outcome is not null)
            {
                if (e.Type != FleetEventType.ContractAccepted) ObserveHistory(owner, e, runState, current, live, historyRevision);
                if (e.Type == FleetEventType.ContractEnded && data.State != runState.Outcome && !runState.Confirmed)
                { runs[data.MissionId] = runState with { Outcome = "CONFLICT", Pending = null }; changed = true; }
                continue;
            }
            if (runState.AcceptedAt is { } accepted && at < accepted) continue;
            var next = e.Type switch {
                FleetEventType.ContractShared when runState.AcceptedAt is null => runState with { Shared = true },
                FleetEventType.ContractDefined => Objective(runState with { Contract = data.Contract, DefinitionId = data.DefinitionId }, data, at),
                FleetEventType.ContractAccepted when runState.AcceptedAt is null && !runState.Historical => runState with {
                    AcceptedAt = at, Owner = ownershipCovered && !runState.Shared && runState.ReadingPeriod == _readingPeriod,
                    ReadingPeriod = _readingPeriod, Gap = false },
                FleetEventType.ContractObjective when runState.AcceptedAt is not null => Objective(runState, data, at),
                FleetEventType.ContractEnded when runState.AcceptedAt is not null => End(runState, data, at),
                _ => runState };
            // Optional diagnostics share the admitted evidence and computed stages.
            // They never contribute to eligibility, ownership, or the durable outbox.
            if (live && (e.Type != FleetEventType.ContractAccepted ||
                runState.AcceptedAt is null && next.AcceptedAt is not null))
                ObserveHistory(owner, e, next, current, true, historyRevision);
            if (next != runState)
            {
                // Presentation facts precede durable enqueue. Records are display-only: a
                // capture failure (even a persistently corrupt records file) is recorded and
                // skipped, and never interrupts achievement judgement for this batch.
                try
                {
                    if (e.Type == FleetEventType.ContractAccepted && next.AcceptedAt is not null && runState.AcceptedAt is null)
                        records?.Capture(owner, next.MissionId, data.Text, null, current);
                    if (next.Pending is { } observation)
                        records?.Capture(owner, next.MissionId, null, new(null, observation.AcceptedAt, observation.ArrivedAt,
                            observation.CompletedAt, (next.Objectives ?? []).Length, observation.Owner, observation.Deaths), current);
                }
                catch (Exception error) when (error is not OperationCanceledException)
                {
                    IdentityGateJournal.Changed("contract-records", $"code=write exception={IdentityGateJournal.Type(error)}");
                }
                runs[data.MissionId] = next; changed = true; queued |= next.Pending is not null;
            }
        }
        if (changed) lease.Save(new(runs.Values.ToArray()), current);
        if (current()) _broken.Remove(owner);
        return queued;
    }

    private void ObserveHistory(BridgeAccountContext owner, FleetEvent evidence, Run run,
        Func<bool> current, bool live, long? revision)
    {
        if (_historyFailed) return;
        Exception? authorityError = null;
        bool HistoryCurrent()
        {
            try { return current(); }
            catch (Exception error) { authorityError = error; throw; }
        }
        try { history?.Observe(owner, evidence, run, HistoryCurrent, live, revision); }
        catch (Exception error) when (!ReferenceEquals(error, authorityError))
        {
            _historyFailed = true;
            IdentityGateJournal.Changed("contract-history", $"code=observe exception={IdentityGateJournal.Type(error)}");
        }
    }
    private Run Objective(Run run, ContractLogEvidence data, DateTimeOffset at)
    {
        if (data.ObjectiveId is null) return run;
        var goals = (run.Objectives ?? []).ToDictionary(o => o.Id);
        var goal = goals.GetValueOrDefault(data.ObjectiveId) ?? new(data.ObjectiveId, at, false, false, null);
        var travel = !run.TravelClosed && _rules(run.Contract)?.IsTravel(data.Text) == true;
        var completedAt = data.State == "COMPLETED" ? goal.CompletedAt ?? at : goal.CompletedAt;
        var updated = goal with { Created = goal.Created || data.Created, Travel = goal.Travel || travel, CompletedAt = completedAt,
            Text = goal.Text ?? (data.Text is { Length: <= 160 } ? data.Text.TrimEnd(' ', ':', '：') : null) };
        var closed = run.TravelClosed || data.Created && data.Text is not null && !travel;
        if (updated == goal && goals.ContainsKey(goal.Id) && closed == run.TravelClosed) return run;
        goals[goal.Id] = updated;
        var arrived = goals.Values.Where(g => g.Travel && g.CompletedAt is not null).Select(g => g.CompletedAt).Min();
        return run with { Objectives = goals.Values.ToArray(), ArrivedAt = run.ArrivedAt ?? arrived,
            TravelClosed = closed };
    }

    private Run End(Run run, ContractLogEvidence data, DateTimeOffset at)
    {
        if (data.State is null) return run;
        var next = run with { Outcome = data.State, EndedAt = at };
        if (data.State != "COMPLETED") return next;
        var goals = run.Objectives ?? [];
        var required = _rules(run.Contract)?.RequiredStages ?? [];
        var complete = run.ReadingPeriod == _readingPeriod && !run.Gap && goals.Any(o => o.Created) &&
            required.All(stage => goals.Any(o => o.Text is not null && stage.Texts.Contains(o.Text, StringComparer.OrdinalIgnoreCase) &&
                o.Created && (!stage.RequireCompleted || o.CompletedAt is not null)));
        var observation = new ContractObservation(1, run.HandleHash, run.MissionId,
            ContractObservation.IsValidContract(run.Contract) ? run.Contract! : "unknown", run.DefinitionId,
            "completed", run.Owner, complete, run.Deaths, run.AcceptedAt!.Value, run.ArrivedAt, at);
        return observation.IsValid ? next with { Pending = observation } : next;
    }
}
