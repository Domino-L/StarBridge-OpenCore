using System.Text.Json;
using StarBridge.HostRuntime.Notifications;

namespace StarBridge.HostRuntime.Communities;

internal sealed partial class CommunityClient
{
    private async Task ObserveWpfS2Players(string bearer, JsonElement[] fleets,
        Action<PlayerActivitySourceSnapshot>? observed, CancellationToken token, string viewerId)
    {
        if (observed is null) return;
        try
        {
            var players = fleets.Length == 0 ? JsonSerializer.SerializeToElement(Array.Empty<object>()) :
                await WorkspaceJson(bearer, "/api/players", token, 8 * 1024 * 1024);
            token.ThrowIfCancellationRequested();
            observed(PlayerActivitySources.Organization(fleets, players, viewerId));
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested) { throw; }
        catch { /* No observation on a failed, missing or malformed optional source. */ }
    }
}
