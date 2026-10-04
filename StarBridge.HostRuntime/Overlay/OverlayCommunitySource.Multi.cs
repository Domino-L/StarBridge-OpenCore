using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Overlay;

internal sealed partial class OverlayCommunitySource
{
    // One session per resource, never per module. Sessions reuse the existing
    // roster/communication lifetimes and chat baseline, but own no timers or feeds.
    private sealed class ModuleSession(string code, OverlayCommunitySource source)
    {
        internal readonly string Code = code;
        internal readonly OverlayCommunitySource Source = source;
        internal DateTimeOffset NextRead;
        internal bool Communication;
    }
    private readonly Dictionary<string, ModuleSession> _moduleSessions = new(StringComparer.Ordinal);
    private readonly SemaphoreSlim _moduleReadGate = new(1, 1);
    private Func<bool>? _moduleMode;
    private Func<object?>? _moduleChangeDemand;
    private long _moduleInvalidation;
    private TimeSpan _moduleRefreshDelay = TimeSpan.FromSeconds(15);
    internal void SetModuleMode(Func<bool> current, Func<object?>? changeDemand = null)
    { _moduleMode = current; _moduleChangeDemand = changeDemand; }
    private bool UsesModuleSources() => _moduleMode?.Invoke() == true;

    internal TimeSpan ModuleRefreshDelay
    {
        get
        {
            lock (_sync) return _moduleRefreshDelay;
        }
    }

    internal async Task RefreshModuleSourcesAsync(BridgeAccountContext owner, long generation,
        IReadOnlyList<string> requested, CancellationToken token, IReadOnlyList<string>? communicationCodes = null)
    {
        await _moduleReadGate.WaitAsync(token).ConfigureAwait(false);
        var scope = (Owner: (BridgeAccountContext?)owner, Generation: generation);
        try
        {
            lock (_sync) { CheckScope(); if (_disposed || _scope != scope) return; }
            using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token, _stop.Token);
            deadline.CancelAfter(TimeSpan.FromSeconds(20));
            var targets = await CatalogAsync(scope, false, deadline.Token).ConfigureAwait(false);
            var codes = targets.Select(t => t.Code).ToHashSet(StringComparer.Ordinal);
            ModuleSession[] reads;
            lock (_sync)
            {
                if (_disposed || _owner() != scope || deadline.IsCancellationRequested) return;
                foreach (var code in _moduleSessions.Keys.Where(code => !requested.Contains(code) || !codes.Contains(code)).ToArray())
                    RemoveModuleSession(code);
                foreach (var code in requested.Distinct(StringComparer.Ordinal).Where(codes.Contains))
                {
                    if (_moduleSessions.ContainsKey(code)) continue;
                    (BridgeAccountContext? Owner, long Generation) PinnedOwner() => _owner() == scope ? scope : (null, generation);
                    var source = new OverlayCommunitySource(PinnedOwner, new ModuleReader(this, owner, generation, code), false, _now);
                    source.Select(code);
                    source.ContentChanged += NotifyContentChanged;
                    if (_workspaceRosters.TryGetValue(code, out var roster))
                        source.ObserveWorkspace(owner, generation, roster.Sequence, roster.AcceptedAt, roster.Content);
                    if (_content?.Code == code && _now() < _validUntil)
                    {
                        source._content = _content;
                        source._validUntil = _validUntil;
                        source._communicationValidUntil = _communicationValidUntil;
                        source._chatNeedsBaseline = _chatNeedsBaseline;
                        source._latestRosterReadStartedAt = _latestRosterReadStartedAt;
                    }
                    if (_moduleAuthorities.TryGetValue(code, out var authority) && _now() < authority.ValidUntil)
                        source._moduleAuthorities[code] = authority;
                    _moduleSessions.Add(code, new(code, source));
                }
                foreach (var session in _moduleSessions.Values)
                {
                    var communication = communicationCodes is null || communicationCodes.Contains(session.Code);
                    if (communication && !session.Communication) session.NextRead = default;
                    session.Communication = communication;
                }
                reads = _moduleSessions.Values.Where(s => s.NextRead <= _now()).ToArray();
            }
            // A slow organization's communication must not withhold another
            // organization's roster. Candidates include fallback discovery;
            // display admission still enforces the shared eight-source budget.
            // Every admitted source needs an independent slot: several slow
            // peers must not consume a healthy source's remaining lease in a queue.
            using var readSlots = new SemaphoreSlim(StarBridge.Core.Overlay.OverlayModuleSourceResolver.MaximumSources,
                StarBridge.Core.Overlay.OverlayModuleSourceResolver.MaximumSources);
            async Task ReadSessionAsync(ModuleSession session)
            {
                await readSlots.WaitAsync(token).ConfigureAwait(false);
                try
                {
                var rejected = session.Source._authorityRejectionVersion;
                var invalidation = Volatile.Read(ref _moduleInvalidation);
                try
                {
                    // The directory's deadline must not cancel every resource.
                    // Each existing session owns its own bounded read/timeout.
                    await session.Source.RefreshAsync(token, includeCommunication: session.Communication).ConfigureAwait(false);
                }
                catch (OperationCanceledException) when (!token.IsCancellationRequested && session.Source._disposed) { }
                lock (_sync)
                {
                    if (_disposed || _scope != scope || _owner() != scope) return;
                    if (session.Source._authorityRejectionVersion != rejected)
                    {
                        RejectPendingWorkspace(session.Code);
                        RevokeWorkspace(session.Code);
                        if (_content?.Code == session.Code) _content = null;
                        _catalogAt = default;
                    }
                    else session.NextRead = _now() + (invalidation != _moduleInvalidation && session.Source._transientFailures == 0
                        ? TimeSpan.FromSeconds(1) : session.Source.NextRefreshDelay());
                }
                }
                finally { readSlots.Release(); }
            }
            var pending = reads.ToDictionary(session => session, ReadSessionAsync);
            // A communication deadline belongs to its source, not the whole
            // batch. Keep the existing single scheduler alive so healthy siblings
            // can renew while a slow source is still in flight. No per-module
            // timers, duplicate reads, or artificial lease extensions.
            while (pending.Values.Any(task => !task.IsCompleted))
            {
                await Task.WhenAny(pending.Values.Where(task => !task.IsCompleted)
                    .Append(Task.Delay(250, token))).ConfigureAwait(false);
                if (token.IsCancellationRequested) break;
                ModuleSession[] due;
                lock (_sync)
                {
                    if (_disposed || _owner() != scope) break;
                    due = _moduleSessions.Values.Where(session => session.NextRead <= _now() &&
                        (!pending.TryGetValue(session, out var task) || task.IsCompletedSuccessfully)).ToArray();
                }
                foreach (var session in due) pending[session] = ReadSessionAsync(session);
            }
            await Task.WhenAll(pending.Values).ConfigureAwait(false);
            lock (_sync)
                _moduleRefreshDelay = TimeSpan.FromSeconds(_moduleSessions.Count == 0 ? 15 :
                    Math.Clamp((_moduleSessions.Values.Min(s => s.NextRead) - _now()).TotalSeconds, 1, 15));
        }
        catch (OperationCanceledException) { throw; }
        catch (Exception error) when (IsTransientReadFailure(error)) { throw; }
        catch
        {
            lock (_sync)
            {
                if (!_disposed && _owner() == scope)
                {
                    InvalidateRead();
                    RejectPendingWorkspace();
                    RevokeWorkspace();
                    _content = null;
                    _catalogAt = default;
                }
            }
            throw;
        }
        finally { _moduleReadGate.Release(); }
    }

    private void InvalidateModuleSources((BridgeAccountContext? Owner, long Generation) scope)
    {
        lock (_sync)
        {
            CheckScope();
            if (_disposed || _scope != scope || !UsesModuleSources()) return;
            Interlocked.Increment(ref _moduleInvalidation);
            _catalogAt = default;
            // Notifications are hints, never authority or a reason to reset
            // transport backoff. The one scheduler coalesces bursts of hints.
            foreach (var session in _moduleSessions.Values)
                if (session.Source._transientFailures == 0) session.NextRead = default;
            _moduleRefreshDelay = TimeSpan.FromSeconds(1);
        }
    }

    private void RemoveModuleSession(string code)
    {
        if (!_moduleSessions.Remove(code, out var session)) return;
        session.Source.ContentChanged -= NotifyContentChanged;
        session.Source.Dispose();
        NotifyContentChanged();
    }

    private sealed class ModuleReader(OverlayCommunitySource parent, BridgeAccountContext expectedOwner, long generation, string code) : IOverlayCommunityReader
    {
        private void RequireCurrent(BridgeAccountContext owner, OverlayCommunityTarget? target = null)
        {
            if (parent._disposed || owner != expectedOwner || parent._owner() != (expectedOwner, generation) ||
                target is not null && target.Code != code) throw new OperationCanceledException();
        }
        public Task<IReadOnlyList<OverlayCommunityTarget>> ReadTargetsAsync(BridgeAccountContext owner, CancellationToken token)
        {
            token.ThrowIfCancellationRequested();
            lock (parent._sync)
            {
                RequireCurrent(owner);
                return Task.FromResult<IReadOnlyList<OverlayCommunityTarget>>(parent._catalog.Where(t => t.Code == code).ToArray());
            }
        }
        public Task<InformationOverlayCommunityContent> ReadContentAsync(BridgeAccountContext owner, OverlayCommunityTarget target, CancellationToken token)
        { RequireCurrent(owner, target); return parent._reader.ReadContentAsync(owner, target, token); }
        public Task<InformationOverlayCommunityContent> ReadContentAsync(BridgeAccountContext owner, OverlayCommunityTarget target,
            Action<InformationOverlayCommunityContent> rosterReady, CancellationToken token)
        { RequireCurrent(owner, target); return parent._reader.ReadContentAsync(owner, target, rosterReady, token); }
        public Task<InformationOverlayCommunityContent> ReadRosterAsync(BridgeAccountContext owner, OverlayCommunityTarget target, CancellationToken token)
        { RequireCurrent(owner, target); return parent._reader.ReadRosterAsync(owner, target, token); }
    }
}
