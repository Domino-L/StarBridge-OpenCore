using System.Globalization;
using System.Text.Json;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Communities;

internal sealed partial class CommunityClient
{
    // Read only the existing authorized list; never request author proofs,
    // avatars, details or Flutter announcementRef addresses for observations.
    private async Task<CommunityNotificationAnnouncements?> NotificationAnnouncements(
        string bearer, string code, bool wpf, bool official, Action current, CancellationToken token,
        CancellationToken domainToken = default)
    {
        if (domainToken.IsCancellationRequested) return null;
        using var budget = CancellationTokenSource.CreateLinkedTokenSource(token, domainToken);
        budget.CancelAfter(TimeSpan.FromSeconds(2));
        try {
            var entries = new List<CommunityNotificationAnnouncement>();
            long? revision = null;
            int? total = null;
            DateTimeOffset? server = null;
            CommunityNotificationAnnouncement? active = null;
            var offset = 0;
            do {
                var path = (official ? "/api/official-fleets" : "/api/fleets") + "/announcements?fleetCode=" + Uri.EscapeDataString(code);
                if (!wpf) path += "&view=client&offset=" + offset.ToString(CultureInfo.InvariantCulture) +
                    (revision is null ? "" : "&expectedRevision=" + revision.Value.ToString(CultureInfo.InvariantCulture));
                var page = await AnnouncementJsonAsync(bearer, path, budget.Token, wpf ? 32 * 1024 * 1024 : 400 * 1024);
                current(); token.ThrowIfCancellationRequested();
                if (wpf) {
                    AnnouncementObject(page);
                    if (!Text(page, "fleetCode", 256).Equals(code, StringComparison.OrdinalIgnoreCase)) throw Invalid();
                } else CheckAnnouncementRoot(page, code);
                var version = AnnouncementRevision(page, "revision");
                if (revision != null && version != revision) throw Invalid();
                revision = version;
                var observed = DateTimeOffset.Parse(Timestamp(page, "refreshedAt") ?? throw Invalid());
                server ??= observed;
                if (observed < server) throw Invalid();
                CommunityNotificationAnnouncement Entry(JsonElement wrapper, bool published) {
                    AnnouncementObject(wrapper);
                    var row = wpf ? wrapper : wrapper.GetProperty("announcement");
                    AnnouncementObject(row);
                    var id = Text(row, "id", 128);
                    var state = Text(row, "state", 16).ToLowerInvariant();
                    DateTimeOffset Date(string key) => row.TryGetProperty(key, out var value) && value.ValueKind == JsonValueKind.String &&
                        DateTimeOffset.TryParse(value.GetString(), CultureInfo.InvariantCulture, DateTimeStyles.None, out var date) ? date : default;
                    var at = Date("publishedAt");
                    var updated = Date("updatedAt");
                    if (at == default || updated == default || at > updated || updated > observed) at = default;
                    if (string.IsNullOrWhiteSpace(id) || id.Any(char.IsControl) ||
                        !Text(row, "fleetCode", 256).Equals(code, StringComparison.OrdinalIgnoreCase) ||
                        state is not ("published" or "archived" or "withdrawn") || published != (state == "published") ||
                        Number(row, "revision", 1, int.MaxValue) > version) throw Invalid();
                    return new(id, published, at);
                }
                var currentEntry = page.GetProperty("current").ValueKind == JsonValueKind.Null ? null : Entry(page.GetProperty("current"), true);
                if (offset == 0) { active = currentEntry; if (active != null) entries.Add(active); }
                else if (active != currentEntry) throw Invalid();
                var history = Rows(page, "history", wpf ? 100 : 20);
                entries.AddRange(history.Select(row => Entry(row, false)));
                if (entries.Count > 100 || entries.Select(e => e.Id).Distinct(StringComparer.OrdinalIgnoreCase).Count() != entries.Count) throw Invalid();
                if (wpf) break;
                var count = Number(page, "totalHistoryCount", 0, active == null ? 100 : 99);
                if (total != null && total != count || Number(page, "offset", 0, 100) != offset ||
                    offset > count || history.Length != Math.Min(20, count - offset)) throw Invalid();
                total = count;
                var next = page.GetProperty("next").ValueKind == JsonValueKind.Null ? (int?)null : Number(page, "next", 0, 100);
                var expected = offset + history.Length < count ? (int?)(offset + history.Length) : null;
                if (next != expected) throw Invalid();
                if (next is null) break;
                offset = next.Value;
            } while (offset <= 100);
            current(); token.ThrowIfCancellationRequested();
            return new(server!.Value, entries.ToArray());
        } catch (OperationCanceledException) when (!token.IsCancellationRequested) { return null; }
        catch (Exception e) when (e is AccountBridgeHostException or HttpRequestException or JsonException or
            InvalidOperationException or KeyNotFoundException or FormatException or OverflowException or InvalidDataException) {
            return null;
        }
    }
    private string? NotificationAnnouncementTarget(string code, string scope, string name, string? viewer = null, bool official = false) {
        var now = _targetClock.GetUtcNow();
        var reference = _targets.FirstOrDefault(p => p.Value.Code == code && p.Value.Scope == scope &&
            p.Value.WpfS2ViewerId == viewer && p.Value.OfficialFleet == official && p.Value.Expires > now).Key;
        if (reference == null) {
            if (_targets.Count >= 4000) return null;
            reference = Guid.NewGuid().ToString("N");
        }
        _targets.AddOrUpdate(reference, new Target(code, scope, now.AddMinutes(5), name, viewer, OfficialFleet: official),
            (_, existing) => existing with { Expires = now.AddMinutes(5) });
        return reference;
    }
}
