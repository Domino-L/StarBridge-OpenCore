namespace StarBridge.HostRuntime.Settings;

using System.Text.Json;
using StarBridge.NativeBridge;

// Local menu desktop only. No account identifiers, paths, URLs, opened targets,
// drafts, screenshots or browser data are accepted in this file.
internal sealed class MenuPreferencesStore(string dataRoot) : IMenuHotkeyPreferences
{
    private readonly object _gate = new();
    private string? _startupToken;
    private bool? _startupSafe;
    private readonly string _path = Path.Combine(Path.GetFullPath(dataRoot), "menu-preferences.v1.json");
    private static readonly HashSet<string> Panels = ["friends", "comms", "organizations", "rooms", "hud", "screenshot", "image", "browser", "settings"];
    // Random UI-process receipt only, never an account or Windows process id.
    internal sealed record StartupReceipt(string Token, bool Safe);
    internal sealed record Snapshot(long Revision, JsonElement Layout, JsonElement Settings, MenuHotkeyOptions? Hotkey = null, StartupReceipt? Startup = null);
    internal static Snapshot Default => new(0,
        JsonSerializer.SerializeToElement(new { version = 1, panels = Array.Empty<object>(), open = Array.Empty<string>() }),
        JsonSerializer.SerializeToElement(new { showClock = true, showContext = true, dimming = 133d / 255, restoreDesktop = false, snapWindows = false }));

    internal Snapshot Read()
    {
        if (!File.Exists(_path)) return Default;
        if (new FileInfo(_path).Length > 32768) throw new IOException("Invalid menu preferences");
        try
        {
            using var document = JsonDocument.Parse(File.ReadAllText(_path));
            if (document.RootElement.TryGetProperty("startup", out var receiptData) && receiptData.ValueKind != JsonValueKind.Null)
            {
                Keys(receiptData, "token", "safe");
                if (!MenuSessionRecoveryStore.ValidToken(receiptData.GetProperty("token").GetString()) ||
                    receiptData.GetProperty("safe").ValueKind is not (JsonValueKind.True or JsonValueKind.False)) return Default;
            }
            var value = document.RootElement.Deserialize<Snapshot>(BridgeProtocol.JsonOptions);
            if (value is null || value.Revision < 0) return Default;
            Validate(value.Layout, value.Settings);
            (value.Hotkey ?? new()).Validate();
            if (value.Startup is { } receipt && !MenuSessionRecoveryStore.ValidToken(receipt.Token)) return Default;
            return value;
        }
        catch (Exception error) when (error is JsonException or ArgumentException or InvalidOperationException or FormatException) { return Default; }
    }

    internal Snapshot Save(long revision, JsonElement layout, JsonElement settings)
    {
        lock (_gate) return SaveCore(revision, layout, settings, null);
    }

    public MenuHotkeyPreferences ReadHotkey()
    {
        var value = Read();
        return new(value.Revision, value.Hotkey ?? new());
    }

    public MenuHotkeyPreferences SaveHotkey(long expectedRevision, MenuHotkeyOptions options)
    {
        options.Validate();
        lock (_gate)
        {
            var value = Read();
            var saved = SaveCore(expectedRevision, value.Layout, value.Settings, options);
            return new(saved.Revision, saved.Hotkey!);
        }
    }

    internal bool BeginStartup(string token)
    {
        if (!MenuSessionRecoveryStore.ValidToken(token)) throw new ArgumentException("Invalid startup token");
        lock (_gate)
        {
            if (_startupToken is not null && _startupToken != token)
                throw new ApplicationPreferencesException("menuStartup.owner_changed", "Startup owner changed");
            _startupToken = token;
            if (_startupSafe is { } known) return known;
            var current = Read();
            // Reply loss/Host reconnect must not consume a newly armed request.
            if (current.Startup?.Token == token) return (_startupSafe = current.Startup.Safe).Value;
            if (!current.Settings.TryGetProperty("safeModeNextLaunch", out var flag) || !flag.GetBoolean()) return (_startupSafe = false).Value;
            var settings = JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(current.Settings.GetRawText())!;
            settings["safeModeNextLaunch"] = JsonSerializer.SerializeToElement(false);
            SaveCore(current.Revision, current.Layout, JsonSerializer.SerializeToElement(settings), null, new(token, true));
            return (_startupSafe = true).Value; // Only after request and receipt are durable.
        }
    }

    private Snapshot SaveCore(long revision, JsonElement layout, JsonElement settings, MenuHotkeyOptions? hotkey, StartupReceipt? startup = null)
    {
        Validate(layout, settings);
        var current = Read();
        if (revision != current.Revision) throw new ApplicationPreferencesException("menuPreferences.revision_conflict", "Menu preferences changed", true);
        var next = new Snapshot(checked(revision + 1), layout.Clone(), settings.Clone(), hotkey ?? current.Hotkey, startup ?? current.Startup);
        var temporary = _path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
            using (var file = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough))
            {
                JsonSerializer.Serialize(file, next, BridgeProtocol.JsonOptions);
                file.Flush(true);
            }
            File.Move(temporary, _path, true);
            return next;
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }

    internal static void Validate(JsonElement layout, JsonElement settings)
    {
        Keys(layout, "version", "panels", "open");
        if (layout.GetProperty("version").GetInt32() != 1) throw new ArgumentException("Invalid version");
        var entries = layout.GetProperty("panels");
        var open = layout.GetProperty("open");
        if (entries.ValueKind != JsonValueKind.Array || entries.GetArrayLength() > Panels.Count || open.ValueKind != JsonValueKind.Array || open.GetArrayLength() > Panels.Count) throw new ArgumentException("Invalid panels");
        var opened = new HashSet<string>();
        foreach (var item in open.EnumerateArray())
        {
            if (item.ValueKind != JsonValueKind.String || item.GetString() is not { } id || !Panels.Contains(id) || !opened.Add(id)) throw new ArgumentException("Invalid opened panel");
        }
        var seen = new HashSet<string>();
        foreach (var entry in entries.EnumerateArray())
        {
            Keys(entry, "id", "bounds");
            var id = entry.GetProperty("id").GetString();
            if (id is null || !Panels.Contains(id) || !seen.Add(id)) throw new ArgumentException("Invalid panel");
            var bounds = entry.GetProperty("bounds");
            if (bounds.ValueKind != JsonValueKind.Array || bounds.GetArrayLength() != 4) throw new ArgumentException("Invalid bounds");
            var index = 0;
            foreach (var number in bounds.EnumerateArray())
            {
                if (!number.TryGetDouble(out var n) || !double.IsFinite(n) || Math.Abs(n) > 1000000 || (index >= 2 && n <= 0)) throw new ArgumentException("Invalid bounds");
                index++;
            }
        }
        // Read old three-field documents without resetting their geometry.
        var keys = new List<string> { "showClock", "showContext", "dimming" };
        foreach (var key in new[] { "restoreDesktop", "restoreAfterRestart", "restoreLastFocus", "safeModeNextLaunch", "snapWindows" })
            if (settings.TryGetProperty(key, out var flag))
            {
                if (flag.ValueKind is not (JsonValueKind.True or JsonValueKind.False)) throw new ArgumentException("Invalid desktop option");
                keys.Add(key);
            }
        if (settings.TryGetProperty("crashRecovery", out var recovery))
        {
            if (recovery.ValueKind != JsonValueKind.String || recovery.GetString() is not ("ask" or "restore" or "startClean")) throw new ArgumentException("Invalid recovery policy");
            keys.Add("crashRecovery");
        }
        if (settings.TryGetProperty("toolbar", out var toolbar))
        {
            if (toolbar.ValueKind != JsonValueKind.Object) throw new ArgumentException("Invalid toolbar presentation");
            var toolbarKeys = new List<string> { "order", "hidden", "density", "labels" };
            if (toolbar.TryGetProperty("showUnreadBadges", out var badges))
            {
                if (badges.ValueKind is not (JsonValueKind.True or JsonValueKind.False)) throw new ArgumentException("Invalid unread badge option");
                toolbarKeys.Add("showUnreadBadges");
            }
            Keys(toolbar, toolbarKeys.ToArray());
            string[] tools = ["hud", "organizations", "friends", "comms", "rooms", "screenshot", "image", "browser"];
            var order = toolbar.GetProperty("order");
            var hidden = toolbar.GetProperty("hidden");
            ValidateTools(order, tools, tools.Length, true);
            ValidateTools(hidden, tools.Where(id => id != "hud").ToArray(), tools.Length - 1, false);
            if (toolbar.GetProperty("density").GetString() is not ("compact" or "standard" or "comfortable") ||
                toolbar.GetProperty("labels").GetString() is not ("auto" or "iconsOnly")) throw new ArgumentException("Invalid toolbar presentation");
            keys.Add("toolbar");
        }
        if (settings.TryGetProperty("display", out var display))
        {
            string[] flags = ["showDate", "showScene", "showMembers", "showShip", "showLocation", "showServer", "showPresence"];
            var displayKeys = new List<string>(flags) { "clockFormat" };
            if (display.TryGetProperty("tooltipDelayMilliseconds", out var tooltipDelay))
            {
                if (tooltipDelay.ValueKind != JsonValueKind.Number ||
                    !tooltipDelay.TryGetInt32(out var milliseconds) || milliseconds is < 100 or > 1500)
                    throw new ArgumentException("Invalid menu tooltip delay");
                displayKeys.Add("tooltipDelayMilliseconds");
            }
            if (display.TryGetProperty("interfaceScalePercent", out var interfaceScale))
            {
                if (interfaceScale.ValueKind != JsonValueKind.Number ||
                    !interfaceScale.TryGetInt32(out var percent) || percent is not (0 or 85 or 100 or 115 or 125))
                    throw new ArgumentException("Invalid menu interface scale");
                displayKeys.Add("interfaceScalePercent");
            }
            if (display.TryGetProperty("textScalePercent", out var textScale))
            {
                if (textScale.ValueKind != JsonValueKind.Number ||
                    !textScale.TryGetInt32(out var percent) || percent is not (100 or 110 or 125))
                    throw new ArgumentException("Invalid menu text scale");
                displayKeys.Add("textScalePercent");
            }
            foreach (var optional in new[] { "streamerPrivacy", "showRoomCode", "reduceMotion", "highContrast" })
                if (display.TryGetProperty(optional, out var flag))
                {
                    if (flag.ValueKind is not (JsonValueKind.True or JsonValueKind.False)) throw new ArgumentException("Invalid privacy option");
                    displayKeys.Add(optional);
                }
            Keys(display, displayKeys.ToArray());
            foreach (var flag in flags)
                if (display.GetProperty(flag).ValueKind is not (JsonValueKind.True or JsonValueKind.False)) throw new ArgumentException("Invalid display option");
            var clockFormat = display.GetProperty("clockFormat");
            if (clockFormat.ValueKind != JsonValueKind.String || clockFormat.GetString() is not ("system" or "twelveHour" or "twentyFourHour")) throw new ArgumentException("Invalid clock format");
            keys.Add("display");
        }
        if (settings.TryGetProperty("social", out var social))
        {
            var socialKeys = new List<string> { "friendSort" };
            if (social.TryGetProperty("showAvatars", out var showAvatars))
            {
                if (showAvatars.ValueKind is not (JsonValueKind.True or JsonValueKind.False))
                    throw new ArgumentException("Invalid menu avatar option");
                socialKeys.Add("showAvatars");
            }
            if (social.TryGetProperty("sound", out var sound))
            {
                if (sound.ValueKind is not (JsonValueKind.True or JsonValueKind.False))
                    throw new ArgumentException("Invalid menu sound option");
                socialKeys.Add("sound");
            }
            if (social.TryGetProperty("notifications", out var notifications))
            {
                if (notifications.ValueKind is not (JsonValueKind.True or JsonValueKind.False))
                    throw new ArgumentException("Invalid menu notification option");
                socialKeys.Add("notifications");
            }
            if (social.TryGetProperty("preview", out var preview))
            {
                if (preview.ValueKind != JsonValueKind.String || preview.GetString() is not
                    ("fullContent" or "sourceOnly" or "hiddenDetails"))
                    throw new ArgumentException("Invalid menu preview option");
                socialKeys.Add("preview");
            }
            Keys(social, socialKeys.ToArray());
            if (social.GetProperty("friendSort").ValueKind != JsonValueKind.String ||
                social.GetProperty("friendSort").GetString() is not ("onlineFirst" or "alphabetical"))
                throw new ArgumentException("Invalid friend sort");
            keys.Add("social");
        }
        if (settings.TryGetProperty("browser", out var browser))
        {
            Keys(browser, "provider", "tabLimit", "openLinksInNewTab", "pauseWhenHidden");
            var provider = browser.GetProperty("provider");
            var tabLimit = browser.GetProperty("tabLimit");
            if (provider.ValueKind != JsonValueKind.String || provider.GetString() is not
                ("bing-cn" or "baidu" or "google" or "duckduckgo" or "bing-global") ||
                tabLimit.ValueKind != JsonValueKind.Number || !tabLimit.TryGetInt32(out var limit) || limit is < 1 or > 12)
                throw new ArgumentException("Invalid browser preferences");
            foreach (var flag in new[] { "openLinksInNewTab", "pauseWhenHidden" })
                if (browser.GetProperty(flag).ValueKind is not (JsonValueKind.True or JsonValueKind.False))
                    throw new ArgumentException("Invalid browser option");
            keys.Add("browser");
        }
        if (settings.TryGetProperty("image", out var image))
        {
            var imageKeys = new List<string> { "openMode", "scaleMode", "opacityPercent" };
            foreach (var key in new[] { "rememberAdjustments", "defaultPinned" })
                if (image.TryGetProperty(key, out var flag))
                {
                    if (flag.ValueKind is not (JsonValueKind.True or JsonValueKind.False)) throw new ArgumentException("Invalid image option");
                    imageKeys.Add(key);
                }
            Keys(image, imageKeys.ToArray());
            var mode = image.GetProperty("openMode");
            var scale = image.GetProperty("scaleMode");
            var opacity = image.GetProperty("opacityPercent");
            if (mode.ValueKind != JsonValueKind.String || mode.GetString() is not ("edit" or "imageOnly") ||
                scale.ValueKind != JsonValueKind.String || scale.GetString() is not ("fit" or "actualSize") ||
                opacity.ValueKind != JsonValueKind.Number || !opacity.TryGetInt32(out var percent) || percent is < 20 or > 100)
                throw new ArgumentException("Invalid image preferences");
            keys.Add("image");
        }
        if (settings.TryGetProperty("screenshot", out var screenshot))
        {
            var screenshotKeys = new List<string> { "format", "jpegQuality", "copyAfterSave", "showConfirmation" };
            if (screenshot.ValueKind == JsonValueKind.Object && screenshot.TryGetProperty("hideMenu", out var hideMenu))
            {
                if (hideMenu.ValueKind is not (JsonValueKind.True or JsonValueKind.False)) throw new ArgumentException("Invalid screenshot visibility");
                screenshotKeys.Add("hideMenu");
            }
            Keys(screenshot, screenshotKeys.ToArray());
            var format = screenshot.GetProperty("format");
            var quality = screenshot.GetProperty("jpegQuality");
            if (format.ValueKind != JsonValueKind.String || format.GetString() is not ("png" or "jpeg") ||
                quality.ValueKind != JsonValueKind.Number || !quality.TryGetInt32(out var percent) || percent is < 50 or > 100)
                throw new ArgumentException("Invalid screenshot export preferences");
            foreach (var key in new[] { "copyAfterSave", "showConfirmation" })
                if (screenshot.GetProperty(key).ValueKind is not (JsonValueKind.True or JsonValueKind.False))
                    throw new ArgumentException("Invalid screenshot option");
            keys.Add("screenshot");
        }
        Keys(settings, keys.ToArray());
        var remembersWindows = (settings.TryGetProperty("restoreDesktop", out var restore) && restore.ValueKind == JsonValueKind.True) ||
            (settings.TryGetProperty("restoreAfterRestart", out var restart) && restart.ValueKind == JsonValueKind.True);
        if (opened.Count > 0 && !remembersWindows) throw new ArgumentException("Desktop restoration disabled");
        foreach (var key in new[] { "showClock", "showContext" })
            if (settings.GetProperty(key).ValueKind is not (JsonValueKind.True or JsonValueKind.False)) throw new ArgumentException("Invalid visibility");
        if (!settings.GetProperty("dimming").TryGetDouble(out var dimming) || !double.IsFinite(dimming) || dimming is < .3 or > .9) throw new ArgumentException("Invalid dimming");
    }

    private static void Keys(JsonElement value, params string[] keys)
    {
        if (value.ValueKind != JsonValueKind.Object) throw new ArgumentException("Invalid object");
        var actual = value.EnumerateObject().Select(p => p.Name).ToArray();
        if (actual.Length != keys.Length || actual.Distinct().Count() != keys.Length || actual.Except(keys).Any()) throw new ArgumentException("Unexpected menu data");
    }

    private static void ValidateTools(JsonElement value, string[] allowed, int count, bool exact)
    {
        if (value.ValueKind != JsonValueKind.Array || (exact ? value.GetArrayLength() != count : value.GetArrayLength() > count)) throw new ArgumentException("Invalid toolbar tools");
        var seen = new HashSet<string>();
        foreach (var entry in value.EnumerateArray())
            if (entry.ValueKind != JsonValueKind.String || entry.GetString() is not { } id || !allowed.Contains(id) || !seen.Add(id)) throw new ArgumentException("Invalid toolbar tools");
    }
}
