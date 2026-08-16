using Microsoft.Win32;
using StarBridge.Core.ShipMedia;
using StarBridge.Core.TrustSafety;
using System.Globalization;
using System.IO;
using System.Net.Http;
using System.Net.Http.Json;
using System.Windows;

namespace StarBridge.Desktop;

internal sealed record ShipImageReportTarget(
    string MediaId,
    string? ShipInstanceId,
    string ShipName,
    string OwnerDisplayName,
    string? OwnerAccountId);

public partial class MainWindow
{
    private HangarManagementView? _hangarManagementView;
    private ShipImageReportTarget? _personalProfileRecentShipReportTarget;

    private async void HeaderHangarMenuItem_Click(object sender, RoutedEventArgs e) =>
        await NavigateToHangarPageAsync();

    private async Task NavigateToHangarPageAsync()
    {
        if (!CanSynchronizeUserData)
        {
            await ShowAppNoticeAsync(
                "我的机库暂不可用",
                "完成登录与身份验证后即可管理机库和专属图片。",
                "专属图片会绑定到你的舰船实例，并在允许展示机库的页面中使用。");
            return;
        }

        if (!TryLeaveOverlayEditorTab())
        {
            return;
        }

        _hangarManagementView ??= new HangarManagementView(
            LoadHangarManagementRowsAsync,
            ScanHangarFromManagementAsync,
            UploadShipMediaAsync,
            RemoveShipMediaAsync,
            row => ShowShipImagePreview(row.ImagePath, row.DisplayName),
            OpenHangarPrivacySettings);
        HangarPageHost.Content = _hangarManagementView;
        MainTabs.SelectedItem = HangarTab;
        SetActiveNav(null);
        await _hangarManagementView.RefreshAsync();
    }

    private void OpenHangarPrivacySettings()
    {
        var previousTab = MainTabs.SelectedItem;
        MainTabs.SelectedItem = SettingsTab;
        SetActiveNav(HeaderSettingsButton);
        ShowPersonalSection(PersonalSection.AppSettings);
        ShowPersonalDashboardSection(PersonalDashboardSection.SyncPrivacy);
        QueueMainPageReveal(previousTab);
    }

    private void ResetHangarManagementPage()
    {
        if (ReferenceEquals(MainTabs?.SelectedItem, HangarTab))
        {
            MainTabs.SelectedItem = PersonalTab;
            SetActiveNav(PersonalNavButton);
        }

        if (HangarPageHost is not null)
        {
            HangarPageHost.Content = null;
        }

        _hangarManagementView = null;
    }

    private async Task<HangarManagementSnapshot> LoadHangarManagementRowsAsync()
    {
        await HangarImportedShipImageCache.UpgradeExistingAsync(
            _ownedShips.Select(ship => ship.Code));

        var catalog = await _relayClient.GetFromJsonAsync<ShipMediaCatalogContract>("api/ship-media/mine") ??
                      new ShipMediaCatalogContract([], DateTimeOffset.UtcNow);
        var changed = OwnedShipMediaCatalogReconciler.Reconcile(_ownedShips, catalog.Items);

        await EnsureShipMediaCachedAsync(catalog.Items.Select(item => item.MediaId));
        if (changed)
        {
            SaveOwnedShips();
        }

        var favoriteCodes = (_personalProfileSettings.FavoriteShipCodes ?? [])
            .Where(code => !string.IsNullOrWhiteSpace(code))
            .Select(code => code.Trim())
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        var rows = _ownedShips
            .OrderBy(ship => ship.DisplayName, StringComparer.CurrentCultureIgnoreCase)
            .Select(ship =>
            {
                var catalogEntry = ShipCatalog.Find(ship.Code, ship.DisplayName);
                var fallback = ShipCatalog.ResolveImagePath(
                    catalogEntry,
                    ship.Code,
                    ship.DisplayName);
                var category = GetOwnedShipRoleCategory(ship);
                var categoryVisual = GetFleetShipRoleVisual(category);
                var status = ShipCatalog.ResolveStatus(catalogEntry);
                var isFlyable = status.Contains("可飞", StringComparison.OrdinalIgnoreCase) ||
                                status.Contains("flight", StringComparison.OrdinalIgnoreCase) ||
                                status.Contains("flyable", StringComparison.OrdinalIgnoreCase);
                var isConcept = status.Contains("概念", StringComparison.OrdinalIgnoreCase) ||
                                status.Contains("concept", StringComparison.OrdinalIgnoreCase);
                _ = decimal.TryParse(
                    catalogEntry?.PriceUsd,
                    NumberStyles.Currency,
                    CultureInfo.InvariantCulture,
                    out var priceValue);
                return new HangarManagementShipRow(
                    ship.InstanceId ?? "",
                    ship.Code,
                    catalogEntry?.DisplayName(_language) ?? ship.DisplayName,
                    FormatFleetShipEnglishName(ship.Code, catalogEntry?.EnglishName),
                    ship.Source,
                    ResolveShipDisplayImagePath(ship.CustomImageMediaId, fallback),
                    ship.CustomImageMediaId,
                    !string.IsNullOrWhiteSpace(ship.InstanceId),
                    string.IsNullOrWhiteSpace(catalogEntry?.Spec) ? "规格待补充" : catalogEntry.Spec,
                    string.IsNullOrWhiteSpace(catalogEntry?.Role)
                        ? "定位待补充"
                        : catalogEntry.RoleDisplay(_language),
                    status,
                    catalogEntry?.PriceDisplay ?? "未公布",
                    priceValue,
                    string.IsNullOrWhiteSpace(ship.ImportedAtDisplay) ? "暂无记录" : ship.ImportedAtDisplay,
                    FormatOwnedShipSyncedAt(ship),
                    GetOwnedShipPreviewTimestamp(ship),
                    categoryVisual.Key,
                    categoryVisual.DisplayName,
                    (int)category,
                    CreateSolidBrush(categoryVisual.ColorHex),
                    GetPersonalHangarStatusBrush(status),
                    isFlyable,
                    isConcept,
                    favoriteCodes.Contains(ship.Code),
                    ship.SyncedAt != default && ship.SyncedAt != DateTimeOffset.MinValue,
                    ship.CustomImageCropFrame.FocusX,
                    ship.CustomImageCropFrame.FocusY,
                    ship.CustomImageCropFrame.Zoom);
            })
            .ToArray();

        var latestReadAt = _ownedShips
            .Select(ship => ship.ImportedAt)
            .Where(value => value != default && value != DateTimeOffset.MinValue)
            .OrderByDescending(value => value)
            .FirstOrDefault();
        var latestSyncedShip = _ownedShips
            .Where(ship =>
                (ship.SyncedAt != default && ship.SyncedAt != DateTimeOffset.MinValue) ||
                (ship.AddedToDatabaseAt != default && ship.AddedToDatabaseAt != DateTimeOffset.MinValue))
            .OrderByDescending(GetOwnedShipPreviewTimestamp)
            .FirstOrDefault();
        var favoriteCount = favoriteCodes.Count(code =>
            rows.Any(row => string.Equals(row.Code, code, StringComparison.OrdinalIgnoreCase)));

        return new HangarManagementSnapshot(
            rows,
            latestReadAt == default
                ? "尚未扫描"
                : latestReadAt.ToLocalTime().ToString("yyyy-MM-dd HH:mm", CultureInfo.InvariantCulture),
            latestSyncedShip is null ? "等待首次同步" : FormatOwnedShipSyncedAt(latestSyncedShip),
            _syncPrivacySettings.SyncEnabled,
            _syncPrivacySettings.SyncEnabled && _syncPrivacySettings.PersonalHangarVisible,
            favoriteCount);
    }

    private async Task ScanHangarFromManagementAsync()
    {
        if (await OpenHangarReaderAsync())
        {
            await PushLocalSnapshotAsync(silent: true);
        }
    }

    private async Task<bool> UploadShipMediaAsync(HangarManagementShipRow row)
    {
        if (string.IsNullOrWhiteSpace(row.InstanceId))
        {
            await ShowAppNoticeAsync(
                "需要重新扫描机库",
                "这艘舰船还没有可用于绑定图片的实例信息。",
                "请点击“扫描官网机库”，完成后再上传专属图片。");
            return false;
        }

        var dialog = new Microsoft.Win32.OpenFileDialog
        {
            Title = $"为 {row.DisplayName} 选择专属图片",
            Filter = "图片文件 (*.png;*.jpg;*.jpeg;*.bmp;*.gif;*.tif;*.tiff;*.webp;*.heic;*.heif;*.avif)|*.png;*.jpg;*.jpeg;*.bmp;*.gif;*.tif;*.tiff;*.webp;*.heic;*.heif;*.avif|所有文件 (*.*)|*.*",
            CheckFileExists = true,
            Multiselect = false
        };
        if (dialog.ShowDialog(this) != true)
        {
            return false;
        }

        var edited = await ApplicationLayerHost.ShowModalAsync<ShipImageEditResult>(
            "编辑舰船图片",
            $"{row.DisplayName} · 上传前预览",
            complete => new ShipImageEditorView(
                dialog.FileName,
                row.DisplayName,
                complete),
            maxWidth: 980,
            maxHeight: 760);
        if (edited is null)
        {
            return false;
        }

        var imageBytes = edited.EncodedBytes;

        var upload = new ShipMediaUploadRequestContract(
            row.InstanceId,
            row.Code,
            row.DisplayName,
            Convert.ToBase64String(imageBytes),
            Guid.NewGuid().ToString("N"),
            edited.CropFrame.FocusX,
            edited.CropFrame.FocusY,
            edited.CropFrame.Zoom);
        try
        {
            using var response = await _relayClient.PostJsonAsync("api/ship-media", upload);
            if (!response.IsSuccessStatusCode)
            {
                throw new InvalidOperationException(await ReadResponseErrorAsync(response));
            }

            var result = await response.Content.ReadFromJsonAsync<ShipMediaUploadResponseContract>() ??
                         throw new InvalidDataException("服务器没有返回图片信息。");
            await ShipMediaCache.StoreAsync(result.Media.MediaId, imageBytes);
            UpdateOwnedShipMedia(row.InstanceId, result.Media.MediaId, result.Media.CropFrame);
            SaveOwnedShips();
            await PushLocalSnapshotAsync(silent: true);
            RefreshPersonalProfileContent();
            return true;
        }
        catch (Exception ex)
        {
            await ShowAppNoticeAsync(
                "图片未上传",
                "暂时无法保存这张专属图片，请稍后重试。",
                UserFacingError.Describe(ex, "请检查网络连接后重试。"));
            return false;
        }
    }

    private async Task<bool> RemoveShipMediaAsync(HangarManagementShipRow row)
    {
        if (string.IsNullOrWhiteSpace(row.CustomImageMediaId))
        {
            return false;
        }

        var confirmed = await ShowAppConfirmationAsync(
            "移除专属图片？",
            $"将移除 {row.DisplayName} 当前使用的专属图片。",
            "移除后会恢复为本地舰船图库图片；已经提交的举报记录仍会保留用于审核。",
            "移除图片",
            "保留图片");
        if (!confirmed)
        {
            return false;
        }

        try
        {
            using var request = new HttpRequestMessage(
                HttpMethod.Delete,
                _relayClient.BuildUri($"api/ship-media/{Uri.EscapeDataString(row.CustomImageMediaId)}"));
            using var response = await _relayClient.SendAsync(request);
            if (!response.IsSuccessStatusCode)
            {
                throw new InvalidOperationException(await ReadResponseErrorAsync(response));
            }

            ShipMediaCache.Remove(row.CustomImageMediaId);
            UpdateOwnedShipMedia(row.InstanceId, null, ShipImageCropFrame.Default);
            SaveOwnedShips();
            await PushLocalSnapshotAsync(silent: true);
            RefreshPersonalProfileContent();
            return true;
        }
        catch (Exception ex)
        {
            await ShowAppNoticeAsync(
                "图片未移除",
                "暂时无法移除这张专属图片，请稍后重试。",
                UserFacingError.Describe(ex, "请检查网络连接后重试。"));
            return false;
        }
    }

    private void UpdateOwnedShipMedia(
        string instanceId,
        string? mediaId,
        ShipImageCropFrame cropFrame)
    {
        var normalized = ShipImageCropFrame.Normalize(cropFrame.FocusX, cropFrame.FocusY, cropFrame.Zoom);
        for (var index = 0; index < _ownedShips.Count; index++)
        {
            if (_ownedShips[index].InstanceId?.Equals(instanceId, StringComparison.OrdinalIgnoreCase) == true)
            {
                _ownedShips[index] = _ownedShips[index] with
                {
                    CustomImageMediaId = mediaId,
                    CustomImageCropFocusX = normalized.FocusX,
                    CustomImageCropFocusY = normalized.FocusY,
                    CustomImageCropZoom = normalized.Zoom
                };
                return;
            }
        }
    }

    private string ResolveShipDisplayImagePath(string? mediaId, string fallback)
    {
        return ShipMediaCache.Resolve(mediaId) ?? fallback;
    }

    private void ShowShipImagePreview(
        string? imagePath,
        string shipName,
        ShipImageReportTarget? reportTarget = null)
    {
        var view = new ShipImagePreviewView(
            imagePath,
            shipName,
            reportTarget is null
                ? null
                : () => SubmitShipImageReportAsync(reportTarget));
        ApplicationLayerHost.ShowWorkspace(
            shipName,
            "舰船图片 · 完整查看",
            view,
            dismissOnBackdrop: true);
    }

    private void FleetShipImagePreview_MouseLeftButtonUp(
        object sender,
        System.Windows.Input.MouseButtonEventArgs e)
    {
        if (sender is FrameworkElement { DataContext: FleetShipInventoryRow ship })
        {
            e.Handled = true;
            OpenFleetShipDetails(ship);
        }
    }

    private void PersonalProfileRecentShipImage_MouseLeftButtonUp(
        object sender,
        System.Windows.Input.MouseButtonEventArgs e)
    {
        if (sender is FrameworkElement { Tag: string path } && !string.IsNullOrWhiteSpace(path))
        {
            e.Handled = true;
            ShowShipImagePreview(
                path,
                PersonalProfileHangarRecentShipNameText.Text,
                _personalProfileRecentShipReportTarget);
        }
    }

    private async Task<bool> EnsureShipMediaCachedAsync(IEnumerable<string?> mediaIds)
    {
        var missing = mediaIds
            .Where(mediaId => !string.IsNullOrWhiteSpace(mediaId) && ShipMediaCache.Resolve(mediaId) is null)
            .Select(mediaId => mediaId!.Trim())
            .Where(mediaId => Guid.TryParseExact(mediaId, "N", out _))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .Take(64)
            .ToArray();
        if (missing.Length == 0)
        {
            return false;
        }

        using var gate = new SemaphoreSlim(4, 4);
        var downloaded = 0;
        await Task.WhenAll(missing.Select(async mediaId =>
        {
            await gate.WaitAsync();
            try
            {
                using var response = await _relayClient.GetAsync($"api/ship-media/{Uri.EscapeDataString(mediaId)}");
                if (!response.IsSuccessStatusCode ||
                    response.Content.Headers.ContentLength is > ShipMediaPolicy.MaximumImageBytes)
                {
                    return;
                }

                await using var source = await response.Content.ReadAsStreamAsync();
                using var target = new MemoryStream();
                var buffer = new byte[81920];
                while (true)
                {
                    var read = await source.ReadAsync(buffer);
                    if (read == 0)
                    {
                        break;
                    }

                    if (target.Length + read > ShipMediaPolicy.MaximumImageBytes)
                    {
                        return;
                    }

                    await target.WriteAsync(buffer.AsMemory(0, read));
                }

                await ShipMediaCache.StoreAsync(mediaId, target.ToArray());
                Interlocked.Increment(ref downloaded);
            }
            catch
            {
                // A missing remote image falls back to the installed local ship catalog.
            }
            finally
            {
                gate.Release();
            }
        }));
        return downloaded > 0;
    }

    private async Task CacheNetworkShipMediaAsync(
        IReadOnlyCollection<NetworkPlayerSnapshot> snapshots,
        AccountSessionLease session)
    {
        var downloaded = await EnsureShipMediaCachedAsync(
            snapshots.SelectMany(snapshot => snapshot.OwnedShips ?? [])
                .Select(ship => ship.CustomImageMediaId));
        if (!downloaded || !_accountSessionCoordinator.IsCurrent(session))
        {
            return;
        }

        RefreshFleetShipInventory();
        RefreshPersonalProfileContent();
    }

    private async Task SubmitShipImageReportAsync(ShipImageReportTarget ship)
    {
        if (!CanSynchronizeUserData || string.IsNullOrWhiteSpace(ship.MediaId) ||
            string.Equals(ship.OwnerAccountId, _accountId, StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        var submission = await ApplicationLayerHost.ShowModalAsync<ReportUserSubmission>(
            "举报舰船图片",
            "选择原因并说明图片问题",
            complete => new ReportUserView(
                $"{ship.ShipName} · {ship.OwnerDisplayName}",
                complete,
                title: "举报舰船图片",
                description: "请选择最符合图片实际情况的原因。举报会附带该图片的媒体标识，便于审核人员核对。"),
            maxWidth: 620,
            maxHeight: 640);
        if (submission is null)
        {
            return;
        }

        var request = new CreateReportRequestContract(
            ReportTargetTypes.ShipImage,
            ship.MediaId,
            $"{ship.ShipName} · 舰船图片",
            ReportEvidenceCategories.ShipImage,
            ship.ShipInstanceId,
            submission.Reason,
            submission.Details,
            Guid.NewGuid().ToString("N"));
        try
        {
            using var response = await _relayClient.PostJsonAsync("api/reports", request);
            if (!response.IsSuccessStatusCode)
            {
                throw new InvalidOperationException(await ReadResponseErrorAsync(response));
            }

            await RefreshNotificationCenterAsync(showErrors: false);
            await ShowAppNoticeAsync(
                "举报已提交",
                "我们已收到对这张舰船图片的举报。",
                "你可以在通知中心的“我的举报”中查看处理进度。");
        }
        catch (Exception ex)
        {
            await ShowAppNoticeAsync(
                "举报未提交",
                "暂时无法提交这份举报，请稍后重试。",
                UserFacingError.Describe(ex, "请检查网络连接后重试。"));
        }
    }

    private async Task<string?> LoadShipMediaForModerationAsync(string mediaId)
    {
        var cached = ShipMediaCache.Resolve(mediaId);
        if (!string.IsNullOrWhiteSpace(cached))
        {
            return cached;
        }

        if (!Guid.TryParseExact(mediaId?.Trim(), "N", out _))
        {
            return null;
        }

        using var response = await _relayClient.GetAsync(
            $"api/admin/ship-media/{Uri.EscapeDataString(mediaId.Trim())}");
        if (!response.IsSuccessStatusCode ||
            response.Content.Headers.ContentLength is > ShipMediaPolicy.MaximumImageBytes)
        {
            return null;
        }

        await using var source = await response.Content.ReadAsStreamAsync();
        using var target = new MemoryStream();
        var buffer = new byte[81920];
        while (true)
        {
            var read = await source.ReadAsync(buffer);
            if (read == 0)
            {
                break;
            }

            if (target.Length + read > ShipMediaPolicy.MaximumImageBytes)
            {
                return null;
            }

            await target.WriteAsync(buffer.AsMemory(0, read));
        }

        return await ShipMediaCache.StoreAsync(mediaId, target.ToArray());
    }

    private async void FleetShipImageReportButton_Click(object sender, RoutedEventArgs e)
    {
        e.Handled = true;
        if (sender is FrameworkElement { Tag: FleetShipInventoryRow ship })
        {
            await SubmitShipImageReportAsync(new ShipImageReportTarget(
                ship.CustomImageMediaId!,
                ship.ShipInstanceId,
                ship.ShipName,
                ship.OwnerDisplay,
                ship.OwnerAccountId));
        }
    }

    private async void PersonalProfileRecentShipImageReportButton_Click(object sender, RoutedEventArgs e)
    {
        if (_personalProfileRecentShipReportTarget is not null)
        {
            await SubmitShipImageReportAsync(_personalProfileRecentShipReportTarget);
        }
    }

    private async void InGameMenuCoordinator_FleetShipImageReportRequested(
        object? sender,
        InGameFleetShipImageReportRequestedEventArgs e)
    {
        var ship = e.Ship;
        if (!string.IsNullOrWhiteSpace(ship.CustomImageMediaId))
        {
            if (!IsVisible)
            {
                Show();
            }

            if (WindowState == WindowState.Minimized)
            {
                WindowState = WindowState.Normal;
            }

            Activate();
            await SubmitShipImageReportAsync(new ShipImageReportTarget(
                ship.CustomImageMediaId,
                ship.ShipInstanceId,
                ship.Name,
                ship.Owner,
                ship.OwnerAccountId));
        }
    }
}
