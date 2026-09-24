namespace StarBridge.HostRuntime.PartyRooms;

using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.Core.PartyRooms;
using StarBridge.HostRuntime.Account;

internal sealed record RoomCommandView(string Status, string? Error, RoomDirectoryView? Directory, RoomView? Preview)
{
    [System.Text.Json.Serialization.JsonIgnore]
    public RoomDirectoryView? AuthorizedOverlayDirectory { get; init; }
    public int SchemaVersion => 1;
    public RoomInviteTargetView[] Targets { get; init; } = [];
    public RoomChatPageView? Chat { get; init; }
    public RoomChatMessageView? Message { get; init; }
}

internal sealed partial class PartyRoomReader
{
    internal async Task<RoomCommandView> ExecuteAsync(string bearer, JsonElement payload, CancellationToken token)
    {
        if (payload.TryGetProperty("operation", out var chatOperation) && chatOperation.GetString() is "chatRead" or "chatSend")
            return await ExecuteChatAsync(bearer, payload, token);
        if (payload.TryGetProperty("operation", out var requested) && requested.GetString() is
            "inviteTargets" or "invite" or "inviteDecline" or "inviteRevoke" or "inviteJoin" or "invitePreview")
        {
            try { return await ExecuteInvitationAsync(bearer, payload, token); }
            catch (Exception error) when (error is InvalidOperationException or KeyNotFoundException or FormatException or JsonException)
            { throw Invalid(); }
        }
        var (path, body, operation) = BuildCommand(payload);
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
        deadline.CancelAfter(TimeSpan.FromSeconds(12));
        if (operation is "update" or "close" or "decide")
        {
            RoomDirectoryView directory;
            try { directory = await ReadAsync(bearer, deadline.Token); }
            catch (AccountBridgeHostException error) when (error.Code is not ("party_rooms.identity_unavailable" or "party_rooms.forbidden"))
            { throw new AccountBridgeHostException("party_rooms.command_unavailable"); }
            var target = payload.GetProperty("data").GetProperty("roomId").GetString();
            var current = directory.Rooms.SingleOrDefault(room => room.RoomId == directory.CurrentRoomId && room.RoomId == target);
            if (current?.ViewerIsHost != true) return new("rejected", "notHost", directory, null);
            if (body is PartyRoomUpdateRequest update && update.Capacity < current.Members.Length)
                return new("rejected", "capacityTooSmall", directory, null);
            if (body is PartyRoomApplicationDecisionRequest decision && !current.PendingApplications.Any(item => item.ApplicationId == decision.ApplicationId))
                return new("rejected", "applicationGone", directory, null);
        }
        using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(_endpoint, path));
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
        request.Content = JsonContent.Create(body, body.GetType());
        try
        {
            using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, deadline.Token);
            if (response.StatusCode == HttpStatusCode.Unauthorized)
                throw new AccountBridgeHostException("party_rooms.identity_unavailable");
            if (response.StatusCode == HttpStatusCode.Forbidden)
                throw new AccountBridgeHostException("party_rooms.forbidden");
            if (response.StatusCode != HttpStatusCode.BadRequest && response.StatusCode != HttpStatusCode.Conflict && !response.IsSuccessStatusCode)
                throw new AccountBridgeHostException("party_rooms.outcome_unknown");
            using var stream = await response.Content.ReadAsStreamAsync(deadline.Token);
            using var buffer = new MemoryStream();
            var bytes = new byte[8192];
            int count;
            while ((count = await stream.ReadAsync(bytes, deadline.Token)) != 0)
            {
                if (buffer.Length + count > MaxBytes) throw Invalid();
                buffer.Write(bytes, 0, count);
            }
            using var document = JsonDocument.Parse(buffer.ToArray());
            var root = document.RootElement;
            var error = root.TryGetProperty("error", out var e) ? e.GetString() : null;
            if (!string.IsNullOrEmpty(error) || !response.IsSuccessStatusCode)
                return new("rejected", SafeRejection(error), null, null);
            var status = root.TryGetProperty("status", out var s) ? s.GetString() : null;
            var expectedStatus = operation switch {
                "create" => status == "joined",
                "join" => status is "joined" or "pending",
                "leave" => status is "left" or "closed",
                "resolve" => status == "resolved",
                "update" => status == "updated",
                "close" => status == "closed",
                "decide" => body is PartyRoomApplicationDecisionRequest decision &&
                    status == (decision.Approve ? "joined" : "rejected"),
                _ => false
            };
            if (status is null || !expectedStatus) throw Invalid();
            if (operation == "decide") status = status == "joined" ? "approved" : "declined";
            if (operation == "resolve")
            {
                var room = root.GetProperty("room");
                var projection = Parse(JsonSerializer.SerializeToUtf8Bytes(new {
                    currentRoomId = (string?)null, serverTime = DateTimeOffset.UtcNow, rooms = new[] { room }
                }));
                return new(status, null, null, projection.Rooms.Single());
            }
            // Never infer membership from a command's room object: pending requests
            // also return a room. Re-read the authoritative membership instead.
            try { return new(status, null, await ReadAsync(bearer, deadline.Token), null); }
            catch (Exception errorAfterWrite) when (errorAfterWrite is AccountBridgeHostException or OperationCanceledException)
            { return new(status, "refreshRequired", null, null); }
        }
        catch (Exception error) when (error is HttpRequestException or IOException or OperationCanceledException)
        { throw new AccountBridgeHostException("party_rooms.outcome_unknown"); }
        // Invalid input is rejected before dispatch. Invalid data after dispatch
        // cannot prove that the write failed and must never enable blind replay.
        catch (AccountBridgeHostException error) when (error.Code == "party_rooms.data_invalid")
        { throw new AccountBridgeHostException("party_rooms.outcome_unknown"); }
        catch (Exception error) when (error is JsonException or InvalidOperationException or KeyNotFoundException or FormatException)
        { throw new AccountBridgeHostException("party_rooms.outcome_unknown"); }
    }

    private static (string Path, object Body, string Operation) BuildCommand(JsonElement payload)
    {
        try
        {
            if (payload.GetProperty("schemaVersion").GetInt32() != 1) throw Invalid();
            var operation = Text(payload, "operation", true);
            if (payload.EnumerateObject().Any(p => p.Name is not ("schemaVersion" or "operation" or "data"))) throw Invalid();
            var data = payload.GetProperty("data");
            if (data.ValueKind != JsonValueKind.Object) throw Invalid();
            string Bounded(string key, int max, bool required = true)
            {
                var value = Text(data, key, required).Trim();
                if (value.Length > max || value.Any(c => char.IsControl(c) && c is not '\n' and not '\t')) throw Invalid();
                return value;
            }
            void Only(params string[] fields)
            {
                if (data.EnumerateObject().Any(p => !fields.Contains(p.Name, StringComparer.Ordinal))) throw Invalid();
            }
            switch (operation)
            {
                case "close":
                    Only("roomId");
                    return ("/api/party-rooms/close", new PartyRoomCloseRequest(Bounded("roomId", 128)), operation);
                case "decide":
                    Only("roomId", "applicationId", "approve");
                    return ("/api/party-rooms/applications/decision", new PartyRoomApplicationDecisionRequest(
                        Bounded("roomId", 128), Bounded("applicationId", 128), data.GetProperty("approve").GetBoolean()), operation);
                case "leave":
                    Only("roomId");
                    return ("/api/party-rooms/leave", new PartyRoomLeaveRequest(Bounded("roomId", 128)), operation);
                case "resolve":
                    Only("roomCode");
                    return ("/api/party-rooms/resolve-code", new PartyRoomResolveCodeRequest(Bounded("roomCode", 32)), operation);
                case "join":
                    Only("roomId", "password");
                    return ("/api/party-rooms/join", new PartyRoomJoinRequest(Bounded("roomId", 128), Bounded("password", 32, false), null), operation);
                case "create":
                case "update":
                    var editing = operation == "update";
                    Only(editing
                        ? ["roomId", "title", "goal", "capacity", "isPublic", "eligibility", "admissionMode", "passwordMode", "password", "voiceRequirement", "language", "recruitmentDurationMinutes", "autoDisbandHours", "gameplayTagNodeIds", "contextTagIds"]
                        : ["title", "goal", "capacity", "isPublic", "eligibility", "admissionMode", "passwordEnabled", "password", "voiceRequirement", "language", "recruitmentDurationMinutes", "autoDisbandHours", "gameplayTagNodeIds", "contextTagIds"]);
                    var capacity = data.GetProperty("capacity").GetInt32();
                    var hours = data.GetProperty("autoDisbandHours").GetInt32();
                    var minutesValue = data.GetProperty("recruitmentDurationMinutes");
                    int? minutes = minutesValue.ValueKind == JsonValueKind.Null ? null : minutesValue.GetInt32();
                    if (capacity is < 2 or > 16 || hours is not (1 or 2 or 4 or 6 or 12 or 24) || minutes is <= 0 || minutes > hours * 60) throw Invalid();
                    string Choice(string key, params string[] choices)
                    {
                        var value = Bounded(key, 32);
                        return choices.Contains(value) ? value : throw Invalid();
                    }
                    string[] Ids(string key, bool gameplay)
                    {
                        var ids = data.GetProperty(key).EnumerateArray().Select(x => x.GetString() ?? "").ToArray();
                        if (ids.Length > 5 || ids.Any(id => id.Length > 128 ||
                            (gameplay ? !PartyRoomTagCatalog.TryGetGameplayNode(id, out _) : !PartyRoomTagCatalog.TryGetContextTag(id, out _)))) throw Invalid();
                        return ids.Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
                    }
                    var gameplay = Ids("gameplayTagNodeIds", true);
                    var context = Ids("contextTagIds", false);
                    if (gameplay.Length is < 1 or > 3 || context.Length > 3 || gameplay.Length + context.Length > 5) throw Invalid();
                    if (gameplay.Where((id, index) => gameplay.Skip(index + 1)
                        .Any(other => PartyRoomTagCatalog.AreOnSameBranch(id, other))).Any()) throw Invalid();
                    var password = Bounded("password", 32, false);
                    var passwordMode = editing ? Choice("passwordMode", "keep", "remove", "replace") : "";
                    var enabled = editing ? passwordMode == "replace" : data.GetProperty("passwordEnabled").GetBoolean();
                    if (enabled && password.Length < 4) throw Invalid();
                    var title = Bounded("title", 32);
                    if (title.Length < 2) throw Invalid();
                    var draft = new PartyRoomCreateRequest(
                        title, Bounded("goal", 120, false), gameplay, context, capacity,
                        data.GetProperty("isPublic").GetBoolean(), Choice("eligibility", "everyone", "friends", "fleet", "invite"),
                        Choice("admissionMode", "direct", "approval"), enabled, enabled ? password : null,
                        Choice("voiceRequirement", "none", "recommended", "required"), Choice("language", "zh", "en", "bilingual"),
                        minutes, hours, null) { TagCatalogVersion = PartyRoomTagCatalog.Version };
                    if (!editing) return ("/api/party-rooms", draft, operation);
                    return ("/api/party-rooms/update", new PartyRoomUpdateRequest(Bounded("roomId", 128),
                        draft.Title, draft.Goal, gameplay, context, capacity, draft.IsPublic, draft.Eligibility,
                        draft.AdmissionMode, passwordMode, enabled ? password : null, draft.VoiceRequirement,
                        draft.Language, minutes, hours) { TagCatalogVersion = PartyRoomTagCatalog.Version }, operation);
                default: throw Invalid();
            }
        }
        catch (Exception error) when (error is InvalidOperationException or KeyNotFoundException or FormatException)
        { throw Invalid(); }
    }

    private static string SafeRejection(string? message) => message switch
    {
        "房间密码不正确。" => "passwordIncorrect",
        "房间已经满员。" => "roomFull",
        "房间已经停止招募。" => "recruitmentClosed",
        "房间已经解散。" => "roomGone",
        "房间不存在或已经解散。" => "roomGone",
        "这条申请已经处理或失效。" => "applicationGone",
        "该玩家已经加入其他房间。" => "applicantMoved",
        "人数上限不能低于当前成员数。" => "capacityTooSmall",
        "只有房主可以修改房间设置。" or "只有房主可以处理加入申请。" or "只有房主可以关闭房间。" => "notHost",
        _ => "rejected"
    };
}
