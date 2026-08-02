using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace StarBridge.Desktop;

internal enum InGameMenuLayoutPreset
{
    BottomDock,
    LeftRail
}

internal enum InGameMenuTool
{
    InformationOverlay,
    Fleet,
    Friends,
    Chat,
    Rooms,
    Screenshot,
    Image,
    Browser
}

internal enum InGameMenuToolbarDensity
{
    Compact,
    Standard,
    Comfortable
}

internal enum InGameMenuToolLabelMode
{
    Auto,
    Always,
    IconsOnly
}

internal enum InGameMenuClockFormat
{
    System,
    TwentyFourHour,
    TwelveHour
}

internal enum InGameMenuImageOpenMode
{
    Edit,
    ImageOnly
}

internal enum InGameMenuImageScaleMode
{
    Fit,
    ActualSize
}

internal enum InGameMenuScreenshotFormat
{
    Png,
    Jpeg
}

internal enum InGameMenuCommunicationLanding
{
    LastUsed,
    DirectMessages,
    Channels
}

internal enum InGameMenuFriendSortMode
{
    OnlineFirst,
    Alphabetical
}

internal enum InGameMenuInvitationPreviewMode
{
    Full,
    SenderOnly,
    Hidden
}

internal enum InGameMenuCrashRecoveryMode
{
    Ask,
    Restore,
    StartClean
}

internal enum InGameMenuMotionMode
{
    System,
    Reduced,
    Off
}

internal enum InGameMenuPerformanceMode
{
    Auto,
    Smooth,
    ResourceSaving
}

internal enum InGameMenuCompatibilityMode
{
    Auto,
    Hardware,
    Software
}

internal sealed record InGameMenuSettings
{
    internal const string DefaultToolOrder =
        "InformationOverlay,Fleet,Friends,Chat,Rooms,Screenshot,Image,Browser";

    public string Hotkey { get; init; } = "Alt+M";
    public bool EnableHotkey { get; init; } = true;
    public bool RestoreOpenTools { get; init; } = true;
    public InGameMenuLayoutPreset LayoutPreset { get; init; } =
        InGameMenuLayoutPreset.BottomDock;
    public bool CloseWithHotkey { get; init; } = true;

    public bool ShowFleetTool { get; init; } = true;
    public bool ShowFriendsTool { get; init; } = true;
    public bool ShowChatTool { get; init; } = true;
    public bool ShowRoomsTool { get; init; } = true;
    public bool ShowScreenshotTool { get; init; } = true;
    public bool ShowImageTool { get; init; } = true;
    public bool ShowBrowserTool { get; init; } = true;
    public string ToolOrder { get; init; } = DefaultToolOrder;
    public InGameMenuToolbarDensity ToolbarDensity { get; init; } =
        InGameMenuToolbarDensity.Standard;
    public InGameMenuToolLabelMode ToolLabelMode { get; init; } =
        InGameMenuToolLabelMode.Auto;
    public bool ShowUnreadBadges { get; init; } = true;

    public bool ShowContextBar { get; init; } = true;
    public bool ShowScene { get; init; } = true;
    public bool ShowMemberCount { get; init; } = true;
    public bool ShowShip { get; init; } = true;
    public bool ShowLocation { get; init; } = true;
    public bool ShowServer { get; init; } = true;
    public bool ShowClock { get; init; } = true;
    public bool ShowDate { get; init; }
    public bool ShowPresence { get; init; } = true;
    public InGameMenuClockFormat ClockFormat { get; init; } =
        InGameMenuClockFormat.System;

    public string BrowserProviderKey { get; init; } = "bing-cn";
    public bool BrowserRestorePreviousPage { get; init; } = true;
    public bool BrowserOpenLinksInNewTab { get; init; } = true;
    public bool BrowserPauseWhenHidden { get; init; } = true;
    public int BrowserTabLimit { get; init; } = 8;

    public InGameMenuImageOpenMode ImageOpenMode { get; init; } =
        InGameMenuImageOpenMode.Edit;
    public InGameMenuImageScaleMode ImageScaleMode { get; init; } =
        InGameMenuImageScaleMode.Fit;
    public int ImageDefaultOpacity { get; init; } = 100;
    public bool RememberImageAdjustments { get; init; } = true;
    public bool ImageDefaultPinned { get; init; }
    public int ImageWindowLimit { get; init; } = 5;
    public bool PauseHiddenAnimatedImages { get; init; } = true;

    public string ScreenshotDirectory { get; init; } = "";
    public InGameMenuScreenshotFormat ScreenshotFormat { get; init; } =
        InGameMenuScreenshotFormat.Png;
    public int ScreenshotJpegQuality { get; init; } = 90;
    public bool ScreenshotCopyToClipboard { get; init; } = true;
    public bool ScreenshotHideMenu { get; init; } = true;
    public bool ScreenshotShowNotification { get; init; } = true;

    public InGameMenuCommunicationLanding CommunicationLanding { get; init; } =
        InGameMenuCommunicationLanding.LastUsed;
    public InGameMenuFriendSortMode FriendSortMode { get; init; } =
        InGameMenuFriendSortMode.OnlineFirst;
    public bool ShowSocialNotifications { get; init; } = true;
    public bool SocialNotificationSound { get; init; }
    public InGameMenuInvitationPreviewMode InvitationPreviewMode { get; init; } =
        InGameMenuInvitationPreviewMode.SenderOnly;
    public bool LoadNetworkAvatars { get; init; } = true;

    public bool RestoreLastFocusedTool { get; init; } = true;
    public bool RememberWindowPlacement { get; init; } = true;
    public bool FitToolsToGameDisplay { get; init; } = true;
    public bool SnapToolWindows { get; init; } = true;
    public int SnapDistance { get; init; } = 12;
    public bool RestoreToolsAcrossRestarts { get; init; }
    public InGameMenuCrashRecoveryMode CrashRecoveryMode { get; init; } =
        InGameMenuCrashRecoveryMode.Ask;

    public int InterfaceScalePercent { get; init; }
    public int TextScalePercent { get; init; } = 100;
    public int BackgroundDimPercent { get; init; } = 65;
    public InGameMenuMotionMode MotionMode { get; init; } =
        InGameMenuMotionMode.System;
    public bool HighContrast { get; init; }
    public int ToolTipDelayMilliseconds { get; init; } = 500;

    public InGameMenuPerformanceMode PerformanceMode { get; init; } =
        InGameMenuPerformanceMode.Auto;
    public bool PauseUpdatesWhileDragging { get; init; } = true;
    public bool AutoReduceEffects { get; init; } = true;
    public InGameMenuCompatibilityMode CompatibilityMode { get; init; } =
        InGameMenuCompatibilityMode.Auto;

    public bool StreamerPrivacyMode { get; init; }
    public bool ShowExactLocation { get; init; } = true;
    public bool ShowRoomCode { get; init; } = true;
    public bool ConfirmExternalLinks { get; init; } = true;
    public bool SafeModeNextLaunch { get; init; }

    [JsonIgnore]
    internal bool IsSafeModeSession { get; init; }

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        PropertyNameCaseInsensitive = true,
        Converters = { new JsonStringEnumConverter() }
    };

    public InGameMenuSettings()
    {
    }

    internal InGameMenuSettings(
        string Hotkey,
        bool EnableHotkey,
        bool RestoreOpenTools,
        InGameMenuLayoutPreset LayoutPreset)
    {
        this.Hotkey = Hotkey;
        this.EnableHotkey = EnableHotkey;
        this.RestoreOpenTools = RestoreOpenTools;
        this.LayoutPreset = LayoutPreset;
    }

    internal static InGameMenuSettings Default { get; } = new();

    [JsonIgnore]
    internal bool EffectiveShowExactLocation =>
        ShowExactLocation && !StreamerPrivacyMode;

    [JsonIgnore]
    internal bool EffectiveShowRoomCode =>
        ShowRoomCode && !StreamerPrivacyMode;

    [JsonIgnore]
    internal bool EffectivePauseBrowserWhenHidden =>
        BrowserPauseWhenHidden ||
        EffectivePerformanceMode == InGameMenuPerformanceMode.ResourceSaving;

    [JsonIgnore]
    internal bool EffectivePauseAnimatedImages =>
        PauseHiddenAnimatedImages ||
        EffectivePerformanceMode == InGameMenuPerformanceMode.ResourceSaving;

    [JsonIgnore]
    internal InGameMenuPerformanceMode EffectivePerformanceMode =>
        IsSafeModeSession
            ? InGameMenuPerformanceMode.ResourceSaving
            : PerformanceMode;

    [JsonIgnore]
    internal InGameMenuMotionMode EffectiveMotionMode =>
        IsSafeModeSession ? InGameMenuMotionMode.Off : MotionMode;

    [JsonIgnore]
    internal InGameMenuCompatibilityMode EffectiveCompatibilityMode =>
        IsSafeModeSession
            ? InGameMenuCompatibilityMode.Software
            : CompatibilityMode;

    internal InGameMenuSettings Normalize()
    {
        var hotkey = OverlayHotkeyBindingPolicy.TryParse(
            Hotkey,
            out var parsedHotkey)
            ? parsedHotkey.StorageText
            : Default.Hotkey;
        return this with
        {
            Hotkey = hotkey,
            LayoutPreset = InGameMenuLayoutPreset.BottomDock,
            ToolOrder = NormalizeToolOrder(ToolOrder),
            BrowserProviderKey =
                InGameBrowserPreferences.NormalizeProviderKey(BrowserProviderKey),
            BrowserTabLimit = Math.Clamp(BrowserTabLimit, 1, 12),
            ImageDefaultOpacity = Math.Clamp(ImageDefaultOpacity, 20, 100),
            ImageWindowLimit = Math.Clamp(ImageWindowLimit, 1, 5),
            ScreenshotDirectory = ScreenshotDirectory?.Trim() ?? "",
            ScreenshotJpegQuality = Math.Clamp(ScreenshotJpegQuality, 50, 100),
            SnapDistance = Math.Clamp(SnapDistance, 0, 32),
            InterfaceScalePercent = NormalizeChoice(
                InterfaceScalePercent,
                [0, 85, 100, 115, 125],
                0),
            TextScalePercent = NormalizeChoice(
                TextScalePercent,
                [100, 110, 125],
                100),
            BackgroundDimPercent = Math.Clamp(BackgroundDimPercent, 35, 85),
            ToolTipDelayMilliseconds = Math.Clamp(
                ToolTipDelayMilliseconds,
                100,
                1500)
        };
    }

    internal IReadOnlyList<InGameMenuTool> ResolveToolOrder()
    {
        var normalized = NormalizeToolOrder(ToolOrder);
        return normalized
            .Split(',', StringSplitOptions.RemoveEmptyEntries)
            .Select(value => Enum.Parse<InGameMenuTool>(value))
            .ToArray();
    }

    internal bool IsToolVisible(InGameMenuTool tool) =>
        tool switch
        {
            InGameMenuTool.InformationOverlay => true,
            InGameMenuTool.Fleet => ShowFleetTool,
            InGameMenuTool.Friends => ShowFriendsTool,
            InGameMenuTool.Chat => ShowChatTool,
            InGameMenuTool.Rooms => ShowRoomsTool,
            InGameMenuTool.Screenshot => ShowScreenshotTool,
            InGameMenuTool.Image => ShowImageTool,
            InGameMenuTool.Browser => ShowBrowserTool,
            _ => false
        };

    internal InGameMenuSettings WithToolVisibility(
        InGameMenuTool tool,
        bool visible) =>
        tool switch
        {
            InGameMenuTool.Fleet => this with { ShowFleetTool = visible },
            InGameMenuTool.Friends => this with { ShowFriendsTool = visible },
            InGameMenuTool.Chat => this with { ShowChatTool = visible },
            InGameMenuTool.Rooms => this with { ShowRoomsTool = visible },
            InGameMenuTool.Screenshot => this with { ShowScreenshotTool = visible },
            InGameMenuTool.Image => this with { ShowImageTool = visible },
            InGameMenuTool.Browser => this with { ShowBrowserTool = visible },
            _ => this
        };

    internal string Serialize() =>
        JsonSerializer.Serialize(Normalize(), JsonOptions);

    internal static InGameMenuSettings Parse(string? payload)
    {
        if (string.IsNullOrWhiteSpace(payload))
        {
            return Default;
        }

        try
        {
            return JsonSerializer.Deserialize<InGameMenuSettings>(
                       payload,
                       JsonOptions)
                   ?.Normalize() ??
                   Default;
        }
        catch (JsonException)
        {
            return Default;
        }
    }

    private static int NormalizeChoice(
        int candidate,
        IReadOnlyCollection<int> choices,
        int fallback) =>
        choices.Contains(candidate) ? candidate : fallback;

    private static string NormalizeToolOrder(string? value)
    {
        var parsed = (value ?? "")
            .Split(',', StringSplitOptions.RemoveEmptyEntries)
            .Select(candidate => Enum.TryParse<InGameMenuTool>(
                candidate.Trim(),
                ignoreCase: true,
                out var tool)
                ? tool
                : (InGameMenuTool?)null)
            .Where(tool => tool is not null)
            .Select(tool => tool!.Value)
            .Distinct()
            .ToList();
        foreach (var tool in Enum.GetValues<InGameMenuTool>())
        {
            if (!parsed.Contains(tool))
            {
                parsed.Add(tool);
            }
        }

        // The current product has one fixed bottom layout. Keep collaboration
        // and local tools in their own groups so the visual divider remains
        // meaningful even when users reorder tools.
        var collaboration = parsed
            .Where(tool => tool is
                InGameMenuTool.InformationOverlay or
                InGameMenuTool.Fleet or
                InGameMenuTool.Friends or
                InGameMenuTool.Chat or
                InGameMenuTool.Rooms);
        var local = parsed
            .Where(tool => tool is
                InGameMenuTool.Screenshot or
                InGameMenuTool.Image or
                InGameMenuTool.Browser);
        return string.Join(
            ',',
            collaboration.Concat(local).Select(tool => tool.ToString()));
    }
}

internal sealed class InGameMenuSettingsStore
{
    private readonly string _settingsPath;

    internal InGameMenuSettingsStore(string settingsPath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(settingsPath);
        _settingsPath = settingsPath;
    }

    internal static InGameMenuSettingsStore CreateDefault() =>
        new(Path.Combine(
            DesktopAppConfig.ConfigDirectory,
            "in-game-menu.json"));

    internal InGameMenuSettings Load(
        bool legacyHotkeysEnabled = true,
        string? legacyBrowserProviderKey = null)
    {
        var fallback = InGameMenuSettings.Default with
        {
            EnableHotkey = legacyHotkeysEnabled,
            BrowserProviderKey =
                InGameBrowserPreferences.NormalizeProviderKey(
                    legacyBrowserProviderKey)
        };
        try
        {
            if (File.Exists(_settingsPath))
            {
                var payload = File.ReadAllText(_settingsPath);
                var loaded = InGameMenuSettings.Parse(payload);
                using var document = JsonDocument.Parse(payload);
                if (!document.RootElement.TryGetProperty(
                        nameof(InGameMenuSettings.BrowserProviderKey),
                        out _))
                {
                    loaded = loaded with
                    {
                        BrowserProviderKey = fallback.BrowserProviderKey
                    };
                }

                loaded = loaded.Normalize();
                if (!loaded.SafeModeNextLaunch)
                {
                    return loaded;
                }

                var persisted = loaded with { SafeModeNextLaunch = false };
                _ = TrySave(persisted, out _);
                return persisted with { IsSafeModeSession = true };
            }

            _ = TrySave(fallback, out _);
            return fallback;
        }
        catch
        {
            return fallback;
        }
    }

    internal bool TrySave(
        InGameMenuSettings settings,
        out string? error)
    {
        var temporaryPath = _settingsPath + ".tmp";
        try
        {
            var directory = Path.GetDirectoryName(_settingsPath);
            if (!string.IsNullOrWhiteSpace(directory))
            {
                Directory.CreateDirectory(directory);
            }

            File.WriteAllText(temporaryPath, settings.Normalize().Serialize());
            File.Move(temporaryPath, _settingsPath, overwrite: true);
            error = null;
            return true;
        }
        catch (Exception exception)
        {
            TryDeleteTemporaryFile(temporaryPath);
            error = UserFacingError.Describe(
                exception,
                "菜单浮层设置未保存，请稍后重试。");
            return false;
        }
    }

    private static void TryDeleteTemporaryFile(string path)
    {
        try
        {
            if (File.Exists(path))
            {
                File.Delete(path);
            }
        }
        catch
        {
            // A later successful save can replace a stale temporary file.
        }
    }
}
