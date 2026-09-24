using System.Collections.Concurrent;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using StarBridge.Core.FleetAnnouncements;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Communities;

internal sealed partial class CommunityClient
{
    private sealed record AnnouncementWriteResult(string Status, string? Error = null, long? Revision = null);
    private sealed record AnnouncementAttempt(string Fingerprint, AnnouncementWriteResult Result, DateTimeOffset CreatedAt);
    private sealed record AnnouncementIntent(string TargetRef, string RequestId, string Action,
        string? AnnouncementRef, string? Title, string? Content);
    private readonly ConcurrentDictionary<string, AnnouncementAttempt> _announcementAttempts = new();

    internal async Task<object> ManageAnnouncementsAsync(string bearer, JsonElement body, string scope,
        Action current, CancellationToken token)
    {
        var intent = ParseAnnouncementIntent(body);
        var fingerprint = Convert.ToHexString(SHA256.HashData(JsonSerializer.SerializeToUtf8Bytes(new
            { intent.Action, intent.AnnouncementRef, intent.Title, intent.Content }, AnnouncementJson)));
        object Receipt(AnnouncementWriteResult result) => new { schemaVersion = 1, targetRef = intent.TargetRef,
            requestId = intent.RequestId, action = intent.Action, status = result.Status, error = result.Error, revision = result.Revision };
        if (!await _write.WaitAsync(0, token)) return Receipt(new("rejected", "busy"));
        var sent = false;
        try
        {
            current();
            var target = Resolve(intent.TargetRef, scope, allowWpfS2: true);
            var key = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(scope + "\0" + target.Code + "\0" + intent.RequestId))).ToLowerInvariant();
            // Repeated bridge delivery must not replay even an uncertain POST.
            if (_announcementAttempts.TryGetValue(key, out var prior))
                return Receipt(prior.Fingerprint == fingerprint ? prior.Result : new("rejected", "intentConflict"));
            AnnouncementTarget? entry = null;
            if (intent.AnnouncementRef is not null)
            {
                if (!_announcementTargets.TryGetValue(intent.AnnouncementRef, out entry) || entry.Scope != scope
                    || entry.Code != target.Code || entry.Expires <= DateTimeOffset.UtcNow)
                    return Receipt(new("rejected", "refreshRequired"));
                if (entry.Record.State != "published") return Receipt(new("rejected", "announcementsChanged"));
            }
            foreach (var old in _announcementAttempts.Where(p => p.Value.Result.Status != "unknown"
                         && p.Value.CreatedAt < DateTimeOffset.UtcNow.AddMinutes(-10)).ToArray())
                _announcementAttempts.TryRemove(old.Key, out _);
            if (_announcementAttempts.Count >= 2048) return Receipt(new("rejected", "refreshRequired"));
            object command = intent.Action switch
            {
                "publish" => new FleetAnnouncementPublishRequestContract(target.Code, intent.Title, intent.Content, key),
                "edit" => new FleetAnnouncementEditRequestContract(target.Code, entry!.Record.Id, entry.Record.Revision, intent.Title, intent.Content, key),
                _ => new FleetAnnouncementWithdrawRequestContract(target.Code, entry!.Record.Id, entry.Record.Revision, key),
            };
            using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
            deadline.CancelAfter(TimeSpan.FromSeconds(12));
            long? beforeRevision = null;
            if (target.WpfS2ViewerId is not null)
            {
                var before = await WpfS2AnnouncementPage(bearer, target, 0, null, null, deadline.Token);
                current();
                if (!before.GetProperty("canManage").GetBoolean()) return Receipt(new("rejected", "notAllowed"));
                beforeRevision = AnnouncementRevision(before, "revision");
                if (entry is not null)
                {
                    var active = before.GetProperty("current");
                    if (active.ValueKind == JsonValueKind.Null) return Receipt(new("rejected", "announcementsChanged"));
                    var record = Announcement(active, target.Code, false);
                    if (record.Id != entry.Record.Id || record.Revision != entry.Record.Revision)
                        return Receipt(new("rejected", "announcementsChanged"));
                }
            }
            using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(_origin,
                "/api/fleets/announcements/" + intent.Action + (target.WpfS2ViewerId is null ? "?view=client" : ""))) { Content = JsonContent.Create(command) };
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
            current(); deadline.Token.ThrowIfCancellationRequested();
            _announcementAttempts[key] = new(fingerprint, new("unknown", "outcomeUnknown"), DateTimeOffset.UtcNow);
            sent = true;
            using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, deadline.Token);
            current();
            AnnouncementWriteResult result;
            if (response.StatusCode != HttpStatusCode.OK)
            {
                result = response.StatusCode switch
                {
                    HttpStatusCode.BadRequest => new("rejected", "dataInvalid"),
                    HttpStatusCode.Unauthorized => new("rejected", "identityUnavailable"),
                    HttpStatusCode.Forbidden => new("rejected", "notAllowed"),
                    HttpStatusCode.NotFound => new("rejected", "refreshRequired"),
                    HttpStatusCode.Conflict => new("rejected", "announcementsChanged"),
                    HttpStatusCode.TooManyRequests => new("rejected", "rateLimited"),
                    _ => new("unknown", "outcomeUnknown"),
                };
            }
            else
            {
                using var stream = await response.Content.ReadAsStreamAsync(deadline.Token);
                using var buffer = new MemoryStream();
                var chunk = new byte[4096];
                int count;
                while ((count = await stream.ReadAsync(chunk, deadline.Token)) > 0)
                {
                    if (buffer.Length + count > (target.WpfS2ViewerId is null ? 16 * 1024 : 32 * 1024 * 1024)) throw Invalid();
                    buffer.Write(chunk, 0, count);
                }
                using var document = JsonDocument.Parse(buffer.ToArray());
                var root = document.RootElement;
                AnnouncementObject(root);
                var status = Text(root, "status", 16);
                var expectedStatus = intent.Action switch { "publish" => "published", "edit" => "edited", _ => "withdrawn" };
                if (target.WpfS2ViewerId is not null)
                {
                    if (status != expectedStatus && status != "duplicate" || Optional(root, "error", 512) is not null) throw Invalid();
                    var timeline = root.GetProperty("timeline");
                    _ = ProjectWpfS2Announcements(timeline, target);
                    var timelineRevision = AnnouncementRevision(timeline, "revision");
                    var changed = intent.Action == "withdraw"
                        ? Rows(timeline, "history", 100).SingleOrDefault(x => Text(x, "id", 128) == entry!.Record.Id)
                        : timeline.GetProperty("current");
                    if (changed.ValueKind is not JsonValueKind.Object ||
                        timelineRevision <= 0 || status != "duplicate" && timelineRevision <= beforeRevision ||
                        entry is not null && (Text(changed, "id", 128) != entry.Record.Id ||
                            AnnouncementRevision(changed, "revision") <= entry.Record.Revision) ||
                        Text(changed.GetProperty("lastEditor"), "accountId", 512) != target.WpfS2ViewerId ||
                        intent.Action == "withdraw" && !Text(changed, "state", 16).Equals("Withdrawn", StringComparison.OrdinalIgnoreCase) ||
                        intent.Action != "withdraw" && (Text(changed, "title", 48) != intent.Title || Text(changed, "content", 1200, true) != intent.Content)) throw Invalid();
                    result = new("accepted", Revision: timelineRevision);
                }
                else
                {
                    var id = Text(root, "announcementId", 128);
                    var revision = AnnouncementRevision(root, "revision");
                    if (Number(root, "schemaVersion", 1, 1) != 1 || Number(root, "membershipModelVersion", 2, 2) != 2
                        || status != expectedStatus && status != "duplicate" || string.IsNullOrWhiteSpace(id)
                        || entry is not null && id != entry.Record.Id || revision <= 0
                        || entry is not null && status != "duplicate" && revision <= entry.TimelineRevision
                        || Optional(root, "error", 512) is not null) throw Invalid();
                    result = new("accepted", Revision: revision);
                }
            }
            deadline.Token.ThrowIfCancellationRequested(); current();
            _announcementAttempts[key] = new(fingerprint, result, DateTimeOffset.UtcNow);
            return Receipt(result);
        }
        catch (Exception e) when (e is HttpRequestException or IOException or OperationCanceledException or JsonException
            or InvalidOperationException or KeyNotFoundException or FormatException or OverflowException
            or AccountBridgeHostException or StarBridge.NativeBridge.BridgeStaleGenerationException)
        {
            return Receipt(new(sent ? "unknown" : "rejected", sent ? "outcomeUnknown" : "refreshRequired"));
        }
        finally { _write.Release(); }
    }

    private static AnnouncementIntent ParseAnnouncementIntent(JsonElement body)
    {
        try
        {
            Validate(body, "targetRef", "requestId", "action", "announcementRef", "title", "content");
            var reference = Text(body, "targetRef", 32);
            var requestId = Text(body, "requestId", 32);
            var action = Text(body, "action", 16);
            var announcementRef = Optional(body, "announcementRef", 32);
            if (!LowerHex(reference, 32) || !LowerHex(requestId, 32) || action is not ("publish" or "edit" or "withdraw")
                || action == "publish" && announcementRef is not null
                || action != "publish" && (announcementRef is null || !LowerHex(announcementRef, 32))) throw Invalid();
            if (action == "withdraw")
            {
                if (Optional(body, "title", 48) is not null || Optional(body, "content", 1200) is not null) throw Invalid();
                return new(reference, requestId, action, announcementRef, null, null);
            }
            var normalized = FleetAnnouncementPolicy.Normalize(Text(body, "title", 48), Text(body, "content", 1200, true));
            if (normalized.Error is not null) throw Invalid();
            return new(reference, requestId, action, announcementRef, normalized.Title, normalized.Content);
        }
        catch (Exception e) when (e is InvalidOperationException or KeyNotFoundException or FormatException or OverflowException or JsonException)
        { throw Invalid(); }
    }
}
