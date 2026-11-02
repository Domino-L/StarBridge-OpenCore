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

    internal static bool ValidWallpaper(string? value) => value is { Length: > 0 and <= 100 } &&
        value.All(c => char.IsAsciiLetterOrDigit(c) || c == '-');
}

internal sealed partial class ScmAccountBridgeHost
{
    public async Task<object> ProfileBackgroundAsync(StarBridge.NativeBridge.BridgeAccountContext context,
        JsonElement payload, bool save, CancellationToken token)
    {
        if (_session is not null && save)
            return await SaveScmProfileBackgroundAsync(context, payload, token);
        if (_session is not null && !save)
        {
            if (payload.ValueKind != JsonValueKind.Object || payload.EnumerateObject().Count() != 1 ||
                !payload.TryGetProperty("schemaVersion", out var schema) || schema.ValueKind != JsonValueKind.Number ||
                !schema.TryGetInt32(out var version) || version != 1)
                throw new AccountBridgeHostException("profile.background_invalid");
            var owner = RequireSession(context);
            var profile = await GetPersonalProfileAsync(context, token);
            RequireSameSession(owner, RequireSession(context));
            if (profile.SchemaVersion != StarBridge.Core.Profiles.PersonalProfileContractPolicy.CurrentSchemaVersion || profile.Revision < 0 ||
                !LegacyPasswordLoginClient.ValidWallpaper(profile.WallpaperId))
                throw new AccountBridgeHostException("profile.background_unavailable");
            return new { schemaVersion = 1, revision = profile.Revision, wallpaperId = profile.WallpaperId };
        }
        // An explicit compatibility owner, never a fallback after Java failure.
        var session = RequireRelaySession(context);
        if (session.Legacy is null || _legacyPasswordLogin is null)
            throw new AccountBridgeHostException("profile.background_unavailable");
        var result = await SendRelayRequestAsync<object>(session,
            (active, ct) => _legacyPasswordLogin.ProfileBackgroundAsync(active.Legacy!, payload, save, ct), token);
        RequireSameRelaySession(session, RequireRelaySession(context));
        return result.Result;
    }

    private async Task<object> SaveScmProfileBackgroundAsync(StarBridge.NativeBridge.BridgeAccountContext context,
        JsonElement payload, CancellationToken token)
    {
        if (payload.ValueKind != JsonValueKind.Object || payload.EnumerateObject().Count() != 3 ||
            !payload.TryGetProperty("schemaVersion", out var schema) || schema.ValueKind != JsonValueKind.Number || !schema.TryGetInt32(out var version) || version != 1 ||
            !payload.TryGetProperty("expectedRevision", out var revision) || revision.ValueKind != JsonValueKind.Number || !revision.TryGetInt64(out var expected) ||
            expected < 0 || expected == long.MaxValue ||
            !payload.TryGetProperty("wallpaperId", out var wallpaper) || wallpaper.ValueKind != JsonValueKind.String ||
            wallpaper.GetString() is not { Length: > 0 and <= 80 } requested ||
            !requested.All(c => c is >= 'a' and <= 'z' or >= '0' and <= '9' or '-') || requested[0] == '-')
            throw new AccountBridgeHostException("profile.background_invalid");
        var generation = Generation;
        await _mutationGate.WaitAsync(token);
        try
        {
            var owner = RequireSession(context);
            if (generation != Generation) throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
            var grant = await _profileAuthorization.AuthorizeProfileWriteAsync(owner, token);
            RequireSameSession(owner, grant);
            RequireSameSession(owner, RequireSession(context));
            token.ThrowIfCancellationRequested();
            if (generation != Generation) throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
            var saved = await _oauth.UpdatePersonalProfileBackgroundAsync(grant, expected, requested, token);
            RequireSameSession(owner, RequireSession(context));
            if (generation != Generation) throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
            return new { schemaVersion = 1, revision = saved.Revision, wallpaperId = saved.WallpaperId };
        }
        catch (ScmApiForbiddenException) { throw new AccountBridgeHostException(AccountBridgeStableErrors.PersonalProfileWriteForbidden); }
        catch (ScmApiAuthenticationException) { throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired); }
        catch (OAuthAuthorizationDeniedException) { throw new OperationCanceledException("Background authorization was cancelled."); }
        catch (TimeoutException) { throw new AccountBridgeHostException(AccountBridgeStableErrors.LoginTimeout, retryable: true); }
        catch (HttpRequestException error) when (error.StatusCode == HttpStatusCode.Conflict)
        { throw new AccountBridgeHostException("profile.background_conflict"); }
        catch (Exception error) when (error is HttpRequestException or IOException or InvalidOperationException)
        { throw new AccountBridgeHostException("profile.background_unavailable"); }
        finally { if (!_disposed) _mutationGate.Release(); }
    }
}
