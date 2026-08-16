using System.Globalization;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using StarBridge.Desktop.Theming;
using Brushes = System.Windows.Media.Brushes;

namespace StarBridge.Desktop;

public partial class MainWindow
{
    private void LoadOwnedShips()
    {
        _ownedShips.Clear();
        if (!IsLoggedIn && !_authenticationExpired)
        {
            UpdateShipDatabaseSummary();
            RefreshFleetShipInventory();
            RefreshPersonalProfileContent();
            return;
        }

        var migratedDisplayNames = false;
        foreach (var ship in ShipDatabaseStore.Load(GetShipDatabaseOwnerKey()))
        {
            var normalizedShip = NormalizeOwnedShipDisplayName(ship);
            migratedDisplayNames |= !string.Equals(normalizedShip.Code, ship.Code, StringComparison.Ordinal) ||
                                    !string.Equals(normalizedShip.DisplayName, ship.DisplayName, StringComparison.Ordinal) ||
                                    !string.Equals(normalizedShip.Source, ship.Source, StringComparison.Ordinal);
            _ownedShips.Add(normalizedShip);
        }

        if (migratedDisplayNames)
        {
            ShipDatabaseStore.Save(GetShipDatabaseOwnerKey(), _ownedShips);
        }

        UpdateShipDatabaseSummary();
        RefreshFleetShipInventory();
        RefreshPersonalProfileContent();
    }

    private void SaveOwnedShips()
    {
        ShipDatabaseStore.Save(GetShipDatabaseOwnerKey(), _ownedShips);
        ReplaceRemoteFleetShipsForOwner(_localPlayer, _callsign, [], refresh: false);
        RefreshFleetShipInventory();
        StartProfileSyncDebounce();
    }

    private void ReplaceOwnedShipsFromImport(IEnumerable<OwnedShipRecord> importedShips)
    {
        var now = DateTimeOffset.UtcNow;
        var existingByInstance = _ownedShips
            .Where(ship => !string.IsNullOrWhiteSpace(ship.InstanceId))
            .GroupBy(ship => ship.InstanceId!, StringComparer.OrdinalIgnoreCase)
            .ToDictionary(group => group.Key, group => group.First(), StringComparer.OrdinalIgnoreCase);
        var existingByCode = _ownedShips
            .GroupBy(ship => ShipNameLocalizer.NormalizeCode(ship.Code), StringComparer.OrdinalIgnoreCase)
            .ToDictionary(group => group.Key, group => new Queue<OwnedShipRecord>(group), StringComparer.OrdinalIgnoreCase);

        _ownedShips.Clear();
        foreach (var ship in importedShips)
        {
            var normalizedShip = NormalizeOwnedShipDisplayName(ship);
            var code = ShipNameLocalizer.NormalizeCode(normalizedShip.Code);
            OwnedShipRecord? existing = null;
            var hasExisting = !string.IsNullOrWhiteSpace(normalizedShip.InstanceId) &&
                              existingByInstance.TryGetValue(normalizedShip.InstanceId, out existing);
            if (!hasExisting && existingByCode.TryGetValue(code, out var legacyMatches) && legacyMatches.Count > 0)
            {
                existing = legacyMatches.Dequeue();
                hasExisting = true;
            }
            var addedToDatabaseAt = hasExisting
                ? NormalizeShipTimestamp(existing!.AddedToDatabaseAt, now)
                : now;
            var syncedAt = hasExisting && !HasOwnedShipChanged(existing!, normalizedShip)
                ? NormalizeShipTimestamp(existing!.SyncedAt, addedToDatabaseAt)
                : default;
            _ownedShips.Add(normalizedShip with
            {
                AddedToDatabaseAt = addedToDatabaseAt,
                SyncedAt = syncedAt,
                CustomImageMediaId = hasExisting ? existing!.CustomImageMediaId : normalizedShip.CustomImageMediaId,
                CustomImageCropFocusX = hasExisting ? existing!.CustomImageCropFocusX : normalizedShip.CustomImageCropFocusX,
                CustomImageCropFocusY = hasExisting ? existing!.CustomImageCropFocusY : normalizedShip.CustomImageCropFocusY,
                CustomImageCropZoom = hasExisting ? existing!.CustomImageCropZoom : normalizedShip.CustomImageCropZoom
            });
        }
    }

    private OwnedShipRecord NormalizeOwnedShipDisplayName(OwnedShipRecord ship)
    {
        var normalizedCode = ShipNameLocalizer.NormalizeCode(ship.Code);
        return ship with
        {
            Code = normalizedCode,
            DisplayName = HangarShipImporter.ResolveShipDisplayName(normalizedCode, _language),
            Source = HangarShipImporter.ResolveShipSourceDisplay(ship.Source, ship.DisplayName, _language)
        };
    }

    private static bool HasOwnedShipChanged(OwnedShipRecord existing, OwnedShipRecord imported)
    {
        return !ShipNameLocalizer.NormalizeCode(existing.Code).Equals(
                   ShipNameLocalizer.NormalizeCode(imported.Code),
                   StringComparison.OrdinalIgnoreCase) ||
               !string.Equals(existing.DisplayName, imported.DisplayName, StringComparison.Ordinal) ||
               !string.Equals(existing.Source, imported.Source, StringComparison.Ordinal) ||
               !IsSameShipTimestamp(existing.ImportedAt, imported.ImportedAt);
    }

    private static bool IsSameShipTimestamp(DateTimeOffset left, DateTimeOffset right)
    {
        if ((left == default || left == DateTimeOffset.MinValue) &&
            (right == default || right == DateTimeOffset.MinValue))
        {
            return true;
        }

        return left.ToUniversalTime().Date == right.ToUniversalTime().Date;
    }

    private string GetShipDatabaseOwnerKey()
    {
        if (!string.IsNullOrWhiteSpace(_accountName))
        {
            return $"account:{_accountName}";
        }

        if (!string.IsNullOrWhiteSpace(_localPlayerId))
        {
            return _localPlayerId;
        }

        if (!string.IsNullOrWhiteSpace(_localPlayer))
        {
            return _localPlayer;
        }

        return "local";
    }

    private void UpdateShipDatabaseSummary(int? matchedCodes = null, int? matchedNames = null)
    {
        RefreshPersonalProfileHangarSummary();
        if (!IsLoggedIn && !_authenticationExpired)
        {
            ShipDatabaseStatusText.Text = "请登录后使用舰船数据库";
            if (PersonalHangarShipCountText is not null)
            {
                PersonalHangarShipCountText.Text = "0 艘";
                PersonalHangarTotalValueText.Text = "未公布";
                PersonalHangarLastReadText.Text = "登录后显示";
                PersonalHangarLastSyncText.Text = "等待登录";
                PersonalHangarShareText.Text = "未启用";
                PersonalHangarShareText.Foreground = FindBrush("MutedTextBrush", Brushes.LightSlateGray);
                PersonalHangarShareBadge.Background = CreateSolidBrush("#111920");
                PersonalHangarShareBadge.BorderBrush = CreateSolidBrush("#3A4C58");
                PersonalHangarSyncStateText.Text = "等待登录";
                PersonalHangarSyncStateText.Foreground = FindBrush("MutedTextBrush", Brushes.LightSlateGray);
                PersonalHangarSyncStateBadge.Background = CreateSolidBrush("#111920");
                PersonalHangarSyncStateBadge.BorderBrush = CreateSolidBrush("#3A4C58");
            }
            RefreshPersonalHangarDistribution();
            RefreshPersonalHangarPreview();
            RefreshPersonalHangarActivity();
            return;
        }

        var text = $"已验证舰船：{_ownedShips.Count}";
        if (matchedCodes is not null || matchedNames is not null)
        {
            text += $" / 官网舰船条目 {matchedCodes ?? 0} / 已识别 {matchedNames ?? 0}";
        }

        ShipDatabaseStatusText.Text = text;
        if (PersonalHangarShipCountText is not null)
        {
            var latestImportedAt = _ownedShips
                .Select(ship => ship.ImportedAt)
                .Where(value => value != default && value != DateTimeOffset.MinValue)
                .DefaultIfEmpty(DateTimeOffset.MinValue)
                .Max();

            var latestSync = _ownedShips
                .Select(ship => ship.SyncedAt)
                .Where(value => value != default && value != DateTimeOffset.MinValue)
                .DefaultIfEmpty(DateTimeOffset.MinValue)
                .Max();
            var allShipsSynced = _ownedShips.Count > 0 && _ownedShips.All(ship =>
                ship.SyncedAt != default && ship.SyncedAt != DateTimeOffset.MinValue);

            PersonalHangarShipCountText.Text = $"{_ownedShips.Count} 艘";
            PersonalHangarTotalValueText.Text = FormatPersonalHangarTotalValue();
            PersonalHangarLastReadText.Text = latestImportedAt == DateTimeOffset.MinValue
                ? "暂无入库记录"
                : latestImportedAt.ToLocalTime().ToString("yyyy-MM-dd");
            PersonalHangarLastSyncText.Text = latestSync == DateTimeOffset.MinValue
                ? "等待数据"
                : latestSync.ToLocalTime().ToString("yyyy-MM-dd HH:mm");
            var personalHangarShared = _syncPrivacySettings.SyncEnabled && _syncPrivacySettings.PersonalHangarVisible;
            PersonalHangarShareText.Text = !personalHangarShared
                ? "仅个人"
                : _ownedShips.Count == 0 ? "等待数据" : $"{FormatSyncPrivacyVisibilityScope(_syncPrivacySettings.EffectiveVisibilityScope)}可见";
            PersonalHangarShareText.Foreground = !personalHangarShared || _ownedShips.Count == 0
                ? FindBrush("MutedTextBrush", Brushes.LightSlateGray)
                : FindBrush("StatusSuccessBrush", Brushes.SpringGreen);
            PersonalHangarShareBadge.Background = !personalHangarShared || _ownedShips.Count == 0
                ? CreateSolidBrush("#111920")
                : CreateSolidBrush("#0D1D16");
            PersonalHangarShareBadge.BorderBrush = !personalHangarShared || _ownedShips.Count == 0
                ? CreateSolidBrush("#3A4C58")
                : CreateSolidBrush("#2F6A49");
            PersonalHangarSyncStateText.Text = !_syncPrivacySettings.SyncEnabled
                ? "同步关闭"
                : _ownedShips.Count == 0 ? "等待读取" : allShipsSynced ? "已同步" : "等待同步";
            PersonalHangarSyncStateText.Foreground = !_syncPrivacySettings.SyncEnabled
                ? FindBrush("MutedTextBrush", Brushes.LightSlateGray)
                : !allShipsSynced
                ? FindBrush("StatusWarningBrush", Brushes.Orange)
                : FindBrush("StatusSuccessBrush", Brushes.SpringGreen);
            PersonalHangarSyncStateBadge.Background = !allShipsSynced
                ? CreateSolidBrush("#1A160D")
                : CreateSolidBrush("#102536");
            PersonalHangarSyncStateBadge.BorderBrush = !allShipsSynced
                ? CreateSolidBrush("#6B5624")
                : CreateSolidBrush("#24506A");
        }
        RefreshPersonalHangarDistribution();
        RefreshPersonalHangarPreview();
        RefreshPersonalHangarActivity();
    }

    private string FormatPersonalHangarTotalValue()
    {
        var pricedShips = _ownedShips
            .Select(ship => ShipCatalog.Find(ship.Code, ship.DisplayName))
            .Where(catalog => catalog is not null && TryReadCatalogPrice(catalog.PriceUsd, out _))
            .Select(catalog =>
            {
                TryReadCatalogPrice(catalog!.PriceUsd, out var price);
                return price;
            })
            .ToArray();

        return pricedShips.Length == 0
            ? "未公布"
            : FormatFleetShipValue(pricedShips.Sum());
    }

    private static bool TryReadCatalogPrice(string? value, out decimal price)
    {
        var normalized = (value ?? "")
            .Replace("$", "", StringComparison.Ordinal)
            .Replace(",", "", StringComparison.Ordinal)
            .Trim();
        return decimal.TryParse(normalized, NumberStyles.Number, CultureInfo.InvariantCulture, out price);
    }

    private void RefreshPersonalHangarDistribution()
    {
        if (PersonalHangarDistributionBar is null)
        {
            return;
        }

        PersonalHangarDistributionBar.Children.Clear();
        PersonalHangarDistributionBar.ColumnDefinitions.Clear();
        _personalHangarDistributionRows.Clear();

        var counts = FleetShipRoleVisuals
            .Select(item => new
            {
                Name = item.DisplayName,
                item.Category,
                Brush = CreateSolidBrush(item.ColorHex),
                Count = _ownedShips.Count(ship => GetOwnedShipRoleCategory(ship) == item.Category)
            })
            .ToArray();

        foreach (var item in counts)
        {
            _personalHangarDistributionRows.Add(new PersonalHangarDistributionRow(
                item.Name,
                $"{item.Count} 艘",
                item.Brush));
        }

        var visibleSegments = counts.Where(item => item.Count > 0).ToArray();
        if (visibleSegments.Length == 0)
        {
            PersonalHangarDistributionBar.ColumnDefinitions.Add(new ColumnDefinition());
            PersonalHangarDistributionBar.Children.Add(new Border
            {
                Background = CreateSolidBrush("#111920"),
                BorderBrush = CreateSolidBrush("#173447"),
                BorderThickness = new Thickness(1)
            });
            return;
        }

        for (var index = 0; index < visibleSegments.Length; index++)
        {
            var segment = visibleSegments[index];
            PersonalHangarDistributionBar.ColumnDefinitions.Add(new ColumnDefinition
            {
                Width = new GridLength(Math.Max(1, segment.Count), GridUnitType.Star)
            });

            var border = new Border
            {
                Background = segment.Brush,
                Opacity = 0.72,
                Margin = index == 0 ? new Thickness(0) : new Thickness(4, 0, 0, 0)
            };
            Grid.SetColumn(border, index);
            PersonalHangarDistributionBar.Children.Add(border);
        }
    }

    private void RefreshPersonalHangarPreview()
    {
        _personalHangarPreviewRows.Clear();

        foreach (var ship in _ownedShips
                     .OrderByDescending(GetOwnedShipPreviewTimestamp)
                     .ThenBy(ship => ship.DisplayName, StringComparer.OrdinalIgnoreCase))
        {
            var catalog = ShipCatalog.Find(ship.Code, ship.DisplayName);
            var englishName = FormatFleetShipEnglishName(ship.Code, catalog?.EnglishName);
            var role = catalog?.RoleDisplay(_language) ?? "定位待补充";
            var value = string.IsNullOrWhiteSpace(ship.ValueDisplay) ? "未公布" : ship.ValueDisplay;
            var status = ShipCatalog.ResolveStatus(catalog);
            var category = GetOwnedShipRoleCategory(ship);

            _personalHangarPreviewRows.Add(new PersonalHangarPreviewRow(
                ship.DisplayName,
                englishName,
                role,
                value,
                status,
                string.IsNullOrWhiteSpace(ship.ImportedAtDisplay) ? "-" : ship.ImportedAtDisplay,
                FormatOwnedShipSyncedAt(ship),
                GetPersonalHangarCategoryBrush(category),
                CreateSolidBrush("#8FD8FF"),
                GetPersonalHangarStatusBrush(status)));
        }

        if (PersonalHangarPreviewEmptyText is not null)
        {
            PersonalHangarPreviewEmptyText.Visibility = _personalHangarPreviewRows.Count == 0
                ? Visibility.Visible
                : Visibility.Collapsed;
        }
    }

    private static string FormatOwnedShipSyncedAt(OwnedShipRecord ship)
    {
        if (!string.IsNullOrWhiteSpace(ship.SyncedAtDisplay))
        {
            return ship.SyncedAtDisplay;
        }

        if (ship.AddedToDatabaseAt != default && ship.AddedToDatabaseAt != DateTimeOffset.MinValue)
        {
            return ship.AddedToDatabaseAt.ToLocalTime().ToString("yyyy-MM-dd HH:mm", CultureInfo.InvariantCulture);
        }

        return "等待同步";
    }

    private static DateTimeOffset GetOwnedShipPreviewTimestamp(OwnedShipRecord ship)
    {
        if (ship.SyncedAt != default && ship.SyncedAt != DateTimeOffset.MinValue)
        {
            return ship.SyncedAt;
        }

        if (ship.AddedToDatabaseAt != default && ship.AddedToDatabaseAt != DateTimeOffset.MinValue)
        {
            return ship.AddedToDatabaseAt;
        }

        return ship.ImportedAt;
    }

    private FleetShipRoleCategory GetOwnedShipRoleCategory(OwnedShipRecord ship)
    {
        var catalog = ShipCatalog.Find(ship.Code, ship.DisplayName);
        // Classification must use the catalog's canonical role, not localized display text.
        return GetFleetShipRoleCategory(catalog?.Role ?? "");
    }

    private string BuildFleetPublicShipTypeSummary()
    {
        return string.Join(
            ';',
            _fleetShipInventory
                .GroupBy(ship => GetFleetShipRoleCategory(ship.ShipRole))
                .OrderBy(group => group.Key)
                .Select(group => $"{group.Key}={group.Count()}"));
    }

    private System.Windows.Media.Brush GetPersonalHangarCategoryBrush(FleetShipRoleCategory category)
    {
        return CreateSolidBrush(GetFleetShipRoleVisual(category).ColorHex);
    }

    private System.Windows.Media.Brush GetPersonalHangarStatusBrush(string status)
    {
        if (status.Contains("可飞", StringComparison.OrdinalIgnoreCase) ||
            status.Contains("flight", StringComparison.OrdinalIgnoreCase) ||
            status.Contains("flyable", StringComparison.OrdinalIgnoreCase))
        {
            return FindBrush("StatusSuccessBrush", Brushes.SpringGreen);
        }

        if (status.Contains("概念", StringComparison.OrdinalIgnoreCase) ||
            status.Contains("concept", StringComparison.OrdinalIgnoreCase))
        {
            return FindBrush("StatusWarningBrush", Brushes.Orange);
        }

        return FindBrush("MutedTextBrush", Brushes.LightSlateGray);
    }

    private void RefreshPersonalHangarActivity()
    {
        if (PersonalActivityHangarText is null)
        {
            return;
        }

        if (!IsLoggedIn && !_authenticationExpired)
        {
            PersonalActivityHangarText.Text = "登录后可读取官网机库";
            PersonalActivityHangarDot.Fill = FindBrush("StatusDisabledBrush", Brushes.LightSlateGray);
            UpdatePersonalConsoleActivityVisibleItems();
            return;
        }

        if (_ownedShips.Count == 0)
        {
            PersonalActivityHangarText.Text = "官网机库等待读取";
            PersonalActivityHangarDot.Fill = FindBrush("StatusWarningBrush", Brushes.Orange);
            UpdatePersonalConsoleActivityVisibleItems();
            return;
        }

        var latestSync = _ownedShips
            .Select(ship => ship.SyncedAt)
            .Where(value => value != default && value != DateTimeOffset.MinValue)
            .DefaultIfEmpty(DateTimeOffset.MinValue)
            .Max();

        PersonalActivityHangarText.Text = latestSync == DateTimeOffset.MinValue
            ? $"官网机库已读取 · 等待同步（{_ownedShips.Count} 艘）"
            : $"官网机库已同步 · {latestSync.ToLocalTime():MM-dd HH:mm}";
        PersonalActivityHangarDot.Fill = latestSync == DateTimeOffset.MinValue
            ? FindBrush("StatusWarningBrush", Brushes.Orange)
            : FindBrush("StatusSuccessBrush", Brushes.SpringGreen);
        UpdatePersonalConsoleActivityVisibleItems();
    }

    private void ReplaceRemoteFleetShips(NetworkFleetShipSnapshot[]? ships)
    {
        if (ships is null)
        {
            return;
        }

        if (NetworkFleetShipSnapshotChangeDetector.AreEquivalent(_remoteFleetShips.Values, ships))
        {
            return;
        }

        _remoteFleetShips.Clear();
        foreach (var ship in ships)
        {
            UpsertRemoteFleetShip(ship);
        }

        RefreshFleetShipInventory();
    }

    private void ReplaceRemoteFleetShipsForOwner(
        string? ownerGameName,
        string? ownerCallsign,
        NetworkFleetShipSnapshot[]? ships,
        bool refresh = true)
    {
        var ownerAliases = EnumerateIdentityAliases(ownerGameName, ownerCallsign)
            .Where(alias => !string.IsNullOrWhiteSpace(alias))
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

        var existingShipsByKey = new Dictionary<string, NetworkFleetShipSnapshot>(StringComparer.OrdinalIgnoreCase);
        if (ownerAliases.Count > 0)
        {
            foreach (var key in _remoteFleetShips
                         .Where(pair => FleetShipOwnerMatches(pair.Value, ownerAliases))
                         .Select(pair => pair.Key)
                         .ToArray())
            {
                if (_remoteFleetShips.Remove(key, out var existingShip))
                {
                    existingShipsByKey[key] = existingShip;
                }
            }
        }

        foreach (var ship in ships ?? [])
        {
            var key = BuildFleetShipKey(ship);
            var nextShip = ship;
            if (existingShipsByKey.TryGetValue(key, out var existingShip))
            {
                nextShip = FleetShipCatalogProjection.InheritAuthoritativeMetadata(nextShip, existingShip) with
                {
                    ImportedAt = existingShip.ImportedAt,
                    HangarImportedAt = ship.HangarImportedAt == default ? existingShip.HangarImportedAt : ship.HangarImportedAt,
                    OwnerAvatarImageData = string.IsNullOrWhiteSpace(ship.OwnerAvatarImageData)
                        ? existingShip.OwnerAvatarImageData
                        : ship.OwnerAvatarImageData
                };
            }
            else if (_localFleetShipSharedAtCache.TryGetValue(key, out var cachedSharedAt))
            {
                nextShip = nextShip with { ImportedAt = cachedSharedAt };
            }
            else
            {
                nextShip = nextShip with { ImportedAt = DateTimeOffset.UtcNow };
            }

            UpsertRemoteFleetShip(nextShip);
        }

        if (refresh)
        {
            RefreshFleetShipInventory();
        }
    }

    private void UpsertRemoteFleetShip(NetworkFleetShipSnapshot ship)
    {
        if (string.IsNullOrWhiteSpace(ship.Code) || string.IsNullOrWhiteSpace(ship.OwnerGameName))
        {
            return;
        }

        var key = BuildFleetShipKey(ship);
        _remoteFleetShips[key] = ship;
        if (ship.ImportedAt != default && ship.ImportedAt != DateTimeOffset.MinValue)
        {
            _localFleetShipSharedAtCache[key] = ship.ImportedAt.ToUniversalTime();
        }
    }

    private static bool FleetShipOwnerMatches(NetworkFleetShipSnapshot ship, HashSet<string> ownerAliases)
    {
        return IdentityMatchesAnyAlias(ship.OwnerGameName, ownerAliases) ||
               IdentityMatchesAnyAlias(ship.OwnerCallsign, ownerAliases);
    }

    private static bool IdentityMatchesAnyAlias(string? identity, HashSet<string> aliases)
    {
        if (string.IsNullOrWhiteSpace(identity))
        {
            return false;
        }

        return EnumerateIdentityAliases(identity, null).Any(aliases.Contains);
    }

    private NetworkPlayerSnapshot? ResolveFleetShipOwnerSnapshot(NetworkFleetShipSnapshot ship)
    {
        if (!string.IsNullOrWhiteSpace(ship.OwnerAccountId))
        {
            var accountMatch = _networkSnapshots.Values.FirstOrDefault(snapshot =>
                string.Equals(snapshot.AccountId, ship.OwnerAccountId, StringComparison.OrdinalIgnoreCase));
            if (accountMatch is not null)
            {
                return accountMatch;
            }
        }

        var ownerAliases = EnumerateIdentityAliases(ship.OwnerGameName, ship.OwnerCallsign)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        return _networkSnapshots.Values.FirstOrDefault(snapshot =>
            IdentityMatchesAnyAlias(snapshot.Name, ownerAliases) ||
            IdentityMatchesAnyAlias(snapshot.Callsign, ownerAliases));
    }

    private PlayerRow? ResolveFleetShipOwnerRosterMember(NetworkFleetShipSnapshot ship)
    {
        if (!string.IsNullOrWhiteSpace(ship.OwnerAccountId))
        {
            var accountMatch = _players.FirstOrDefault(player =>
                string.Equals(player.AccountId, ship.OwnerAccountId, StringComparison.OrdinalIgnoreCase));
            if (accountMatch is not null)
            {
                return accountMatch;
            }
        }

        var ownerAliases = EnumerateIdentityAliases(ship.OwnerGameName, ship.OwnerCallsign)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        return _players.FirstOrDefault(player =>
            IdentityMatchesAnyAlias(player.Name, ownerAliases) ||
            IdentityMatchesAnyAlias(player.Callsign, ownerAliases));
    }

    private static string BuildFleetShipKey(string? ownerGameName, string? shipCode, string? instanceId = null)
    {
        var shipIdentity = string.IsNullOrWhiteSpace(instanceId)
            ? NormalizeLocalKey(shipCode)
            : $"instance:{NormalizeLocalKey(instanceId)}";
        return $"{NormalizeLocalKey(ownerGameName)}::{shipIdentity}";
    }

    private static string BuildFleetShipKey(NetworkFleetShipSnapshot ship)
    {
        var owner = string.IsNullOrWhiteSpace(ship.OwnerAccountId)
            ? ship.OwnerGameName
            : $"account:{ship.OwnerAccountId}";
        return BuildFleetShipKey(owner, ship.Code, ship.InstanceId);
    }

    private static string NormalizeLocalKey(string? value)
    {
        return string.IsNullOrWhiteSpace(value) ? "unknown" : value.Trim();
    }

    private void RefreshFleetShipInventory()
    {
        if (FleetShipInventoryCountText is null)
        {
            return;
        }

        var ownerName = string.IsNullOrWhiteSpace(_localPlayer) ? "Unknown" : _localPlayer;
        var ownerCallsign = string.IsNullOrWhiteSpace(_callsign) ? ownerName : _callsign!;
        var ownerAvatarImageData = BuildAvatarImageData();
        IEnumerable<NetworkFleetShipSnapshot> localShips = _syncPrivacySettings.PersonalHangarVisible
            ? _ownedShips.Select(ship => new NetworkFleetShipSnapshot(
                ship.Code,
                ship.DisplayName,
                ownerName,
                ownerCallsign,
                ownerAvatarImageData,
                GetFleetShipSharedAt(ship, ownerName),
                ship.ImportedAt,
                ship.InstanceId,
                GetOwnedShipRoleCategory(ship).ToString(),
                _accountId,
                ship.CustomImageMediaId,
                ship.CustomImageCropFrame.FocusX,
                ship.CustomImageCropFrame.FocusY,
                ship.CustomImageCropFrame.Zoom))
            : [];
        var rows = new Dictionary<string, NetworkFleetShipSnapshot>(StringComparer.OrdinalIgnoreCase);
        foreach (var ship in _remoteFleetShips.Values.Concat(localShips))
        {
            if (string.IsNullOrWhiteSpace(ship.Code) || string.IsNullOrWhiteSpace(ship.OwnerGameName))
            {
                continue;
            }

            var key = BuildFleetShipKey(ship.OwnerGameName, ship.Code, ship.InstanceId);
            rows[key] = rows.TryGetValue(key, out var existingShip)
                ? FleetShipCatalogProjection.InheritAuthoritativeMetadata(ship, existingShip)
                : ship;
        }

        var shipRows = new List<FleetShipInventoryRow>();
        foreach (var ship in rows.Values
                     .OrderBy(ship => ship.ImportedAt)
                     .ThenBy(ship => ship.DisplayName, StringComparer.OrdinalIgnoreCase))
        {
            var catalog = ShipCatalog.Find(ship.Code, ship.DisplayName);
            var catalogPresentation = FleetShipCatalogProjection.Resolve(ship, catalog, _language);
            var shipDisplayName = catalog?.DisplayName(_language) ?? ship.DisplayName;
            var shipEnglishName = FormatFleetShipEnglishName(ship.Code, catalog?.EnglishName);
            var shipRoleVisual = GetFleetShipRoleVisual(GetFleetShipRoleCategory(catalogPresentation.RawRole));
            var ownerDisplay = FormatFleetShipOwnerDisplay(ship.OwnerCallsign, ship.OwnerGameName);
            var ownerRosterMember = ResolveFleetShipOwnerRosterMember(ship);
            var ownerSnapshot = ResolveFleetShipOwnerSnapshot(ship);
            var ownerPresence = FleetShipOwnerPresenceProjection.Resolve(ownerRosterMember, ownerSnapshot);
            var hangarImportedAt = NormalizeShipTimestamp(ship.HangarImportedAt, ship.ImportedAt);
            var row = new FleetShipInventoryRow(
                0,
                shipDisplayName,
                shipEnglishName,
                ownerDisplay,
                string.IsNullOrWhiteSpace(ship.OwnerCallsign) ? ship.OwnerGameName : ship.OwnerCallsign!,
                ship.OwnerGameName,
                ship.OwnerAvatarImageData,
                GetInitials(ship.OwnerCallsign ?? ship.OwnerGameName),
                hangarImportedAt.ToLocalTime().ToString("yyyy-MM-dd"),
                ship.ImportedAt.ToLocalTime().ToString("yyyy-MM-dd"),
                catalogPresentation.Spec,
                catalogPresentation.Role,
                catalogPresentation.Status,
                catalogPresentation.Price,
                ResolveShipDisplayImagePath(
                    ship.CustomImageMediaId,
                    ShipCatalog.ResolveImagePath(catalog, ship.Code, ship.DisplayName)),
                ship.InstanceId,
                shipRoleVisual.ColorHex,
                ship.OwnerAccountId,
                ship.CustomImageMediaId,
                !string.IsNullOrWhiteSpace(ship.CustomImageMediaId) &&
                !string.Equals(ship.OwnerAccountId, _accountId, StringComparison.OrdinalIgnoreCase),
                ship.CustomImageCropFocusX,
                ship.CustomImageCropFocusY,
                ship.CustomImageCropZoom,
                ownerPresence.OnlineStatus,
                ownerPresence.LiveStatus);

            shipRows.Add(row with { LoanerRows = BuildFleetShipLoanerRows(row, catalog) });
        }

        var sortedRows = SortFleetShipRows(shipRows)
            .Select((row, index) => row with { Number = index + 1 })
            .ToArray();
        if (!FleetShipInventoryRowChangeDetector.AreEquivalent(_fleetShipInventory, sortedRows))
        {
            _fleetShipInventory.Clear();
            foreach (var row in sortedRows)
            {
                _fleetShipInventory.Add(row);
            }
        }

        if (FleetShipCountText is not null)
        {
            FleetShipCountText.Text = _fleetShipInventory.Count.ToString();
        }

        FleetShipInventoryCountText.Text = $"已共享舰船 / {_fleetShipInventory.Count}";
        FleetShipInventoryEmptyText.Visibility = _fleetShipInventory.Count == 0
            ? Visibility.Visible
            : Visibility.Collapsed;
        FleetShipDatabaseCountText.Text = _fleetShipInventory.Count.ToString();
        RefreshFleetShipDatabaseSpecDistribution();
        RefreshFleetShipDatabaseRoleDistribution();
        var preferredDispatch = ResolvePreferredFleetShipDispatch();
        FleetShipDatabasePreferredDispatchText.Text = preferredDispatch is null
            ? _fleetShipInventory.Count == 0
                ? "暂无已同步舰船"
                : "暂无在线可飞舰船"
            : $"{preferredDispatch.ShipName} · {preferredDispatch.OwnerDisplay} · {preferredDispatch.ShipSpec} · {preferredDispatch.ShipRoleTag}";
        var pricedShips = _fleetShipInventory
            .Where(ship => ship.ShipPriceValue.HasValue)
            .ToArray();
        FleetShipDatabaseTotalValueText.Text = pricedShips.Length == 0
            ? "未公布"
            : FormatFleetShipValue(pricedShips.Sum(ship => ship.ShipPriceValue!.Value));
        FleetShipDatabaseTopOwnerText.Text = _fleetShipInventory.Count == 0
            ? "-"
            : _fleetShipInventory
                .GroupBy(ship => ship.OwnerGameId)
                .OrderByDescending(group => group.Count())
                .Select(group => group.First().OwnerDisplay)
                .FirstOrDefault() ?? "-";
        FleetShipDatabaseAceText.Text = pricedShips
            .OrderByDescending(ship => ship.ShipPriceValue!.Value)
            .Select(ship => ship.ShipName)
            .FirstOrDefault() ?? "待评定";
        RefreshFleetShipDatabaseRows();
        RefreshFleetRightContextSidebar();
    }

    private void RefreshFleetShipDatabaseSpecDistribution()
    {
        if (FleetShipDatabaseSpecDistributionBar is null)
        {
            return;
        }

        var segments = FleetShipSpecVisuals
            .Select((visual, order) => (
                visual.DisplayName,
                Count: CountFleetShipSpec(visual.Spec),
                AvailableCount: (int?)null,
                visual.ColorHex,
                Order: order))
            .Where(item => item.Count > 0)
            .ToArray();

        RenderFleetShipDistributionBar(
            FleetShipDatabaseSpecDistributionBar,
            segments,
            "暂无舰船规格数据",
            FleetShipDistributionColorMode.OrdinalTonal);
    }

    private void RefreshFleetShipDatabaseRoleDistribution()
    {
        if (FleetShipDatabaseRoleDistributionBar is null)
        {
            return;
        }

        var deployableAssets = _fleetShipInventory
            .Where(IsFleetShipDispatchableAsset)
            .ToArray();
        var segments = FleetShipRoleVisuals
            .Select((visual, order) => (
                visual.DisplayName,
                Count: CountFleetShipRoleCategory(visual.Category),
                AvailableCount: (int?)CountFleetShipsByRoleCategory(deployableAssets, visual.Category),
                visual.ColorHex,
                Order: order))
            .Where(item => item.Count > 0)
            .ToArray();

        RenderFleetShipDistributionBar(
            FleetShipDatabaseRoleDistributionBar,
            segments,
            "暂无已同步舰船",
            FleetShipDistributionColorMode.CategoricalOutline);
    }

    private enum FleetShipDistributionColorMode
    {
        OrdinalTonal,
        CategoricalOutline
    }

    private void RenderFleetShipDistributionBar(
        Grid target,
        IReadOnlyList<(string DisplayName, int Count, int? AvailableCount, string ColorHex, int Order)> segments,
        string emptyText,
        FleetShipDistributionColorMode colorMode)
    {
        target.Children.Clear();
        target.ColumnDefinitions.Clear();

        if (segments.Count == 0)
        {
            target.ColumnDefinitions.Add(new ColumnDefinition());
            target.Children.Add(new Border
            {
                Background = BridgeTokenBrushes.GetRequired(this, BridgeBrushToken.Panel),
                BorderBrush = BridgeTokenBrushes.GetRequired(this, BridgeBrushToken.Hairline),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(2),
                Child = new TextBlock
                {
                    Text = emptyText,
                    Foreground = BridgeTokenBrushes.GetRequired(this, BridgeBrushToken.Ink3),
                    FontFamily = new System.Windows.Media.FontFamily("Microsoft YaHei UI"),
                    FontSize = 10.5,
                    HorizontalAlignment = System.Windows.HorizontalAlignment.Center,
                    VerticalAlignment = VerticalAlignment.Center
                }
            });
            return;
        }

        for (var index = 0; index < segments.Count; index++)
        {
            var segment = segments[index];
            var brushes = ResolveFleetShipDistributionBrushes(segment, colorMode);
            var labelText = segment.AvailableCount.HasValue
                ? $"{segment.DisplayName} {segment.AvailableCount.Value} / {segment.Count}"
                : $"{segment.DisplayName} {segment.Count}";
            target.ColumnDefinitions.Add(new ColumnDefinition
            {
                Width = new GridLength(segment.Count, GridUnitType.Star),
                MinWidth = CalculateFleetShipDistributionSegmentMinWidth(
                    segment.DisplayName,
                    segment.Count,
                    segment.AvailableCount)
            });

            var label = new TextBlock
            {
                Text = labelText,
                Foreground = brushes.Foreground,
                FontFamily = new System.Windows.Media.FontFamily("Microsoft YaHei UI"),
                FontSize = 10,
                FontWeight = FontWeights.SemiBold,
                TextTrimming = TextTrimming.None,
                HorizontalAlignment = System.Windows.HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center,
                Margin = new Thickness(4, 0, 4, 0),
                ToolTip = segment.AvailableCount.HasValue
                    ? $"{segment.DisplayName} · 可调度 {segment.AvailableCount.Value} / 全部 {segment.Count} 艘"
                    : $"{segment.DisplayName} · {segment.Count} 艘"
            };
            var block = new Border
            {
                Background = brushes.Background,
                BorderBrush = brushes.Border,
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(2),
                Margin = index == 0 ? new Thickness(0) : new Thickness(2, 0, 0, 0),
                Child = label,
                ToolTip = label.ToolTip
            };
            Grid.SetColumn(block, index);
            target.Children.Add(block);
        }
    }

    private static (System.Windows.Media.Brush Foreground,
        System.Windows.Media.Brush Background,
        System.Windows.Media.Brush Border)
        ResolveFleetShipDistributionBrushes(
            (string DisplayName, int Count, int? AvailableCount, string ColorHex, int Order) segment,
            FleetShipDistributionColorMode colorMode)
    {
        if (colorMode == FleetShipDistributionColorMode.OrdinalTonal)
        {
            return (
                BrushFromHex(segment.ColorHex, 0.86),
                BrushFromHex(segment.ColorHex, 0.055),
                BrushFromHex(segment.ColorHex, 0.52));
        }

        return (
            BrushFromHex(segment.ColorHex, 0.82),
            BrushFromHex(segment.ColorHex, 0.06),
            BrushFromHex(segment.ColorHex, 0.38));
    }

    private static double CalculateFleetShipDistributionSegmentMinWidth(
        string displayName,
        int count,
        int? availableCount)
    {
        const double chineseCharacterWidth = 13;
        const double numericCharacterWidth = 8;
        const double horizontalPadding = 22;
        var numericText = availableCount.HasValue
            ? $"{availableCount.Value}/{count}"
            : count.ToString(CultureInfo.InvariantCulture);
        return Math.Max(
            58,
            (displayName.Length * chineseCharacterWidth) +
            (numericText.Length * numericCharacterWidth) +
            horizontalPadding);
    }

    private IReadOnlyList<FleetShipInventoryRow> BuildFleetShipLoanerRows(
        FleetShipInventoryRow sourceRow,
        ShipCatalogEntry? sourceCatalog)
    {
        if (sourceCatalog is null ||
            !sourceCatalog.Status.Equals("概念", StringComparison.OrdinalIgnoreCase))
        {
            return [];
        }

        var loaners = ShipLoanerMatrix.FindForConceptSource(sourceCatalog.EnglishName);
        if (loaners.Count == 0)
        {
            return [];
        }

        var rows = new List<FleetShipInventoryRow>(loaners.Count);
        foreach (var loaner in loaners)
        {
            var catalog = ShipLoanerMatrix.FindLoanerCatalog(loaner.LoanerEnglishName);
            var shipName = catalog?.DisplayName(_language) ?? loaner.LoanerEnglishName;
            var shipCode = catalog?.EnglishName ?? loaner.LoanerEnglishName;
            var shipSpec = string.IsNullOrWhiteSpace(catalog?.Spec) ? "待分类" : catalog!.Spec;
            var shipRole = catalog?.RoleDisplay(_language) ?? "";
            var shipRoleVisual = GetFleetShipRoleVisual(GetFleetShipRoleCategory(catalog?.Role ?? ""));
            var shipStatus = ShipCatalog.ResolveStatus(catalog);
            var shipPrice = catalog?.PriceDisplay ?? "未公布";

            rows.Add(new FleetShipInventoryRow(
                0,
                shipName,
                shipCode,
                sourceRow.OwnerDisplay,
                sourceRow.OwnerCallsign,
                sourceRow.OwnerGameId,
                sourceRow.OwnerAvatarPath,
                sourceRow.OwnerInitials,
                sourceRow.ImportedAtText,
                sourceRow.FleetSharedAtText,
                shipSpec,
                shipRole,
                shipStatus,
                shipPrice,
                ShipCatalog.ResolveImagePath(catalog, shipCode, loaner.LoanerEnglishName),
                $"loaner:{sourceRow.ShipInstanceId ?? sourceRow.ShipCode}:{shipCode}",
                shipRoleVisual.ColorHex,
                sourceRow.OwnerAccountId,
                OwnerOnlineStatus: sourceRow.OwnerOnlineStatus,
                OwnerLiveStatus: sourceRow.OwnerLiveStatus));
        }

        return rows;
    }

    private static string FormatFleetShipEnglishName(string? shipCode, string? catalogEnglishName)
    {
        var normalizedCode = ShipNameLocalizer.NormalizeCode(shipCode);
        var manufacturer = "";
        var fallbackName = normalizedCode;
        var separatorIndex = normalizedCode.IndexOf('_');
        if (separatorIndex > 0 && separatorIndex < normalizedCode.Length - 1)
        {
            manufacturer = normalizedCode[..separatorIndex];
            fallbackName = normalizedCode[(separatorIndex + 1)..];
        }

        var shipName = string.IsNullOrWhiteSpace(catalogEnglishName)
            ? FormatFleetShipCodeName(fallbackName)
            : catalogEnglishName.Trim();

        manufacturer = FleetShipManufacturerDisplayNames.TryGetValue(manufacturer, out var manufacturerDisplay)
            ? manufacturerDisplay
            : manufacturer.ToUpperInvariant();

        return string.IsNullOrWhiteSpace(manufacturer)
            ? shipName
            : $"{manufacturer} {shipName}";
    }

    private static string FormatFleetShipCodeName(string value)
    {
        var normalized = Regex.Replace(value.Replace('_', ' '), @"\s+", " ").Trim();
        return Regex.Replace(normalized, @"\b([A-Za-z]+) ([A-Z])\b", "$1-$2");
    }

    private static string FormatFleetShipOwnerDisplay(string? ownerCallsign, string ownerGameName)
    {
        var callsign = ownerCallsign?.Trim();
        if (!string.IsNullOrWhiteSpace(callsign) &&
            !callsign.Equals(ownerGameName, StringComparison.OrdinalIgnoreCase))
        {
            return callsign;
        }

        return string.IsNullOrWhiteSpace(ownerGameName) ? "Unknown" : ownerGameName;
    }

    private void RefreshFleetShipDatabaseRows()
    {
        if (FleetShipDatabaseList is null)
        {
            return;
        }

        var filteredRows = SortFleetShipRows(_fleetShipInventory
            .Where(MatchesFleetShipDatabaseFilter)
            .Where(MatchesFleetShipDatabaseSearch))
            .Select((row, index) => row with { Number = index + 1 })
            .ToArray();

        if (!FleetShipInventoryRowChangeDetector.AreEquivalent(_fleetShipDatabaseRows, filteredRows))
        {
            _fleetShipDatabaseRows.Clear();
            foreach (var row in filteredRows)
            {
                _fleetShipDatabaseRows.Add(row);
            }
        }

        if (FleetShipDatabaseEmptyText is null)
        {
            return;
        }

        FleetShipDatabaseEmptyText.Text = _fleetShipInventory.Count == 0
            ? "暂无舰船数据\n成员上传机库数据后，舰队舰船将在此显示。"
            : "没有匹配的舰船\n调整搜索或过滤条件后再试。";
        FleetShipDatabaseEmptyText.Visibility = _fleetShipDatabaseRows.Count == 0
            ? Visibility.Visible
            : Visibility.Collapsed;
    }

    private void FleetShipDetailsButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not FrameworkElement { DataContext: FleetShipInventoryRow ship })
        {
            return;
        }

        OpenFleetShipDetails(ship);
    }

    private void OpenFleetShipDetails(FleetShipInventoryRow ship)
    {
        FleetShipDetailsOverlay.DataContext = ship;
        FleetShipDetailsOverlay.Show();
    }

    private void FleetShipDetailsCloseButton_Click(object sender, RoutedEventArgs e)
    {
        CloseFleetShipDetailsOverlay();
    }

    private void CloseFleetShipDetailsOverlay()
    {
        if (FleetShipDetailsOverlay is null)
        {
            return;
        }

        FleetShipDetailsOverlay.Hide();
        FleetShipDetailsOverlay.DataContext = null;
    }

    private bool MatchesFleetShipDatabaseSearch(FleetShipInventoryRow ship)
    {
        var query = _fleetShipDatabaseSearch.Trim();
        if (string.IsNullOrWhiteSpace(query))
        {
            return true;
        }

        return ContainsFleetShipSearchText(ship.ShipName, query) ||
               ContainsFleetShipSearchText(ship.ShipCode, query) ||
               ContainsFleetShipSearchText(ship.OwnerDisplay, query) ||
               ContainsFleetShipSearchText(ship.OwnerCallsign, query) ||
               ContainsFleetShipSearchText(ship.OwnerGameId, query) ||
               ContainsFleetShipSearchText(ship.ShipSpec, query) ||
               ContainsFleetShipSearchText(ship.ShipRole, query) ||
               ContainsFleetShipSearchText(ship.ShipStatus, query) ||
               ContainsFleetShipSearchText(ship.ShipPrice, query) ||
               ship.LoanerRows.Any(loaner =>
                   ContainsFleetShipSearchText(loaner.ShipName, query) ||
                   ContainsFleetShipSearchText(loaner.ShipCode, query) ||
                   ContainsFleetShipSearchText(loaner.ShipSpec, query) ||
                   ContainsFleetShipSearchText(loaner.ShipRole, query) ||
                   ContainsFleetShipSearchText(loaner.ShipStatus, query) ||
                   ContainsFleetShipSearchText(loaner.ShipPrice, query));
    }

    private static bool ContainsFleetShipSearchText(string value, string query)
    {
        return !string.IsNullOrWhiteSpace(value) &&
               value.Contains(query, StringComparison.OrdinalIgnoreCase);
    }

    private bool MatchesFleetShipDatabaseFilter(FleetShipInventoryRow ship)
    {
        return _fleetShipDatabaseFilter switch
        {
            "旗舰级" or "大型" or "中型" or "小型" => ship.ShipSpec.Equals(_fleetShipDatabaseFilter, StringComparison.OrdinalIgnoreCase),
            "可飞" => ship.ShipStatus.Equals("可飞", StringComparison.OrdinalIgnoreCase) ||
                    ship.ShipStatus.Equals("Flyable", StringComparison.OrdinalIgnoreCase),
            "概念" => ship.ShipStatus.Contains("概念", StringComparison.OrdinalIgnoreCase) ||
                    ship.ShipStatus.Contains("Concept", StringComparison.OrdinalIgnoreCase),
            "未知" => ship.ShipSpec.Equals("待分类", StringComparison.OrdinalIgnoreCase) ||
                    string.IsNullOrWhiteSpace(ship.ShipRole) ||
                    ship.ShipPriceTag.Equals("未公布", StringComparison.OrdinalIgnoreCase) ||
                    ship.ShipStatus.Contains("未知", StringComparison.OrdinalIgnoreCase) ||
                    ship.ShipStatus.Contains("unknown", StringComparison.OrdinalIgnoreCase),
            _ => true
        };
    }

    private IEnumerable<FleetShipInventoryRow> SortFleetShipRows(IEnumerable<FleetShipInventoryRow> rows)
    {
        var sorted = _fleetShipSortColumn switch
        {
            FleetShipSortColumn.Name => OrderFleetShipRowsByText(rows, ship => ship.ShipName, _fleetShipSortDescending),
            FleetShipSortColumn.Status => rows.OrderBy(ship => GetFleetShipStatusSortRank(ship.ShipStatus, conceptFirst: _fleetShipSortDescending)),
            FleetShipSortColumn.Price => _fleetShipSortDescending
                ? rows.OrderByDescending(ship => ship.ShipPriceValue ?? -1m)
                : rows.OrderBy(ship => ship.ShipPriceValue ?? decimal.MaxValue),
            FleetShipSortColumn.Role => OrderFleetShipRowsByText(rows, ship => ship.ShipRole, _fleetShipSortDescending),
            FleetShipSortColumn.Owner => OrderFleetShipRowsByText(rows, ship => ship.OwnerDisplay, _fleetShipSortDescending),
            _ => rows.OrderBy(ship => GetFleetShipSpecSortRank(ship.ShipSpec, largeFirst: _fleetShipSortDescending))
        };

        return sorted.ThenBy(ship => ship.ShipName, StringComparer.CurrentCultureIgnoreCase)
            .ThenBy(ship => ship.ShipCode, StringComparer.CurrentCultureIgnoreCase);
    }

    private static IOrderedEnumerable<FleetShipInventoryRow> OrderFleetShipRowsByText(
        IEnumerable<FleetShipInventoryRow> rows,
        Func<FleetShipInventoryRow, string> selector,
        bool descending)
    {
        return descending
            ? rows.OrderBy(ship => string.IsNullOrWhiteSpace(selector(ship)))
                .ThenByDescending(selector, StringComparer.CurrentCultureIgnoreCase)
            : rows.OrderBy(ship => string.IsNullOrWhiteSpace(selector(ship)))
                .ThenBy(selector, StringComparer.CurrentCultureIgnoreCase);
    }

    private static int GetFleetShipSpecSortRank(string spec, bool largeFirst)
    {
        var rank = spec.Trim() switch
        {
            "旗舰级" => 0,
            "大型" => 1,
            "中型" => 2,
            "小型" => 3,
            _ => 4
        };

        if (largeFirst)
        {
            return rank;
        }

        return rank switch
        {
            3 => 0,
            2 => 1,
            1 => 2,
            0 => 3,
            _ => 4
        };
    }

    private static int GetFleetShipStatusSortRank(string status, bool conceptFirst)
    {
        var normalized = status.Trim();
        var isConcept = normalized.Equals("概念", StringComparison.OrdinalIgnoreCase) ||
            normalized.Equals("Concept", StringComparison.OrdinalIgnoreCase);
        var isFlyable = normalized.Equals("可飞", StringComparison.OrdinalIgnoreCase) ||
            normalized.Equals("Flyable", StringComparison.OrdinalIgnoreCase);

        if (isConcept)
        {
            return conceptFirst ? 0 : 1;
        }

        if (isFlyable)
        {
            return conceptFirst ? 1 : 0;
        }

        return 2;
    }

    private void FleetShipDatabaseSortHeader_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not FrameworkElement { Tag: string tag } ||
            !TryParseFleetShipSortColumn(tag, out var column))
        {
            return;
        }

        if (_fleetShipSortColumn == column)
        {
            _fleetShipSortDescending = !_fleetShipSortDescending;
        }
        else
        {
            _fleetShipSortColumn = column;
            _fleetShipSortDescending = GetDefaultDescendingForFleetShipSortColumn(column);
        }

        UpdateFleetShipSortHeaderIndicators();
        RefreshFleetShipDatabaseRows();
    }

    private void FleetShipSortMenuButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not System.Windows.Controls.Button button ||
            button.ContextMenu is null)
        {
            return;
        }

        button.ContextMenu.PlacementTarget = button;
        button.ContextMenu.IsOpen = true;
    }

    private void FleetShipDatabaseScopeInfo_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not System.Windows.Controls.Button button ||
            button.ContextMenu is null)
        {
            return;
        }

        button.ContextMenu.PlacementTarget = button;
        button.ContextMenu.IsOpen = true;
    }

    private void FleetShipSearchBox_TextChanged(object sender, TextChangedEventArgs e)
    {
        _fleetShipDatabaseSearch = FleetShipSearchBox?.Text ?? "";
        RefreshFleetShipDatabaseRows();
    }

    private void FleetShipFilterButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not System.Windows.Controls.Button { CommandParameter: string filter })
        {
            return;
        }

        _fleetShipDatabaseFilter = filter;
        UpdateFleetShipFilterButtons();
        RefreshFleetShipDatabaseRows();
    }

    private void UpdateFleetShipFilterButtons()
    {
        if (FleetShipFilterAllButton is null)
        {
            return;
        }

        SetFleetShipFilterButtonState(FleetShipFilterAllButton, "全部");
        SetFleetShipFilterButtonState(FleetShipFilterCapitalButton, "旗舰级");
        SetFleetShipFilterButtonState(FleetShipFilterLargeButton, "大型");
        SetFleetShipFilterButtonState(FleetShipFilterMediumButton, "中型");
        SetFleetShipFilterButtonState(FleetShipFilterSmallButton, "小型");
        SetFleetShipFilterButtonState(FleetShipFilterFlyableButton, "可飞");
        SetFleetShipFilterButtonState(FleetShipFilterConceptButton, "概念");
    }

    private void SetFleetShipFilterButtonState(System.Windows.Controls.Button button, string filter)
    {
        button.Tag = _fleetShipDatabaseFilter.Equals(filter, StringComparison.OrdinalIgnoreCase)
            ? "Active"
            : null;
    }

    private static bool TryParseFleetShipSortColumn(string tag, out FleetShipSortColumn column)
    {
        column = tag switch
        {
            "name" => FleetShipSortColumn.Name,
            "spec" => FleetShipSortColumn.Spec,
            "status" => FleetShipSortColumn.Status,
            "price" => FleetShipSortColumn.Price,
            "role" => FleetShipSortColumn.Role,
            "owner" => FleetShipSortColumn.Owner,
            _ => FleetShipSortColumn.Spec
        };

        return tag is "name" or "spec" or "status" or "price" or "role" or "owner" or "squad";
    }

    private static bool GetDefaultDescendingForFleetShipSortColumn(FleetShipSortColumn column)
    {
        return column is FleetShipSortColumn.Spec or FleetShipSortColumn.Status or FleetShipSortColumn.Price;
    }

    private void UpdateFleetShipSortHeaderIndicators()
    {
        SetFleetShipSortArrow(FleetShipSortNameArrow, FleetShipSortColumn.Name);
        SetFleetShipSortArrow(FleetShipSortSpecArrow, FleetShipSortColumn.Spec);
        SetFleetShipSortArrow(FleetShipSortStatusArrow, FleetShipSortColumn.Status);
        SetFleetShipSortArrow(FleetShipSortPriceArrow, FleetShipSortColumn.Price);
        SetFleetShipSortArrow(FleetShipSortRoleArrow, FleetShipSortColumn.Role);
        SetFleetShipSortArrow(FleetShipSortOwnerArrow, FleetShipSortColumn.Owner);
        if (FleetShipSortMenuText is not null)
        {
            FleetShipSortMenuText.Text = $"{GetFleetShipSortColumnLabel(_fleetShipSortColumn)} {(_fleetShipSortDescending ? "↓" : "↑")}";
        }
    }

    private void SetFleetShipSortArrow(TextBlock arrowText, FleetShipSortColumn column)
    {
        arrowText.Text = _fleetShipSortColumn == column
            ? _fleetShipSortDescending ? "↓" : "↑"
            : string.Empty;
    }

    private static string GetFleetShipSortColumnLabel(FleetShipSortColumn column)
    {
        return column switch
        {
            FleetShipSortColumn.Name => "名称",
            FleetShipSortColumn.Price => "价格",
            FleetShipSortColumn.Owner => "持有者",
            FleetShipSortColumn.Status => "状态",
            FleetShipSortColumn.Role => "定位",
            _ => "规格"
        };
    }

    private int CountFleetShipSpec(string spec)
    {
        return _fleetShipInventory.Count(ship => ship.ShipSpec.Equals(spec, StringComparison.OrdinalIgnoreCase));
    }

    private int CountFleetShipRoleCategory(FleetShipRoleCategory category)
    {
        return _fleetShipInventory.Count(ship => GetFleetShipRoleCategory(ship.ShipRole) == category);
    }

    private static FleetShipRoleCategory GetFleetShipRoleCategory(string? role)
    {
        var value = role ?? "";
        if (ContainsFleetShipRoleToken(value, "escort", "interceptor", "patrol", "combat", "fighter", "gunship", "bomber", "attack",
                "护卫", "拦截", "巡逻", "战斗", "炮艇", "轰炸", "攻击", "格斗"))
        {
            return FleetShipRoleCategory.Combat;
        }

        if (ContainsFleetShipRoleToken(value, "cargo", "freight", "transport", "trade", "trading", "hauler",
                "货运", "运输", "贸易", "客运", "快递", "运载"))
        {
            return FleetShipRoleCategory.Transport;
        }

        if (ContainsFleetShipRoleToken(value, "mining", "industrial", "salvage",
                "采矿", "工业", "打捞", "建造"))
        {
            return FleetShipRoleCategory.Industrial;
        }

        if (ContainsFleetShipRoleToken(value, "exploration", "scanning", "pathfinder", "scout",
                "探索", "扫描", "探路", "远征", "侦察"))
        {
            return FleetShipRoleCategory.Exploration;
        }

        if (ContainsFleetShipRoleToken(value, "medical", "rescue", "repair", "refuel", "support",
                "医疗", "救援", "维修", "加油", "支援"))
        {
            return FleetShipRoleCategory.Support;
        }

        return FleetShipRoleCategory.Utility;
    }

    private static bool ContainsFleetShipRoleToken(string value, params string[] tokens)
    {
        foreach (var token in tokens)
        {
            if (value.Contains(token, StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
        }

        return false;
    }

    private static string FormatFleetShipValue(decimal value)
    {
        return value <= 0
            ? "未公布"
            : string.Format(CultureInfo.InvariantCulture, "${0:N0}", value);
    }
}
