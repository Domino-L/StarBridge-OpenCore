using System.Reflection;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace StarBridge.HostRuntime.Presence;

internal sealed record GameLogLocationName(string EnglishName, string? ChineseName, bool CanSynchronize = true);

/// <summary>
/// Display-only lookup for the location codes accepted by the existing Game.log parser.
/// Carries the catalog's synchronization eligibility; publication remains outside this module.
/// </summary>
internal sealed class GameLogLocationNameIndex
{
    private static readonly TimeSpan PatternTimeout = TimeSpan.FromMilliseconds(100);
    private readonly Dictionary<string, GameLogLocationName> _names =
        new(StringComparer.OrdinalIgnoreCase);
    private readonly List<(Regex Pattern, GameLogLocationName Name)> _dynamic = [];
    private readonly Dictionary<string, string> _canonicalCodes = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, string> _compatibilityNames = new(StringComparer.OrdinalIgnoreCase);
    private Regex _instanceSuffix = new(@"\s*\[\d+\]\s*$", RegexOptions.CultureInvariant, PatternTimeout);
    private string _optionalPrefix = "LOC_";

    private GameLogLocationNameIndex() { }

    internal static GameLogLocationNameIndex Load()
    {
        using var stream = Assembly.GetExecutingAssembly()
            .GetManifestResourceStream("StarBridge.LocationCatalog.json");
        using var compatibility = Assembly.GetExecutingAssembly()
            .GetManifestResourceStream("StarBridge.LocationCompatibilityNames.txt");
        return Load(stream, compatibility);
    }

    // Caller owns the stream. Keeps optional-data behavior testable without
    // distributing the private compatibility catalog or mutating global state.
    internal static GameLogLocationNameIndex Load(Stream? stream, Stream? compatibility = null)
    {
        var index = new GameLogLocationNameIndex();
        try
        {
            if (stream is null)
            {
                return index;
            }

            using var document = JsonDocument.Parse(stream, new JsonDocumentOptions
            {
                MaxDepth = 16,
                CommentHandling = JsonCommentHandling.Disallow
            });
            var root = document.RootElement;
            if (root.GetProperty("schemaVersion").GetInt32() != 1)
            {
                return new GameLogLocationNameIndex();
            }

            if (root.TryGetProperty("normalization", out var normalization))
            {
                var prefix = Text(normalization, "optionalQuantumPrefix");
                if (prefix.Length is > 0 and <= 16)
                {
                    index._optionalPrefix = prefix;
                }
                var suffix = Text(normalization, "instanceSuffixPattern");
                if (suffix.Length is > 0 and <= 128)
                {
                    index._instanceSuffix = new Regex(
                        suffix,
                        RegexOptions.CultureInvariant,
                        PatternTimeout);
                }
            }

            var entries = root.GetProperty("entries");
            if (entries.GetArrayLength() is <= 0 or > 10000)
            {
                return new GameLogLocationNameIndex();
            }
            foreach (var entry in entries.EnumerateArray())
            {
                var code = Text(entry, "canonicalCode");
                var english = Text(entry, "nameEn");
                var chinese = Text(entry, "nameZh");
                if (!Safe(code, 256) || !Safe(english, 256))
                {
                    return new GameLogLocationNameIndex();
                }
                index.Add(code, new(english, Safe(chinese, 256) ? chinese : null));
            }

            if (root.TryGetProperty("aliases", out var aliases))
            {
                if (aliases.GetArrayLength() > 5000)
                {
                    return new GameLogLocationNameIndex();
                }
                foreach (var alias in aliases.EnumerateArray())
                {
                    var code = Text(alias, "code");
                    var normalized = Text(alias, "normalizedCode");
                    var canonical = Text(alias, "canonicalCode");
                    if (!index._names.TryGetValue(canonical, out var canonicalName))
                    {
                        continue;
                    }
                    var english = Text(alias, "nameEn");
                    var chinese = Text(alias, "nameZh");
                    var name = new GameLogLocationName(
                        Safe(english, 256) ? english : canonicalName.EnglishName,
                        Safe(chinese, 256) ? chinese : canonicalName.ChineseName);
                    if (Safe(code, 256)) index.Add(code, name, canonical);
                    if (Safe(normalized, 256)) index.Add(normalized, name, canonical);
                }
            }

            if (root.TryGetProperty("dynamicPatterns", out var dynamicPatterns))
            {
                if (dynamicPatterns.GetArrayLength() > 32)
                {
                    return new GameLogLocationNameIndex();
                }
                foreach (var item in dynamicPatterns.EnumerateArray())
                {
                    var expression = Text(item, "pattern");
                    var english = Text(item, "nameEn");
                    var chinese = Text(item, "nameZh");
                    if (!Safe(expression, 256) || !Safe(english, 256))
                    {
                        continue;
                    }
                    index._dynamic.Add((
                        new Regex(expression, RegexOptions.CultureInvariant | RegexOptions.IgnoreCase, PatternTimeout),
                        new(english, Safe(chinese, 256) ? chinese : null,
                            item.TryGetProperty("persistent", out var persistent) && persistent.ValueKind == JsonValueKind.True)));
                }
            }
            index.LoadCompatibilityNames(compatibility);
            return index;
        }
        catch (Exception error) when (error is JsonException or InvalidOperationException or
                                      KeyNotFoundException or FormatException or ArgumentException)
        {
            return new GameLogLocationNameIndex();
        }
    }

    internal GameLogLocationName? Find(string raw)
    {
        var normalized = _instanceSuffix.Replace(raw.Trim(), string.Empty);
        if (StarBridge.Core.Locations.NavigationStationDisplay.TryGetStationCode(normalized, out var station) &&
            _names.TryGetValue(station, out var stationName)) return WithCompatibilityName(station, station, stationName);
        if (_names.TryGetValue(normalized, out var name))
        {
            return WithCompatibilityName(normalized, normalized, name);
        }
        var alternate = normalized.StartsWith(_optionalPrefix, StringComparison.OrdinalIgnoreCase)
            ? normalized[_optionalPrefix.Length..]
            : _optionalPrefix + normalized;
        if (_names.TryGetValue(alternate, out name))
        {
            return WithCompatibilityName(normalized, alternate, name);
        }
        if (TryCompatibilityName(normalized, normalized, out var localName))
            return new(normalized, localName); // Existing field-confirmed display alias, no invented canonical identity.
        var dynamic = _dynamic.FirstOrDefault(candidate => candidate.Pattern.IsMatch(normalized));
        if (dynamic.Name is not null)
        {
            return dynamic.Name;
        }
        return null;
    }

    // Presentation-only reverse lookup. Do not broaden the Game.log parser's
    // accepted location identifiers, and never guess between ambiguous names.
    internal GameLogLocationName? FindDisplay(string raw)
    {
        if (Find(raw) is { } exact) return exact;
        if (StarBridge.Core.Locations.NavigationStationDisplay.TryGetStationCodeFromDisplayName(raw, out var station))
            return Find(station);
        var matches = _names.Values.Where(name =>
            string.Equals(name.EnglishName, raw.Trim(), StringComparison.OrdinalIgnoreCase))
            .Distinct().Take(2).ToArray();
        return matches.Length == 1 ? matches[0] : null;
    }

    private void Add(string key, GameLogLocationName name, string? canonical = null)
    {
        if (!_names.ContainsKey(key))
        {
            _names.Add(key, name);
            _canonicalCodes.Add(key, canonical ?? key);
        }
    }

    private GameLogLocationName WithCompatibilityName(string input, string lookup, GameLogLocationName name) =>
        StarBridge.Core.Locations.NavigationStationDisplay.TryGetStationName(lookup, out var stationName)
        ? name with { EnglishName = stationName.EnglishName, ChineseName = stationName.ChineseName } :
        !StarBridge.Core.Locations.NavigationStationDisplay.PreferCatalogStationName(lookup) &&
        TryCompatibilityName(input, lookup, out var chinese) ? name with { ChineseName = chinese } : name;

    private bool TryCompatibilityName(string input, string lookup, out string chinese)
    {
        if (_compatibilityNames.TryGetValue(input, out chinese!)) return true;
        if (input.StartsWith(_optionalPrefix, StringComparison.OrdinalIgnoreCase) &&
            _compatibilityNames.TryGetValue(input[_optionalPrefix.Length..], out chinese!)) return true;
        return _canonicalCodes.TryGetValue(lookup, out var canonical) && _compatibilityNames.TryGetValue(canonical, out chinese!);
    }

    private void LoadCompatibilityNames(Stream? stream)
    {
        if (stream is null) return;
        try
        {
            using var reader = new StreamReader(stream, System.Text.Encoding.UTF8, true, 1024, leaveOpen: true);
            var size = 0;
            while (reader.ReadLine() is { } raw)
            {
                if ((size += raw.Length) > 262144) { _compatibilityNames.Clear(); return; }
                var line = raw.Trim();
                if (line.Length == 0 || line.StartsWith('#') || line.EndsWith("system:", StringComparison.OrdinalIgnoreCase)) continue;
                var note = line.IndexOf("标注", StringComparison.Ordinal);
                if (note > 0) line = line[..note].Trim();
                var separator = line.IndexOf('=');
                string key, value;
                if (separator > 0) { key = line[..separator].Trim(); value = line[(separator + 1)..].Trim(); }
                else
                {
                    var match = Regex.Match(line, @"(?<code>[A-Za-z0-9_-]+)\s+(?<value>.+)", RegexOptions.CultureInvariant, PatternTimeout);
                    if (!match.Success) continue;
                    key = match.Groups["code"].Value; value = match.Groups["value"].Value.Trim();
                }
                // Match WPF's existing compatibility display normalization.
                if (value.StartsWith('/')) value = value[1..].Trim();
                var slash = value.LastIndexOf('/');
                if (slash >= 0 && slash < value.Length - 1) value = value[(slash + 1)..].Trim();
                var cjk = value.TakeWhile(c => c is < '\u4e00' or > '\u9fff').Count();
                if (cjk > 0 && cjk < value.Length && value[..cjk].Any(char.IsLetter) && value[..cjk].Any(char.IsWhiteSpace))
                    value = value[cjk..].Trim();
                if (Safe(key, 256) && Safe(value, 256)) _compatibilityNames[key] = value;
            }
        }
        catch (Exception error) when (error is IOException or ArgumentException or RegexMatchTimeoutException)
        { _compatibilityNames.Clear(); }
    }

    private static string Text(JsonElement element, string property) =>
        element.TryGetProperty(property, out var value) && value.ValueKind == JsonValueKind.String
            ? value.GetString()?.Trim() ?? string.Empty
            : string.Empty;

    private static bool Safe(string value, int maximum) =>
        value.Length is > 0 && value.Length <= maximum && !value.Any(char.IsControl);
}
