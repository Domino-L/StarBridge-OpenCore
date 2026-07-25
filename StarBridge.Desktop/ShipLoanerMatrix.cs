using System.IO;
using System.Text;
using System.Text.RegularExpressions;

namespace StarBridge.Desktop;

public sealed record ShipLoanerMatrixEntry(
    string SourceEnglishName,
    string SourceChineseName,
    string SourceSpec,
    string UexSourceName,
    string LoanerEnglishName,
    string UexUpdatedText,
    string DisplayRule,
    string HiddenTag);

public static partial class ShipLoanerMatrix
{
    private const string ConceptDisplayRule = "OnlyWhenSourceIsConcept";

    private static readonly Lazy<IReadOnlyDictionary<string, IReadOnlyList<ShipLoanerMatrixEntry>>> EntriesBySourceCache =
        new(BuildEntriesBySource);

    private static readonly string[] ManufacturerPrefixes =
    [
        "Roberts Space Industries",
        "Consolidated Outland",
        "Aegis",
        "Anvil",
        "Argo",
        "Banu",
        "Crusader",
        "Drake",
        "Esperia",
        "Gatac",
        "Greycat",
        "Kruger",
        "MISC",
        "Mirai",
        "Origin",
        "RSI",
        "Tumbril",
        "Vanduul",
        "Aopoa",
        "C.O.",
        "C.O"
    ];

    private static readonly IReadOnlyDictionary<string, string> LoanerAliases = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
    {
        ["Crusader C2 Hercules Starlifter"] = "C2 Hercules",
        ["C2 Hercules Starlifter"] = "C2 Hercules",
        ["C.O. Nomad"] = "Nomad"
    };

    public static IReadOnlyList<ShipLoanerMatrixEntry> FindForConceptSource(string? sourceEnglishName)
    {
        var key = NormalizeKey(sourceEnglishName);
        if (string.IsNullOrWhiteSpace(key) ||
            !EntriesBySourceCache.Value.TryGetValue(key, out var entries))
        {
            return [];
        }

        return entries;
    }

    public static ShipCatalogEntry? FindLoanerCatalog(string loanerEnglishName)
    {
        foreach (var candidate in BuildLoanerLookupCandidates(loanerEnglishName))
        {
            var entry = ShipCatalog.Find(candidate, candidate);
            if (entry is not null)
            {
                return entry;
            }
        }

        return null;
    }

    private static IReadOnlyDictionary<string, IReadOnlyList<ShipLoanerMatrixEntry>> BuildEntriesBySource()
    {
        var path = Path.Combine(AppContext.BaseDirectory, "Data", "ship-loaner-matrix.tsv");
        if (!File.Exists(path))
        {
            return new Dictionary<string, IReadOnlyList<ShipLoanerMatrixEntry>>(StringComparer.OrdinalIgnoreCase);
        }

        var rows = new Dictionary<string, List<ShipLoanerMatrixEntry>>(StringComparer.OrdinalIgnoreCase);
        foreach (var line in File.ReadLines(path, Encoding.UTF8))
        {
            if (string.IsNullOrWhiteSpace(line) ||
                line.StartsWith('#') ||
                line.StartsWith("源英文飞船名", StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            var parts = line.Split('\t');
            if (parts.Length < 8)
            {
                continue;
            }

            var displayRule = Clean(parts[6]);
            if (!displayRule.Equals(ConceptDisplayRule, StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            var entry = new ShipLoanerMatrixEntry(
                Clean(parts[0]),
                Clean(parts[1]),
                Clean(parts[2]),
                Clean(parts[3]),
                Clean(parts[4]),
                Clean(parts[5]),
                displayRule,
                Clean(parts[7]));

            var key = NormalizeKey(entry.SourceEnglishName);
            if (string.IsNullOrWhiteSpace(key) ||
                string.IsNullOrWhiteSpace(entry.LoanerEnglishName))
            {
                continue;
            }

            if (!rows.TryGetValue(key, out var sourceRows))
            {
                sourceRows = [];
                rows[key] = sourceRows;
            }

            if (sourceRows.All(existing => !existing.LoanerEnglishName.Equals(entry.LoanerEnglishName, StringComparison.OrdinalIgnoreCase)))
            {
                sourceRows.Add(entry);
            }
        }

        return rows.ToDictionary(
            pair => pair.Key,
            pair => (IReadOnlyList<ShipLoanerMatrixEntry>)pair.Value
                .OrderBy(entry => entry.LoanerEnglishName, StringComparer.OrdinalIgnoreCase)
                .ToArray(),
            StringComparer.OrdinalIgnoreCase);
    }

    private static IEnumerable<string> BuildLoanerLookupCandidates(string loanerEnglishName)
    {
        var cleaned = Clean(loanerEnglishName);
        if (string.IsNullOrWhiteSpace(cleaned))
        {
            yield break;
        }

        yield return cleaned;

        if (LoanerAliases.TryGetValue(cleaned, out var alias))
        {
            yield return alias;
        }

        var stripped = StripManufacturerPrefix(cleaned);
        if (!stripped.Equals(cleaned, StringComparison.OrdinalIgnoreCase))
        {
            yield return stripped;

            if (LoanerAliases.TryGetValue(stripped, out var strippedAlias))
            {
                yield return strippedAlias;
            }
        }

        var withoutStarlifter = StarlifterSuffixRegex().Replace(stripped, "").Trim();
        if (!withoutStarlifter.Equals(stripped, StringComparison.OrdinalIgnoreCase))
        {
            yield return withoutStarlifter;
        }
    }

    private static string StripManufacturerPrefix(string value)
    {
        foreach (var prefix in ManufacturerPrefixes.OrderByDescending(prefix => prefix.Length))
        {
            if (value.StartsWith(prefix + " ", StringComparison.OrdinalIgnoreCase))
            {
                return value[(prefix.Length + 1)..].Trim();
            }
        }

        return value;
    }

    private static string NormalizeKey(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return "";
        }

        return NameKeySeparatorRegex()
            .Replace(value.Trim().ToLowerInvariant(), " ")
            .Trim();
    }

    private static string Clean(string? value)
    {
        return Regex.Replace(value ?? "", @"\s+", " ").Trim();
    }

    [GeneratedRegex(@"[^a-z0-9]+", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex NameKeySeparatorRegex();

    [GeneratedRegex(@"\s+Starlifter$", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex StarlifterSuffixRegex();
}
