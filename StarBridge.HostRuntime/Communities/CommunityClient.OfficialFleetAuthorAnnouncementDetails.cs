using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Communities;

internal sealed partial class CommunityClient
{
    private async Task<object> ReadOfficialAnnouncementAuthorDetail(string bearer, JsonElement body, string targetRef, string announcementRef,
        Target target, AnnouncementTarget entry, string scope, int offset, string? byteVersion, Action current, CancellationToken token)
    {
        var publicationToken = token; var operationStarted = System.Diagnostics.Stopwatch.GetTimestamp();
        using var operation = CancellationTokenSource.CreateLinkedTokenSource(token); operation.CancelAfter(TimeSpan.FromSeconds(12)); token = operation.Token;
        var expectedAuthor = ExpectedAuthorVersion(body, "expectedAuthorIdentityVersion"); var expectedEditor = ExpectedAuthorVersion(body, "expectedEditorIdentityVersion");
        var source = "officialFleet:" + target.Code["OFFICIALFLEET:".Length..];
        current(); token.ThrowIfCancellationRequested();
        var root = await OfficialAuthorJson(bearer, "/api/official-fleets/announcements/read", new
        {
            schemaVersion = 2,
            sourceRef = source,
            fleetCode = target.Code,
            mode = "detail",
            expectedRevision = entry.TimelineRevision,
            observedAnnouncements = new[] { new { announcementId = entry.Record.Id, revision = entry.Record.Revision } },
            expectedAuthorIdentityVersion = expectedAuthor,
            expectedEditorIdentityVersion = expectedEditor
        }, 1600 * 1024, token);
        current(); token.ThrowIfCancellationRequested();
        if (Number(root, "schemaVersion", 2, 2) != 2 || Text(root, "sourceRef", 64) != source) throw Invalid();
        var page = root.GetProperty("page"); CheckAnnouncementRoot(page, target.Code, 2);
        if (AnnouncementRevision(page, "revision") != entry.TimelineRevision) throw Invalid();
        var detail = NeutralOfficialAnnouncement(Announcement(page.GetProperty("entry"), target.Code, true));
        if (detail != entry.Record) throw new AccountBridgeHostException("communities.announcementsChanged");
        var ids = new HashSet<string>(StringComparer.Ordinal);
        foreach (var id in new[] { detail.Author.AccountId, detail.Editor.AccountId }) if (OfficialBid(id)) ids.Add(id);
        var hintValid = TryAuthorRefresh(root, out var refresh);
        var identities = hintValid ? AuthorIdentities(root, ids, detail: true) : new Dictionary<string, OfficialAuthorObservation>();
        var first = identities.GetValueOrDefault(detail.Author.AccountId) ?? new OfficialAuthorObservation("unavailable");
        var second = identities.GetValueOrDefault(detail.Editor.AccountId) ?? new OfficialAuthorObservation("unavailable");
        refresh = refresh || !first.Current(_targetClock.GetUtcNow()) || !second.Current(_targetClock.GetUtcNow()) ||
            first.IdentityVersion != expectedAuthor || second.IdentityVersion != expectedEditor;
        if (first.IdentityVersion != expectedAuthor) first = new("unavailable"); if (second.IdentityVersion != expectedEditor) second = new("unavailable");
        var captured = new Dictionary<string, OfficialAuthorObservation>(StringComparer.Ordinal);
        if (OfficialBid(detail.Author.AccountId)) captured[detail.Author.AccountId] = first;
        if (OfficialBid(detail.Editor.AccountId)) captured[detail.Editor.AccountId] = second;
        JsonObject Person(AnnouncementPerson person, OfficialAuthorObservation observation)
        {
            var memberRef = observation.Current(_targetClock.GetUtcNow())
                ? MemberReferenceFor("account:" + person.AccountId, target.Code, scope, create: false) : null;
            var result = new JsonObject { ["memberRef"] = memberRef }; ApplyOfficialPerson(result, observation); return result;
        }
        return OfficialAuthorProjectionResult(captured, retired =>
        {
            var author = retired.Contains(detail.Author.AccountId) ? new OfficialAuthorObservation("unavailable") : first;
            var editor = retired.Contains(detail.Editor.AccountId) ? new OfficialAuthorObservation("unavailable") : second;
            var authorVisible = author.Current(_targetClock.GetUtcNow()); var editorVisible = editor.Current(_targetClock.GetUtcNow());
            var bytes = JsonSerializer.SerializeToUtf8Bytes(new
            {
                authorAvatarImageData = authorVisible ? author.Avatar : null,
                editorAvatarImageData = editorVisible ? editor.Avatar : null
            }, AnnouncementJson);
            return OfficialDetailChunk(targetRef, null, announcementRef, offset, byteVersion, bytes, Person(detail.Author, author), Person(detail.Editor, editor),
                refresh || !authorVisible || !editorVisible, current, publicationToken);
        }, current, publicationToken, operationStarted, targetRef);
    }
}