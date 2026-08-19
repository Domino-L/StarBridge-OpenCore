using System.Collections.ObjectModel;
using System.IO;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace StarBridge.Desktop;

public sealed record LocationCatalogMatch(
    string CanonicalCode,
    string? ScmLocationCode,
    string Kind,
    string NameZh,
    string NameEn,
    bool IsDynamic,
    bool Persistent,
    string? ParentCode = null,
    string? ExternalGuid = null,
    bool HiddenInStarMap = false,
    string? NameZhSource = null,
    string? ScmMatchMethod = null,
    string? RuntimeAliasSource = null);

public sealed record LocationCatalogMetadata(
    int SchemaVersion,
    DateTimeOffset? GeneratedAtUtc,
    string? GameBuild,
    string? ScmCatalogVersion,
    int EntryCount,
    int AliasCount,
    int QuantumAliasCount,
    int ObjectContainerAliasCount,
    int DynamicPatternCount,
    int ScmLinkedEntryCount,
    int ExcludedEntryCount);

internal sealed class LocationCatalogIndex
{
    internal const int SupportedSchemaVersion = 1;
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);
    private static readonly TimeSpan PatternTimeout = TimeSpan.FromMilliseconds(100);
    private readonly IReadOnlyDictionary<string, LocationCatalogMatch> _canonical;
    private readonly IReadOnlyDictionary<string, LocationCatalogMatch> _lookup;
    private readonly DynamicLocationPattern[] _dynamicPatterns;
    private readonly string _optionalQuantumPrefix;
    private readonly Regex _instanceSuffixPattern;

    private LocationCatalogIndex(
        IReadOnlyDictionary<string, LocationCatalogMatch> canonical,
        IReadOnlyDictionary<string, LocationCatalogMatch> lookup,
        DynamicLocationPattern[] dynamicPatterns,
        LocationCatalogMetadata metadata,
        string optionalQuantumPrefix,
        Regex instanceSuffixPattern,
        bool isLoaded,
        string? loadError)
    {
        _canonical = canonical;
        _lookup = lookup;
        _dynamicPatterns = dynamicPatterns;
        Metadata = metadata;
        _optionalQuantumPrefix = optionalQuantumPrefix;
        _instanceSuffixPattern = instanceSuffixPattern;
        IsLoaded = isLoaded;
        LoadError = loadError;
    }

    internal bool IsLoaded { get; }
    internal string? LoadError { get; }
    internal IReadOnlyDictionary<string, LocationCatalogMatch> Lookup => _lookup;
    internal LocationCatalogMetadata Metadata { get; }

    internal static LocationCatalogIndex Load(string path)
    {
        try
        {
            if (!File.Exists(path))
            {
                return Empty($"Location catalog is missing: {Path.GetFileName(path)}");
            }

            using var stream = File.OpenRead(path);
            var document = JsonSerializer.Deserialize<LocationCatalogDocument>(stream, JsonOptions)
                ?? throw new InvalidDataException("Location catalog is empty.");
            if (document.SchemaVersion != SupportedSchemaVersion)
            {
                throw new InvalidDataException(
                    $"Unsupported location catalog schema version {document.SchemaVersion}.");
            }

            var normalization = document.Normalization
                ?? throw new InvalidDataException("Location catalog normalization settings are missing.");
            if (!string.Equals(normalization.Comparison, "ordinal-ignore-case", StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidDataException(
                    $"Unsupported location comparison mode '{normalization.Comparison}'.");
            }

            var optionalQuantumPrefix = Required(
                normalization.OptionalQuantumPrefix,
                "normalization.optionalQuantumPrefix");
            var instanceSuffixPattern = new Regex(
                Required(normalization.InstanceSuffixPattern, "normalization.instanceSuffixPattern"),
                RegexOptions.CultureInvariant,
                PatternTimeout);

            if ((document.UnresolvedAliases?.Length ?? 0) != 0)
            {
                throw new InvalidDataException("Location catalog contains unresolved aliases.");
            }

            if ((document.SkippedXml?.Length ?? 0) != 0)
            {
                throw new InvalidDataException("Location catalog contains skipped XML records.");
            }

            var entries = document.Entries ?? [];
            if (entries.Length == 0)
            {
                throw new InvalidDataException("Location catalog contains no entries.");
            }

            var canonical = new Dictionary<string, LocationCatalogMatch>(StringComparer.OrdinalIgnoreCase);
            foreach (var entry in entries)
            {
                var code = Required(entry.CanonicalCode, "canonicalCode");
                var nameZh = Required(entry.NameZh, $"{code}.nameZh");
                var nameEn = Required(entry.NameEn, $"{code}.nameEn");
                if (entry.NeedsChineseReview || !ContainsCjk(nameZh))
                {
                    throw new InvalidDataException($"Location catalog entry '{code}' has unreviewed Chinese text.");
                }

                if (!canonical.TryAdd(
                        code,
                        new LocationCatalogMatch(
                            code,
                            NormalizeOptional(entry.ScmLocationCode),
                            NormalizeOptional(entry.Kind) ?? "location",
                            nameZh,
                            nameEn,
                            IsDynamic: false,
                            Persistent: true,
                            NormalizeOptional(entry.ParentCode),
                            NormalizeOptional(entry.ExternalGuid),
                            entry.HiddenInStarMap,
                            NormalizeOptional(entry.NameZhSource),
                            NormalizeOptional(entry.ScmMatchMethod))))
                {
                    throw new InvalidDataException($"Duplicate canonical location code '{code}'.");
                }
            }

            var lookup = new Dictionary<string, LocationCatalogMatch>(canonical, StringComparer.OrdinalIgnoreCase);
            foreach (var alias in document.Aliases ?? [])
            {
                var code = Required(alias.Code, "alias.code");
                var canonicalCode = Required(alias.CanonicalCode, $"{code}.canonicalCode");
                var aliasKind = Required(alias.Kind, $"{code}.kind");
                if (!aliasKind.Equals("quantum-target", StringComparison.OrdinalIgnoreCase) &&
                    !aliasKind.Equals("object-container", StringComparison.OrdinalIgnoreCase))
                {
                    throw new InvalidDataException(
                        $"Location alias '{code}' has unsupported kind '{aliasKind}'.");
                }

                if (!canonical.TryGetValue(canonicalCode, out var target))
                {
                    throw new InvalidDataException(
                        $"Location alias '{code}' targets missing canonical code '{canonicalCode}'.");
                }

                var nameZh = Required(alias.NameZh, $"{code}.nameZh");
                var nameEn = Required(alias.NameEn, $"{code}.nameEn");
                if (alias.NeedsChineseReview || !ContainsCjk(nameZh))
                {
                    throw new InvalidDataException($"Location alias '{code}' has no Chinese display text.");
                }

                var match = target with
                {
                    ScmLocationCode = NormalizeOptional(alias.ScmLocationCode) ?? target.ScmLocationCode,
                    Kind = aliasKind,
                    NameZh = nameZh,
                    NameEn = nameEn,
                    NameZhSource = NormalizeOptional(alias.NameZhSource) ?? target.NameZhSource,
                    RuntimeAliasSource = NormalizeOptional(alias.Source)
                };
                AddAlias(lookup, code, match);
                var normalizedCode = NormalizeOptional(alias.NormalizedCode);
                if (normalizedCode is not null)
                {
                    AddAlias(lookup, normalizedCode, match);
                }
            }

            var dynamicPatterns = (document.DynamicPatterns ?? [])
                .Select(pattern =>
                {
                    var expression = Required(pattern.Pattern, "dynamicPatterns.pattern");
                    var nameZh = Required(pattern.NameZh, $"{expression}.nameZh");
                    var nameEn = Required(pattern.NameEn, $"{expression}.nameEn");
                    return new DynamicLocationPattern(
                        new Regex(
                            expression,
                            RegexOptions.CultureInvariant | RegexOptions.IgnoreCase,
                            PatternTimeout),
                        NormalizeOptional(pattern.Kind) ?? "dynamic-location",
                        nameZh,
                        nameEn,
                        pattern.Persistent);
                })
                .ToArray();

            var excludedCodes = (document.ExcludedEntries ?? [])
                .Select(entry => NormalizeOptional(entry.CanonicalCode))
                .Where(code => code is not null)
                .Select(code => code!)
                .ToHashSet(StringComparer.OrdinalIgnoreCase);
            var exposedExcluded = canonical.Keys.FirstOrDefault(excludedCodes.Contains);
            if (exposedExcluded is not null)
            {
                throw new InvalidDataException(
                    $"Excluded location definition '{exposedExcluded}' is exposed as a canonical entry.");
            }

            ValidateStatistics(document.Statistics, entries, document.Aliases ?? [], excludedCodes.Count);
            ValidateHierarchy(canonical);

            DateTimeOffset? generatedAtUtc = DateTimeOffset.TryParse(document.GeneratedAtUtc, out var generatedAt)
                ? generatedAt
                : null;
            var metadata = new LocationCatalogMetadata(
                document.SchemaVersion,
                generatedAtUtc,
                NormalizeOptional(document.GameBuild),
                NormalizeOptional(document.ScmCatalogVersion),
                entries.Length,
                document.Aliases?.Length ?? 0,
                (document.Aliases ?? []).Count(alias =>
                    string.Equals(alias.Kind, "quantum-target", StringComparison.OrdinalIgnoreCase)),
                (document.Aliases ?? []).Count(alias =>
                    string.Equals(alias.Kind, "object-container", StringComparison.OrdinalIgnoreCase)),
                dynamicPatterns.Length,
                entries.Count(entry => !string.IsNullOrWhiteSpace(entry.ScmLocationCode)),
                excludedCodes.Count);

            return new LocationCatalogIndex(
                new ReadOnlyDictionary<string, LocationCatalogMatch>(canonical),
                new ReadOnlyDictionary<string, LocationCatalogMatch>(lookup),
                dynamicPatterns,
                metadata,
                optionalQuantumPrefix,
                instanceSuffixPattern,
                isLoaded: true,
                loadError: null);
        }
        catch (Exception exception) when (exception is IOException or
                                          UnauthorizedAccessException or
                                          JsonException or
                                          InvalidDataException or
                                          ArgumentException)
        {
            return Empty(exception.Message);
        }
    }

    internal bool TryResolve(string code, out LocationCatalogMatch match)
    {
        var normalized = NormalizeCode(code);
        if (_lookup.TryGetValue(normalized, out match!))
        {
            return true;
        }

        if (normalized.StartsWith(_optionalQuantumPrefix, StringComparison.OrdinalIgnoreCase) &&
            _lookup.TryGetValue(normalized[_optionalQuantumPrefix.Length..], out var unprefixedMatch) &&
            IsQuantumAlias(unprefixedMatch))
        {
            match = unprefixedMatch;
            return true;
        }

        if (!normalized.StartsWith(_optionalQuantumPrefix, StringComparison.OrdinalIgnoreCase) &&
            _lookup.TryGetValue($"{_optionalQuantumPrefix}{normalized}", out var prefixedMatch) &&
            IsQuantumAlias(prefixedMatch))
        {
            match = prefixedMatch;
            return true;
        }

        foreach (var pattern in _dynamicPatterns)
        {
            bool matches;
            try
            {
                matches = pattern.Pattern.IsMatch(normalized);
            }
            catch (RegexMatchTimeoutException)
            {
                continue;
            }

            if (!matches)
            {
                continue;
            }

            match = new LocationCatalogMatch(
                normalized,
                null,
                pattern.Kind,
                pattern.NameZh,
                pattern.NameEn,
                IsDynamic: true,
                pattern.Persistent);
            return true;
        }

        match = null!;
        return false;
    }

    internal string NormalizeCode(string? code)
    {
        if (string.IsNullOrWhiteSpace(code))
        {
            return "Unknown";
        }

        string normalized;
        try
        {
            normalized = _instanceSuffixPattern.Replace(code.Trim(), "").Trim();
        }
        catch (RegexMatchTimeoutException)
        {
            normalized = code.Trim();
        }
        return string.IsNullOrWhiteSpace(normalized) ? "Unknown" : normalized;
    }

    internal IReadOnlyList<LocationCatalogMatch> GetHierarchy(string code)
    {
        if (!TryResolve(code, out var leaf) || leaf.IsDynamic)
        {
            return [];
        }

        var hierarchy = new List<LocationCatalogMatch> { leaf };
        var visited = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { leaf.CanonicalCode };
        var parentCode = leaf.ParentCode;
        while (!string.IsNullOrWhiteSpace(parentCode) &&
               visited.Add(parentCode) &&
               _canonical.TryGetValue(parentCode, out var parent))
        {
            hierarchy.Add(parent);
            parentCode = parent.ParentCode;
        }

        hierarchy.Reverse();
        return hierarchy;
    }

    private static void AddAlias(
        IDictionary<string, LocationCatalogMatch> lookup,
        string code,
        LocationCatalogMatch match)
    {
        if (lookup.TryGetValue(code, out var existing))
        {
            if (!existing.CanonicalCode.Equals(match.CanonicalCode, StringComparison.OrdinalIgnoreCase) ||
                !existing.NameZh.Equals(match.NameZh, StringComparison.Ordinal) ||
                !existing.NameEn.Equals(match.NameEn, StringComparison.Ordinal))
            {
                throw new InvalidDataException($"Conflicting location alias '{code}'.");
            }

            return;
        }

        lookup[code] = match;
    }

    private static LocationCatalogIndex Empty(string error) =>
        new(
            new ReadOnlyDictionary<string, LocationCatalogMatch>(
                new Dictionary<string, LocationCatalogMatch>(StringComparer.OrdinalIgnoreCase)),
            new ReadOnlyDictionary<string, LocationCatalogMatch>(
                new Dictionary<string, LocationCatalogMatch>(StringComparer.OrdinalIgnoreCase)),
            [],
            new LocationCatalogMetadata(SupportedSchemaVersion, null, null, null, 0, 0, 0, 0, 0, 0, 0),
            "LOC_",
            new Regex(@"\s*\[\d+\]\s*$", RegexOptions.CultureInvariant, PatternTimeout),
            isLoaded: false,
            loadError: error);

    private static void ValidateStatistics(
        LocationCatalogStatisticsContract? statistics,
        LocationCatalogEntryContract[] entries,
        LocationCatalogAliasContract[] aliases,
        int excludedCount)
    {
        if (statistics is null)
        {
            throw new InvalidDataException("Location catalog statistics are missing.");
        }

        var quantumAliasCount = aliases.Count(alias =>
            string.Equals(alias.Kind, "quantum-target", StringComparison.OrdinalIgnoreCase));
        var objectContainerAliasCount = aliases.Count(alias =>
            string.Equals(alias.Kind, "object-container", StringComparison.OrdinalIgnoreCase));
        var checks = new List<(string Name, int Expected, int Actual)>
        {
            ("entries", statistics.Entries, entries.Length),
            ("quantumAliases", statistics.QuantumAliases, quantumAliasCount),
            ("reviewedChineseEntries", statistics.ReviewedChineseEntries, entries.Count(entry => !entry.NeedsChineseReview)),
            ("chineseReviewEntries", statistics.ChineseReviewEntries, entries.Count(entry => entry.NeedsChineseReview)),
            ("scmLinkedEntries", statistics.ScmLinkedEntries, entries.Count(entry => !string.IsNullOrWhiteSpace(entry.ScmLocationCode))),
            ("unresolvedQuantumAliases", statistics.UnresolvedQuantumAliases, 0),
            ("skippedXmlRecords", statistics.SkippedXmlRecords, 0),
            ("excludedDefinitionEntries", statistics.ExcludedDefinitionEntries, excludedCount)
        };
        if (statistics.RuntimeAliases is not null)
        {
            checks.Add(("runtimeAliases", statistics.RuntimeAliases.Value, aliases.Length));
        }

        if (statistics.OocAliases is not null)
        {
            checks.Add(("oocAliases", statistics.OocAliases.Value, objectContainerAliasCount));
        }

        var mismatch = checks.FirstOrDefault(check => check.Expected != check.Actual);
        if (mismatch.Name is not null)
        {
            throw new InvalidDataException(
                $"Location catalog statistic '{mismatch.Name}' is {mismatch.Expected}, expected {mismatch.Actual}.");
        }
    }

    private static void ValidateHierarchy(IReadOnlyDictionary<string, LocationCatalogMatch> canonical)
    {
        foreach (var entry in canonical.Values)
        {
            var visited = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { entry.CanonicalCode };
            var parentCode = entry.ParentCode;
            while (!string.IsNullOrWhiteSpace(parentCode) && canonical.TryGetValue(parentCode, out var parent))
            {
                if (!visited.Add(parent.CanonicalCode))
                {
                    throw new InvalidDataException(
                        $"Location catalog hierarchy contains a cycle at '{parent.CanonicalCode}'.");
                }

                parentCode = parent.ParentCode;
            }
        }
    }

    private static string Required(string? value, string field)
    {
        var normalized = NormalizeOptional(value);
        return normalized ?? throw new InvalidDataException($"Location catalog field '{field}' is required.");
    }

    private static string? NormalizeOptional(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim();

    private static bool IsQuantumAlias(LocationCatalogMatch match) =>
        match.Kind.Equals("quantum-target", StringComparison.OrdinalIgnoreCase);

    private static bool ContainsCjk(string value) =>
        value.Any(character => character is >= '\u4e00' and <= '\u9fff');

    private sealed record DynamicLocationPattern(
        Regex Pattern,
        string Kind,
        string NameZh,
        string NameEn,
        bool Persistent);

    private sealed record LocationCatalogDocument(
        int SchemaVersion,
        string? GeneratedAtUtc,
        string? GameBuild,
        string? ScmCatalogVersion,
        LocationCatalogNormalizationContract? Normalization,
        DynamicLocationPatternContract[]? DynamicPatterns,
        LocationCatalogStatisticsContract? Statistics,
        LocationCatalogEntryContract[]? Entries,
        LocationCatalogAliasContract[]? Aliases,
        JsonElement[]? UnresolvedAliases,
        JsonElement[]? SkippedXml,
        LocationCatalogExcludedEntryContract[]? ExcludedEntries);

    private sealed record LocationCatalogNormalizationContract(
        string? Comparison,
        string? OptionalQuantumPrefix,
        string? InstanceSuffixPattern);

    private sealed record LocationCatalogStatisticsContract(
        int Entries,
        int? RuntimeAliases,
        int QuantumAliases,
        int? OocAliases,
        int ReviewedChineseEntries,
        int ChineseReviewEntries,
        int ScmLinkedEntries,
        int UnresolvedQuantumAliases,
        int SkippedXmlRecords,
        int ExcludedDefinitionEntries);

    private sealed record DynamicLocationPatternContract(
        string? Pattern,
        string? Kind,
        string? NameZh,
        string? NameEn,
        bool Persistent);

    private sealed record LocationCatalogEntryContract(
        string? CanonicalCode,
        string? ScmLocationCode,
        string? Kind,
        string? NameZh,
        string? NameEn,
        bool NeedsChineseReview,
        string? ParentCode,
        string? ExternalGuid,
        bool HiddenInStarMap,
        string? NameZhSource,
        string? ScmMatchMethod);

    private sealed record LocationCatalogAliasContract(
        string? Code,
        string? NormalizedCode,
        string? CanonicalCode,
        string? ScmLocationCode,
        string? Kind,
        string? NameZh,
        string? NameEn,
        string? NameZhSource,
        bool NeedsChineseReview,
        string? Source);

    private sealed record LocationCatalogExcludedEntryContract(string? CanonicalCode);
}
