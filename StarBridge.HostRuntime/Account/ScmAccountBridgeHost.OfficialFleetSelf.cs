using StarBridge.HostRuntime.OfficialFleet;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    private readonly object _fleetViewerGate = new();
    private (long Generation, string Subject, string BusinessSubjectId)? _fleetViewer;

    // Marks only the viewer's own Java-verified visible row, so the shared board opens
    // the viewer's own page instead of a visitor read. Names never prove self. Any
    // identity-read failure leaves every row as an ordinary member.
    private async Task<long?> FindOfficialFleetSelfAsync(BridgeAccountContext owner, long generation,
        IReadOnlyDictionary<long, OfficialFleetMemberIdentity> identities, CancellationToken token)
    {
        if (!identities.Values.Any(row => row.State == "visible")) return null;
        try
        {
            RequireFleetReadOwner(owner, generation);
            var session = RequireSession(owner);
            string? viewer = null;
            lock (_fleetViewerGate)
                if (_fleetViewer is { } known && known.Generation == generation && known.Subject == session.Subject)
                    viewer = known.BusinessSubjectId;
            if (viewer is null)
            {
                using var budget = CancellationTokenSource.CreateLinkedTokenSource(token);
                budget.CancelAfter(TimeSpan.FromSeconds(5));
                var identity = await _oauth.LoadBusinessIdentityAsync(session, budget.Token);
                RequireFleetReadOwner(owner, generation);
                RequireSameSession(session, identity.ActiveSession);
                _session = identity.ActiveSession;
                viewer = identity.BusinessSubjectId;
                lock (_fleetViewerGate) _fleetViewer = (generation, session.Subject, viewer);
            }
            var self = identities.Values.Where(row => row.State == "visible" && row.BusinessSubjectId == viewer).ToArray();
            return self.Length == 1 ? self[0].MemberId : null;
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested) { throw; }
        catch (AccountBridgeHostException) { throw; }
        catch (Exception error) when (error is HttpRequestException or IOException or InvalidOperationException or
            System.Text.Json.JsonException or OperationCanceledException or TimeoutException)
        { return null; }
    }
}
