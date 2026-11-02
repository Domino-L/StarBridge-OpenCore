namespace StarBridge.HostRuntime.Onboarding;

internal sealed partial class FirstUseModeRuntime
{
    // Native-only provenance for recovery before an installation object exists.
    // It cannot authorize login, business activation, a mode write or completion.
    internal sealed class InstallationOrigin
    {
        private readonly FirstUseModeRuntime _mode;
        private readonly FirstUseOnlineOrigin _origin;
        private readonly Task<AccountBridgeRuntime> _started;
        private readonly long _epoch;
        private InstallationOrigin(FirstUseModeRuntime mode, FirstUseOnlineOrigin origin,
            Task<AccountBridgeRuntime> started, long epoch)
        { _mode = mode; _origin = origin; _started = started; _epoch = epoch; }

        internal static InstallationOrigin? Capture(FirstUseModeRuntime mode, long revision)
        {
            try
            {
                var pending = mode._accepted; var start = mode._candidateStart;
                var epoch = Interlocked.Read(ref mode._epoch); var origin = mode.ModeStore.ReadOnlineOrigin();
                if (pending is not { Phase: "onlinePending" } || pending.Revision != revision ||
                    !mode.HasConfirmedOnlineAccount(revision) || start is not { IsCompletedSuccessfully: true } ||
                    origin is not { CandidateStarted: true } || !origin.IsFor(pending) || mode.ModeStore.Read() != pending ||
                    Interlocked.Read(ref mode._epoch) != epoch || !ReferenceEquals(start, mode._candidateStart)) return null;
                return new(mode, origin, start, epoch);
            }
            catch { return null; }
        }

        internal FirstUseModeObservation? ReturnedLocal(AccountBridgeRuntime.PreparedFirstUseBusinessOwner? prepared)
        {
            try
            {
                var accepted = _mode._accepted;
                if (_mode._closed || accepted is null || accepted.Phase != _origin.Local.Phase ||
                    accepted.Revision != _origin.Pending.Revision + 1 || _mode.ModeStore.Read() != accepted ||
                    Interlocked.Read(ref _mode._epoch) != _epoch || !ReferenceEquals(_mode._candidateStart, _started) ||
                    prepared is not null && !ReferenceEquals(prepared.Owner, _started.Result)) return null;
                // Only the original mode's actual candidate exit or installed
                // recovery can prove this adopted local return. A newer intent,
                // external same-phase write or merely stopped observer cannot.
                var exited = _mode._candidateCancel is { IsCompletedSuccessfully: true, Result: true } ||
                    _mode._onlineCommit is { } commit && commit.ReturnedLocal == accepted && commit.Origin == _origin &&
                    ReferenceEquals(commit.Graph.Installation.Owner, _started.Result) && HasOriginalRecoveryExit(commit);
                var result = _mode.Current;
                return exited && result.Revision == accepted.Revision && result.State is "local" or "offline" ? result : null;
            }
            catch { return null; }
        }
    }
}
