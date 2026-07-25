namespace StarBridge.Desktop;

using System.IO;
using System.Net;
using System.Net.Http;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using StarBridge.Core.Profiles;

internal enum PersonalProfileLoadSource
{
    None,
    Remote,
    Cache
}

internal enum PersonalProfileSaveStatus
{
    Saved,
    QueuedOffline,
    Conflict,
    Unauthorized
}

internal enum PersonalProfilePublicLoadStatus
{
    Loaded,
    NotFound,
    Unavailable
}

internal sealed record PersonalProfileLoadResult(
    PersonalProfileDocumentContract? Document,
    PersonalProfileLoadSource Source,
    bool HasPendingUpload,
    string? Error = null);

internal sealed record PersonalProfileSaveResult(
    PersonalProfileSaveStatus Status,
    PersonalProfileDocumentContract? Document,
    string? Error = null);

internal sealed record PersonalProfilePublicLoadResult(
    PersonalProfilePublicLoadStatus Status,
    PersonalProfileDocumentContract? Document,
    string? Error = null);

internal sealed record PersonalProfileGameplayStatisticsSaveResult(
    bool Saved,
    PersonalProfileDocumentContract? Document,
    string? Error = null);

internal sealed record PersonalProfileCacheEnvelope(
    PersonalProfileDocumentContract? Snapshot,
    PersonalProfileUpdateRequestContract? PendingUpdate,
    DateTimeOffset CachedAt);

internal sealed class PersonalProfileSyncCoordinator
{
    public PersonalProfileDocumentContract? Snapshot { get; private set; }

    public bool TryAcceptRemote(
        PersonalProfileDocumentContract document,
        bool isEditing,
        bool hasUnsavedChanges)
    {
        if (isEditing || hasUnsavedChanges)
        {
            return false;
        }

        if (Snapshot is not null && document.Revision < Snapshot.Revision)
        {
            return false;
        }

        Snapshot = document;
        return true;
    }

    public void AcceptSaved(PersonalProfileDocumentContract document)
    {
        Snapshot = document;
    }

    public void Reset()
    {
        Snapshot = null;
    }
}

internal sealed class PersonalProfileRemoteRepository
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web)
    {
        WriteIndented = true
    };

    private readonly StarBridgeRelayClient _relayClient;

    public PersonalProfileRemoteRepository(StarBridgeRelayClient relayClient)
    {
        _relayClient = relayClient;
    }

    public async Task<PersonalProfileLoadResult> LoadOwnerAsync(
        string accountIdentity,
        CancellationToken cancellationToken = default)
    {
        var cache = await ReadCacheAsync(accountIdentity, cancellationToken);
        if (cache?.PendingUpdate is not null)
        {
            var flush = await SendUpdateAsync(accountIdentity, cache.PendingUpdate, cancellationToken);
            if (flush.Status == PersonalProfileSaveStatus.Saved && flush.Document is not null)
            {
                cache = new PersonalProfileCacheEnvelope(flush.Document, null, DateTimeOffset.UtcNow);
                await WriteCacheAsync(accountIdentity, cache, cancellationToken);
            }
            else if (flush.Status == PersonalProfileSaveStatus.Conflict && flush.Document is not null)
            {
                cache = cache with { Snapshot = flush.Document, CachedAt = DateTimeOffset.UtcNow };
                await WriteCacheAsync(accountIdentity, cache, cancellationToken);
                return new PersonalProfileLoadResult(
                    flush.Document,
                    PersonalProfileLoadSource.Cache,
                    true,
                    "个人资料在其他设备上已有更新，本地草稿仍被保留。");
            }
        }

        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, _relayClient.BuildUri("api/profile/me"));
            using var response = await _relayClient.SendAsync(request, cancellationToken);
            if (response.StatusCode == HttpStatusCode.Unauthorized)
            {
                return new PersonalProfileLoadResult(
                    cache?.Snapshot,
                    cache?.Snapshot is null ? PersonalProfileLoadSource.None : PersonalProfileLoadSource.Cache,
                    cache?.PendingUpdate is not null,
                    "登录状态已失效，当前显示本地资料。");
            }

            response.EnsureSuccessStatusCode();
            var document = await response.Content.ReadFromJsonAsync<PersonalProfileDocumentContract>(cancellationToken);
            if (document is null)
            {
                throw new InvalidDataException("个人资料响应为空。");
            }

            var updatedCache = new PersonalProfileCacheEnvelope(
                document,
                cache?.PendingUpdate,
                DateTimeOffset.UtcNow);
            await WriteCacheAsync(accountIdentity, updatedCache, cancellationToken);
            return new PersonalProfileLoadResult(
                document,
                PersonalProfileLoadSource.Remote,
                updatedCache.PendingUpdate is not null);
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException or InvalidDataException)
        {
            return new PersonalProfileLoadResult(
                cache?.Snapshot,
                cache?.Snapshot is null ? PersonalProfileLoadSource.None : PersonalProfileLoadSource.Cache,
                cache?.PendingUpdate is not null,
                cache?.Snapshot is null
                    ? "暂时无法同步个人资料。"
                    : "暂时无法连接服务器，当前显示已缓存的个人资料。");
        }
    }

    public async Task<PersonalProfileSaveResult> SaveOwnerAsync(
        string accountIdentity,
        PersonalProfileUpdateRequestContract update,
        CancellationToken cancellationToken = default)
    {
        var cache = await ReadCacheAsync(accountIdentity, cancellationToken);
        await WriteCacheAsync(
            accountIdentity,
            new PersonalProfileCacheEnvelope(cache?.Snapshot, update, DateTimeOffset.UtcNow),
            cancellationToken);

        var result = await SendUpdateAsync(accountIdentity, update, cancellationToken);
        if (result.Status == PersonalProfileSaveStatus.Saved && result.Document is not null)
        {
            await WriteCacheAsync(
                accountIdentity,
                new PersonalProfileCacheEnvelope(result.Document, null, DateTimeOffset.UtcNow),
                cancellationToken);
        }
        else if (result.Status == PersonalProfileSaveStatus.Conflict && result.Document is not null)
        {
            await WriteCacheAsync(
                accountIdentity,
                new PersonalProfileCacheEnvelope(result.Document, update, DateTimeOffset.UtcNow),
                cancellationToken);
        }

        return result;
    }

    public async Task<PersonalProfilePublicLoadResult> LoadPublicAsync(
        string publicId,
        CancellationToken cancellationToken = default)
    {
        var normalizedPublicId = (publicId ?? "").Trim();
        if (normalizedPublicId.Length is < 8 or > 128)
        {
            return new PersonalProfilePublicLoadResult(
                PersonalProfilePublicLoadStatus.NotFound,
                null);
        }

        try
        {
            using var request = new HttpRequestMessage(
                HttpMethod.Get,
                _relayClient.BuildUri($"api/profiles/{Uri.EscapeDataString(normalizedPublicId)}"));
            using var response = await _relayClient.SendAsync(request, cancellationToken);
            if (response.StatusCode == HttpStatusCode.NotFound)
            {
                return new PersonalProfilePublicLoadResult(
                    PersonalProfilePublicLoadStatus.NotFound,
                    null);
            }

            response.EnsureSuccessStatusCode();
            var document = await response.Content.ReadFromJsonAsync<PersonalProfileDocumentContract>(cancellationToken);
            return document is null
                ? new PersonalProfilePublicLoadResult(
                    PersonalProfilePublicLoadStatus.Unavailable,
                    null,
                    "公开资料响应为空，请稍后重试。")
                : new PersonalProfilePublicLoadResult(
                    PersonalProfilePublicLoadStatus.Loaded,
                    document);
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException or InvalidDataException)
        {
            return new PersonalProfilePublicLoadResult(
                PersonalProfilePublicLoadStatus.Unavailable,
                null,
                "暂时无法读取公开资料，请检查连接后重试。");
        }
    }

    public async Task<PersonalProfileGameplayStatisticsSaveResult> SaveGameplayStatisticsAsync(
        PersonalProfileGameplayStatisticsUpdateRequestContract update,
        CancellationToken cancellationToken = default)
    {
        try
        {
            using var request = new HttpRequestMessage(
                HttpMethod.Put,
                _relayClient.BuildUri("api/profile/me/gameplay-statistics"))
            {
                Content = JsonContent.Create(update)
            };
            using var response = await _relayClient.SendAsync(request, cancellationToken);
            if (response.StatusCode == HttpStatusCode.Unauthorized)
            {
                return new PersonalProfileGameplayStatisticsSaveResult(
                    false,
                    null,
                    "登录状态已失效，统计仍仅保存在本机。");
            }

            response.EnsureSuccessStatusCode();
            var document = await response.Content.ReadFromJsonAsync<PersonalProfileDocumentContract>(cancellationToken);
            return document is null
                ? new PersonalProfileGameplayStatisticsSaveResult(false, null, "服务器返回了空统计资料。")
                : new PersonalProfileGameplayStatisticsSaveResult(true, document);
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException or InvalidDataException)
        {
            return new PersonalProfileGameplayStatisticsSaveResult(
                false,
                null,
                "暂时无法同步公开统计；本地记录不受影响。");
        }
    }

    private async Task<PersonalProfileSaveResult> SendUpdateAsync(
        string accountIdentity,
        PersonalProfileUpdateRequestContract update,
        CancellationToken cancellationToken)
    {
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Put, _relayClient.BuildUri("api/profile/me"))
            {
                Content = JsonContent.Create(update)
            };
            using var response = await _relayClient.SendAsync(request, cancellationToken);
            if (response.StatusCode == HttpStatusCode.Unauthorized)
            {
                return new PersonalProfileSaveResult(
                    PersonalProfileSaveStatus.Unauthorized,
                    null,
                    "登录状态已失效，资料已保存在本地并等待重新登录。");
            }

            if (response.StatusCode == HttpStatusCode.Conflict)
            {
                var current = await response.Content.ReadFromJsonAsync<PersonalProfileDocumentContract>(cancellationToken);
                return new PersonalProfileSaveResult(
                    PersonalProfileSaveStatus.Conflict,
                    current,
                    "个人资料已在其他设备更新，请重新载入后再保存。");
            }

            response.EnsureSuccessStatusCode();
            var saved = await response.Content.ReadFromJsonAsync<PersonalProfileDocumentContract>(cancellationToken);
            return saved is null
                ? new PersonalProfileSaveResult(PersonalProfileSaveStatus.QueuedOffline, null, "服务器返回了空资料，已保留本地草稿。")
                : new PersonalProfileSaveResult(PersonalProfileSaveStatus.Saved, saved);
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException)
        {
            return new PersonalProfileSaveResult(
                PersonalProfileSaveStatus.QueuedOffline,
                null,
                "网络暂不可用，资料已保存在本地并将在恢复连接后同步。");
        }
    }

    private static async Task<PersonalProfileCacheEnvelope?> ReadCacheAsync(
        string accountIdentity,
        CancellationToken cancellationToken)
    {
        var path = GetCachePath(accountIdentity);
        if (!File.Exists(path))
        {
            return null;
        }

        try
        {
            await using var stream = File.OpenRead(path);
            return await JsonSerializer.DeserializeAsync<PersonalProfileCacheEnvelope>(stream, JsonOptions, cancellationToken);
        }
        catch
        {
            return null;
        }
    }

    private static async Task WriteCacheAsync(
        string accountIdentity,
        PersonalProfileCacheEnvelope cache,
        CancellationToken cancellationToken)
    {
        var path = GetCachePath(accountIdentity);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var tempPath = $"{path}.tmp";
        await using (var stream = File.Create(tempPath))
        {
            await JsonSerializer.SerializeAsync(stream, cache, JsonOptions, cancellationToken);
        }

        File.Move(tempPath, path, overwrite: true);
    }

    internal static string GetCachePath(string accountIdentity)
    {
        var hash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(accountIdentity.Trim())))
            .ToLowerInvariant();
        return Path.Combine(DesktopAppConfig.ConfigDirectory, "personal-profile-cache", $"{hash}.json");
    }
}

internal static class PersonalProfileContractMapper
{
    public static PersonalProfileContentContract ToContract(PersonalProfileSettings settings) =>
        PersonalProfileContractPolicy.Normalize(new PersonalProfileContentContract(
            settings.ShowOnlineTime,
            settings.OnlineTimeStart,
            settings.OnlineTimeEnd,
            settings.ActivityRhythm,
            settings.Introduction,
            settings.SkilledRoles ?? [],
            settings.SupportCapabilities ?? [],
            settings.ParticipationInterests ?? [],
            settings.ShipWishlist ?? [],
            settings.FavoriteShipCodes ?? [],
            settings.Modules.Select(module => new PersonalProfileModuleContract(
                module.Id,
                module.Span,
                module.IsVisible,
                module.Order,
                module.Position)).ToArray(),
            settings.AvailabilityTimeZoneId,
            (settings.AvailabilityWindows ?? [])
                .Select(window => new PersonalProfileAvailabilityWindowContract(
                    window.Days.ToArray(),
                    window.StartTime,
                    window.EndTime))
                .ToArray(),
            settings.PresenceIntent));

    public static PersonalProfileSettings ToSettings(
        PersonalProfileDocumentContract document,
        PersonalProfileSettings fallback) => fallback with
        {
            ShowOnlineTime = document.Content.ShowOnlineTime,
            OnlineTimeStart = document.Content.OnlineTimeStart,
            OnlineTimeEnd = document.Content.OnlineTimeEnd,
            ActivityRhythm = document.Content.ActivityRhythm,
            Introduction = document.Content.Introduction,
            SkilledRoles = document.Content.SkilledRoles.ToArray(),
            SupportCapabilities = document.Content.SupportCapabilities.ToArray(),
            ParticipationInterests = document.Content.ParticipationInterests.ToArray(),
            ShipWishlist = document.Content.ShipWishlist.ToArray(),
            FavoriteShipCodes = document.Content.FavoriteShipCodes.ToArray(),
            AvailabilityTimeZoneId = string.IsNullOrWhiteSpace(document.Content.AvailabilityTimeZoneId)
                ? fallback.AvailabilityTimeZoneId
                : document.Content.AvailabilityTimeZoneId,
            AvailabilityWindows = MapAvailabilityWindows(document, fallback),
            PresenceIntent = document.Content.PresenceIntent,
            IsProfilePublic = document.IsPublic,
            Modules = MergeModules(document.Content.Modules, fallback.Modules)
        };

    private static PersonalProfileAvailabilityWindowSetting[] MapAvailabilityWindows(
        PersonalProfileDocumentContract document,
        PersonalProfileSettings fallback)
    {
        if (document.Content.AvailabilityWindows is not null)
        {
            return document.Content.AvailabilityWindows
                .Select(ToAvailabilityWindowSetting)
                .ToArray();
        }

        if (document.SchemaVersion < PersonalProfileContractPolicy.CurrentSchemaVersion)
        {
            var savedWindows = fallback.AvailabilityWindows ?? [];
            if (savedWindows.Length > 0)
            {
                return savedWindows
                    .Select(window => new PersonalProfileAvailabilityWindowSetting(
                        window.Days.ToArray(),
                        window.StartTime,
                        window.EndTime))
                    .ToArray();
            }

            return PersonalProfileContractPolicy.Normalize(document.Content).AvailabilityWindows!
                .Select(ToAvailabilityWindowSetting)
                .ToArray();
        }

        return [];
    }

    private static PersonalProfileAvailabilityWindowSetting ToAvailabilityWindowSetting(
        PersonalProfileAvailabilityWindowContract window) =>
        new(window.Days.ToArray(), window.StartTime, window.EndTime);

    private static PersonalProfileModuleSetting[] MergeModules(
        IEnumerable<PersonalProfileModuleContract> remote,
        IEnumerable<PersonalProfileModuleSetting> fallback)
    {
        var remoteById = remote.ToDictionary(module => module.Id, StringComparer.OrdinalIgnoreCase);
        return fallback
            .Select(module => remoteById.TryGetValue(module.Id, out var value)
                ? new PersonalProfileModuleSetting(value.Id, value.Span, value.IsVisible, value.Order, value.Position)
                : module)
            .OrderBy(module => module.Order)
            .ToArray();
    }
}
