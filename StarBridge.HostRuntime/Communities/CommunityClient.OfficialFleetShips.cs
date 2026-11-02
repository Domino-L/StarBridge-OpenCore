using System.Collections.Concurrent;
using System.Globalization;
using System.Text.Json;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Communities;

internal sealed partial class CommunityClient
{
    internal sealed record OfficialShipOwner(string State, string Callsign, string? ProfileReference,
        string? AvatarImageData, string? AvatarVersion, long MemberId = 0);
    private sealed record OfficialShipDisplayReference(string Reference, DateTimeOffset Expires, OfficialShipImageReference? Image = null);
    internal sealed record OfficialShipImageReference(string AccountScope, string SourceRef, string TargetRef, string ShipId, long MemberId, string? Version, bool Read, bool Report);
    // Presentation references confer no authority. The context/source and G1 are
    // checked afresh on every read, continuation, search and detail request.
    private readonly ConcurrentDictionary<string, OfficialShipDisplayReference> _officialShipDisplayReferences = new();

    internal Task<object> ReadOfficialShipsAsync(string bearer, JsonElement body, string sourceRef, string scope,
        Action current, Func<JsonElement, CancellationToken, Task<IReadOnlyDictionary<string, OfficialShipOwner>>> authorize,
        TimeProvider observationClock, CancellationToken token, Action<DateTimeOffset?>? projectionDeadlineObserved = null) => GuardWorkspace(async () =>
    {
        Validate(body, "targetRef", "offset", "revision", "query");
        var reference = Text(body, "targetRef", 32);
        var offset = Number(body, "offset", 0, 1000000);
        var expected = Optional(body, "revision", 64);
        var query = body.TryGetProperty("query", out var element) && element.ValueKind != JsonValueKind.Null
            ? ParseShipQuery(element) : new ShipQuery("", "all", "spec", true, "zh-CN");
        if (offset % 20 != 0 || offset > 0 && expected is null || expected is not null && !ShipHash(expected)) throw Invalid();
        RequireOfficialFleetTarget(body, sourceRef, scope);
        var target = ResolveForRead(reference, scope);
        var owners = new Dictionary<string, OfficialShipOwner>(StringComparer.Ordinal);
        DateTimeOffset? projectionDeadline = null;
        OfficialHangarImageFeatures? imageFeatures = null;
        void Current()
        {
            current(); token.ThrowIfCancellationRequested();
            RequireOfficialFleetTarget(body, sourceRef, scope);
            if (projectionDeadline is { } expires && observationClock.GetUtcNow() >= expires)
                throw new AccountBridgeHostException("communities.identityUnavailable");
        }
        async Task<JsonElement> Page(int pageOffset, string? revision, ShipQuery selection, CancellationToken ct)
        {
            Current();
            var path = "/api/official-fleets/ships?sourceRef=" + Uri.EscapeDataString(sourceRef)
                + "&offset=" + pageOffset.ToString(CultureInfo.InvariantCulture)
                + (revision is null ? "" : "&revision=" + revision) + selection.Url;
            JsonElement raw;
            try { raw = await WorkspaceJson(bearer, path, ct, 400 * 1024, officialImages: true); }
            catch (AccountBridgeHostException e) when (e.Code == "communities.unavailable")
            {
                // A failed directory read cannot establish whether the former
                // viewer-scoped identity is still public. Clear stale UI.
                throw new AccountBridgeHostException("communities.identityUnavailable");
            }
            Current(); ShipObject(raw);
            var protocol = Number(raw, "schemaVersion", 1, 2);
            var features = protocol == 2 ? ReadOfficialImageFeatures(raw) : new OfficialHangarImageFeatures(false, false, false, false);
            if (imageFeatures is not null && imageFeatures != features) throw Invalid();
            imageFeatures = features;
            if (Text(raw, "sourceRef", 64) != sourceRef ||
                Text(raw, "coverage", 64) != "completeAuthorizedProjection" ||
                Number(raw, "queryVersion", 2, 2) != 2 || ParseShipQuery(raw.GetProperty("query")) != selection ||
                Number(raw, "offset", 0, 1000000) != pageOffset) throw Invalid();
            var total = Number(raw, "totalCount", 0, 1000000);
            var matched = Number(raw, "matchedCount", 0, total);
            var pageRows = Rows(raw, "ships", 20);
            var next = raw.GetProperty("next").ValueKind == JsonValueKind.Null ? (int?)null : Number(raw, "next", 0, matched);
            var actualRevision = Text(raw, "revision", 64);
            if (!ShipHash(actualRevision) || revision is not null && revision != actualRevision || pageOffset > matched ||
                pageRows.Length != Math.Min(20, matched - pageOffset) ||
                next != (pageOffset + pageRows.Length < matched ? pageOffset + pageRows.Length : null)) throw Invalid();
            var deadline = raw.GetProperty("identityValidUntilUtc");
            if (deadline.ValueKind == JsonValueKind.Null)
            {
                if (total != 0) throw new AccountBridgeHostException("communities.identityUnavailable");
            }
            else
            {
                if (deadline.ValueKind != JsonValueKind.String || !deadline.TryGetDateTimeOffset(out var value) ||
                    value.Offset != TimeSpan.Zero || value <= observationClock.GetUtcNow())
                    throw new AccountBridgeHostException("communities.identityUnavailable");
                projectionDeadline = projectionDeadline is null || value < projectionDeadline ? value : projectionDeadline;
                projectionDeadlineObserved?.Invoke(projectionDeadline);
            }
            var verified = await authorize(raw, ct);
            Current();
            foreach (var pair in verified)
            {
                if (owners.TryGetValue(pair.Key, out var prior) && prior != pair.Value)
                    throw new AccountBridgeHostException("communities.identityUnavailable");
                owners[pair.Key] = pair.Value;
            }
            var rows = pageRows.Select(row =>
            {
                ShipObject(row);
                var id = Text(row, "id", 64);
                var owner = Text(row, "ownerMemberId", 64);
                if (!ShipHash(id) || !ShipHash(owner) || !verified.TryGetValue(owner, out var identity) ||
                    row.GetProperty("instanceId").ValueKind != JsonValueKind.Null ||
                    Optional(row, "customImageMediaId", 256) is not null || Text(row, "ownerGameName", 256) != "" ||
                    Text(row, "ownerCallsign", 256) != identity.Callsign || row.GetProperty("ownerOnline").GetBoolean() ||
                    Text(row, "ownerLiveStatus", 64) != "Unknown" || row.GetProperty("ownerHasAvatar").GetBoolean()) throw Invalid();
                var fields = row.EnumerateObject().ToDictionary(p => p.Name, p => p.Value);
                if (protocol == 2) { _ = row.GetProperty("imageVersion"); if (row.GetProperty("customImageMediaId").ValueKind != JsonValueKind.Null) throw Invalid(); }
                var hasImage = protocol == 2 && row.GetProperty("hasImage").GetBoolean();
                var imageVersion = protocol == 2 ? Optional(row, "imageVersion", 64) : null;
                if (hasImage != (imageVersion is not null) || imageVersion is not null && !ShipHash(imageVersion)) throw Invalid();
                if (hasImage) { _ = ShipCrop(row,"customImageCropFocusX",0,1); _ = ShipCrop(row,"customImageCropFocusY",0,1); _ = ShipCrop(row,"customImageCropZoom",1,3); }
                fields["hasImage"] = JsonSerializer.SerializeToElement(hasImage);
                fields["imageVersion"] = JsonSerializer.SerializeToElement(imageVersion);
                fields["ownerHasAvatar"] = JsonSerializer.SerializeToElement(identity.AvatarImageData is not null);
                fields["ownerAvatarVersion"] = JsonSerializer.SerializeToElement(identity.AvatarVersion);
                return JsonSerializer.SerializeToElement(fields);
            }).ToArray();
            // Adapt only the wire envelope for the existing WPF loaner search.
            // No official source is registered as a community membership.
            return JsonSerializer.SerializeToElement(new { schemaVersion = 1, code = target.Code,
                revision = actualRevision, queryVersion = 2, query = selection.View,
                offset = pageOffset, next, totalCount = total, matchedCount = matched, ships = rows });
        }
        var root = query.Text.Length > 0
            ? await ReadLoanerSearchPage(bearer, target.Code, query, offset, expected, Current, token,
                Page, TimeSpan.FromSeconds(12))
            : await Page(offset, expected, query, token);
        Current();
        var now = observationClock.GetUtcNow();
        foreach (var item in _officialShipDisplayReferences.Where(p => p.Value.Expires <= now).ToArray())
            _officialShipDisplayReferences.TryRemove(item.Key, out _);
        string Ref(string kind, string id)
        {
            var key = scope + "|" + kind + "|" + id;
            if (_officialShipDisplayReferences.Count >= 20000 && !_officialShipDisplayReferences.ContainsKey(key))
                throw new AccountBridgeHostException("communities.refreshRequired");
            return _officialShipDisplayReferences.AddOrUpdate(key,
                _ => new(Guid.NewGuid().ToString("N"), now.AddMinutes(5)),
                (_, old) => old with { Expires = now.AddMinutes(5) }).Reference;
        }
        var selected = Rows(root, "ships", 20);
        var seen = new HashSet<string>(StringComparer.Ordinal);
        var views = selected.Select(row =>
        {
            var id = Text(row, "id", 64);
            if (!seen.Add(id)) throw Invalid();
            var shipRef = Ref("ship", id);
            var member = owners[Text(row, "ownerMemberId", 64)];
            var hasImage = row.GetProperty("hasImage").GetBoolean();
            var version = Optional(row, "imageVersion", 64);
            if (hasImage && member.MemberId <= 0) throw Invalid();
            var key = scope + "|ship|" + id;
            _officialShipDisplayReferences[key] = _officialShipDisplayReferences[key] with {
                Image = new(scope, sourceRef, reference, id, member.MemberId, version, imageFeatures?.Read == true, imageFeatures?.Report == true) };
            var projected = JsonSerializer.SerializeToElement(ProjectShipView(row, shipRef, Ref("owner", Text(row, "ownerMemberId", 64)), query));
            var fields = projected.EnumerateObject().ToDictionary(p => p.Name, p => p.Value);
            fields["hasCustomImage"] = JsonSerializer.SerializeToElement(hasImage);
            fields["imageVersion"] = JsonSerializer.SerializeToElement(version);
            return JsonSerializer.SerializeToElement(fields);
        }).ToArray();
        var sidecar = selected.Select(row => Text(row, "ownerMemberId", 64)).Distinct().Select(id => new {
            ownerMemberRef = Ref("owner", id), profileReference = owners[id].ProfileReference,
            avatarImageData = owners[id].AvatarImageData, avatarVersion = owners[id].AvatarVersion,
        }).ToArray();
        Current(); RenewTarget(reference, target, token);
        return new { schemaVersion = 1, targetRef = reference, sourceRef,
            revision = Text(root, "revision", 64), offset, next = root.GetProperty("next"),
            totalCount = Number(root, "totalCount", 0, 1000000), matchedCount = Number(root, "matchedCount", 0, 1000000),
            queryVersion = 2, query = query.View, ships = views, owners = sidecar,
            imageFeatures = new { protocolVersion = 1, read = imageFeatures?.Read == true, upload = imageFeatures?.Upload == true, report = imageFeatures?.Report == true, reduce = imageFeatures?.Reduce == true } };
    });
}
