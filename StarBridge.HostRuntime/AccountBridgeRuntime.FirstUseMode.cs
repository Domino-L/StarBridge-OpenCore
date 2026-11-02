using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Onboarding;
using StarBridge.HostRuntime.Overlay;

namespace StarBridge.HostRuntime;

public sealed partial class AccountBridgeRuntime
{
    internal FirstUseModeRuntime? FirstUseMode { get; private set; }
    private Lifecycle.DeviceNetworkAdmission? _ordinaryDeviceNetwork;
    public Lifecycle.DeviceNetworkAdmission DeviceNetwork => FirstUseMode?.DeviceNetwork ?? _ordinaryDeviceNetwork ?? Lifecycle.DeviceNetworkAdmission.Unavailable;
    internal LocalGameLogRuntime? FirstUseGame { get; private set; }
    internal LocalGameplayTimeRuntime? FirstUseStatistics { get; private set; }
    public IBridgeRequestDispatcher? GuideStateDispatcher { get; private set; }
    public IBridgeRequestDispatcher? FirstUseStatisticsDispatcher { get; private set; }
    public IBridgeRequestDispatcher? FirstUseOnlineReviewDispatcher { get; private set; }
    private LocalOverlaySourceRuntime? _firstUseOverlay;
    private string? _firstUseRoot;
    private Func<Presence.GameProcessSession>? _firstUseLocalProbe;
    private readonly object _firstUseSourcesStopGate = new();
    private Task? _firstUseSourcesStop;
    private readonly SemaphoreSlim _firstUseSourcesWriter = new(1, 1);
    internal bool HasCurrentFirstUseLocalSources(long generation)
    {
        lock (_firstUseSourcesStopGate)
            return !_disposed && _firstUseSourcesStop is null && _gameLog is not null &&
                FirstUseGame is not null && FirstUseStatistics is not null && _firstUseOverlay is not null &&
                FirstUseMode?.AllowsLocalSourceReconstruction(generation) == true;
    }
    internal LocalDeviceSetupReviewRuntime? FirstUseDeviceReview { get; private set; }
    internal FirstUseCompletionRuntime? FirstUseCompletion { get; private set; }
    private FirstUseBridgeDispatcher? _firstUseDispatcher;
    public IBridgeRequestDispatcher? FirstUseDeviceReviewDispatcher { get; private set; }
    public IInformationOverlayLocalSource? FirstUseOverlaySource { get; private set; }

    internal void BlockFirstUseAccountRequests() => _ = _requestRetirement.Close();

    internal bool IsDeviceOnlyFirstUseStopped => !_disposed && _requestRetirement.IsClosed &&
        _backgroundConfiguration.IsClosed && _localBusinessRetired && _host is EnvironmentLockedAccountBridgeHost;

    internal bool IsLocalAccountStopped(long generation) => !_disposed && _requestRetirement.IsClosed &&
        _localBusinessRetired && Generation == generation && _host is ScmAccountBridgeHost scm &&
        scm.IsKnownSignedOutForLocalMode &&
        _localAccountStop is { RequestsDrained: true, PublicationStopped: true, SessionLoopsStopped: true,
            BusinessBackgroundStopped: true } progress && progress.SignedOutGeneration == generation &&
        LocalAccountStopCurrent(progress, scm);

    private void InitializeFirstUseMode(string root, bool deviceOnly,
        Func<FirstUseOnlineCandidateIntent, CancellationToken, Task<AccountBridgeRuntime>>? candidateFactory = null,
        TimeProvider? modeTime = null, Func<Presence.GameProcessSession>? localGameProbe = null)
    {
        if (FirstUseMode is not null) throw new InvalidOperationException("First-use mode is already owned.");
        InitializeOfflineAccount(root);
        var identities = new LocalFirstUseStore(root);
        var mode = new FirstUseModeRuntime(new(root), identities, this, deviceOnly, candidateFactory, modeTime);
        mode.Initialize();
        FirstUseMode = mode;
        GuideStateDispatcher = new GuideStateBridgeDispatcher(root, mode.CaptureGuideScope, () => _disposed ? -1 : mode.ControlGeneration);
        mode.ColdCompletionHistory = new(root);
        FirstUseOnlineReviewDispatcher = new FirstUseOnlineReviewBridgeDispatcher(mode, () => _disposed ? -1 : mode.ControlGeneration);
        _firstUseRoot = root;
        _firstUseLocalProbe = localGameProbe;
        if (_gameLog is null) return;
        FirstUseGame = new(identities, mode.LocalMode, _firstUseLocalProbe);
        FirstUseStatistics = new(identities, new(root), FirstUseGame, mode.LocalMode);
        FirstUseStatisticsDispatcher = new LocalStatisticsChoiceBridgeDispatcher(() => FirstUseStatistics, () => _disposed ? -1 : mode.ControlGeneration,
            new InstalledSetupStatisticsChoice(root, mode));
        FirstUseGame.AttachStatistics(FirstUseStatistics);
        _firstUseOverlay = new(identities, FirstUseGame, mode.LocalMode);
        FirstUseOverlaySource = new LocalOverlaySourceBinding(() => _disposed ? null : _firstUseOverlay);
        _gameLog.AttachLocalSlot(FirstUseGame);
    }

    public void ConfigureFirstUseDeviceSetup(Settings.ApplicationPreferencesBridgeDispatcher application,
        OverlayBridgeDispatcher overlay, Notifications.NotificationSettingsBridgeDispatcher notifications,
        Reminders.ContinuousPlayReminderRuntime reminder)
    {
        if (_disposed || _firstUseRoot is null || FirstUseDeviceReview is not null)
            throw new InvalidOperationException("First-use device choices are unavailable or already owned.");
        FirstUseDeviceReview = new(new(new(_firstUseRoot), () => _disposed ? -1 : FirstUseMode?.ControlGeneration ?? Generation,
            application, overlay, notifications, reminder), new(_firstUseRoot));
        FirstUseDeviceReviewDispatcher = new LocalDeviceReviewBridgeDispatcher(FirstUseDeviceReview, () => _disposed ? -1 : FirstUseMode?.ControlGeneration ?? Generation);
        if (FirstUseMode is not null) FirstUseCompletion = new(_firstUseRoot, FirstUseMode, FirstUseDeviceReview);
    }

    // Used by the real default factory before resolving endpoints or constructing
    // OAuth/vault owners. Missing intent preserves existing-user startup; corrupt
    // or unfinished intent never silently restores the previous authorization.
    internal static async Task<AccountBridgeRuntime> CreateWithFirstUseModeAsync(string root,
        Func<CancellationToken, Task<AccountBridgeRuntime>> createOnline, CancellationToken token = default,
        Func<FirstUseOnlineCandidateIntent, CancellationToken, Task<AccountBridgeRuntime>>? candidateFactory = null,
        TimeProvider? modeTime = null, Support.LocalGameEventJournal? eventJournal = null,
        Func<Presence.GameProcessSession>? localGameProbe = null, bool enableFirstUseModes = true)
    {
        token.ThrowIfCancellationRequested();
        // Official releases use the pre-experiment account lifecycle. Do not
        // read, repair, delete or rewrite experimental intent, including corrupt
        // or interrupted state. This admits normal authentication work; it does
        // not declare a session online or weaken the original identity checks.
        if (!enableFirstUseModes)
        {
            var ordinary = await createOnline(token).ConfigureAwait(false);
            try
            {
                token.ThrowIfCancellationRequested();
                ordinary._ordinaryDeviceNetwork = new(() => !ordinary._disposed);
                return ordinary;
            }
            catch { ordinary.Dispose(); throw; }
        }
        var store = new FirstUseModeStore(root);
        FirstUseModeChoice? startup;
        try { startup = store.Read(); }
        catch (LocalFirstUseException) { startup = null; }
        var blocked = startup is null || startup.BlocksAutomaticAccountStartup;
        AccountBridgeRuntime runtime;
        if (blocked)
        {
            runtime = new(new EnvironmentLockedAccountBridgeHost("device-local"),
                gameLog: new Presence.GameLogSettingsStore(root), eventJournal: eventJournal);
            // No account owners were installed. The sole log timer remains for
            // the confirmed independent local slot, never an account slot.
            runtime._localBusinessRetired = true;
            await runtime._backgroundConfiguration.Close().ConfigureAwait(false);
            await runtime._requestRetirement.Close().ConfigureAwait(false);
            await runtime._gameLog!.RetireAccountAsync().ConfigureAwait(false);
        }
        else runtime = await createOnline(token).ConfigureAwait(false);
        try
        {
            token.ThrowIfCancellationRequested();
            // Configuration resolution may have awaited IO. A changed choice
            // cannot authorize the newly created online owner's first restore.
            if (!blocked && store.Read() != startup)
                throw new LocalFirstUseException("firstUse.context_changed");
            // Default construction has no restored session. Attach from the
            // original startup decision before exposing any account dispatch.
            if (!blocked && startup?.Phase == "online")
                runtime.RequireColdFirstUseGameIdentity(() => runtime.FirstUseMode?.HasInstalledOnlineForCompletion == true);
            runtime.InitializeFirstUseMode(root, deviceOnly: blocked, candidateFactory, modeTime, localGameProbe);
            return runtime;
        }
        catch { runtime.Dispose(); throw; }
    }

    // Candidate construction is explicit and separate from bootstrap. A candidate
    // is auth-only, not a mode receipt or an installed business graph. Product
    // lifecycle still needs an actual owner handoff before activating online
    // consumers; it cannot attach this staged dispatcher as the live runtime
    // or reopen the old runtime's sealed admission/background owners.
    internal Task<AccountBridgeRuntime> ConstructFirstUseOnlineCandidateAsync(FirstUseOnlineCandidateIntent intent,
        CancellationToken token)
    {
        if (_disposed || _firstUseRoot is null || !intent.IsCurrent)
            throw new LocalFirstUseException("firstUse.context_changed");
        return CreateOnlineDefaultAsync(_firstUseRoot, requireFreshSignIn: !intent.RetainSession, detectedGameIdentity: null,
            cancellationToken: token, eventJournal: _eventJournal, candidateIntent: intent);
    }

    internal bool IsFirstUseOnlineCandidateFor(FirstUseOnlineCandidateIntent intent) => !_disposed &&
        _firstUseCandidate && _candidateIntent == intent && intent.IsCurrent &&
        _host is ScmAccountBridgeHost scm && (intent.RetainSession ? scm.IsRetainedFirstUseCandidate : scm.IsFreshFirstUseCandidate);

    internal bool RetainsFirstUseSession => _firstUseCandidate && _candidateIntent?.RetainSession == true;

    private async Task<bool> RetireFirstUseCandidateCoreAsync(bool preserveSession)
    {
        if (_disposed || !_firstUseCandidate || _host is not ScmAccountBridgeHost { IsFirstUseAuthenticationCandidate: true } scm ||
            RetainsFirstUseSession && !preserveSession)
            return false;
        var requests = Task.WhenAll(_requestRetirement.Close(), _firstUseBusinessPreparation.Close(),
            _firstUseInstallation?.SealAndDrainAsync() ?? Task.CompletedTask);
        await scm.CancelLoginAsync().ConfigureAwait(false);
        await requests.ConfigureAwait(false); // Actual lease exit, not cancellation requested.
        // Configuration can be assigning Native owners while cancellation is
        // requested. Only its real exit permits taking and retiring that graph.
        try { await RetireBusinessBackgroundForLocalMode().ConfigureAwait(false); }
        catch (Exception original)
        {
            // Failed background exit still owns its original server publication.
            // Attempt withdrawal before draining publishers, even when activation
            // or a sibling's physical disposal failed. Never acknowledge sign-out
            // or delete credentials on this faulted path.
            var failures = new List<Exception> { original };
            try
            {
                var generation = Generation;
                if (!await StopPrivacyPublicationAsync().ConfigureAwait(false) || Generation != generation)
                    failures.Add(new InvalidOperationException("Original candidate withdrawal was not confirmed."));
            }
            catch (Exception withdrawal) { failures.Add(withdrawal); }
            try
            {
                await Task.WhenAll(Begin(() => _gameLog?.RetireAsync() ?? Task.CompletedTask),
                    Begin(RetirePublicationOwnersAsync), Begin(scm.RetireFirstUseBusinessAdmissionAsync)).ConfigureAwait(false);
            }
            catch (Exception cleanup) { failures.Add(cleanup); }
            if (failures.Count > 1) throw new AggregateException(failures);
            throw;
        }
        // Even a partially activated install withdraws before business/session
        // drain and credential clear. An auth-only candidate has nothing to send.
        var withdrawalGeneration = Generation;
        bool withdrawn;
        try { withdrawn = await StopPrivacyPublicationAsync().ConfigureAwait(false) && Generation == withdrawalGeneration; }
        catch (Exception withdrawal)
        {
            // A withdrawal fault never authorizes sign-out, but a discarded
            // candidate still owns no continuing sampler, publisher or SCM loop.
            // Preserve the original fault and wait every physical sibling exit.
            try { await DrainFirstUseCandidateBusinessAsync(scm).ConfigureAwait(false); }
            catch (Exception cleanup) { throw new AggregateException(withdrawal, cleanup); }
            throw;
        }
        // Initiate every sibling exit even if one publisher's physical disposal
        // faults. A discarded candidate owns no continuing device sampler or SCM
        // loop; all original work must exit before credentials can be cleared.
        await DrainFirstUseCandidateBusinessAsync(scm).ConfigureAwait(false);
        if (!withdrawn || Generation != withdrawalGeneration) return false;
        if (preserveSession)
        {
            // Normal application shutdown is not sign-out. Every original
            // callback, publisher, sampler and SCM loop has physically exited;
            // disposal does not revoke OAuth or delete its refresh credential.
            // This branch never creates a local recovery/sign-out receipt.
            Dispose();
            return true;
        }
        if (!await scm.RetireFreshFirstUseSessionAsync().ConfigureAwait(false)) return false;
        // Consume this unique cleanup's confirmed withdrawal and physical exit,
        // not a second Stop against already-retired publishers. Fresh-session
        // cleanup has just established the authoritative signed-out generation.
        if (scm.CurrentContext is not null || !scm.IsKnownSignedOutForLocalMode ||
            _publicationExit?.IsCompletedSuccessfully != true ||
            _localBackgroundRetirement?.IsCompletedSuccessfully != true) return false;
        _localAccountStop = new(null, Generation)
        {
            RequestsDrained = true, BusinessBackgroundStopped = true,
            PublicationWithdrawalConfirmed = true, PublicationStopped = true
        };
        var stopped = await StopAccountForLocalModeAsync(Generation).ConfigureAwait(false);
        if (stopped.State != "sessionStopped" || !IsLocalAccountStopped(stopped.Generation)) return false;
        await RetireStoppedFirstUseBusinessGraphAsync().ConfigureAwait(false);
        // Disposal is after every original auth/background admission has exited.
        Dispose();
        return true;
    }

    private Task DrainFirstUseCandidateBusinessAsync(ScmAccountBridgeHost scm) =>
        Task.WhenAll(Begin(RetirePublicationOwnersAsync),
            Begin(() => _gameLog?.RetireAsync() ?? Task.CompletedTask),
            Begin(scm.RetireFirstUseBusinessAdmissionAsync));

    private void CloseFirstUseMode()
    {
        FirstUseMode?.Close();
        _ = _firstUseDispatcher?.RetireAsync();
        _ = FirstUseDeviceReview?.RetireAsync();
        _ = FirstUseCompletion?.RetireAsync();
        _ = RetireFirstUseLocalSourcesAsync();
    }

    internal Task RetireFirstUseControlsAsync() => Task.WhenAll(
        DeviceNetwork.RetireAsync(),
        _firstUseDispatcher?.RetireAsync() ?? Task.CompletedTask,
        FirstUseCompletion?.RetireAsync() ?? Task.CompletedTask,
        FirstUseDeviceReview?.RetireAsync() ?? Task.CompletedTask);

    internal FirstUseBridgeDispatcher CreateFirstUseDispatcher(NativeAccountRuntimeBinding native, FirstUseStartupReader startup,
        IFirstUseLogPicker picker, NativeBusinessComposition composition, Func<string> locale)
    {
        if (_disposed || _firstUseRoot is null || _firstUseDispatcher is not null || FirstUseCompletion is null)
            throw new InvalidOperationException("First-use product owner unavailable or already attached.");
        return _firstUseDispatcher = new(_firstUseRoot, this, native, startup, picker, composition.Configure, locale);
    }

    // One physical exit for the old device consumers and their sole sampler.
    // This does not close the mode/device review owner, write online intent,
    // authorize a replacement, or reopen retired readers on failed installation.
    // A caller may cancel its observation with WaitAsync, never this actual exit.
    internal Task RetireFirstUseLocalSourcesAsync()
    {
        TaskCompletionSource completion;
        lock (_firstUseSourcesStopGate)
        {
            if (_firstUseSourcesStop is not null) return _firstUseSourcesStop;
            completion = new(TaskCreationOptions.RunContinuationsAsynchronously);
            _firstUseSourcesStop = completion.Task;
        }
        _ = ExitLocalSourcesAsync(completion);
        return completion.Task;
    }

    internal bool OwnsSuccessfulFirstUseSourcesExit(Task exit)
    {
        lock (_firstUseSourcesStopGate)
            return !_disposed && ReferenceEquals(exit, _firstUseSourcesStop) && exit.IsCompletedSuccessfully;
    }

    private async Task ExitLocalSourcesAsync(TaskCompletionSource completion)
    {
        await _firstUseSourcesWriter.WaitAsync().ConfigureAwait(false);
        Exception? failure = null;
        try
        {
            await StopLocalSourcesAsync(_firstUseOverlay, FirstUseStatistics, FirstUseGame, _gameLog).ConfigureAwait(false);
        }
        catch (Exception error) { failure = error; }
        finally { _firstUseSourcesWriter.Release(); }
        if (failure is null) completion.TrySetResult();
        else completion.TrySetException(failure);
    }

    private static Task StopLocalSourcesAsync(LocalOverlaySourceRuntime? overlay, LocalGameplayTimeRuntime? statistics,
        LocalGameLogRuntime? game, Presence.GameLogRuntime? sampler)
    {
        // Stop every admission even if an earlier owner fails synchronously.
        // Do not hold the reservation lock across cancellation callbacks.
        static Task Stop(Func<Task> retire)
        { try { return retire(); } catch (Exception error) { return Task.FromException(error); } }
        var exits = new[] {
            Stop(() => overlay?.RetireAsync() ?? Task.CompletedTask),
            Stop(() => statistics?.RetireAsync() ?? Task.CompletedTask),
            Stop(() => game?.RetireAsync() ?? Task.CompletedTask),
            Stop(() => sampler?.RetireAsync() ?? Task.CompletedTask),
        };
        return Task.WhenAll(exits);
    }

    // Internal recovery only. A completed task from another batch is not a
    // receipt; restoring readers is neither a mode write nor online installation.
    internal async Task<bool> RestoreFirstUseLocalSourcesAsync(Task exited, long modeGeneration)
    {
        if (!await _firstUseSourcesWriter.WaitAsync(0).ConfigureAwait(false)) return false;
        LocalGameLogRuntime? game = null;
        LocalGameplayTimeRuntime? statistics = null;
        LocalOverlaySourceRuntime? overlay = null;
        Presence.GameLogRuntime? sampler = null;
        bool installed = false, started = false;
        bool ModeCurrent() => !_disposed && FirstUseMode?.AllowsLocalSourceReconstruction(modeGeneration) == true;
        bool ReceiptCurrent()
        {
            lock (_firstUseSourcesStopGate)
                return ReferenceEquals(exited, _firstUseSourcesStop) && exited.IsCompletedSuccessfully && ModeCurrent();
        }
        try
        {
            if (_firstUseRoot is null || _newDormantGameLog is null || !ReceiptCurrent()) return false;
            var identities = new LocalFirstUseStore(_firstUseRoot);
            var mode = FirstUseMode!;
            game = new(identities, mode.LocalMode, _firstUseLocalProbe);
            statistics = new(identities, new(_firstUseRoot), game, mode.LocalMode);
            game.AttachStatistics(statistics);
            overlay = new(identities, game, mode.LocalMode);
            sampler = _newDormantGameLog();
            sampler.AttachLocalSlot(game);
            await sampler.RetireAccountAsync().ConfigureAwait(false);
            lock (_firstUseSourcesStopGate)
            {
                if (!ReceiptCurrent()) return false;
                if (_gameLog is not null) _gameLog.CityArrival -= ObserveCityArrival;
                if (_gameLog is not null) _gameLog.PublicationChanged -= WakeGamePublication;
                _gameLog = sampler;
                // Recovery is local-only, so it does not subscribe account publication.
                FirstUseGame = game;
                FirstUseStatistics = statistics;
                _firstUseOverlay = overlay;
                _firstUseSourcesStop = null;
                installed = true;
            }
            if (!ModeCurrent() || !sampler.StartDeferredSampling()) return false;
            lock (_firstUseSourcesStopGate)
                started = _firstUseSourcesStop is null && ModeCurrent();
            return started;
        }
        catch { return false; }
        finally
        {
            try
            {
                if (!started && (game is not null || sampler is not null))
                {
                    TaskCompletionSource? failureExit = null;
                    lock (_firstUseSourcesStopGate)
                    {
                        if (installed && _firstUseSourcesStop is null)
                        {
                            failureExit = new(TaskCreationOptions.RunContinuationsAsynchronously);
                            _firstUseSourcesStop = failureExit.Task;
                        }
                    }
                    try
                    {
                        await StopLocalSourcesAsync(overlay, statistics, game, sampler).ConfigureAwait(false);
                        failureExit?.TrySetResult();
                    }
                    catch (Exception error) { failureExit?.TrySetException(error); throw; }
                }
            }
            finally { _firstUseSourcesWriter.Release(); }
        }
    }
}
