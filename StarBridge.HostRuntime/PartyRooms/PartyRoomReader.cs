namespace StarBridge.HostRuntime.PartyRooms;

using System.Net;
using System.Net.Http.Headers;
using System.Text.Json;
using System.Text.Json.Serialization;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Presence;

// Deliberately not the Relay DTO: credentials, internal account IDs,
// raw application/invitation DTOs never cross this directory bridge. Hosts receive
// only the minimal application projection needed for an explicit decision.
internal sealed record RoomMemberView(string Callsign, string GameId, bool IsHost,
    string PresenceText, string LocationText, string ShipText, string ShardText)
{
    public string PresenceKey => RoomAvatarProjection.PresenceKey(PresenceText);
    public string? LocationHiddenReason { get; init; }
    public bool ArrivalPendingConfirmation { get; init; }
    public string? ArrivalTargetCode { get; init; }
    public RoomLocationLabels? ArrivalTargetLabels => ArrivalPendingConfirmation
        ? RoomLocationLabels.From(ArrivalTargetCode) : null;
    public string? AvatarImageData { get; init; }
    public string? UserRef { get; init; }
    public string? RemovalToken { get; init; }
    public bool IsSelf { get; init; }
    [JsonIgnore]
    public string AccountId { get; init; } = "";
    public string ServerRegion => GameServerRegionPresentation.ResolveCode(ShardText) ?? "";
    public RoomLocationLabels? LocationLabels => RoomLocationLabels.From(LocationText);
    public GameShipLabels? ShipLabels => PresenceKey == "presence.inGame" ? GameShipLabels.From(ShipText) : null;
}
internal sealed record RoomLocationLabels(
    [property: JsonPropertyName("en")] string En,
    [property: JsonPropertyName("zhHans")] string? ZhHans)
{
    internal static RoomLocationLabels? From(string? raw, GameLogLocationNameIndex? index = null)
    {
        if (string.IsNullOrWhiteSpace(raw)) return null;
        var name = index is null
            ? GameLogSessionTracker.FindSharedLocationName(raw)
            : index.FindDisplay(raw);
        return name is null ? null : new(name.EnglishName, name.ChineseName);
    }
}
internal sealed record RoomTagView(string Id, string Text, bool IsGameplay);
internal sealed record RoomApplicationView(string ApplicationId, string Callsign, string GameId, DateTimeOffset CreatedAt)
{
    public string? AvatarImageData { get; init; }
    public string? UserRef { get; init; }
    [JsonIgnore]
    public string AccountId { get; init; } = "";
}
internal sealed record RoomView(string RoomId, string Title, string Goal, int Capacity,
    bool IsPublic, string Eligibility, string AdmissionMode, bool PasswordRequired,
    string VoiceRequirement, string Language, DateTimeOffset ExpiresAt,
    DateTimeOffset? RecruitmentClosesAt, bool ViewerIsHost, RoomMemberView[] Members)
{
    public RoomTagView[] Tags { get; init; } = [];
    public string LeaderServerRegion { get; init; } = "";
    public string LeaderGameVersion { get; init; } = "";
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? RoomCode { get; init; }
    public RoomApplicationView[] PendingApplications { get; init; } = [];
    public bool CanPreviewMemberProfiles { get; init; }
}
internal sealed record RoomDirectoryView(
    [property: JsonIgnore(Condition = JsonIgnoreCondition.Never)] string? CurrentRoomId,
    DateTimeOffset ServerTime, RoomView[] Rooms)
{
    public int SchemaVersion => 1;
    public bool SupportsHostTransfer { get; init; }
    public string[]? ViewerPendingRoomIds { get; init; }
    public RoomInvitationView[] ReceivedInvitations { get; init; } = [];
    public RoomInvitationView[] SentInvitations { get; init; } = [];
    public RoomTagView[] TagOptions => CatalogOptions;
    private static readonly RoomTagView[] CatalogOptions = AllGameplay(PartyRoomTagCatalog.GameplayRoots)
        .Select(node => new RoomTagView(node.Id, PartyRoomTagCatalog.GetGameplayPathText(node.Id), true))
        .Concat(PartyRoomTagCatalog.ContextGroups.SelectMany(group => group.Tags)
            .Select(tag => new RoomTagView(tag.Id, tag.Name, false))).ToArray();
    private static IEnumerable<PartyRoomTagNode> AllGameplay(IEnumerable<PartyRoomTagNode> nodes)
    {
        foreach (var node in nodes)
        {
            yield return node;
            foreach (var child in AllGameplay(node.Children)) yield return child;
        }
    }
}

internal sealed partial class PartyRoomReader : IDisposable
{
    private const int MaxBytes = 2 * 1024 * 1024;
    private readonly HttpClient _http;
    private readonly Uri _endpoint;

    internal PartyRoomReader(Uri baseUri, HttpMessageHandler? handler = null)
    {
        if (!baseUri.IsAbsoluteUri || !string.IsNullOrEmpty(baseUri.UserInfo) ||
            !string.IsNullOrEmpty(baseUri.Query) || !string.IsNullOrEmpty(baseUri.Fragment) ||
            (baseUri.Scheme != "https" && !(baseUri.Scheme == "http" && baseUri.IsLoopback)))
            throw new ArgumentException("A trusted HTTPS or loopback Relay origin is required.", nameof(baseUri));
        _endpoint = new Uri(baseUri, "/api/party-rooms");
        _http = new HttpClient(handler ?? new HttpClientHandler { AllowAutoRedirect = false })
            { Timeout = TimeSpan.FromSeconds(12) };
    }

    internal async Task<RoomDirectoryView> ReadAsync(string bearer, CancellationToken token)
    {
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
        deadline.CancelAfter(TimeSpan.FromSeconds(12));
        using var request = new HttpRequestMessage(HttpMethod.Get, _endpoint);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
        try
        {
            using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, deadline.Token);
            if (response.StatusCode == HttpStatusCode.Unauthorized)
                // S2 uses 401 for an absent ACTIVE compatibility link too. This must
                // not invalidate an otherwise valid SCM session or create a link.
                throw new AccountBridgeHostException("party_rooms.identity_unavailable");
            if (response.StatusCode == HttpStatusCode.Forbidden)
                throw new AccountBridgeHostException("party_rooms.forbidden");
            if (!response.IsSuccessStatusCode)
                throw new AccountBridgeHostException("party_rooms.read_unavailable", true);
            if (response.Content.Headers.ContentLength > MaxBytes) throw Invalid();
            using var stream = await response.Content.ReadAsStreamAsync(deadline.Token);
            using var buffer = new MemoryStream();
            var chunk = new byte[8192];
            int count;
            while ((count = await stream.ReadAsync(chunk, deadline.Token)) != 0)
            {
                if (buffer.Length + count > MaxBytes) throw Invalid();
                buffer.Write(chunk, 0, count);
            }
            return Parse(buffer.ToArray());
        }
        catch (Exception error) when (error is HttpRequestException or IOException)
        { throw new AccountBridgeHostException("party_rooms.read_unavailable", true); }
        catch (OperationCanceledException) when (!token.IsCancellationRequested)
        { throw new AccountBridgeHostException("party_rooms.read_unavailable", true); }
    }

    internal static RoomDirectoryView Parse(byte[] json)
    {
        try
        {
            using var document = JsonDocument.Parse(json);
            var root = document.RootElement;
            var now = root.GetProperty("serverTime").GetDateTimeOffset();
            var currentValue = root.GetProperty("currentRoomId");
            var current = currentValue.ValueKind == JsonValueKind.Null ? null : Text(root, "currentRoomId", true);
            var rooms = root.GetProperty("rooms").EnumerateArray().Select(room =>
            {
                var joined = current is not null && current == Text(room, "roomId", true);
                var preview = room.TryGetProperty("canPreviewMemberProfiles", out var permitted) &&
                    permitted.ValueKind == JsonValueKind.True &&
                    StarBridge.Core.PartyRooms.PartyRoomProfilePreviewPolicy.Allows(
                        room.GetProperty("passwordRequired").GetBoolean(), Text(room, "admissionMode"), Text(room, "eligibility"));
                var capacity = room.GetProperty("capacity").GetInt32();
                var members = room.GetProperty("members").EnumerateArray().Select(member => new RoomMemberView(
                    Text(member, "callsign"), joined ? Text(member, "gameId") : "", member.GetProperty("isHost").GetBoolean(),
                    Text(member, "presenceText"), Text(member, "locationText"), Text(member, "shipText"),
                    Text(member, "shardText")) {
                        AvatarImageData = (joined || preview && !string.IsNullOrWhiteSpace(ReadMemberIdentity(member, false, true))) &&
                            member.TryGetProperty("avatarImageData", out var avatar) && avatar.ValueKind == JsonValueKind.String
                            ? RoomAvatarProjection.Normalize(avatar.GetString(), 512 * 1024) : null,
                        AccountId = ReadMemberIdentity(member, joined, preview),
                        RemovalToken = joined && room.GetProperty("viewerIsHost").GetBoolean() && !member.GetProperty("isHost").GetBoolean() &&
                            member.TryGetProperty("removalToken", out var removal) && removal.ValueKind == JsonValueKind.String &&
                            Guid.TryParseExact(removal.GetString(), "N", out _) ? removal.GetString() : null,
                        ArrivalPendingConfirmation = ReadArrivalPending(member, joined),
                        ArrivalTargetCode = ReadArrivalPending(member, joined) &&
                            member.TryGetProperty("arrivalTargetCode", out var arrivalTarget) && arrivalTarget.ValueKind == JsonValueKind.String
                            ? Text(member, "arrivalTargetCode") : null,
                        LocationHiddenReason = joined && member.TryGetProperty("locationHiddenReason", out var reason) &&
                            reason.ValueKind == JsonValueKind.String
                            ? StarBridge.Core.Presence.SharedLocationVisibility.NormalizeReason(reason.GetString(),
                                Text(member, "locationText"), RoomAvatarProjection.PresenceKey(Text(member, "presenceText")) == "presence.inGame",
                                ReadArrivalPending(member, joined)) : null
                    }).ToArray();
                if (capacity is < 2 or > 16 || members.Length > capacity) throw Invalid();
                var closes = room.GetProperty("recruitmentClosesAt");
                return new RoomView(Text(room, "roomId", true), Text(room, "title", true), Text(room, "goal"), capacity,
                    room.GetProperty("isPublic").GetBoolean(), Text(room, "eligibility", true),
                    Text(room, "admissionMode", true), room.GetProperty("passwordRequired").GetBoolean(),
                    Text(room, "voiceRequirement", true), Text(room, "language", true),
                    room.GetProperty("expiresAt").GetDateTimeOffset(),
                    closes.ValueKind == JsonValueKind.Null ? null : closes.GetDateTimeOffset(),
                    room.GetProperty("viewerIsHost").GetBoolean(), members)
                {
                    Tags = ReadTags(room),
                    CanPreviewMemberProfiles = !joined && preview,
                    PendingApplications = current == Text(room, "roomId", true) &&
                        room.GetProperty("viewerIsHost").GetBoolean() ? ReadApplications(room) : [],
                    RoomCode = current is not null && Text(room, "roomId", true) == current &&
                        room.TryGetProperty("roomCode", out _) ? Text(room, "roomCode") : null,
                    LeaderServerRegion = GameServerRegionPresentation.ResolveCode(
                        members.FirstOrDefault(member => member.IsHost)?.ShardText) ?? "",
                    LeaderGameVersion = RoomAvatarProjection.GameVersion(members.FirstOrDefault(member => member.IsHost)?.PresenceText)
                };
            }).ToArray();
            if (rooms.Length > 2000 || rooms.Select(room => room.RoomId).Distinct(StringComparer.Ordinal).Count() != rooms.Length ||
                (current is not null && !rooms.Any(room => room.RoomId == current))) throw Invalid();
            // A current membership is authoritative. Do not expose other rooms to
            // the client while joined, even if the old directory includes them.
            var visible = current is null ? rooms : rooms.Where(room => room.RoomId == current).ToArray();
            return new(current, now, visible) {
                SupportsHostTransfer = root.TryGetProperty("supportsHostTransfer", out var transfer) &&
                    transfer.ValueKind == JsonValueKind.True,
                ViewerPendingRoomIds = ReadPendingRoomIds(root),
                ReceivedInvitations = ReadInvitations(root, "receivedInvitations", now),
                SentInvitations = visible.Any(room => room.RoomId == current && room.ViewerIsHost)
                    ? ReadInvitations(root, "sentInvitations", now).Where(item => item.RoomId == current).ToArray() : []
            };
        }
        catch (Exception error) when (error is JsonException or InvalidOperationException or KeyNotFoundException or FormatException)
        { throw Invalid(); }
    }

    private static string[]? ReadPendingRoomIds(JsonElement root)
    {
        if (!root.TryGetProperty("viewerPendingRoomIds", out var values) ||
            values.ValueKind == JsonValueKind.Null) return null;
        if (values.ValueKind != JsonValueKind.Array || values.GetArrayLength() > 2000) throw Invalid();
        var ids = values.EnumerateArray().Select(value => value.GetString() ?? "").ToArray();
        if (ids.Any(id => string.IsNullOrWhiteSpace(id) || id.Length > 128 || id.Any(char.IsControl)) ||
            ids.Distinct(StringComparer.Ordinal).Count() != ids.Length) throw Invalid();
        return ids;
    }

    private static string ReadMemberIdentity(JsonElement member, bool currentRoom, bool preview = false)
    {
        // Discovery identities are intentionally redacted by the service.
        // Empty accountId is not a malformed room. Newer service projections
        // expose a bounded public profile identity only inside the joined room.
        if (!currentRoom && !preview) return "";
        if (member.TryGetProperty("publicProfileId", out var publicId) && publicId.ValueKind != JsonValueKind.Null)
        {
            if (publicId.ValueKind != JsonValueKind.String) throw Invalid();
            var value = publicId.GetString()!.Trim();
            if (value.Length is < 8 or > 128 || value.Contains('@') || value.Any(char.IsControl)) throw Invalid();
            return value;
        }
        if (!currentRoom || !member.TryGetProperty("accountId", out var account) || account.ValueKind == JsonValueKind.Null) return "";
        if (account.ValueKind != JsonValueKind.String) throw Invalid();
        return Text(member, "accountId");
    }

    private static bool ReadArrivalPending(JsonElement member, bool joined) => joined &&
        RoomAvatarProjection.PresenceKey(Text(member, "presenceText")) == "presence.inGame" &&
        !string.IsNullOrWhiteSpace(Text(member, "locationText")) &&
        member.TryGetProperty("arrivalPendingConfirmation", out var pending) && pending.ValueKind == JsonValueKind.True;

    private static string Text(JsonElement item, string key, bool required = false)
    {
        var value = item.GetProperty(key).GetString() ?? "";
        if (value.Length > 4096 || (required && string.IsNullOrWhiteSpace(value))) throw Invalid();
        return value;
    }

    private static RoomApplicationView[] ReadApplications(JsonElement room)
    {
        if (!room.TryGetProperty("pendingApplications", out var values)) return [];
        if (values.GetArrayLength() > 256) throw Invalid();
        var items = values.EnumerateArray().Select(item => new RoomApplicationView(
            Text(item, "applicationId", true), Text(item, "callsign"), Text(item, "gameId"),
            item.GetProperty("createdAt").GetDateTimeOffset()) {
                AccountId = ReadApplicationIdentity(item),
                AvatarImageData = item.TryGetProperty("avatarImageData", out var avatar) && avatar.ValueKind == JsonValueKind.String
                    ? RoomAvatarProjection.Normalize(avatar.GetString(), 512 * 1024) : null
            }).ToArray();
        if (items.Select(item => item.ApplicationId).Distinct(StringComparer.Ordinal).Count() != items.Length) throw Invalid();
        return items;
    }

    private static string ReadApplicationIdentity(JsonElement item)
    {
        if (!item.TryGetProperty("accountId", out var id) || id.ValueKind != JsonValueKind.String) return "";
        var value = id.GetString()!.Trim();
        return value.Length is >= 8 and <= 128 && !value.Contains('@') && !value.Any(char.IsControl) ? value : "";
    }

    private static RoomTagView[] ReadTags(JsonElement room)
    {
        var tags = new List<RoomTagView>();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var key in new[] { "gameplayTagNodeIds", "contextTagIds" })
        {
            if (!room.TryGetProperty(key, out var values) || values.ValueKind == JsonValueKind.Null) continue;
            if (values.GetArrayLength() > 32) throw Invalid();
            foreach (var value in values.EnumerateArray())
            {
                var id = value.GetString();
                if (id is null || id.Length > 256) throw Invalid();
                if (key == "gameplayTagNodeIds")
                {
                    var path = PartyRoomTagCatalog.GetGameplayPath(id);
                    if (path.Count > 0 && seen.Add(path[^1].Id))
                        tags.Add(new(path[^1].Id, string.Join(" · ", path.Select(node => node.Name)), true));
                }
                else if (PartyRoomTagCatalog.TryGetContextTag(id, out var tag) && seen.Add(tag.Id))
                    tags.Add(new(tag.Id, tag.Name, false));
            }
        }
        return tags.ToArray();
    }
    private static AccountBridgeHostException Invalid() => new("party_rooms.data_invalid");
    public void Dispose() => _http.Dispose();
}
