using System.Net;
using System.Text.Json;
using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    private static object VisibilityProjection(long revision, string visibility) => new
    {
        schemaVersion = 1, revision, visibility,
        availableVisibilities = new[] { "public", "friendsAndMainFleet", "friendsOnly", "private" }
    };

    private async Task<object> ScmProfileVisibilityAsync(BridgeAccountContext context, JsonElement payload,
        bool save, CancellationToken token)
    {
        string[] fields = save ? ["schemaVersion", "expectedRevision", "visibility"] : ["schemaVersion"];
        if (payload.ValueKind != JsonValueKind.Object || payload.EnumerateObject().Count() != fields.Length ||
            payload.EnumerateObject().Select(p => p.Name).Distinct().Count() != fields.Length ||
            payload.EnumerateObject().Any(p => !fields.Contains(p.Name)) ||
            !payload.TryGetProperty("schemaVersion", out var schema) || !schema.TryGetInt32(out var version) || version != 1)
            throw new AccountBridgeHostException("profile.visibility_invalid");
        long expected = 0;
        string? requested = null;
        if (save && (!payload.TryGetProperty("expectedRevision", out var revision) || !revision.TryGetInt64(out expected) ||
            expected < 0 || expected == long.MaxValue || !payload.TryGetProperty("visibility", out var scope) ||
            scope.ValueKind != JsonValueKind.String || !OAuthPkceClient.ValidProfileVisibility(requested = scope.GetString())))
            throw new AccountBridgeHostException("profile.visibility_invalid");
        var generation = Generation;
        if (!save)
        {
            var owner = RequireSession(context);
            var profile = await GetPersonalProfileAsync(context, token);
            RequireSameSession(owner, RequireSession(context));
            if (generation != Generation) throw new BridgeStaleGenerationException(generation, Generation);
            if (profile.Revision < 0 || !OAuthPkceClient.ValidProfileVisibility(profile.Visibility))
                throw new AccountBridgeHostException("profile.visibility_unavailable");
            return VisibilityProjection(profile.Revision, profile.Visibility);
        }
        await _mutationGate.WaitAsync(token);
        try
        {
            var owner = RequireSession(context);
            if (generation != Generation) throw new BridgeStaleGenerationException(generation, Generation);
            var grant = await _profileAuthorization.AuthorizeProfileWriteAsync(owner, token);
            RequireSameSession(owner, grant);
            RequireSameSession(owner, RequireSession(context));
            token.ThrowIfCancellationRequested();
            if (generation != Generation) throw new BridgeStaleGenerationException(generation, Generation);
            var saved = await _oauth.UpdatePersonalProfileVisibilityAsync(grant, expected, requested!, token);
            RequireSameSession(owner, RequireSession(context));
            if (generation != Generation) throw new BridgeStaleGenerationException(generation, Generation);
            return VisibilityProjection(saved.Revision, saved.Visibility);
        }
        catch (ScmApiForbiddenException) { throw new AccountBridgeHostException(AccountBridgeStableErrors.PersonalProfileWriteForbidden); }
        catch (ScmApiAuthenticationException) { throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired); }
        catch (OAuthAuthorizationDeniedException) { throw new OperationCanceledException("Visibility authorization was cancelled."); }
        catch (TimeoutException) { throw new AccountBridgeHostException(AccountBridgeStableErrors.LoginTimeout, retryable: true); }
        catch (HttpRequestException error) when (error.StatusCode == HttpStatusCode.Conflict)
        { throw new AccountBridgeHostException("profile.visibility_conflict"); }
        catch (Exception error) when (error is HttpRequestException or IOException or InvalidOperationException)
        { throw new AccountBridgeHostException("profile.visibility_unavailable"); }
        finally { if (!_disposed) _mutationGate.Release(); }
    }
}
