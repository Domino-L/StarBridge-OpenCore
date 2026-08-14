using System.Collections.ObjectModel;
using System.Globalization;
using System.IO;
using System.Net;
using System.Text;
using System.Text.RegularExpressions;
using StarBridge.Core.ShipMedia;

namespace StarBridge.Desktop;

public sealed record OwnedShipRecord(
    string Code,
    string DisplayName,
    string Source,
    DateTimeOffset ImportedAt,
    DateTimeOffset AddedToDatabaseAt = default,
    DateTimeOffset SyncedAt = default,
    string? InstanceId = null,
    string? CustomImageMediaId = null,
    double CustomImageCropFocusX = 0.5,
    double CustomImageCropFocusY = 0.5,
    double CustomImageCropZoom = 1.0)
{
    public ShipImageCropFrame CustomImageCropFrame => ShipImageCropFrame.Normalize(
        CustomImageCropFocusX,
        CustomImageCropFocusY,
        CustomImageCropZoom);

    public string ValueDisplay => ShipCatalog.Find(Code, DisplayName)?.PriceDisplay ?? "";

    public string ImportedAtDisplay => ImportedAt == DateTimeOffset.MinValue
        ? ""
        : ImportedAt.ToLocalTime().ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);

    public string SyncedAtDisplay => SyncedAt == default || SyncedAt == DateTimeOffset.MinValue
        ? ""
        : SyncedAt.ToLocalTime().ToString("yyyy-MM-dd HH:mm", CultureInfo.InvariantCulture);
}

public sealed record HangarImportResult(
    IReadOnlyList<OwnedShipRecord> Ships,
    int MatchedCodes,
    int MatchedNames)
{
    public IReadOnlyList<HangarShipImageCandidate> ImageCandidates { get; init; } = [];
}

public sealed record HangarShipImageCandidate(
    string Code,
    string ImageUrl);

public sealed record HangarShipCandidate(
    string Title,
    string ManufacturerCode,
    string? CreatedAtText = null,
    string? SourceTitle = null,
    string? InstanceId = null,
    string? ImageUrl = null);

public static partial class HangarShipImporter
{
    private static readonly IReadOnlyDictionary<string, string> OfficialNameAliases =
        new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["A1 Spirit"] = "CRUS_A1_Spirit",
            ["Ares Ion"] = "CRUS_Starfighter_Ion",
            ["Asgard"] = "ANVL_Asgard",
            ["Basher"] = "GLSN_Basher",
            ["Cyclone MT"] = "TMBL_Cyclone_MT",
            ["Dragonfly Black"] = "DRAK_Dragonfly_Black",
            ["Eclipse"] = "AEGS_Eclipse",
            ["F7C-M Super Hornet Mk II"] = "ANVL_Hornet_F7CM_Mk2",
            ["F8C Lightning"] = "ANVL_Lightning_F8C",
            ["Fury MX"] = "Misc_Fury_Miru",
            ["Gladius"] = "AEGS_Gladius",
            ["Hammerhead"] = "AEGS_Hammerhead",
            ["Hercules Starlifter A2"] = "CRUS_Starlifter_A2",
            ["Hurricane"] = "ANVL_Hurricane",
            ["Idris-P Frigate"] = "AEGS_Idris_P",
            ["Ironclad"] = "DRAK_Ironclad",
            ["Ironclad Assault"] = "DRAK_Ironclad_Assault",
            ["M80"] = "ORIG_M80",
            ["Nox"] = "XIAN_Nox",
            ["Origin M80"] = "ORIG_M80",
            ["Railen"] = "XIAN_Railen",
            ["Retaliator"] = "AEGS_Retaliator",
            ["Sabre Firebird"] = "AEGS_Sabre_Firebird",
            ["Scorpius Antares"] = "RSI_Scorpius_Antares",
            ["Starlancer TAC"] = "MISC_Starlancer_TAC",
            ["起源 M80"] = "ORIG_M80",
            ["Starfarer Gemini"] = "MISC_Starfarer_Gemini",
            ["Terrapin"] = "ANVL_Terrapin",
            ["Vanguard Harbinger"] = "AEGS_Vanguard_Harbinger"
        };

    public static HangarImportResult ImportOfficialHangarSnapshot(string content, string language)
    {
        var decoded = WebUtility.HtmlDecode(content);
        var normalizedContent = WhitespaceRegex().Replace(decoded, " ");
        return ImportOfficialShipCandidates(ExtractShipItemCandidates(normalizedContent), language);
    }

    public static HangarImportResult ImportOfficialShipTitles(IEnumerable<string> titles, string language)
    {
        return ImportOfficialShipCandidates(
            titles.Select(title => new HangarShipCandidate(title, "")),
            language);
    }

    public static HangarImportResult ImportOfficialShipCandidates(IEnumerable<HangarShipCandidate> candidates, string language)
    {
        var found = new Dictionary<string, OwnedShipRecord>(StringComparer.OrdinalIgnoreCase);
        var fallbackOccurrences = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        var imageCandidates = new Dictionary<string, HangarShipImageCandidate>(StringComparer.OrdinalIgnoreCase);
        var matchedTitles = 0;
        var matchedAliases = 0;

        foreach (var candidate in candidates)
        {
            matchedTitles++;
            if (!TryResolveOfficialShipCandidate(candidate, out var code))
            {
                continue;
            }

            matchedAliases++;
            var normalizedCode = ShipNameLocalizer.NormalizeCode(code);
            if (Uri.TryCreate(candidate.ImageUrl?.Trim(), UriKind.Absolute, out var imageUri) &&
                imageUri.Scheme.Equals(Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase))
            {
                imageCandidates.TryAdd(
                    normalizedCode,
                    new HangarShipImageCandidate(normalizedCode, imageUri.AbsoluteUri));
            }

            var instanceId = NormalizeInstanceId(candidate.InstanceId);
            if (string.IsNullOrWhiteSpace(instanceId))
            {
                var fingerprint = BuildCandidateFingerprint(candidate, normalizedCode);
                fallbackOccurrences.TryGetValue(fingerprint, out var occurrence);
                fallbackOccurrences[fingerprint] = occurrence + 1;
                instanceId = $"legacy:{fingerprint}:{occurrence + 1}";
            }

            AddShip(
                found,
                normalizedCode,
                candidate.Title,
                candidate.SourceTitle,
                language,
                ParseOfficialHangarDate(candidate.CreatedAtText) ?? DateTimeOffset.Now,
                instanceId);
        }

        return new HangarImportResult(
            found.Values.OrderBy(ship => ship.DisplayName, StringComparer.CurrentCultureIgnoreCase).ToArray(),
            matchedTitles,
            matchedAliases)
        {
            ImageCandidates = imageCandidates.Values.ToArray()
        };
    }

    public static string ResolveShipDisplayName(string? code, string language)
    {
        var normalizedCode = ShipNameLocalizer.NormalizeCode(code);
        var localizedName = ShipNameLocalizer.DisplayName(normalizedCode, language);
        if (!localizedName.Equals(normalizedCode, StringComparison.OrdinalIgnoreCase))
        {
            return localizedName;
        }

        return ShipCatalog.Find(normalizedCode, null)?.DisplayName(language) ?? localizedName;
    }

    public static string ResolveShipSourceDisplay(string? sourceTitle, string? shipTitleOrCode, string language)
    {
        var standalone = language.Equals("zh", StringComparison.OrdinalIgnoreCase)
            ? "单船"
            : "Standalone";
        var source = NormalizeTitle(WebUtility.HtmlDecode(sourceTitle ?? ""));
        var shipTitle = NormalizeTitle(WebUtility.HtmlDecode(shipTitleOrCode ?? ""));

        if (string.IsNullOrWhiteSpace(source) ||
            IsStandaloneSource(source, shipTitle))
        {
            return standalone;
        }

        return source;
    }

    private static IEnumerable<HangarShipCandidate> ExtractShipItemCandidates(string content)
    {
        foreach (Match match in ShipKindRegex().Matches(content))
        {
            var prefixStart = Math.Max(0, match.Index - 6000);
            var prefix = content[prefixStart..match.Index];
            var titleMatches = TitleRegex().Matches(prefix);
            if (titleMatches.Count == 0)
            {
                continue;
            }

            var title = StripTags(titleMatches[^1].Groups["title"].Value);
            if (!string.IsNullOrWhiteSpace(title))
            {
                var suffixEnd = Math.Min(content.Length, match.Index + 1200);
                var suffix = content[match.Index..suffixEnd];
                var linerMatch = LinerRegex().Match(suffix);
                var liner = linerMatch.Success
                    ? StripTags(linerMatch.Groups["liner"].Value)
                    : "";

                yield return new HangarShipCandidate(title, ExtractManufacturerCode(liner), ExtractCreatedAtText(prefix));
            }
        }
    }

    private static bool TryResolveOfficialShipCandidate(HangarShipCandidate candidate, out string code)
    {
        var title = NormalizeTitle(candidate.Title);
        if (OfficialNameAliases.TryGetValue(title, out code!))
        {
            return true;
        }

        foreach (var alias in OfficialNameAliases)
        {
            if (title.Contains(alias.Key, StringComparison.OrdinalIgnoreCase))
            {
                code = alias.Value;
                return true;
            }
        }

        if (TryResolveFromKnownCodes(title, candidate.ManufacturerCode, out code))
        {
            return true;
        }

        code = "";
        return false;
    }

    private static bool TryResolveFromKnownCodes(string title, string manufacturerCode, out string code)
    {
        var titleTokens = MakeSearchTokens(title);
        if (titleTokens.Count == 0)
        {
            code = "";
            return false;
        }

        var titleKey = MakeSearchKey(title);
        var bestCode = "";
        var bestScore = int.MinValue;

        foreach (var knownCode in ShipNameLocalizer.KnownShipCodes)
        {
            var normalizedCode = ShipNameLocalizer.NormalizeCode(knownCode);
            if (normalizedCode.Equals("Unknown", StringComparison.OrdinalIgnoreCase) ||
                !IsManufacturerCompatible(normalizedCode, manufacturerCode))
            {
                continue;
            }

            var codeWithoutManufacturer = RemoveManufacturerPrefix(normalizedCode);
            var codeTokens = MakeSearchTokens(codeWithoutManufacturer);
            if (codeTokens.Count == 0 || !codeTokens.All(titleTokens.Contains))
            {
                continue;
            }

            var codeKey = MakeSearchKey(codeWithoutManufacturer);
            var score = codeTokens.Count * 10;
            if (titleKey.Equals(codeKey, StringComparison.OrdinalIgnoreCase))
            {
                score += 1000;
            }
            else if (titleKey.Contains(codeKey, StringComparison.OrdinalIgnoreCase) ||
                     codeKey.Contains(titleKey, StringComparison.OrdinalIgnoreCase))
            {
                score += 300;
            }

            if (HasExactManufacturerPrefix(normalizedCode, manufacturerCode))
            {
                score += 50;
            }

            score -= normalizedCode.Length;
            if (score <= bestScore)
            {
                continue;
            }

            bestScore = score;
            bestCode = normalizedCode;
        }

        code = bestCode;
        return !string.IsNullOrWhiteSpace(code);
    }

    private static void AddShip(
        Dictionary<string, OwnedShipRecord> found,
        string code,
        string title,
        string? sourceTitle,
        string language,
        DateTimeOffset acquiredAt,
        string instanceId)
    {
        code = ShipNameLocalizer.NormalizeCode(code);
        var source = ResolveShipSourceDisplay(sourceTitle, title, language);
        var key = string.IsNullOrWhiteSpace(instanceId) ? code : instanceId;
        if (found.TryGetValue(key, out var existing))
        {
            if (acquiredAt < existing.ImportedAt)
            {
                found[key] = existing with { ImportedAt = acquiredAt, Source = source };
            }

            return;
        }

        found[key] = new OwnedShipRecord(
            code,
            ResolveShipDisplayName(code, language),
            source,
            acquiredAt,
            DateTimeOffset.UtcNow,
            default,
            instanceId);
    }

    private static string BuildCandidateFingerprint(HangarShipCandidate candidate, string code)
    {
        var raw = string.Join("|", code, candidate.Title, candidate.SourceTitle, candidate.CreatedAtText);
        var bytes = System.Security.Cryptography.SHA256.HashData(Encoding.UTF8.GetBytes(raw));
        return Convert.ToHexString(bytes.AsSpan(0, 10)).ToLowerInvariant();
    }

    private static string NormalizeInstanceId(string? value)
    {
        return string.IsNullOrWhiteSpace(value) ? "" : value.Trim();
    }

    private static bool IsStandaloneSource(string source, string shipTitle)
    {
        if (source.Contains("standalone", StringComparison.OrdinalIgnoreCase) ||
            source.Contains("single ship", StringComparison.OrdinalIgnoreCase) ||
            source.Contains("单船", StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }

        if (source.Contains("RSI", StringComparison.OrdinalIgnoreCase) &&
            (source.Contains("hangar", StringComparison.OrdinalIgnoreCase) ||
             source.Contains("机库", StringComparison.OrdinalIgnoreCase) ||
             source.Contains("å®˜", StringComparison.OrdinalIgnoreCase) ||
             source.Contains("æœº", StringComparison.OrdinalIgnoreCase)))
        {
            return true;
        }

        if (string.IsNullOrWhiteSpace(shipTitle))
        {
            return false;
        }

        return source.Equals(shipTitle, StringComparison.OrdinalIgnoreCase) ||
               MakeSearchKey(source).Equals(MakeSearchKey(shipTitle), StringComparison.OrdinalIgnoreCase);
    }

    private static string ExtractCreatedAtText(string prefix)
    {
        var matches = CreatedDateRegex().Matches(prefix);
        if (matches.Count == 0)
        {
            return "";
        }

        return StripTags(matches[^1].Groups["date"].Value);
    }

    private static DateTimeOffset? ParseOfficialHangarDate(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return null;
        }

        var dateText = CreatedLabelRegex()
            .Replace(StripTags(WebUtility.HtmlDecode(value)).Replace('\u00a0', ' '), "")
            .Trim();
        if (string.IsNullOrWhiteSpace(dateText))
        {
            return null;
        }

        var chineseDate = ChineseDateRegex().Match(dateText);
        if (chineseDate.Success &&
            int.TryParse(chineseDate.Groups["year"].Value, out var year) &&
            int.TryParse(chineseDate.Groups["month"].Value, out var month) &&
            int.TryParse(chineseDate.Groups["day"].Value, out var day))
        {
            return ToLocalOffset(new DateTime(year, month, day));
        }

        if (DateTimeOffset.TryParse(
                dateText,
                CultureInfo.InvariantCulture,
                DateTimeStyles.AllowWhiteSpaces,
                out var invariantOffset))
        {
            return invariantOffset;
        }

        if (DateTimeOffset.TryParse(
                dateText,
                CultureInfo.CurrentCulture,
                DateTimeStyles.AllowWhiteSpaces,
                out var localOffset))
        {
            return localOffset;
        }

        if (DateTime.TryParse(
                dateText,
                CultureInfo.InvariantCulture,
                DateTimeStyles.AllowWhiteSpaces | DateTimeStyles.AssumeLocal,
                out var invariantDate))
        {
            return ToLocalOffset(invariantDate);
        }

        if (DateTime.TryParse(
                dateText,
                CultureInfo.CurrentCulture,
                DateTimeStyles.AllowWhiteSpaces | DateTimeStyles.AssumeLocal,
                out var localDate))
        {
            return ToLocalOffset(localDate);
        }

        return null;
    }

    private static DateTimeOffset ToLocalOffset(DateTime value)
    {
        var localValue = value.Kind == DateTimeKind.Unspecified
            ? DateTime.SpecifyKind(value, DateTimeKind.Local)
            : value.ToLocalTime();
        return new DateTimeOffset(localValue);
    }

    private static string NormalizeTitle(string value)
    {
        return WhitespaceRegex()
            .Replace(value.Replace('‘', '\'').Replace('’', '\''), " ")
            .Trim();
    }

    private static string StripTags(string value)
    {
        return NormalizeTitle(TagRegex().Replace(value, ""));
    }

    private static string ExtractManufacturerCode(string value)
    {
        var match = ManufacturerCodeRegex().Match(value);
        return match.Success ? match.Groups["code"].Value.Trim().ToUpperInvariant() : "";
    }

    private static bool IsManufacturerCompatible(string shipCode, string manufacturerCode)
    {
        if (string.IsNullOrWhiteSpace(manufacturerCode))
        {
            return true;
        }

        return HasExactManufacturerPrefix(shipCode, manufacturerCode) ||
               manufacturerCode.Equals("MRAI", StringComparison.OrdinalIgnoreCase) &&
               shipCode.StartsWith("Misc_", StringComparison.OrdinalIgnoreCase) ||
               manufacturerCode.Equals("GAMA", StringComparison.OrdinalIgnoreCase) &&
               shipCode.StartsWith("XIAN_", StringComparison.OrdinalIgnoreCase);
    }

    private static bool HasExactManufacturerPrefix(string shipCode, string manufacturerCode)
    {
        if (string.IsNullOrWhiteSpace(manufacturerCode))
        {
            return false;
        }

        return shipCode.StartsWith($"{manufacturerCode}_", StringComparison.OrdinalIgnoreCase);
    }

    private static string RemoveManufacturerPrefix(string shipCode)
    {
        var separatorIndex = shipCode.IndexOf('_');
        return separatorIndex > 0 && separatorIndex < shipCode.Length - 1
            ? shipCode[(separatorIndex + 1)..]
            : shipCode;
    }

    private static HashSet<string> MakeSearchTokens(string value)
    {
        return SearchTokenSeparatorRegex()
            .Split(NormalizeSearchText(value))
            .Where(token => token.Length > 0)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
    }

    private static string MakeSearchKey(string value)
    {
        return SearchKeySeparatorRegex().Replace(NormalizeSearchText(value), "");
    }

    private static string NormalizeSearchText(string value)
    {
        var normalized = NormalizeTitle(value).ToLowerInvariant();
        normalized = MarkTwoRegex().Replace(normalized, "mk2");
        normalized = ShipVariantHyphenRegex().Replace(normalized, "${left}${right}");
        return normalized;
    }

    [GeneratedRegex(@"<div\s+class=""kind""[^>]*>\s*(Ship|飞船)\s*</div>", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex ShipKindRegex();

    [GeneratedRegex(@"<div\s+class=""title""[^>]*>\s*(?<title>.*?)\s*</div>", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex TitleRegex();

    [GeneratedRegex(@"<div\s+class=""liner""[^>]*>\s*(?<liner>.*?)\s*</div>", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex LinerRegex();

    [GeneratedRegex(@"<div\s+class=""date-col""[^>]*>\s*<label>\s*(?:Created|Acquired|创建|建立|入库|获得|获取)\s*:?\s*</label>\s*(?<date>.*?)\s*</div>", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex CreatedDateRegex();

    [GeneratedRegex(@"^\s*(?:Created|Acquired|创建|建立|入库|获得|获取)\s*:?\s*", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex CreatedLabelRegex();

    [GeneratedRegex(@"(?<year>\d{4})\s*年\s*(?<month>\d{1,2})\s*月\s*(?<day>\d{1,2})\s*日?", RegexOptions.CultureInvariant)]
    private static partial Regex ChineseDateRegex();

    [GeneratedRegex(@"\((?<code>[A-Z0-9]{3,5})\)", RegexOptions.CultureInvariant)]
    private static partial Regex ManufacturerCodeRegex();

    [GeneratedRegex(@"\b(?:mark|mk)\s*ii\b", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex MarkTwoRegex();

    [GeneratedRegex(@"(?<left>[a-z]+\d+[a-z]?)-(?<right>[a-z])", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex ShipVariantHyphenRegex();

    [GeneratedRegex(@"[^a-z0-9]+", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex SearchTokenSeparatorRegex();

    [GeneratedRegex(@"[^a-z0-9]+", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex SearchKeySeparatorRegex();

    [GeneratedRegex(@"<.*?>", RegexOptions.CultureInvariant)]
    private static partial Regex TagRegex();

    [GeneratedRegex(@"\s+", RegexOptions.CultureInvariant)]
    private static partial Regex WhitespaceRegex();
}

public static class ShipDatabaseStore
{
    public static ObservableCollection<OwnedShipRecord> Load(string ownerKey)
    {
        var ships = new ObservableCollection<OwnedShipRecord>();
        var path = GetPath(ownerKey);
        if (!File.Exists(path))
        {
            return ships;
        }

        foreach (var line in File.ReadLines(path, Encoding.UTF8))
        {
            var parts = line.Split('\t');
            if (parts.Length < 4 ||
                string.IsNullOrWhiteSpace(parts[0]) ||
                string.IsNullOrWhiteSpace(parts[1]))
            {
                continue;
            }

            var importedAt = DateTimeOffset.TryParse(parts[3], out var parsedImportedAt)
                ? parsedImportedAt
                : DateTimeOffset.MinValue;
            var addedToDatabaseAt = parts.Length > 4 &&
                                    DateTimeOffset.TryParse(parts[4], out var parsedAddedToDatabaseAt)
                ? parsedAddedToDatabaseAt
                : importedAt;
            var syncedAt = parts.Length > 5
                ? DateTimeOffset.TryParse(parts[5], out var parsedSyncedAt)
                    ? parsedSyncedAt
                    : default
                : addedToDatabaseAt;

            ships.Add(new OwnedShipRecord(
                parts[0],
                parts[1],
                parts[2],
                importedAt,
                addedToDatabaseAt,
                syncedAt,
                parts.Length > 6 && !string.IsNullOrWhiteSpace(parts[6]) ? parts[6] : null,
                parts.Length > 7 && !string.IsNullOrWhiteSpace(parts[7]) ? parts[7] : null,
                ParseCropValue(parts, 8, 0.5),
                ParseCropValue(parts, 9, 0.5),
                ParseCropValue(parts, 10, 1.0)));
        }

        return ships;
    }

    public static void Save(string ownerKey, IEnumerable<OwnedShipRecord> ships)
    {
        Directory.CreateDirectory(DesktopAppConfig.ConfigDirectory);
        File.WriteAllLines(
            GetPath(ownerKey),
            ships.Select(ship => string.Join(
                '\t',
                Clean(ship.Code),
                Clean(ship.DisplayName),
                Clean(ship.Source),
                ship.ImportedAt.ToString("O"),
                (ship.AddedToDatabaseAt == default ? ship.ImportedAt : ship.AddedToDatabaseAt).ToString("O"),
                ship.SyncedAt == default ? "" : ship.SyncedAt.ToString("O"),
                Clean(ship.InstanceId ?? ""),
                Clean(ship.CustomImageMediaId ?? ""),
                ship.CustomImageCropFrame.FocusX.ToString("R", CultureInfo.InvariantCulture),
                ship.CustomImageCropFrame.FocusY.ToString("R", CultureInfo.InvariantCulture),
                ship.CustomImageCropFrame.Zoom.ToString("R", CultureInfo.InvariantCulture))),
            Encoding.UTF8);
    }

    private static double ParseCropValue(string[] parts, int index, double fallback) =>
        parts.Length > index &&
        double.TryParse(parts[index], NumberStyles.Float, CultureInfo.InvariantCulture, out var value)
            ? value
            : fallback;

    private static string GetPath(string ownerKey)
    {
        return Path.Combine(DesktopAppConfig.ConfigDirectory, $"ships-{Sanitize(ownerKey)}.database");
    }

    private static string Sanitize(string value)
    {
        var sanitized = new string(value.Select(ch => char.IsLetterOrDigit(ch) ? ch : '_').ToArray());
        return string.IsNullOrWhiteSpace(sanitized) ? "local" : sanitized;
    }

    private static string Clean(string value)
    {
        return value.Replace('\t', ' ').Replace("\r", " ").Replace("\n", " ").Trim();
    }
}
