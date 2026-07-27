using System.IO;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace StarBridge.Desktop;

public sealed class ShipNamePackDocument
{
    public int SchemaVersion { get; init; }
    public string Revision { get; init; } = "";
    public IReadOnlyList<ShipNamePackEntry> Entries { get; init; } = [];
}

public sealed class ShipNamePackEntry
{
    public string RuntimeId { get; init; } = "";
    public string EnglishName { get; init; } = "";
    public string ChineseName { get; init; } = "";
    public IReadOnlyList<string> Aliases { get; init; } = [];
}

public sealed class ShipNameCatalogSnapshot
{
    internal ShipNameCatalogSnapshot(
        IReadOnlyDictionary<string, string> chineseNames,
        IReadOnlyDictionary<string, string> englishNames,
        IReadOnlyDictionary<string, IReadOnlyList<string>> nameAliases,
        IReadOnlyDictionary<string, string> codeAliases,
        IReadOnlyCollection<string> knownCodes,
        IReadOnlyList<string> diagnostics)
    {
        ChineseNames = chineseNames;
        EnglishNames = englishNames;
        NameAliases = nameAliases;
        CodeAliases = codeAliases;
        KnownCodes = knownCodes;
        Diagnostics = diagnostics;
    }

    public IReadOnlyDictionary<string, string> ChineseNames { get; }
    public IReadOnlyDictionary<string, string> EnglishNames { get; }
    public IReadOnlyDictionary<string, IReadOnlyList<string>> NameAliases { get; }
    public IReadOnlyDictionary<string, string> CodeAliases { get; }
    public IReadOnlyCollection<string> KnownCodes { get; }
    public IReadOnlyList<string> Diagnostics { get; }

    public string ResolveCode(string? shipCodeOrName)
    {
        var normalized = ShipNameCatalog.NormalizeCode(shipCodeOrName);
        if (normalized.Equals(ShipNameCatalog.Unknown, StringComparison.OrdinalIgnoreCase))
        {
            return ShipNameCatalog.Unknown;
        }

        if (CodeAliases.TryGetValue(ShipNameCatalog.NormalizeLookupKey(normalized), out var exactCode))
        {
            return exactCode;
        }

        if (normalized.Contains('_', StringComparison.Ordinal))
        {
            return normalized;
        }

        return ShipNameCatalog.TryInferCodeFromEnglish(normalized, out var inferredCode)
            ? inferredCode
            : normalized;
    }

    public string DisplayName(string? shipCodeOrName, string language)
    {
        var code = ResolveCode(shipCodeOrName);
        if (code.Equals(ShipNameCatalog.Unknown, StringComparison.OrdinalIgnoreCase))
        {
            return ShipNameCatalog.Unknown;
        }

        if (language.Equals("zh", StringComparison.OrdinalIgnoreCase) &&
            ChineseNames.TryGetValue(code, out var chineseName))
        {
            return chineseName;
        }

        return EnglishNames.TryGetValue(code, out var englishName)
            ? englishName
            : ShipNameCatalog.ToDisplayName(code);
    }

    public IReadOnlyList<string> GetNameAliases(string? shipCode)
    {
        var normalized = ShipNameCatalog.NormalizeCode(shipCode);
        return NameAliases.TryGetValue(normalized, out var aliases)
            ? aliases
            : [];
    }
}

public static class ShipNameCatalog
{
    internal const string Unknown = "Unknown";
    private const int CurrentSchemaVersion = 1;
    private const string PublicPackFileName = "ship-name-pack.json";
    private const string LegacyNameFileName = "ship-names-zh.txt";
    private const string LegacyCatalogFileName = "ship-catalog.tsv";
    private static readonly Regex RuntimeIdPattern = new(
        "^[A-Za-z0-9]+_[A-Za-z0-9_-]+$",
        RegexOptions.CultureInvariant);

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
        ReadCommentHandling = JsonCommentHandling.Skip,
        AllowTrailingCommas = true,
        UnmappedMemberHandling = System.Text.Json.Serialization.JsonUnmappedMemberHandling.Disallow
    };

    private static readonly IReadOnlyDictionary<string, string[]> ManufacturerEnglishNames =
        new Dictionary<string, string[]>(StringComparer.OrdinalIgnoreCase)
        {
            ["AEGS"] = ["Aegis Dynamics", "Aegis"],
            ["ANVL"] = ["Anvil Aerospace", "Anvil"],
            ["ARGO"] = ["Argo Astronautics", "Argo"],
            ["BANU"] = ["Banu"],
            ["CNOU"] = ["Consolidated Outland", "CNOU"],
            ["CRUS"] = ["Crusader Industries", "Crusader"],
            ["DRAK"] = ["Drake Interplanetary", "Drake"],
            ["ESPR"] = ["Esperia"],
            ["GAMA"] = ["Gatac"],
            ["GLSN"] = ["Grey's Market", "Greys Market"],
            ["GRIN"] = ["Greycat Industrial", "Greycat"],
            ["KRIG"] = ["Kruger Intergalactic", "Kruger"],
            ["MISC"] = ["Musashi Industrial and Starflight Concern", "MISC", "Musashi"],
            ["MIRAI"] = ["Mirai"],
            ["MRAI"] = ["Mirai"],
            ["ORIG"] = ["Origin Jumpworks", "Origin"],
            ["RSI"] = ["Roberts Space Industries", "RSI"],
            ["TMBL"] = ["Tumbril Land Systems", "Tumbril"],
            ["VNCL"] = ["Vanduul"],
            ["XIAN"] = ["Aopoa", "Xi'an", "Xian"],
            ["XNAA"] = ["Aopoa", "Xi'an", "Xian"],
            ["AOPOA"] = ["Aopoa", "Xi'an", "Xian"],
            ["AOPA"] = ["Aopoa", "Xi'an", "Xian"]
        };

    public static ShipNameCatalogSnapshot Load(string baseDirectory, bool includeLegacyData = true)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(baseDirectory);

        var dataDirectory = Path.Combine(baseDirectory, "Data");
        var builder = new CatalogBuilder();
        LoadPublicPack(Path.Combine(dataDirectory, PublicPackFileName), builder);

        if (includeLegacyData)
        {
            LoadLegacyNames(Path.Combine(dataDirectory, LegacyNameFileName), builder);
            LoadLegacyCatalog(Path.Combine(dataDirectory, LegacyCatalogFileName), builder);
        }

        return builder.Build();
    }

    public static string NormalizeCode(string? shipCode)
    {
        if (string.IsNullOrWhiteSpace(shipCode) ||
            shipCode.Equals(Unknown, StringComparison.OrdinalIgnoreCase))
        {
            return Unknown;
        }

        var normalized = Regex.Replace(shipCode.Trim(), @"_\d+$", "");
        return string.IsNullOrWhiteSpace(normalized) ? Unknown : normalized;
    }

    public static string ToDisplayName(string? shipCode)
    {
        var normalized = NormalizeCode(shipCode);
        if (normalized.Equals(Unknown, StringComparison.OrdinalIgnoreCase))
        {
            return Unknown;
        }

        var separatorIndex = normalized.IndexOf('_');
        if (separatorIndex > 0 &&
            separatorIndex < normalized.Length - 1 &&
            ManufacturerEnglishNames.ContainsKey(normalized[..separatorIndex]))
        {
            normalized = normalized[(separatorIndex + 1)..];
        }

        return Regex.Replace(
                normalized.Replace('_', ' ').Replace('-', ' '),
                @"\s+",
                " ")
            .Trim();
    }

    internal static string NormalizeLookupKey(string? value)
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

    internal static bool TryInferCodeFromEnglish(string value, out string code)
    {
        var trimmed = value.Trim();
        foreach (var manufacturer in ManufacturerEnglishNames)
        {
            foreach (var name in manufacturer.Value.OrderByDescending(candidate => candidate.Length))
            {
                if (!trimmed.StartsWith(name, StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }

                var remaining = trimmed[name.Length..].TrimStart(' ', '-', ':');
                if (string.IsNullOrWhiteSpace(remaining))
                {
                    continue;
                }

                var modelCode = Regex.Replace(remaining, @"[^A-Za-z0-9]+", "_").Trim('_');
                if (string.IsNullOrWhiteSpace(modelCode))
                {
                    continue;
                }

                code = $"{manufacturer.Key}_{modelCode}";
                return true;
            }
        }

        code = "";
        return false;
    }

    private static void LoadPublicPack(string path, CatalogBuilder builder)
    {
        if (!File.Exists(path))
        {
            return;
        }

        try
        {
            var document = JsonSerializer.Deserialize<ShipNamePackDocument>(
                File.ReadAllText(path, Encoding.UTF8),
                JsonOptions);
            var validationErrors = ValidatePublicPack(document);
            if (validationErrors.Count > 0)
            {
                builder.AddDiagnostic(
                    $"{PublicPackFileName} was ignored: {string.Join("; ", validationErrors)}");
                return;
            }

            foreach (var entry in document!.Entries)
            {
                builder.AddPublicEntry(entry);
            }
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or JsonException)
        {
            builder.AddDiagnostic($"{PublicPackFileName} was ignored: {ex.Message}");
        }
    }

    private static IReadOnlyList<string> ValidatePublicPack(ShipNamePackDocument? document)
    {
        var errors = new List<string>();
        if (document is null)
        {
            errors.Add("document is empty");
            return errors;
        }

        if (document.SchemaVersion != CurrentSchemaVersion)
        {
            errors.Add($"schemaVersion must be {CurrentSchemaVersion}");
        }

        if (string.IsNullOrWhiteSpace(document.Revision))
        {
            errors.Add("revision is required");
        }

        if (document.Entries is null)
        {
            errors.Add("entries is required");
            return errors;
        }

        var runtimeIds = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        for (var index = 0; index < document.Entries.Count; index++)
        {
            var entry = document.Entries[index];
            var label = $"entries[{index}]";
            var runtimeId = NormalizeCode(entry.RuntimeId);

            if (runtimeId.Equals(Unknown, StringComparison.OrdinalIgnoreCase) ||
                !RuntimeIdPattern.IsMatch(entry.RuntimeId))
            {
                errors.Add($"{label}.runtimeId is invalid");
            }
            else if (!runtimeIds.Add(runtimeId))
            {
                errors.Add($"{label}.runtimeId is duplicated");
            }

            Require(entry.EnglishName, $"{label}.englishName", errors);
            Require(entry.ChineseName, $"{label}.chineseName", errors);
            if (entry.Aliases is null)
            {
                errors.Add($"{label}.aliases is required");
                continue;
            }

            var aliases = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            for (var aliasIndex = 0; aliasIndex < entry.Aliases.Count; aliasIndex++)
            {
                var alias = entry.Aliases[aliasIndex];
                if (string.IsNullOrWhiteSpace(alias))
                {
                    errors.Add($"{label}.aliases[{aliasIndex}] is invalid");
                }
                else if (!aliases.Add(alias.Trim()))
                {
                    errors.Add($"{label}.aliases[{aliasIndex}] is duplicated");
                }
            }
        }

        return errors;
    }

    private static void Require(string value, string name, ICollection<string> errors)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            errors.Add($"{name} is required");
        }
    }

    private static void LoadLegacyNames(string path, CatalogBuilder builder)
    {
        if (!File.Exists(path))
        {
            return;
        }

        var preferredNames = new Dictionary<string, (string Name, bool IsShort)>(
            StringComparer.OrdinalIgnoreCase);
        foreach (var line in File.ReadLines(path, Encoding.UTF8))
        {
            if (!TryParseLegacyName(line, out var code, out var value, out var isShortName))
            {
                continue;
            }

            builder.AddAlias(code, value);
            if (!preferredNames.TryGetValue(code, out var existing) ||
                isShortName ||
                !existing.IsShort)
            {
                preferredNames[code] = (value, isShortName);
            }
        }

        foreach (var preferredName in preferredNames)
        {
            builder.AddLegacyChineseName(preferredName.Key, preferredName.Value.Name);
        }
    }

    private static bool TryParseLegacyName(
        string line,
        out string code,
        out string value,
        out bool isShortName)
    {
        code = "";
        value = "";
        isShortName = false;

        var separatorIndex = line.IndexOf('=');
        if (separatorIndex <= 0 || separatorIndex >= line.Length - 1)
        {
            return false;
        }

        var rawKey = line[..separatorIndex].Trim();
        value = line[(separatorIndex + 1)..].Trim();
        if (!rawKey.StartsWith("vehicle_Name", StringComparison.OrdinalIgnoreCase) ||
            string.IsNullOrWhiteSpace(value))
        {
            return false;
        }

        code = rawKey["vehicle_Name".Length..];
        isShortName = code.EndsWith("_short", StringComparison.OrdinalIgnoreCase);
        if (isShortName)
        {
            code = code[..^"_short".Length];
        }

        code = NormalizeCode(code);
        return !code.Equals(Unknown, StringComparison.OrdinalIgnoreCase);
    }

    private static void LoadLegacyCatalog(string path, CatalogBuilder builder)
    {
        if (!File.Exists(path))
        {
            return;
        }

        foreach (var line in File.ReadLines(path, Encoding.UTF8))
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
                !builder.TryResolveUniqueAlias(chineseName, out var code))
            {
                continue;
            }

            builder.AddLegacyEnglishName(code, englishName);
            builder.AddAlias(code, englishName);
        }
    }

    private static string Clean(string? value)
    {
        return value?.Replace('\t', ' ').Replace("\r", " ").Replace("\n", " ").Trim() ?? "";
    }

    private sealed class CatalogBuilder
    {
        private readonly Dictionary<string, string> _chineseNames =
            new(StringComparer.OrdinalIgnoreCase);
        private readonly Dictionary<string, string> _englishNames =
            new(StringComparer.OrdinalIgnoreCase);
        private readonly Dictionary<string, List<string>> _aliases =
            new(StringComparer.OrdinalIgnoreCase);
        private readonly HashSet<string> _publicChineseNames =
            new(StringComparer.OrdinalIgnoreCase);
        private readonly HashSet<string> _publicEnglishNames =
            new(StringComparer.OrdinalIgnoreCase);
        private readonly List<string> _diagnostics = [];

        public void AddPublicEntry(ShipNamePackEntry entry)
        {
            var code = NormalizeCode(entry.RuntimeId);
            _englishNames[code] = Clean(entry.EnglishName);
            _publicEnglishNames.Add(code);

            if (!string.IsNullOrWhiteSpace(entry.ChineseName))
            {
                _chineseNames[code] = Clean(entry.ChineseName);
                _publicChineseNames.Add(code);
            }

            AddAlias(code, code);
            AddAlias(code, entry.EnglishName);
            AddAlias(code, entry.ChineseName);
            foreach (var alias in entry.Aliases)
            {
                AddAlias(code, alias);
            }
        }

        public void AddLegacyChineseName(string code, string name)
        {
            code = NormalizeCode(code);
            if (!_publicChineseNames.Contains(code))
            {
                _chineseNames[code] = Clean(name);
            }
        }

        public void AddLegacyEnglishName(string code, string name)
        {
            code = NormalizeCode(code);
            if (!_publicEnglishNames.Contains(code))
            {
                _englishNames[code] = Clean(name);
            }
        }

        public void AddAlias(string code, string? alias)
        {
            code = NormalizeCode(code);
            var cleanAlias = Clean(alias);
            if (code.Equals(Unknown, StringComparison.OrdinalIgnoreCase) ||
                string.IsNullOrWhiteSpace(cleanAlias))
            {
                return;
            }

            if (!_aliases.TryGetValue(code, out var values))
            {
                values = [];
                _aliases[code] = values;
            }

            if (!values.Contains(cleanAlias, StringComparer.OrdinalIgnoreCase))
            {
                values.Add(cleanAlias);
            }
        }

        public bool TryResolveUniqueAlias(string alias, out string code)
        {
            var key = NormalizeLookupKey(alias);
            var matches = _aliases
                .Where(pair => pair.Value.Any(value =>
                    NormalizeLookupKey(value).Equals(key, StringComparison.OrdinalIgnoreCase)))
                .Select(pair => pair.Key)
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .Take(2)
                .ToArray();

            code = matches.Length == 1 ? matches[0] : "";
            return matches.Length == 1;
        }

        public void AddDiagnostic(string diagnostic)
        {
            _diagnostics.Add(diagnostic);
        }

        public ShipNameCatalogSnapshot Build()
        {
            var knownCodes = _chineseNames.Keys
                .Concat(_englishNames.Keys)
                .Concat(_aliases.Keys)
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .OrderBy(code => code, StringComparer.OrdinalIgnoreCase)
                .ToArray();

            foreach (var code in knownCodes)
            {
                AddGeneratedAliases(code);
            }

            var codeAliases = BuildCodeAliasIndex(knownCodes);
            return new ShipNameCatalogSnapshot(
                new Dictionary<string, string>(_chineseNames, StringComparer.OrdinalIgnoreCase),
                new Dictionary<string, string>(_englishNames, StringComparer.OrdinalIgnoreCase),
                _aliases.ToDictionary(
                    pair => pair.Key,
                    pair => (IReadOnlyList<string>)pair.Value.ToArray(),
                    StringComparer.OrdinalIgnoreCase),
                codeAliases,
                knownCodes,
                _diagnostics.ToArray());
        }

        private void AddGeneratedAliases(string code)
        {
            AddAlias(code, code);
            AddAlias(code, ToDisplayName(code));

            var separatorIndex = code.IndexOf('_');
            if (separatorIndex <= 0 || separatorIndex >= code.Length - 1)
            {
                return;
            }

            var manufacturerCode = code[..separatorIndex];
            var modelName = ToDisplayName(code);
            if (!ManufacturerEnglishNames.TryGetValue(manufacturerCode, out var manufacturerNames))
            {
                return;
            }

            foreach (var manufacturerName in manufacturerNames)
            {
                AddAlias(code, $"{manufacturerName} {modelName}");
            }
        }

        private IReadOnlyDictionary<string, string> BuildCodeAliasIndex(IEnumerable<string> knownCodes)
        {
            var index = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            var ambiguous = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

            foreach (var code in knownCodes)
            {
                foreach (var alias in _aliases.GetValueOrDefault(code) ?? [])
                {
                    var key = NormalizeLookupKey(alias);
                    if (string.IsNullOrWhiteSpace(key) || ambiguous.Contains(key))
                    {
                        continue;
                    }

                    if (index.TryGetValue(key, out var existingCode) &&
                        !existingCode.Equals(code, StringComparison.OrdinalIgnoreCase))
                    {
                        index.Remove(key);
                        ambiguous.Add(key);
                        continue;
                    }

                    index[key] = code;
                }
            }

            return index;
        }
    }
}
