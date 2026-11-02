using System.Text.Json;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Communities;

internal sealed partial class CommunityClient
{
    // The selected announcement surface has one old record. Other observed batches
    // remain bounded without N+1 requests or a second authorization cache.
    private async Task<OfficialAnnouncementRead> ReauthorizeOfficialAnnouncement(string bearer, Target target,
        OfficialAnnouncementRead read, CancellationToken token)
    {
        if (read.Updates.Length != 1 || !read.Updates[0].Found) return read;
        var observed = read.Updates[0]; var timeline = AnnouncementRevision(read.Page, "revision");
        if (observed.Address.TimelineRevision == timeline) return read;
        var wrappers = Rows(read.Page, "history", 20).ToList();
        if (read.Page.GetProperty("current").ValueKind != JsonValueKind.Null) wrappers.Add(read.Page.GetProperty("current"));
        if (wrappers.Any(wrapper => Text(wrapper.GetProperty("announcement"), "id", 128) == observed.Address.Record.Id)) return read;
        var record = observed.Address.Record; var source = "officialFleet:" + target.Code["OFFICIALFLEET:".Length..];
        // Optional identities may fail; this exact detail's original content admission
        // must succeed. Do not swallow membership/source/read errors as profile failure.
        var root = await OfficialAuthorJson(bearer, "/api/official-fleets/announcements/read", new
        {
            schemaVersion = 2,
            sourceRef = source,
            fleetCode = target.Code,
            mode = "detail",
            expectedRevision = timeline,
            observedAnnouncements = new[] { new { announcementId = record.Id, revision = record.Revision } },
            expectedAuthorIdentityVersion = read.Identities.GetValueOrDefault(record.Author.AccountId)?.IdentityVersion,
            expectedEditorIdentityVersion = read.Identities.GetValueOrDefault(record.Editor.AccountId)?.IdentityVersion
        }, 1600 * 1024, token);
        token.ThrowIfCancellationRequested();
        if (Number(root, "schemaVersion", 2, 2) != 2 || Text(root, "sourceRef", 64) != source) throw Invalid();
        var page = root.GetProperty("page"); CheckAnnouncementRoot(page, target.Code, 2);
        if (AnnouncementRevision(page, "revision") != timeline) throw Invalid();
        if (NeutralOfficialAnnouncement(Announcement(page.GetProperty("entry"), target.Code, true)) != record)
            throw new AccountBridgeHostException("communities.announcementsChanged");
        var ids = new HashSet<string>(StringComparer.Ordinal);
        foreach (var id in new[] { record.Author.AccountId, record.Editor.AccountId }) if (OfficialBid(id)) ids.Add(id);
        var hintValid = TryAuthorRefresh(root, out var upstreamRefresh);
        var fresh = hintValid ? AuthorIdentities(root, ids, detail: true) : new Dictionary<string, OfficialAuthorObservation>();
        var retained = read.Identities.ToDictionary(pair => pair.Key, pair => pair.Value, StringComparer.Ordinal);
        foreach (var id in ids)
        {
            var old = retained.GetValueOrDefault(id); var next = fresh.GetValueOrDefault(id);
            // A later IO may only narrow the first observation, never renew its TTL.
            retained[id] = old?.Current(_targetClock.GetUtcNow()) == true && next?.Current(_targetClock.GetUtcNow()) == true && old.IdentityVersion == next.IdentityVersion
                ? old with { Until = old.Until < next.Until ? old.Until : next.Until }
                : new(next?.State == "hidden" ? "hidden" : "unavailable");
        }
        return read with { RefreshRequired = read.RefreshRequired || upstreamRefresh, Identities = retained, ProvenOffpage = new HashSet<string>(StringComparer.Ordinal) { observed.Reference } };
    }
}