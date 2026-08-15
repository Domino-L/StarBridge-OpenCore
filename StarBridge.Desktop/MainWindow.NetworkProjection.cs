using StarBridge.Core.Events;
using StarBridge.Core.FleetChat;
using StarBridge.Core.Presence;
using StarBridge.Core.State;
using System.Globalization;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Media.Imaging;

namespace StarBridge.Desktop;

public partial class MainWindow
{
    private Uri BuildNetworkUri(string path)
    {
        var uri = _relayClient.BuildUri(path);
        if (!uri.Scheme.Equals(Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase) && !uri.IsLoopback)
        {
            throw new InvalidOperationException("StarBridge 联机会话必须使用 HTTPS 加密连接。请检查服务器地址。");
        }

        return uri;
    }

    private Uri BuildAuthenticationUri(string path)
    {
        return BuildNetworkUri(path);
    }

    private static string NormalizeNetworkServerUrl(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return DefaultRelayUrl;
        }

        var trimmed = value.Trim().TrimEnd('/');
        var isLegacyLiteralAddress =
            Uri.TryCreate(trimmed, UriKind.Absolute, out var parsedUri) &&
            IPAddress.TryParse(parsedUri.Host, out _) &&
            !parsedUri.IsLoopback;
        if (trimmed.Equals("http://127.0.0.1:5058", StringComparison.OrdinalIgnoreCase) ||
            trimmed.Equals("http://localhost:5058", StringComparison.OrdinalIgnoreCase) ||
            trimmed.Equals("http://api.scstarbridge.com", StringComparison.OrdinalIgnoreCase) ||
            isLegacyLiteralAddress)
        {
            return DefaultRelayUrl;
        }

        return trimmed;
    }

    private Task<HttpResponseMessage> PostNetworkJsonAsync<T>(string path, T payload)
    {
        return _relayClient.PostJsonAsync(path, payload);
    }

    private string BuildFleetEmailBody(string eventName, params (string Label, string Value)[] fields)
    {
        var lines = new List<string>
        {
            "StarBridge 组织邮件通知",
            "",
            $"事件：{eventName}",
            $"组织：{_fleetName} ({_fleetCode})",
            ResolveFleetEmailSenderLine()
        };

        foreach (var (label, value) in fields)
        {
            lines.Add($"{label}:{NormalizeOptionalField(value)}");
        }

        return string.Join(Environment.NewLine, lines);
    }

    private string ResolveFleetEmailSenderLine()
    {
        var display = FormatCommanderName(_callsign, _localPlayer);
        if (IsCurrentUserFleetCommander())
        {
            return $"发送人：{display} / 组织负责人";
        }

        var permission = GetCurrentUserFleetPermission();
        var role = permission is { PermissionEnabled: true } &&
                   !string.IsNullOrWhiteSpace(permission.RoleTitle)
            ? permission.RoleTitle
            : "组织成员";
        return $"发送人：{display} / {role}";
    }

    private async Task SendFleetEmailNotificationAsync(string subject, string body, bool silent = false)
    {
        if (!IsLoggedIn || !_hasFleet || string.IsNullOrWhiteSpace(_fleetCode))
        {
            return;
        }

        if (!_fleetEmailNotificationsEnabled)
        {
            if (!silent)
            {
                AppendOutput("Fleet email notification skipped: fleet email notifications are disabled.");
            }

            return;
        }

        try
        {
            var request = new FleetNotificationRequest(_fleetCode, subject, body);
            var response = await PostNetworkJsonAsync("api/fleets/notify", request);
            if (!response.IsSuccessStatusCode)
            {
                if (!silent)
                {
                    var error = response.StatusCode == HttpStatusCode.NotFound
                        ? "server notify endpoint is not available; deploy the latest StarBridge relay"
                        : await ReadResponseErrorAsync(response);
                    AppendOutput($"Fleet email notification failed: {error}");
                }

                return;
            }

            if (!silent)
            {
                AppendOutput("Fleet email notification sent.");
            }
        }
        catch (Exception ex)
        {
            if (!silent)
            {
                AppendOutput($"Fleet email notification failed: {ex.Message}");
            }
        }
    }

    private static async Task<string> ReadResponseErrorAsync(HttpResponseMessage response)
    {
        if (response.StatusCode == HttpStatusCode.RequestEntityTooLarge)
        {
            return "上传内容超过了当前通道的容量限制，请稍后重试或选择更小的文件。";
        }

        try
        {
            var body = await response.Content.ReadAsStringAsync();
            if (!string.IsNullOrWhiteSpace(body))
            {
                var trimmedBody = body.Trim();
                try
                {
                    using var document = JsonDocument.Parse(trimmedBody);
                    if (document.RootElement.ValueKind == JsonValueKind.Object &&
                        document.RootElement.TryGetProperty("error", out var errorElement) &&
                        errorElement.ValueKind == JsonValueKind.String)
                    {
                        var serverMessage = errorElement.GetString();
                        return IsUserFacingChineseMessage(serverMessage)
                            ? serverMessage!
                            : DescribeResponseFailure(response.StatusCode);
                    }

                    if (document.RootElement.ValueKind == JsonValueKind.String)
                    {
                        var serverMessage = document.RootElement.GetString();
                        return IsUserFacingChineseMessage(serverMessage)
                            ? serverMessage!
                            : DescribeResponseFailure(response.StatusCode);
                    }
                }
                catch (JsonException)
                {
                    // The relay may return plain text for proxy or platform errors.
                }

                if (trimmedBody.StartsWith("<", StringComparison.Ordinal))
                {
                    return DescribeResponseFailure(response.StatusCode);
                }

                return IsUserFacingChineseMessage(trimmedBody)
                    ? trimmedBody
                    : DescribeResponseFailure(response.StatusCode);
            }
        }
        catch
        {
            // Fall back to the HTTP status line when the server body is unavailable.
        }

        return DescribeResponseFailure(response.StatusCode);
    }

    private static bool IsUserFacingChineseMessage(string? message) =>
        !string.IsNullOrWhiteSpace(message) &&
        message.Any(character => character is >= '\u3400' and <= '\u9FFF');

    private static string DescribeResponseFailure(HttpStatusCode statusCode) => statusCode switch
    {
        HttpStatusCode.BadRequest => "请求内容无法处理，请检查填写内容后重试。",
        HttpStatusCode.Unauthorized => "登录状态已失效，请重新登录。",
        HttpStatusCode.Forbidden => "当前账号没有执行此操作的权限。",
        HttpStatusCode.NotFound => "请求的内容不存在或已失效。",
        HttpStatusCode.Conflict => "内容已在其他位置更新，请刷新后重试。",
        HttpStatusCode.RequestEntityTooLarge => "上传内容过大，请缩小文件后重试。",
        HttpStatusCode.TooManyRequests => "操作过于频繁，请稍后重试。",
        HttpStatusCode.BadGateway or HttpStatusCode.ServiceUnavailable or HttpStatusCode.GatewayTimeout =>
            "星海舰桥服务暂时不可用，请稍后重试。",
        _ when (int)statusCode >= 500 => "服务器暂时无法完成操作，请稍后重试。",
        _ => "操作未完成，请稍后重试。"
    };

    private NetworkFleetSnapshot BuildLocalFleetSnapshot(
        bool includeDirectoryImages = true,
        bool includeRepeatedImages = false)
    {
        var actionPlans = BuildActionPlanSnapshots(includeRepeatedImages);

        return new NetworkFleetSnapshot(
            _fleetName,
            _fleetCode,
            _fleetChiefCommander,
            _fleetDescription,
            _fleetType,
            _fleetActiveTime,
            _fleetJoinPolicy,
            string.IsNullOrWhiteSpace(_fleetCode) ? "LOGO" : _fleetCode,
            includeDirectoryImages ? BuildFleetLogoImageData() : null,
            _players.Count(player => IsOnlineStatus(player.SharedOnlineStatusValue)),
            Math.Max(1, _players.Count),
            _fleetNoticeTitle,
            _fleetNoticeContent,
            _fleetCurrentTaskTitle,
            _fleetCurrentTaskBrief,
            _fleetCurrentTaskParticipants,
            _fleetCurrentTaskRally,
            _fleetCurrentTaskShip,
            _fleetCurrentTaskTime,
            actionPlans,
            DateTimeOffset.UtcNow,
            _accountName,
            BuildFleetMemberPermissionSnapshots(),
            BuildFleetMemberSnapshots(includeRepeatedImages),
            BuildFleetEventLogSnapshots(),
            _fleetCurrentTaskNoticeRevision,
            BuildFleetShipSnapshots(includeRepeatedImages),
            BuildFleetTaskHistorySnapshots(),
            _fleetApplicationSnapshots,
            _fleetEmailNotificationsEnabled,
            null,
            BuildNetworkFleetActivityWindows(),
            _fleetActiveDaysDescription,
            _fleetActivityCadence,
            _fleetTimeZoneId,
            _fleetRecruitingEnabled,
            _fleetRecruitingTarget,
            "",
            _fleetInviteSnapshots,
            RoleGroups: BuildFleetRoleGroupSnapshots(),
            PublicListingEnabled: _fleetPublicListingEnabled,
            PublicMemberScaleMode: _fleetPublicMemberScaleMode,
            PublicShipScaleMode: _fleetPublicShipScaleMode,
            PublicProfileEnabled: true,
            PublicShowDescription: _manageShowDescriptionPublic,
            PublicShowTags: _fleetPublicShowTags,
            PublicShowActiveSystems: _fleetPublicShowActiveSystems,
            PublicShowActivityTime: _fleetPublicShowActivityTime,
            PublicShowExternalContacts: _fleetPublicShowExternalContacts,
            InviteCodeCreationPolicy: _fleetInviteCodeCreationPolicy,
            FleetInvitationCardPolicy: _fleetInvitationCardPolicy,
            ActiveSystemIds: _selectedFleetSystemIds.ToArray(),
            Language: _fleetLanguage,
            WebsiteUrl: _fleetWebsiteUrl,
            ExternalContacts: _fleetExternalContacts
                .Where(contact => !string.IsNullOrWhiteSpace(contact.Platform) && !string.IsNullOrWhiteSpace(contact.Value))
                .Select(contact => new NetworkFleetExternalContactSnapshot(contact.Platform.Trim(), contact.Value.Trim()))
                .Take(5)
                .ToArray(),
            PublicShipCount: _fleetShipInventory.Count,
            PublicShipTypeSummary: BuildFleetPublicShipTypeSummary(),
            NoticePublishedAt: _fleetNoticePublishedAt);
    }

    private NetworkFleetActivityWindowSnapshot[] BuildNetworkFleetActivityWindows()
    {
        EnsureDefaultFleetActivityWindow();
        return _fleetActivityWindows
            .Take(MaxFleetActivityWindowCount)
            .Select(window => new NetworkFleetActivityWindowSnapshot(
                NormalizeFleetActivityDays(window.Days),
                NormalizeFleetActivityClockText(window.StartTime, DefaultFleetActivityStartTime),
                NormalizeFleetActivityClockText(window.EndTime, DefaultFleetActivityEndTime),
                ShouldFleetActivityEndNextDay(window.StartTime, window.EndTime, window.EndsNextDay)))
            .ToArray();
    }

    private NetworkActionPlanSnapshot[] BuildActionPlanSnapshots(bool includeParticipantImages = false)
    {
        return _fleetActionPlans
            .Select(plan => BuildActionPlanSnapshot(plan, includeParticipantImages))
            .ToArray();
    }

    private NetworkActionPlanSnapshot BuildActionPlanSnapshot(
        FleetActionPlanRow plan,
        bool includeParticipantImages = false)
    {
        return new NetworkActionPlanSnapshot(
            plan.Id,
            plan.Title,
            plan.Content,
            plan.StartTime,
            plan.NotifyMembers,
            plan.Participants
                .Select(participant => BuildActionPlanParticipantSnapshot(participant, includeParticipantImages))
                .ToArray(),
            plan.Status,
            plan.CanceledAt,
            plan.CanceledBy,
            plan.CancelReason,
            plan.ReachedAt,
            plan.CompletedAt,
            plan.CompletedBy,
            plan.CompletionMode,
            plan.UpdatedAt,
            plan.Version);
    }

    private NetworkActionPlanParticipantSnapshot BuildActionPlanParticipantSnapshot(
        ActionPlanParticipantRow participant,
        bool includeImage = false)
    {
        return new NetworkActionPlanParticipantSnapshot(
            participant.Callsign,
            participant.GameName,
            participant.AvatarPath,
            participant.Initials,
            includeImage ? ResolveParticipantAvatarImageData(participant) : null,
            participant.ReminderRequested,
            participant.ReminderSentAt);
    }

    private NetworkFleetMemberPermissionSnapshot[] BuildFleetMemberPermissionSnapshots()
    {
        var commanderName = GetGameNameFromDisplayName(_fleetChiefCommander);
        var rows = _fleetMemberPermissions.Values
            .Where(item => !string.IsNullOrWhiteSpace(item.GameName))
            .Where(item => !IsFleetCommanderRole(item.RoleGroupKey, item.RoleTitle) ||
                           (!string.IsNullOrWhiteSpace(commanderName) &&
                            item.GameName.Trim().Equals(commanderName, StringComparison.OrdinalIgnoreCase)))
            .Select(item => new NetworkFleetMemberPermissionSnapshot(
                item.GameName.Trim(),
                item.Callsign,
                NormalizeRoleTitle(item.RoleTitle),
                item.PermissionEnabled,
                item.CanRemoveMembers,
                item.CanPublishTasks,
                item.CanPublishPlans,
                item.CanManageFleetInfo,
                item.UpdatedAt,
                NormalizeRoleGroupKey(item.RoleGroupKey, item.RoleTitle),
                item.ExtraAllowedPermissions,
                item.ExtraDeniedPermissions))
            .ToList();

        if (!string.IsNullOrWhiteSpace(commanderName))
        {
            var commanderPermission = new NetworkFleetMemberPermissionSnapshot(
                commanderName,
                GetCallsignFromDisplayName(_fleetChiefCommander),
                "组织负责人",
                true,
                true,
                true,
                true,
                true,
                DateTimeOffset.UtcNow,
                "fleet_commander");
            var commanderIndex = rows.FindIndex(item =>
                item.GameName.Equals(commanderName, StringComparison.OrdinalIgnoreCase));
            if (commanderIndex >= 0)
            {
                rows[commanderIndex] = commanderPermission;
            }
            else
            {
                rows.Add(commanderPermission);
            }
        }

        if (!string.IsNullOrWhiteSpace(_localPlayer) &&
            rows.All(item => !item.GameName.Equals(_localPlayer, StringComparison.OrdinalIgnoreCase)))
        {
            var localPermission = GetFleetPermission(_localPlayer);
            rows.Add(new NetworkFleetMemberPermissionSnapshot(
                _localPlayer.Trim(),
                string.IsNullOrWhiteSpace(_callsign) ? localPermission?.Callsign : _callsign,
                IsFleetCommander(_localPlayer, _callsign)
                    ? "组织负责人"
                    : NormalizeRoleTitle(localPermission?.RoleTitle ?? "成员"),
                localPermission?.PermissionEnabled ?? false,
                localPermission?.CanRemoveMembers ?? false,
                localPermission?.CanPublishTasks ?? false,
                localPermission?.CanPublishPlans ?? false,
                localPermission?.CanManageFleetInfo ?? false,
                localPermission?.UpdatedAt ?? DateTimeOffset.UtcNow,
                NormalizeRoleGroupKey(localPermission?.RoleGroupKey, localPermission?.RoleTitle)));
        }

        return rows.ToArray();
    }

    private NetworkFleetRoleGroupSnapshot[] BuildFleetRoleGroupSnapshots(
        IEnumerable<LocalFleetRoleGroup>? roleGroupsOverride = null)
    {
        return FleetRoleGroupSnapshotFactory.Build(
            roleGroupsOverride ?? GetFleetRoleGroupDefinitionsForPersistenceForCurrentSave());
    }

    private NetworkFleetMemberSnapshot[] BuildFleetMemberSnapshots(bool includeAvatarImage = false)
    {
        if (string.IsNullOrWhiteSpace(_localPlayer))
        {
            return [];
        }

        var local = _players.FirstOrDefault(player =>
            player.Name.Equals(_localPlayer, StringComparison.OrdinalIgnoreCase));
        var permission = GetFleetPermission(_localPlayer);
        var role = IsFleetCommander(_localPlayer, _callsign)
            ? "组织负责人"
            : NormalizeRoleTitle(permission?.RoleTitle ?? local?.Role ?? "成员");

        var privacyProjection = GetLocalFleetPresencePrivacyProjection();
        var publishShip = privacyProjection.CanShareRealtime && _syncPrivacySettings.SyncShipStatus;
        var publishLocation = privacyProjection.CanShareRealtime && _syncPrivacySettings.SyncLocationStatus;
        var publishServerInfo = privacyProjection.CanShareRealtime &&
                                _syncPrivacySettings.SyncServerInfo &&
                                IsGameServerRegionCurrent();
        var locationProjection = FleetPresencePrivacyPolicy.ProjectLocation(
            local?.RawLocation,
            local?.LocationConfidence,
            publishLocation,
            _syncPrivacySettings.HideLowConfidenceLocation);

        return
        [
            new NetworkFleetMemberSnapshot(
                _localPlayer.Trim(),
                string.IsNullOrWhiteSpace(_callsign) ? local?.Callsign : _callsign,
                role,
                privacyProjection.Online,
                publishShip
                    ? string.IsNullOrWhiteSpace(local?.RawShip) ? local?.Ship ?? "Unknown" : local.RawShip
                    : "Unknown",
                locationProjection.Location,
                DateTimeOffset.UtcNow,
                includeAvatarImage ? BuildAvatarImageData() : null,
                locationProjection.Confidence,
                publishServerInfo ? _gameServerShard : null,
                publishServerInfo ? _gameServerRegion : null,
                privacyProjection.LiveStatus,
                _accountId,
                _fleetJoinedAtUtc)
        ];
    }

    private NetworkFleetEventLogSnapshot[] BuildFleetEventLogSnapshots()
    {
        return _allFleetEventLogs
            .Where(row => !IsPersonalPlanParticipationLog(row))
            .OrderByDescending(row => row.EffectiveEndTimestamp)
            .Take(500)
            .Select(row => new NetworkFleetEventLogSnapshot(
                row.Id,
                row.Timestamp,
                row.Type,
                SanitizeFleetEventText(row.Title),
                SanitizeFleetEventText(row.Detail),
                row.EndTimestamp,
                row.OccurrenceCount))
            .ToArray();
    }

    private NetworkFleetTaskHistorySnapshot[] BuildFleetTaskHistorySnapshots()
    {
        return _fleetTaskHistory
            .Take(200)
            .Select(row => new NetworkFleetTaskHistorySnapshot(
                row.Key,
                row.Title,
                row.Brief,
                row.Status,
                row.Participants,
                row.Rally,
                row.RequiredShip,
                row.PublishedAtText))
            .ToArray();
    }

    private NetworkOwnedShipSnapshot[] BuildOwnedShipSnapshots()
    {
        return _ownedShips
            .Select(ship => new NetworkOwnedShipSnapshot(
                ship.Code,
                ship.DisplayName,
                ship.Source,
                ship.ImportedAt,
                NormalizeShipTimestamp(ship.SyncedAt, ship.ImportedAt),
                ship.InstanceId,
                GetOwnedShipRoleCategory(ship).ToString(),
                ship.CustomImageMediaId,
                ship.CustomImageCropFrame.FocusX,
                ship.CustomImageCropFrame.FocusY,
                ship.CustomImageCropFrame.Zoom))
            .ToArray();
    }

    private NetworkFleetShipSnapshot[] BuildFleetShipSnapshots(bool includeOwnerAvatarImage = false)
    {
        if (!_syncPrivacySettings.SyncEnabled || !_syncPrivacySettings.PersonalHangarVisible)
        {
            return [];
        }

        var ownerName = string.IsNullOrWhiteSpace(_localPlayer)
            ? _accountName ?? "Unknown"
            : _localPlayer;
        var avatarImageData = includeOwnerAvatarImage ? BuildAvatarImageData() : null;

        return _ownedShips
            .Select(ship => new NetworkFleetShipSnapshot(
                ship.Code,
                ship.DisplayName,
                ownerName,
                _callsign,
                avatarImageData,
                GetFleetShipSharedAt(ship, ownerName),
                ship.ImportedAt,
                ship.InstanceId,
                GetOwnedShipRoleCategory(ship).ToString(),
                _accountId,
                ship.CustomImageMediaId,
                ship.CustomImageCropFrame.FocusX,
                ship.CustomImageCropFrame.FocusY,
                ship.CustomImageCropFrame.Zoom))
            .ToArray();
    }

    private DateTimeOffset GetFleetShipSharedAt(OwnedShipRecord ship, string ownerName)
    {
        var key = BuildFleetShipKey(ownerName, ship.Code, ship.InstanceId);
        if (_remoteFleetShips.TryGetValue(key, out var remoteShip) &&
            remoteShip.ImportedAt != default &&
            remoteShip.ImportedAt != DateTimeOffset.MinValue)
        {
            var remoteSharedAt = remoteShip.ImportedAt.ToUniversalTime();
            _localFleetShipSharedAtCache[key] = remoteSharedAt;
            return remoteSharedAt;
        }

        if (_localFleetShipSharedAtCache.TryGetValue(key, out var cachedSharedAt))
        {
            return cachedSharedAt;
        }

        var sharedAt = DateTimeOffset.UtcNow;
        _localFleetShipSharedAtCache[key] = sharedAt;
        return sharedAt;
    }

    private static DateTimeOffset NormalizeShipTimestamp(DateTimeOffset value, DateTimeOffset fallback)
    {
        return value == default || value == DateTimeOffset.MinValue
            ? fallback
            : value.ToUniversalTime();
    }

    private static NetworkFleetShipSnapshot[] BuildFleetShipsFromPlayerSnapshot(NetworkPlayerSnapshot snapshot)
    {
        if (!snapshot.PersonalHangarSharedWithFleet)
        {
            return [];
        }

        return (snapshot.OwnedShips ?? [])
            .Where(ship => !string.IsNullOrWhiteSpace(ship.Code))
            .Select(ship => new NetworkFleetShipSnapshot(
                ship.Code,
                ship.DisplayName,
                snapshot.Name,
                snapshot.Callsign,
                snapshot.AvatarImageData,
                NormalizeShipTimestamp(ship.SyncedAt, ship.ImportedAt),
                ship.ImportedAt,
                ship.InstanceId,
                ship.RoleCategory,
                snapshot.AccountId,
                ship.CustomImageMediaId,
                ship.CustomImageCropFocusX,
                ship.CustomImageCropFocusY,
                ship.CustomImageCropZoom))
            .ToArray();
    }

    private string? ResolveParticipantAvatarImageData(ActionPlanParticipantRow participant)
    {
        if (!string.IsNullOrWhiteSpace(participant.GameName) &&
            IsLocalPlayer(participant.GameName))
        {
            return BuildAvatarImageData();
        }

        if (IsImageDataValue(participant.AvatarPath))
        {
            return participant.AvatarPath;
        }

        if (!string.IsNullOrWhiteSpace(participant.GameName) &&
            _networkSnapshots.TryGetValue(participant.GameName, out var snapshot))
        {
            return snapshot.AvatarImageData;
        }

        return null;
    }

    private string? GetAvatarImageDataForPlayer(PlayerRow player)
    {
        if (player.IsSelf)
        {
            return BuildAvatarImageData();
        }

        if (_networkSnapshots.TryGetValue(
                GetNetworkSnapshotKey(player.AccountId, player.Name),
                out var snapshot))
        {
            return snapshot.AvatarImageData;
        }

        return IsImageDataValue(player.AvatarPath) ? player.AvatarPath : null;
    }

    private static bool IsImageDataValue(string? value)
    {
        return !string.IsNullOrWhiteSpace(value) &&
               value.StartsWith("data:image/", StringComparison.OrdinalIgnoreCase);
    }

    private string? BuildAvatarImageData()
    {
        try
        {
            if (string.IsNullOrWhiteSpace(_avatarPath) || !File.Exists(_avatarPath))
            {
                return null;
            }

            var writeTime = File.GetLastWriteTimeUtc(_avatarPath);
            if (_cachedAvatarImagePath == _avatarPath &&
                _cachedAvatarImageWriteTimeUtc == writeTime)
            {
                return _cachedAvatarImageData;
            }

            var imageData = BuildImageDataFromPath(_avatarPath, 512 * 1024);
            if (string.IsNullOrWhiteSpace(imageData))
            {
                return null;
            }

            _cachedAvatarImagePath = _avatarPath;
            _cachedAvatarImageWriteTimeUtc = writeTime;
            _cachedAvatarImageData = imageData;
            return _cachedAvatarImageData;
        }
        catch
        {
            return _fleetLogoPath;
        }
    }

    private string? SaveNetworkFleetBanner(NetworkFleetSnapshot snapshot)
    {
        var prefix = BuildNetworkFleetBannerPrefix(snapshot.Code);
        if (!TryDecodeImageData(snapshot.BannerImageData, FleetBannerSyncImageMaxBytes, out var bytes))
        {
            return _fleetBannerPath;
        }

        try
        {
            var hash = Convert.ToHexString(SHA256.HashData(bytes))[..12].ToLowerInvariant();
            var path = BuildImagePath(prefix, hash);
            WriteImageFileIfChanged(path, bytes);
            CleanupImageVariants(prefix, path);
            return path;
        }
        catch
        {
            return _fleetBannerPath;
        }
    }

    private string? BuildFleetLogoImageData()
    {
        return BuildImageDataFromPath(_fleetLogoPath, FleetSyncImageMaxBytes);
    }

    private string? BuildFleetBannerImageData()
    {
        return null;
    }

    private static string? BuildImageDataFromPath(string? path, int maxBytes)
    {
        if (IsImageDataValue(path))
        {
            return path;
        }

        if (string.IsNullOrWhiteSpace(path) || !File.Exists(path))
        {
            return null;
        }

        try
        {
            var bytes = File.ReadAllBytes(path);
            if (bytes.Length == 0 || bytes.Length > maxBytes)
            {
                return null;
            }

            var extension = Path.GetExtension(path).ToLowerInvariant();
            var mimeType = extension is ".jpg" or ".jpeg" ? "image/jpeg" : "image/png";
            return $"data:{mimeType};base64,{Convert.ToBase64String(bytes)}";
        }
        catch
        {
            return null;
        }
    }

    private string? SaveNetworkFleetLogo(NetworkFleetSnapshot snapshot)
    {
        var prefix = BuildNetworkFleetLogoPrefix(snapshot.Code);
        if (!TryDecodeImageData(snapshot.LogoImageData, 768 * 1024, out var bytes))
        {
            return _fleetLogoPath;
        }

        try
        {
            var hash = Convert.ToHexString(SHA256.HashData(bytes))[..12].ToLowerInvariant();
            var path = BuildImagePath(prefix, hash);
            WriteImageFileIfChanged(path, bytes);
            CleanupImageVariants(prefix, path);
            return path;
        }
        catch
        {
            return null;
        }
    }

    private static bool TryDecodeImageData(string? imageData, int maxBytes, out byte[] bytes)
    {
        bytes = [];
        if (string.IsNullOrWhiteSpace(imageData))
        {
            return false;
        }

        try
        {
            var payload = imageData;
            var commaIndex = payload.IndexOf(',');
            if (payload.StartsWith("data:image/", StringComparison.OrdinalIgnoreCase) && commaIndex >= 0)
            {
                payload = payload[(commaIndex + 1)..];
            }

            bytes = Convert.FromBase64String(payload);
            return bytes.Length > 0 && bytes.Length <= maxBytes;
        }
        catch
        {
            bytes = [];
            return false;
        }
    }

    private static string BuildNetworkFleetLogoPrefix(string? fleetCode)
    {
        return $"fleet-{BuildSafeImageToken(fleetCode, "fleet")}-logo";
    }

    private static string BuildNetworkFleetBannerPrefix(string? fleetCode)
    {
        return $"fleet-{BuildSafeImageToken(fleetCode, "fleet")}-banner";
    }

    private static string BuildSafeImageToken(string? value, string fallback)
    {
        var safeValue = new string((value ?? fallback).Where(char.IsLetterOrDigit).ToArray());
        return string.IsNullOrWhiteSpace(safeValue) ? fallback : safeValue;
    }

    private enum LocalImageStorage
    {
        Cache,
        UserAsset
    }

    private static string GetLocalImageCacheDirectory()
    {
        return Path.Combine(DesktopAppConfig.ConfigDirectory, "Images");
    }

    private static string GetUserAssetImageDirectory()
    {
        return Path.Combine(DesktopAppConfig.ConfigDirectory, "UserAssets");
    }

    private static string BuildImagePath(string prefix, string? contentHash = null)
    {
        return BuildImagePathInDirectory(GetLocalImageCacheDirectory(), prefix, contentHash);
    }

    private static string BuildUserAssetImagePath(string prefix, string? contentHash = null)
    {
        return BuildImagePathInDirectory(GetUserAssetImageDirectory(), prefix, contentHash);
    }

    private static string BuildImagePathInDirectory(string directory, string prefix, string? contentHash = null)
    {
        Directory.CreateDirectory(directory);
        var suffix = string.IsNullOrWhiteSpace(contentHash) ? "" : $"-{contentHash}";
        return Path.Combine(directory, $"{prefix}{suffix}.png");
    }

    private static void CleanupImageVariants(string prefix, string? keepPath)
    {
        try
        {
            var directory = GetLocalImageCacheDirectory();
            if (!Directory.Exists(directory))
            {
                return;
            }

            var fullKeepPath = string.IsNullOrWhiteSpace(keepPath) ? null : Path.GetFullPath(keepPath);
            foreach (var file in Directory.EnumerateFiles(directory, $"{prefix}*.png"))
            {
                try
                {
                    if (!IsImageVariantForPrefix(file, prefix))
                    {
                        continue;
                    }

                    if (fullKeepPath is not null &&
                        string.Equals(Path.GetFullPath(file), fullKeepPath, StringComparison.OrdinalIgnoreCase))
                    {
                        continue;
                    }

                    File.Delete(file);
                }
                catch
                {
                    // Cache cleanup is best-effort. A locked image should not break sync.
                }
            }
        }
        catch
        {
            // Cache cleanup is best-effort. A locked image should not break sync.
        }
    }

    private static void CleanupUserAssetImageVariants(string prefix, string? keepPath)
    {
        try
        {
            var directory = GetUserAssetImageDirectory();
            if (!Directory.Exists(directory))
            {
                return;
            }

            var fullKeepPath = string.IsNullOrWhiteSpace(keepPath) ? null : Path.GetFullPath(keepPath);
            foreach (var file in Directory.EnumerateFiles(directory, $"{prefix}*.png"))
            {
                try
                {
                    if (!IsImageVariantForPrefix(file, prefix))
                    {
                        continue;
                    }

                    if (fullKeepPath is not null &&
                        string.Equals(Path.GetFullPath(file), fullKeepPath, StringComparison.OrdinalIgnoreCase))
                    {
                        continue;
                    }

                    File.Delete(file);
                }
                catch
                {
                    // User asset cleanup is best-effort; a locked avatar should not break profile updates.
                }
            }
        }
        catch
        {
            // User asset cleanup is best-effort.
        }
    }

    private static bool IsImageVariantForPrefix(string path, string prefix)
    {
        var fileName = Path.GetFileNameWithoutExtension(path);
        if (string.Equals(fileName, prefix, StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }

        var hashPrefix = $"{prefix}-";
        if (!fileName.StartsWith(hashPrefix, StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        var suffix = fileName[hashPrefix.Length..];
        return suffix.Length == 12 && suffix.All(Uri.IsHexDigit);
    }

    private static bool IsPathInsideDirectory(string path, string directory)
    {
        try
        {
            var fullPath = Path.GetFullPath(path);
            var fullDirectory = Path.GetFullPath(directory)
                .TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar) +
                Path.DirectorySeparatorChar;
            return fullPath.StartsWith(fullDirectory, StringComparison.OrdinalIgnoreCase);
        }
        catch
        {
            return false;
        }
    }

    private static bool IsSamePath(string path, string? otherPath)
    {
        if (string.IsNullOrWhiteSpace(otherPath))
        {
            return false;
        }

        try
        {
            return string.Equals(
                Path.GetFullPath(path),
                Path.GetFullPath(otherPath),
                StringComparison.OrdinalIgnoreCase);
        }
        catch
        {
            return false;
        }
    }

    private static void WriteImageFileIfChanged(string path, byte[] bytes)
    {
        if (File.Exists(path))
        {
            try
            {
                var existing = File.ReadAllBytes(path);
                if (existing.SequenceEqual(bytes))
                {
                    return;
                }
            }
            catch
            {
                // Rewrite the image if the old file cannot be read.
            }
        }

        File.WriteAllBytes(path, bytes);
    }
}
