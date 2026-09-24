using System.Text.Json;

namespace StarBridge.HostRuntime.Communities;

internal sealed partial class CommunityClient
{
    // Confirm the mutation from the authoritative narrow membership/application
    // endpoints. Re-downloading public discovery (including every logo) adds no
    // evidence about whether this account joined the target.
    private async Task<bool> ReadWpfS2AdmissionOutcome(
        string bearer, string code, string action, CancellationToken token)
    {
        if (action is "join" or "apply")
        {
            var membership = await WorkspaceJson(bearer, "/api/fleets/membership", token);
            if (WpfS2MembershipCodes(membership).Contains(code)) return true;
            if (action == "join") return false;
        }
        var applications = await WorkspaceJson(bearer, "/api/fleets/applications/mine", token);
        if (applications.ValueKind != JsonValueKind.Array || applications.GetArrayLength() > 10000) throw Invalid();
        var pending = applications.EnumerateArray().Any(row =>
            Text(row, "fleetCode", 256).Trim().Equals(code, StringComparison.OrdinalIgnoreCase));
        return action == "apply" ? pending : action == "withdraw" && !pending;
    }
}
