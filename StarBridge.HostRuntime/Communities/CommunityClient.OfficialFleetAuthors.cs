using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.HostRuntime.OfficialFleet;
using StarBridge.HostRuntime.PartyRooms;

namespace StarBridge.HostRuntime.Communities;

internal sealed partial class CommunityClient
{
    private sealed record OfficialAuthorObservation(string State, string? Callsign = null, string? AvatarVersion = null,
        string? IdentityVersion = null, DateTimeOffset? Observed = null, DateTimeOffset? Until = null, string? Avatar = null)
    {
        internal bool Current(DateTimeOffset now) => State == "visible" && Observed is { } observed && Until is { } until &&
            observed <= now.AddSeconds(1) && until > observed && until <= observed.AddSeconds(5) && now < until;
    }
    private sealed record OfficialObservedChat(string Reference, ChatTarget Address, bool Found);
    private sealed record OfficialAuthorRead(JsonElement Page, IReadOnlyDictionary<string, OfficialAuthorObservation> Identities, OfficialObservedChat[]? ChatUpdates = null, bool RefreshRequired = false);
    private static bool OfficialAuthorOptIn(JsonElement body, Target target, string observedKey, bool renewal = false, bool preview = false)
    {
        if (!body.TryGetProperty("authorIdentitySchemaVersion", out var version) && !renewal)
        {
            if (body.TryGetProperty(observedKey, out _)) throw Invalid(); return false;
        }
        // Chat's emergency downgrade must not suppress an independently advertised preview.
        var supported = target.AuthorIdentitySchemaVersion == 1 || preview && target.PreviewAuthorsAvailable;
        if ((!renewal && (version.ValueKind != JsonValueKind.Number || version.GetInt32() != 1)) || !target.OfficialFleet || !supported ||
            !body.TryGetProperty(observedKey, out var refs) || refs.ValueKind != JsonValueKind.Array) throw Invalid();
        var maximum = preview ? 8 : observedKey == "observeMessageRefs" ? 50 : 21;
        var values = refs.EnumerateArray().Select(row => row.GetString() ?? "").ToArray();
        if (values.Length > maximum || values.Any(value => !LowerHex(value, 32)) || values.Distinct(StringComparer.Ordinal).Count() != values.Length) throw Invalid();
        return true;
    }
    private static bool TryAuthorRefresh(JsonElement root, out bool refresh)
    {
        refresh = true;
        if (root.ValueKind != JsonValueKind.Object) return false;
        var names = root.EnumerateObject().Select(row => row.Name).ToArray();
        if (names.Length != names.Distinct(StringComparer.Ordinal).Count() || !root.TryGetProperty("authorRefreshRequired", out var value) ||
            value.ValueKind is not (JsonValueKind.True or JsonValueKind.False)) return false;
        refresh = value.GetBoolean(); return true;
    }
    private static bool OfficialBid(string value) => value.Length == 71 && value.StartsWith("scm-v1:", StringComparison.Ordinal) && LowerHex(value[7..], 64);
    private static bool AuthorKeys(JsonElement value, string[] required, string[]? optional = null)
    {
        if (value.ValueKind != JsonValueKind.Object) return false;
        var names = value.EnumerateObject().Select(p => p.Name).ToArray();
        return names.Length == names.Distinct(StringComparer.Ordinal).Count() && required.All(names.Contains) &&
            names.All(name => required.Contains(name) || (optional?.Contains(name) ?? false));
    }
    private static DateTimeOffset AuthorUtc(JsonElement row, string name) => OfficialFleetMemberIdentityObservation.Utc(row.GetProperty(name));
    private static string AuthorHash(string text) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(text))).ToLowerInvariant();
    private IReadOnlyDictionary<string, OfficialAuthorObservation> AuthorIdentities(JsonElement root, HashSet<string> expected, bool detail = false,
        Privacy.OfficialChatAuthorReadObservation? diagnostic = null, bool preserveLapsedVisible = false)
    {
        var neutral = expected.ToDictionary(id => id, _ => new OfficialAuthorObservation("unavailable"), StringComparer.Ordinal);
        try
        {
            var rows = Rows(root, "identities", 100);
            if (rows.Length != expected.Count) throw Invalid();
            var result = new Dictionary<string, OfficialAuthorObservation>(StringComparer.Ordinal);
            foreach (var row in rows)
            {
                var id = Text(row, "businessSubjectId", 71); var state = Text(row, "state", 16);
                if (!expected.Contains(id) || result.ContainsKey(id)) throw Invalid();
                if (state is "hidden" or "unavailable")
                {
                    if (!AuthorKeys(row, ["businessSubjectId", "state"])) throw Invalid();
                    result[id] = new(state); continue;
                }
                if (state != "visible" || !AuthorKeys(row, ["businessSubjectId", "state", "callsign", "hasAvatar", "identityVersion", "identityObservedAtUtc", "identityValidUntilUtc"], detail ? ["avatarVersion", "avatarImageData"] : ["avatarVersion"])) throw Invalid();
                var callsign = Text(row, "callsign", 128); if (string.IsNullOrWhiteSpace(callsign) || callsign != callsign.Trim()) throw Invalid();
                var hasAvatar = row.GetProperty("hasAvatar").GetBoolean(); var avatarVersion = Optional(row, "avatarVersion", 64);
                var identityVersion = Text(row, "identityVersion", 64);
                if (!LowerHex(identityVersion, 64) || hasAvatar != (avatarVersion is not null) || avatarVersion is not null && !LowerHex(avatarVersion, 64) ||
                    identityVersion != AuthorHash("StarBridge.OfficialFleet.CommunicationAuthor.v1\n" + JsonSerializer.Serialize(new[] { callsign, avatarVersion }, ChatJson))) throw Invalid();
                var observed = AuthorUtc(row, "identityObservedAtUtc"); var until = AuthorUtc(row, "identityValidUntilUtc");
                if (until <= observed || until > observed.AddSeconds(5)) throw Invalid();
                var avatar = detail ? Optional(row, "avatarImageData", 4096) : null;
                if (detail && (hasAvatar != (avatar is not null) || avatar is not null && (RoomAvatarProjection.Normalize(avatar, 3 * 1024) != avatar || AuthorHash(avatar) != avatarVersion))) throw Invalid();
                var observation = new OfficialAuthorObservation(state, callsign, avatarVersion, identityVersion, observed, until, avatar);
                var now = _targetClock.GetUtcNow(); var current = observation.Current(now);
                result[id] = current || preserveLapsedVisible ? observation : new("unavailable");
                diagnostic?.Visible(observed, until, now, current);
            }
            return result;
        }
        catch (Exception error) when (error is JsonException or InvalidOperationException or KeyNotFoundException or FormatException or OverflowException or StarBridge.HostRuntime.Account.AccountBridgeHostException) { diagnostic?.ParseFailed(); return neutral; }
    }
    private void ApplyChatAuthor(JsonObject item, OfficialAuthorObservation? author, bool preserveLapsedVisible = false)
    {
        // Display observation only. Current remains the sole validity decision for proof consumers.
        var visible = author?.Current(_targetClock.GetUtcNow()) == true || preserveLapsedVisible && author?.State == "visible";
        item["senderCallsign"] = visible ? author!.Callsign : ""; item["senderGameId"] = ""; item["senderRoleTitle"] = ""; item["senderRoleColor"] = "#9DAAB3";
        item["hasAvatar"] = visible && author!.AvatarVersion is not null; item["avatarVersion"] = visible ? author!.AvatarVersion : null;
        item["authorIdentityState"] = visible ? "visible" : author?.State == "hidden" ? "hidden" : "unavailable";
        item["authorIdentityVersion"] = visible ? author!.IdentityVersion : null;
        item["identityObservedAtUtc"] = visible ? JsonValue.Create(author!.Observed) : null;
        item["identityValidUntilUtc"] = visible ? JsonValue.Create(author!.Until) : null;
    }
    private object CompleteOfficialChatAuthors(object result, OfficialAuthorRead read, IEnumerable<(string Reference, string SenderId)> addresses, Action current, CancellationToken token, long operationStarted, string targetRef, bool preview = false)
    {
        var senders = addresses.ToDictionary(row => row.Reference, row => row.SenderId, StringComparer.Ordinal);
        token.ThrowIfCancellationRequested(); current();
        foreach (var observed in read.ChatUpdates ?? []) if (observed.Found)
                _chatTargets.TryUpdate(observed.Reference, observed.Address with
                {
                    Expires = _targetClock.GetUtcNow().AddMinutes(5),
                    SenderRef = MemberReferenceFor("account:" + observed.Address.SenderId, observed.Address.Code, observed.Address.Scope, create: false)
                        ?? observed.Address.SenderRef
                }, observed.Address);
        return OfficialAuthorProjectionResult(read.Identities, retired =>
        {
            OfficialAuthorObservation? Author(string id) => retired.Contains(id) ? null : read.Identities.GetValueOrDefault(id);
            var node = JsonSerializer.SerializeToNode(result, ChatJson)!.AsObject();
            foreach (var message in node["messages"]!.AsArray())
            {
                var item = message!.AsObject(); ApplyChatAuthor(item, Author(senders[item["messageRef"]!.GetValue<string>()]), preserveLapsedVisible: !preview);
            }
            var updates = new JsonArray(); var refresh = read.RefreshRequired || retired.Count > 0;
            foreach (var observed in read.ChatUpdates ?? [])
            {
                var senderRef = MemberReferenceFor("account:" + observed.Address.SenderId, observed.Address.Code, observed.Address.Scope, create: false)
                    ?? observed.Address.SenderRef;
                if (senderRef is null) { refresh = true; continue; }
                var item = new JsonObject { ["messageRef"] = observed.Reference, ["senderRef"] = senderRef, ["sequence"] = observed.Address.Sequence, ["recordState"] = observed.Found ? "found" : "notRetained" };
                ApplyChatAuthor(item, observed.Found ? Author(observed.Address.SenderId) : null, preserveLapsedVisible: !preview);
                item.Remove("senderGameId"); item.Remove("senderRoleTitle"); item.Remove("senderRoleColor"); updates.Add(item); if (!observed.Found) refresh = true;
            }
            if (JsonSerializer.SerializeToUtf8Bytes(updates, ChatJson).Length > 64 * 1024) throw Invalid();
            node["authorUpdates"] = updates; node["authorRefreshRequired"] = refresh; node["authorIdentitySchemaVersion"] = 1; return node;
        }, current, token, operationStarted, targetRef, preview, preserveLapsedVisible: !preview);
    }
}
