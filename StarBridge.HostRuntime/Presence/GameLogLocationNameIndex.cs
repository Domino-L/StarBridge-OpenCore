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
    private Regex _instanceSuffix = new(@"\s*\[\d+\]\s*$", RegexOptions.CultureInvariant, PatternTimeout);
    private string _optionalPrefix = "LOC_";

    private GameLogLocationNameIndex() { }

    internal static GameLogLocationNameIndex Load()
    {
        using var stream = Assembly.GetExecutingAssembly()
            .GetManifestResourceStream("StarBridge.LocationCatalog.json");
        return Load(stream);
    }

    // Caller owns the stream. Keeps optional-data behavior testable without
    // distributing the private compatibility catalog or mutating global state.
    internal static GameLogLocationNameIndex Load(Stream? stream)
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
                    if (Safe(code, 256)) index.Add(code, name);
                    if (Safe(normalized, 256)) index.Add(normalized, name);
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
        if (_names.TryGetValue(normalized, out var name))
        {
            return name;
        }
        var alternate = normalized.StartsWith(_optionalPrefix, StringComparison.OrdinalIgnoreCase)
            ? normalized[_optionalPrefix.Length..]
            : _optionalPrefix + normalized;
        if (_names.TryGetValue(alternate, out name))
        {
            return name;
        }
        var dynamic = _dynamic.FirstOrDefault(candidate => candidate.Pattern.IsMatch(normalized));
        if (dynamic.Name is not null)
        {
            return dynamic.Name;
        }
        return null;
    }

    private void Add(string key, GameLogLocationName name)
    {
        if (!_names.ContainsKey(key))
        {
            _names.Add(key, name);
        }
    }

    private static string Text(JsonElement element, string property) =>
        element.TryGetProperty(property, out var value) && value.ValueKind == JsonValueKind.String
            ? value.GetString()?.Trim() ?? string.Empty
            : string.Empty;

    private static bool Safe(string value, int maximum) =>
        value.Length is > 0 && value.Length <= maximum && !value.Any(char.IsControl);
}
