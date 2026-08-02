using Microsoft.Win32;
using StarBridge.Core.Events;
using StarBridge.Core.State;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Diagnostics.CodeAnalysis;
using System.Globalization;
using System.IO;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Brushes = System.Windows.Media.Brushes;
using Color = System.Windows.Media.Color;
using Cursors = System.Windows.Input.Cursors;
using HorizontalAlignment = System.Windows.HorizontalAlignment;
using OpenFileDialog = Microsoft.Win32.OpenFileDialog;
using SaveFileDialog = Microsoft.Win32.SaveFileDialog;
using WinForms = System.Windows.Forms;

namespace StarBridge.Desktop;

public partial class MainWindow
{
    private void LoadOverlayPreset(string preset)
    {
        _activeOverlayPreset = NormalizeOverlayPresetId(preset);
        _selectedOverlayInspectorItem = null;
        _isOverlayEventNotificationSelected = false;
        _isOverlayCrosshairSelected = false;
        _overlaySettings = ApplyOverlayFeatureLocks(OverlayDisplaySettings.Parse(
            DesktopAppConfig.LoadOverlayPresetSettings(_activeOverlayPreset) ??
            CreateDefaultOverlaySettings(_activeOverlayPreset).Serialize()));

        LoadOverlayLayout(
            DesktopAppConfig.LoadOverlayPresetLayout(_activeOverlayPreset) ??
            SerializeOverlayLayout(CreateDefaultOverlayLayout(_activeOverlayPreset)));

        ClearOverlayEditorHistory();
        _isLoadingSettings = true;
        ApplyOverlaySettingsToControls();
        _isLoadingSettings = false;
        RenderOverlayEditor();
        MarkOverlayEditorLayoutSaved();
        SaveCurrentConfig();
        RefreshOverlayWindow();
        AppendOutput($"Overlay preset loaded: {_activeOverlayPreset}.");
    }

    private void LoadOverlayPresetEntries()
    {
        _overlayPresetEntries.Clear();
        foreach (var entry in ParseOverlayPresetEntries(DesktopAppConfig.LoadOverlayPresetManifest()))
        {
            AddOverlayPresetEntryIfUnique(entry);
        }

        if (_overlayPresetEntries.Count > 0)
        {
            return;
        }

        var defaultEntry = new OverlayPresetEntry(OverlayPresetDefault, "默认预设");
        _overlayPresetEntries.Add(defaultEntry);
        DesktopAppConfig.SaveOverlayPresetSettings(defaultEntry.Id, GetDefaultOverlayPresetSettingsPayload());
        DesktopAppConfig.SaveOverlayPresetLayout(defaultEntry.Id, GetDefaultOverlayPresetLayoutPayload());
        SaveOverlayPresetManifest();
    }

    private void SaveOverlayPresetManifest()
    {
        if (_overlayPresetEntries.Count == 0)
        {
            return;
        }

        var manifest = new OverlayPresetManifest(_overlayPresetEntries.ToList());
        DesktopAppConfig.SaveOverlayPresetManifest(JsonSerializer.Serialize(manifest, OverlayPresetJsonOptions));
    }

    private static IEnumerable<OverlayPresetEntry> ParseOverlayPresetEntries(string? serialized)
    {
        if (string.IsNullOrWhiteSpace(serialized))
        {
            yield break;
        }

        List<OverlayPresetEntry>? entries = null;
        try
        {
            entries = JsonSerializer.Deserialize<OverlayPresetManifest>(serialized)?.Presets;
        }
        catch
        {
            // Older experimental builds may have written a raw list. Try that below.
        }

        if (entries is null)
        {
            try
            {
                entries = JsonSerializer.Deserialize<List<OverlayPresetEntry>>(serialized);
            }
            catch
            {
                entries = null;
            }
        }

        if (entries is null)
        {
            yield break;
        }

        foreach (var entry in entries)
        {
            var id = SanitizeOverlayPresetId(entry.Id);
            var name = CleanOverlayPresetName(entry.Name) ?? "默认预设";
            if (id.Equals(OverlayPresetDefault, StringComparison.OrdinalIgnoreCase) &&
                (name.Equals("预设1", StringComparison.OrdinalIgnoreCase) ||
                 name.Equals("舰桥标准", StringComparison.OrdinalIgnoreCase)))
            {
                name = "默认预设";
            }

            yield return new OverlayPresetEntry(id, name);
        }
    }

    private void AddOverlayPresetEntryIfUnique(OverlayPresetEntry entry)
    {
        if (_overlayPresetEntries.Any(existing => existing.Id.Equals(entry.Id, StringComparison.OrdinalIgnoreCase)))
        {
            return;
        }

        _overlayPresetEntries.Add(entry);
    }

    private string NormalizeOverlayPresetId(string? preset)
    {
        if (_overlayPresetEntries.Count == 0)
        {
            LoadOverlayPresetEntries();
        }

        var id = SanitizeOverlayPresetId(preset);
        return _overlayPresetEntries.FirstOrDefault(entry =>
            entry.Id.Equals(id, StringComparison.OrdinalIgnoreCase))?.Id ??
            _overlayPresetEntries.FirstOrDefault()?.Id ??
            OverlayPresetDefault;
    }

    private static string SanitizeOverlayPresetId(string? value)
    {
        var raw = string.IsNullOrWhiteSpace(value) ? OverlayPresetDefault : value.Trim().ToLowerInvariant();
        var safe = Regex.Replace(raw, "[^a-z0-9]+", "-").Trim('-');
        return string.IsNullOrWhiteSpace(safe) ? OverlayPresetDefault : safe;
    }

    private static string? CleanOverlayPresetName(string? value)
    {
        var name = value?.Trim();
        if (string.IsNullOrWhiteSpace(name))
        {
            return null;
        }

        return name.Length > 24 ? name[..24] : name;
    }

    private string CreateUniqueOverlayPresetName(string baseName)
    {
        var cleanBaseName = CleanOverlayPresetName(baseName) ?? "预设";
        var candidate = cleanBaseName;
        var index = 2;
        while (_overlayPresetEntries.Any(entry => entry.Name.Equals(candidate, StringComparison.OrdinalIgnoreCase)))
        {
            candidate = CleanOverlayPresetName($"{cleanBaseName} {index}") ?? $"{cleanBaseName} {index}";
            index++;
        }

        return candidate;
    }

    private string CreateOverlayPresetId()
    {
        string id;
        do
        {
            id = $"preset-{Guid.NewGuid():N}";
            id = id[..20];
        }
        while (_overlayPresetEntries.Any(entry => entry.Id.Equals(id, StringComparison.OrdinalIgnoreCase)));

        return id;
    }

    private string GetDefaultOverlayPresetSettingsPayload()
    {
        return DesktopAppConfig.LoadOverlayPresetSettings(OverlayPresetCompact) ??
            DesktopAppConfig.LoadOverlaySettings() ??
            OverlayDefaultPreset.Settings.Serialize();
    }

    private static string GetDefaultOverlayPresetLayoutPayload()
    {
        return DesktopAppConfig.LoadOverlayPresetLayout(OverlayPresetCompact) ??
            DesktopAppConfig.LoadOverlayLayout() ??
            OverlayDefaultPreset.LayoutPayload;
    }

    private void RefreshOverlayPresetBoxItems()
    {
        if (OverlayPresetBox is null)
        {
            return;
        }

        if (_overlayPresetEntries.Count == 0)
        {
            LoadOverlayPresetEntries();
        }

        var wasLoadingSettings = _isLoadingSettings;
        _isLoadingSettings = true;
        OverlayPresetBox.Items.Clear();
        foreach (var preset in _overlayPresetEntries)
        {
            OverlayPresetBox.Items.Add(new ComboBoxItem
            {
                Content = preset.Name,
                Tag = preset.Id
            });
        }

        OverlayPresetBox.SelectedItem = OverlayPresetBox.Items
            .OfType<ComboBoxItem>()
            .FirstOrDefault(item => item.Tag is string id && id.Equals(_activeOverlayPreset, StringComparison.OrdinalIgnoreCase)) ??
            OverlayPresetBox.Items.OfType<ComboBoxItem>().FirstOrDefault();
        _isLoadingSettings = wasLoadingSettings;
        RefreshOverlayPresetActionButtons();
    }

    private void RefreshOverlayPresetActionButtons()
    {
        if (OverlayDeletePresetButton is not null)
        {
            OverlayDeletePresetButton.IsEnabled = _overlayPresetEntries.Count > 1;
        }
    }

    private static string NormalizeOverlayPreset(string? preset)
    {
        return SanitizeOverlayPresetId(preset) switch
        {
            OverlayPresetDefault => OverlayPresetDefault,
            OverlayPresetCombat => OverlayPresetCombat,
            OverlayPresetCompact => OverlayPresetCompact,
            OverlayPresetCommand => OverlayPresetCommand,
            OverlayPresetCustom => OverlayPresetCustom,
            _ => OverlayPresetDefault
        };
    }

    private OverlayDisplaySettings CreateDefaultOverlaySettings(string preset)
    {
        var settings = NormalizeOverlayPreset(preset) switch
        {
            OverlayPresetDefault => OverlayDefaultPreset.Settings,
            OverlayPresetCompact => OverlayDisplaySettings.Default with
            {
                HideMissionWhenIdle = false,
                HideOfflineMembers = true,
                HideSquadIcons = true,
                Opacity = 0.78,
                ShowNotice = true,
                ShowSquads = true,
                ShowMission = false,
                ShowMembers = true
            },
            OverlayPresetCommand => OverlayDisplaySettings.Default with
            {
                HideMissionWhenIdle = false,
                HideOfflineMembers = false,
                HideSquadIcons = false,
                Opacity = 0.9,
                ShowNotice = true,
                ShowSquads = true,
                ShowMission = false,
                ShowMembers = true
            },
            _ => OverlayDisplaySettings.Default
        };

        return ApplyOverlayFeatureLocks(settings);
    }

    private void LoadOverlayLayout(string? serialized)
    {
        _overlayLayout.Clear();
        var parsed = OverlayLayoutItem.ParseMany(serialized).ToArray();
        var layout = parsed.Length == 0
            ? CreateDefaultOverlayLayout(_activeOverlayPreset).ToList()
            : parsed.ToList();
        if (!layout.Any(item => item.Key.Equals("Chat", StringComparison.OrdinalIgnoreCase)))
        {
            var chatDefault = CreateDefaultOverlayLayout(_activeOverlayPreset)
                .First(item => item.Key.Equals("Chat", StringComparison.OrdinalIgnoreCase));
            layout.Add(chatDefault);
        }

        _overlayLayout.AddRange(layout);
        foreach (var item in _overlayLayout.Where(IsCommunicationEventModule))
        {
            NormalizeCommunicationEventDock(item);
        }
    }

    private static bool IsCommunicationEventModule(OverlayLayoutItem? item) =>
        item?.Key.Equals("Notice", StringComparison.OrdinalIgnoreCase) == true;

    private static void NormalizeCommunicationEventDock(OverlayLayoutItem item)
    {
        var dockBottom = item.VerticalAnchor == OverlayVerticalAnchor.Bottom ||
                         item.Y + item.Height / 2 >= 0.5;
        item.VerticalAnchor = dockBottom ? OverlayVerticalAnchor.Bottom : OverlayVerticalAnchor.Top;
        item.Y = dockBottom ? Math.Max(0, 1 - item.Height) : 0;
    }

    private Rect ConstrainCommunicationEventRect(OverlayLayoutItem item, Rect rect)
    {
        if (!IsCommunicationEventModule(item) || OverlayEditorCanvas is null)
        {
            return rect;
        }

        var clamped = ClampOverlayEditorRect(rect);
        var dockBottom = clamped.Top + clamped.Height / 2 >= OverlayEditorCanvas.Height / 2;
        return new Rect(
            clamped.Left,
            dockBottom ? Math.Max(0, OverlayEditorCanvas.Height - clamped.Height) : 0,
            clamped.Width,
            clamped.Height);
    }

    private string SerializeOverlayLayout()
    {
        return SerializeOverlayLayout(_overlayLayout);
    }

    private static string SerializeOverlayLayout(IEnumerable<OverlayLayoutItem> layout)
    {
        return string.Join(
            ";",
            layout
                .Where(item => !OverlayLayoutItem.IsRetiredModuleKey(item.Key))
                .Select(item => item.Serialize()));
    }

    private OverlaySkin GetSelectedOverlaySkin()
    {
        return OverlaySkinBox?.SelectedItem is ComboBoxItem { Tag: OverlaySkin selectedSkin }
            ? selectedSkin
            : _selectedOverlaySkin;
    }

    private void SelectOverlaySkin(OverlaySkin skin)
    {
        var profile = OverlaySkinCatalog.Get(skin);
        _selectedOverlaySkin = profile.IsReleased
            ? profile.Id
            : OverlaySkin.Default;

        if (OverlaySkinBox is null)
        {
            return;
        }

        foreach (var item in OverlaySkinBox.Items.OfType<ComboBoxItem>())
        {
            if (item.Tag is OverlaySkin option && option == _selectedOverlaySkin)
            {
                OverlaySkinBox.SelectedItem = item;
                return;
            }
        }
    }

    private void RefreshOverlaySkinOptions()
    {
        if (OverlaySkinBox is null)
        {
            return;
        }

        var selectedSkin = OverlaySkinCatalog.Get(_overlaySettings.Skin).IsReleased
            ? _overlaySettings.Skin
            : OverlaySkin.Default;
        var zh = _language.Equals("zh", StringComparison.OrdinalIgnoreCase);
        var wasLoadingSettings = _isLoadingSettings;
        _isLoadingSettings = true;
        try
        {
            OverlaySkinBox.Items.Clear();
            foreach (var profile in OverlaySkinCatalog.Released)
            {
                var available = CanUseOverlaySkin(profile.Id);
                OverlaySkinBox.Items.Add(new ComboBoxItem
                {
                    Tag = profile.Id,
                    Content = available
                        ? profile.DisplayName(_language)
                        : zh
                            ? $"{profile.DisplayNameZh}（未解锁）"
                            : $"{profile.DisplayNameEn} (locked)",
                    IsEnabled = available
                });
            }

            var selectedItem = OverlaySkinBox.Items
                .OfType<ComboBoxItem>()
                .FirstOrDefault(item =>
                    item.IsEnabled &&
                    item.Tag is OverlaySkin option &&
                    option == selectedSkin)
                ?? OverlaySkinBox.Items
                    .OfType<ComboBoxItem>()
                    .FirstOrDefault(item =>
                        item.IsEnabled &&
                        item.Tag is OverlaySkin option &&
                        option == OverlaySkin.Default);

            OverlaySkinBox.SelectedItem = selectedItem;
            _selectedOverlaySkin = selectedItem?.Tag is OverlaySkin selected
                ? selected
                : OverlaySkin.Default;
        }
        finally
        {
            _isLoadingSettings = wasLoadingSettings;
        }
    }

    private void ApplyOverlaySettingsToControls()
    {
        _overlaySettings = ApplyOverlayFeatureLocks(_overlaySettings);
        RefreshOverlaySkinOptions();

        if (OverlayPresetBox is not null)
        {
            RefreshOverlayPresetBoxItems();
        }

        TrayModeCheck.IsChecked = _overlaySettings.EnableTrayMode;
        ShowNoticePanelCheck.IsChecked = _overlaySettings.ShowNotice;
        ShowSquadsPanelCheck.IsChecked = _overlaySettings.ShowSquads;
        ShowMembersPanelCheck.IsChecked = _overlaySettings.ShowMembers;
        ShowChatPanelCheck.IsChecked = _overlaySettings.ShowChat;
        ShowEventNotificationsCheck.IsChecked = _overlaySettings.ShowEventNotifications;
        OverlayInspectorCommunicationFriendEventsCheck.IsChecked = _overlaySettings.CommunicationFriendEvents;
        OverlayInspectorCommunicationMessagePreviewCheck.IsChecked = _overlaySettings.CommunicationMessagePreview;
        OverlayInspectorCommunicationDurationSlider.Value =
            OverlayDisplaySettings.NormalizeCommunicationEventDuration(_overlaySettings.CommunicationEventDurationSeconds);
        OverlayInspectorCommunicationDurationValueText.Text =
            $"{_overlaySettings.CommunicationEventDurationSeconds:0.#}s";
        RefreshOverlayCommunicationEventControls();
        ApplyOverlayEventNotificationTypeChecks(_overlaySettings.EventNotificationTypes);
        SetComboBoxSelectedTag(OverlayEventMaxCountBox, OverlayDisplaySettings.NormalizeEventNotificationMaxVisibleCount(_overlaySettings.EventNotificationMaxVisibleCount).ToString(CultureInfo.InvariantCulture));
        OverlayEventPinImportantCheck.IsChecked = _overlaySettings.EventNotificationPinImportant;
        SetComboBoxSelectedTag(OverlayEventAnimationSpeedBox, _overlaySettings.EventNotificationAnimationSpeed.ToString());
        OverlayEventNotificationSideBox.SelectedIndex = _overlaySettings.EventNotificationSide == OverlayEventNotificationSide.Left ? 0 : 1;
        OverlayEventNotificationDurationSlider.Value = Math.Clamp(_overlaySettings.EventNotificationDurationSeconds, 1, 12);
        SelectOverlaySkin(_overlaySettings.Skin);
        SetComboBoxSelectedTag(OverlayNightShadowBloomBox, _overlaySettings.NightShadowBloom.ToString());
        SetComboBoxSelectedTag(OverlayAnimationFrameRateBox, _overlaySettings.AnimationFrameRate.ToString());
        _isSyncingOverlaySceneControls = true;
        try
        {
            SetComboBoxSelectedTag(OverlaySceneModeBox, _overlaySettings.ScenePreference.ToString());
            SetComboBoxSelectedTag(OverlayBehaviorSceneModeBox, _overlaySettings.ScenePreference.ToString());
            SetComboBoxSelectedTag(OverlayFullScreenSceneModeBox, _overlaySettings.ScenePreference.ToString());
        }
        finally
        {
            _isSyncingOverlaySceneControls = false;
        }
        AutoThemeByShipCheck.IsChecked = _overlaySettings.AutoThemeByShip;
        ShowCrosshairCheck.IsChecked = _overlaySettings.ShowCrosshair;
        SetComboBoxSelectedTag(
            CrosshairModeBox,
            OverlayDisplaySettings.NormalizeCrosshairMode(_overlaySettings.CrosshairMode).ToString());
        CrosshairThemeColorCheck.IsChecked = _overlaySettings.CrosshairUseThemeColor;
        CrosshairSizeSlider.Value = OverlayDisplaySettings.NormalizeCrosshairSize(_overlaySettings.CrosshairSize);
        CrosshairThicknessSlider.Value = Math.Clamp(_overlaySettings.CrosshairThickness, 1, 8);
        CrosshairGapSlider.Value = OverlayDisplaySettings.NormalizeCrosshairGap(_overlaySettings.CrosshairGap);
        CrosshairCenterMarkCheck.IsChecked = _overlaySettings.CrosshairShowCenterMark;
        CrosshairCenterSizeSlider.Value = OverlayDisplaySettings.NormalizeCrosshairCenterMarkSize(_overlaySettings.CrosshairCenterMarkSize);
        CrosshairOpacitySlider.Value = Math.Clamp(_overlaySettings.CrosshairOpacity, 0.2, 1.0) * 100.0;
        CrosshairOutlineOpacitySlider.Value = OverlayDisplaySettings.NormalizeCrosshairOutlineOpacity(_overlaySettings.CrosshairOutlineOpacity) * 100.0;
        CrosshairColorBox.Text = OverlayDisplaySettings.NormalizeCrosshairColor(_overlaySettings.CrosshairColor);
        OverlayThemeBox.SelectedIndex = _overlaySettings.Theme switch
        {
            OverlayVisualTheme.Anvil => 1,
            OverlayVisualTheme.Drake => 2,
            OverlayVisualTheme.Argo => 3,
            OverlayVisualTheme.Musashi => 4,
            OverlayVisualTheme.Mirai => 5,
            OverlayVisualTheme.Crusader => 6,
            OverlayVisualTheme.Aegis => 7,
            OverlayVisualTheme.Rsi => 8,
            OverlayVisualTheme.Origin => 9,
            OverlayVisualTheme.Aopoa => 10,
            OverlayVisualTheme.Esperia => 11,
            OverlayVisualTheme.Gatac => 12,
            _ => 0
        };
        OverlayOpacitySlider.Value = Math.Clamp(_overlaySettings.Opacity, 0.15, 1.0) * 100.0;
        OverlayOpacityValueText.Text = $"{Math.Round(OverlayOpacitySlider.Value)}%";
        OverlayTransitionEnabledCheck.IsChecked = _overlaySettings.EnableStartupTransition;
        OverlaySkipTransitionInGameCheck.IsChecked = _overlaySettings.SkipStartupTransitionWhenGameForeground;
        OverlayAutoFocusGameWindowCheck.IsChecked = _overlaySettings.AutoFocusGameWindowOnOpen;
        OverlayAutoOpenOnGameStartCheck.IsChecked = _overlaySettings.AutoOpenOverlayOnGameStart;
        OverlayAutoOpenOnGameForegroundCheck.IsChecked = _overlaySettings.AutoOpenOverlayOnGameForeground;
        OverlayAutoCloseOnGameBackgroundCheck.IsChecked = _overlaySettings.AutoCloseOverlayOnGameBackground;
        OverlayTransitionFrameRateBox.SelectedIndex = _overlaySettings.StartupTransitionFrameRate switch
        {
            OverlayStartupTransitionFrameRate.Fps45 => 1,
            OverlayStartupTransitionFrameRate.Fps60 => 2,
            OverlayStartupTransitionFrameRate.Fps120 => 3,
            _ => 0
        };
        RefreshCrosshairSettingLabels();
        RefreshOverlayTransitionControls();
        RefreshOverlaySkinControls();
        RefreshOverlayEventNotificationControls();
        RefreshOverlayHiddenModuleLibrary();
    }

    private void RefreshOverlayTransitionControls()
    {
        if (OverlayTransitionEnabledCheck is null ||
            OverlaySkipTransitionInGameCheck is null ||
            OverlayTransitionFrameRateBox is null ||
            OverlayTransitionStyleValueText is null ||
            OverlayTransitionStyleHintText is null)
        {
            return;
        }

        var enabled = OverlayTransitionEnabledCheck.IsChecked == true;
        OverlaySkipTransitionInGameCheck.IsEnabled = enabled;
        OverlaySkipTransitionInGameCheck.Opacity = enabled ? 1.0 : 0.48;
        OverlayTransitionFrameRateBox.IsEnabled = enabled;
        OverlayTransitionFrameRateBox.Opacity = enabled ? 1.0 : 0.58;
        var zh = _language.Equals("zh", StringComparison.OrdinalIgnoreCase);
        OverlayTransitionStyleValueText.Text = _overlaySettings.StartupTransitionStyle switch
        {
            OverlayStartupTransitionStyle.NightShadowFlowField => zh ? "夜影流场接入" : "Night Shadow flow field",
            OverlayStartupTransitionStyle.LagrangeWeaveEquilibrium => zh ? "平衡点求解" : "Equilibrium solve",
            OverlayStartupTransitionStyle.VerdictProtocol => zh ? "裁决协议" : "Verdict protocol",
            _ => zh ? "舰桥终端接入" : "Bridge terminal link"
        };
        OverlayTransitionStyleHintText.Text = zh
            ? "随当前外观风格自动切换"
            : "Automatically follows the active appearance";
        RefreshOverlayExperiencePresetStatus();
    }

    private void RefreshOverlaySkinControls()
    {
        RefreshOverlaySkinOptions();
        var profile = OverlaySkinCatalog.Get(_overlaySettings.Skin);
        var skinLocked = profile.LocksTheme;
        var skinAvailable = CanUseOverlaySkin(profile.Id);
        var zh = _language.Equals("zh", StringComparison.OrdinalIgnoreCase);
        var wasLoadingSettings = _isLoadingSettings;
        _isLoadingSettings = true;
        try
        {
            SelectOverlaySkin(_overlaySettings.Skin);

            if (skinLocked)
            {
                if (AutoThemeByShipCheck is not null)
                {
                    AutoThemeByShipCheck.IsChecked = false;
                }

                if (CrosshairColorBox is not null)
                {
                    CrosshairColorBox.Text = OverlayDisplaySettings.NormalizeCrosshairColor(_overlaySettings.CrosshairColor);
                }

            }
        }
        finally
        {
            _isLoadingSettings = wasLoadingSettings;
        }

        if (OverlaySkinLockedHintText is not null)
        {
            OverlaySkinLockedHintText.Text = !skinAvailable
                ? zh
                    ? $"“{profile.DisplayNameZh}”需要对应的账号使用资格。"
                    : $"{profile.DisplayNameEn} requires an account entitlement."
                : zh
                    ? $"“{profile.DisplayNameZh}”使用固定配色，颜色方案不可单独更改。"
                    : $"{profile.DisplayNameEn} uses a fixed palette; color scheme controls are read-only.";
            OverlaySkinLockedHintText.Visibility = skinLocked || !skinAvailable
                ? Visibility.Visible
                : Visibility.Collapsed;
        }

        if (OverlayNightShadowBloomBox is not null)
        {
            OverlayNightShadowBloomBox.Visibility = profile.SupportsBloom ? Visibility.Visible : Visibility.Collapsed;
            OverlayNightShadowBloomBox.IsEnabled = profile.SupportsBloom;
            OverlayNightShadowBloomBox.Opacity = 1.0;
        }

        if (OverlayNightShadowBloomLabel is not null)
        {
            OverlayNightShadowBloomLabel.Visibility = profile.SupportsBloom ? Visibility.Visible : Visibility.Collapsed;
            OverlayNightShadowBloomLabel.Opacity = 1.0;
        }

        if (OverlayThemeBox is not null)
        {
            OverlayThemeBox.Visibility = skinLocked ? Visibility.Collapsed : Visibility.Visible;
            OverlayThemeBox.IsEnabled = !skinLocked;
            OverlayThemeBox.Opacity = skinLocked ? 0.58 : 1.0;
        }

        if (OverlayThemeLockedValueText is not null)
        {
            OverlayThemeLockedValueText.Visibility = skinLocked ? Visibility.Visible : Visibility.Collapsed;
        }

        if (AutoThemeByShipCheck is not null)
        {
            AutoThemeByShipCheck.IsEnabled = !skinLocked;
            AutoThemeByShipCheck.Opacity = skinLocked ? 0.58 : 1.0;
        }

        var useThemeColor = CrosshairThemeColorCheck?.IsChecked == true;
        if (CrosshairThemeColorCheck is not null)
        {
            CrosshairThemeColorCheck.IsEnabled = true;
            CrosshairThemeColorCheck.Opacity = 1.0;
        }

        if (CrosshairColorBox is not null)
        {
            CrosshairColorBox.IsEnabled = !useThemeColor;
            CrosshairColorBox.Opacity = CrosshairColorBox.IsEnabled ? 1.0 : 0.6;
        }

        if (CrosshairColorPickerButton is not null)
        {
            CrosshairColorPickerButton.IsEnabled = !useThemeColor;
            CrosshairColorPickerButton.Opacity = CrosshairColorPickerButton.IsEnabled ? 1.0 : 0.6;
        }
    }

    private void RefreshOverlayEventNotificationControls()
    {
        if (ShowEventNotificationsCheck is null ||
            OverlayEventMaxCountBox is null ||
            OverlayEventPinImportantCheck is null ||
            OverlayEventAnimationSpeedBox is null ||
            OverlayEventNotificationSideBox is null ||
            OverlayEventNotificationDurationSlider is null ||
            OverlayEventNotificationDurationValueText is null)
        {
            return;
        }

        var enabled = ShowEventNotificationsCheck.IsChecked == true;
        OverlayEventMaxCountBox.IsEnabled = enabled;
        OverlayEventMaxCountBox.Opacity = enabled ? 1.0 : 0.58;
        OverlayEventPinImportantCheck.IsEnabled = enabled;
        OverlayEventPinImportantCheck.Opacity = enabled ? 1.0 : 0.58;
        OverlayEventAnimationSpeedBox.IsEnabled = enabled;
        OverlayEventAnimationSpeedBox.Opacity = enabled ? 1.0 : 0.58;
        OverlayEventNotificationSideBox.IsEnabled = enabled;
        OverlayEventNotificationSideBox.Opacity = enabled ? 1.0 : 0.58;
        OverlayEventNotificationDurationSlider.IsEnabled = enabled;
        OverlayEventNotificationDurationSlider.Opacity = enabled ? 1.0 : 0.58;
        OverlayEventNotificationDurationValueText.Text = $"{OverlayEventNotificationDurationSlider.Value:0.#}s";

        foreach (var checkBox in GetOverlayEventNotificationTypeCheckBoxes())
        {
            checkBox.IsEnabled = enabled;
            checkBox.Opacity = enabled ? 1.0 : 0.58;
        }

        RefreshOverlayEventDurationOverrideControls();
        SyncOverlayInspectorEventControls();
        SyncOverlayFullScreenEventControls();
    }

    private void OverlayEventNotificationSideBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_isLoadingSettings || _isSyncingOverlayInspectorModuleControls)
        {
            return;
        }

        CommitOverlayModuleSettings(BuildOverlayModuleSettingsFromControls("EventNotifications", useFullScreenControls: false));
    }

    private bool IsOverlayRunning =>
        IsInformationOverlayRunning ||
        _inGameMenuCoordinator.IsOpen;

    private void RefreshOverlayRuntimeStatus()
    {
        var informationVisible = IsInformationOverlayRunning;
        var zh = _language.Equals("zh", StringComparison.OrdinalIgnoreCase);
        var menuVisible = _inGameMenuCoordinator.IsOpen;
        var informationStatusText = zh
            ? informationVisible ? "显示中" : "已隐藏"
            : informationVisible ? "Visible" : "Hidden";
        var menuHotkeyReady =
            _inGameMenuSettings.EnableHotkey &&
            _menuHotkeyBindingState ==
                OverlayHotkeyBindingState.Ready &&
            _menuHotkeyListenerReady;
        var menuStatusText = zh
            ? menuVisible
                ? "已打开"
                : menuHotkeyReady
                    ? "热键可用"
                    : _inGameMenuSettings.EnableHotkey
                        ? "热键不可用"
                        : "可手动打开"
            : menuVisible
                ? "Open"
                : menuHotkeyReady
                    ? "Shortcut ready"
                    : _inGameMenuSettings.EnableHotkey
                        ? "Shortcut unavailable"
                        : "Manual open";
        var summaryText = zh
            ? informationVisible ? "已开启" : "未开启"
            : informationVisible ? "Active" : "Inactive";
        var actionText = zh
            ? informationVisible ? "关闭信息浮层" : "信息浮层"
            : informationVisible ? "Close information" : "Information overlay";
        var informationStatusBrush = FindBrush(
            informationVisible ? "StatusSuccessBrush" : "StatusDisabledBrush",
            informationVisible ? Brushes.SpringGreen : Brushes.LightSlateGray);
        var menuStatusBrush = menuVisible
            ? FindBrush("StatusSuccessBrush", Brushes.SpringGreen)
            : menuHotkeyReady
                ? new SolidColorBrush(Color.FromRgb(139, 124, 255))
                : FindBrush(
                    _inGameMenuSettings.EnableHotkey
                        ? "StatusWarningBrush"
                        : "StatusDisabledBrush",
                    _inGameMenuSettings.EnableHotkey
                        ? Brushes.Goldenrod
                        : Brushes.LightSlateGray);

        if (OverlayHeaderStatusText is not null)
        {
            OverlayHeaderStatusText.Text = informationStatusText;
            OverlayHeaderStatusText.Foreground = informationStatusBrush;
        }

        if (OverlayHeaderStatusDot is not null)
        {
            OverlayHeaderStatusDot.Fill = informationStatusBrush;
        }

        if (OverlayHeaderMenuStatusText is not null)
        {
            OverlayHeaderMenuStatusText.Text = menuStatusText;
            OverlayHeaderMenuStatusText.Foreground = menuStatusBrush;
        }

        if (OverlayHeaderMenuStatusDot is not null)
        {
            OverlayHeaderMenuStatusDot.Fill = menuStatusBrush;
        }

        if (OverlayOverviewStatusText is not null)
        {
            OverlayOverviewStatusText.Text = summaryText;
            OverlayOverviewStatusText.Foreground = informationStatusBrush;
        }

        ApplyOverlaySettingsWorkspacePresentation();

        if (OverlayHeaderInformationPreviewButton is not null)
        {
            OverlayHeaderInformationPreviewButton.Content = informationVisible
                ? zh ? "关闭浮层" : "Close overlay"
                : zh ? "打开浮层" : "Open overlay";
        }

        if (OverlayHeaderMenuPreviewButton is not null)
        {
            OverlayHeaderMenuPreviewButton.Content = menuVisible
                ? zh ? "关闭菜单浮层" : "Close game menu"
                : zh ? "打开菜单浮层" : "Open game menu";
        }

        if (MenuOverlayRailPreviewButton is not null)
        {
            MenuOverlayRailPreviewButton.Content = menuVisible
                ? zh ? "关闭菜单浮层" : "Close game menu"
                : zh ? "打开菜单浮层" : "Open game menu";
        }

        if (OverlayFullScreenStartOverlayButton is not null)
        {
            OverlayFullScreenStartOverlayButton.Content = actionText;
        }
    }

    private void OverlayAnimationFrameRateBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_isLoadingSettings)
        {
            return;
        }

        OverlaySetting_Changed(sender, e);
    }

    private void OverlaySceneModeBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_isLoadingSettings || _isSyncingOverlaySceneControls ||
            sender is not System.Windows.Controls.ComboBox comboBox ||
            comboBox.SelectedItem is not ComboBoxItem item ||
            !Enum.TryParse<OverlayScenePreference>(item.Tag?.ToString(), out var preference))
        {
            return;
        }

        var historyState = CreateOverlayEditorHistoryState();
        _overlaySettings = _overlaySettings with { ScenePreference = preference };
        _isSyncingOverlaySceneControls = true;
        try
        {
            SetComboBoxSelectedTag(OverlaySceneModeBox, preference.ToString());
            SetComboBoxSelectedTag(OverlayBehaviorSceneModeBox, preference.ToString());
            SetComboBoxSelectedTag(OverlayFullScreenSceneModeBox, preference.ToString());
        }
        finally
        {
            _isSyncingOverlaySceneControls = false;
        }

        PushOverlayEditorUndoState(historyState);
        MarkOverlayEditorLayoutDirty();
        SaveCurrentConfig();
        RenderOverlayEditor();
        RefreshOverlayInspector();
        RefreshOverlayWindow();
    }

    private void RefreshOverlaySceneChrome()
    {
        if (OverlayPreviewTitleText is null)
        {
            return;
        }

        var scene = ResolveCurrentOverlayScene().Context;
        var zh = _language.Equals("zh", StringComparison.OrdinalIgnoreCase);
        var sceneName = scene.Kind == OverlaySceneKind.PartyRoom
            ? zh ? "当前房间" : "Party"
            : zh ? "舰队" : "Fleet";
        var fallback = scene.IsFallback
            ? zh ? "（当前无房间，已回退舰队）" : " (no party; using fleet)"
            : "";
        OverlayPreviewTitleText.Text = zh
            ? $"我的屏幕布局 · {sceneName}{fallback}"
            : $"My Screen Layout · {sceneName}{fallback}";
    }

    private void OverlayEventNotificationOptions_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_isLoadingSettings)
        {
            return;
        }

        OverlaySetting_Changed(sender, e);
    }

    private void OverlayEventNotificationDurationSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (OverlayEventNotificationDurationValueText is not null)
        {
            OverlayEventNotificationDurationValueText.Text = $"{e.NewValue:0.#}s";
        }

        if (_isLoadingSettings || _isSyncingOverlayInspectorModuleControls)
        {
            return;
        }

        CommitOverlayModuleSettings(BuildOverlayModuleSettingsFromControls("EventNotifications", useFullScreenControls: false));
    }

    private void RefreshCrosshairSettingLabels()
    {
        if (CrosshairSizeSlider is null ||
            CrosshairThicknessSlider is null ||
            CrosshairGapSlider is null ||
            CrosshairCenterMarkCheck is null ||
            CrosshairCenterSizeSlider is null ||
            CrosshairOpacitySlider is null ||
            CrosshairOutlineOpacitySlider is null ||
            CrosshairSizeValueText is null ||
            CrosshairThicknessValueText is null ||
            CrosshairGapValueText is null ||
            CrosshairCenterSizeValueText is null ||
            CrosshairOpacityValueText is null ||
            CrosshairOutlineOpacityValueText is null ||
            CrosshairColorBox is null ||
            CrosshairColorPreview is null ||
            CrosshairThemeColorCheck is null ||
            CrosshairColorPickerButton is null)
        {
            return;
        }

        CrosshairSizeValueText.Text = $"{Math.Round(CrosshairSizeSlider.Value)}px";
        CrosshairThicknessValueText.Text = $"{CrosshairThicknessSlider.Value:0.##}px";
        CrosshairGapValueText.Text = $"{Math.Round(CrosshairGapSlider.Value)}px";
        CrosshairCenterSizeValueText.Text = CrosshairCenterMarkCheck.IsChecked == true
            ? $"{Math.Round(CrosshairCenterSizeSlider.Value)}px"
            : _language.Equals("zh", StringComparison.OrdinalIgnoreCase) ? "关闭" : "Off";
        CrosshairOpacityValueText.Text = $"{Math.Round(CrosshairOpacitySlider.Value)}%";
        CrosshairOutlineOpacityValueText.Text = $"{Math.Round(CrosshairOutlineOpacitySlider.Value)}%";
        var usesThemeColor = CrosshairThemeColorCheck.IsChecked == true;
        CrosshairThemeColorCheck.IsEnabled = true;
        CrosshairThemeColorCheck.Opacity = 1.0;
        CrosshairColorBox.IsEnabled = !usesThemeColor;
        CrosshairColorBox.Opacity = usesThemeColor ? 0.6 : 1.0;
        CrosshairColorPickerButton.IsEnabled = !usesThemeColor;
        CrosshairColorPickerButton.Opacity = CrosshairColorPickerButton.IsEnabled ? 1.0 : 0.6;
        CrosshairCenterSizeSlider.IsEnabled = CrosshairCenterMarkCheck.IsChecked == true;
        CrosshairCenterSizeSlider.Opacity = CrosshairCenterSizeSlider.IsEnabled ? 1.0 : 0.55;
        RefreshCrosshairModeControlAvailability();

        CrosshairColorPreview.Background = usesThemeColor
            ? GetOverlayThemeAccent(GetEffectiveOverlaySettings().Theme)
            : new SolidColorBrush(TryParseHexColor(CrosshairColorBox.Text, out var parsed)
                ? parsed
                : Color.FromRgb(235, 247, 255));
    }
}
