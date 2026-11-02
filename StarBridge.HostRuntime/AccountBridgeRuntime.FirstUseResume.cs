using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Onboarding;

namespace StarBridge.HostRuntime;

public sealed partial class AccountBridgeRuntime
{
    internal bool RequiresFirstUseGameIdentityReauthorization(FirstUseOnlineCandidateIntent intent) =>
        _host is ScmAccountBridgeHost scm && scm.FirstUseGameIdentityReauthorizationRequired &&
        !_requestRetirement.IsClosed && IsFirstUseOnlineCandidateFor(intent);

    internal async Task<string> ResumeFirstUseCandidateAsync(FirstUseOnlineCandidateIntent intent, CancellationToken token)
        => await FirstUseSessionOperationAsync(intent, token, false).ConfigureAwait(false);

    internal Task<string> ReauthorizeFirstUseCandidateAsync(FirstUseOnlineCandidateIntent intent, CancellationToken token)
        => FirstUseSessionOperationAsync(intent, token, true);

    private async Task<string> FirstUseSessionOperationAsync(FirstUseOnlineCandidateIntent intent, CancellationToken token, bool reauthorize)
    {
        if (!intent.RetainSession || !IsFirstUseOnlineCandidateFor(intent) ||
            _host is not ScmAccountBridgeHost scm) return "contextChanged";
        using var work = _requestRetirement.Enter(token);
        if (work is null) return "contextChanged";
        try
        {
            bool Current() => work.IsCurrent && IsFirstUseOnlineCandidateFor(intent);
            var result = reauthorize
                ? await scm.ReauthorizeFirstUseSessionAsync(Current, work.Token).ConfigureAwait(false)
                : await scm.ResumeFirstUseSessionAsync(Current, work.Token).ConfigureAwait(false);
            return Current() ? result.State : "contextChanged";
        }
        catch (OperationCanceledException) when (!work.IsCurrent) { return "contextChanged"; }
    }
}
