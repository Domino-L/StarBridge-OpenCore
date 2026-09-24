using System.Text.Json;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Communities;

internal sealed partial class CommunityClient
{
    internal async Task<string> ResolveApplicantIdentityAsync(string bearer, string targetRef,
        string entryRef, string scope, string viewerId, Action current, CancellationToken token)
    {
        var epoch = Interlocked.Read(ref _inviteEpoch);
        var target = Resolve(targetRef, scope, allowWpfS2: true);
        if (target.WpfS2ViewerId != viewerId) throw new AccountBridgeHostException("profile.visitor_unavailable");
        Check();
        if (!_admissionTargets.TryGetValue(entryRef, out var entry))
            throw new AccountBridgeHostException("communities.refreshRequired");
        var result = await WorkspaceJson(bearer,
            "/api/fleets/admissions/applicant?code=" + Uri.EscapeDataString(target.Code) +
            "&applicationId=" + Uri.EscapeDataString(entry.Id), token);
        Check();
        if (Number(result, "schemaVersion", 1, 1) != 1 || Text(result, "code", 256) != target.Code ||
            Text(result, "applicationId", 128) != entry.Id) throw Invalid();
        var id = Text(result, "accountId", 128);
        if (id.Length < 8) throw Invalid();
        return id;

        void Check()
        {
            current();
            token.ThrowIfCancellationRequested();
            if (epoch != Interlocked.Read(ref _inviteEpoch) ||
                !_admissionTargets.TryGetValue(entryRef, out var row) || row.Scope != scope ||
                row.Code != target.Code || row.Kind != "applications" || row.Expires <= _targetClock.GetUtcNow())
                throw new AccountBridgeHostException("communities.refreshRequired");
        }
    }
}
