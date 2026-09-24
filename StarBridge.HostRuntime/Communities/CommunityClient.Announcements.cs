using System.Collections.Concurrent;
using System.Globalization;
using System.Security.Cryptography;
using System.Text.Encodings.Web;
using System.Text.Json;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Communities;

internal sealed partial class CommunityClient
{
    private sealed record AnnouncementPerson(string AccountId, string Callsign, string GameId, string RoleTitle,
        string RoleColor, bool HasAvatar, string? Avatar);
    private sealed record AnnouncementRecord(string Id, string Code, string Title, string Content, string State, int Revision,
        string PublishedAt, string UpdatedAt, string? ArchivedAt, string? WithdrawnAt,
        AnnouncementPerson Author, AnnouncementPerson Editor);
    private sealed record AnnouncementTarget(string Code, string Scope, long TimelineRevision,
        AnnouncementRecord Record, DateTimeOffset Expires);
    private readonly ConcurrentDictionary<string, AnnouncementTarget> _announcementTargets = new();
    private static readonly JsonSerializerOptions AnnouncementJson = new(JsonSerializerDefaults.Web)
        { Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping };
    private const int AnnouncementChunkBytes = 192 * 1024;

    internal Task<object> ReadAnnouncementsAsync(string bearer, JsonElement body, string scope, Action current, CancellationToken token) =>
        GuardWorkspace(async () =>
        {
            Validate(body, "targetRef", "offset", "expectedRevision");
            var reference = Text(body, "targetRef", 32);
            var offset = Number(body, "offset", 0, 100);
            long? expected = body.TryGetProperty("expectedRevision", out var requested) && requested.ValueKind != JsonValueKind.Null
                ? AnnouncementRevision(body, "expectedRevision") : null;
            if (offset > 0 && expected is null) throw Invalid();
            current();
        var target = ResolveForRead(reference, scope, allowWpfS2: true);
            var path = "/api/fleets/announcements?fleetCode=" + Uri.EscapeDataString(target.Code)
                + "&view=client&offset=" + offset.ToString(CultureInfo.InvariantCulture)
                + (expected is null ? "" : "&expectedRevision=" + expected.Value.ToString(CultureInfo.InvariantCulture));
            var root = target.WpfS2ViewerId is not null
                ? await WpfS2AnnouncementPage(bearer, target, offset, expected, null, token)
                : await AnnouncementJsonAsync(bearer, path, token, 400 * 1024);
            current(); token.ThrowIfCancellationRequested();
            CheckAnnouncementRoot(root, target.Code, target.WpfS2ViewerId is null ? 2 : 1);
            var revision = AnnouncementRevision(root, "revision");
            if (expected is not null && revision != expected || Number(root, "offset", 0, 100) != offset) throw Invalid();
            var canManage = root.GetProperty("canManage").GetBoolean();
            var total = Number(root, "totalHistoryCount", 0, 100);
            var next = root.GetProperty("next").ValueKind == JsonValueKind.Null ? (int?)null : Number(root, "next", 0, 100);
            var refreshedAt = Timestamp(root, "refreshedAt") ?? throw Invalid();
            var active = root.GetProperty("current").ValueKind == JsonValueKind.Null ? null : Announcement(root.GetProperty("current"), target.Code, false);
            var history = Rows(root, "history", 20).Select(row => Announcement(row, target.Code, false)).ToArray();
            if (offset > total || history.Length != Math.Min(20, total - offset)
                || next != (offset + history.Length < total ? offset + history.Length : null)
                || active is not null && (active.State != "published" || total > 99)
                || history.Any(item => item.State == "published")) throw Invalid();
            var records = active is null ? history : [active, .. history];
            if (records.Select(item => item.Id).Distinct(StringComparer.OrdinalIgnoreCase).Count() != records.Length
                || records.Any(item => item.Revision > revision)) throw Invalid();
            for (var i = 1; i < history.Length; i++)
                if (DateTimeOffset.Parse(history[i - 1].UpdatedAt) < DateTimeOffset.Parse(history[i].UpdatedAt)
                    || DateTimeOffset.Parse(history[i - 1].UpdatedAt) == DateTimeOffset.Parse(history[i].UpdatedAt)
                    && StringComparer.Ordinal.Compare(history[i - 1].Id, history[i].Id) >= 0) throw Invalid();

            var pending = new Dictionary<string, AnnouncementTarget>();
            var members = new Dictionary<string, MemberTarget>();
            object Person(AnnouncementPerson person)
            {
                string? memberRef = null;
                if (!string.IsNullOrWhiteSpace(person.AccountId) && person.AccountId != "legacy")
                {
                    var memberId = "account:" + person.AccountId;
                    memberRef = members.FirstOrDefault(p => p.Value.MemberId == memberId).Key
                        ?? _memberTargets.FirstOrDefault(p => p.Value.MemberId == memberId && p.Value.Code == target.Code
                            && p.Value.Scope == scope && p.Value.Expires > DateTimeOffset.UtcNow).Key
                        ?? Guid.NewGuid().ToString("N");
                    members[memberRef] = new(memberId, target.Code, scope, DateTimeOffset.UtcNow.AddMinutes(5));
                }
                return new { memberRef, callsign = person.Callsign, gameId = person.GameId, roleTitle = person.RoleTitle,
                    roleColor = person.RoleColor, hasAvatar = person.HasAvatar };
            }
            object View(AnnouncementRecord item)
            {
                var id = _announcementTargets.FirstOrDefault(p => p.Value.Code == target.Code && p.Value.Scope == scope
                    && p.Value.TimelineRevision == revision && p.Value.Record == item && p.Value.Expires > DateTimeOffset.UtcNow).Key
                    ?? Guid.NewGuid().ToString("N");
                pending[id] = new(target.Code, scope, revision, item, DateTimeOffset.UtcNow.AddMinutes(5));
                return new { announcementRef = id, title = item.Title, content = item.Content, state = item.State, revision = item.Revision,
                    publishedAt = item.PublishedAt, updatedAt = item.UpdatedAt, archivedAt = item.ArchivedAt, withdrawnAt = item.WithdrawnAt,
                    author = Person(item.Author), editor = Person(item.Editor) };
            }
            var activeView = active is null ? null : View(active);
            var historyViews = history.Select(View).ToArray();
            foreach (var old in _announcementTargets.Where(p => p.Value.Expires <= DateTimeOffset.UtcNow).ToArray()) _announcementTargets.TryRemove(old.Key, out _);
            foreach (var old in _memberTargets.Where(p => p.Value.Expires <= DateTimeOffset.UtcNow).ToArray()) _memberTargets.TryRemove(old.Key, out _);
            if (_announcementTargets.Count + pending.Count(p => !_announcementTargets.ContainsKey(p.Key)) > 4000
                || _memberTargets.Count + members.Count(p => !_memberTargets.ContainsKey(p.Key)) > 10000)
                throw new AccountBridgeHostException("communities.refreshRequired");
            current(); token.ThrowIfCancellationRequested();
            foreach (var pair in pending) _announcementTargets[pair.Key] = pair.Value;
            foreach (var pair in members) _memberTargets[pair.Key] = pair.Value;
            RenewTarget(reference, target, token);
            return new { schemaVersion = 1, targetRef = reference, revision, canManage, current = activeView, history = historyViews,
                offset, next, totalHistoryCount = total, refreshedAt };
        });

    internal Task<object> ReadAnnouncementDetailAsync(string bearer, JsonElement body, string scope, Action current, CancellationToken token) =>
        GuardWorkspace(async () =>
        {
            Validate(body, "targetRef", "announcementRef", "offset", "version");
            var reference = Text(body, "targetRef", 32);
            var announcementRef = Text(body, "announcementRef", 32);
            var offset = Number(body, "offset", 0, 1600 * 1024);
            var version = Optional(body, "version", 64);
            if (offset % AnnouncementChunkBytes != 0 || offset > 0 && version is null
                || version is not null && (version.Length != 64 || version.Any(c => !char.IsAsciiHexDigit(c) || char.IsUpper(c)))) throw Invalid();
            current();
            var target = Resolve(reference, scope, allowWpfS2: true);
            if (!_announcementTargets.TryGetValue(announcementRef, out var entry) || entry.Code != target.Code
                || entry.Scope != scope || entry.Expires <= DateTimeOffset.UtcNow)
                throw new AccountBridgeHostException("communities.refreshRequired");
            var root = target.WpfS2ViewerId is not null
                ? await WpfS2AnnouncementPage(bearer, target, 0, entry.TimelineRevision, entry.Record.Id, token)
                : await AnnouncementJsonAsync(bearer, "/api/fleets/announcements?fleetCode=" + Uri.EscapeDataString(target.Code)
                + "&view=detail&announcementId=" + Uri.EscapeDataString(entry.Record.Id)
                + "&expectedRevision=" + entry.TimelineRevision.ToString(CultureInfo.InvariantCulture), token, 1600 * 1024);
            current(); token.ThrowIfCancellationRequested();
            CheckAnnouncementRoot(root, target.Code, target.WpfS2ViewerId is null ? 2 : 1);
            if (AnnouncementRevision(root, "revision") != entry.TimelineRevision) throw Invalid();
            var canManage = root.GetProperty("canManage").GetBoolean();
            var detail = Announcement(root.GetProperty("entry"), target.Code, true);
            if ((detail with { Author = detail.Author with { Avatar = null }, Editor = detail.Editor with { Avatar = null } }) != entry.Record)
                throw new AccountBridgeHostException("communities.announcementsChanged");
            var bytes = JsonSerializer.SerializeToUtf8Bytes(new { authorAvatarImageData = detail.Author.Avatar,
                editorAvatarImageData = detail.Editor.Avatar }, AnnouncementJson);
            if (bytes.Length > 1600 * 1024 || offset >= bytes.Length) throw Invalid();
            var hash = Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();
            if (version is not null && version != hash) throw new AccountBridgeHostException("communities.announcementsChanged");
            var size = Math.Min(AnnouncementChunkBytes, bytes.Length - offset);
            int? next = offset + size < bytes.Length ? offset + size : null;
            current(); token.ThrowIfCancellationRequested();
            return new { schemaVersion = 1, targetRef = reference, announcementRef, canManage, offset, next,
                totalBytes = bytes.Length, version = hash, data = Convert.ToBase64String(bytes, offset, size) };
        });

    private async Task<JsonElement> AnnouncementJsonAsync(string bearer, string path, CancellationToken token, int maximum)
    {
        try { return await WorkspaceJson(bearer, path, token, maximum); }
        catch (AccountBridgeHostException e) when (e.Code == "communities.mediaChanged")
        { throw new AccountBridgeHostException("communities.announcementsChanged"); }
    }

    private static void CheckAnnouncementRoot(JsonElement root, string code, int membershipVersion = 2)
    {
        AnnouncementObject(root);
        if (Number(root, "schemaVersion", 1, 1) != 1 || Number(root, "membershipModelVersion", membershipVersion, membershipVersion) != membershipVersion
            || !Text(root, "fleetCode", 256).Equals(code, StringComparison.OrdinalIgnoreCase)) throw Invalid();
    }
    private static long AnnouncementRevision(JsonElement root, string key)
    {
        var value = root.GetProperty(key).GetInt64();
        return value >= 0 ? value : throw Invalid();
    }
    private static void AnnouncementObject(JsonElement value)
    {
        if (value.ValueKind != JsonValueKind.Object || value.EnumerateObject().Select(p => p.Name).Distinct().Count()
            != value.EnumerateObject().Count()) throw Invalid();
    }
    private static AnnouncementRecord Announcement(JsonElement wrapper, string code, bool detail)
    {
        AnnouncementObject(wrapper);
        var row = wrapper.GetProperty("announcement");
        AnnouncementObject(row);
        var state = Text(row, "state", 16).ToLowerInvariant();
        var id = Text(row, "id", 128);
        var title = Text(row, "title", 48);
        if (string.IsNullOrWhiteSpace(id) || string.IsNullOrWhiteSpace(title) || state is not ("published" or "archived" or "withdrawn")
            || !Text(row, "fleetCode", 256).Equals(code, StringComparison.OrdinalIgnoreCase)) throw Invalid();
        return new(id, code, title, Text(row, "content", 1200, true), state, Number(row, "revision", 1, int.MaxValue),
            Timestamp(row, "publishedAt") ?? throw Invalid(), Timestamp(row, "updatedAt") ?? throw Invalid(),
            Timestamp(row, "archivedAt"), Timestamp(row, "withdrawnAt"),
            AnnouncementAuthor(row.GetProperty("author"), wrapper.GetProperty("authorHasAvatar").GetBoolean(), detail),
            AnnouncementAuthor(row.GetProperty("lastEditor"), wrapper.GetProperty("lastEditorHasAvatar").GetBoolean(), detail));
    }
    private static AnnouncementPerson AnnouncementAuthor(JsonElement row, bool hasAvatar, bool detail)
    {
        AnnouncementObject(row);
        var color = Text(row, "roleColor", 7);
        if (color.Length != 7 || color[0] != '#' || color.Skip(1).Any(c => !char.IsAsciiHexDigit(c))) throw Invalid();
        var source = Optional(row, "avatarImageData", 720 * 1024);
        if (!detail && !string.IsNullOrEmpty(source) || detail && hasAvatar != !string.IsNullOrEmpty(source)) throw Invalid();
        return new(Text(row, "accountId", 256), Text(row, "callsign", 256), Text(row, "gameId", 256),
            Text(row, "roleTitle", 256), color, hasAvatar, detail ? AnnouncementAvatar(source) : null);
    }
    private static string? AnnouncementAvatar(string? source)
    {
        if (string.IsNullOrEmpty(source)) return null;
        if (source.StartsWith("data:", StringComparison.Ordinal)) return ChatAvatar(source);
        var bytes = Convert.FromBase64String(source);
        var mime = bytes.AsSpan() switch
        {
            [137, 80, 78, 71, 13, 10, 26, 10, ..] => "image/png", [255, 216, 255, ..] => "image/jpeg",
            [66, 77, ..] => "image/bmp", [71, 73, 70, 56, 55 or 57, 97, ..] => "image/gif",
            [82, 73, 70, 70, _, _, _, _, 87, 69, 66, 80, ..] => "image/webp", _ => null
        };
        return mime is null ? throw Invalid() : ChatAvatar("data:" + mime + ";base64," + source);
    }
}
