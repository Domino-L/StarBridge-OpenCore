using System.Globalization;
using System.Text.Json;
#if STARBRIDGE_HOST_RUNTIME
// Shared pure filter implementation compiled into each authorized read adapter.
// Host supplies only the already-authorized public fields, not server models.
using NetworkFleetSnapshot = StarBridge.HostRuntime.Communities.WpfS2DirectoryFilterSnapshot;
using NetworkFleetActivityWindowSnapshot = StarBridge.HostRuntime.Communities.WpfS2DirectoryActivityWindow;
using CommunityDirectoryRow = StarBridge.HostRuntime.Communities.CommunityView;
using RelayGeneralPolicy = StarBridge.HostRuntime.Communities.WpfS2DirectoryFilterSnapshot;
#endif

// Transitional WPF discovery semantics. Match only the viewer-visible projection.
internal sealed record CommunityDirectoryFilters(Dictionary<string, string[]> Groups,
    string Sort, string Language, string[] Tags, bool AllTags, bool SameZone, int Offset)
{
    internal static CommunityDirectoryFilters Parse(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return new([], "recommended", "", [], false, false, 0);
        if (json.Length > 4096) throw new FormatException();
        using var document = JsonDocument.Parse(json);
        var root = document.RootElement;
        if (root.ValueKind != JsonValueKind.Object || root.EnumerateObject().Select(p => p.Name).Distinct().Count() != root.EnumerateObject().Count())
            throw new FormatException();
        string[] List(string key, string[]? allowed = null)
        {
            if (!root.TryGetProperty(key, out var value)) return [];
            var values = value.EnumerateArray().Select(x => x.GetString() ?? "").ToArray();
            if (values.Length > 20 || values.Any(x => x.Length is 0 or > 128 || x.Any(char.IsControl) || allowed is not null && !allowed.Contains(x)))
                throw new FormatException();
            return values.Distinct().ToArray();
        }
        string Text(string key, string fallback) => root.TryGetProperty(key, out var value) ? value.GetString() ?? fallback : fallback;
        bool Flag(string key) => root.TryGetProperty(key, out var value) && value.GetBoolean();
        var groups = new Dictionary<string, string[]>
        {
            ["join"] = List("join", ["direct", "application", "inviteOnly"]),
            ["status"] = List("status", ["recruiting", "pending"]),
            ["scale"] = List("scale", ["small", "medium", "large", "veryLarge"]),
            ["targets"] = List("targets", ["所有玩家", "新手友好", "战斗玩家", "工业玩家", "贸易与货运", "医疗与支援"]),
            ["cadence"] = List("cadence", ["休闲", "固定开黑", "周末行动", "高频组织", "大型行动前通知"]),
            ["period"] = List("period", ["night", "morning", "afternoon", "evening"]),
            ["days"] = List("days", ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]),
            ["ships"] = List("ships", ["small", "medium", "large", "veryLarge"]),
            ["roles"] = List("roles", ["combat", "industrial", "transport", "exploration", "support", "utility"]),
            ["systems"] = List("systems", ["Stanton", "Pyro", "Nyx"]),
        };
        if (root.EnumerateObject().Any(p => !groups.ContainsKey(p.Name) && p.Name is not ("sort" or "language" or "tags" or "allTags" or "sameZone" or "offset")))
            throw new FormatException();
        var sort = Text("sort", "recommended");
        var language = Text("language", "");
        var tags = List("tags");
        var offset = root.TryGetProperty("offset", out var off) ? off.GetInt32() : 0;
        if (sort is not ("recommended" or "name" or "members" or "recent") || language.Length > 128 ||
            language.Any(char.IsControl) || tags.Length > 5 || offset is < -840 or > 840) throw new FormatException();
        return new(groups, sort, language, tags, Flag("allTags"), Flag("sameZone"), offset);
    }
    private string[] Group(string key) => Groups.GetValueOrDefault(key) ?? [];
    private bool Match(string key, string? value) => Group(key).Length == 0 ||
        Group(key).Contains(value ?? "", StringComparer.OrdinalIgnoreCase);
    internal static string Scale(int count, bool ships = false) => count <= 10 ? "small" :
        count <= (ships ? 30 : 50) ? "medium" : count < (ships ? 100 : 300) ? "large" : "veryLarge";
    internal bool Matches(NetworkFleetSnapshot visible, CommunityDirectoryRow row)
    {
        if (!Match("join", row.JoinMode) || !Match("scale", row.MemberScale) ||
            Group("status").Contains("recruiting") && !row.Recruiting ||
            Group("status").Contains("pending") && row.Relationship != "pending" ||
            Group("targets").Length > 0 && (!row.Recruiting || !Match("targets", row.RecruitingTarget)) ||
            !Match("cadence", visible.PublicShowActivityTime ? visible.ActivityCadence : null) ||
            Language.Length > 0 && !row.Language.Contains(Language, StringComparison.OrdinalIgnoreCase)) return false;
        if (Group("systems").Length > 0 && !Group("systems").Any(x => row.Systems.Contains(x, StringComparer.OrdinalIgnoreCase))) return false;
        if (Tags.Length > 0 && !(AllTags ? Tags.All(TagMatch) : Tags.Any(TagMatch))) return false;
        bool TagMatch(string tag) => row.Tags.Contains(tag, StringComparison.OrdinalIgnoreCase);
        if (Group("ships").Length > 0 &&
            (RelayGeneralPolicy.NormalizeFleetPublicShipScaleMode(visible.PublicShipScaleMode) == "Hidden" ||
             visible.PublicShipCount <= 0 || !Match("ships", Scale(visible.PublicShipCount, true)))) return false;
        if (Group("roles").Length > 0)
        {
            if (RelayGeneralPolicy.NormalizeFleetPublicShipScaleMode(visible.PublicShipScaleMode) != "TypeSummary") return false;
            var roles = (visible.PublicShipTypeSummary ?? "").Split(';', StringSplitOptions.RemoveEmptyEntries)
                .Select(x => x.Split('=', 2, StringSplitOptions.TrimEntries))
                .Where(x => x.Length == 2 && int.TryParse(x[1], out var n) && n > 0).Select(x => x[0]);
            if (!Group("roles").Any(x => roles.Contains(x, StringComparer.OrdinalIgnoreCase))) return false;
        }
        if (SameZone || Group("period").Length > 0 || Group("days").Length > 0)
        {
            if (!visible.PublicShowActivityTime) return false;
            if (SameZone || Group("period").Length > 0)
            {
                try
                {
                    var zone = TimeZoneInfo.FindSystemTimeZoneById(visible.TimeZoneId ?? "");
                    if ((int)zone.GetUtcOffset(DateTimeOffset.UtcNow).TotalMinutes != Offset) return false;
                }
                catch (Exception e) when (e is TimeZoneNotFoundException or InvalidTimeZoneException or ArgumentException) { return false; }
            }
            var windows = visible.ActivityWindows ?? [];
            if (Group("days").Length > 0 && !windows.Any(w => (w.Days ?? []).Any(d => Group("days").Contains(d, StringComparer.OrdinalIgnoreCase)))) return false;
            if (Group("period").Length > 0 && !windows.Any(Overlaps)) return false;
        }
        return true;
    }
    private bool Overlaps(NetworkFleetActivityWindowSnapshot window)
    {
        if (!TimeSpan.TryParse(window.StartTime, CultureInfo.InvariantCulture, out var start) ||
            !TimeSpan.TryParse(window.EndTime, CultureInfo.InvariantCulture, out var end)) return false;
        var a = Math.Clamp((int)start.TotalMinutes, 0, 1439);
        var b = Math.Clamp((int)end.TotalMinutes, 0, 1440);
        if (a == b) return true;
        return Group("period").Any(period =>
        {
            var p = period switch { "morning" => 360, "afternoon" => 720, "evening" => 1080, _ => 0 };
            return window.EndsNextDay || b < a ? a < p + 360 || b > p : a < p + 360 && b > p;
        });
    }
    internal static int SearchScore(CommunityDirectoryRow row, string query)
    {
        if (query.Length == 0) return 1;
        if (row.Name.Equals(query, StringComparison.OrdinalIgnoreCase)) return 95;
        if (row.Name.StartsWith(query, StringComparison.OrdinalIgnoreCase)) return 70;
        if (row.Name.Contains(query, StringComparison.OrdinalIgnoreCase)) return 40;
        return new[] { row.Description, row.Tags, row.Language, row.ActiveTime, row.Recruiting ? row.RecruitingTarget : "" }
            .Any(x => x.Contains(query, StringComparison.OrdinalIgnoreCase)) ? 30 : 0;
    }
}
