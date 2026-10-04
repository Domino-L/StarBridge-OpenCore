using System.Text.Json;
using StarBridge.HostRuntime.Communities;
using StarBridge.HostRuntime.Overlay;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost : IOverlayCommunityReader, IOverlayCommunityChangeReader
{
    private long _workspaceRosterSequence;
    internal Action<BridgeAccountContext, long, long, DateTimeOffset, InformationOverlayCommunityContent>? CommunityRosterObserved { get; set; }
    internal Action<BridgeAccountContext, long, long, DateTimeOffset, IReadOnlyList<InformationOverlayCommunityContent>>? CommunityDirectoryObserved { get; set; }
    internal Action<BridgeAccountContext, long, long, string>? CommunityRosterRevoked { get; set; }
    async Task<OverlayActivityCursor> IOverlayCommunityChangeReader.WaitForChangesAsync(
        BridgeAccountContext owner, long generation, OverlayActivityCursor after, CancellationToken token)
    {
        if (generation != Generation) throw new BridgeStaleGenerationException(generation, Generation);
        var result = JsonSerializer.SerializeToElement(await WaitCommunityActivityAsync(owner,
            JsonSerializer.SerializeToElement(new { schemaVersion = 1, instance = after.Instance, version = after.Version }), token));
        if (generation != Generation) throw new BridgeStaleGenerationException(generation, Generation);
        return new(result.GetProperty("instance").GetString()!, result.GetProperty("version").GetInt64(),
            result.TryGetProperty("presenceEvents", out var supports) && supports.ValueKind == JsonValueKind.True);
    }
    async Task<IReadOnlyList<OverlayCommunityTarget>> IOverlayCommunityReader.ReadTargetsAsync(
        BridgeAccountContext owner, CancellationToken token)
    {
        var generation = Generation;
        var targets = new List<OverlayCommunityTarget>();
        var seen = new HashSet<string>(StringComparer.Ordinal);
        var cursors = new HashSet<string>(StringComparer.Ordinal);
        string? after = null;
        do
        {
            var page = (CommunityPage)await ReadCommunitiesCoreAsync(owner,
                JsonSerializer.SerializeToElement(new { schemaVersion = 1, view = "mine", query = "", after }), token,
                backgroundActivity: true, includeManagement: false);
            if (generation != Generation) throw new BridgeStaleGenerationException(generation, Generation);
            foreach (var row in page.Items.Where(x => x.Relationship is "member" or "owner"))
            {
                var target = _communities!.OverlayTarget(row.TargetRef, FriendScope(owner, generation));
                if (!seen.Add(target.Code)) throw new InvalidDataException("Duplicate organization source.");
                targets.Add(target);
            }
            after = page.Next;
            if (after is not null && (!cursors.Add(after) || cursors.Count >= 128))
                throw new InvalidDataException("Organization directory did not complete.");
        } while (after is not null);
        return targets;
    }

    Task<InformationOverlayCommunityContent> IOverlayCommunityReader.ReadContentAsync(
        BridgeAccountContext owner, OverlayCommunityTarget target, CancellationToken token) =>
        ReadOverlayCommunityContentAsync(owner, target, null, token);

    Task<InformationOverlayCommunityContent> IOverlayCommunityReader.ReadRosterAsync(
        BridgeAccountContext owner, OverlayCommunityTarget target, CancellationToken token) =>
        ReadOverlayCommunityContentAsync(owner, target, null, token, includeCommunication: false);

    Task<InformationOverlayCommunityContent> IOverlayCommunityReader.ReadContentAsync(
        BridgeAccountContext owner, OverlayCommunityTarget target,
        Action<InformationOverlayCommunityContent> rosterReady, CancellationToken token) =>
        ReadOverlayCommunityContentAsync(owner, target, rosterReady, token);

    private async Task<InformationOverlayCommunityContent> ReadOverlayCommunityContentAsync(
        BridgeAccountContext owner, OverlayCommunityTarget target,
        Action<InformationOverlayCommunityContent>? rosterReady, CancellationToken token, bool includeCommunication = true)
    {
        var generation = Generation;
        var members = new List<InformationOverlayCommunityMember>();
        var seen = new HashSet<string>(StringComparer.Ordinal);
        int? expectedTotal = null;
        var offset = 0;
        string? name = null;
        for (var pageIndex = 0; pageIndex < 128; pageIndex++)
        {
            InformationOverlayCommunityContent? completeRoster = null;
            var result = await ReadCommunitySurfaceAsync(owner,
                JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef = target.Reference, query = "", offset }), "workspace", token,
                backgroundActivity: true, includeManagement: false, rosterReady: value => completeRoster = value);
            if (generation != Generation) throw new BridgeStaleGenerationException(generation, Generation);
            var page = JsonSerializer.SerializeToElement(result);
            if (page.GetProperty("code").GetString() != target.Code)
                throw new InvalidDataException("Mismatched organization source.");
            // Only rows visible to this viewer are required. A private member
            // omitted by the server must not be recovered from another source.
            var total = page.GetProperty("matchedCount").GetInt32();
            if (expectedTotal is not null && expectedTotal != total)
                throw new AccountBridgeHostException("overlay.source_changed", true);
            expectedTotal = total;
            name ??= page.GetProperty("name").GetString() ?? target.Name;
            if (completeRoster is not null)
            {
                if (offset != 0 || completeRoster.Code != target.Code || completeRoster.Members.Count != total)
                    throw new AccountBridgeHostException("overlay.source_changed", true);
                // S2 already returned and validated every member. UI pagination
                // must not turn one complete response into repeated downloads.
                members.AddRange(completeRoster.Members);
            }
            else foreach (var row in page.GetProperty("members").EnumerateArray())
            {
                // The opaque member address, not a callsign or a display name,
                // detects pagination drift. Never send account IDs to the HUD.
                if (!seen.Add(row.GetProperty("memberRef").GetString()!))
                    throw new AccountBridgeHostException("overlay.source_changed", true);
                members.Add(ProjectOverlayMember(row) with
                { PreferenceKey = _communities!.OverlayPreferenceKey(row.GetProperty("memberRef").GetString()!, FriendScope(owner, generation)) });
            }
            var next = page.GetProperty("next");
            if (completeRoster is not null || next.ValueKind == JsonValueKind.Null)
            {
                if (members.Count != total)
                    throw new AccountBridgeHostException("overlay.source_changed", true);
                token.ThrowIfCancellationRequested();
                // Only the complete, privacy-projected roster crosses this seam.
                // Chat or announcement latency must not withhold accepted members.
                rosterReady?.Invoke(new(target.Code, name, Array.AsReadOnly(members.ToArray())));
                if (!includeCommunication) return new(target.Code, name, Array.AsReadOnly(members.ToArray()));
                var announcements = JsonSerializer.SerializeToElement(await ReadCommunityAnnouncementsAsync(owner,
                    JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef = target.Reference, offset = 0 }), token));
                var chat = JsonSerializer.SerializeToElement(await ReadCommunityChatAsync(owner,
                    JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef = target.Reference, after = 0L, before = 0L }), token));
                if (generation != Generation) throw new BridgeStaleGenerationException(generation, Generation);
                var notice = announcements.GetProperty("current");
                var messages = chat.GetProperty("messages").EnumerateArray().Select(message =>
                    new InformationOverlayRoomMessage(message.GetProperty("sequence").GetInt64(),
                        message.GetProperty("senderCallsign").GetString() ?? "",
                        message.GetProperty("senderGameId").GetString() ?? "",
                        message.GetProperty("text").GetString() ?? "",
                        message.GetProperty("createdAt").GetDateTimeOffset(),
                        message.TryGetProperty("isSystem", out var system) && system.GetBoolean())
                        {
                            IsSelf = message.GetProperty("isSelf").GetBoolean(),
                            // List metadata only confirms an attachment exists. Do not infer
                            // its type or fetch a package just to render a HUD placeholder.
                            AttachmentKind = message.TryGetProperty("hasAttachment", out var attachment) && attachment.GetBoolean()
                                ? "attachment" : null
                        }).ToArray();
                return new(target.Code, name, Array.AsReadOnly(members.ToArray()))
                {
                    AnnouncementTitle = notice.ValueKind == JsonValueKind.Null ? "" : notice.GetProperty("title").GetString() ?? "",
                    AnnouncementText = notice.ValueKind == JsonValueKind.Null ? "" : notice.GetProperty("content").GetString() ?? "",
                    LatestChatSequence = chat.GetProperty("latestSequence").GetInt64(),
                    Messages = Array.AsReadOnly(messages)
                };
            }
            var nextOffset = next.GetInt32();
            if (nextOffset <= offset) throw new InvalidDataException("Non-progressing organization page.");
            offset = nextOffset;
        }
        // Never publish the first page as if it were the complete roster.
        throw new AccountBridgeHostException("overlay.source_too_large");
    }

    internal static InformationOverlayCommunityMember ProjectOverlayMember(JsonElement row)
    {
        string Text(string key) => row.TryGetProperty(key, out var value) && value.ValueKind == JsonValueKind.String
            ? value.GetString()! : "";
        var pending = Text("liveStatus") == "InGame" && Text("location").Length > 0 &&
            row.TryGetProperty("arrivalPendingConfirmation", out var arrival) && arrival.ValueKind == JsonValueKind.True &&
            (!row.TryGetProperty("hasServerSession", out var session) || session.ValueKind != JsonValueKind.False);
        return new(Text("gameName"), Text("callsign"), Text("roleTitle"), Text("liveStatus"),
            Text("ship"), Text("location"), Text("serverRegion"), row.GetProperty("isSelf").GetBoolean())
        { LocationHiddenReason = StarBridge.Core.Presence.SharedLocationVisibility.NormalizeReason(
            Text("locationHiddenReason"), Text("location"), Text("liveStatus") == "InGame", pending),
            ArrivalPendingConfirmation = pending,
            ArrivalTargetCode = pending ? Text("arrivalTargetCode") : null };
    }
}
