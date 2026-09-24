namespace StarBridge.HostRuntime.Auth;

using StarBridge.Core.Profiles;
using StarBridge.HostRuntime.Account;
using System.IO;
using System.Text.Json;

internal sealed class ScmProfileCacheStore
{
    private const string CacheDirectoryName = "scm-profile-cache";
    private readonly string _cacheDirectory;

    internal ScmProfileCacheStore(string? configDirectory = null)
    {
        _cacheDirectory = Path.Combine(
            configDirectory ?? StarBridge.HostRuntime.HostDataRoot.CurrentRoot,
            CacheDirectoryName);
    }

    internal ScmCachedProfileContract? Load(AccountRouteIdentity route)
    {
        if (!route.IsAuthenticated)
        {
            return null;
        }

        try
        {
            var path = ResolvePath(route);
            if (!File.Exists(path))
            {
                return null;
            }

            var cached = JsonSerializer.Deserialize<ScmCachedProfileContract>(File.ReadAllText(path));
            if (!IsForRoute(cached, route))
            {
                return null;
            }

            _ = cached!.ToOfflineProfile();
            return cached;
        }
        catch (Exception exception) when (exception is IOException or
                                         UnauthorizedAccessException or
                                         JsonException or
                                         ArgumentException)
        {
            return null;
        }
    }

    internal void Save(AccountRouteIdentity route, ScmSelfProfileContract profile, DateTimeOffset cachedAtUtc)
    {
        if (!route.IsAuthenticated)
        {
            throw new InvalidOperationException("Cannot cache an SCM profile without an authenticated route.");
        }

        var normalized = profile.Normalize();
        if (!normalized.Subject.Equals(route.Subject, StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException("SCM profile subject does not match the active account route.");
        }

        var cached = ScmCachedProfileContract.Create(
            route.Environment,
            route.Authority,
            normalized,
            cachedAtUtc);
        Directory.CreateDirectory(_cacheDirectory);
        var destination = ResolvePath(route);
        var temporary = destination + ".tmp";
        File.WriteAllText(temporary, JsonSerializer.Serialize(cached));
        File.Move(temporary, destination, overwrite: true);
    }

    internal bool Clear(AccountRouteIdentity route)
    {
        if (!route.IsAuthenticated)
        {
            return false;
        }

        var path = ResolvePath(route);
        if (!File.Exists(path))
        {
            return false;
        }

        File.Delete(path);
        return true;
    }

    private string ResolvePath(AccountRouteIdentity route) =>
        Path.Combine(_cacheDirectory, $"{route.CacheNamespace["account:".Length..]}.json");

    private static bool IsForRoute(ScmCachedProfileContract? cached, AccountRouteIdentity route) =>
        cached is not null &&
        cached.SchemaVersion == ScmCachedProfileContract.CurrentSchemaVersion &&
        cached.Environment.Equals(route.Environment, StringComparison.OrdinalIgnoreCase) &&
        cached.Authority.Equals(route.Authority, StringComparison.OrdinalIgnoreCase) &&
        cached.Subject.Equals(route.Subject, StringComparison.OrdinalIgnoreCase);
}
