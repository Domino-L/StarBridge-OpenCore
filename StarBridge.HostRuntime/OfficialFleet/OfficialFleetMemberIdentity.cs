using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.PartyRooms;

namespace StarBridge.HostRuntime.OfficialFleet;

// Java resolves registered ownership and viewer-scoped privacy. Raw IDs stay in
// Native Host; neither display names nor locally calculated hashes prove a link.
internal sealed record OfficialFleetMemberIdentity(long MemberId, string State,
    string? BusinessSubjectId = null, string? Callsign = null, string? AvatarImageData = null)
{
    internal const string Unavailable = "official_fleet.identity_unavailable";
    internal static AccountBridgeHostException Invalid() => new(Unavailable);

    internal static IReadOnlyDictionary<long, OfficialFleetMemberIdentity> Parse(
        JsonElement root, string sourceRef, IReadOnlyCollection<long> requested)
    {
        RequireProperties(root, ["schemaVersion", "sourceRef", "members"]);
        if (root.GetProperty("schemaVersion").GetInt32() != 1 ||
            root.GetProperty("sourceRef").GetString() != sourceRef ||
            root.GetProperty("members") is not { ValueKind: JsonValueKind.Array } rows ||
            rows.GetArrayLength() != requested.Count) throw Invalid();
        var expected = requested.ToHashSet();
        var result = new Dictionary<long, OfficialFleetMemberIdentity>();
        foreach (var row in rows.EnumerateArray())
        {
            RequireProperties(row, ["memberId", "state"], ["businessSubjectId", "callsign", "avatarImageData"]);
            var id = row.GetProperty("memberId").GetInt64();
            var state = row.GetProperty("state").GetString();
            if (!expected.Contains(id) || result.ContainsKey(id) || state is not ("unlinked" or "visible" or "restricted"))
                throw Invalid();
            var subject = OptionalString(row, "businessSubjectId");
            var callsign = OptionalString(row, "callsign");
            var avatar = OptionalString(row, "avatarImageData");
            if (state != "visible")
            {
                // Rejected identities never carry a hidden account identifier,
                // nickname or photo, including an empty/placeholder target.
                if (subject is not null || callsign is not null || avatar is not null) throw Invalid();
            }
            else
            {
                if (subject is not { Length: 71 } || !subject.StartsWith("scm-v1:", StringComparison.Ordinal) ||
                    subject.AsSpan(7).IndexOfAnyExcept("0123456789abcdef") >= 0 ||
                    callsign is not { Length: > 0 and <= 128 } || callsign != callsign.Trim() || callsign.Any(char.IsControl))
                    throw Invalid();
                if (avatar is not null && (avatar.Length > 4096 ||
                    RoomAvatarProjection.Normalize(avatar, 3 * 1024) != avatar)) throw Invalid();
            }
            result.Add(id, new(id, state!, subject, callsign, avatar));
        }
        return result;
    }

    private static string? OptionalString(JsonElement row, string key) =>
        row.TryGetProperty(key, out var value) && value.ValueKind != JsonValueKind.Null ? value.GetString() : null;

    private static void RequireProperties(JsonElement value, string[] required, string[]? optional = null)
    {
        if (value.ValueKind != JsonValueKind.Object) throw Invalid();
        var names = value.EnumerateObject().Select(p => p.Name).ToArray();
        if (names.Distinct(StringComparer.Ordinal).Count() != names.Length || required.Any(n => !names.Contains(n)) ||
            names.Any(n => !required.Contains(n) && optional?.Contains(n) != true)) throw Invalid();
    }
}
