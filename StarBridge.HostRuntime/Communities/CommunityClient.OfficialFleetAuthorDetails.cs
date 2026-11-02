using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.Core.Chat;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Communities;

internal sealed partial class CommunityClient
{
    private static string? ExpectedAuthorVersion(JsonElement body, string name)
    {
        var value = Optional(body, name, 64); if (value is not null && !LowerHex(value, 64)) throw Invalid(); return value;
    }
    private static bool OfficialAuthorDetailOptIn(JsonElement body, Target target, bool announcements)
    {
        if (!body.TryGetProperty("authorIdentitySchemaVersion", out var schema))
        {
            if (body.TryGetProperty("expectedAuthorIdentityVersion", out _) || body.TryGetProperty("expectedEditorIdentityVersion", out _)) throw Invalid(); return false;
        }
        if (schema.ValueKind != JsonValueKind.Number || schema.GetInt32() != 1 || !target.OfficialFleet || target.AuthorIdentitySchemaVersion != 1) throw Invalid();
        _ = ExpectedAuthorVersion(body, "expectedAuthorIdentityVersion"); if (announcements) _ = ExpectedAuthorVersion(body, "expectedEditorIdentityVersion"); return true;
    }
    private async Task<object> ReadOfficialChatAuthorDetail(string bearer, JsonElement body, string targetRef, string messageRef, Target target,
        ChatTarget message, string scope, int offset, string? byteVersion, Action current, CancellationToken token)
    {
        var publicationToken = token; var operationStarted = System.Diagnostics.Stopwatch.GetTimestamp();
        using var diagnostic = new Privacy.OfficialChatAuthorReadObservation("detail", ChatAuthorDiagnostic);
        diagnostic.Requested(OfficialBid(message.SenderId) ? 1 : 0);
        try
        {
            using var operation = CancellationTokenSource.CreateLinkedTokenSource(token); operation.CancelAfter(TimeSpan.FromSeconds(12)); token = operation.Token;
            var expected = ExpectedAuthorVersion(body, "expectedAuthorIdentityVersion");
            var source = "officialFleet:" + target.Code["OFFICIALFLEET:".Length..];
            current(); token.ThrowIfCancellationRequested();
            var root = await OfficialAuthorJson(bearer, "/api/official-fleets/chat/messages/read", new
            {
                schemaVersion = 2,
                sourceRef = source,
                fleetCode = target.Code,
                mode = "detail",
                observedMessages = new[] { new { messageId = message.MessageId, sequence = message.Sequence } },
                expectedAuthorIdentityVersion = expected
            }, 2 * 1024 * 1024, token, chatDiagnostic: diagnostic);
            diagnostic.Raw(root, expected);
            current(); token.ThrowIfCancellationRequested();
            if (Number(root, "schemaVersion", 2, 2) != 2 || Text(root, "sourceRef", 64) != source) throw Invalid();
            var row = root.GetProperty("page"); ChatObject(row);
            if (Text(row, "messageId", 128) != message.MessageId || ChatSequence(row, "sequence", true) != message.Sequence ||
                Text(row, "senderAccountId", 512) != message.SenderId || !Text(row, "channelId", 272).Equals(message.ChannelId, StringComparison.OrdinalIgnoreCase)) throw new AccountBridgeHostException("communities.notFound");
            ChatAttachmentContract? attachment = null;
            if (row.TryGetProperty("attachment", out var raw) && raw.ValueKind != JsonValueKind.Null)
            {
                var value = raw.Deserialize<ChatAttachmentContract>(ChatJson);
                if (!ChatAttachmentPolicy.TryNormalize(value, out attachment, out _) || attachment is not null && attachment.Kind != ChatAttachmentKinds.OverlayPreset) throw Invalid();
            }
            var ids = new HashSet<string>(StringComparer.Ordinal); if (OfficialBid(message.SenderId)) ids.Add(message.SenderId);
            var hintValid = TryAuthorRefresh(root, out var refresh);
            if (!hintValid) diagnostic.ParseFailed();
            var identities = hintValid ? AuthorIdentities(root, ids, detail: true, diagnostic: diagnostic, preserveLapsedVisible: true) : new Dictionary<string, OfficialAuthorObservation>();
            var observation = identities.GetValueOrDefault(message.SenderId) ?? new OfficialAuthorObservation("unavailable");
            refresh = refresh || !observation.Current(_targetClock.GetUtcNow()) || observation.IdentityVersion != expected;
            if (observation.State != "hidden" && observation.IdentityVersion != expected) observation = new("unavailable");
            if (message.SenderRef is null) throw new AccountBridgeHostException("communities.refreshRequired");
            var captured = new Dictionary<string, OfficialAuthorObservation>(StringComparer.Ordinal) { { message.SenderId, observation } };
            return OfficialAuthorProjectionResult(captured, retired =>
            {
                var authorObservation = retired.Contains(message.SenderId) ? new OfficialAuthorObservation("unavailable") : observation;
                var currentVisible = authorObservation.Current(_targetClock.GetUtcNow());
                // The matching response is display data; only Current may admit its proof.
                var bytes = JsonSerializer.SerializeToUtf8Bytes(new { avatarImageData = authorObservation.State == "visible" ? authorObservation.Avatar : null, attachment }, ChatJson);
                var author = new JsonObject { ["senderRef"] = message.SenderRef }; ApplyOfficialPerson(author, authorObservation, preserveLapsedVisible: true);
                return OfficialDetailChunk(targetRef, messageRef, null, offset, byteVersion, bytes, author, null, refresh || !currentVisible, current, publicationToken);
            }, current, publicationToken, operationStarted, targetRef, preserveLapsedVisible: true);
        }
        catch (Exception error) { diagnostic.Fail(error); throw; }
    }
    private JsonObject OfficialDetailChunk(string targetRef, string? messageRef, string? announcementRef, int offset, string? expectedByteVersion, byte[] bytes,
            JsonObject author, JsonObject? editor, bool refresh, Action current, CancellationToken token)
    {
        var maximum = announcementRef is null ? 2 * 1024 * 1024 : 1600 * 1024;
        if (bytes.Length > maximum || offset >= bytes.Length && !refresh) throw Invalid();
        var hash = Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();
        if (expectedByteVersion is not null && expectedByteVersion != hash && !refresh)
            throw new AccountBridgeHostException(announcementRef is null ? "communities.mediaChanged" : "communities.announcementsChanged");
        var size = offset >= bytes.Length ? 0 : Math.Min(ChatDetailChunkBytes, bytes.Length - offset);
        int? next = offset + size < bytes.Length ? offset + size : null;
        var result = new JsonObject
        {
            ["schemaVersion"] = 1,
            ["targetRef"] = targetRef,
            ["offset"] = offset,
            ["next"] = next,
            ["totalBytes"] = bytes.Length,
            ["version"] = hash,
            ["data"] = Convert.ToBase64String(bytes, Math.Min(offset, bytes.Length), size),
            ["authorRefreshRequired"] = refresh,
            ["author"] = author
        };
        if (messageRef is not null) result["messageRef"] = messageRef;
        if (announcementRef is not null) { result["announcementRef"] = announcementRef; result["canManage"] = false; result["editor"] = editor; }
        token.ThrowIfCancellationRequested(); current(); return result;
    }
}
