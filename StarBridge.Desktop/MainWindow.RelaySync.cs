using Microsoft.Win32;
using StarBridge.Core.Events;
using StarBridge.Core.FleetChat;
using StarBridge.Core.LogWatching;
using StarBridge.Core.Parsing;
using StarBridge.Core.Presence;
using StarBridge.Core.Profiles;
using StarBridge.Core.State;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Diagnostics;
using System.Diagnostics.CodeAnalysis;
using System.Globalization;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Net.Http.Json;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Brushes = System.Windows.Media.Brushes;
using Color = System.Windows.Media.Color;

namespace StarBridge.Desktop;

public partial class MainWindow
{
    private async Task<bool> PushLocalSnapshotAsync(
        bool silent = false,
        bool pushFleetDirectory = false,
        bool forcePrivacyClear = false)
    {
        while (_isNetworkSnapshotPushRunning)
        {
            await Task.Delay(25);
        }

        _isNetworkSnapshotPushRunning = true;
        try
        {
            return await PushLocalSnapshotCoreAsync(silent, pushFleetDirectory, forcePrivacyClear);
        }
        finally
        {
            _isNetworkSnapshotPushRunning = false;
        }
    }

    private async Task<bool> PushLocalSnapshotCoreAsync(
        bool silent = false,
        bool pushFleetDirectory = false,
        bool forcePrivacyClear = false)
    {
        if (!CanSynchronizeUserData)
        {
            if (!silent)
            {
                NetworkStatusText.Text = IsLoggedIn
                    ? "无法验证身份：所有同步已暂停"
                    : "浏览模式：登录后才能上传状态";
            }

            return false;
        }

        if (string.IsNullOrWhiteSpace(_localPlayer))
        {
            if (!silent)
            {
                NetworkStatusText.Text = "需要先从日志识别玩家名";
            }

            return false;
        }

        var sharing = GetPresenceSharingDecision();
        if (!sharing.CanPublishRealtime && !forcePrivacyClear)
        {
            if (!silent)
            {
                NetworkStatusText.Text = _syncPrivacySettings.PresenceVisibilityMode == PlayerPresenceVisibilityMode.Invisible
                    ? "隐身模式不会上传即时状态"
                    : "离线模式不会上传即时状态";
            }

            return true;
        }

        if (!_syncPrivacySettings.SyncEnabled && !forcePrivacyClear)
        {
            if (!silent)
            {
                NetworkStatusText.Text = "同步信息已关闭";
            }

            return true;
        }

        var local = _players.FirstOrDefault(player => player.Name.Equals(_localPlayer, StringComparison.OrdinalIgnoreCase));
        var privacyProjection = GetLocalFleetPresencePrivacyProjection();
        var canPublishSharedState = privacyProjection.CanShareRealtime;
        var publishOnline = privacyProjection.Online;
        var liveStatus = privacyProjection.LiveStatus;
        var publishShip = canPublishSharedState && _syncPrivacySettings.SyncShipStatus;
        var publishLocation = canPublishSharedState && _syncPrivacySettings.SyncLocationStatus;
        var rawShip = publishShip ? local?.RawShip ?? "Unknown" : "Unknown";
        var shipConfidence = publishShip ? local?.ShipConfidence ?? "None" : "None";
        var locationProjection = FleetPresencePrivacyPolicy.ProjectLocation(
            local?.RawLocation,
            local?.LocationConfidence,
            publishLocation,
            _syncPrivacySettings.HideLowConfidenceLocation);
        var rawLocation = locationProjection.Location;
        var locationConfidence = locationProjection.Confidence;
        var publishServerInfo = canPublishSharedState &&
                                _syncPrivacySettings.SyncServerInfo &&
                                IsGameServerRegionCurrent();
        var serverShard = publishServerInfo ? _gameServerShard : null;
        var serverRegion = publishServerInfo ? _gameServerRegion : null;
        if (!_syncPrivacySettings.SyncServerInfo ||
            (_syncPrivacySettings.HideServerInfoBeforePu && !IsGameServerRegionCurrent()))
        {
            rawLocation = RemoveServerDetailFromLocation(rawLocation);
        }

        var ownedShips = _syncPrivacySettings.SyncEnabled && _syncPrivacySettings.PersonalHangarVisible
            ? BuildOwnedShipSnapshots()
            : [];

        var snapshot = new NetworkPlayerSnapshot(
            _localPlayer!,
            DisplayCallsign(_callsign, _localPlayer),
            _hasFleet ? _fleetName : "No Fleet",
            _joinedSquad?.Name ?? "Unassigned",
            publishOnline,
            rawShip,
            shipConfidence,
            rawLocation,
            locationConfidence,
            DateTimeOffset.UtcNow,
            BuildAvatarImageData(),
            ownedShips,
            FormatNetworkVisibilityScope(_syncPrivacySettings.SyncEnabled
                ? _syncPrivacySettings.EffectiveVisibilityScope
                : SyncPrivacyVisibilityScope.Private),
            _syncPrivacySettings.SyncEnabled && _syncPrivacySettings.PersonalHangarVisible,
            serverShard,
            serverRegion,
            liveStatus,
            SharedEventTypes: _playerEventSharingSettings.ToWireValue(),
            SharedEvents: _playerEventSharingSettings.Allows(PlayerSharedEventTypes.Life)
                ? _sharedLifeEvents.ToArray()
                : [],
            FriendsCanViewPresence: _syncPrivacySettings.FriendsCanViewPresence);

        try
        {
            var response = await PostNetworkJsonAsync("api/players", snapshot);
            response.EnsureSuccessStatusCode();
            if (pushFleetDirectory)
            {
                await PushFleetDirectoryAsync(silent: true);
            }
            NetworkStatusText.Text = $"已上传：{snapshot.Name}";
            if (_syncPrivacySettings.SyncEnabled && _syncPrivacySettings.PersonalHangarVisible)
            {
                MarkOwnedShipsSynced();
            }
            RefreshHeaderStatusBar();
            HideNetworkSyncIssueDialog();
            if (!silent)
            {
                AppendOutput($"NETWORK | pushed={snapshot.Name}");
            }

            return true;
        }
        catch (Exception ex)
        {
            if (HandleAuthorizationFailure(ex, "上传状态", silent))
            {
                return false;
            }

            var issue = FormatNetworkSyncIssue("上传失败", ex);
            NetworkStatusText.Text = issue;
            RefreshHeaderStatusBar();
            if (!silent)
            {
                AppendOutput($"NETWORK | push failed={ex.Message}");
                ShowNetworkSyncIssueDialog(issue);
            }

            return false;
        }

    }

    private void MarkOwnedShipsSynced()
    {
        var unsyncedIndexes = Enumerable.Range(0, _ownedShips.Count)
            .Where(index => _ownedShips[index].SyncedAt == default ||
                            _ownedShips[index].SyncedAt == DateTimeOffset.MinValue)
            .ToArray();
        if (unsyncedIndexes.Length == 0)
        {
            return;
        }

        var syncedAt = DateTimeOffset.UtcNow;
        foreach (var index in unsyncedIndexes)
        {
            _ownedShips[index] = _ownedShips[index] with { SyncedAt = syncedAt };
        }

        ShipDatabaseStore.Save(GetShipDatabaseOwnerKey(), _ownedShips);
        UpdateShipDatabaseSummary();
    }

    private async Task PushOfflineSnapshotOnShutdownAsync()
    {
        while (_isNetworkSnapshotPushRunning)
        {
            await Task.Delay(25);
        }

        if (!CanSynchronizeUserData || string.IsNullOrWhiteSpace(_localPlayer) || !_syncPrivacySettings.SyncEnabled)
        {
            _pendingPrivacyOfflineClear = false;
            return;
        }

        _pendingPrivacyOfflineClear = true;

        _fleetState.Apply(new FleetEvent(FleetEventType.PlayerOffline, _localPlayer));
        var snapshot = BuildOfflineNetworkSnapshot();
        var authToken = _authToken;

        for (var attempt = 0; attempt < 3; attempt++)
        {
            try
            {
                using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(2));
                await SendOfflineSnapshotAsync(snapshot, authToken, timeout.Token);
                _pendingPrivacyOfflineClear = false;
                return;
            }
            catch when (attempt < 2)
            {
                await Task.Delay(TimeSpan.FromMilliseconds(150 * (attempt + 1)));
            }
            catch
            {
                // Keep the clear pending so invisible mode retries on the next sync cycle.
            }
        }
    }

    private async Task PushOfflineSnapshotForAccountSwitchAsync()
    {
        if (!CanSynchronizeUserData || string.IsNullOrWhiteSpace(_localPlayer) || !_syncPrivacySettings.SyncEnabled)
        {
            return;
        }

        for (var attempt = 0; _isNetworkSnapshotPushRunning && attempt < 20; attempt++)
        {
            await Task.Delay(25);
        }

        var snapshot = BuildOfflineNetworkSnapshot();
        var authToken = _authToken;
        try
        {
            using var timeout = new CancellationTokenSource(TimeSpan.FromMilliseconds(1500));
            await SendOfflineSnapshotAsync(snapshot, authToken, timeout.Token);
        }
        catch
        {
            // Account switching must continue; the relay timeout will retire a missed offline heartbeat.
        }
    }

    private NetworkPlayerSnapshot BuildOfflineNetworkSnapshot()
    {
        var ownedShips = _syncPrivacySettings.SyncEnabled && _syncPrivacySettings.PersonalHangarVisible
            ? BuildOwnedShipSnapshots()
            : [];

        return new NetworkPlayerSnapshot(
            _localPlayer!,
            DisplayCallsign(_callsign, _localPlayer),
            _hasFleet ? _fleetName : "No Fleet",
            _joinedSquad?.Name ?? "Unassigned",
            false,
            "Unknown",
            "None",
            "Unknown",
            "None",
            DateTimeOffset.UtcNow,
            BuildAvatarImageData(),
            ownedShips,
            FormatNetworkVisibilityScope(_syncPrivacySettings.EffectiveVisibilityScope),
            _syncPrivacySettings.PersonalHangarVisible,
            LiveStatus: "Offline",
            SharedEventTypes: _playerEventSharingSettings.ToWireValue(),
            FriendsCanViewPresence: _syncPrivacySettings.FriendsCanViewPresence);
    }

    private async Task SendOfflineSnapshotAsync(
        NetworkPlayerSnapshot snapshot,
        string? authToken,
        CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, BuildNetworkUri("api/players"))
        {
            Content = JsonContent.Create(snapshot)
        };
        var key = NetworkServerKeyBox.Password.Trim();
        if (!string.IsNullOrWhiteSpace(key))
        {
            request.Headers.Add("X-StarBridge-Key", key);
        }

        if (!string.IsNullOrWhiteSpace(authToken))
        {
            request.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", authToken);
        }

        using var response = await _networkClient.SendAsync(request, cancellationToken);
        response.EnsureSuccessStatusCode();
    }

    private async Task<bool> PullNetworkSnapshotsAsync(bool silent = false)
    {
        if (!CanSynchronizeUserData)
        {
            return false;
        }

        if (!GetPresenceSharingDecision().CanReceiveRealtime)
        {
            if (!silent)
            {
                NetworkStatusText.Text = "离线模式不会接收玩家即时状态";
            }

            return true;
        }

        var session = _accountSessionCoordinator.Capture();
        try
        {
            var snapshots = (await _relayClient.GetFromJsonAsync<NetworkPlayerSnapshot[]>("api/players") ?? [])
                .Where(snapshot => !FleetMemberDisplaySanitizer.IsEmail(snapshot.Name))
                .ToArray();
            if (!_accountSessionCoordinator.IsCurrent(session))
            {
                return false;
            }
            var fingerprint = NetworkPlayerSnapshotChangeDetector.BuildFingerprint(
                snapshots,
                _hasFleet ? _fleetCode : null);
            if (string.Equals(fingerprint, _lastNetworkPlayerSnapshotFingerprint, StringComparison.Ordinal))
            {
                HideNetworkSyncIssueDialog();
                return true;
            }

            _lastNetworkPlayerSnapshotFingerprint = fingerprint;
            var snapshotNames = snapshots
                .Select(GetNetworkSnapshotKey)
                .ToHashSet(StringComparer.OrdinalIgnoreCase);
            var knownFleetMemberNames = _hasFleet
                ? _fleetMemberPermissions.Keys
                    .Where(name => !string.IsNullOrWhiteSpace(name))
                    .Select(name => name.Trim())
                    .ToHashSet(StringComparer.OrdinalIgnoreCase)
                : new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            var hasRemotePlayerPayload = snapshotNames.Count > 0;
            if (hasRemotePlayerPayload)
            {
                foreach (var name in _networkSnapshots.Keys
                             .Where(name => !snapshotNames.Contains(name) && !knownFleetMemberNames.Contains(name))
                             .ToArray())
                {
                    _networkSnapshots.Remove(name);
                }
            }

            var retainedPlayerNames = _hasFleet
                ? snapshotNames.ToList()
                : new List<string>();
            retainedPlayerNames.AddRange(knownFleetMemberNames);
            if (!_hasFleet)
            {
                _networkSnapshots.Clear();
            }

            if (!string.IsNullOrWhiteSpace(_localPlayer))
            {
                retainedPlayerNames.Add(_localPlayer);
            }

            if (hasRemotePlayerPayload || !_hasFleet)
            {
                _fleetState.RemovePlayersExcept(retainedPlayerNames);
            }
            foreach (var snapshot in snapshots)
            {
                if (IsLocalNetworkSnapshot(snapshot))
                {
                    ApplyLocalNetworkSnapshot(snapshot);
                    continue;
                }

                ApplyNetworkSnapshot(snapshot);
            }

            RenderState();
            NetworkStatusText.Text = $"已拉取：{snapshots.Length} 名玩家";
            RefreshHeaderStatusBar();
            HideNetworkSyncIssueDialog();
            if (!silent)
            {
                AppendOutput($"NETWORK | pulled players={snapshots.Length}");
            }

            return true;
        }
        catch (Exception ex)
        {
            if (!_accountSessionCoordinator.IsCurrent(session))
            {
                return false;
            }

            if (HandleAuthorizationFailure(ex, "拉取玩家", silent))
            {
                return false;
            }

            var issue = FormatNetworkSyncIssue("拉取玩家失败", ex);
            NetworkStatusText.Text = issue;
            RefreshHeaderStatusBar();
            if (!silent)
            {
                AppendOutput($"NETWORK | pull failed={ex.Message}");
                ShowNetworkSyncIssueDialog(issue);
            }

            return false;
        }
    }

    private void QueueFleetBannerDirectoryBackfill()
    {
        return;
    }

    private async Task BackfillFleetBannerDirectoryAsync()
    {
        if (_isFleetBannerDirectoryBackfillInProgress)
        {
            return;
        }

        _isFleetBannerDirectoryBackfillInProgress = true;
        try
        {
            if (string.IsNullOrWhiteSpace(BuildFleetBannerImageData()))
            {
                return;
            }

            await PushFleetInfoAsync(silent: true, includeImages: true, scope: FleetInfoUpdateScope.Banner);
        }
        finally
        {
            _isFleetBannerDirectoryBackfillInProgress = false;
        }
    }

    private async Task<NetworkFleetSnapshot?> PushFleetDirectorySnapshotAsync(
        NetworkFleetSnapshot snapshot,
        bool silent = false,
        bool markPendingOnFailure = true)
    {
        if (!IsLoggedIn)
        {
            if (!silent)
            {
                NetworkStatusText.Text = "浏览模式：登录后才能发布舰队";
            }

            return null;
        }

        try
        {
            _lastFleetDirectorySyncAttemptAtUtc = DateTimeOffset.UtcNow;
            var response = await PostNetworkJsonAsync("api/fleets", snapshot);
            if (!response.IsSuccessStatusCode &&
                response.StatusCode == HttpStatusCode.RequestEntityTooLarge)
            {
                response.Dispose();
                snapshot = snapshot with
                {
                    LogoImageData = null,
                    BannerImageData = null
                };
                response = await PostNetworkJsonAsync("api/fleets", snapshot);
            }

            if (!response.IsSuccessStatusCode)
            {
                if (response.StatusCode == HttpStatusCode.Gone &&
                    markPendingOnFailure &&
                    _hasFleet)
                {
                    await HandleRemoteFleetDisbandedAsync(response, silent);
                    return null;
                }

                if (markPendingOnFailure)
                {
                    MarkFleetDirectorySyncPending();
                }
                var error = await ReadResponseErrorAsync(response);
                if (!silent)
                {
                    NetworkStatusText.Text = $"发布舰队失败：{error}";
                    AppendOutput($"NETWORK | push fleet failed={error}");
                }

                return null;
            }

            NetworkFleetSnapshot? merged = null;
            try
            {
                merged = await response.Content.ReadFromJsonAsync<NetworkFleetSnapshot>();
            }
            catch
            {
                // A fleet write must return the merged server snapshot so creation cannot look successful locally only.
            }

            if (merged is null)
            {
                if (markPendingOnFailure)
                {
                    MarkFleetDirectorySyncPending();
                }
                if (!silent)
                {
                    NetworkStatusText.Text = "发布舰队失败：服务器没有返回舰队确认数据。";
                    AppendOutput("NETWORK | push fleet failed=missing server confirmation");
                }

                return null;
            }

            if (!string.Equals(merged.Code, snapshot.Code, StringComparison.OrdinalIgnoreCase) ||
                !FleetSnapshotContainsLocalPlayer(merged))
            {
                if (markPendingOnFailure)
                {
                    MarkFleetDirectorySyncPending();
                }
                var reason = !string.Equals(merged.Code, snapshot.Code, StringComparison.OrdinalIgnoreCase)
                    ? "同步的数据不属于当前舰队，已停止应用。请刷新后重试。"
                    : "服务器没有确认当前账号属于该舰队";
                if (!silent)
                {
                    NetworkStatusText.Text = $"发布舰队失败：{reason}。";
                    AppendOutput($"NETWORK | push fleet failed={reason}");
                }

                return null;
            }

            return merged;
        }
        catch (Exception ex)
        {
            if (HandleAuthorizationFailure(ex, "发布舰队", silent))
            {
                return null;
            }

            if (markPendingOnFailure)
            {
                MarkFleetDirectorySyncPending();
            }
            if (!silent)
            {
                var issue = FormatNetworkSyncIssue("发布舰队失败", ex);
                NetworkStatusText.Text = issue;
                AppendOutput($"NETWORK | push fleet failed={ex.Message}");
                ShowNetworkSyncIssueDialog(issue);
            }

            return null;
        }
    }

    private async Task<bool> PushFleetDirectoryAsync(bool silent = false)
    {
        if (!IsLoggedIn)
        {
            if (!silent)
            {
                NetworkStatusText.Text = "浏览模式：登录后才能发布舰队";
            }

            return false;
        }

        if (!_hasFleet)
        {
            return false;
        }

        var snapshot = BuildLocalFleetSnapshot(includeDirectoryImages: true, includeRepeatedImages: false);
        try
        {
            _lastFleetDirectorySyncAttemptAtUtc = DateTimeOffset.UtcNow;
            var response = await PostNetworkJsonAsync("api/fleets", snapshot);
            if (!response.IsSuccessStatusCode &&
                response.StatusCode == HttpStatusCode.RequestEntityTooLarge)
            {
                response.Dispose();
                snapshot = BuildLocalFleetSnapshot(includeDirectoryImages: false, includeRepeatedImages: false);
                response = await PostNetworkJsonAsync("api/fleets", snapshot);
            }

            if (!response.IsSuccessStatusCode)
            {
                if (response.StatusCode == HttpStatusCode.Gone)
                {
                    return await HandleRemoteFleetDisbandedAsync(response, silent);
                }

                MarkFleetDirectorySyncPending();
                var error = await ReadResponseErrorAsync(response);
                if (!silent)
                {
                    NetworkStatusText.Text = $"发布舰队失败：{error}";
                    AppendOutput($"NETWORK | push fleet failed={error}");
                }

                return false;
            }

            NetworkFleetSnapshot? merged = null;
            try
            {
                merged = await response.Content.ReadFromJsonAsync<NetworkFleetSnapshot>();
            }
            catch
            {
                // A fleet write must return the merged server snapshot so creation cannot look successful locally only.
            }

            if (merged is null)
            {
                MarkFleetDirectorySyncPending();
                if (!silent)
                {
                    NetworkStatusText.Text = "发布舰队失败：服务器没有返回舰队确认数据。";
                    AppendOutput("NETWORK | push fleet failed=missing server confirmation");
                }

                return false;
            }

            if (!string.Equals(merged.Code, snapshot.Code, StringComparison.OrdinalIgnoreCase) ||
                !FleetSnapshotContainsLocalPlayer(merged))
            {
                MarkFleetDirectorySyncPending();
                var reason = !string.Equals(merged.Code, snapshot.Code, StringComparison.OrdinalIgnoreCase)
                    ? "同步的数据不属于当前舰队，已停止应用。请刷新后重试。"
                    : "服务器没有确认当前账号属于该舰队";
                if (!silent)
                {
                    NetworkStatusText.Text = $"发布舰队失败：{reason}。";
                    AppendOutput($"NETWORK | push fleet failed={reason}");
                }

                return false;
            }

            _fleetDirectorySyncPending = false;
            MergeNetworkFleetState(merged);

            if (!silent)
            {
                NetworkStatusText.Text = $"已发布舰队：{snapshot.Name}";
                AppendOutput($"NETWORK | pushed fleet={snapshot.Name}");
            }
            HideNetworkSyncIssueDialog();

            return true;
        }
        catch (Exception ex)
        {
            if (HandleAuthorizationFailure(ex, "发布舰队", silent))
            {
                return false;
            }

            MarkFleetDirectorySyncPending();
            if (!silent)
            {
                var issue = FormatNetworkSyncIssue("发布舰队失败", ex);
                NetworkStatusText.Text = issue;
                AppendOutput($"NETWORK | push fleet failed={ex.Message}");
                ShowNetworkSyncIssueDialog(issue);
            }

            return false;
        }
    }

    private async Task<bool> HandleRemoteFleetDisbandedAsync(HttpResponseMessage response, bool silent)
    {
        var error = await ReadResponseErrorAsync(response);
        var removedFleetName = _fleetName;
        var removedFleetCode = _fleetCode;

        ClearFleetState();
        _fleetDirectorySyncPending = false;
        SaveCurrentConfig();

        _allNetworkFleets.RemoveAll(card =>
            string.Equals(card.Snapshot.Name, removedFleetName, StringComparison.OrdinalIgnoreCase) ||
            string.Equals(card.Snapshot.Code, removedFleetCode, StringComparison.OrdinalIgnoreCase));
        ApplyFleetSearchFilter();
        RefreshHeaderStatusBar();
        HideNetworkSyncIssueDialog();

        var message = string.IsNullOrWhiteSpace(error)
            ? "当前舰队已在服务器解散，已清理本地舰队状态。"
            : error;
        NetworkStatusText.Text = message;
        if (!silent)
        {
            AppendOutput($"NETWORK | fleet disbanded remotely={removedFleetCode}");
            _ = ShowAppNoticeAsync(
                "舰队已解散",
                "服务器确认该舰队已经解散。",
                "本地舰队状态已清理。旧客户端缓存不会重新创建该舰队；如需继续使用，请创建或加入新的舰队。");
        }

        return false;
    }

    private async Task<bool> PushFleetMutationAsync<T>(
        string path,
        T payload,
        string successMessage,
        string failurePrefix,
        bool silent = true)
    {
        if (!IsLoggedIn || !_hasFleet || string.IsNullOrWhiteSpace(_fleetCode))
        {
            return false;
        }

        try
        {
            var response = await PostNetworkJsonAsync(path, payload);
            if (!response.IsSuccessStatusCode)
            {
                if (HandleAuthorizationFailure(response.StatusCode, failurePrefix, silent))
                {
                    return false;
                }

                var error = await ReadResponseErrorAsync(response);
                if (!silent)
                {
                    NetworkStatusText.Text = $"{failurePrefix}:{error}";
                    AppendOutput($"NETWORK | {failurePrefix}={error}");
                }

                return false;
            }

            var snapshot = await response.Content.ReadFromJsonAsync<NetworkFleetSnapshot>();
            if (snapshot is not null)
            {
                MergeNetworkFleetState(snapshot);
            }

            if (!silent)
            {
                NetworkStatusText.Text = successMessage;
                AppendOutput($"NETWORK | {successMessage}");
            }

            return true;
        }
        catch (Exception ex)
        {
            if (HandleAuthorizationFailure(ex, failurePrefix, silent))
            {
                return false;
            }

            if (!silent)
            {
                NetworkStatusText.Text = UserFacingError.Describe(ex, "同步未完成，应用稍后会自动重试。");
                AppendOutput($"NETWORK | {failurePrefix}={ex.Message}");
            }

            return false;
        }
    }

    private Task<bool> PushFleetTaskAsync(bool silent = true)
    {
        return PushFleetMutationAsync(
            "api/fleets/task",
            new FleetTaskUpdateRequest(
                _fleetCode,
                _fleetCurrentTaskTitle,
                _fleetCurrentTaskBrief,
                _fleetCurrentTaskParticipants,
                _fleetCurrentTaskRally,
                _fleetCurrentTaskShip,
                _fleetCurrentTaskTime,
                _fleetCurrentTaskNoticeRevision,
                BuildFleetTaskHistorySnapshots(),
                BuildFleetEventLogSnapshots()),
            "舰队任务已同步",
            "任务同步失败",
            silent);
    }

    private Task<bool> PushFleetTaskResponseAsync(
        string response,
        string? taskTitle,
        DateTime? taskTime,
        bool silent = true)
    {
        return PushFleetMutationAsync(
            "api/fleets/task-response",
            new FleetTaskResponseRequest(
                _fleetCode,
                taskTitle,
                taskTime,
                response),
            "任务回应已同步",
            "任务回应同步失败",
            silent);
    }

    private Task<bool> PushFleetActionPlansAsync(bool silent = true)
    {
        return PushFleetMutationAsync(
            "api/fleets/action-plans",
            new FleetActionPlansUpdateRequest(
                _fleetCode,
                BuildActionPlanSnapshots(),
                BuildFleetEventLogSnapshots()),
            "行动计划已同步",
            "行动计划同步失败",
            silent);
    }

    private Task<bool> PushFleetActionPlanJoinAsync(
        FleetActionPlanRow plan,
        ActionPlanParticipantRow participant,
        bool silent = true)
    {
        return PushFleetMutationAsync(
            "api/fleets/action-plans/join",
            new FleetActionPlanJoinRequest(
                _fleetCode,
                plan.Id,
                BuildActionPlanParticipantSnapshot(participant)),
            "行动预约已同步",
            "行动预约同步失败",
            silent);
    }

    private Task<bool> PushFleetActionPlanLeaveAsync(
        string planId,
        bool silent = true)
    {
        return PushFleetMutationAsync(
            "api/fleets/action-plans/leave",
            new FleetActionPlanLeaveRequest(_fleetCode, planId),
            "行动预约已取消",
            "取消行动预约失败",
            silent);
    }

    private Task<bool> PushFleetActionPlanCancelAsync(
        FleetActionPlanRow plan,
        string? reason,
        bool silent = true)
    {
        return PushFleetMutationAsync(
            "api/fleets/action-plans/cancel",
            new FleetActionPlanCancelRequest(_fleetCode, plan.Id, plan.Version, reason),
            "行动计划已取消",
            "取消行动计划失败",
            silent);
    }

    private Task<bool> PushFleetActionPlanCompleteAsync(
        FleetActionPlanRow plan,
        bool silent = true)
    {
        return PushFleetMutationAsync(
            "api/fleets/action-plans/complete",
            new FleetActionPlanCompleteRequest(_fleetCode, plan.Id, plan.Version),
            "行动计划已完成",
            "完成行动计划失败",
            silent);
    }

    private Task<bool> PushFleetMemberPermissionAsync(
        FleetMemberManagementRow row,
        bool silent = true)
    {
        var permission = new NetworkFleetMemberPermissionSnapshot(
            row.GameName,
            row.Callsign,
            NormalizeRoleTitle(row.RoleTitle),
            row.PermissionEnabled,
            row.CanRemoveMembers,
            row.CanPublishTasks,
            row.CanPublishPlans,
            row.CanManageFleetInfo,
            DateTimeOffset.UtcNow,
            ResolveRoleGroupKeyFromDisplayName(row.RoleTitle));

        return PushFleetMutationAsync(
            "api/fleets/permissions",
            new FleetMemberPermissionUpdateRequest(
                _fleetCode,
                permission,
                BuildFleetEventLogSnapshots()),
            "成员权限已同步",
            "成员权限同步失败",
            silent);
    }

    private Task<bool> PushFleetInfoAsync(
        bool silent = true,
        bool includeImages = false,
        bool requireLogoImage = false,
        bool requireBannerImage = false,
        bool clearLogoImage = false,
        bool clearBannerImage = false,
        FleetInfoUpdateScope scope = FleetInfoUpdateScope.Profile,
        NetworkFleetRoleGroupSnapshot[]? roleGroupsOverride = null)
    {
        var logoImageData = includeImages ? BuildFleetLogoImageData() : null;
        var logoPayloadCheck = FleetImageSyncGuard.CheckRequiredImage(
            requireLogoImage,
            "舰队标志",
            _fleetLogoPath,
            logoImageData);
        if (!logoPayloadCheck.CanSync)
        {
            return FailFleetImageSync(logoPayloadCheck.Message!, silent);
        }

        return PushFleetMutationAsync(
            "api/fleets/info",
            new FleetInfoUpdateRequest(
                _fleetCode,
                _fleetDescription,
                _fleetType,
                _fleetActiveTime,
                _fleetJoinPolicy,
                string.IsNullOrWhiteSpace(_fleetCode) ? "LOGO" : _fleetCode,
                logoImageData,
                null,
                null,
                _fleetEmailNotificationsEnabled,
                BuildNetworkFleetActivityWindows(),
                _fleetActiveDaysDescription,
                _fleetActivityCadence,
                _fleetTimeZoneId,
                _fleetRecruitingEnabled,
                _fleetRecruitingTarget,
                "",
                roleGroupsOverride ?? BuildFleetRoleGroupSnapshots(),
                _fleetPublicListingEnabled,
                _fleetPublicMemberScaleMode,
                _fleetPublicShipScaleMode,
                _manageAllowPublicProfileView,
                _manageShowDescriptionPublic,
                _fleetPublicShowTags,
                _fleetPublicShowActiveSystems,
                _fleetPublicShowActivityTime,
                _fleetPublicShowExternalContacts,
                clearLogoImage,
                false,
                ActiveSystemIds: _selectedFleetSystemIds.ToArray(),
                Language: _fleetLanguage,
                WebsiteUrl: _fleetWebsiteUrl,
                ExternalContacts: _fleetExternalContacts
                    .Where(contact => !string.IsNullOrWhiteSpace(contact.Platform) && !string.IsNullOrWhiteSpace(contact.Value))
                    .Select(contact => new NetworkFleetExternalContactSnapshot(contact.Platform.Trim(), contact.Value.Trim()))
                    .Take(5)
                    .ToArray(),
                UpdatedSections: [GetFleetInfoUpdateSection(scope)],
                ExpectedProfileRevision: _fleetProfileRevision,
                InviteCodeCreationPolicy: _fleetInviteCodeCreationPolicy,
                FleetInvitationCardPolicy: _fleetInvitationCardPolicy),
            "舰队资料已同步",
            "舰队资料同步失败",
            silent);
    }

    private static string GetFleetInfoUpdateSection(FleetInfoUpdateScope scope) => scope switch
    {
        FleetInfoUpdateScope.RoleGroups => "role-groups",
        FleetInfoUpdateScope.Logo => "logo",
        FleetInfoUpdateScope.Banner => "banner",
        FleetInfoUpdateScope.Description => "description",
        FleetInfoUpdateScope.EmailNotifications => "email-notifications",
        _ => "profile"
    };

    private Task<bool> FailFleetImageSync(string message, bool silent)
    {
        if (!silent)
        {
            NetworkStatusText.Text = message;
            SetFleetDescriptionStatus(message, ManageProfileStatusTone.Danger);
            AppendOutput($"NETWORK | fleet image sync blocked: {message}");
        }

        return Task.FromResult(false);
    }

    private bool ValidateRequiredFleetImagePayload(string imageLabel, string imagePath, int maxBytes)
    {
        var imageData = BuildImageDataFromPath(imagePath, maxBytes);
        var payloadCheck = FleetImageSyncGuard.CheckRequiredImage(true, imageLabel, imagePath, imageData);
        if (payloadCheck.CanSync)
        {
            return true;
        }

        NetworkStatusText.Text = payloadCheck.Message!;
        SetFleetDescriptionStatus(payloadCheck.Message!, ManageProfileStatusTone.Danger);
        AppendOutput($"NETWORK | fleet image sync blocked: {payloadCheck.Message}");
        return false;
    }

    private Task<bool> PushFleetSquadsAsync(bool silent = true)
    {
        return PushFleetMutationAsync(
            "api/fleets/squads",
            new FleetSquadsUpdateRequest(
                _fleetCode,
                BuildSquadSnapshots(),
                BuildFleetEventLogSnapshots()),
            "小队信息已同步",
            "小队信息同步失败",
            silent);
    }

    private async Task<bool> PullNetworkFleetsAsync(
        bool silent = false,
        FleetDirectoryRefreshBehavior refreshBehavior = FleetDirectoryRefreshBehavior.Reorder)
    {
        if (!CanSynchronizeUserData)
        {
            return false;
        }

        var isPassiveRefresh = refreshBehavior == FleetDirectoryRefreshBehavior.PreserveVisibleOrder;
        if (isPassiveRefresh && _fleetDirectoryState.IsVisibleLoadInProgress)
        {
            return false;
        }

        var session = _accountSessionCoordinator.Capture();
        var preservedVisibleOrder = isPassiveRefresh
            ? _networkFleets
                .Select(card => card.Snapshot.Code)
                .Where(code => !string.IsNullOrWhiteSpace(code))
                .ToArray()
            : [];
        var requestVersion = isPassiveRefresh
            ? _fleetDirectoryState.BeginPassiveRefresh()
            : _fleetDirectoryState.BeginLoad(_allNetworkFleets.Count > 0);
        if (!isPassiveRefresh)
        {
            RefreshFleetDirectoryViewState();
        }
        try
        {
            var applicationsTask = PullMyFleetApplicationsAsync(silent: true);
            var membershipTask = IsLoggedIn
                ? _relayClient.GetFromJsonAsync<FleetMembershipResponse>("api/fleets/membership")
                : Task.FromResult<FleetMembershipResponse?>(null);
            var snapshotsTask = _relayClient.GetFromJsonAsync<NetworkFleetSnapshot[]>("api/fleets");
            await Task.WhenAll(applicationsTask, membershipTask, snapshotsTask);
            var membership = await membershipTask;
            var snapshots = await snapshotsTask ?? [];
            if (!_accountSessionCoordinator.IsCurrent(session))
            {
                return false;
            }
            var fetchedFleetCards = new List<NetworkFleetCard>();
            var currentFleetExistsOnRelay = false;
            NetworkFleetSnapshot? currentFleetSnapshot = null;
            var retainedPendingFleet = false;
            foreach (var snapshot in snapshots)
            {
                var displaySnapshot = snapshot;
                if (IsSameFleet(snapshot.Name) || IsSameFleet(snapshot.Code))
                {
                    currentFleetExistsOnRelay = true;
                    currentFleetSnapshot = snapshot;
                }

                fetchedFleetCards.Add(NetworkFleetCard.FromSnapshot(
                    displaySnapshot,
                    _fleetName,
                    _fleetCode,
                    _hasFleet,
                    _pendingFleetApplicationCodes));
            }

            if (!string.IsNullOrWhiteSpace(membership?.FleetCode))
            {
                var membershipSnapshot = snapshots.FirstOrDefault(snapshot =>
                    snapshot.Code.Equals(membership.FleetCode, StringComparison.OrdinalIgnoreCase));
                if (membershipSnapshot is not null)
                {
                    currentFleetExistsOnRelay = true;
                    currentFleetSnapshot = membershipSnapshot;
                    if (!_hasFleet || !IsSameFleet(membershipSnapshot.Code))
                    {
                        _hasFleet = true;
                        _isCreatingFleet = false;
                        MarkFleetMembershipChanged();
                        LocalFleetText.Text = $"{membershipSnapshot.Name} [{membershipSnapshot.Code}]";
                        UpdateFleetEntryPanels();
                    }
                }
            }

            if (!_fleetDirectoryState.IsLatestRequest(requestVersion))
            {
                return false;
            }

            if (currentFleetSnapshot is not null)
            {
                _fleetDirectorySyncPending = false;
                if (FleetPassiveRefreshPolicy.ShouldMerge(
                        currentFleetSnapshot.Code,
                        currentFleetSnapshot.LastUpdated,
                        _latestFleetSnapshotCode,
                        _latestFleetSnapshotUpdatedAtUtc))
                {
                    MergeNetworkFleetState(currentFleetSnapshot);
                }
            }

            if (_hasFleet && !currentFleetExistsOnRelay)
            {
                retainedPendingFleet = true;
                MarkFleetDirectorySyncPending();
                await RetryPendingFleetDirectorySyncAsync(silent: true);
                if (fetchedFleetCards.All(card =>
                        !IsSameFleet(card.Snapshot.Name) &&
                        !IsSameFleet(card.Snapshot.Code)))
                {
                    var localSnapshot = BuildLocalFleetSnapshot(
                        includeDirectoryImages: true,
                        includeRepeatedImages: true);
                    fetchedFleetCards.Insert(0, NetworkFleetCard.FromSnapshot(
                        localSnapshot,
                        _fleetName,
                        _fleetCode,
                        _hasFleet,
                        _pendingFleetApplicationCodes));
                }
                if (!silent)
                {
                    NetworkStatusText.Text = "服务器暂未确认当前舰队，已保留本地舰队缓存。";
                    AppendOutput("NETWORK | current fleet missing on relay; retained local fleet cache");
                }
            }

            _allNetworkFleets.Clear();
            _allNetworkFleets.AddRange(fetchedFleetCards);
            _ = _fleetDirectoryCache.SaveAsync(snapshots);
            _fleetDirectoryState.CompleteLoad(requestVersion, fetchedFleetCards.Count);
            ApplyFleetSearchFilter(preservedVisibleOrder);
            RefreshFleetDirectoryViewState();

            if (!silent)
            {
                NetworkStatusText.Text = retainedPendingFleet
                        ? "正在等待服务器确认当前舰队"
                        : $"已拉取：{snapshots.Length} 个舰队";
                AppendOutput($"NETWORK | pulled fleets={snapshots.Length}");
            }
            HideNetworkSyncIssueDialog();
            _accountSessionRequiresFreshSync = false;

            return true;
        }
        catch (Exception ex)
        {
            if (!_accountSessionCoordinator.IsCurrent(session))
            {
                return false;
            }

            if (_fleetDirectoryState.IsLatestRequest(requestVersion) && _allNetworkFleets.Count == 0)
            {
                var cachedSnapshots = await _fleetDirectoryCache.LoadAsync();
                if (_fleetDirectoryState.IsLatestRequest(requestVersion) && cachedSnapshots.Count > 0)
                {
                    _allNetworkFleets.AddRange(cachedSnapshots.Select(snapshot => NetworkFleetCard.FromSnapshot(
                        snapshot,
                        _fleetName,
                        _fleetCode,
                        _hasFleet,
                        _pendingFleetApplicationCodes)));
                }
            }

            if (HandleAuthorizationFailure(ex, "拉取舰队", silent))
            {
                if (!isPassiveRefresh)
                {
                    _fleetDirectoryState.FailLoad(
                        requestVersion,
                        _allNetworkFleets.Count > 0,
                        "登录状态已失效，请重新登录后刷新舰队目录。");
                    RefreshFleetDirectoryViewState();
                    ApplyFleetSearchFilter();
                }
                return false;
            }

            if (!isPassiveRefresh)
            {
                _fleetDirectoryState.FailLoad(
                    requestVersion,
                    _allNetworkFleets.Count > 0,
                    "舰队目录加载失败，请检查网络后重试。");
                RefreshFleetDirectoryViewState();
                ApplyFleetSearchFilter();
            }

            if (!silent)
            {
                var issue = FormatNetworkSyncIssue("拉取舰队失败", ex);
                NetworkStatusText.Text = issue;
                AppendOutput($"NETWORK | pull fleets failed={ex.Message}");
                ShowNetworkSyncIssueDialog(issue);
            }

            return false;
        }
    }

    private async Task PullMyFleetApplicationsAsync(bool silent = true)
    {
        if (!IsLoggedIn)
        {
            _pendingFleetApplicationCodes.Clear();
            return;
        }

        var session = _accountSessionCoordinator.Capture();
        try
        {
            var applications = await _relayClient.GetFromJsonAsync<FleetJoinApplicationStatusResponse[]>(
                "api/fleets/applications/mine") ?? [];
            if (!_accountSessionCoordinator.IsCurrent(session))
            {
                return;
            }
            _pendingFleetApplicationCodes.Clear();
            foreach (var application in applications)
            {
                if (!string.IsNullOrWhiteSpace(application.FleetCode))
                {
                    _pendingFleetApplicationCodes.Add(application.FleetCode.Trim());
                }
            }
        }
        catch (Exception ex)
        {
            if (HandleAuthorizationFailure(ex, "拉取加入申请", silent))
            {
                return;
            }

            if (!silent)
            {
                NetworkStatusText.Text = UserFacingError.Describe(ex, "加入申请暂时无法同步，请稍后重试。");
                AppendOutput($"NETWORK | pull applications failed={ex.Message}");
            }
        }
    }

    private async Task MeasureRelayLatencyAsync()
    {
        if (_isRelayLatencyProbeRunning ||
            _syncPrivacySettings.PresenceVisibilityMode == PlayerPresenceVisibilityMode.Offline)
        {
            return;
        }

        _isRelayLatencyProbeRunning = true;
        try
        {
            ApplyRelayHealthProbeResult(await ProbeRelayHealthAsync());
        }
        finally
        {
            _isRelayLatencyProbeRunning = false;
            RefreshFleetClockDisplays();
        }
    }

    private async Task<RelayHealthProbeResult> ProbeRelayHealthAsync()
    {
        var stopwatch = Stopwatch.StartNew();
        try
        {
            using var response = await _networkClient.GetAsync(
                BuildNetworkUri("health"),
                HttpCompletionOption.ResponseHeadersRead);
            RelayHealthResponseContract? health = null;
            try
            {
                health = await response.Content.ReadFromJsonAsync<RelayHealthResponseContract>();
            }
            catch (Exception ex) when (ex is JsonException or NotSupportedException)
            {
                // Legacy relays may return a health payload without the new resource contract.
            }

            var state = RelayHealthPresentationPolicy.Resolve(health?.Status, response.StatusCode);
            var error = response.IsSuccessStatusCode
                ? null
                : new HttpRequestException(
                    $"服务器健康检查返回 {(int)response.StatusCode}。",
                    null,
                    response.StatusCode);
            return new RelayHealthProbeResult(
                state,
                Math.Max(1, stopwatch.ElapsedMilliseconds),
                response.StatusCode,
                error);
        }
        catch (Exception ex)
        {
            return new RelayHealthProbeResult(
                RelayServiceHealthState.Unreachable,
                -1,
                Error: ex);
        }
    }
}
