using System.Text.Json;
using StarBridge.HostRuntime.Overlay;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost : IOverlayFleetReader
{
    internal Action<BridgeAccountContext, long, string?>? FleetMembershipObserved { get; set; }
    private sealed record OverlayFleetWait(BridgeAccountContext Owner, long Generation, string Source, int Pages);
    private OverlayFleetWait? _overlayFleetWait;

    async Task<OverlayCommunityTarget?> IOverlayFleetReader.ReadFleetTargetAsync(BridgeAccountContext owner, CancellationToken token)
    {
        var generation = Generation;
        var projection = await GetOfficialFleetIdentityAsync(owner, token).ConfigureAwait(false);
        RequireFleetReadOwner(owner, generation);
        if (projection.State == "notMember") return null;
        var fleet = projection.Fleet ?? throw new AccountBridgeHostException("official_fleet.runtime_unavailable", true);
        return new(OverlayCommunitySource.FleetId, fleet.Name, fleet.SourceRef);
    }

    private static JsonElement OverlayFleetQuery(string source, int page) => JsonSerializer.SerializeToElement(new
    { schemaVersion = 2, sourceRef = source, search = "", filter = "all", pageNumber = page, pageSize = 100 });

    async Task<InformationOverlayCommunityContent> IOverlayFleetReader.ReadFleetContentAsync(BridgeAccountContext owner,
        OverlayCommunityTarget target, Action<InformationOverlayCommunityContent>? rosterReady, bool communication, CancellationToken token)
    {
        var generation = Generation;
        var rows = new List<InformationOverlayCommunityMember>();
        var seen = new HashSet<string>(StringComparer.Ordinal);
        int? total = null;
        var pages = 1;
        for (var page = 1; page <= pages; page++)
        {
            // This is exactly the page's privacy-projected runtime read. No raw
            // roster, profile, local game state or community enriches its fields.
            var result = JsonSerializer.SerializeToElement(await GetOfficialFleetRuntimeMembersAsync(owner,
                OverlayFleetQuery(target.Reference, page), token).ConfigureAwait(false));
            RequireFleetReadOwner(owner, generation);
            var count = result.GetProperty("totalCount").GetInt32();
            var pageCount = result.GetProperty("totalPages").GetInt32();
            if (result.GetProperty("sourceRef").GetString() != target.Reference || total is not null && total != count ||
                pageCount != Math.Max(1, (int)Math.Ceiling(count / 100d)) || pageCount > 128)
                throw new AccountBridgeHostException("overlay.source_changed", true);
            total = count; pages = pageCount;
            foreach (var row in result.GetProperty("members").EnumerateArray())
            {
                var reference = row.GetProperty("memberRef").GetString()!;
                if (!seen.Add(reference)) throw new AccountBridgeHostException("overlay.source_changed", true);
                rows.Add(ProjectOverlayFleetMember(row, OverlaySceneChoiceStore.Hash(owner) + "\n" + target.Reference));
            }
        }
        if (rows.Count != total) throw new AccountBridgeHostException("overlay.source_changed", true);
        RequireFleetReadOwner(owner, generation); token.ThrowIfCancellationRequested();
        Volatile.Write(ref _overlayFleetWait, new(owner, generation, target.Reference, pages));
        var roster = new InformationOverlayCommunityContent(OverlayCommunitySource.FleetId, target.Name, rows.AsReadOnly())
        { SharedFieldsOnly = true };
        rosterReady?.Invoke(roster);
        if (!communication) return roster;
        // Only the existing official communication channel. Rally is a separate
        // banner owner and is never read by this source. No attachment detail reads.
        var opened = JsonSerializer.SerializeToElement(await OfficialFleetCommunicationAsync(owner,
            JsonSerializer.SerializeToElement(new { schemaVersion = 1, sourceRef = target.Reference, action = "open" }), token));
        var targetRef = opened.GetProperty("targetRef").GetString();
        var announcements = opened.GetProperty("announcementsAvailable").GetBoolean()
            ? JsonSerializer.SerializeToElement(await OfficialFleetCommunicationAsync(owner, JsonSerializer.SerializeToElement(new
                { schemaVersion = 1, sourceRef = target.Reference, action = "announcements", targetRef, offset = 0 }), token))
            : JsonSerializer.SerializeToElement(new { current = (object?)null });
        // Match the main fleet page's opt-in. CommunityClient alone projects
        // visible authors and keeps hidden/unavailable identities anonymous.
        var chatQuery = new Dictionary<string, object?>
        {
            ["schemaVersion"] = 1, ["sourceRef"] = target.Reference, ["action"] = "chat",
            ["targetRef"] = targetRef, ["after"] = 0L, ["before"] = 0L
        };
        if (opened.TryGetProperty("authorIdentitySchemaVersion", out var authorSchema) && authorSchema.GetInt32() == 1)
        {
            chatQuery["authorIdentitySchemaVersion"] = 1;
            chatQuery["observeMessageRefs"] = Array.Empty<string>();
        }
        var chat = opened.GetProperty("chatAvailable").GetBoolean()
            ? JsonSerializer.SerializeToElement(await OfficialFleetCommunicationAsync(owner, JsonSerializer.SerializeToElement(chatQuery), token))
            : JsonSerializer.SerializeToElement(new { latestSequence = 0L, messages = Array.Empty<object>() });
        RequireFleetReadOwner(owner, generation); token.ThrowIfCancellationRequested();
        return ProjectOverlayFleetCommunication(roster, announcements, chat);
    }

    internal static InformationOverlayCommunityMember ProjectOverlayFleetMember(JsonElement row, string scope)
    {
        string Text(string key) => row.TryGetProperty(key, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString()! : "";
        string Cell(string key) => row.TryGetProperty(key, out var value) && value.GetProperty("state").GetString() == "value"
            ? value.GetProperty("value").GetString() ?? "" : "";
        var presence = Text("presence") switch { "inGame" => "InGame", "online" => "AppOnline", "away" => "Away", "offline" => "Offline", _ => "Unknown" };
        // Use the community projection for hidden-location and pending-arrival
        // semantics, after translating only fields authorized by the fleet page.
        var projected = ProjectOverlayMember(JsonSerializer.SerializeToElement(new
        {
            gameName = Text("gameId"), callsign = Text("callsign"), roleTitle = Text("officialRankName"), liveStatus = presence,
            ship = Cell("ship"), location = Cell("location"),
            serverRegion = row.GetProperty("server").GetProperty("state").GetString() == "value" ? Text("serverRegion") : "",
            // The page's server cell carries the shard id when the member shares it.
            serverShard = row.GetProperty("server").GetProperty("state").GetString() == "value" ? Cell("server") : "",
            isSelf = row.TryGetProperty("isSelf", out var self) && self.ValueKind == JsonValueKind.True,
            locationHiddenReason = Text("locationHiddenReason"),
            arrivalPendingConfirmation = row.TryGetProperty("arrivalPending", out var pending) && pending.ValueKind == JsonValueKind.True,
            arrivalTargetCode = Text("arrivalTargetCode"),
            hasServerSession = !row.TryGetProperty("hasServerSession", out var session) || session.ValueKind != JsonValueKind.False
        }));
        return projected with { PreferenceKey = OverlayMemberIdentity.FromAccountId(scope + "\n" + Text("memberRef")) };
    }

    internal static InformationOverlayCommunityContent ProjectOverlayFleetCommunication(InformationOverlayCommunityContent roster,
        JsonElement announcements, JsonElement chat)
    {
        static bool IsRallyOrSystem(JsonElement value) =>
            value.TryGetProperty("isSystem", out var system) && system.ValueKind == JsonValueKind.True ||
            new[] { "kind", "type", "sourceType" }.Any(key => value.TryGetProperty(key, out var kind) &&
                kind.ValueKind == JsonValueKind.String && kind.GetString() is { } text && text.Contains("rally", StringComparison.OrdinalIgnoreCase));
        var notice = announcements.GetProperty("current");
        var showNotice = notice.ValueKind == JsonValueKind.Object && !IsRallyOrSystem(notice);
        var messages = chat.GetProperty("messages").EnumerateArray().Where(message => !IsRallyOrSystem(message)).Select(message =>
            new InformationOverlayRoomMessage(message.GetProperty("sequence").GetInt64(),
                message.GetProperty("senderCallsign").GetString() ?? "", message.GetProperty("senderGameId").GetString() ?? "",
                message.GetProperty("text").GetString() ?? "", message.GetProperty("createdAt").GetDateTimeOffset(), false)
            {
                IsSelf = message.GetProperty("isSelf").GetBoolean(),
                AuthorValidUntil = message.TryGetProperty("identityValidUntilUtc", out var validity) &&
                    validity.ValueKind == JsonValueKind.String && validity.TryGetDateTimeOffset(out var until) ? until : DateTimeOffset.MinValue,
                AttachmentKind = message.TryGetProperty("hasAttachment", out var attachment) && attachment.ValueKind == JsonValueKind.True ? "attachment" : null
            }).ToArray();
        return roster with
        {
            AnnouncementTitle = showNotice ? notice.GetProperty("title").GetString() ?? "" : "",
            AnnouncementText = showNotice ? notice.GetProperty("content").GetString() ?? "" : "",
            LatestChatSequence = chat.GetProperty("latestSequence").GetInt64(), Messages = Array.AsReadOnly(messages)
        };
    }

    async Task<OverlayActivityCursor> IOverlayFleetReader.WaitFleetChangesAsync(BridgeAccountContext owner, long generation,
        OverlayActivityCursor after, CancellationToken token)
    {
        RequireFleetReadOwner(owner, generation);
        var scope = Volatile.Read(ref _overlayFleetWait);
        if (scope is null || scope.Owner != owner || scope.Generation != generation)
            throw new AccountBridgeHostException("official_fleet.runtime_unavailable", true);
        using var pending = CancellationTokenSource.CreateLinkedTokenSource(token);
        var started = System.Diagnostics.Stopwatch.GetTimestamp();
        async Task<bool> Wait(int page)
        {
            var result = JsonSerializer.SerializeToElement(await WaitOfficialFleetRuntimeActivityAsync(owner,
                OverlayFleetQuery(scope.Source, page), pending.Token).ConfigureAwait(false));
            RequireFleetReadOwner(owner, generation);
            return result.GetProperty("changed").GetBoolean();
        }
        var communicationAfter = after.Instance == scope.Source ? after.FleetCommunication ?? new() : new();
        var communicationNext = communicationAfter;
        async Task<bool> WaitCommunication()
        {
            var result = JsonSerializer.SerializeToElement(await WaitOfficialFleetActivityAsync(owner,
                JsonSerializer.SerializeToElement(new { schemaVersion = 1, sourceRef = scope.Source,
                    instance = communicationAfter.Instance, version = communicationAfter.Version }), pending.Token).ConfigureAwait(false));
            RequireFleetReadOwner(owner, generation);
            communicationNext = new(result.GetProperty("instance").GetString()!, result.GetProperty("version").GetInt64());
            return communicationNext.Instance != communicationAfter.Instance || communicationNext.Version != communicationAfter.Version;
        }
        // Every displayed member page and the communication channel participate.
        // Quiet member state must not conceal a chat or announcement change.
        var waits = Enumerable.Range(1, scope.Pages).Select(Wait).Append(WaitCommunication()).ToList();
        var changed = false;
        try
        {
            while (waits.Count > 0)
            {
                var completed = await Task.WhenAny(waits).ConfigureAwait(false);
                waits.Remove(completed);
                if (await completed.ConfigureAwait(false)) { changed = true; break; }
            }
        }
        finally
        {
            pending.Cancel();
            try { await Task.WhenAll(waits).ConfigureAwait(false); } catch (OperationCanceledException) when (!token.IsCancellationRequested) { }
        }
        RequireFleetReadOwner(owner, generation);
        // An older/empty-owner server may complete a quiet wait immediately.
        // Keep that case at reconciliation frequency instead of a short poll.
        if (!changed && System.Diagnostics.Stopwatch.GetElapsedTime(started) < TimeSpan.FromSeconds(1))
            await Task.Delay(TimeSpan.FromSeconds(15), token).ConfigureAwait(false);
        RequireFleetReadOwner(owner, generation);
        if (Volatile.Read(ref _overlayFleetWait) != scope)
            throw new AccountBridgeHostException("overlay.source_changed", true);
        return new(scope.Source, changed ? Math.Max(0, after.Version) + 1 : Math.Max(0, after.Version), true)
        { FleetCommunication = communicationNext };
    }
}
