using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime.Auth;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class LegacyPasswordLoginClient
{
    internal async Task<object> ProfileBackgroundAsync(LegacyMigrationCredential credential,
        JsonElement payload, bool save, CancellationToken token)
    {
        string[] fields = save ? ["schemaVersion", "expectedRevision", "wallpaperId"] : ["schemaVersion"];
        if (payload.ValueKind != JsonValueKind.Object || payload.EnumerateObject().Count() != fields.Length ||
            payload.EnumerateObject().Select(p => p.Name).Distinct(StringComparer.Ordinal).Count() != fields.Length ||
            payload.EnumerateObject().Any(p => !fields.Contains(p.Name)) ||
            !payload.TryGetProperty("schemaVersion", out var schema) || schema.ValueKind != JsonValueKind.Number ||
            !schema.TryGetInt32(out var version) || version != 1) throw new AccountBridgeHostException("profile.background_invalid");
        string? requested = null;
        if (save && (!payload.TryGetProperty("expectedRevision", out var revision) || revision.ValueKind != JsonValueKind.Number ||
            !revision.TryGetInt64(out var expected) || expected < 0 || expected == long.MaxValue ||
            !payload.TryGetProperty("wallpaperId", out var wallpaper) || wallpaper.ValueKind != JsonValueKind.String ||
            !ValidWallpaper(requested = wallpaper.GetString()))) throw new AccountBridgeHostException("profile.background_invalid");
        using var request = new HttpRequestMessage(save ? HttpMethod.Put : HttpMethod.Get, new Uri(_baseUri, "api/profile/me/background"));
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", credential.AuthToken);
        if (save) request.Content = JsonContent.Create(payload);
        using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token);
        if (response.StatusCode == HttpStatusCode.Conflict) throw new AccountBridgeHostException("profile.background_conflict");
        if (!response.IsSuccessStatusCode) throw new AccountBridgeHostException("profile.background_unavailable");
        try
        {
            using var json = await LegacyPasswordRecoveryClient.ReadBoundedJsonAsync(response.Content, token, 4096);
            var root = json.RootElement;
            if (root.GetProperty("schemaVersion").GetInt32() != 1 || !root.GetProperty("revision").TryGetInt64(out var savedRevision) || savedRevision < 0 ||
                !ValidWallpaper(root.GetProperty("wallpaperId").GetString()) || save && root.GetProperty("wallpaperId").GetString() != requested)
                throw new AccountBridgeHostException("profile.background_unavailable");
            // Never forward unexpected remote fields to the UI.
            return new { schemaVersion = 1, revision = savedRevision, wallpaperId = root.GetProperty("wallpaperId").GetString() };
        }
        catch (Exception error) when (error is JsonException or KeyNotFoundException or InvalidOperationException or FormatException)
        { throw new AccountBridgeHostException("profile.background_unavailable"); }
    }

    private static bool ValidWallpaper(string? value) => value is { Length: > 0 and <= 100 } &&
        value.All(c => char.IsAsciiLetterOrDigit(c) || c == '-');
}

internal sealed partial class ScmAccountBridgeHost
{
    public async Task<object> ProfileBackgroundAsync(StarBridge.NativeBridge.BridgeAccountContext context,
        JsonElement payload, bool save, CancellationToken token)
    {
        // An explicit compatibility owner, never a fallback after Java failure.
        var session = RequireRelaySession(context);
        if (session.Legacy is null || _legacyPasswordLogin is null)
            throw new AccountBridgeHostException("profile.background_unavailable");
        var result = await SendRelayRequestAsync<object>(session,
            (active, ct) => _legacyPasswordLogin.ProfileBackgroundAsync(active.Legacy!, payload, save, ct), token);
        RequireSameRelaySession(session, RequireRelaySession(context));
        return result.Result;
    }
}
