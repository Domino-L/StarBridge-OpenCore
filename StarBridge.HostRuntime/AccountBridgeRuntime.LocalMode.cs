using StarBridge.HostRuntime.Account;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime;

// Narrow lifecycle facts, deliberately not a "local mode ready" receipt. Native
// sources and other installed background owners still need their own retirement.
internal sealed record LocalAccountStopObservation(string State, long Generation,
    bool RequestsDrained = false, bool PublicationStopped = false, bool SessionLoopsStopped = false,
    bool BusinessBackgroundStopped = false);

public sealed partial class AccountBridgeRuntime
{
    private readonly SemaphoreSlim _localAccountStopGate = new(1, 1);
    private readonly Lifecycle.AsyncWorkRetirement _backgroundConfiguration = new();
    private volatile bool _localBusinessRetired;
    private Task? _localBackgroundRetirement;
    private volatile LocalAccountStopProgress? _localAccountStop;

    // Live, original-owner facts only. A retry resumes this one-way retirement;
    // it cannot adopt a newer login or replace an unknown cold-start receipt.
    // Only successful exits are retained, never cancellation or a requested stop.
    private sealed class LocalAccountStopProgress(BridgeAccountContext? context, long generation)
    {
        internal BridgeAccountContext? Context { get; } = context;
        internal long Generation { get; } = generation;
        private long _signedOutGeneration = -1;
        internal long? SignedOutGeneration
        {
            get { var value = Interlocked.Read(ref _signedOutGeneration); return value < 0 ? null : value; }
            set => Interlocked.Exchange(ref _signedOutGeneration, value ?? -1);
        }
        internal volatile bool RequestsDrained, PublicationWithdrawalConfirmed, PublicationStopped, SessionLoopsStopped, BusinessBackgroundStopped;
        internal LocalAccountStopObservation Observe(string state, long currentGeneration) => new(state, currentGeneration,
            RequestsDrained, PublicationStopped, SessionLoopsStopped, BusinessBackgroundStopped);
    }

    private bool LocalAccountStopCurrent(LocalAccountStopProgress progress, ScmAccountBridgeHost scm) => !_disposed &&
        (progress.SignedOutGeneration is { } signedOut
            ? Generation == signedOut && scm.CurrentContext is null && scm.IsKnownSignedOutForLocalMode
            : Generation == progress.Generation && scm.CurrentContext == progress.Context);

    // Retire the installed online observers and account sampling slots, not the
    // device-local settings or the single Game.log timer. Composition still owns
    // activating independent local slots after the full mode handoff.
    private Task RetireBusinessBackgroundForLocalMode()
    {
        if (_localBackgroundRetirement is not null) return _localBackgroundRetirement;
        _localBusinessRetired = true;
        return _localBackgroundRetirement = DrainBackgroundConfigurationAsync();
    }

    // Native process shutdown uses the original physical consumer drain, without
    // requesting a mode transition, logout, credential clear, or new admission.
    internal Task RetireNativeBusinessConsumersAsync() => RetireBusinessBackgroundForLocalMode();

    private async Task DrainBackgroundConfigurationAsync()
    {
        // A configure call can already be constructing a driver or registering
        // callbacks. Seal admission and await that call before taking the owner
        // set; otherwise a newly assigned owner could escape the drain receipt.
        await Task.WhenAll(_backgroundConfiguration.Close(),
            _firstUseInstallation?.SealAndDrainAsync() ?? Task.CompletedTask).ConfigureAwait(false);
        // Start every retirement even if one Native callback throws. Such a fault
        // still prevents acknowledgement, but cannot leave sibling readers alive.
        static Task Stop(Func<Task> stop)
        { try { return stop(); } catch (Exception error) { return Task.FromException(error); } }
        await Task.WhenAll(
            Stop(() => _hangarAutoSync?.RetireAsync() ?? Task.CompletedTask),
            Stop(() => _activityReceiver?.RetireAsync() ?? Task.CompletedTask),
            Stop(() => _communityNotifications?.RetireAsync() ?? Task.CompletedTask),
            Stop(RetireTradeNotificationsAsync),
            Stop(() => _achievements?.RetireAsync() ?? Task.CompletedTask),
            Stop(() => _scmAchievementUnlocks?.RetireAsync() ?? Task.CompletedTask),
            Stop(() => _playerActivity?.RetireAccountActivityAsync() ?? Task.CompletedTask),
            Stop(() => _overlayCommunities?.RetireAsync() ?? Task.CompletedTask),
            Stop(() => _gameplayTime?.RetireAsync() ?? Task.CompletedTask),
            Stop(() => {
                // Seal the candidate's complete sampler with its siblings, but
                // await that cached physical exit only AFTER publication
                // withdrawal in DrainFirstUseCandidateBusinessAsync.
                if (_firstUseCandidate) _ = _gameLog?.RetireAsync();
                return _gameLog?.RetireAccountAsync() ?? Task.CompletedTask;
            }),
            Stop(RetireLiveOverlayUpdatesAsync),
            Stop(() => { _achievementCelebration?.Dispose(); return Task.CompletedTask; })).ConfigureAwait(false);
    }

    internal async Task<LocalAccountStopObservation> StopAccountForLocalModeAsync(
        long expectedGeneration, CancellationToken cancellationToken = default,
        Action<LocalAccountStopObservation, Auth.ScmCredentialRetirementStamp, Func<bool>>? beforeCredentialClear = null)
    {
        await _localAccountStopGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            if (_disposed) return new("unavailable", Generation);
            if (expectedGeneration < 0 || expectedGeneration != Generation)
                return new("contextChanged", Generation);
            if (_host is not ScmAccountBridgeHost scm)
                return new("unsupported", Generation);
            var progress = _localAccountStop;
            if (progress is null)
            {
                var context = scm.CurrentContext;
                if (context is null && !scm.IsKnownSignedOutForLocalMode)
                    return new("sessionUnchecked", Generation);
                progress = _localAccountStop = new(context, expectedGeneration);
            }
            if (!LocalAccountStopCurrent(progress, scm)) return progress.Observe("contextChanged", Generation);

            // Close admission before waiting: later reads/login cannot queue behind
            // the transition, and cancellation-ignoring old replies are discarded.
            if (!progress.RequestsDrained)
            {
                var drained = Task.WhenAll(_requestRetirement.Close(), _firstUseBusinessPreparation.Close(),
                    _firstUseInstallation?.SealAndDrainAsync() ?? Task.CompletedTask);
                await scm.CancelLoginAsync().ConfigureAwait(false);
                await drained.WaitAsync(cancellationToken).ConfigureAwait(false);
                progress.RequestsDrained = true;
            }
            if (!LocalAccountStopCurrent(progress, scm)) return progress.Observe("contextChanged", Generation);

            if (!progress.BusinessBackgroundStopped)
            {
                await RetireBusinessBackgroundForLocalMode().WaitAsync(cancellationToken).ConfigureAwait(false);
                progress.BusinessBackgroundStopped = true;
            }
            if (!LocalAccountStopCurrent(progress, scm)) return progress.Observe("contextChanged", Generation);

            if (!progress.PublicationStopped)
            {
                if (!progress.PublicationWithdrawalConfirmed)
                {
                    if (!await StopPrivacyPublicationAsync(cancellationToken).ConfigureAwait(false))
                        return progress.Observe("publicationPending", Generation);
                    progress.PublicationWithdrawalConfirmed = true;
                }
                // Withdraw first. A cancelled observer can resume this original
                // physical drain without calling Stop on already retired owners.
                await RetirePublicationOwnersAsync().WaitAsync(cancellationToken).ConfigureAwait(false);
                progress.PublicationStopped = true;
            }
            cancellationToken.ThrowIfCancellationRequested();
            if (!LocalAccountStopCurrent(progress, scm)) return progress.Observe("contextChanged", Generation);
            // Installed SCM business reads (including support/enrollment that
            // ignore cancellation) must physically exit before credential clear.
            await scm.RetireFirstUseBusinessAdmissionAsync().WaitAsync(cancellationToken).ConfigureAwait(false);
            if (!LocalAccountStopCurrent(progress, scm)) return progress.Observe("contextChanged", Generation);
            if (progress.SignedOutGeneration is null)
            {
                if (!scm.StopSessionLoopsForLocalMode(progress.Generation))
                    return progress.Observe("contextChanged", Generation);
                if (beforeCredentialClear is not null && progress.Context is { } original)
                {
                    // This distinct checkpoint proves actual withdrawals and loop
                    // exits before credential deletion, not a completed sign-out.
                    if (!await scm.WaitForOriginalSessionLoopsAsync(original, progress.Generation, cancellationToken).ConfigureAwait(false))
                        return progress.Observe("contextChanged", Generation);
                    var credential = await scm.PrepareLocalCredentialRetirementAsync(original, progress.Generation, cancellationToken).ConfigureAwait(false);
                    if (credential is not null)
                        beforeCredentialClear(new("credentialClearPending", progress.Generation, true, true, true, true), credential,
                            () => LocalAccountStopCurrent(progress, scm) && progress.RequestsDrained && progress.PublicationStopped &&
                                progress.BusinessBackgroundStopped && scm.IsLocalCredentialRetirementCurrent(original, progress.Generation, credential));
                }
                if (progress.Context is { } context &&
                    !await scm.LogoutForLocalModeAsync(context, progress.Generation, cancellationToken).ConfigureAwait(false))
                    return progress.Observe("contextChanged", Generation);
                // The generation advanced by our actual logout is the only new
                // generation this retirement may follow. An unrelated lifecycle
                // change (even to a signed-out projection) cannot grant a retry.
                var expectedSignedOut = progress.Context is null ? progress.Generation : progress.Generation + 1;
                if (Generation != expectedSignedOut || scm.CurrentContext is not null || !scm.IsKnownSignedOutForLocalMode)
                    return progress.Observe("contextChanged", Generation);
                progress.SignedOutGeneration = expectedSignedOut;
            }
            var signedOutGeneration = progress.SignedOutGeneration.Value;
            cancellationToken.ThrowIfCancellationRequested();
            if (!await scm.WaitForSignedOutSessionLoopsAsync(signedOutGeneration, cancellationToken).ConfigureAwait(false))
                return progress.Observe("sessionPending", Generation);
            if (!LocalAccountStopCurrent(progress, scm)) return progress.Observe("contextChanged", Generation);
            progress.SessionLoopsStopped = true;
            return progress.Observe("sessionStopped", signedOutGeneration);
        }
        catch (OperationCanceledException) { throw; }
        catch { return _localAccountStop?.Observe("unavailable", Generation) ?? new("unavailable", Generation); }
        finally { _localAccountStopGate.Release(); }
    }
}
