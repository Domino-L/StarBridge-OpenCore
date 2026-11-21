using StarBridge.NativeBridge;
using StarBridge.HostRuntime.Presence;

namespace StarBridge.HostRuntime.Onboarding;

public sealed partial class FirstUseBridgeDispatcher
{
    private async Task Execute(string action, Dictionary<string, object?> checkpoint, View view, CancellationToken token, int? candidateIndex = null)
    {
        var step = checkpoint["step"] as string;
        switch (action)
        {
            case "applyMode":
                if (checkpoint["mode"] is not string choice ||
                    step != "mode" && !(step == "log" && choice == "local"))
                    throw new LocalFirstUseException("firstUse.invalid_request");
                // The guide cannot stage an online choice before the local
                // source is confirmed. Returning and completed users retain the settings
                // workflow (login, log setup, review, installation).
                if (choice == "online" && _completed.Read() is null && !_mode.ReturningAtStartup &&
                    !_mode.HasLocalIdentityForOnlineSelection)
                    throw new LocalFirstUseException("firstUse.evidence_required");
                if (choice == "online" && _mode.HasInstalledOnlineAccount)
                {
                    SaveProgress(checkpoint, view, token);
                    break;
                }
                if (_mode.Current.State == "signInRequired" && choice == "local")
                {
                    var cancelled = _mode.HasColdOnlinePending
                        ? await _mode.RecoverColdOnlineAsync(_mode.Current.Revision, Op(), token).ConfigureAwait(false)
                        : await _mode.CancelOnlineAsync(_mode.Current.Revision, Op(), token).ConfigureAwait(false);
                    if (cancelled.State is not ("local" or "offline"))
                        throw new LocalFirstUseException("firstUse.recovery_required");
                }
                await EnsureLocal(token).ConfigureAwait(false);
                if (choice == "online")
                {
                    var current = _mode.Current;
                    if (current.State == "offline") _mode.RequestResume(current.Revision, Op());
                    else _mode.RequestOnline(current.Revision, Op());
                }
                var local = _local.Read();
                _local.SaveProgress(local.Revision, Op(), new(step!, choice, local.SelectedSourceKey,
                    checkpoint["evidenceKey"] as string, null), () => !_closed && !token.IsCancellationRequested && _mode.LocalMode().Active);
                break;
            case "prepareLog":
                // Opening the log step needs local mode for discovery and selection.
                // Only a device with no signed-in account at all is prepared here;
                // a signed-in, restoring or pending account is never switched.
                if (step != "log" || checkpoint["mode"] as string != "local")
                    throw new LocalFirstUseException("firstUse.invalid_request");
                if (_mode.LocalMode().Active || _mode.Current.State != "online" ||
                    _mode.HasInstalledOnlineAccount || _mode.HasAuthenticatedOnlineCandidate) break;
                var signedOut = await _native.DispatchAsync(BridgeEnvelope.Request("account.getCurrent", Op(), _native.Generation,
                    new { schemaVersion = 1 }), token).ConfigureAwait(false);
                if (signedOut.Response.Status != "ok" || signedOut.Response.Payload.GetProperty("state").GetString() != "signedOut") break;
                token.ThrowIfCancellationRequested();
                if (_closed || _mode.ControlGeneration != view.Generation || _mode.Current != view.Mode)
                    throw new LocalFirstUseException("firstUse.context_changed");
                await _mode.ApplyLocalAsync(_mode.Current.Revision, Op(), _root.Generation, token).ConfigureAwait(false);
                if (!_mode.LocalMode().Active) throw new LocalFirstUseException("firstUse.mode_receipt_required");
                var prepared = _local.Read();
                _local.SaveProgress(prepared.Revision, Op(), new("log", "local", prepared.SelectedSourceKey,
                    checkpoint["evidenceKey"] as string, null), () => !_closed && !token.IsCancellationRequested && _mode.LocalMode().Active);
                break;
            case "login":
                if (step != "mode" || checkpoint["mode"] as string != "online") throw new LocalFirstUseException("firstUse.invalid_request");
                if (_mode.RetainsOnlineReviewSession) await _mode.ResumeOnlineCandidateAsync(_mode.Current.Revision, token).ConfigureAwait(false);
                else if (!await _mode.AuthenticateOnlineCandidateAsync(_mode.Current.Revision, token).ConfigureAwait(false))
                    throw new LocalFirstUseException("firstUse.sign_in_not_confirmed");
                break;
            case "cancelLogin":
                await _mode.CancelOnlineAsync(_mode.Current.Revision, Op(), token).ConfigureAwait(false);
                break;
            case "skipLog":
                if (step != "log" || checkpoint["mode"] as string != "local" ||
                    _mode.Current.State is not ("local" or "offline") || !_mode.LocalMode().Active || _mode.HasAuthenticatedOnlineCandidate)
                    throw new LocalFirstUseException("firstUse.mode_receipt_required");
                _local.DeferLog(view.Local.Revision, Op(), () => !_closed && !token.IsCancellationRequested &&
                    _mode.ControlGeneration == view.Generation && _mode.Current.State is "local" or "offline" && _mode.LocalMode().Active);
                break;
            case "selectLog":
                if (step != "log" || !_mode.AllowsLocalIdentitySetup) throw new LocalFirstUseException("firstUse.context_changed");
                var path = candidateIndex is { } index
                    ? _mode.LocalMode().Active && _logCandidateGeneration == view.Generation && _logCandidates is { } candidates && index < candidates.Count
                        ? candidates[index].Path : throw new LocalFirstUseException("firstUse.context_changed")
                    : await _picker.PickAsync(_locale(), token).ConfigureAwait(false);
                token.ThrowIfCancellationRequested();
                if (_closed || _mode.ControlGeneration != view.Generation || _local.Read().Revision != view.Local.Revision)
                    throw new LocalFirstUseException("firstUse.context_changed");
                if (path is not null)
                {
                    var version = GameLogLocator.ChannelOf(path) ?? throw new LocalFirstUseException("firstUse.source_invalid");
                    _evidence.Select(view.Local.Revision, path, version);
                    _logCandidates = null;
                    _logSearchBlocked = -1;
                }
                break;
            case "locateLogs":
                // Disk state is checked once before and once after the scan. In
                // between only in-memory lifecycle, generation and mode fences run.
                if (step != "log" || !_mode.LocalMode().Active) throw new LocalFirstUseException("firstUse.context_changed");
                var fence = _mode.CaptureLocalModeFence();
                void Current()
                {
                    if (_closed || _mode.ControlGeneration != view.Generation || _mode.Current != view.Mode ||
                        !_mode.LocalMode().Active || _local.Read().Revision != view.Local.Revision)
                        throw new LocalFirstUseException("firstUse.context_changed");
                }
                void Live()
                {
                    if (_closed || _mode.ControlGeneration != view.Generation || !fence())
                        throw new LocalFirstUseException("firstUse.context_changed");
                }
                Current();
                // Metadata only. Evidence for the selected log is read by the
                // explicit identity actions, never by discovery.
                var (found, blocked) = await FindLogCandidatesAsync(view.Local.Sources
                    .OrderByDescending(s => s.SourceKey == view.Local.SelectedSourceKey).Select(s => s.LogPath).ToArray(), Live, token).ConfigureAwait(false);
                token.ThrowIfCancellationRequested();
                Current();
                // Blocked is not "nothing found": the page says the search did
                // not finish, and a refused retry keeps the earlier candidates.
                _logSearchBlocked = blocked ? view.Generation : -1;
                if (found is null) break;
                _logCandidates = found;
                _logCandidateGeneration = view.Generation;
                break;
            case "refresh":
                if (_local.Read().SelectedSourceKey is string selected) _evidence.Refresh(selected, token);
                break;
            case "confirmHandle":
                if (step != "identity" || checkpoint["sourceKey"] is not string source || checkpoint["evidenceKey"] is not string evidence)
                    throw new LocalFirstUseException("firstUse.evidence_required");
                // A cold projection of a persisted association is not an issued
                // live evidence key. Refresh the same source before confirming.
                var currentEvidence = _evidence.Current;
                if (currentEvidence.EvidenceKey != evidence)
                {
                    currentEvidence = _evidence.Refresh(source, token);
                    if (!currentEvidence.IdentityConfirmed) throw new LocalFirstUseException("firstUse.evidence_required");
                }
                _evidence.Confirm(source, currentEvidence.EvidenceKey!);
                FinishLogSetup(_local.Read(), view, token);
                break;
            case "finishLogSetup":
                if (step != "identity" || checkpoint["mode"] as string !=
                    (view.Facts["onlineSetupPending"] is true ? "online" : view.Facts["activeMode"] as string) ||
                    checkpoint["sourceKey"] is not string retrySource || retrySource != view.Local.SelectedSourceKey ||
                    view.Facts["localIdentityConfirmed"] is not true)
                    throw new LocalFirstUseException("firstUse.context_changed");
                FinishLogSetup(view.Local, view, token);
                break;
            case "reviewLocalSettings":
                if (step != "local" || (await _completion.ReadAsync(token).ConfigureAwait(false)).State is not ("ready" or "completed"))
                    throw new LocalFirstUseException("firstUse.device_review_required");
                break;
            case "reviewOnlineChoices":
                if (step == "online" && checkpoint["mode"] as string == "online" && _mode.HasInstalledOnlineForCompletion &&
                    (await _completion.ReadAsync(token).ConfigureAwait(false)).State is "ready" or "completed") break;
                if (step != "online" || checkpoint["mode"] as string != "online" ||
                    (await _completion.ReadAsync(token).ConfigureAwait(false)).State is not ("ready" or "completed") ||
                    !_mode.HasConfirmedOnlineIdentity(_mode.Current.Revision))
                    throw new LocalFirstUseException("firstUse.completion_required");
                await _native.InstallConfirmedOnlineAsync(_mode.Current.Revision, _configure, token).ConfigureAwait(false);
                if (!_mode.HasInstalledOnlineForCompletion) throw new LocalFirstUseException("firstUse.installation_failed");
                break;
            default: throw new LocalFirstUseException("firstUse.invalid_request");
        }
    }

    private void FinishLogSetup(LocalFirstUseSnapshot snapshot, View view, CancellationToken token)
    {
        var source = snapshot.Sources.SingleOrDefault(s => s.SourceKey == snapshot.SelectedSourceKey);
        var mode = view.Mode;
        var revision = snapshot.Revision;
        bool Current() => !_closed && !token.IsCancellationRequested && _mode.AllowsLocalIdentitySetup &&
            _mode.ControlGeneration == view.Generation && _mode.Current == mode &&
            _local.Read() is var now && now.Revision == revision && now.SelectedSourceKey == source?.SourceKey &&
            now.ActiveProfileId == snapshot.ActiveProfileId && now.Sources.SingleOrDefault(s => s.SourceKey == source?.SourceKey) == source;
        if (source is null || source.NeedsFreshGameEvidence || source.ConfirmedProfileId is null ||
            source.ConfirmedProfileId != snapshot.ActiveProfileId || !Current())
            throw new LocalFirstUseException("firstUse.context_changed");
        // Recheck current game identity, including after a cold page reopen.
        // A changed Handle invalidates the association; it cannot inherit consent.
        var evidence = _evidence.Refresh(source.SourceKey, token);
        if (!evidence.IdentityConfirmed || evidence.RequiresFreshEvidence || !Current())
            throw new LocalFirstUseException("firstUse.context_changed");
        if (snapshot.DeferredStatisticsAllowed is not null)
        {
            var statistics = _root.FirstUseStatistics ?? throw new LocalFirstUseException("firstUse.unavailable");
            statistics.ApplyDeferredConsent(Current, token);
            revision++;
        }
        if (!Current()) throw new LocalFirstUseException("firstUse.context_changed");
        if (source.ListeningEnabled != true || snapshot.LogSetupPending)
            _local.SetListening(revision, Op(), source.SourceKey, true, Current);
    }

    // One scan at a time, including one that outlived its wait: a later request
    // never starts a second scan while an earlier one is still blocked on disk.
    // Blocked means the search did not finish; null candidates mean no new scan
    // ran at all, so the caller keeps what it already showed.
    private Task? _logSearchWorker;
    private long _logSearchBlocked = -1;
    private async Task<(IReadOnlyList<LocalGameLogCandidate>? Found, bool Blocked)> FindLogCandidatesAsync(string[] previous, Action live, CancellationToken token)
    {
        if (_logSearchWorker is { IsCompleted: false }) return (null, true);
        var collected = new List<LocalGameLogCandidate>();
        var stop = CancellationTokenSource.CreateLinkedTokenSource(token);
        var search = Task.Run(() => _logSearch.Find(previous, live, stop.Token, collected), stop.Token);
        _logSearchWorker = search;
        try
        {
            var found = await search.WaitAsync(_logSearch.HardStop, token).ConfigureAwait(false);
            stop.Dispose();
            // The scan's own budget can end it before the hard stop; that is
            // just as unfinished, with the candidates it fully checked.
            return (found.Candidates, !found.Complete);
        }
        catch (TimeoutException)
        {
            // A blocking disk call outlived the budget. Stop waiting, keep only
            // fully checked candidates and let the read-only scan end unseen.
            stop.Cancel();
            _ = search.ContinueWith(t => { _ = t.Exception; stop.Dispose(); }, TaskScheduler.Default);
            lock (collected) return ([.. collected], true);
        }
    }

    private async Task EnsureLocal(CancellationToken token)
    {
        if (_mode.LocalMode().Active) return;
        if (_mode.Current is { State: "recoveryRequired" } pending)
        {
            // This is reached only by an explicit applyMode action. Reuse the
            // original retirement/provenance checks; never reset unknown data,
            // infer an exited owner, or substitute a fresh empty mode receipt.
            var recovered = await _mode.RecoverLocalSelectionAsync(pending.Revision, Op(), _native, token).ConfigureAwait(false);
            if (recovered.State is not ("local" or "offline") || !_mode.LocalMode().Active)
                throw new LocalFirstUseException("firstUse.recovery_required");
            return;
        }
        if (_mode.Current.State != "online") throw new LocalFirstUseException("firstUse.mode_receipt_required");
        var current = await _native.DispatchAsync(BridgeEnvelope.Request("account.getCurrent", Op(), _native.Generation,
            new { schemaVersion = 1 }), token).ConfigureAwait(false);
        if (current.Response.Status != "ok") throw new LocalFirstUseException("firstUse.mode_receipt_required");
        var state = current.Response.Payload.GetProperty("state").GetString();
        if (state == "signedIn")
            await _mode.ApplyManualOfflineAsync(_mode.Current.Revision, Op(), _native, token).ConfigureAwait(false);
        else if (state == "signedOut")
            await _mode.ApplyLocalAsync(_mode.Current.Revision, Op(), _root.Generation, token).ConfigureAwait(false);
        else throw new LocalFirstUseException("firstUse.mode_receipt_required");
        if (!_mode.LocalMode().Active) throw new LocalFirstUseException("firstUse.mode_receipt_required");
    }
    private static string Op() => Guid.NewGuid().ToString("N");
}
