using System.IO;
using System.Text;
using System.Text.RegularExpressions;

namespace StarBridge.Desktop;

public static partial class LocationNameLocalizer
{
    private const string Unknown = "Unknown";
    private const string VerifiedLocationFileName = "location-names-zh.txt";
    private static readonly Lazy<IReadOnlyDictionary<string, string>> ChineseNames =
        new(() => LoadChineseNames(VerifiedLocationFileName));

    public static string DisplayName(string? location, string language)
    {
        var normalized = NormalizeLocation(location);
        if (normalized.Equals(Unknown, StringComparison.OrdinalIgnoreCase))
        {
            return normalized;
        }

        if (!language.Equals("zh", StringComparison.OrdinalIgnoreCase))
        {
            return normalized;
        }

        if (ChineseNames.Value.TryGetValue(normalized, out var localized))
        {
            return localized;
        }

        return SimplifyHumanReadableLocation(normalized);
    }

    public static IReadOnlyDictionary<string, string> KnownChineseNames => ChineseNames.Value;

    public static string NormalizeLocation(string? location)
    {
        if (string.IsNullOrWhiteSpace(location) ||
            location.Equals(Unknown, StringComparison.OrdinalIgnoreCase))
        {
            return Unknown;
        }

        var normalized = location.Trim();
        normalized = BracketIdRegex().Replace(normalized, "").Trim();
        return string.IsNullOrWhiteSpace(normalized) ? Unknown : normalized;
    }

    private static IReadOnlyDictionary<string, string> LoadChineseNames(string fileName)
    {
        var names = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        var path = Path.Combine(AppContext.BaseDirectory, "Data", fileName);
        if (!File.Exists(path))
        {
            return names;
        }

        foreach (var line in File.ReadLines(path, Encoding.UTF8))
        {
            if (TryParseMapping(line, out var code, out var value))
            {
                names[code] = value;
            }
        }

        return names;
    }

    private static bool TryParseMapping(string rawLine, out string code, out string value)
    {
        code = "";
        value = "";

        var line = rawLine.Trim();
        if (string.IsNullOrWhiteSpace(line) ||
            line.StartsWith('#') ||
            line.EndsWith("system:", StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        var noteIndex = line.IndexOf("标注", StringComparison.Ordinal);
        if (noteIndex > 0)
        {
            line = line[..noteIndex].Trim();
        }

        var equalsIndex = line.IndexOf('=');
        if (equalsIndex > 0)
        {
            code = line[..equalsIndex].Trim();
            value = NormalizeDisplayValue(line[(equalsIndex + 1)..]);
            return !string.IsNullOrWhiteSpace(code) && !string.IsNullOrWhiteSpace(value);
        }

        var match = FlexibleTableLineRegex().Match(line);
        if (!match.Success)
        {
            return false;
        }

        code = match.Groups["code"].Value.Trim();
        value = NormalizeDisplayValue(match.Groups["value"].Value);
        return !string.IsNullOrWhiteSpace(code) && !string.IsNullOrWhiteSpace(value);
    }

    private static string NormalizeDisplayValue(string rawValue)
    {
        var value = rawValue.Trim();
        if (value.StartsWith('/'))
        {
            value = value[1..].Trim();
        }

        var slashIndex = value.LastIndexOf('/');
        if (slashIndex >= 0 && slashIndex < value.Length - 1)
        {
            value = value[(slashIndex + 1)..].Trim();
        }

        var firstCjk = FirstCjkIndex(value);
        if (firstCjk > 0)
        {
            var prefix = value[..firstCjk];
            if (prefix.Any(char.IsLetter) && prefix.Any(char.IsWhiteSpace))
            {
                value = value[firstCjk..].Trim();
            }
        }

        return value;
    }

    private static string SimplifyHumanReadableLocation(string value)
    {
        if (!ContainsCjk(value))
        {
            return value;
        }

        return EnglishParenthesesRegex().Replace(value, "").Trim();
    }

    private static bool ContainsCjk(string value)
    {
        return FirstCjkIndex(value) >= 0;
    }

    private static int FirstCjkIndex(string value)
    {
        for (var index = 0; index < value.Length; index++)
        {
            if (IsCjk(value[index]))
            {
                return index;
            }
        }

        return -1;
    }

    private static bool IsCjk(char character)
    {
        return character is >= '\u4e00' and <= '\u9fff';
    }

    [GeneratedRegex(@"(?<code>[A-Za-z0-9_-]+)\s+(?<value>.+)", RegexOptions.Compiled)]
    private static partial Regex FlexibleTableLineRegex();

    [GeneratedRegex(@"\s*\[[0-9]+\]\s*", RegexOptions.Compiled)]
    private static partial Regex BracketIdRegex();

    [GeneratedRegex(@"\s*\([A-Za-z0-9 _.'-]+\)\s*", RegexOptions.Compiled)]
    private static partial Regex EnglishParenthesesRegex();
}
