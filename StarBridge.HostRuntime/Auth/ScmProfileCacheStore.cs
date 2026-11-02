namespace StarBridge.HostRuntime.Auth;

using StarBridge.Core.Profiles;
using StarBridge.HostRuntime.Account;
using System.IO;
using System.Text.Json;

internal sealed class ScmProfileCacheStore
{
    private const string CacheDirectoryName = "scm-profile-cache";
    private const int MaximumBytes = 64 * 1024;
    private const int MaximumTextCharacters = 8192;
    private static readonly JsonDocumentOptions DocumentOptions = new() { MaxDepth = 8 };
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
            CheckPath(path, directory: false);
            // Readers retain the last complete file while a writer replaces it.
            using var input = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read | FileShare.Delete);
            if (input.Length is <= 0 or > MaximumBytes) return null;
            var bytes = new byte[(int)input.Length];
            input.ReadExactly(bytes);
            using var document = JsonDocument.Parse(bytes, DocumentOptions);
            if (document.RootElement.ValueKind != JsonValueKind.Object) return null;
            var names = new HashSet<string>(StringComparer.Ordinal);
            foreach (var property in document.RootElement.EnumerateObject())
                if (!names.Add(property.Name)) return null;
            var cached = document.RootElement.Deserialize<ScmCachedProfileContract>();
            if (!IsForRoute(cached, route))
            {
                return null;
            }

            _ = cached!.ToOfflineProfile();
            CheckTextBudget(cached.Environment, cached.Authority, cached.Subject, cached.DisplayName,
                cached.AvatarUrl, cached.Locale, cached.TimeZone);
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
        if (cachedAtUtc == default) throw new InvalidDataException("Profile cache requires an observation time.");

        CheckTextBudget(route.Environment, route.Authority, profile.Subject, profile.DisplayName,
            profile.AvatarUrl, profile.Locale, profile.TimeZone);
        var normalized = profile.Normalize();
        if (!normalized.Subject.Equals(route.Subject, StringComparison.Ordinal))
        {
            throw new InvalidOperationException("SCM profile subject does not match the active account route.");
        }

        var cached = ScmCachedProfileContract.Create(
            route.Environment,
            route.Authority,
            normalized,
            cachedAtUtc);
        var destination = ResolvePath(route);
        CheckPath(_cacheDirectory, directory: true);
        Directory.CreateDirectory(_cacheDirectory);
        using var writer = AcquireWriter(destination);
        var bytes = JsonSerializer.SerializeToUtf8Bytes(cached);
        if (bytes.Length > MaximumBytes) throw new InvalidDataException("Profile cache exceeds its byte budget.");
        var temporary = destination + "." + Guid.NewGuid().ToString("N") + ".tmp";
        var created = false;
        try
        {
            using (var output = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write,
                FileShare.None, 4096, FileOptions.WriteThrough))
            {
                created = true;
                output.Write(bytes);
                output.Flush(flushToDisk: true);
            }
            CheckPath(destination, directory: false);
            if (File.Exists(destination)) File.Replace(temporary, destination, null);
            else File.Move(temporary, destination);
        }
        finally
        {
            if (created) File.Delete(temporary);
        }
    }

    internal bool Clear(AccountRouteIdentity route)
    {
        if (!route.IsAuthenticated)
        {
            return false;
        }

        var path = ResolvePath(route);
        CheckPath(_cacheDirectory, directory: true);
        if (!Directory.Exists(_cacheDirectory)) return false;
        using var writer = AcquireWriter(path);
        var removed = DeleteIfPresent(path);
        // Recover only this namespace's former fixed name and GUID operation files.
        // The shared writer lease prevents deleting another current writer's data.
        removed |= DeleteIfPresent(path + ".tmp");
        var prefix = Path.GetFileName(path) + ".";
        foreach (var candidate in Directory.EnumerateFiles(_cacheDirectory, prefix + "*.tmp"))
        {
            var name = Path.GetFileName(candidate);
            var operation = name[prefix.Length..^4];
            if (operation.Length == 32 && Guid.TryParseExact(operation, "N", out _))
                removed |= DeleteIfPresent(candidate);
        }
        return removed;
    }

    private string ResolvePath(AccountRouteIdentity route) =>
        Path.Combine(_cacheDirectory, $"{route.CacheNamespace["account:".Length..]}.json");

    private static bool IsForRoute(ScmCachedProfileContract? cached, AccountRouteIdentity route) =>
        cached is not null &&
        cached.SchemaVersion == ScmCachedProfileContract.CurrentSchemaVersion &&
        cached.CachedAtUtc != default &&
        string.Equals(cached.Environment, route.Environment, StringComparison.OrdinalIgnoreCase) &&
        string.Equals(cached.Authority, route.Authority, StringComparison.OrdinalIgnoreCase) &&
        string.Equals(cached.Subject, route.Subject, StringComparison.Ordinal);

    private static FileStream AcquireWriter(string path)
    {
        CheckPath(path, directory: false);
        CheckPath(path + ".lock", directory: false);
        // Fail fast: private disk contention must not queue a foreground network read.
        return new FileStream(path + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
    }

    private static bool DeleteIfPresent(string path)
    {
        CheckPath(path, directory: false);
        if (!File.Exists(path)) return false;
        File.Delete(path);
        return true;
    }

    private static void CheckTextBudget(params string?[] values)
    {
        long characters = 0;
        foreach (var value in values) characters += value?.Length ?? 0;
        if (characters > MaximumTextCharacters) throw new InvalidDataException("Profile cache exceeds its text budget.");
    }

    private static void CheckPath(string path, bool directory)
    {
        var full = Path.GetFullPath(path);
        for (var node = full; node is not null; node = Path.GetDirectoryName(node))
        {
            try
            {
                var attributes = File.GetAttributes(node);
                var expectedDirectory = directory || !string.Equals(node, full, StringComparison.OrdinalIgnoreCase);
                if ((attributes & FileAttributes.ReparsePoint) != 0 ||
                    ((attributes & FileAttributes.Directory) != 0) != expectedDirectory)
                    throw new IOException("Invalid profile cache path.");
            }
            catch (FileNotFoundException) { }
            catch (DirectoryNotFoundException) { }
        }
    }
}
