using System.Text.Json;
using StarBridge.HostRuntime.Settings;
using StarBridge.NativeBridge;

internal static class MenuPreferencesTests
{
    internal static async Task Verify()
    {
        var root = Path.Combine(Path.GetTempPath(), "StarBridge-menu-test-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var store = new MenuPreferencesStore(root);
            var initial = store.Read();
            var layout = JsonSerializer.SerializeToElement(new { version = 1, panels = new[] { new { id = "browser", bounds = new[] { 50d, 70, 800, 500 } } }, open = Array.Empty<string>() });
            var saved = store.Save(0, layout, initial.Settings);
            Require(saved.Revision == 1 && new MenuPreferencesStore(root).Read().Layout.GetProperty("panels").GetArrayLength() == 1, "persists geometry");
            try { store.Save(0, layout, initial.Settings); throw new Exception("stale revision accepted"); }
            catch (ApplicationPreferencesException error)
            {
                Require(error.Code == "menuPreferences.revision_conflict", "settings page baseline becomes stale after menu geometry save, not an IO failure");
            }
            foreach (var bad in new[] {
                "{\"version\":1,\"panels\":[],\"open\":[\"friends\"]}",
                "{\"version\":1,\"panels\":[{\"id\":\"p1\",\"bounds\":[1,2,3,4]}],\"open\":[]}",
                "{\"version\":1,\"panels\":[{\"id\":\"browser\",\"bounds\":[1,2,-3,4]}],\"open\":[]}",
                "{\"version\":1,\"panels\":[],\"open\":[],\"account\":\"forbidden\"}"
            })
            {
                using var document = JsonDocument.Parse(bad);
                try { store.Save(1, document.RootElement, initial.Settings); throw new Exception("invalid document accepted"); }
                catch (ArgumentException) { }
            }
            Require(store.Read().Revision == 1, "invalid writes preserve file");
            var remembered = JsonSerializer.SerializeToElement(new { showClock = true, showContext = true, dimming = .5, restoreDesktop = true, snapWindows = false });
            var desktop = JsonSerializer.SerializeToElement(new { version = 1, panels = new[] { new { id = "browser", bounds = new[] { -500d, 1500, 800, 500 } } }, open = new[] { "friends", "browser", "settings" } });
            store.Save(1, desktop, remembered);
            var restarted = new MenuPreferencesStore(root).Read();
            Require(restarted.Revision == 2 && restarted.Layout.GetProperty("open")[1].GetString() == "browser" && restarted.Layout.GetProperty("panels")[0].GetProperty("bounds")[0].GetDouble() == -500, "restart preserves desktop z order and offscreen geometry");
            foreach (var bad in new[] {
                "{\"version\":1,\"panels\":[],\"open\":[\"friends\",\"friends\"]}",
                "{\"version\":1,\"panels\":[],\"open\":[\"p1\"]}",
                "{\"version\":1,\"panels\":[],\"open\":[123]}"
            })
            {
                using var document = JsonDocument.Parse(bad);
                try { store.Save(2, document.RootElement, remembered); throw new Exception("invalid desktop accepted"); }
                catch (ArgumentException) { }
            }
            var legacy = JsonSerializer.SerializeToElement(new { showClock = false, showContext = true, dimming = .5 });
            store.Save(2, layout, legacy);
            Require(new MenuPreferencesStore(root).Read().Revision == 3, "legacy settings remain readable");
            var shortcut = store.ReadHotkey();
            Require(shortcut.Options == new MenuHotkeyOptions() && shortcut.Revision == 3, "legacy layout supplies WPF shortcut defaults without rewriting");
            var changedShortcut = store.SaveHotkey(3, new("Ctrl+Alt+F8", false, false));
            Require(changedShortcut.Revision == 4 && new MenuPreferencesStore(root).ReadHotkey() == changedShortcut, "shortcut survives process restart");
            Require(store.Read().Layout.GetRawText() == layout.GetRawText(), "shortcut save preserves layout");
            store.Save(4, desktop, remembered);
            Require(store.ReadHotkey().Options == changedShortcut.Options, "later layout saves do not erase shortcut");
            try { store.SaveHotkey(4, new()); throw new Exception("stale shortcut accepted"); }
            catch (ApplicationPreferencesException) { }
            Require(store.ReadHotkey().Options == changedShortcut.Options, "stale shortcut does not overwrite geometry or key");
            var toolbar = JsonSerializer.SerializeToElement(new { showClock = true, showContext = true, dimming = .5,
                toolbar = new { order = new[] { "browser", "hud", "organizations", "friends", "comms", "rooms", "screenshot", "image" }, hidden = new[] { "image", "friends" }, density = "compact", labels = "iconsOnly" } });
            store.Save(5, layout, toolbar);
            var toolbarRestart = new MenuPreferencesStore(root).Read();
            Require(toolbarRestart.Settings.GetProperty("toolbar").GetProperty("order")[0].GetString() == "browser" && toolbarRestart.Hotkey == changedShortcut.Options, "toolbar ordering and visibility survive restart without changing shortcut");
            foreach (var bad in new[] {
                toolbar.GetRawText().Replace("\"image\",\"friends\"", "\"hud\""),
                toolbar.GetRawText().Replace("\"browser\",\"hud\"", "\"browser\",\"browser\""),
                toolbar.GetRawText().Replace("\"compact\"", "\"invalid\""),
                toolbar.GetRawText().Replace("\"iconsOnly\"", "\"invalid\""),
                toolbar.GetRawText().Replace("\"hidden\":[", "\"account\":\"forbidden\",\"hidden\":[")
            })
            {
                using var document = JsonDocument.Parse(bad);
                try { store.Save(6, layout, document.RootElement); throw new Exception("invalid toolbar accepted"); }
                catch (ArgumentException) { }
            }
            Require(store.Read().Revision == 6 && store.Read().Settings.GetRawText() == toolbar.GetRawText(), "invalid toolbar writes preserve saved configuration");
            var displayData = JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(toolbar.GetRawText())!;
            displayData["showClock"] = JsonSerializer.SerializeToElement(false);
            displayData["display"] = JsonSerializer.SerializeToElement(new { showDate = true, clockFormat = "twelveHour",
                showScene = false, showMembers = false, showShip = true, showLocation = false, showServer = true, showPresence = false });
            var display = JsonSerializer.SerializeToElement(displayData);
            store.Save(6, layout, display);
            var displayRestart = new MenuPreferencesStore(root).Read();
            Require(!displayRestart.Settings.GetProperty("showClock").GetBoolean() &&
                displayRestart.Settings.GetProperty("display").GetProperty("clockFormat").GetString() == "twelveHour" &&
                displayRestart.Hotkey == changedShortcut.Options &&
                displayRestart.Settings.GetProperty("toolbar").GetRawText() == toolbar.GetProperty("toolbar").GetRawText(), "display preferences survive restart without changing toolbar or shortcut");
            foreach (var bad in new[] {
                display.GetRawText().Replace("\"twelveHour\"", "\"invalid\""),
                display.GetRawText().Replace("\"twelveHour\"", "12"),
                display.GetRawText().Replace("\"twelveHour\"", "null"),
                display.GetRawText().Replace("\"showDate\":true", "\"showDate\":1"),
                display.GetRawText().Replace("\"showDate\":true", "\"showDate\":true,\"account\":\"forbidden\""),
                display.GetRawText().Replace("\"showDate\":true,", "")
            })
            {
                using var document = JsonDocument.Parse(bad);
                try { store.Save(7, layout, document.RootElement); throw new Exception("invalid display accepted"); }
                catch (ArgumentException) { }
            }
            Require(store.Read().Revision == 7 && store.Read().Settings.GetRawText() == display.GetRawText(), "invalid display writes preserve saved configuration");
            var badgeData = JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(display.GetRawText())!;
            var badgeToolbar = JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(badgeData["toolbar"].GetRawText())!;
            badgeToolbar["showUnreadBadges"] = JsonSerializer.SerializeToElement(false);
            badgeData["toolbar"] = JsonSerializer.SerializeToElement(badgeToolbar);
            var badgeSettings = JsonSerializer.SerializeToElement(badgeData);
            store.Save(7, layout, badgeSettings);
            var badgeRestart = new MenuPreferencesStore(root).Read();
            Require(!badgeRestart.Settings.GetProperty("toolbar").GetProperty("showUnreadBadges").GetBoolean() &&
                badgeRestart.Hotkey == changedShortcut.Options && badgeRestart.Layout.GetRawText() == layout.GetRawText() &&
                badgeRestart.Settings.GetProperty("display").GetRawText() == display.GetProperty("display").GetRawText(), "unread badge preference survives restart and preserves other preferences");
            foreach (var bad in new[] { "null", "1", "\"false\"" })
            {
                using var document = JsonDocument.Parse(badgeSettings.GetRawText().Replace("\"showUnreadBadges\":false", "\"showUnreadBadges\":" + bad));
                try { store.Save(8, layout, document.RootElement); throw new Exception("invalid unread badge flag accepted"); }
                catch (ArgumentException) { }
            }
            Require(store.Read().Revision == 8 && store.Read().Settings.GetRawText() == badgeSettings.GetRawText(), "invalid badge writes preserve saved configuration");
            var restorationData = JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(badgeSettings.GetRawText())!;
            restorationData["restoreDesktop"] = JsonSerializer.SerializeToElement(false);
            restorationData["restoreAfterRestart"] = JsonSerializer.SerializeToElement(true);
            var restoration = JsonSerializer.SerializeToElement(restorationData);
            store.Save(8, desktop, restoration);
            Require(new MenuPreferencesStore(root).Read().Layout.GetProperty("open").GetArrayLength() == 3 &&
                store.ReadHotkey().Options == changedShortcut.Options, "restart-only restoration preserves layout and shortcut");
            foreach (var bad in new[] { "null", "1", "\"true\"" })
            {
                using var document = JsonDocument.Parse(restoration.GetRawText().Replace("\"restoreAfterRestart\":true", "\"restoreAfterRestart\":" + bad));
                try { store.Save(9, desktop, document.RootElement); throw new Exception("invalid restart flag accepted"); }
                catch (ArgumentException) { }
            }
            restorationData["restoreAfterRestart"] = JsonSerializer.SerializeToElement(false);
            try { store.Save(9, desktop, JsonSerializer.SerializeToElement(restorationData)); throw new Exception("disabled restoration retained opened tools"); }
            catch (ArgumentException) { }
            Require(store.Read().Revision == 9 && store.Read().Settings.GetRawText() == restoration.GetRawText(), "rejected restoration changes preserve file");
            restorationData["restoreDesktop"] = JsonSerializer.SerializeToElement(true);
            store.Save(9, desktop, JsonSerializer.SerializeToElement(restorationData));
            Require(!new MenuPreferencesStore(root).Read().Settings.GetProperty("restoreAfterRestart").GetBoolean(), "session-only choice persists independently");
            restorationData["restoreLastFocus"] = JsonSerializer.SerializeToElement(false);
            restorationData["crashRecovery"] = JsonSerializer.SerializeToElement("restore");
            var recoverySettings = JsonSerializer.SerializeToElement(restorationData);
            store.Save(10, desktop, recoverySettings);
            var restoredPolicy = new MenuPreferencesStore(root).Read();
            Require(!restoredPolicy.Settings.GetProperty("restoreLastFocus").GetBoolean() &&
                restoredPolicy.Settings.GetProperty("crashRecovery").GetString() == "restore" &&
                restoredPolicy.Hotkey == changedShortcut.Options && restoredPolicy.Layout.GetRawText() == desktop.GetRawText(), "focus and interruption choices preserve layout and shortcut after restart");
            foreach (var bad in new[] {
                recoverySettings.GetRawText().Replace("\"restoreLastFocus\":false", "\"restoreLastFocus\":null"),
                recoverySettings.GetRawText().Replace("\"restoreLastFocus\":false", "\"restoreLastFocus\":1"),
                recoverySettings.GetRawText().Replace("\"crashRecovery\":\"restore\"", "\"crashRecovery\":null"),
                recoverySettings.GetRawText().Replace("\"crashRecovery\":\"restore\"", "\"crashRecovery\":true"),
                recoverySettings.GetRawText().Replace("\"crashRecovery\":\"restore\"", "\"crashRecovery\":\"unknown\"")
            })
            {
                using var document = JsonDocument.Parse(bad);
                try { store.Save(11, desktop, document.RootElement); throw new Exception("invalid interruption policy accepted"); }
                catch (ArgumentException) { }
            }
            Require(store.Read().Revision == 11 && store.Read().Settings.GetRawText() == recoverySettings.GetRawText(), "invalid interruption policy preserves file");
            foreach (var mode in new[] { "ask", "startClean" })
            {
                restorationData["crashRecovery"] = JsonSerializer.SerializeToElement(mode);
                var nextPolicy = store.Save(store.Read().Revision, desktop, JsonSerializer.SerializeToElement(restorationData));
                Require(new MenuPreferencesStore(root).Read().Settings.GetProperty("crashRecovery").GetString() == mode && nextPolicy.Layout.GetRawText() == desktop.GetRawText(), "each interruption policy persists without clearing layout during settings edit");
            }
            var browserData = JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(store.Read().Settings.GetRawText())!;
            var beforeBrowser = store.Read();
            foreach (var provider in new[] { "bing-cn", "baidu", "google", "duckduckgo", "bing-global" })
            {
                browserData["browser"] = JsonSerializer.SerializeToElement(new { provider, tabLimit = 12, openLinksInNewTab = false, pauseWhenHidden = false });
                var candidate = JsonSerializer.SerializeToElement(browserData);
                store.Save(store.Read().Revision, desktop, candidate);
                var after = new MenuPreferencesStore(root).Read();
                Require(after.Settings.GetProperty("browser").GetProperty("provider").GetString() == provider &&
                    after.Layout.GetRawText() == beforeBrowser.Layout.GetRawText() && after.Hotkey == beforeBrowser.Hotkey &&
                    after.Settings.GetProperty("toolbar").GetRawText() == beforeBrowser.Settings.GetProperty("toolbar").GetRawText(),
                    "browser choice survives restart and preserves layout/toolbar/hotkey");
            }
            var validBrowser = store.Read();
            foreach (var bad in new[] {
                "null", "{}",
                "{\"provider\":\"custom\",\"tabLimit\":8,\"openLinksInNewTab\":true,\"pauseWhenHidden\":true}",
                "{\"provider\":\"google\",\"tabLimit\":0,\"openLinksInNewTab\":true,\"pauseWhenHidden\":true}",
                "{\"provider\":\"google\",\"tabLimit\":13,\"openLinksInNewTab\":true,\"pauseWhenHidden\":true}",
                "{\"provider\":\"google\",\"tabLimit\":2.5,\"openLinksInNewTab\":true,\"pauseWhenHidden\":true}",
                "{\"provider\":\"google\",\"tabLimit\":8,\"openLinksInNewTab\":1,\"pauseWhenHidden\":true}",
                "{\"provider\":\"google\",\"tabLimit\":8,\"openLinksInNewTab\":true,\"pauseWhenHidden\":null}",
                "{\"provider\":\"google\",\"tabLimit\":8,\"openLinksInNewTab\":true,\"pauseWhenHidden\":true,\"url\":\"https://example.test/\"}"
            })
            {
                browserData["browser"] = JsonSerializer.Deserialize<JsonElement>(bad);
                try { store.Save(validBrowser.Revision, desktop, JsonSerializer.SerializeToElement(browserData)); throw new Exception("invalid browser accepted"); }
                catch (ArgumentException) { }
                catch (InvalidOperationException) { }
            }
            Require(store.Read().Revision == validBrowser.Revision && store.Read().Settings.GetRawText() == validBrowser.Settings.GetRawText(), "invalid browser writes preserve file");
            browserData["browser"] = JsonSerializer.SerializeToElement(new { provider = "bing-cn", tabLimit = 1, openLinksInNewTab = true, pauseWhenHidden = true });
            store.Save(validBrowser.Revision, desktop, JsonSerializer.SerializeToElement(browserData));
            Require(new MenuPreferencesStore(root).Read().Settings.GetProperty("browser").GetProperty("tabLimit").GetInt32() == 1, "minimum tab limit persists");
            var beforeImage = store.Read();
            var imageData = JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(beforeImage.Settings.GetRawText())!;
            foreach (var openMode in new[] { "edit", "imageOnly" })
            foreach (var scaleMode in new[] { "fit", "actualSize" })
            foreach (var opacityPercent in new[] { 20, 100 })
            {
                imageData["image"] = JsonSerializer.SerializeToElement(new { openMode, scaleMode, opacityPercent });
                store.Save(store.Read().Revision, desktop, JsonSerializer.SerializeToElement(imageData));
                var after = new MenuPreferencesStore(root).Read();
                Require(after.Settings.GetProperty("image").GetRawText() == imageData["image"].GetRawText() &&
                    after.Layout.GetRawText() == beforeImage.Layout.GetRawText() && after.Hotkey == beforeImage.Hotkey &&
                    after.Settings.GetProperty("browser").GetRawText() == beforeImage.Settings.GetProperty("browser").GetRawText(),
                    "image defaults persist without changing browser, layout or shortcut");
            }
            foreach (var rememberAdjustments in new[] { true, false })
            foreach (var defaultPinned in new[] { true, false })
            {
                imageData["image"] = JsonSerializer.SerializeToElement(new { openMode = "edit", scaleMode = "fit", opacityPercent = 100, rememberAdjustments, defaultPinned });
                store.Save(store.Read().Revision, desktop, JsonSerializer.SerializeToElement(imageData));
                var persisted = new MenuPreferencesStore(root).Read().Settings.GetProperty("image");
                Require(persisted.GetProperty("rememberAdjustments").GetBoolean() == rememberAdjustments &&
                    persisted.GetProperty("defaultPinned").GetBoolean() == defaultPinned, "reference memory and default pin persist");
            }
            var validImage = store.Read();
            foreach (var bad in new[] {
                "null", "{}",
                "{\"openMode\":\"edit\",\"scaleMode\":\"fit\",\"opacityPercent\":100,\"rememberAdjustments\":null}",
                "{\"openMode\":\"edit\",\"scaleMode\":\"fit\",\"opacityPercent\":100,\"defaultPinned\":1}",
                "{\"openMode\":true,\"scaleMode\":\"fit\",\"opacityPercent\":100}",
                "{\"openMode\":\"unknown\",\"scaleMode\":\"fit\",\"opacityPercent\":100}",
                "{\"openMode\":\"edit\",\"scaleMode\":null,\"opacityPercent\":100}",
                "{\"openMode\":\"edit\",\"scaleMode\":\"unknown\",\"opacityPercent\":100}",
                "{\"openMode\":\"edit\",\"scaleMode\":\"fit\",\"opacityPercent\":19}",
                "{\"openMode\":\"edit\",\"scaleMode\":\"fit\",\"opacityPercent\":101}",
                "{\"openMode\":\"edit\",\"scaleMode\":\"fit\",\"opacityPercent\":20.5}",
                "{\"openMode\":\"edit\",\"scaleMode\":\"fit\",\"opacityPercent\":\"100\"}",
                "{\"openMode\":\"edit\",\"scaleMode\":\"fit\",\"opacityPercent\":100,\"path\":\"synthetic.png\"}",
                "{\"openMode\":\"edit\",\"openMode\":\"imageOnly\",\"scaleMode\":\"fit\",\"opacityPercent\":100}"
            })
            {
                imageData["image"] = JsonSerializer.Deserialize<JsonElement>(bad);
                try { store.Save(validImage.Revision, desktop, JsonSerializer.SerializeToElement(imageData)); throw new Exception("invalid image defaults accepted"); }
                catch (ArgumentException) { }
                catch (InvalidOperationException) { }
            }
            Require(store.Read().Revision == validImage.Revision && store.Read().Settings.GetRawText() == validImage.Settings.GetRawText(),
                "invalid image writes do not reset existing settings");
            var exportData = JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(validImage.Settings.GetRawText())!;
            exportData["screenshot"] = JsonSerializer.SerializeToElement(new { format = "jpeg", jpegQuality = 75, copyAfterSave = true, showConfirmation = false });
            var exportSettings = store.Save(validImage.Revision, desktop, JsonSerializer.SerializeToElement(exportData));
            var exportRestart = new MenuPreferencesStore(root).Read();
            Require(exportRestart.Settings.GetProperty("screenshot").GetProperty("jpegQuality").GetInt32() == 75 &&
                exportRestart.Hotkey == validImage.Hotkey && exportRestart.Layout.GetRawText() == desktop.GetRawText() &&
                exportRestart.Settings.GetProperty("image").GetRawText() == validImage.Settings.GetProperty("image").GetRawText(),
                "screenshot export survives restart without changing other preferences");
            Require(!exportRestart.Settings.GetProperty("screenshot").TryGetProperty("hideMenu", out _),
                "reading legacy export settings does not rewrite them");
            foreach (var hide in new[] { false, true })
            {
                exportData["screenshot"] = JsonSerializer.SerializeToElement(new {
                    format = "jpeg", jpegQuality = 75, copyAfterSave = true, showConfirmation = false, hideMenu = hide });
                exportSettings = store.Save(exportSettings.Revision, desktop, JsonSerializer.SerializeToElement(exportData));
                Require(new MenuPreferencesStore(root).Read().Settings.GetProperty("screenshot").GetProperty("hideMenu").GetBoolean() == hide,
                    "capture visibility survives restart");
            }
            foreach (var bad in new[] {
                "{\"format\":\"gif\",\"jpegQuality\":90,\"copyAfterSave\":false,\"showConfirmation\":true}",
                "{\"format\":\"jpeg\",\"jpegQuality\":49,\"copyAfterSave\":false,\"showConfirmation\":true}",
                "{\"format\":\"jpeg\",\"jpegQuality\":101,\"copyAfterSave\":false,\"showConfirmation\":true}",
                "{\"format\":\"jpeg\",\"jpegQuality\":75.5,\"copyAfterSave\":false,\"showConfirmation\":true}",
                "{\"format\":\"jpeg\",\"jpegQuality\":90,\"copyAfterSave\":1,\"showConfirmation\":true}",
                "{\"format\":\"jpeg\",\"jpegQuality\":90,\"copyAfterSave\":false,\"showConfirmation\":null}",
                "{\"format\":\"jpeg\",\"jpegQuality\":90,\"copyAfterSave\":false,\"showConfirmation\":true,\"hideMenu\":null}",
                "{\"format\":\"jpeg\",\"jpegQuality\":90,\"copyAfterSave\":false,\"showConfirmation\":true,\"hideMenu\":\"false\"}",
                "{\"format\":\"jpeg\",\"jpegQuality\":90,\"copyAfterSave\":false,\"showConfirmation\":true,\"hideMenu\":false,\"hideMenu\":true}",
                "{\"format\":\"jpeg\",\"jpegQuality\":90,\"copyAfterSave\":false,\"showConfirmation\":true,\"path\":\"forbidden\"}",
                "{\"format\":\"png\",\"format\":\"jpeg\",\"jpegQuality\":90,\"copyAfterSave\":false,\"showConfirmation\":true}",
                "null", "{}"
            })
            {
                using var value = JsonDocument.Parse(bad);
                exportData["screenshot"] = value.RootElement.Clone();
                try { store.Save(exportSettings.Revision, desktop, JsonSerializer.SerializeToElement(exportData)); throw new Exception("invalid screenshot export accepted"); }
                catch (ArgumentException) { }
                catch (InvalidOperationException) { }
            }
            Require(store.Read().Revision == exportSettings.Revision && store.Read().Settings.GetRawText() == exportSettings.Settings.GetRawText(),
                "invalid screenshot options preserve file and revision");
            using var dispatcher = new ApplicationPreferencesBridgeDispatcher(root, () => 5);
            Require(!displayRestart.Settings.GetProperty("display").TryGetProperty("streamerPrivacy", out _),
                "legacy display read does not rewrite privacy defaults");
            var privacyData = JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(exportSettings.Settings.GetRawText())!;
            var privacyDisplay = JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(display.GetProperty("display").GetRawText())!;
            privacyDisplay["streamerPrivacy"] = JsonSerializer.SerializeToElement(true);
            privacyDisplay["showRoomCode"] = JsonSerializer.SerializeToElement(false);
            privacyDisplay["textScalePercent"] = JsonSerializer.SerializeToElement(125);
            privacyDisplay["interfaceScalePercent"] = JsonSerializer.SerializeToElement(85);
            privacyDisplay["reduceMotion"] = JsonSerializer.SerializeToElement(true);
            privacyDisplay["highContrast"] = JsonSerializer.SerializeToElement(true);
            privacyDisplay["tooltipDelayMilliseconds"] = JsonSerializer.SerializeToElement(1500);
            privacyData["display"] = JsonSerializer.SerializeToElement(privacyDisplay);
            var privacy = store.Save(store.Read().Revision, desktop, JsonSerializer.SerializeToElement(privacyData));
            var privacyRestart = new MenuPreferencesStore(root).Read();
            Require(privacyRestart.Settings.GetProperty("display").GetProperty("tooltipDelayMilliseconds").GetInt32() == 1500,
                "menu tooltip delay survives restart");
            foreach (var invalidDelay in new[] { "null", "true", "\"500\"", "500.5", "99", "1501", "1500,\"tooltipDelayMilliseconds\":500" })
            {
                using var invalidDocument = JsonDocument.Parse(privacy.Settings.GetRawText().Replace("\"tooltipDelayMilliseconds\":1500", "\"tooltipDelayMilliseconds\":" + invalidDelay));
                try { store.Save(privacy.Revision, desktop, invalidDocument.RootElement); throw new Exception("invalid tooltip delay accepted"); }
                catch (ArgumentException) { }
            }
            Require(privacyRestart.Settings.GetProperty("display").GetProperty("highContrast").GetBoolean(),
                "menu contrast survives restart");
            foreach (var invalidContrast in new[] { "null", "1", "\"true\"", "true,\"highContrast\":false" })
            {
                using var invalidDocument = JsonDocument.Parse(privacy.Settings.GetRawText().Replace("\"highContrast\":true", "\"highContrast\":" + invalidContrast));
                try { store.Save(privacy.Revision, desktop, invalidDocument.RootElement); throw new Exception("invalid contrast accepted"); }
                catch (ArgumentException) { }
            }
            Require(privacyRestart.Settings.GetProperty("display").GetProperty("reduceMotion").GetBoolean(),
                "menu reduced motion survives restart");
            foreach (var invalidMotion in new[] { "null", "1", "\"true\"", "true,\"reduceMotion\":false" })
            {
                using var invalidDocument = JsonDocument.Parse(privacy.Settings.GetRawText().Replace("\"reduceMotion\":true", "\"reduceMotion\":" + invalidMotion));
                try { store.Save(privacy.Revision, desktop, invalidDocument.RootElement); throw new Exception("invalid motion accepted"); }
                catch (ArgumentException) { }
            }
            Require(privacyRestart.Settings.GetProperty("display").GetProperty("interfaceScalePercent").GetInt32() == 85,
                "menu interface size survives restart");
            foreach (var invalidScale in new[] { "null", "true", "\"85\"", "85.5", "99", "126", "85,\"interfaceScalePercent\":100" })
            {
                using var invalidDocument = JsonDocument.Parse(privacy.Settings.GetRawText().Replace("\"interfaceScalePercent\":85", "\"interfaceScalePercent\":" + invalidScale));
                try { store.Save(privacy.Revision, desktop, invalidDocument.RootElement); throw new Exception("invalid interface size accepted"); }
                catch (ArgumentException) { }
            }
            Require(privacyRestart.Settings.GetProperty("display").GetProperty("textScalePercent").GetInt32() == 125,
                "menu text size survives restart");
            foreach (var invalidScale in new[] { "null", "true", "\"125\"", "125.5", "99", "126", "125,\"textScalePercent\":100" })
            {
                using var invalidDocument = JsonDocument.Parse(privacy.Settings.GetRawText().Replace("\"textScalePercent\":125", "\"textScalePercent\":" + invalidScale));
                try { store.Save(privacy.Revision, desktop, invalidDocument.RootElement); throw new Exception("invalid text size accepted"); }
                catch (ArgumentException) { }
            }
            Require(privacyRestart.Settings.GetProperty("display").GetProperty("streamerPrivacy").GetBoolean() &&
                !privacyRestart.Settings.GetProperty("display").GetProperty("showRoomCode").GetBoolean(), "privacy persists across restart");
            foreach (var invalid in new[] { "null", "1", "\"true\"", "true,\"streamerPrivacy\":false" })
            {
                using var document = JsonDocument.Parse(privacy.Settings.GetRawText().Replace("\"streamerPrivacy\":true", "\"streamerPrivacy\":" + invalid));
                try { store.Save(privacy.Revision, desktop, document.RootElement); throw new Exception("invalid privacy accepted"); }
                catch (ArgumentException) { }
            }
            Require(store.Read().Revision == privacy.Revision, "invalid privacy leaves revision unchanged");
            var socialData = JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(privacy.Settings.GetRawText())!;
            socialData["social"] = JsonSerializer.SerializeToElement(new { friendSort = "alphabetical" });
            var social = store.Save(privacy.Revision, desktop, JsonSerializer.SerializeToElement(socialData));
            Require(new MenuPreferencesStore(root).Read().Settings.GetProperty("social").GetProperty("friendSort").GetString() == "alphabetical",
                "friend sorting survives restart");
            socialData["social"] = JsonSerializer.SerializeToElement(new { friendSort = "alphabetical", notifications = false, preview = "hiddenDetails", sound = true, showAvatars = false });
            social = store.Save(social.Revision, desktop, JsonSerializer.SerializeToElement(socialData));
            var socialRestart = new MenuPreferencesStore(root).Read().Settings.GetProperty("social");
            Require(!socialRestart.GetProperty("notifications").GetBoolean() && socialRestart.GetProperty("preview").GetString() == "hiddenDetails",
                "menu notification privacy survives restart");
            Require(socialRestart.GetProperty("sound").GetBoolean(), "menu sound choice survives restart without enabling notices");
            Require(!socialRestart.GetProperty("showAvatars").GetBoolean(), "menu avatar choice survives restart");
            foreach (var bad in new[] { "null", "{}", "{\"friendSort\":true}", "{\"friendSort\":\"invalid\"}",
                "{\"friendSort\":\"onlineFirst\",\"extra\":true}", "{\"friendSort\":\"onlineFirst\",\"friendSort\":\"alphabetical\"}",
                "{\"friendSort\":\"onlineFirst\",\"notifications\":1}", "{\"friendSort\":\"onlineFirst\",\"preview\":\"bad\"}",
                "{\"friendSort\":\"onlineFirst\",\"sound\":1}", "{\"friendSort\":\"onlineFirst\",\"sound\":true,\"sound\":false}",
                "{\"friendSort\":\"onlineFirst\",\"showAvatars\":1}", "{\"friendSort\":\"onlineFirst\",\"showAvatars\":true,\"showAvatars\":false}",
                "{\"friendSort\":\"onlineFirst\",\"notifications\":true,\"notifications\":false}" })
            {
                socialData["social"] = JsonSerializer.Deserialize<JsonElement>(bad);
                try { store.Save(social.Revision, desktop, JsonSerializer.SerializeToElement(socialData)); throw new Exception("invalid social accepted"); }
                catch (ArgumentException) { }
                catch (InvalidOperationException) { }
            }
            Require(store.Read().Revision == social.Revision, "invalid social leaves settings unchanged");
            var request = BridgeEnvelope.Request("applicationPreferences.menu.get", "menu", 5, new { schemaVersion = 1 });
            var read = await dispatcher.DispatchAsync(request);
            Require(read.Response.Status == "ok", "dispatcher reads local preferences");
            var stale = await dispatcher.DispatchAsync(BridgeEnvelope.Request("applicationPreferences.menu.get", "old", 4, new { schemaVersion = 1 }));
            Require(stale.Response.Status != "ok", "stale generation denied");
            Console.WriteLine("PASS menu local geometry, revision conflict, allowlist, atomic preservation and generation checks");
        }
        finally { Directory.Delete(root, true); }
    }
    private static void Require(bool value, string label) { if (!value) throw new Exception(label); }
}
