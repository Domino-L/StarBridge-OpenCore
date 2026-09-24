using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.Core.Chat;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Communities;

// Resolved by the owning chat reader, never deserialized directly from Bridge input.
internal sealed record InvitationDeliveryTarget(string Channel, string Id, string Scope, Uri Origin, string DisplayName = "")
{
    [System.Text.Json.Serialization.JsonIgnore]
    public string[] RecipientAccountIds { get; init; } = [];
}
internal sealed record InvitationDeliveryIntent(string RequestId, DateTimeOffset RequestedAt, ChatAttachmentContract Card);
internal sealed record InvitationDeliveryResult(string Status, string? Error = null, string? MessageId = null,
    long? Sequence = null, DateTimeOffset? CreatedAt = null);

internal sealed partial class CommunityClient
{
    internal async Task<InvitationDeliveryResult> DeliverInvitationCardAsync(string bearer, string organizationRef,
        InvitationDeliveryTarget destination, InvitationDeliveryIntent intent, bool confirmOnly, string scope,
        Action current, CancellationToken token)
    {
        static bool Id(string value) => value.Length == 32 && value.All(c => c is >= '0' and <= '9' or >= 'a' and <= 'f');
        InvitationDeliveryResult BeforeSend(string reason) => new(confirmOnly ? "unknown" : "rejected", reason);
        if (!Id(intent.RequestId) || !Id(organizationRef) || destination.Channel is not ("private" or "room")
            || string.IsNullOrWhiteSpace(destination.Id) || destination.Id.Length > 256 || destination.Id.Any(char.IsControl)
            || destination.Scope != scope || destination.Origin.GetLeftPart(UriPartial.Authority) != _origin.GetLeftPart(UriPartial.Authority)
            || !ChatAttachmentPolicy.TryNormalize(intent.Card, out var card, out _) || card?.Kind != ChatAttachmentKinds.FleetInvitation
            || card != intent.Card || intent.RequestedAt > DateTimeOffset.UtcNow.AddMinutes(5)) return BeforeSend("dataInvalid");
        if (!await _write.WaitAsync(0, token)) return BeforeSend("busy");
        var epoch = Interlocked.Read(ref _inviteEpoch);
        var posted = false;
        try
        {
            current();
            var source = Resolve(organizationRef, scope);
            using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
            deadline.CancelAfter(TimeSpan.FromSeconds(12));
            var access = await WorkspaceJson(bearer,
                $"/api/fleets/admissions?code={Uri.EscapeDataString(source.Code)}&section=access&offset=0", deadline.Token, 16 * 1024);
            current();
            if (Number(access, "schemaVersion", 1, 1) != 1 || Number(access, "membershipModelVersion", 2, 2) != 2
                || Text(access, "code", 256) != source.Code || Text(access, "section", 16) != "access") throw Invalid();
            // Old Relay versions may ignore additional POST fields, including ConfirmOnly.
            if (!access.TryGetProperty("inviteDeliveryVersion", out var version) || version.GetInt32() != 1)
                return BeforeSend("unavailable");
            // A lost result may still be confirmed after card-generation permission is removed.
            // Current chat authorization is always checked by the destination route.
            if (!confirmOnly && !access.GetProperty("access").GetProperty("canSendInvitationCard").GetBoolean())
                return BeforeSend("notAllowed");
            var path = destination.Channel == "private" ? "/api/friends/chat/messages?view=client" : "/api/party-rooms/chat?view=client";
            var body = new Dictionary<string, object?>
            {
                [destination.Channel == "private" ? "targetAccountId" : "roomId"] = destination.Id,
                ["text"] = "", ["attachment"] = intent.Card, ["clientMessageId"] = intent.RequestId,
                ["clientRequestedAt"] = intent.RequestedAt, ["confirmOnly"] = confirmOnly
            };
            if (destination.Channel == "private") body["origin"] = "friend_center";
            using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(_origin, path)) { Content = JsonContent.Create(body) };
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
            lock (_inviteGate)
            {
                current(); deadline.Token.ThrowIfCancellationRequested();
                if (epoch != _inviteEpoch) return BeforeSend("identityUnavailable");
                posted = true;
            }
            using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, deadline.Token);
            current();
            if (epoch != Interlocked.Read(ref _inviteEpoch)) return new("unknown", "outcomeUnknown");
            if (response.StatusCode != HttpStatusCode.OK)
            {
                var reason = response.StatusCode switch
                {
                    HttpStatusCode.Unauthorized => "identityUnavailable", HttpStatusCode.Forbidden => "notAllowed",
                    HttpStatusCode.NotFound => "refreshRequired", HttpStatusCode.BadRequest or HttpStatusCode.Conflict => "dataInvalid",
                    HttpStatusCode.TooManyRequests => "rateLimited", _ => "outcomeUnknown"
                };
                return new(confirmOnly || reason == "outcomeUnknown" ? "unknown" : "rejected", reason);
            }
            using var stream = await response.Content.ReadAsStreamAsync(deadline.Token);
            using var buffer = new MemoryStream();
            var chunk = new byte[1024]; int count;
            while ((count = await stream.ReadAsync(chunk, deadline.Token)) > 0)
            {
                if (buffer.Length + count > 4096) throw Invalid();
                buffer.Write(chunk, 0, count);
            }
            using var document = JsonDocument.Parse(buffer.ToArray());
            var root = document.RootElement;
            var names = root.EnumerateObject().Select(field => field.Name).ToArray();
            if (names.Length != 6 || names.Distinct().Count() != 6
                || names.Any(name => name is not ("schemaVersion" or "status" or "requestId" or "messageId" or "sequence" or "createdAt"))
                || Number(root, "schemaVersion", 1, 1) != 1 || Text(root, "requestId", 32) != intent.RequestId) throw Invalid();
            var status = Text(root, "status", 16);
            var message = Optional(root, "messageId", 32);
            long? sequence = root.GetProperty("sequence").ValueKind == JsonValueKind.Null ? null : root.GetProperty("sequence").GetInt64();
            DateTimeOffset? created = root.GetProperty("createdAt").ValueKind == JsonValueKind.Null ? null : root.GetProperty("createdAt").GetDateTimeOffset();
            deadline.Token.ThrowIfCancellationRequested(); current();
            if (epoch != Interlocked.Read(ref _inviteEpoch)) return new("unknown", "outcomeUnknown");
            if (status == "unknown" && message is null && sequence is null && created is null) return new("unknown", "outcomeUnknown");
            if (status != "sent" || message is null || !Id(message) || sequence is null or <= 0 || created is null
                || created > DateTimeOffset.UtcNow.AddMinutes(5)
                || destination.Channel == "private" && message != intent.RequestId) throw Invalid();
            return new("sent", MessageId: message, Sequence: sequence, CreatedAt: created);
        }
        catch (Exception error) when (error is HttpRequestException or IOException or OperationCanceledException or JsonException
            or AccountBridgeHostException or StarBridge.NativeBridge.BridgeStaleGenerationException or InvalidOperationException
            or KeyNotFoundException or FormatException or OverflowException)
        { return posted || confirmOnly ? new("unknown", "outcomeUnknown") : BeforeSend("refreshRequired"); }
        finally { _write.Release(); }
    }
}
