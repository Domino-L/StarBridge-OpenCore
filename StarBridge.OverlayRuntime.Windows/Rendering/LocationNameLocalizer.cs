using System.IO;
using System.Text;
using System.Text.RegularExpressions;

namespace StarBridge.Desktop;

public static partial class LocationNameLocalizer
{
    private const string Unknown = "Unknown";
    private const string VerifiedLocationFileName = "location-names-zh.txt";
    private const string LocationCatalogFileName = "starbridge_location_catalog.json";
    private static readonly Lazy<LocationCatalogIndex> Catalog =
        new(() => LocationCatalogIndex.Load(
            Path.Combine(AppContext.BaseDirectory, "Data", LocationCatalogFileName)));
    private static readonly Lazy<IReadOnlyDictionary<string, string>> LegacyChineseNames =
        new(() => LoadChineseNames(VerifiedLocationFileName));
    private static readonly Lazy<IReadOnlyDictionary<string, string>> ChineseNames =
        new(BuildCombinedChineseNames);
    private static readonly Lazy<IReadOnlyList<string>> ChineseDisplayNames =
        new(() => ChineseNames.Value.Values
            .Select(value => value.Trim())
            .Where(value =>
                !string.IsNullOrWhiteSpace(value) &&
                !value.Equals(Unknown, StringComparison.OrdinalIgnoreCase) &&
                !value.Contains('_') &&
                ContainsCjk(value))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .OrderBy(value => value, StringComparer.OrdinalIgnoreCase)
            .ToArray());
    private static readonly object UnknownDiagnosticsGate = new();
    private static readonly Dictionary<string, UnknownLocationDiagnostic> UnknownDiagnostics =
        new(StringComparer.OrdinalIgnoreCase);
    private const int UnknownDiagnosticCapacity = 64;

    public static string DisplayName(string? location, string language)
    {
        var normalized = NormalizeLocation(location);
        if (normalized.Equals(Unknown, StringComparison.OrdinalIgnoreCase))
        {
            return normalized;
        }

        if (Catalog.Value.TryResolve(normalized, out var match))
        {
            if (!language.Equals("zh", StringComparison.OrdinalIgnoreCase))
            {
                return match.NameEn;
            }

            return TryGetLegacyChineseName(normalized, match, out var legacyName)
                ? legacyName
                : match.NameZh;
        }

        if (language.Equals("zh", StringComparison.OrdinalIgnoreCase) &&
            LegacyChineseNames.Value.TryGetValue(normalized, out var localized))
        {
            return localized;
        }

        ObserveUnknownLocation(normalized);
        return SimplifyHumanReadableLocation(normalized);
    }

    public static IReadOnlyDictionary<string, string> KnownChineseNames => ChineseNames.Value;
    public static IReadOnlyList<string> ConfirmedChineseDisplayNames => ChineseDisplayNames.Value;
    public static bool IsCatalogLoaded => Catalog.Value.IsLoaded;
    public static string? CatalogLoadError => Catalog.Value.LoadError;
    public static LocationCatalogMetadata CatalogMetadata => Catalog.Value.Metadata;

    public static IReadOnlyList<UnknownLocationDiagnostic> UnknownLocationDiagnostics
    {
        get
        {
            lock (UnknownDiagnosticsGate)
            {
                return UnknownDiagnostics.Values
                    .OrderByDescending(item => item.LastSeenAtUtc)
                    .ToArray();
            }
        }
    }

    public static bool TryResolve(string? location, out LocationCatalogMatch match)
    {
        var normalized = NormalizeLocation(location);
        if (normalized.Equals(Unknown, StringComparison.OrdinalIgnoreCase))
        {
            match = null!;
            return false;
        }

        var resolved = Catalog.Value.TryResolve(normalized, out match);
        if (!resolved)
        {
            ObserveUnknownLocation(normalized);
        }

        return resolved;
    }

    public static bool CanPersistOrSynchronize(string? location)
    {
        var normalized = NormalizeLocation(location);
        return !Catalog.Value.TryResolve(normalized, out var match) ||
               !match.IsDynamic ||
               match.Persistent;
    }

    public static string Breadcrumb(string? location, string language)
    {
        var hierarchy = Catalog.Value.GetHierarchy(NormalizeLocation(location));
        if (hierarchy.Count == 0)
        {
            return DisplayName(location, language);
        }

        var chinese = language.Equals("zh", StringComparison.OrdinalIgnoreCase);
        return string.Join(
            " › ",
            hierarchy
                .Select(item => chinese ? item.NameZh : item.NameEn)
                .Where(name => !string.IsNullOrWhiteSpace(name))
                .Distinct(StringComparer.OrdinalIgnoreCase));
    }

    public static string CatalogDiagnosticSummary()
    {
        if (!IsCatalogLoaded)
        {
            return $"地点目录：加载失败（{CatalogLoadError ?? "未知错误"}）";
        }

        var metadata = CatalogMetadata;
        var generated = metadata.GeneratedAtUtc?.ToString("u") ?? "未提供";
        return string.Join(Environment.NewLine, new[]
        {
            $"地点目录：已加载 / schema {metadata.SchemaVersion}",
            $"目录生成时间：{generated}",
            $"游戏版本：{metadata.GameBuild ?? "未提供"}",
            $"SCM 目录版本：{metadata.ScmCatalogVersion ?? "未提供"}",
            $"规范地点 / 运行时别名 / 动态规则：{metadata.EntryCount} / {metadata.AliasCount} / {metadata.DynamicPatternCount}",
            $"量子别名 / OOC 容器别名：{metadata.QuantumAliasCount} / {metadata.ObjectContainerAliasCount}",
            $"SCM 已关联 / 排除定义：{metadata.ScmLinkedEntryCount} / {metadata.ExcludedEntryCount}",
            $"本次运行未知地点代码：{UnknownLocationDiagnostics.Count}"
        });
    }

    public static string NormalizeLocation(string? location)
    {
        if (string.IsNullOrWhiteSpace(location) ||
            location.Equals(Unknown, StringComparison.OrdinalIgnoreCase))
        {
            return Unknown;
        }

        return Catalog.Value.NormalizeCode(location);
    }

    private static void ObserveUnknownLocation(string value)
    {
        if (string.IsNullOrWhiteSpace(value) ||
            value.Equals(Unknown, StringComparison.OrdinalIgnoreCase) ||
            value.Equals("None", StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        var safeCode = new string(value
            .Where(character => !char.IsControl(character))
            .Take(160)
            .ToArray())
            .Trim();
        if (safeCode.Length == 0)
        {
            return;
        }

        lock (UnknownDiagnosticsGate)
        {
            var now = DateTimeOffset.UtcNow;
            if (UnknownDiagnostics.TryGetValue(safeCode, out var existing))
            {
                UnknownDiagnostics[safeCode] = existing with
                {
                    Count = existing.Count + 1,
                    LastSeenAtUtc = now
                };
                return;
            }

            if (UnknownDiagnostics.Count >= UnknownDiagnosticCapacity)
            {
                var oldest = UnknownDiagnostics.Values.MinBy(item => item.LastSeenAtUtc);
                if (oldest is not null)
                {
                    UnknownDiagnostics.Remove(oldest.Code);
                }
            }

            UnknownDiagnostics[safeCode] = new UnknownLocationDiagnostic(safeCode, 1, now);
        }
    }

    private static IReadOnlyDictionary<string, string> BuildCombinedChineseNames()
    {
        var names = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var pair in Catalog.Value.Lookup)
        {
            names[pair.Key] = pair.Value.NameZh;
        }

        foreach (var pair in LegacyChineseNames.Value)
        {
            names[pair.Key] = pair.Value;
            var prefixedAlias = $"LOC_{pair.Key}";
            if (names.ContainsKey(prefixedAlias))
            {
                names[prefixedAlias] = pair.Value;
            }
        }

        return names;
    }

    private static bool TryGetLegacyChineseName(
        string normalized,
        LocationCatalogMatch match,
        out string name)
    {
        if (LegacyChineseNames.Value.TryGetValue(normalized, out name!))
        {
            return true;
        }

        if (normalized.StartsWith("LOC_", StringComparison.OrdinalIgnoreCase) &&
            LegacyChineseNames.Value.TryGetValue(normalized[4..], out name!))
        {
            return true;
        }

        return LegacyChineseNames.Value.TryGetValue(match.CanonicalCode, out name!);
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

    [GeneratedRegex(@"\s*\([A-Za-z0-9 _.'-]+\)\s*", RegexOptions.Compiled)]
    private static partial Regex EnglishParenthesesRegex();
}

public sealed record UnknownLocationDiagnostic(
    string Code,
    int Count,
    DateTimeOffset LastSeenAtUtc);
