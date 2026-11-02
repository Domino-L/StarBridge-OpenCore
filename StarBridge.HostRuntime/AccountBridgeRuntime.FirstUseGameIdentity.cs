using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Onboarding;

namespace StarBridge.HostRuntime;

public sealed partial class AccountBridgeRuntime
{
    internal async Task<object> FirstUseGameIdentityAsync(FirstUseOnlineCandidateIntent intent,
        string command, JsonElement payload, Func<bool> current, CancellationToken token)
    {
        using var work = _requestRetirement.Enter(token);
        bool Current() => work is { IsCurrent: true } && current() && IsFirstUseOnlineCandidateFor(intent);
        if (!Current() || _host is not ScmAccountBridgeHost scm)
            throw new LocalFirstUseException("firstUse.context_changed");
        try
        {
            var response = await scm.FirstUseGameIdentityAsync(command, payload, Current, work!.Token).ConfigureAwait(false);
            if (!Current()) throw new LocalFirstUseException("firstUse.context_changed");
            return response;
        }
        catch (OperationCanceledException) when (!Current() && !token.IsCancellationRequested)
        { throw new LocalFirstUseException("firstUse.context_changed"); }
    }
}
