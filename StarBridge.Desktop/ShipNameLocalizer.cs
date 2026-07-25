using System.IO;
using System.Text;
using System.Text.RegularExpressions;

namespace StarBridge.Desktop;

public static partial class ShipNameLocalizer
{
    private const string Unknown = "Unknown";
    private static readonly Lazy<IReadOnlyDictionary<string, string>> ChineseNames = new(LoadChineseNames);
    private static readonly Lazy<IReadOnlyDictionary<string, IReadOnlyList<string>>> ChineseNameAliases = new(LoadChineseNameAliases);
    private static readonly Lazy<IReadOnlyDictionary<string, string>> ShipCodeAliases = new(BuildShipCodeAliasIndex);
    private static readonly IReadOnlyDictionary<string, string[]> ManufacturerEnglishNames =
        new Dictionary<string, string[]>(StringComparer.OrdinalIgnoreCase)
        {
            ["AEGS"] = ["Aegis", "Aegis Dynamics"],
            ["ANVL"] = ["Anvil", "Anvil Aerospace"],
            ["ARGO"] = ["Argo", "Argo Astronautics"],
            ["BANU"] = ["Banu"],
            ["CNOU"] = ["Consolidated Outland", "CO"],
            ["CRUS"] = ["Crusader", "Crusader Industries"],
            ["DRAK"] = ["Drake", "Drake Interplanetary"],
            ["ESPR"] = ["Esperia"],
            ["GAMA"] = ["Gatac"],
            ["GLSN"] = ["Grey's Market", "Greys Market"],
            ["GRIN"] = ["Greycat", "Greycat Industrial"],
            ["KRIG"] = ["Kruger", "Kruger Intergalactic"],
            ["MISC"] = ["MISC", "Musashi"],
            ["MIRAI"] = ["Mirai"],
            ["MRAI"] = ["Mirai"],
            ["ORIG"] = ["Origin", "Origin Jumpworks"],
            ["RSI"] = ["RSI", "Roberts Space Industries"],
            ["TMBL"] = ["Tumbril", "Tumbril Land Systems"],
            ["VNCL"] = ["Vanduul"],
            ["XIAN"] = ["Aopoa", "Xi'an", "Xian"],
            ["XNAA"] = ["Aopoa", "Xi'an", "Xian"],
            ["AOPOA"] = ["Aopoa", "Xi'an", "Xian"],
            ["AOPA"] = ["Aopoa", "Xi'an", "Xian"]
        };

    public static string DisplayName(string? shipCode, string language)
    {
        var normalized = ResolveCode(shipCode);
        if (normalized.Equals(Unknown, StringComparison.OrdinalIgnoreCase) ||
            !language.Equals("zh", StringComparison.OrdinalIgnoreCase))
        {
            return normalized;
        }

        return ChineseNames.Value.TryGetValue(normalized, out var localized)
            ? localized
            : normalized;
    }

    public static IReadOnlyDictionary<string, string> KnownChineseNames => ChineseNames.Value;

    public static string ResolveCode(string? shipCodeOrName)
    {
        var normalized = NormalizeCode(shipCodeOrName);
        if (normalized.Equals(Unknown, StringComparison.OrdinalIgnoreCase))
        {
            return Unknown;
        }

        if (IsKnownCode(normalized) || normalized.Contains('_', StringComparison.Ordinal))
        {
            return normalized;
        }

        return ShipCodeAliases.Value.TryGetValue(NormalizeLookupKey(normalized), out var code)
            ? code
            : normalized;
    }

    public static IReadOnlyList<string> GetNameAliases(string? shipCode)
    {
        var normalized = NormalizeCode(shipCode);
        return ChineseNameAliases.Value.TryGetValue(normalized, out var aliases)
            ? aliases
            : [];
    }

    public static string NormalizeCode(string? shipCode)
    {
        if (string.IsNullOrWhiteSpace(shipCode) ||
            shipCode.Equals(Unknown, StringComparison.OrdinalIgnoreCase))
        {
            return Unknown;
        }

        var normalized = EntityIdSuffixRegex().Replace(shipCode.Trim(), "");
        return string.IsNullOrWhiteSpace(normalized) ? Unknown : normalized;
    }

    private static bool IsKnownCode(string code)
    {
        return ChineseNames.Value.ContainsKey(code) ||
               ChineseNameAliases.Value.ContainsKey(code);
    }

    private static IReadOnlyDictionary<string, string> BuildShipCodeAliasIndex()
    {
        var aliases = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        var ambiguous = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        void AddAlias(string? value, string code)
        {
            var key = NormalizeLookupKey(value);
            if (string.IsNullOrWhiteSpace(key) || ambiguous.Contains(key))
            {
                return;
            }

            if (aliases.TryGetValue(key, out var existing))
            {
                if (!existing.Equals(code, StringComparison.OrdinalIgnoreCase))
                {
                    aliases.Remove(key);
                    ambiguous.Add(key);
                }

                return;
            }

            aliases[key] = code;
        }

        var knownCodes = ChineseNames.Value.Keys
            .Concat(ChineseNameAliases.Value.Keys)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();

        foreach (var code in knownCodes)
        {
            AddCodeAliases(code, AddAlias);
        }

        var chineseAliasToCode = BuildChineseAliasToCode(knownCodes);
        var catalogPath = Path.Combine(AppContext.BaseDirectory, "Data", "ship-catalog.tsv");
        if (File.Exists(catalogPath))
        {
            foreach (var line in File.ReadLines(catalogPath, Encoding.UTF8))
            {
                if (string.IsNullOrWhiteSpace(line) || line.StartsWith('#'))
                {
                    continue;
                }

                var parts = line.Split('\t');
                if (parts.Length < 3)
                {
                    continue;
                }

                var englishName = Clean(parts[1]);
                var chineseName = Clean(parts[2]);
                if (string.IsNullOrWhiteSpace(englishName) ||
                    string.IsNullOrWhiteSpace(chineseName) ||
                    !chineseAliasToCode.TryGetValue(NormalizeLookupKey(chineseName), out var code))
                {
                    continue;
                }

                AddAlias(englishName, code);
                AddManufacturerAliases(englishName, code, AddAlias);
            }
        }

        return aliases;
    }

    private static void AddCodeAliases(string code, Action<string?, string> addAlias)
    {
        var normalizedCode = NormalizeCode(code);
        if (normalizedCode.Equals(Unknown, StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        addAlias(normalizedCode, normalizedCode);
        addAlias(ToDisplayWords(normalizedCode), normalizedCode);

        var codeWithoutManufacturer = RemoveManufacturerPrefix(normalizedCode);
        addAlias(codeWithoutManufacturer, normalizedCode);
        addAlias(ToDisplayWords(codeWithoutManufacturer), normalizedCode);
        AddManufacturerAliases(ToDisplayWords(codeWithoutManufacturer), normalizedCode, addAlias);

        if (ChineseNames.Value.TryGetValue(normalizedCode, out var displayName))
        {
            addAlias(displayName, normalizedCode);
        }

        foreach (var alias in GetNameAliases(normalizedCode))
        {
            addAlias(alias, normalizedCode);
        }
    }

    private static IReadOnlyDictionary<string, string> BuildChineseAliasToCode(IEnumerable<string> knownCodes)
    {
        var index = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

        void AddChineseAlias(string? value, string code)
        {
            var key = NormalizeLookupKey(value);
            if (!string.IsNullOrWhiteSpace(key) && !index.ContainsKey(key))
            {
                index[key] = code;
            }
        }

        foreach (var code in knownCodes)
        {
            if (ChineseNames.Value.TryGetValue(code, out var displayName))
            {
                AddChineseAlias(displayName, code);
            }

            foreach (var alias in GetNameAliases(code))
            {
                AddChineseAlias(alias, code);
            }
        }

        return index;
    }

    private static void AddManufacturerAliases(string englishName, string code, Action<string?, string> addAlias)
    {
        if (string.IsNullOrWhiteSpace(englishName))
        {
            return;
        }

        var manufacturerCode = GetManufacturerCode(code);
        if (string.IsNullOrWhiteSpace(manufacturerCode) ||
            !ManufacturerEnglishNames.TryGetValue(manufacturerCode, out var manufacturerNames))
        {
            return;
        }

        foreach (var manufacturerName in manufacturerNames)
        {
            addAlias($"{manufacturerName} {englishName}", code);
        }
    }

    private static string GetManufacturerCode(string code)
    {
        var normalizedCode = NormalizeCode(code);
        var separatorIndex = normalizedCode.IndexOf('_');
        return separatorIndex > 0 ? normalizedCode[..separatorIndex] : "";
    }

    private static string RemoveManufacturerPrefix(string code)
    {
        var normalizedCode = NormalizeCode(code);
        var separatorIndex = normalizedCode.IndexOf('_');
        return separatorIndex > 0 && separatorIndex < normalizedCode.Length - 1
            ? normalizedCode[(separatorIndex + 1)..]
            : normalizedCode;
    }

    private static string ToDisplayWords(string value)
    {
        return value
            .Replace('_', ' ')
            .Replace('-', ' ')
            .Trim();
    }

    private static string NormalizeLookupKey(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return "";
        }

        var builder = new StringBuilder(value.Length);
        foreach (var ch in value.Trim().ToLowerInvariant())
        {
            if (char.IsLetterOrDigit(ch))
            {
                builder.Append(ch);
            }
        }

        return builder.ToString();
    }

    private static string Clean(string? value)
    {
        return value?.Replace('\t', ' ').Replace("\r", " ").Replace("\n", " ").Trim() ?? "";
    }

    private static IReadOnlyDictionary<string, string> LoadChineseNames()
    {
        var names = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        var path = Path.Combine(AppContext.BaseDirectory, "Data", "ship-names-zh.txt");
        if (!File.Exists(path))
        {
            return names;
        }

        foreach (var line in File.ReadLines(path, Encoding.UTF8))
        {
            var separatorIndex = line.IndexOf('=');
            if (separatorIndex <= 0 || separatorIndex >= line.Length - 1)
            {
                continue;
            }

            var rawKey = line[..separatorIndex].Trim();
            var value = line[(separatorIndex + 1)..].Trim();
            var isShortName = rawKey.EndsWith("_short", StringComparison.OrdinalIgnoreCase);
            var code = rawKey;

            if (code.StartsWith("vehicle_Name", StringComparison.OrdinalIgnoreCase))
            {
                code = code["vehicle_Name".Length..];
            }
            else
            {
                continue;
            }

            if (isShortName)
            {
                code = code[..^"_short".Length];
            }

            if (string.IsNullOrWhiteSpace(code) || string.IsNullOrWhiteSpace(value))
            {
                continue;
            }

            if (isShortName || !names.ContainsKey(code))
            {
                names[code] = value;
            }
        }

        return names;
    }

    private static IReadOnlyDictionary<string, IReadOnlyList<string>> LoadChineseNameAliases()
    {
        var aliases = new Dictionary<string, List<string>>(StringComparer.OrdinalIgnoreCase);
        var path = Path.Combine(AppContext.BaseDirectory, "Data", "ship-names-zh.txt");
        if (!File.Exists(path))
        {
            return new Dictionary<string, IReadOnlyList<string>>(StringComparer.OrdinalIgnoreCase);
        }

        foreach (var line in File.ReadLines(path, Encoding.UTF8))
        {
            var separatorIndex = line.IndexOf('=');
            if (separatorIndex <= 0 || separatorIndex >= line.Length - 1)
            {
                continue;
            }

            var code = line[..separatorIndex].Trim();
            var value = line[(separatorIndex + 1)..].Trim();
            if (!code.StartsWith("vehicle_Name", StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            code = code["vehicle_Name".Length..];
            if (code.EndsWith("_short", StringComparison.OrdinalIgnoreCase))
            {
                code = code[..^"_short".Length];
            }

            if (string.IsNullOrWhiteSpace(code) || string.IsNullOrWhiteSpace(value))
            {
                continue;
            }

            if (!aliases.TryGetValue(code, out var codeAliases))
            {
                codeAliases = [];
                aliases[code] = codeAliases;
            }

            if (!codeAliases.Contains(value, StringComparer.OrdinalIgnoreCase))
            {
                codeAliases.Add(value);
            }
        }

        return aliases.ToDictionary(
            pair => pair.Key,
            pair => (IReadOnlyList<string>)pair.Value.ToArray(),
            StringComparer.OrdinalIgnoreCase);
    }

    [GeneratedRegex(@"_\d+$", RegexOptions.Compiled)]
    private static partial Regex EntityIdSuffixRegex();
}
