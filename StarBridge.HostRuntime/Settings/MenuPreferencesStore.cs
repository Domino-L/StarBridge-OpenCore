namespace StarBridge.HostRuntime.Settings;

using System.Text.Json;
using StarBridge.NativeBridge;

// Local menu desktop only. No account identifiers, paths, URLs, opened targets,
// drafts, screenshots or browser data are accepted in this file.
internal sealed class MenuPreferencesStore(string dataRoot)
{
    private readonly string _path = Path.Combine(Path.GetFullPath(dataRoot), "menu-preferences.v1.json");
    private static readonly HashSet<string> Panels = ["friends", "comms", "organizations", "rooms", "hud", "screenshot", "image", "browser", "settings"];
    internal sealed record Snapshot(long Revision, JsonElement Layout, JsonElement Settings);
    internal static Snapshot Default => new(0,
        JsonSerializer.SerializeToElement(new { version = 1, panels = Array.Empty<object>(), open = Array.Empty<string>() }),
        JsonSerializer.SerializeToElement(new { showClock = true, showContext = true, dimming = 133d / 255, restoreDesktop = false, snapWindows = false }));

    internal Snapshot Read()
    {
        if (!File.Exists(_path)) return Default;
        if (new FileInfo(_path).Length > 32768) throw new IOException("Invalid menu preferences");
        try
        {
            var value = JsonSerializer.Deserialize<Snapshot>(File.ReadAllText(_path), BridgeProtocol.JsonOptions);
            if (value is null || value.Revision < 0) return Default;
            Validate(value.Layout, value.Settings);
            return value;
        }
        catch (Exception error) when (error is JsonException or ArgumentException or InvalidOperationException or FormatException) { return Default; }
    }

    internal Snapshot Save(long revision, JsonElement layout, JsonElement settings)
    {
        Validate(layout, settings);
        var current = Read();
        if (revision != current.Revision) throw new ApplicationPreferencesException("menuPreferences.revision_conflict", "Menu preferences changed", true);
        var next = new Snapshot(checked(revision + 1), layout.Clone(), settings.Clone());
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
        foreach (var key in new[] { "restoreDesktop", "snapWindows" })
            if (settings.TryGetProperty(key, out var flag))
            {
                if (flag.ValueKind is not (JsonValueKind.True or JsonValueKind.False)) throw new ArgumentException("Invalid desktop option");
                keys.Add(key);
            }
        Keys(settings, keys.ToArray());
        if (opened.Count > 0 && (!settings.TryGetProperty("restoreDesktop", out var restore) || restore.ValueKind != JsonValueKind.True)) throw new ArgumentException("Desktop restoration disabled");
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
}
