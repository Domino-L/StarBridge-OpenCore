using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Xml;
using Microsoft.Win32.SafeHandles;
using StarBridge.HostRuntime.Presence;

namespace StarBridge.HostRuntime.Tools;

internal sealed record KeyBinding(string Device, int Instance, string Input, bool Customized, int? MultiTap = null, string? Mode = null);
internal sealed record KeyBindingAction(string Name, IReadOnlyList<KeyBinding> Bindings, string? LabelKey = null, string? LocalizedName = null, string? EnglishName = null);
internal sealed record KeyBindingMap(string Name, IReadOnlyList<KeyBindingAction> Actions, string? LabelKey = null, string? LocalizedName = null, string? EnglishName = null);
internal sealed record KeyBindingDefaults(string Version, IReadOnlyList<KeyBindingMap> Maps, string? Release = null);
internal sealed record KeyBindingsSnapshot(string State, string Channel, string? Path, DateTimeOffset? ModifiedAt,
    string? DefaultsVersion, IReadOnlyList<KeyBindingMap> Maps, string NamesState = "unused", string? NamesPath = null,
    string? DefaultsRelease = null, IReadOnlyList<string>? Localizations = null, string? Localization = null,
    bool LocalizationFallback = false);

/// <summary>
/// Reads two fixed files below a version folder, only when asked: the player's actionmaps.xml and, when the table
/// says which names to look for, the localization file for the interface language. It never searches a
/// disk, opens another game file or writes anything. The defaults are private release data, so a public build has none.
/// </summary>
internal sealed class KeyBindingsReader(Func<string?> selectedGameLog, Func<IReadOnlyList<string>>? installationRoots = null,
    KeyBindingDefaults? defaults = null, bool useBundledDefaults = true)
{
    private const int MaximumFileBytes = 4 * 1024 * 1024;
    private const int MaximumRebinds = 8192;
    private const int MaximumTextLength = 256;
    private const int MaximumNamesFileBytes = 64 * 1024 * 1024;
    private const int MaximumNameLength = 64;
    private const int MaximumNamesLineBytes = 4096;
    private static readonly string[] ProfilePath = ["user", "client", "0", "Profiles", "default", "actionmaps.xml"];
    private static readonly Dictionary<string, string> LanguageFolders = new(StringComparer.Ordinal)
    {
        ["zh-Hans"] = "chinese_(simplified)", ["zh-Hant"] = "chinese_(traditional)", ["en"] = "english",
    };
    private static ReadOnlySpan<byte> Utf8Bom => [0xEF, 0xBB, 0xBF];
    private static readonly Regex Rebind = new(@"^(kb|mo|js|gp)([1-9][0-9]?)_(.*)$", RegexOptions.Singleline | RegexOptions.CultureInvariant);
    private readonly KeyBindingDefaults? _defaults = defaults ?? (useBundledDefaults ? Bundled.Value : null);
    private static readonly Lazy<KeyBindingDefaults?> Bundled = new(LoadBundled);

    public static bool ValidChannel(string? channel) => channel is "LIVE" or "PTU";
    public static bool ValidLanguage(string? language) => language is not null && LanguageFolders.ContainsKey(language);
    private static readonly Regex LocalizationName = new(@"^[A-Za-z0-9_()\-]{1,48}$", RegexOptions.CultureInvariant);
    private const int MaximumLocalizations = 64;
    public static bool ValidLocalization(string? name) => name is not null && LocalizationName.IsMatch(name);

    /// <param name="localization">A folder the player chose from the listed ones; null follows the interface.</param>
    public KeyBindingsSnapshot Read(string channel, string language = "zh-Hans", string? localization = null)
    {
        var folder = Locate(channel, out var state);
        if (folder is null) return Result(state, channel);
        var path = Path.Combine([folder, .. ProfilePath]);
        List<RawRebind> rebinds;
        DateTimeOffset modified;
        try
        {
            // Checked before anything else touches the path, so a link above it is never followed.
            if (CheckedFile(path) is not { } checkedPath)
                return Localized(Result("noFile", channel, path, maps: _defaults?.Maps ?? []), folder, language, localization);
            path = checkedPath;
            modified = File.GetLastWriteTimeUtc(path);
            rebinds = Parse(ReadBounded(path));
        }
        catch (FormatException) { return Result("format", channel, path); }
        catch (XmlException) { return Result("format", channel, path); }
        catch (IOException) { return Result("unreadable", channel, path); }
        catch (UnauthorizedAccessException) { return Result("unreadable", channel, path); }
        return Localized(Result("ok", channel, path, modified, Merge(rebinds)), folder, language, localization);
    }

    private KeyBindingsSnapshot Result(string state, string channel, string? path = null, DateTimeOffset? modified = null,
        IReadOnlyList<KeyBindingMap>? maps = null) =>
        new(state, channel, path, modified, _defaults?.Version, maps ?? [], DefaultsRelease: _defaults?.Release);

    // A missing or broken names file changes the names only, never the list. Without the table there are no
    // label keys to look for, so a public build does not open this file at all.
    private KeyBindingsSnapshot Localized(KeyBindingsSnapshot snapshot, string folder, string language, string? requested)
    {
        if (_defaults is null || snapshot.Maps.Count == 0) return snapshot;
        var installed = InstalledLocalizations(folder);
        var fallback = requested is not null && !installed.Contains(requested, StringComparer.OrdinalIgnoreCase);
        var chosen = requested is not null && !fallback
            ? installed.First(name => name.Equals(requested, StringComparison.OrdinalIgnoreCase))
            : LanguageFolders[language];
        var result = FromFile(snapshot, folder, chosen);
        // English is the one language the official table carries itself.
        if (result.NamesState != "ok" && chosen.Equals("english", StringComparison.OrdinalIgnoreCase))
            result = WithEnglishNames(result);
        return result with { Localizations = installed, Localization = chosen, LocalizationFallback = fallback };
    }

    // One level only, and only folders that hold a global.ini: the names the player can choose between.
    private static IReadOnlyList<string> InstalledLocalizations(string folder)
    {
        var root = Path.Combine(folder, "data", "Localization");
        try
        {
            // The folder and every one above it must be local and unlinked before anything is looked at through them;
            // a missing folder throws here and means no languages.
            root = RequireLocalUnlinked(root);
            var found = new List<string>();
            foreach (var path in Directory.EnumerateDirectories(root))
            {
                var name = Path.GetFileName(path);
                if (!ValidLocalization(name) || (File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0) continue;
                if (!File.Exists(Path.Combine(path, "global.ini"))) continue;
                found.Add(name);
                if (found.Count == MaximumLocalizations) break;
            }
            found.Sort(StringComparer.OrdinalIgnoreCase);
            return found;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            return [];
        }
    }

    private static KeyBindingsSnapshot WithEnglishNames(KeyBindingsSnapshot snapshot)
    {
        if (!snapshot.Maps.Any(map => map.EnglishName is not null || map.Actions.Any(action => action.EnglishName is not null))) return snapshot;
        return snapshot with
        {
            NamesState = "bundled",
            Maps = [.. snapshot.Maps.Select(map => map with
            {
                LocalizedName = map.EnglishName,
                Actions = [.. map.Actions.Select(action => action with { LocalizedName = action.EnglishName })],
            })],
        };
    }

    private static KeyBindingsSnapshot FromFile(KeyBindingsSnapshot snapshot, string folder, string localization)
    {
        var path = Path.Combine(folder, "data", "Localization", localization, "global.ini");
        var wanted = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var map in snapshot.Maps)
        {
            if (map.LabelKey is { } mapKey) wanted.Add(mapKey);
            foreach (var action in map.Actions)
                if (action.LabelKey is { } actionKey) wanted.Add(actionKey);
        }
        Dictionary<string, string> names;
        try
        {
            if (CheckedFile(path) is not { } checkedPath) return snapshot with { NamesState = "missing" };
            path = checkedPath;
            names = ReadNames(path, wanted);
        }
        catch (FormatException) { return snapshot with { NamesState = "unreadable" }; }
        catch (IOException) { return snapshot with { NamesState = "unreadable" }; }
        catch (UnauthorizedAccessException) { return snapshot with { NamesState = "unreadable" }; }
        if (names.Count == 0) return snapshot with { NamesState = "missing" };
        string? Name(string? key) => key is not null && names.TryGetValue(key, out var name) ? name : null;
        return snapshot with
        {
            NamesState = "ok", NamesPath = path,
            Maps = [.. snapshot.Maps.Select(map => map with
            {
                LocalizedName = Name(map.LabelKey),
                Actions = [.. map.Actions.Select(action => action with { LocalizedName = Name(action.LabelKey) })],
            })],
        };
    }

    // Keeps only the wanted lines of a file of about 100,000, so the rest never stays in memory or crosses the Bridge.
    private static Dictionary<string, string> ReadNames(string path, HashSet<string> wanted)
    {
        using var stream = OpenChecked(path, MaximumNamesFileBytes);
        var names = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        var buffer = new byte[64 * 1024];
        var line = new byte[MaximumNamesLineBytes];
        var length = 0;
        var tooLong = false;
        long total = 0;
        int count;
        // Count what is really read: the game may still be writing, and one huge line must not become one huge string.
        while ((count = stream.Read(buffer)) > 0)
        {
            if ((total += count) > MaximumNamesFileBytes) throw new FormatException("The file grew past any known size.");
            for (var i = 0; i < count; i++)
            {
                if (buffer[i] == (byte)'\n')
                {
                    if (!tooLong) AddName(line.AsSpan(0, length), wanted, names);
                    length = 0;
                    tooLong = false;
                }
                else if (length == line.Length) tooLong = true;
                else line[length++] = buffer[i];
            }
        }
        if (!tooLong) AddName(line.AsSpan(0, length), wanted, names);
        return names;
    }

    private static void AddName(ReadOnlySpan<byte> bytes, HashSet<string> wanted, Dictionary<string, string> names)
    {
        var split = bytes.IndexOf((byte)'=');
        if (split <= 0) return;
        var head = bytes[..split];
        if (head.StartsWith(Utf8Bom)) head = head[Utf8Bom.Length..];
        var key = Encoding.UTF8.GetString(head).Trim();
        if (key.EndsWith(",P", StringComparison.OrdinalIgnoreCase)) key = key[..^2];
        if (!wanted.Contains(key) || names.ContainsKey(key)) return;
        var value = Encoding.UTF8.GetString(bytes[(split + 1)..]).Replace("\\n", " ").Trim();
        if (value.Length is > 0 and <= MaximumNameLength && !value.Any(char.IsControl) && !value.Contains('\uFFFD'))
            names.Add(key, value);
    }

    private string? Locate(string channel, out string state)
    {
        var folders = new List<string>();
        var refused = false;
        void Add(string? root)
        {
            if (string.IsNullOrWhiteSpace(root)) return;
            try
            {
                // Checked before Directory.Exists, which would otherwise look through a link or reach a share.
                var folder = RequireLocalUnlinked(Path.Combine(root, channel));
                if (Directory.Exists(folder) && !folders.Contains(folder, StringComparer.OrdinalIgnoreCase)) folders.Add(folder);
            }
            catch (RefusedPathException) { refused = true; }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException or ArgumentException or NotSupportedException)
            {
                // Missing, not allowed or malformed: not an install.
            }
        }
        // The selected version's install is stronger evidence than another copy on the disk.
        var selected = selectedGameLog();
        if (GameLogLocator.ChannelOf(selected) is not null) Add(Path.GetDirectoryName(Path.GetDirectoryName(selected!)));
        if (folders.Count == 1) { state = "ok"; return folders[0]; }
        // The selected install is linked: say so, rather than quietly showing another copy's keys.
        if (refused) { state = "unreadable"; return null; }
        foreach (var root in (installationRoots ?? GameLogLocator.CommonInstallationRoots)().Take(256)) Add(root);
        // A linked install was found but is not read, as before: it reads as unreadable rather than not installed.
        state = folders.Count switch { 0 when refused => "unreadable", 0 => "notInstalled", 1 => "ok", _ => "multiple" };
        return folders.Count == 1 ? folders[0] : null;
    }

    private static string RequireLocalUnlinked(string path)
    {
        var full = Path.GetFullPath(path);
        var root = Path.GetPathRoot(full)!;
        if (full.StartsWith(@"\\", StringComparison.Ordinal)) throw new RefusedPathException();
        var drive = new DriveInfo(root).DriveType;
        if (drive == DriveType.NoRootDirectory) throw new DirectoryNotFoundException();
        if (drive != DriveType.Fixed) throw new RefusedPathException();
        var chain = new List<string>();
        for (var current = full; current.Length > root.Length; current = Path.GetDirectoryName(current)!) chain.Add(current);
        // From the drive down, so no step is ever looked at through a link above it. A missing step throws, as not found.
        for (var index = chain.Count - 1; index >= 0; index--)
            if ((File.GetAttributes(chain[index]) & FileAttributes.ReparsePoint) != 0)
                throw new RefusedPathException();
        return full;
    }

    // A path that exists but is not read: a link, a network share or a removable disk.
    private sealed class RefusedPathException() : IOException("Only unlinked paths on a local disk are read.");

    // The checks File.Exists would make, after the path itself is checked; the answers it gives as false stay "missing".
    private static string? CheckedFile(string path)
    {
        try
        {
            var full = RequireLocalUnlinked(path);
            return File.Exists(full) ? full : null;
        }
        catch (Exception error) when (error is FileNotFoundException or DirectoryNotFoundException or UnauthorizedAccessException)
        {
            return null;
        }
    }

    private static byte[] ReadBounded(string path)
    {
        using var stream = OpenChecked(path, MaximumFileBytes);
        var bytes = new byte[stream.Length];
        stream.ReadExactly(bytes);
        return bytes;
    }

    private static FileStream OpenChecked(string path, long maximumBytes)
    {
        // No delete sharing, so the checked file cannot be swapped while it is read.
        var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
        try
        {
            var finalPath = new StringBuilder(2048);
            var length = GetFinalPathNameByHandle(stream.SafeFileHandle, finalPath, (uint)finalPath.Capacity, 0);
            // The handle settles it: a folder swapped after the path check, or a second name for another file, stops here.
            if (length == 0 || length >= finalPath.Capacity ||
                !finalPath.ToString().Equals(@"\\?\" + path, StringComparison.OrdinalIgnoreCase) ||
                !GetFileInformationByHandle(stream.SafeFileHandle, out var information) || information.Links != 1 ||
                (information.Attributes & (FileAttributes.Directory | FileAttributes.ReparsePoint)) != 0)
                throw new IOException("The opened file is not the expected one.");
            if (stream.Length > maximumBytes) throw new FormatException("The file is larger than any known format.");
            return stream;
        }
        catch
        {
            stream.Dispose();
            throw;
        }
    }

    private sealed record RawRebind(string Map, string Action, KeyBinding Binding);

    private static List<RawRebind> Parse(byte[] bytes)
    {
        using var memory = new MemoryStream(bytes);
        // The game writes device names as it finds them, so tolerate odd characters but never a DTD.
        using var xml = XmlReader.Create(memory, new XmlReaderSettings
        {
            DtdProcessing = DtdProcessing.Prohibit, XmlResolver = null, CheckCharacters = false,
            IgnoreComments = true, IgnoreWhitespace = true, MaxCharactersInDocument = MaximumFileBytes,
        });
        xml.MoveToContent();
        if (xml.NodeType != XmlNodeType.Element || xml.Name != "ActionMaps") throw new FormatException("Unknown root.");
        var rebinds = new List<RawRebind>();
        var profiles = 0;
        var inFirstProfile = false;
        string? map = null, action = null;
        // Read to the end even past the first profile, so a cut-off file is never taken as complete.
        while (xml.Read())
        {
            if (xml.NodeType != XmlNodeType.Element) continue;
            // Leaving a level ends its context: a rebind only counts inside its own action.
            if (xml.Depth <= 3) action = null;
            if (xml.Depth <= 2) map = null;
            // Only the inside of the first profile counts: a later profile would mix other choices into this list.
            if (xml.Depth == 1) inFirstProfile = xml.Name == "ActionProfiles" && ++profiles == 1;
            if (!inFirstProfile) continue;
            if (xml.Depth == 2 && xml.Name == "actionmap") map = Text(xml.GetAttribute("name"));
            else if (xml.Depth == 3 && xml.Name == "action" && map is not null) action = Text(xml.GetAttribute("name"));
            else if (xml.Name == "rebind")
            {
                if (xml.Depth != 4 || map is null || action is null || xml.GetAttribute("input") is not { } input)
                    throw new FormatException("Orphan rebind.");
                if (rebinds.Count >= MaximumRebinds) throw new FormatException("Too many rebinds.");
                rebinds.Add(new(map, action, Binding(input, xml.GetAttribute("multiTap"), xml.GetAttribute("activationMode"))));
            }
        }
        if (profiles == 0) throw new FormatException("No profile.");
        return rebinds;
    }

    private static string Text(string? value) =>
        value is { Length: > 0 and <= MaximumTextLength } && !value.Any(char.IsControl) ? value : throw new FormatException("Invalid name.");

    private static KeyBinding Binding(string raw, string? multiTap, string? mode)
    {
        var tap = int.TryParse(multiTap, out var count) && count is > 1 and < 10 ? count : (int?)null;
        var activation = mode is { Length: > 0 and <= 64 } && mode.All(c => char.IsAsciiLetterOrDigit(c) || c == '_') ? mode : null;
        var match = Rebind.Match(raw);
        // Show what cannot be understood instead of guessing which key it means.
        if (!match.Success || raw.Length > MaximumTextLength || raw.Any(char.IsControl))
            return new("unknown", 1, Sanitized(raw), true, tap, activation);
        return new(Device(match.Groups[1].Value), int.Parse(match.Groups[2].Value), match.Groups[3].Value.Trim(), true, tap, activation);
    }

    private static string Sanitized(string raw)
    {
        var clean = new string(raw.Where(c => !char.IsControl(c)).Take(MaximumTextLength).ToArray());
        return clean.Length == 0 ? "?" : clean;
    }

    // The game treats keyboard and mouse as one rebind device: it writes kb1_mouse4 and mo1_space alike.
    private static string Device(string prefix) => prefix switch
    {
        "kb" or "mo" => "keyboardMouse", "js" => "joystick", "gp" => "gamepad", _ => "unknown",
    };

    private IReadOnlyList<KeyBindingMap> Merge(List<RawRebind> rebinds)
    {
        var changed = rebinds.GroupBy(r => (r.Map, r.Action)).ToDictionary(g => g.Key, g => g.Select(r => r.Binding).ToList());
        var used = new HashSet<(string, string)>();
        var maps = new List<KeyBindingMap>();
        foreach (var map in _defaults?.Maps ?? [])
        {
            var actions = new List<KeyBindingAction>();
            foreach (var action in map.Actions)
            {
                if (!changed.TryGetValue((map.Name, action.Name), out var own)) { actions.Add(action); continue; }
                used.Add((map.Name, action.Name));
                // Rebinds for one device replace that device's defaults and leave the others alone. This holds across
                // instances: game-written files bind js2 without clearing js1's default. Not tried in the game itself.
                var replaced = own.Select(b => b.Device).ToHashSet();
                var bound = action.Bindings.Select(b => b.Device).ToHashSet();
                // Clearing a device that had no default changes nothing, and the game writes many of these.
                actions.Add(action with
                {
                    Bindings = [.. action.Bindings.Where(b => !replaced.Contains(b.Device)),
                        .. own.Where(b => b.Input.Length > 0 || bound.Contains(b.Device))
                            .Select(b => b with { Mode = b.Mode ?? InheritedMode(action, b.Device) })],
                });
            }
            actions.AddRange(Extra(rebinds, map.Name, used));
            maps.Add(map with { Actions = actions });
        }
        foreach (var name in rebinds.Select(r => r.Map).Distinct(StringComparer.Ordinal).ToArray())
            if (_defaults?.Maps.Any(m => m.Name == name) != true)
                maps.Add(new(name, Extra(rebinds, name, used)));
        return maps;
    }

    // A rebind that names only a key keeps how the action is pressed, when the defaults agree on one way.
    private static string? InheritedMode(KeyBindingAction action, string device)
    {
        var modes = action.Bindings.Where(b => b.Device == device).Select(b => b.Mode).Distinct().ToArray();
        return modes.Length == 1 ? modes[0] : null;
    }

    // An action the table does not know, because it is older than the game, still shows the player's choice.
    private static List<KeyBindingAction> Extra(List<RawRebind> rebinds, string map, HashSet<(string, string)> used) =>
        rebinds.Where(r => r.Map == map && !used.Contains((map, r.Action))).GroupBy(r => r.Action)
            .Select(g => { used.Add((map, g.Key)); return new KeyBindingAction(g.Key, [.. g.Select(r => r.Binding)]); }).ToList();

    private static KeyBindingDefaults? LoadBundled()
    {
        try
        {
            using var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("StarBridge.KeyBindingDefaults.json");
            return stream is null ? null : ParseDefaults(JsonDocument.Parse(stream));
        }
        catch (Exception error) when (error is JsonException or FormatException or InvalidOperationException or KeyNotFoundException)
        {
            return null;
        }
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct FileInformation
    {
        internal FileAttributes Attributes;
        internal System.Runtime.InteropServices.ComTypes.FILETIME Creation, Access, Write;
        internal uint Volume, SizeHigh, SizeLow, Links, IndexHigh, IndexLow;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern uint GetFinalPathNameByHandle(SafeFileHandle file, StringBuilder path, uint size, uint flags);
    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetFileInformationByHandle(SafeFileHandle file, out FileInformation information);

    internal static KeyBindingDefaults ParseDefaults(JsonDocument document)
    {
        var root = document.RootElement;
        if (root.GetProperty("schemaVersion").GetInt32() != 1) throw new FormatException("Unknown defaults table.");
        var maps = new List<KeyBindingMap>();
        foreach (var map in root.GetProperty("maps").EnumerateArray())
        {
            var actions = new List<KeyBindingAction>();
            foreach (var action in map.GetProperty("actions").EnumerateArray())
            {
                var bindings = new List<KeyBinding>();
                foreach (var binding in action.GetProperty("d").EnumerateArray())
                    bindings.Add(new(Device(binding.GetProperty("s").GetString()!), 1, binding.GetProperty("i").GetString()!, false, null,
                        binding.TryGetProperty("m", out var mode) ? mode.GetString() : null));
                actions.Add(new(action.GetProperty("name").GetString()!, bindings, Label(action), null, English(action)));
            }
            maps.Add(new(map.GetProperty("name").GetString()!, actions, Label(map), null, English(map)));
        }
        var release = root.TryGetProperty("release", out var given) && given.GetString() is { Length: > 0 and <= 16 } text ? text : null;
        return new(root.GetProperty("version").GetString()!, maps, release);
    }

    private static string? English(JsonElement element) =>
        element.TryGetProperty("n", out var name) && name.GetString() is { Length: > 0 and <= MaximumNameLength } text ? text : null;

    private static string? Label(JsonElement element) =>
        element.TryGetProperty("l", out var label) && label.GetString() is { Length: > 0 } key ? key : null;
}
