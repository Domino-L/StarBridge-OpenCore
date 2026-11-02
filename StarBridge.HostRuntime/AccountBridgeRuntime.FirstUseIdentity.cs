using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Onboarding;

namespace StarBridge.HostRuntime;

public sealed partial class AccountBridgeRuntime
{
    internal string FirstUseSignInState(FirstUseOnlineCandidateIntent intent) =>
        !_requestRetirement.IsClosed && IsFirstUseOnlineCandidateFor(intent) && _host is ScmAccountBridgeHost scm
            ? scm.FirstUseSignInState : "contextChanged";

    internal bool IsFirstUseIdentityCurrent(FirstUseOnlineCandidateIntent intent, FirstUseScmIdentityFacts facts) =>
        !_requestRetirement.IsClosed && IsFirstUseOnlineCandidateFor(intent) &&
        _host is ScmAccountBridgeHost scm && scm.IsFirstUseIdentityCurrent(facts);

    // This is a Native identity-review read, not a fifth general dispatcher
    // command. It shares the candidate's real admission/exit lease and original
    // mutation lane, so mode cancellation waits for its actual transport exit.
    internal async Task<FirstUseScmIdentityRead> ReadFirstUseIdentityAsync(FirstUseOnlineCandidateIntent intent,
        CancellationToken token)
    {
        if (!IsFirstUseOnlineCandidateFor(intent) || _host is not ScmAccountBridgeHost scm) return new("contextChanged");
        using var work = _requestRetirement.Enter(token);
        if (work is null) return new("contextChanged");
        try
        {
            var result = await scm.ReadFirstUseIdentityAsync(work.Token).ConfigureAwait(false);
            if (!work.IsCurrent || !IsFirstUseOnlineCandidateFor(intent) ||
                result.Facts is { } facts && !IsFirstUseIdentityCurrent(intent, facts)) return new("contextChanged");
            return result;
        }
        catch (OperationCanceledException) when (!work.IsCurrent) { return new("contextChanged"); }
        catch (Auth.ScmApiAuthenticationException) { return new("reauthorizationRequired"); }
        catch (AccountBridgeHostException) { return new("reauthorizationRequired"); }
        catch (Exception error) when (error is System.Net.Http.HttpRequestException or System.IO.IOException or
            System.Text.Json.JsonException or InvalidOperationException or OperationCanceledException)
        { return new("unavailable"); }
    }
}
