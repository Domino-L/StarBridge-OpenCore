using System.Net;
using System.Text.Json;
using System.Text.RegularExpressions;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.OfficialFleet;

internal sealed record OfficialFleetProfile(string? BannerUrl, int? MemberCount,
    string? RsiDescription, string? ScmSupplementalDescription, string? PrimaryFocusLabel,
    string? SecondaryFocusLabel, string[] LanguageLabels, string? OrganizationModelLabel,
    string? CommitmentLabel, string? RoleplayLabel, string? ArchetypeLabel, string[] Tags,
    // Public RSI logo (RSI's default logo when none was uploaded); the client
    // uses it only when the membership summary carries no logo.
    string? LogoUrl = null,
    // Dimmed full-page background; fall back to a solid color when absent.
    string? BackgroundUrl = null);

/// Existing public SCM facts; no complete RSI roster, StarBridge presence or permissions.
internal static class OfficialFleetReadModel
{
    internal static OfficialFleetProfile Profile(JsonElement data, string sourceRef, string sid)
    {
        if (sourceRef != $"officialFleet:{OfficialFleetPublicId.Read(data.GetProperty("id"))}" ||
            !string.Equals(Text(data, "sid", 128), sid, StringComparison.OrdinalIgnoreCase) ||
            data.TryGetProperty("unavailable", out var unavailable) && unavailable.ValueKind == JsonValueKind.True)
            throw Invalid();
        var count = data.TryGetProperty("membersCount", out var members) && members.ValueKind != JsonValueKind.Null
            ? members.GetInt32() : (int?)null;
        if (count is < 0) throw Invalid();
        var description = Text(data, "description", 32768);
        if (description is not null) {
            description = Regex.Replace(description, @"<(script|style)\b[^>]*>.*?</\1\s*>", "",
                RegexOptions.IgnoreCase | RegexOptions.Singleline, TimeSpan.FromMilliseconds(100));
            description = WebUtility.HtmlDecode(Regex.Replace(description, "<[^>]*>", " ",
                RegexOptions.None, TimeSpan.FromMilliseconds(100))).Trim();
        }
        var language = Text(data, "language", 256);
        var tags = data.TryGetProperty("tags", out var rows) && rows.ValueKind == JsonValueKind.Array
            ? rows.EnumerateArray().Take(21).Select(row => Text(row, "name", 128))
                .Where(name => name is not null).Cast<string>().ToArray() : [];
        if (tags.Length > 20) throw Invalid();
        return new(Url(data, "banner"), count, description, Text(data, "customDescription", 8192),
            Text(data, "primaryFocus", 256), Text(data, "secondaryFocus", 256),
            language is null ? [] : [language], Text(data, "model", 256), Text(data, "commitment", 256),
            Text(data, "roleplay", 256), Text(data, "archetype", 256), tags, Url(data, "image"), Url(data, "backgroundImage"));
    }

    internal static object Members(JsonElement data, string sourceRef, int pageNumber, int pageSize,
        string search, Func<long, string> reference, IReadOnlyDictionary<long, OfficialFleetMemberIdentity>? identities = null,
        long? selfMemberId = null)
    {
        var total = data.GetProperty("total").GetInt32();
        var list = data.GetProperty("list");
        if (total < 0 || list.ValueKind != JsonValueKind.Array || list.GetArrayLength() > pageSize ||
            list.GetArrayLength() > total) throw Invalid();
        var ids = new HashSet<long>();
        var rows = list.EnumerateArray().Select(row => {
            var id = OfficialFleetPublicId.Read(row.GetProperty("userId"));
            if (id <= 0 || !ids.Add(id)) throw Invalid();
            var identity = identities is null ? null : identities.GetValueOrDefault(id) ?? throw OfficialFleetMemberIdentity.Invalid();
            var linked = identity?.State == "visible";
            var restricted = identity?.State == "restricted";
            return new {
                memberRef = reference(id), callsign = linked ? identity!.Callsign : restricted ? "—" : Text(row, "nickname", 256) ?? "—", gameId = "",
                avatarUrl = linked || restricted ? null : AvatarUrl(row), officialRankName = Text(row, "organizationRank", 128),
                identityState = linked ? "starBridge" : restricted ? "restricted" : "scm",
                avatarImageData = linked ? identity!.AvatarImageData : null,
                profileTargetRef = linked ? reference(id) : null,
                // Only a Java-verified visible link to the viewer's own business subject.
                isSelf = linked && id == selfMemberId ? true : (bool?)null,
                officialRankValue = (int?)null, presence = "unknown", starBridgeConnected = linked ? true : (bool?)null,
                server = new { state = "unknown" }, ship = new { state = "unknown" }, location = new { state = "unknown" },
                arrivalPending = false
            };
        }).ToArray();
        return new { schemaVersion = 1, sourceRef, search, pageNumber, pageSize, filter = "all", members = rows,
            totalCount = total, totalPages = Math.Max(1, (int)Math.Ceiling(total / (double)pageSize)),
            onlineCount = (int?)null, inGameCount = (int?)null, coverage = "scmRegisteredMembers",
            supportedFilters = new[] { "all" } };
    }

    private static string? AvatarUrl(JsonElement data)
    {
        if (!data.TryGetProperty("avatar", out var value) || value.ValueKind == JsonValueKind.Null) return null;
        if (value.ValueKind != JsonValueKind.String) throw Invalid();
        return RsiAvatarImage.Validate(value.GetString())?.AbsoluteUri;
    }

    private static string? Url(JsonElement data, string key)
    {
        var value = Text(data, key, 2048);
        return value is not null && Uri.TryCreate(value, UriKind.Absolute, out var uri) &&
            uri.Scheme == Uri.UriSchemeHttps && uri.UserInfo.Length == 0 && uri.Host.Length > 0 ? value : null;
    }

    private static string? Text(JsonElement data, string key, int limit)
    {
        if (!data.TryGetProperty(key, out var value) || value.ValueKind == JsonValueKind.Null) return null;
        if (value.ValueKind != JsonValueKind.String || value.GetString()!.Length > limit) throw Invalid();
        return string.IsNullOrWhiteSpace(value.GetString()) ? null : value.GetString()!.Trim();
    }

    internal static AccountBridgeHostException Invalid() => new(AccountBridgeStableErrors.OfficialFleetDataInvalid);
}
