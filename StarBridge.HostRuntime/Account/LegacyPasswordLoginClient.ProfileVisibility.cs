using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime.Auth;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class LegacyPasswordLoginClient
{
    internal async Task<object> ProfileVisibilityAsync(LegacyMigrationCredential credential,
        JsonElement payload, bool save, CancellationToken token)
    {
        string[] fields = save ? ["schemaVersion", "expectedRevision", "visibility"] : ["schemaVersion"];
        if (payload.ValueKind != JsonValueKind.Object || payload.EnumerateObject().Count() != fields.Length ||
            payload.EnumerateObject().Select(p => p.Name).Distinct().Count() != fields.Length ||
            payload.EnumerateObject().Any(p => !fields.Contains(p.Name)) ||
            !payload.TryGetProperty("schemaVersion", out var schema) || !schema.TryGetInt32(out var version) || version != 1)
            throw new AccountBridgeHostException("profile.visibility_invalid");
        string? requested = null;
        if (save && (!payload.TryGetProperty("expectedRevision", out var revision) || !revision.TryGetInt64(out var expected) || expected < 0 ||
            !payload.TryGetProperty("visibility", out var visibility) || visibility.ValueKind != JsonValueKind.String ||
            !ValidVisibility(requested = visibility.GetString()))) throw new AccountBridgeHostException("profile.visibility_invalid");
        using var request = new HttpRequestMessage(save ? HttpMethod.Put : HttpMethod.Get, new Uri(_baseUri, "api/profile/me/visibility"));
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", credential.AuthToken);
        if (save) request.Content = JsonContent.Create(payload);
        using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token);
        if (response.StatusCode == HttpStatusCode.Conflict) throw new AccountBridgeHostException("profile.visibility_conflict");
        if (!response.IsSuccessStatusCode) throw new AccountBridgeHostException("profile.visibility_unavailable");
        using var body = await LegacyPasswordRecoveryClient.ReadBoundedJsonAsync(response.Content, token, 4096);
        var root = body.RootElement;
        if (root.GetProperty("schemaVersion").GetInt32() != 1 || !root.GetProperty("revision").TryGetInt64(out var savedRevision) || savedRevision < 0 ||
            !ValidVisibility(root.GetProperty("visibility").GetString()) || save && root.GetProperty("visibility").GetString() != requested)
            throw new AccountBridgeHostException("profile.visibility_unavailable");
        return root.Clone();
    }
    private static bool ValidVisibility(string? value) => value is "public" or "friendsFleetAndOrganizations" or "friendsOnly" or "private";
}

internal sealed partial class ScmAccountBridgeHost
{
    public async Task<object> ProfileVisibilityAsync(StarBridge.NativeBridge.BridgeAccountContext context,
        JsonElement payload, bool save, CancellationToken token)
    {
        // This is the still-live S2 profile owner, never a Java-failure fallback.
        var session = RequireRelaySession(context);
        if (session.Legacy is null || _legacyPasswordLogin is null)
            throw new AccountBridgeHostException("profile.visibility_unavailable");
        var result = await SendRelayRequestAsync<object>(session,
            (active, ct) => _legacyPasswordLogin.ProfileVisibilityAsync(active.Legacy!, payload, save, ct), token);
        RequireSameRelaySession(session, RequireRelaySession(context));
        return result.Result;
    }
}
