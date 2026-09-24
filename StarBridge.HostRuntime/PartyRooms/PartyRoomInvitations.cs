namespace StarBridge.HostRuntime.PartyRooms;

using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using StarBridge.Core.PartyRooms;
using StarBridge.HostRuntime.Account;

internal sealed record RoomInvitationView(string InvitationId, string RoomId, string RoomTitle,
    string InviterCallsign, string InviterGameId, string RecipientCallsign, string RecipientGameId,
    DateTimeOffset ExpiresAt)
{ public DateTimeOffset? CreatedAt { get; init; } }
internal sealed record RoomInviteTargetView(string TargetRef, string Callsign, string GameId, bool AlreadyInvited);

internal sealed partial class PartyRoomReader
{
    private readonly byte[] _inviteReferenceKey = RandomNumberGenerator.GetBytes(32);
    private string TargetReference(string bearer, string id) => Convert.ToHexString(
        HMACSHA256.HashData(_inviteReferenceKey, Encoding.UTF8.GetBytes(bearer + "\n" + id)));

    private static RoomInvitationView[] ReadInvitations(JsonElement root, string key, DateTimeOffset now)
    {
        if (!root.TryGetProperty(key, out var list)) return [];
        if (list.GetArrayLength() > 256) throw Invalid();
        var items = list.EnumerateArray().Select(item => new RoomInvitationView(
            Text(item, "invitationId", true), Text(item, "roomId", true), Text(item, "roomTitle", true),
            Text(item, "inviterCallsign"), Text(item, "inviterGameId"),
            Text(item, "recipientCallsign"), Text(item, "recipientGameId"),
            item.GetProperty("expiresAt").GetDateTimeOffset()) {
                CreatedAt = item.TryGetProperty("createdAt", out var created) && created.ValueKind == JsonValueKind.String && created.TryGetDateTimeOffset(out var instant) ? instant : null
            }).ToArray();
        if (items.Select(item => item.InvitationId).Distinct(StringComparer.Ordinal).Count() != items.Length) throw Invalid();
        return items.Where(item => item.ExpiresAt > now).ToArray();
    }

    // Fixed same-origin GETs only. Tokens and upstream bodies stay inside Host.
    private async Task<JsonDocument> ReadRoomJsonAsync(string bearer, string path, CancellationToken token)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, new Uri(_endpoint, path));
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
        try {
            using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token);
            if (response.StatusCode == HttpStatusCode.Unauthorized) throw new AccountBridgeHostException("party_rooms.identity_unavailable");
            if (response.StatusCode == HttpStatusCode.Forbidden) throw new AccountBridgeHostException("party_rooms.forbidden");
            if (!response.IsSuccessStatusCode) throw new AccountBridgeHostException("party_rooms.command_unavailable");
            return await ReadBoundedRoomJsonAsync(response, token);
        }
        catch (Exception error) when (error is HttpRequestException or IOException or OperationCanceledException)
        { throw new AccountBridgeHostException("party_rooms.command_unavailable"); }
    }

    private static async Task<JsonDocument> ReadBoundedRoomJsonAsync(HttpResponseMessage response, CancellationToken token)
    {
        if (response.Content.Headers.ContentLength > MaxBytes) throw Invalid();
        using var stream = await response.Content.ReadAsStreamAsync(token);
        using var buffer = new MemoryStream();
        var bytes = new byte[8192];
        int count;
        while ((count = await stream.ReadAsync(bytes, token)) != 0) {
            if (buffer.Length + count > MaxBytes) throw Invalid();
            buffer.Write(bytes, 0, count);
        }
        try { return JsonDocument.Parse(buffer.ToArray()); }
        catch (JsonException) { throw Invalid(); }
    }

    private async Task<RoomCommandView> ExecuteInvitationAsync(string bearer, JsonElement payload, CancellationToken token)
    {
        string operation, roomId, reference;
        try {
            if (payload.GetProperty("schemaVersion").GetInt32() != 1 ||
                payload.EnumerateObject().Any(p => p.Name is not ("schemaVersion" or "operation" or "data"))) throw Invalid();
            operation = Text(payload, "operation", true);
            var data = payload.GetProperty("data");
            var extra = operation == "invite" ? "targetRef" : "invitationId";
            if (data.EnumerateObject().Any(p => p.Name != "roomId" && (operation == "inviteTargets" || p.Name != extra))) throw Invalid();
            roomId = Text(data, "roomId", true);
            reference = operation == "inviteTargets" ? "" : Text(data, extra, true);
            if (roomId.Length > 128 || reference.Length > 128) throw Invalid();
        } catch (Exception error) when (error is InvalidOperationException or KeyNotFoundException or FormatException) { throw Invalid(); }
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
        deadline.CancelAfter(TimeSpan.FromSeconds(12));
        using var rawDirectory = await ReadRoomJsonAsync(bearer, "/api/party-rooms", deadline.Token);
        var directory = Parse(Encoding.UTF8.GetBytes(rawDirectory.RootElement.GetRawText()));
        var host = directory.CurrentRoomId == roomId && directory.Rooms.SingleOrDefault()?.ViewerIsHost == true;
        string path;
        object body;
        string expected;
        if (operation is "inviteTargets" or "invite") {
            if (!host) return new("rejected", "notHost", directory, null);
            using var friends = await ReadRoomJsonAsync(bearer, "/api/friends?includePresence=false", deadline.Token);
            var list = friends.RootElement.GetProperty("friends");
            if (list.GetArrayLength() > 2000) throw Invalid();
            var rawRoom = rawDirectory.RootElement.GetProperty("rooms").EnumerateArray().Single(item => Text(item, "roomId") == roomId);
            var memberIds = rawRoom.GetProperty("members").EnumerateArray().Select(item => Text(item, "accountId", true)).ToHashSet(StringComparer.OrdinalIgnoreCase);
            var activeIds = directory.SentInvitations.Select(item => item.InvitationId).ToHashSet(StringComparer.Ordinal);
            var invitedIds = rawDirectory.RootElement.TryGetProperty("sentInvitations", out var sentInvitations)
                ? sentInvitations.EnumerateArray().Where(item => activeIds.Contains(Text(item, "invitationId", true)))
                    .Select(item => Text(item, "recipientAccountId", true)).ToHashSet(StringComparer.OrdinalIgnoreCase)
                : [];
            var users = list.EnumerateArray().Select(entry => entry.GetProperty("user"))
                .Where(user => Text(user, "relationshipState") == "friend" && !memberIds.Contains(Text(user, "accountId", true))).ToArray();
            if (operation == "inviteTargets") return new("targets", null, directory, null) {
                Targets = users.Select(user => new RoomInviteTargetView(TargetReference(bearer, Text(user, "accountId", true)),
                    Text(user, "callsign"), Text(user, "gameId"), invitedIds.Contains(Text(user, "accountId", true)))).ToArray()
            };
            var selected = users.FirstOrDefault(user => TargetReference(bearer, Text(user, "accountId", true)) == reference);
            if (selected.ValueKind == JsonValueKind.Undefined) return new("rejected", "targetGone", directory, null);
            path = "/api/party-rooms/invitations";
            body = new PartyRoomInviteCreateRequest(roomId, Text(selected, "accountId", true));
            expected = "invited";
        } else {
            var sent = operation == "inviteRevoke";
            if (sent && !host) return new("rejected", "notHost", directory, null);
            var invitation = (sent ? directory.SentInvitations : directory.ReceivedInvitations)
                .SingleOrDefault(item => item.InvitationId == reference && item.RoomId == roomId);
            if (invitation is null) return new("rejected", "invitationGone", directory, null);
            if (operation == "invitePreview") {
                if (directory.CurrentRoomId is not null) return new("rejected", "alreadyJoined", directory, null);
                using var previewRequest = new HttpRequestMessage(HttpMethod.Post, new Uri(_endpoint, "/api/party-rooms/invitations/preview"));
                previewRequest.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
                previewRequest.Content = JsonContent.Create(new PartyRoomInvitePreviewRequest(roomId, reference));
                using var previewResponse = await _http.SendAsync(previewRequest, HttpCompletionOption.ResponseHeadersRead, deadline.Token);
                if (!previewResponse.IsSuccessStatusCode) return new("rejected", "invitationGone", null, null);
                using var previewBody = await ReadBoundedRoomJsonAsync(previewResponse, deadline.Token);
                var preview = Parse(JsonSerializer.SerializeToUtf8Bytes(new {
                    currentRoomId = (string?)null, serverTime = directory.ServerTime,
                    rooms = new[] { previewBody.RootElement.GetProperty("room") }
                })).Rooms.Single();
                if (preview.RoomId != roomId) throw Invalid();
                return new("resolved", null, null, preview);
            }
            if (operation == "inviteJoin") {
                if (directory.CurrentRoomId is not null) return new("rejected", "alreadyJoined", directory, null);
                path = "/api/party-rooms/join";
                body = new PartyRoomJoinRequest(roomId, null, null) { InvitationId = reference };
                expected = "joined";
            } else {
                path = "/api/party-rooms/invitations/action";
                body = new PartyRoomInviteActionRequest(roomId, reference, sent ? "revoke" : "decline");
                expected = sent ? "revoked" : "declined";
            }
        }
        using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(_endpoint, path));
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
        request.Content = JsonContent.Create(body, body.GetType());
        try {
            using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, deadline.Token);
            if (response.StatusCode == HttpStatusCode.Unauthorized) throw new AccountBridgeHostException("party_rooms.identity_unavailable");
            if (response.StatusCode == HttpStatusCode.Forbidden) throw new AccountBridgeHostException("party_rooms.forbidden");
            if (!response.IsSuccessStatusCode && response.StatusCode != HttpStatusCode.BadRequest) throw new AccountBridgeHostException("party_rooms.outcome_unknown");
            using var result = await ReadBoundedRoomJsonAsync(response, deadline.Token);
            if (!response.IsSuccessStatusCode || (result.RootElement.TryGetProperty("error", out var error) && error.ValueKind != JsonValueKind.Null))
                return new("rejected", "invitationRejected", null, null);
            var status = Text(result.RootElement, "status");
            if (status != expected && !(operation == "invite" && status == "already_invited")) throw Invalid();
            try { return new(expected, null, await ReadAsync(bearer, deadline.Token), null); }
            catch (Exception refreshError) when (refreshError is AccountBridgeHostException or OperationCanceledException) { return new(expected, "refreshRequired", null, null); }
        } catch (AccountBridgeHostException error) when (error.Code == "party_rooms.data_invalid") { throw new AccountBridgeHostException("party_rooms.outcome_unknown"); }
        catch (Exception error) when (error is HttpRequestException or IOException or OperationCanceledException or JsonException or InvalidOperationException or KeyNotFoundException)
        { throw new AccountBridgeHostException("party_rooms.outcome_unknown"); }
    }
}
