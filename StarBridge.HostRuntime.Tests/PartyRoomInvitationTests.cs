using System.Net;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.PartyRooms;
using StarBridge.NativeBridge;

internal static class PartyRoomInvitationTests
{
    internal static async Task Invitations()
    {
        byte[] Directory(bool host) {
            var root = JsonNode.Parse(PartyRoomReaderTests.Wire(host ? "one" : null, PartyRoomReaderTests.Room("one")))!;
            root["rooms"]![0]!["viewerIsHost"] = host;
            root[host ? "sentInvitations" : "receivedInvitations"] = JsonSerializer.SerializeToNode(new[] {
                new { invitationId = "invitation-1", roomId = "one", roomTitle = "Test room", inviterCallsign = "房主",
                    inviterGameId = "Host_CN", recipientCallsign = "好友", recipientGameId = "Friend_CN",
                    inviterAccountId = "private-owner", recipientAccountId = "private-target", expiresAt = "2026-09-06T12:00:00Z" }
            });
            return Encoding.UTF8.GetBytes(root.ToJsonString());
        }
        var previewPosts = 0;
        using (var previews = new PartyRoomReader(new Uri("https://relay.example.test"), new Handler(request => {
            if (request.Method == HttpMethod.Get) return Ok(Directory(false));
            Check(request.Method == HttpMethod.Post && request.RequestUri!.AbsolutePath == "/api/party-rooms/invitations/preview",
                "Preview never joins a room or reads chat.");
            previewPosts++;
            using var payload = JsonDocument.Parse(request.Content!.ReadAsStringAsync().GetAwaiter().GetResult());
            Check(payload.RootElement.GetProperty("invitationId").GetString() == "invitation-1", "Preview preserves the authorized invitation.");
            return Ok(JsonSerializer.SerializeToUtf8Bytes(new { room = PartyRoomReaderTests.Room("one") }));
        }))) {
            var preview = await previews.ExecuteAsync("bearer-test", JsonSerializer.SerializeToElement(new {
                schemaVersion = 1, operation = "invitePreview", data = new { roomId = "one", invitationId = "invitation-1" }
            }), default);
            Check(preview.Status == "resolved" && preview.Preview?.RoomId == "one" && preview.Directory == null, "Preview does not change membership.");
            var missing = await previews.ExecuteAsync("bearer-test", JsonSerializer.SerializeToElement(new {
                schemaVersion = 1, operation = "invitePreview", data = new { roomId = "one", invitationId = "missing" }
            }), default);
            Check(missing.Error == "invitationGone" && previewPosts == 1, "Forged or expired invitation cannot access preview.");
        }
        var projection = PartyRoomReader.Parse(Directory(false));
        Check(projection.ReceivedInvitations.Single().InviterGameId == "Host_CN", "Handle casing preserved.");
        Check(!BridgePayload.From(projection).GetRawText().Contains("private-"), "Invitations strip raw account identifiers.");
        var requests = new List<string>();
        using var reader = new PartyRoomReader(new Uri("https://relay.example.test"), new Handler(request => {
            requests.Add(request.Method.Method + " " + request.RequestUri!.AbsolutePath);
            if (request.RequestUri.AbsolutePath == "/api/friends") {
                Check(request.RequestUri.Query == "?includePresence=false", "No unsolicited friend presence sharing.");
                return Ok(JsonSerializer.SerializeToUtf8Bytes(new { friends = new[] {
                    new { user = new { accountId = "private-target", callsign = "好友", gameId = "Friend_CN", relationshipState = "friend" } },
                    new { user = new { accountId = "private-member", callsign = "房内成员", gameId = "Member_CN", relationshipState = "friend" } }
                } }));
            }
            if (request.Method == HttpMethod.Get) return Ok(Directory(true));
            using var body = JsonDocument.Parse(request.Content!.ReadAsStringAsync().GetAwaiter().GetResult());
            Check(body.RootElement.GetProperty("targetAccountId").GetString() == "private-target", "Opaque target resolves only in Host.");
            return Ok(Encoding.UTF8.GetBytes("{\"status\":\"already_invited\",\"error\":null}"));
        }));
        JsonElement Command(string operation, object data) => JsonSerializer.SerializeToElement(new { schemaVersion = 1, operation, data });
        var targets = await reader.ExecuteAsync("bearer-test", Command("inviteTargets", new { roomId = "one" }), default);
        Check(targets.Targets.Length == 1 && targets.Targets[0].TargetRef != "private-target", "Exclude room members; only scoped opaque refs reach Flutter.");
        Check(targets.Targets[0].AlreadyInvited, "Existing outgoing invitations disable repeated invitation UI.");
        var invited = await reader.ExecuteAsync("bearer-test", Command("invite", new { roomId = "one", targetRef = targets.Targets[0].TargetRef }), default);
        Check(invited.Status == "invited" && requests.Count(item => item.StartsWith("POST")) == 1, "Already invited is successful and never retried.");
        var count = requests.Count;
        var forged = await reader.ExecuteAsync("different-account-bearer", Command("invite", new { roomId = "one", targetRef = targets.Targets[0].TargetRef }), default);
        Check(forged.Error == "targetGone" && requests.Skip(count).All(item => item.StartsWith("GET")), "Ref cannot transfer to another authenticated account.");
        foreach (var operation in new[] { "inviteJoin", "inviteDecline", "inviteRevoke" }) {
            var posts = 0;
            using var actions = new PartyRoomReader(new Uri("https://relay.example.test"), new Handler(request => {
                if (request.Method == HttpMethod.Get) return Ok(Directory(operation == "inviteRevoke"));
                posts++;
                using var body = JsonDocument.Parse(request.Content!.ReadAsStringAsync().GetAwaiter().GetResult());
                Check(body.RootElement.GetProperty("invitationId").GetString() == "invitation-1", "Invitation identity preserved.");
                var status = operation == "inviteJoin" ? "joined" : operation == "inviteDecline" ? "declined" : "revoked";
                return Ok(JsonSerializer.SerializeToUtf8Bytes(new { status }));
            }));
            var result = await actions.ExecuteAsync("bearer-test", Command(operation, new { roomId = "one", invitationId = "invitation-1" }), default);
            Check(result.Directory is not null && posts == 1, "Invitation action writes once and refreshes.");
            var expired = await actions.ExecuteAsync("bearer-test", Command(operation, new { roomId = "one", invitationId = "missing" }), default);
            Check(expired.Error == "invitationGone" && posts == 1, "Missing invitation is rejected before a write.");
        }
    }
    private static HttpResponseMessage Ok(byte[] data) => new(HttpStatusCode.OK) { Content = new ByteArrayContent(data) };
    private static void Check(bool value, string reason) { if (!value) throw new Exception(reason); }
    private sealed class Handler(Func<HttpRequestMessage, HttpResponseMessage> send) : HttpMessageHandler {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) => Task.FromResult(send(request));
    }
}
