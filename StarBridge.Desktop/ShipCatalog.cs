using System.IO;
using System.Text;
using System.Text.RegularExpressions;

namespace StarBridge.Desktop;

public sealed record ShipCatalogEntry(
    string Spec,
    string EnglishName,
    string ChineseName,
    string Role,
    string Status,
    string PriceUsd,
    string Source,
    string Notes,
    string HiddenTags = "",
    string ImagePath = "")
{
    public string PriceDisplay => string.IsNullOrWhiteSpace(PriceUsd) ? "未公布" : $"${PriceUsd}";

    public bool HasHiddenTag(string tag)
    {
        return HiddenTags
            .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Any(value => value.Equals(tag, StringComparison.OrdinalIgnoreCase));
    }

    public string DisplayName(string language)
    {
        return language.Equals("zh", StringComparison.OrdinalIgnoreCase) &&
               !string.IsNullOrWhiteSpace(ChineseName)
            ? ChineseName
            : EnglishName;
    }

    public string RoleDisplay(string language)
    {
        return language.Equals("zh", StringComparison.OrdinalIgnoreCase)
            ? ShipRoleLocalizer.DisplayName(Role)
            : Role;
    }
}

internal static class ShipRoleLocalizer
{
    private static readonly IReadOnlyDictionary<string, string> RoleNames = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
    {
        ["Attack"] = "攻击",
        ["Ambulance"] = "救护",
        ["Anti-Air"] = "防空",
        ["Anti-aircraft"] = "防空",
        ["Assault"] = "突击",
        ["Boarding"] = "登舰",
        ["Bomber"] = "轰炸",
        ["Bounty Hunting"] = "赏金猎人",
        ["Capital"] = "旗舰",
        ["Carrier"] = "航母",
        ["Cargo Loader"] = "货物装载",
        ["Combat"] = "战斗",
        ["Combat Support"] = "战斗支援",
        ["Command"] = "指挥",
        ["Competition"] = "竞赛",
        ["Construction"] = "建造",
        ["Corvette"] = "轻型主力舰",
        ["Courier"] = "快递",
        ["Data"] = "数据",
        ["Destroyer"] = "驱逐舰",
        ["Dropship"] = "登陆艇",
        ["Expedition"] = "远征",
        ["Explorer"] = "探索",
        ["Exploration"] = "探索",
        ["Fighter"] = "战斗机",
        ["Freight"] = "货运",
        ["Freighter"] = "货船",
        ["Frigate"] = "护卫舰",
        ["Generalist"] = "通用",
        ["Ground"] = "地面",
        ["Gun Ship"] = "炮艇",
        ["Gunship"] = "炮艇",
        ["Hauler"] = "运输",
        ["Heavy Construction"] = "重型建造",
        ["Heavy Fighter"] = "重型战斗机",
        ["Heavy Freight"] = "重型货运",
        ["Heavy Mining"] = "重型采矿",
        ["Heavy Refining"] = "重型精炼",
        ["Heavy Refuel"] = "重型加油",
        ["Heavy Repair"] = "重型维修",
        ["Heavy Salvage"] = "重型打捞",
        ["Industrial"] = "工业",
        ["Intelligence"] = "情报",
        ["Interception"] = "拦截",
        ["Interdiction"] = "拦截",
        ["Interdictor"] = "拦截",
        ["Light Carrier"] = "轻型航母",
        ["Light Fighter"] = "轻型战斗机",
        ["Light Freight"] = "轻型货运",
        ["Light Refueler"] = "轻型加油",
        ["Light Salvage"] = "轻型打捞",
        ["Light Science"] = "轻型科研",
        ["Luxury"] = "豪华",
        ["Luxury Transport"] = "豪华运输",
        ["Luxury Touring"] = "豪华观光",
        ["Medical"] = "医疗",
        ["Medium Cargo"] = "中型货运",
        ["Medium Data"] = "中型数据",
        ["Medium Fighter"] = "中型战斗机",
        ["Medium Freight"] = "中型货运",
        ["Medium Freighter"] = "中型货船",
        ["Medium Hauler"] = "中型运输",
        ["Medium Refuel"] = "中型加油",
        ["Medium Repair"] = "中型维修",
        ["Medium Salvage"] = "中型打捞",
        ["Military"] = "军用",
        ["Mine Layer"] = "布雷",
        ["Mining"] = "采矿",
        ["Modular"] = "模块化",
        ["Multi-role"] = "多用途",
        ["Passenger"] = "客运",
        ["Patrol"] = "巡逻",
        ["Pathfinder"] = "探路",
        ["Personal Transport"] = "个人交通",
        ["Prospecting"] = "勘探",
        ["Racing"] = "竞速",
        ["Recon"] = "侦察",
        ["Reconnaissance"] = "侦察",
        ["Recovery"] = "回收",
        ["Refuel"] = "加油",
        ["Refueling"] = "加油",
        ["Refinery"] = "精炼",
        ["Repair"] = "维修",
        ["Reporting"] = "报道",
        ["Research"] = "研究",
        ["Rescue"] = "救援",
        ["Salvage"] = "打捞",
        ["Scanning"] = "扫描",
        ["Science"] = "科研",
        ["Scout"] = "侦察",
        ["Snub"] = "舰载小艇",
        ["Snub Fighter"] = "舰载战斗机",
        ["Starter"] = "入门",
        ["Stealth"] = "隐身",
        ["Stealth Bomber"] = "隐身轰炸",
        ["Stealth Fighter"] = "隐身战斗机",
        ["Support"] = "支援",
        ["Touring"] = "观光",
        ["Transport"] = "运输",
        ["Transporter"] = "运输",
        ["Utility"] = "通用",
    };

    public static string DisplayName(string role)
    {
        if (string.IsNullOrWhiteSpace(role))
        {
            return "";
        }

        var parts = role
            .Split('/', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Select(TranslatePart)
            .Where(part => !string.IsNullOrWhiteSpace(part));

        return string.Join(" / ", parts);
    }

    private static string TranslatePart(string value)
    {
        if (RoleNames.TryGetValue(value, out var exact))
        {
            return exact;
        }

        var words = value.Split(' ', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        if (words.Length <= 1)
        {
            return value;
        }

        var translated = words
            .Select(word => RoleNames.TryGetValue(word, out var translatedWord) ? translatedWord : word)
            .ToArray();

        return string.Join("", translated);
    }
}

public static partial class ShipCatalog
{
    private static readonly Lazy<IReadOnlyList<ShipCatalogEntry>> EntriesCache = new(LoadEntries);
    private static readonly Lazy<IReadOnlyDictionary<string, ShipCatalogEntry>> NameIndexCache = new(BuildNameIndex);

    public static IReadOnlyList<ShipCatalogEntry> Entries => EntriesCache.Value;

    public static ShipCatalogEntry? Find(string? code, string? displayName)
    {
        foreach (var candidate in BuildLookupCandidates(code, displayName))
        {
            if (NameIndexCache.Value.TryGetValue(NormalizeNameKey(candidate), out var exactMatch))
            {
                return exactMatch;
            }
        }

        var codeTokens = MakeEnglishTokenSet(RemoveManufacturerPrefix(ShipNameLocalizer.NormalizeCode(code)));
        if (codeTokens.Count > 0)
        {
            var tokenMatch = Entries.FirstOrDefault(entry =>
            {
                var entryTokens = MakeEnglishTokenSet(entry.EnglishName);
                return entryTokens.Count > 0 && entryTokens.SetEquals(codeTokens);
            });

            if (tokenMatch is not null)
            {
                return tokenMatch;
            }
        }

        return null;
    }

    public static string ResolveImagePath(
        ShipCatalogEntry? catalog,
        string? code,
        string? displayName)
    {
        return !string.IsNullOrWhiteSpace(catalog?.ImagePath)
            ? catalog.ImagePath
            : ShipMediaManifestCatalog.FindImagePath(code, displayName) ?? "";
    }

    private static IEnumerable<string> BuildLookupCandidates(string? code, string? displayName)
    {
        if (!string.IsNullOrWhiteSpace(displayName))
        {
            yield return displayName;
        }

        if (!string.IsNullOrWhiteSpace(code))
        {
            var normalizedCode = ShipNameLocalizer.NormalizeCode(code);

            yield return code;
            yield return normalizedCode;
            yield return RemoveManufacturerPrefix(normalizedCode);
            yield return ShipNameLocalizer.DisplayName(normalizedCode, "zh");

            foreach (var alias in ShipNameLocalizer.GetNameAliases(normalizedCode))
            {
                yield return alias;
            }
        }
    }

    private static IReadOnlyDictionary<string, ShipCatalogEntry> BuildNameIndex()
    {
        var index = new Dictionary<string, ShipCatalogEntry>(StringComparer.OrdinalIgnoreCase);
        foreach (var entry in Entries)
        {
            AddNameIndex(index, entry.EnglishName, entry);
            AddNameIndex(index, entry.ChineseName, entry);

            var chineseParts = entry.ChineseName.Split(' ', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
            if (chineseParts.Length > 1)
            {
                AddNameIndex(index, string.Join(' ', chineseParts.Skip(1)), entry);
            }
        }

        return index;
    }

    private static void AddNameIndex(Dictionary<string, ShipCatalogEntry> index, string value, ShipCatalogEntry entry)
    {
        var key = NormalizeNameKey(value);
        if (!string.IsNullOrWhiteSpace(key) && !index.ContainsKey(key))
        {
            index[key] = entry;
        }
    }

    private static IReadOnlyList<ShipCatalogEntry> LoadEntries()
    {
        var path = Path.Combine(AppContext.BaseDirectory, "Data", "ship-catalog.tsv");
        if (!File.Exists(path))
        {
            return [];
        }

        var entries = new List<ShipCatalogEntry>();
        foreach (var line in File.ReadLines(path, Encoding.UTF8))
        {
            if (string.IsNullOrWhiteSpace(line) || line.StartsWith('#'))
            {
                continue;
            }

            var parts = line.Split('\t');
            if (parts.Length < 6 ||
                parts[0].Equals("规格", StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            entries.Add(new ShipCatalogEntry(
                Clean(parts.ElementAtOrDefault(0)),
                Clean(parts.ElementAtOrDefault(1)),
                Clean(parts.ElementAtOrDefault(2)),
                Clean(parts.ElementAtOrDefault(3)),
                NormalizeStatus(parts.ElementAtOrDefault(4)),
                Clean(parts.ElementAtOrDefault(5)),
                Clean(parts.ElementAtOrDefault(6)),
                Clean(parts.ElementAtOrDefault(7)),
                Clean(parts.ElementAtOrDefault(8)),
                Clean(parts.ElementAtOrDefault(9))));
        }

        return entries;
    }

    private static string NormalizeStatus(string? value)
    {
        var status = Clean(value);
        if (status.Contains("Flight Ready", StringComparison.OrdinalIgnoreCase) ||
            status.Contains("可飞", StringComparison.OrdinalIgnoreCase))
        {
            return "可飞";
        }

        if (status.Contains("Concept", StringComparison.OrdinalIgnoreCase) ||
            status.Contains("概念", StringComparison.OrdinalIgnoreCase))
        {
            return "概念";
        }

        return string.IsNullOrWhiteSpace(status) ? "概念" : status;
    }

    private static string RemoveManufacturerPrefix(string value)
    {
        var separatorIndex = value.IndexOf('_');
        return separatorIndex > 0 && separatorIndex < value.Length - 1
            ? value[(separatorIndex + 1)..]
            : value;
    }

    private static HashSet<string> MakeEnglishTokenSet(string value)
    {
        return EnglishTokenSeparatorRegex()
            .Split(value.ToLowerInvariant())
            .Where(token => token.Length > 0)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
    }

    private static string NormalizeNameKey(string? value)
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

    [GeneratedRegex(@"[^a-z0-9]+", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex EnglishTokenSeparatorRegex();
}
