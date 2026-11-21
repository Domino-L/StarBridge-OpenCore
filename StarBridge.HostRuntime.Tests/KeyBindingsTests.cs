using System.Text;
using System.Text.Json;
using StarBridge.HostRuntime.Tools;
using StarBridge.NativeBridge;

internal static class KeyBindingsTests
{
    private const string Header = """
        <ActionMaps>
         <ActionProfiles version="1" optionsVersion="2" rebindVersion="2" profileName="default">
          <options type="joystick" instance="1" Product="Secret Stick  {18E50B05-0000-0000-0000-504944564944}"/>
          <modifiers />
        """;
    private const string Footer = """
         </ActionProfiles>
        </ActionMaps>
        """;
    private static readonly KeyBinding[] DoorDefaults =
    [
        new("keyboardMouse", 1, "f8", false), new("joystick", 1, "button3", false), new("gamepad", 1, "a", false, null, "tap"),
    ];
    private static readonly KeyBindingDefaults Table = new("4.10.196.36804", Release: "4.10.2", Maps:
    [
        new("spaceship_general", [new("v_toggle_all_doors", DoorDefaults), new("v_unbound", [])]),
        new("player", [new("toggle_walk", [new("keyboardMouse", 1, "lctrl", false)])]),
    ]);

    internal static async Task Run()
    {
        Check(!BridgeRequestPolicy.RequiresAccountContext(KeyBindingsBridgeDispatcher.RequestName), "the local read needs no account");
        Merging();
        KeepingHowAKeyIsPressed();
        PlayerNames();
        Languages();
        ChosenLocalizations();
        OnlyOwnPlaceCounts();
        Locating();
        Failures();
        await Dispatching();
        ReadsOnlyTheFixedFile();
    }

    private static void Merging()
    {
        using var f = new Fixture();
        f.Write("LIVE", Header + """
              <actionmap name="spaceship_general">
               <action name="v_toggle_all_doors"><rebind input="kb1_lalt+f8"/></action>
               <action name="v_new_action"><rebind input="js2_button7" multiTap="2" activationMode="double_tap"/></action>
               <action name="v_unbound"><rebind input="js1_ "/></action>
              </actionmap>
              <actionmap name="player">
               <action name="toggle_walk"><rebind input="kb1_ "/></action>
              </actionmap>
              <actionmap name="unknown_map">
               <action name="odd"><rebind input="zz9_what"/><rebind input="mo1_mouse5"/></action>
              </actionmap>
            """ + Footer);
        var result = f.Reader(Table).Read("LIVE");
        Check(result.State == "ok" && result.DefaultsVersion == "4.10.196.36804" && result.DefaultsRelease == "4.10.2" &&
            result.ModifiedAt is not null, "official table names its build and release");
        var doors = Action(result, "spaceship_general", "v_toggle_all_doors");
        Check(doors.Bindings.Count == 3, "a keyboard rebind leaves other devices' defaults");
        Check(!doors.Bindings.Any(b => b.Input == "f8"), "a keyboard rebind replaces the keyboard default");
        Check(doors.Bindings.Single(b => b.Device == "keyboardMouse") is { Input: "lalt+f8", Customized: true }, "the player's key wins");
        Check(doors.Bindings.Single(b => b.Device == "joystick") is { Input: "button3", Customized: false }, "the stick default is still a default");
        Check(Action(result, "spaceship_general", "v_unbound").Bindings.Count == 0, "clearing a device with no default changes nothing");
        Check(Action(result, "spaceship_general", "v_new_action").Bindings.Single() is
            { Device: "joystick", Instance: 2, Input: "button7", MultiTap: 2, Mode: "double_tap", Customized: true },
            "an action the table does not know keeps the player's key");
        Check(Action(result, "player", "toggle_walk").Bindings.Single() is { Input: "", Customized: true }, "a cleared key removes the default");
        var odd = Action(result, "unknown_map", "odd").Bindings;
        Check(odd[0] is { Device: "unknown", Input: "zz9_what" }, "an input we cannot read is shown as written");
        Check(odd[1] is { Device: "keyboardMouse", Input: "mouse5" }, "mouse and keyboard are one device");

        var publicBuild = f.Reader(null).Read("LIVE");
        Check(publicBuild.DefaultsVersion is null, "a public build names no table");
        Check(publicBuild.Maps.SelectMany(m => m.Actions).SelectMany(a => a.Bindings).All(b => b.Customized), "a public build lists only the player's keys");
        Check(publicBuild.Maps.Count == 3 && publicBuild.Maps.All(m => m.Actions.All(a => a.Bindings.Count > 0)), "a public build has nothing from the table");
    }

    private static void KeepingHowAKeyIsPressed()
    {
        using var f = new Fixture();
        f.Write("LIVE", Header + """
              <actionmap name="m">
               <action name="long"><rebind input="kb1_f8"/></action>
               <action name="own"><rebind input="kb1_f9" activationMode="tap"/></action>
               <action name="mixed"><rebind input="kb1_f10"/></action>
              </actionmap>
            """ + Footer);
        var table = new KeyBindingDefaults("1.2.3.4",
        [
            new("m",
            [
                new("long", [new("keyboardMouse", 1, "f1", false, null, "delayed_press_medium")]),
                new("own", [new("keyboardMouse", 1, "f2", false, null, "delayed_press")]),
                new("mixed", [new("keyboardMouse", 1, "f3", false, null, "hold"), new("keyboardMouse", 1, "f4", false, null, "double_tap")]),
            ]),
        ]);
        var result = f.Reader(table).Read("LIVE");
        Check(Action(result, "m", "long").Bindings.Single() is { Input: "f8", Mode: "delayed_press_medium" }, "changing only the key keeps a long press");
        Check(Action(result, "m", "own").Bindings.Single() is { Input: "f9", Mode: "tap" }, "the player's own mode wins");
        Check(Action(result, "m", "mixed").Bindings.Single() is { Input: "f10", Mode: null }, "defaults that disagree are not guessed between");
    }

    private static void PlayerNames()
    {
        using var f = new Fixture();
        f.Write("LIVE", Header + """<actionmap name="m"><action name="door"><rebind input="kb1_f8"/></action></actionmap>""" + Footer);
        var table = new KeyBindingDefaults("1.2.3.4",
        [
            new("m",
            [
                new("door", [new("keyboardMouse", 1, "f1", false)], "ui_door"),
                new("lamp", [], "ui_lamp"),
                new("long", [], "ui_long"),
                new("empty", [], "ui_empty"),
                new("broken", [], "ui_broken"),
                new("none", [], "ui_none"),
                new("nolabel", []),
            ], "ui_map"),
        ]);
        Check(f.Reader(table).Read("LIVE") is { State: "ok", NamesState: "missing", NamesPath: null }, "no names file still lists keys");
        var path = Path.Combine(f.Root, "LIVE", "data", "Localization", "chinese_(simplified)", "global.ini");
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, "\uFEFFui_door=舱门\r\nUI_LAMP,P=头灯\\n（开启）\nui_map=驾驶舱\nui_door=第二次\nunrelated_secret=不要带出去\n" +
            "ui_long=" + new string('长', 65) + "\nui_empty=\nno equals here\n=novalue\nui_broken=\uFFFD坏\n", new UTF8Encoding(false));
        var result = f.Reader(table).Read("LIVE");
        Check(result is { State: "ok", NamesState: "ok" } && result.NamesPath!.EndsWith("global.ini"), "the names file is read");
        var map = result.Maps.Single();
        Check(map.LocalizedName == "驾驶舱", "a category takes its name too");
        string? Name(string action) => map.Actions.Single(a => a.Name == action).LocalizedName;
        Check(Name("door") == "舱门", "the first line wins");
        Check(map.Actions.Single(a => a.Name == "door").Bindings.Single() is { Input: "f8", Customized: true }, "names leave keys alone");
        Check(Name("lamp") == "头灯 （开启）", "keys match in any case, and a written line break becomes a space");
        foreach (var skipped in new[] { "long", "empty", "broken", "none", "nolabel" })
            Check(Name(skipped) is null, $"{skipped} falls back quietly");
        var strict = System.Text.Json.JsonSerializer.Serialize(result);
        Check(!strict.Contains("不要带出去"), "lines nobody asked for stay behind");

        File.WriteAllText(path, "nothing=useful\n");
        Check(f.Reader(table).Read("LIVE") is { State: "ok", NamesState: "missing" }, "a file with none of the names counts as no file");
        File.WriteAllText(path, "ui_door=舱门\n");
        using (new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.None))
        {
            Check(f.Reader(table).Read("LIVE") is { State: "ok", NamesState: "unreadable" }, "a locked names file changes only the names");
            Check(f.Reader(null).Read("LIVE") is { State: "ok", NamesState: "unused" }, "a public build has no keys to look for and does not open it");
        }
        // One enormous line costs a fixed buffer, and the names after it still count.
        using (var longLine = new StreamWriter(path, false, new UTF8Encoding(false)))
        {
            longLine.Write("ui_lamp=");
            longLine.Write(new string('x', 8 * 1024 * 1024));
            longLine.Write("\nui_door=舱门\r\n");
        }
        var afterLong = f.Reader(table).Read("LIVE");
        Check(afterLong.NamesState == "ok" && afterLong.Maps.Single().Actions.Single(a => a.Name == "door").LocalizedName == "舱门" &&
            afterLong.Maps.Single().Actions.Single(a => a.Name == "lamp").LocalizedName is null, "a line past the limit is skipped");
        using (var oversized = new FileStream(path, FileMode.Create, FileAccess.Write)) oversized.SetLength(64L * 1024 * 1024 + 1);
        Check(f.Reader(table).Read("LIVE") is { State: "ok", NamesState: "unreadable" }, "an oversized names file is not read");
        File.WriteAllText(path, "ui_door=舱门\n");
        var before = File.GetLastWriteTimeUtc(path);
        f.Reader(table).Read("LIVE");
        Check(File.GetLastWriteTimeUtc(path) == before, "the names file is not written");
        File.Delete(f.File("LIVE"));
        Check(f.Reader(table).Read("LIVE") is { State: "noFile", NamesState: "ok" }, "defaults take names without a key file");
    }

    private static void Languages()
    {
        using var f = new Fixture();
        f.Write("LIVE", Header + Footer);
        var table = new KeyBindingDefaults("1.2.3.4", [new("m", [new("door", [], "ui_door", null, "Toggle doors"), new("lamp", [], "ui_lamp")], "ui_map", null, "Cockpit")]);
        void Names(string folder, string text)
        {
            var path = Path.Combine(f.Root, "LIVE", "data", "Localization", folder, "global.ini");
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            File.WriteAllText(path, text, new UTF8Encoding(false));
        }
        var english = f.Reader(table).Read("LIVE", "en");
        Check(english is { NamesState: "bundled", NamesPath: null } && english.Maps.Single().LocalizedName == "Cockpit", "English falls back to the table's own names");
        Check(english.Maps.Single().Actions.Single(a => a.Name == "door").LocalizedName == "Toggle doors" && english.Maps.Single().Actions.Single(a => a.Name == "lamp").LocalizedName is null, "a name the table lacks stays empty");
        Check(f.Reader(table).Read("LIVE", "zh-Hans").NamesState == "missing", "Chinese does not fall back to English");
        Names("chinese_(simplified)", "ui_door=简体舱门\n");
        Names("chinese_(traditional)", "ui_door=繁體艙門\n");
        Names("english", "ui_door=Player doors\n");
        string? Door(string language) => f.Reader(table).Read("LIVE", language).Maps.Single().Actions.Single(a => a.Name == "door").LocalizedName;
        Check(Door("zh-Hans") == "简体舱门" && Door("zh-Hant") == "繁體艙門", "each interface language reads its own file");
        Check(Door("en") == "Player doors" && f.Reader(table).Read("LIVE", "en").NamesPath!.Contains(@"\english\"), "a local English file wins over the table");
        Check(f.Reader(null).Read("LIVE", "en") is { NamesState: "unused" }, "a public build has no English names");
        File.Delete(Path.Combine(f.Root, "LIVE", "data", "Localization", "chinese_(traditional)", "global.ini"));
        Check(f.Reader(table).Read("LIVE", "zh-Hant").NamesState == "missing", "traditional does not borrow the simplified file");
    }

    private static void ChosenLocalizations()
    {
        using var f = new Fixture();
        f.Write("LIVE", Header + Footer);
        var table = new KeyBindingDefaults("1.2.3.4", [new("m", [new("door", [], "ui_door", null, "Toggle doors")], "ui_map")]);
        void Names(string folder, string? text)
        {
            var dir = Path.Combine(f.Root, "LIVE", "data", "Localization", folder);
            Directory.CreateDirectory(dir);
            if (text is not null) File.WriteAllText(Path.Combine(dir, "global.ini"), text, new UTF8Encoding(false));
        }
        Names("chinese_(simplified)", "ui_door=简体舱门\n");
        Names("japanese_(japan)", "ui_door=ドア\n");
        Names("empty_folder", null);
        Names("bad name!", "ui_door=x\n");
        Directory.CreateDirectory(Path.Combine(f.Root, "LIVE", "data", "Localization", "japanese_(japan)", "nested"));
        var listed = f.Reader(table).Read("LIVE", "zh-Hans");
        Check(listed.Localizations!.SequenceEqual(["chinese_(simplified)", "japanese_(japan)"]), "only folders with a names file are listed, one level");
        Check(listed.Localization == "chinese_(simplified)" && !listed.LocalizationFallback, "the interface language is the default");
        var picked = f.Reader(table).Read("LIVE", "zh-Hans", "japanese_(japan)");
        Check(picked.Maps.Single().Actions.Single().LocalizedName == "ドア" && picked.Localization == "japanese_(japan)", "a listed folder can be chosen");
        var gone = f.Reader(table).Read("LIVE", "zh-Hans", "korean_(south_korea)");
        Check(gone.LocalizationFallback && gone.Localization == "chinese_(simplified)" &&
            gone.Maps.Single().Actions.Single().LocalizedName == "简体舱门", "a choice not installed falls back and says so");
        var english = f.Reader(table).Read("LIVE", "zh-Hans", null);
        Check(f.Reader(table).Read("LIVE", "en").NamesState == "bundled", "English without a file still has names");
        Check(f.Reader(null).Read("LIVE", "zh-Hans", "japanese_(japan)") is { Localizations: null, NamesState: "unused" }, "a public build lists nothing");
        // A linked data folder above Localization is not listed through.
        var outside = Path.Combine(f.Root, "outside", "Localization", "german_(germany)");
        Directory.CreateDirectory(outside);
        File.WriteAllText(Path.Combine(outside, "global.ini"), "ui_door=Tür\n");
        using var g = new Fixture();
        g.Write("LIVE", Header + Footer);
        var data = Path.Combine(g.Root, "LIVE", "data");
        if (!Directory.Exists(data) && TryJunction(data, Path.Combine(f.Root, "outside")))
        {
            Check(new KeyBindingsReader(() => null, () => [g.Root], table, false).Read("LIVE", "zh-Hans").Localizations is { Count: 0 },
                "a linked folder above is not listed");
            Directory.Delete(data);
        }
        Check(!KeyBindingsReader.ValidLocalization("..") && !KeyBindingsReader.ValidLocalization("a/b") && !KeyBindingsReader.ValidLocalization(""), "a choice cannot be a path");
    }

    private static void OnlyOwnPlaceCounts()
    {
        using var f = new Fixture();
        const string map = """<actionmap name="a"><action name="b"><rebind input="kb1_a"/></action></actionmap>""";
        f.Write("LIVE", Header + map + "</ActionProfiles>" +
            """<ActionProfiles profileName="other"><actionmap name="x"><action name="y"><rebind input="kb1_z"/></action></actionmap></ActionProfiles></ActionMaps>""");
        var second = f.Reader(null).Read("LIVE");
        Check(second.State == "ok" && second.Maps.Single().Name == "a" && second.Maps.Single().Actions.Single().Name == "b", "a later profile is ignored");
        f.Write("LIVE", Header + map + "</ActionProfiles><ActionProfiles><actionmap name=\"x\">");
        Check(f.Reader(null).Read("LIVE").State == "format", "a file cut off in a later profile is not complete");
        f.Write("LIVE", Header + """<actionmap name="a"><action name="b"></action><rebind input="kb1_a"/></actionmap>""" + Footer);
        Check(f.Reader(null).Read("LIVE").State == "format", "a rebind after its action closed belongs to nothing");
        f.Write("LIVE", Header + """<actionmap name="a"><group><action name="b"><rebind input="kb1_a"/></action></group></actionmap>""" + Footer);
        Check(f.Reader(null).Read("LIVE").State == "format", "a rebind nested deeper is not guessed at");
        f.Write("LIVE", Header + """<actionmap name="a"><action name="closed"/><group><rebind input="kb1_a"/></group></actionmap>""" + Footer);
        Check(f.Reader(null).Read("LIVE").State == "format", "a rebind beside a closed action does not join it");
        f.Write("LIVE", Header + """<actionmap name="a"/><group><action name="b"><rebind input="kb1_a"/></action></group>""" + Footer);
        Check(f.Reader(null).Read("LIVE").State == "format", "an action beside a closed map does not join it");

        f.Write("LIVE", """<ActionMaps><ActionProfiles/><group><actionmap name="m"><action name="outside"><rebind input="kb1_x"/></action></actionmap></group></ActionMaps>""");
        Check(f.Reader(null).Read("LIVE") is { State: "ok", Maps.Count: 0 }, "a rebind outside the first profile is not the player's");
        var elsewhere = Path.Combine(f.Root, "elsewhere.xml");
        File.WriteAllText(elsewhere, Header + map + Footer);
        Directory.CreateDirectory(Path.GetDirectoryName(f.File("PTU"))!);
        if (CreateHardLink(f.File("PTU"), elsewhere, IntPtr.Zero))
            Check(f.Reader(null).Read("PTU").State == "unreadable", "a second name for another file is refused");
    }

    private static bool TryJunction(string link, string target)
    {
        try
        {
            Directory.CreateSymbolicLink(link, target);
            return true;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            return false;
        }
    }

    [System.Runtime.InteropServices.DllImport("kernel32.dll", EntryPoint = "CreateHardLinkW", CharSet = System.Runtime.InteropServices.CharSet.Unicode, SetLastError = true)]
    private static extern bool CreateHardLink(string link, string existing, IntPtr attributes);

    private static void Locating()
    {
        using var f = new Fixture();
        Check(f.Reader(Table).Read("LIVE") is { State: "notInstalled", Path: null, Maps.Count: 0 }, "no version folder says so");
        f.Folder("LIVE");
        var missing = f.Reader(Table).Read("LIVE");
        Check(missing.State == "noFile" && missing.Maps.Count == 2, "no file yet shows the defaults");
        Check(f.Reader(null).Read("LIVE") is { State: "noFile", Maps.Count: 0 }, "no file and no table shows nothing");
        Check(f.Reader(Table).Read("PTU").State == "notInstalled", "PTU is not read from LIVE");
        f.Write("LIVE", Header + """<actionmap name="a"><action name="live"><rebind input="kb1_a"/></action></actionmap>""" + Footer);
        f.Write("PTU", Header + """<actionmap name="a"><action name="ptu"><rebind input="kb1_b"/></action></actionmap>""" + Footer);
        var live = f.Reader(null).Read("LIVE");
        var ptu = f.Reader(null).Read("PTU");
        Check(live.Path!.Contains(@"\LIVE\") && live.Maps.Single().Actions.Single().Name == "live", "LIVE reads LIVE");
        Check(ptu.Path!.Contains(@"\PTU\") && ptu.Maps.Single().Actions.Single().Name == "ptu", "PTU reads PTU");

        using var other = new Fixture();
        other.Write("LIVE", Header + """<actionmap name="a"><action name="other"><rebind input="kb1_c"/></action></actionmap>""" + Footer);
        var two = new KeyBindingsReader(() => null, () => [f.Root, other.Root], null, false);
        Check(two.Read("LIVE") is { State: "multiple", Path: null }, "two installs are not guessed between");
        var selected = new KeyBindingsReader(() => Path.Combine(other.Root, "LIVE", "Game.log"), () => [f.Root, other.Root], null, false);
        Check(selected.Read("LIVE").Maps.Single().Actions.Single().Name == "other", "the selected log's install wins");
    }

    private static void Failures()
    {
        using var f = new Fixture();
        foreach (var (name, content) in new[]
        {
            ("wrong root", "<Other/>"),
            ("no profile", "<ActionMaps></ActionMaps>"),
            ("not xml", "not xml"),
            ("cut short", Header + """<actionmap name="a">"""),
            ("a DTD", """<!DOCTYPE ActionMaps [<!ENTITY x "y">]><ActionMaps/>"""),
            ("orphan rebind", Header + """<rebind input="kb1_a"/>""" + Footer),
            ("nameless action", Header + """<actionmap name="a"><action><rebind input="kb1_a"/></action></actionmap>""" + Footer),
        })
        {
            f.Write("LIVE", content);
            Check(f.Reader(Table).Read("LIVE") is { State: "format", Maps.Count: 0 }, $"{name} is a format failure and hides defaults");
        }
        f.Write("LIVE", new string(' ', 4 * 1024 * 1024 + 1));
        Check(f.Reader(Table).Read("LIVE").State == "format", "an oversized file is not parsed");
        f.Write("LIVE", Header + Footer);
        using (new FileStream(f.File("LIVE"), FileMode.Open, FileAccess.Read, FileShare.None))
            Check(f.Reader(Table).Read("LIVE") is { State: "unreadable", Maps.Count: 0 }, "a locked file says so and hides defaults");
        Check(f.Reader(Table).Read("LIVE").State == "ok", "the next read recovers");
    }

    private static async Task Dispatching()
    {
        using var f = new Fixture();
        f.Write("LIVE", Header + """<actionmap name="a"><action name="b"><rebind input="kb1_a"/></action></actionmap>""" + Footer);
        var generation = 4L;
        using var dispatcher = new KeyBindingsBridgeDispatcher(f.Reader(null), () => generation);
        async Task<BridgeEnvelope> Call(object body) => (await dispatcher.DispatchAsync(
            BridgeEnvelope.Request(KeyBindingsBridgeDispatcher.RequestName, Guid.NewGuid().ToString("N"), 4, body))).Response;
        var response = await Call(new { schemaVersion = 1, channel = "LIVE", language = "zh-Hans" });
        Check(response.Status == "ok" && response.Payload.GetProperty("state").GetString() == "ok", "the read answers");
        Check(response.Payload.GetProperty("defaultsVersion").ValueKind == JsonValueKind.Null, "no table is an explicit null");
        Check(response.Payload.GetProperty("defaultsRelease").ValueKind == JsonValueKind.Null, "nor a release");
        Check(response.Payload.GetProperty("namesState").GetString() == "unused" && response.Payload.GetProperty("namesPath").ValueKind == JsonValueKind.Null, "names state crosses the Bridge");
        var binding = response.Payload.GetProperty("maps")[0].GetProperty("actions")[0].GetProperty("bindings")[0];
        Check(binding.GetProperty("input").GetString() == "a" && binding.GetProperty("multiTap").ValueKind == JsonValueKind.Null, "bindings cross the Bridge");
        Check(!response.Payload.GetRawText().Contains("Secret Stick"), "device names are not sent");
        foreach (var bad in new object[]
        {
            new { schemaVersion = 1 }, new { schemaVersion = 1, channel = "LIVE" }, new { schemaVersion = 2, channel = "LIVE", language = "en" }, new { schemaVersion = 1, channel = "EPTU", language = "en" },
            new { schemaVersion = 1, channel = "LIVE", language = "../english" }, new { schemaVersion = 1, channel = "LIVE", language = "fr" },
            new { schemaVersion = 1, channel = "LIVE", language = "en", localization = "../x" }, new { schemaVersion = 1, channel = "LIVE", language = "en", other = "x" },
            new { schemaVersion = 1, channel = "../LIVE", language = "en" }, new { schemaVersion = 1, channel = "LIVE", path = "C:\\x.xml" },
        })
            Check((await Call(bad)).Error?.Code == BridgeErrorCodes.InvalidEnvelope, "only the two versions can be asked for");
        // Each rebind fits the file limit, but together the answer would not fit one Bridge frame.
        var many = new StringBuilder(Header + """<actionmap name="m">""");
        for (var i = 0; i < 8000; i++)
            many.Append($"""<action name="a{i}"><rebind input="kb1_{new string('k', 128)}"/></action>""");
        f.Write("LIVE", many + "</actionmap>" + Footer);
        var large = await Call(new { schemaVersion = 1, channel = "LIVE", language = "zh-Hans" });
        Check(large.Status == "ok" && large.Payload.GetProperty("state").GetString() == "format" &&
            large.Payload.GetProperty("maps").GetArrayLength() == 0, "an answer too large for the Bridge says so instead of ending the connection");
        Check(large.Payload.GetRawText().Length < BridgeProtocol.MaximumFrameBytes, "the refusal fits");
        var longId = BridgeEnvelope.Request(KeyBindingsBridgeDispatcher.RequestName, new string('x', 257), 4, new { schemaVersion = 1, channel = "LIVE", language = "zh-Hans" });
        Check((await dispatcher.DispatchAsync(longId)).Response.Error?.Code == BridgeErrorCodes.InvalidEnvelope, "an oversized request id cannot push the answer past a frame");
        // The chosen view lives in one small file of ours.
        var viewPath = Path.Combine(f.Root, "view.json");
        using var saving = new KeyBindingsBridgeDispatcher(f.Reader(null), () => 4, viewPath);
        async Task<BridgeEnvelope> Save(object body) => (await saving.DispatchAsync(
            BridgeEnvelope.Request(KeyBindingsBridgeDispatcher.SaveViewRequestName, Guid.NewGuid().ToString("N"), 4, body))).Response;
        async Task<BridgeEnvelope> ReadView() => (await saving.DispatchAsync(
            BridgeEnvelope.Request(KeyBindingsBridgeDispatcher.RequestName, Guid.NewGuid().ToString("N"), 4, new { schemaVersion = 1, channel = "LIVE", language = "en" }))).Response;
        Check((await ReadView()).Payload.GetProperty("view").ValueKind == JsonValueKind.Null, "no choice yet");
        Check((await Save(new { schemaVersion = 1, keyboard = "p60", mouse = "many" })).Status == "ok", "a choice saves");
        Check((await ReadView()).Payload.GetProperty("view").GetProperty("keyboard").GetString() == "p60", "and comes back");
        Check((await Save(new { schemaVersion = 1, keyboard = "p60", mouse = "many", localization = "japanese_(japan)" })).Status == "ok", "a names language saves");
        Check((await ReadView()).Payload.GetProperty("view").GetProperty("localization").GetString() == "japanese_(japan)", "and comes back too");
        Check((await Save(new { schemaVersion = 1, keyboard = "p60", mouse = "many", localization = "../x" })).Error?.Code == BridgeErrorCodes.InvalidEnvelope, "a path is refused");
        // The page layout: list height and what is folded, all optional.
        Check((await Save(new { schemaVersion = 1, keyboard = "p60", mouse = "many", listHeight = 300, listOpen = false, notesOpen = true })).Status == "ok", "the page layout saves");
        var layout = (await ReadView()).Payload.GetProperty("view");
        Check(layout.GetProperty("listHeight").GetInt32() == 300 && !layout.GetProperty("listOpen").GetBoolean() &&
            layout.GetProperty("notesOpen").GetBoolean(), "and comes back");
        foreach (var edge in new[] { 120, 4000 })
            Check((await Save(new { schemaVersion = 1, keyboard = "p60", mouse = "many", listHeight = edge })).Status == "ok", $"a list {edge} high saves");
        // No keyboard: none chosen, so the page keeps picking one by width.
        Check((await Save(new { schemaVersion = 1, mouse = "many", listOpen = true })).Status == "ok", "a layout saves without a keyboard size");
        var unchosen = (await ReadView()).Payload.GetProperty("view");
        Check(unchosen.GetProperty("keyboard").ValueKind == JsonValueKind.Null && unchosen.GetProperty("listOpen").GetBoolean(), "and comes back without one");
        Check((await Save(new { schemaVersion = 1, keyboard = "p60", mouse = "many" })).Status == "ok", "without it, a view still saves");
        Check((await ReadView()).Payload.GetProperty("view").GetProperty("listHeight").ValueKind == JsonValueKind.Null, "and no layout comes back");
        foreach (var bad in new object[]
        {
            new { schemaVersion = 1, keyboard = "p60", mouse = "many", listHeight = 50 },
            new { schemaVersion = 1, keyboard = "p60", mouse = "many", listHeight = 4001 },
            new { schemaVersion = 1, keyboard = "p60", mouse = "many", listHeight = 300.5 },
            new { schemaVersion = 1, keyboard = "p60", mouse = "many", listOpen = "yes" },
            new { schemaVersion = 1, keyboard = "p60", mouse = "many", other = true },
        })
            Check((await Save(bad)).Error?.Code == BridgeErrorCodes.InvalidEnvelope, "only a known layout saves");
        Check(Directory.GetFiles(f.Root, "*.tmp").Length == 0, "no temporary file stays");
        // A left-over file with the old temporary name is never written through.
        File.WriteAllText(viewPath + ".tmp", "keep");
        var saves = Enumerable.Range(0, 12).Select(i => Save(new { schemaVersion = 1, keyboard = i % 2 == 0 ? "tkl" : "p75", mouse = "standard" })).ToArray();
        Check((await Task.WhenAll(saves)).All(r => r.Status == "ok"), "saves at the same time all finish");
        Check(File.ReadAllText(viewPath + ".tmp") == "keep", "an old temporary file is left alone");
        Check(Directory.GetFiles(f.Root, "key-bindings-view.*.tmp").Length == 0, "no temporary file of ours stays");
        Check((await ReadView()).Payload.GetProperty("view").GetProperty("keyboard").GetString() is "tkl" or "p75", "the saved view is one of them");
        foreach (var bad in new object[]
        {
            new { schemaVersion = 1, keyboard = "../x", mouse = "many" }, new { schemaVersion = 1, keyboard = "p60", mouse = "x" },
            new { schemaVersion = 1, keyboard = "p60" }, new { schemaVersion = 2, keyboard = "p60", mouse = "many" },
        })
            Check((await Save(bad)).Error?.Code == BridgeErrorCodes.InvalidEnvelope, "only known choices save");
        File.WriteAllText(viewPath, "{not json");
        Check((await ReadView()).Payload.GetProperty("view").ValueKind == JsonValueKind.Null, "a broken file is no choice");
        File.WriteAllText(viewPath, "{\"keyboard\":\"../x\",\"mouse\":\"many\"}");
        Check((await ReadView()).Payload.GetProperty("view").ValueKind == JsonValueKind.Null, "an unknown value is no choice");
        File.WriteAllText(viewPath, "{\"keyboard\":\"tkl\",\"mouse\":\"many\",\"listHeight\":9,\"listOpen\":\"x\"}");
        var odd = (await ReadView()).Payload.GetProperty("view");
        Check(odd.GetProperty("keyboard").GetString() == "tkl" && odd.GetProperty("listHeight").ValueKind == JsonValueKind.Null &&
            odd.GetProperty("listOpen").ValueKind == JsonValueKind.Null, "an odd layout is dropped, the view kept");
        generation = 5;
        Check((await Call(new { schemaVersion = 1, channel = "LIVE", language = "zh-Hans" })).Error?.Code == "keyBindings.unavailable", "a stale session is refused");
    }

    private static void ReadsOnlyTheFixedFile()
    {
        using var f = new Fixture();
        var content = Header + Footer;
        f.Write("LIVE", content);
        var before = File.GetLastWriteTimeUtc(f.File("LIVE"));
        var entries = Directory.GetFileSystemEntries(f.Root, "*", SearchOption.AllDirectories).Length;
        for (var i = 0; i < 3; i++) f.Reader(Table).Read("LIVE");
        Check(File.ReadAllText(f.File("LIVE")) == content && File.GetLastWriteTimeUtc(f.File("LIVE")) == before, "the file is not written");
        Check(Directory.GetFileSystemEntries(f.Root, "*", SearchOption.AllDirectories).Length == entries, "nothing is created beside it");
    }

    private static KeyBindingAction Action(KeyBindingsSnapshot snapshot, string map, string action) =>
        snapshot.Maps.Single(m => m.Name == map).Actions.Single(a => a.Name == action);

    private static void Check(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }

    private sealed class Fixture : IDisposable
    {
        internal string Root { get; } = Path.Combine(Path.GetTempPath(), "sb-keybindings-" + Guid.NewGuid().ToString("N"));
        internal Fixture() => Directory.CreateDirectory(Root);
        internal string File(string channel) => Path.Combine(Root, channel, "user", "client", "0", "Profiles", "default", "actionmaps.xml");
        internal void Folder(string channel) => Directory.CreateDirectory(Path.Combine(Root, channel));
        internal void Write(string channel, string content)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(File(channel))!);
            System.IO.File.WriteAllText(File(channel), content, new UTF8Encoding(false));
        }
        internal KeyBindingsReader Reader(KeyBindingDefaults? defaults) => new(() => null, () => [Root], defaults, false);
        public void Dispose() => Directory.Delete(Root, true);
    }
}
