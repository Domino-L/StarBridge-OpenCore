using System.Net;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace StarBridge.HostRuntime.Marketplace;

/// <summary>Bounded projections for SCM contracts (0.7.2 G1). Names are masked as in the hall; SCM
/// member ids and avatars stay in the Host. A member can be messaged through an opaque chat
/// reference. Rich-text descriptions arrive as plain text.</summary>
internal static partial class MarketplaceContracts
{
    internal static readonly string[] Types = ["BOUNTY", "SERVICE", "COOPERATION"];

    [GeneratedRegex("<[^>]*>")] private static partial Regex Tags();
    [GeneratedRegex("[ \\t]+")] private static partial Regex Spaces();
    [GeneratedRegex("\\n{3,}")] private static partial Regex Blank();

    private static object? Value(JsonElement row, string key, int max = 2000)
    {
        if (row.ValueKind != JsonValueKind.Object || !row.TryGetProperty(key, out var v)) return null;
        return v.ValueKind switch
        {
            JsonValueKind.String => v.GetString() is { } text ? text.Length > max ? text[..max] : text : null,
            JsonValueKind.Number => v.Clone(),
            JsonValueKind.True or JsonValueKind.False => v.GetBoolean(),
            _ => null,
        };
    }

    internal static string? PlainText(string? html, int max)
    {
        if (string.IsNullOrWhiteSpace(html)) return null;
        var text = html.Replace("<br", "\n<br", StringComparison.OrdinalIgnoreCase)
            .Replace("</p>", "\n</p>", StringComparison.OrdinalIgnoreCase);
        text = WebUtility.HtmlDecode(Tags().Replace(text, ""));
        text = Blank().Replace(Spaces().Replace(text.Replace("\r", ""), " "), "\n\n").Trim();
        return text.Length > max ? text[..max] : text;
    }

    internal static object Contract(JsonElement row, Func<long, string?> chat) => new
    {
        id = Value(row, "id"),
        number = Value(row, "contractNumber", 60),
        type = Value(row, "contractType", 20),
        creator = MarketplaceRecords.Mask(Value(row, "creatorNickname", 100) as string),
        creatorChat = MarketplaceChat.Id(row, "creatorId") is var creator and > 0 ? chat(creator) : null,
        creatorReputation = Value(row, "creatorReputation"),
        creatorOnline = Value(row, "creatorStatus") is JsonElement s && s.TryGetInt32(out var status) ? status is 1 or 2 : (bool?)null,
        fleet = Value(row, "creatorType") is JsonElement t && t.TryGetInt32(out var kind) && kind == 1,
        fleetName = Value(row, "organizationName", 100),
        fleetSid = Value(row, "organizationSid", 50),
        title = Value(row, "title", 100),
        description = PlainText(Value(row, "description", 8000) as string, 2000),
        location = Value(row, "locationDescription", 500),
        rewardType = Value(row, "rewardType", 10),
        rewardUec = Value(row, "rewardUec"),
        rewardNote = Value(row, "rewardDescription", 500),
        slots = Value(row, "maxParticipants"),
        taken = Value(row, "currentParticipants"),
        applications = Value(row, "applyCount"),
        minReputation = Value(row, "minReputation"),
        requirements = Value(row, "otherRequirements", 1000),
        status = Value(row, "status"),
        expireTime = Value(row, "expireTime", 40),
        startTime = Value(row, "startTime", 40),
        completeTime = Value(row, "completeTime", 40),
        createTime = Value(row, "createTime", 40),
        mine = Value(row, "isCreator") is true,
        applied = Value(row, "isApplied") is true,
        myStatus = Value(row, "participantStatus"),
        eligible = Value(row, "meetReputationRequirement"),
    };

    internal static object Participant(JsonElement row, Func<long, string?> chat) => new
    {
        id = Value(row, "id"),
        name = MarketplaceRecords.Mask(Value(row, "userNickname", 100) as string),
        chat = MarketplaceChat.Id(row, "userId") is var user and > 0 ? chat(user) : null,
        reputation = Value(row, "userReputation"),
        fleetName = Value(row, "organizationName", 100),
        message = Value(row, "applyMessage", 1000),
        ships = row.ValueKind == JsonValueKind.Object && row.TryGetProperty("applyShipNames", out var ships) && ships.ValueKind == JsonValueKind.Array
            ? ships.EnumerateArray().Where(s => s.ValueKind == JsonValueKind.String).Take(20).Select(s => s.GetString()!.Length > 80 ? s.GetString()![..80] : s.GetString()).ToArray()
            : [],
        status = Value(row, "status"),
        rejoined = Value(row, "rejoined") is true,
        applyTime = Value(row, "applyTime", 40),
        acceptTime = Value(row, "acceptTime", 40),
        completeTime = Value(row, "completeTime", 40),
        rejectReason = Value(row, "rejectReason", 500),
        breachReason = Value(row, "breachReason", 500),
        work = Value(row, "workDescription", 1000),
        reviewedByCreator = Value(row, "isReviewedByCreator") is true,
        reviewedByParticipant = Value(row, "isReviewedByParticipant") is true,
    };

    internal static object Milestone(JsonElement row) => new
    {
        id = Value(row, "id"),
        order = Value(row, "milestoneOrder"),
        title = Value(row, "title", 200),
        description = Value(row, "description", 1000),
        reward = Value(row, "rewardAmount"),
        status = Value(row, "status"),
        completeTime = Value(row, "completeTime", 40),
        confirmTime = Value(row, "confirmTime", 40),
    };
}
