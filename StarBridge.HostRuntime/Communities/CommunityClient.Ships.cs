using System.Collections.Concurrent;
using System.Globalization;
using System.Text.Json;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Communities;

internal sealed partial class CommunityClient
{
    private sealed record ShipTarget(string Id, string Code, string Scope, DateTimeOffset Expires);
    private readonly ConcurrentDictionary<string, ShipTarget> _shipTargets = new();

    internal Task<object> ReadShipsAsync(string bearer, JsonElement body, string scope, Action current, CancellationToken token) =>
        GuardWorkspace(async () =>
        {
            Validate(body, "targetRef", "offset", "revision", "query");
            var query = body.TryGetProperty("query", out var queryElement) && queryElement.ValueKind != JsonValueKind.Null
                ? ParseShipQuery(queryElement) : null;
            var reference = Text(body, "targetRef", 32);
            var offset = Number(body, "offset", 0, 1000000);
            var expected = Optional(body, "revision", 64);
            if (offset % 20 != 0 || offset > 0 && expected is null || expected is not null && !ShipHash(expected)) throw Invalid();
            current(); token.ThrowIfCancellationRequested();
            var target = ResolveForRead(reference, scope, allowWpfS2: true);
            var path = "/api/fleets/ships?code=" + Uri.EscapeDataString(target.Code) + "&offset=" + offset.ToString(CultureInfo.InvariantCulture)
                + (expected is null ? "" : "&revision=" + expected) + (query?.Url ?? "");
            JsonElement root;
            try
            {
                root = target.WpfS2ViewerId is not null
                    ? await WpfS2Ships(bearer, target, query, offset, expected, current, token)
                    : _loanerSearchAvailable && query is { Text.Length: > 0 }
                    ? await ReadLoanerSearchPage(bearer, target.Code, query, offset, expected, current, token)
                    : await WorkspaceJson(bearer, path, token, 400 * 1024);
            }
            catch (AccountBridgeHostException e) when (e.Code == "communities.mediaChanged")
            { throw new AccountBridgeHostException("communities.shipsChanged"); }
            current(); token.ThrowIfCancellationRequested();
            ShipObject(root);
            var revision = Text(root, "revision", 64);
            var total = Number(root, "totalCount", 0, 1000000);
            var matched = total;
            if (query is not null)
            {
                if (!root.TryGetProperty("queryVersion", out var queryVersion) || queryVersion.GetInt32() != 2)
                    throw new AccountBridgeHostException("communities.upgradeRequired");
                if (ParseShipQuery(root.GetProperty("query")) != query) throw Invalid();
                matched = Number(root, "matchedCount", 0, total);
            }
            var next = root.GetProperty("next").ValueKind == JsonValueKind.Null ? (int?)null : Number(root, "next", 0, 1000000);
            var source = Rows(root, "ships", 20);
            if (Number(root, "schemaVersion", 1, 1) != 1 || Text(root, "code", 256) != target.Code || !ShipHash(revision)
                || expected is not null && expected != revision || Number(root, "offset", 0, 1000000) != offset
                || offset > matched || source.Length != Math.Min(20, matched - offset)
                || next != (offset + source.Length < matched ? offset + source.Length : null)) throw Invalid();

            var now = DateTimeOffset.UtcNow;
            var members = new Dictionary<string, MemberTarget>();
            var ships = new Dictionary<string, ShipTarget>();
            string? previousId = null;
            var seen = new HashSet<string>(StringComparer.Ordinal);
            var views = source.Select(row =>
            {
                ShipObject(row);
                var id = Text(row, "id", 64);
                if (!ShipHash(id) || !seen.Add(id) || query is null && previousId is not null && StringComparer.Ordinal.Compare(previousId, id) >= 0) throw Invalid();
                previousId = id;
                var memberId = Text(row, "ownerMemberId", 512);
                if (!(memberId.StartsWith("account:", StringComparison.Ordinal) && memberId.Length > 8 ||
                    memberId.StartsWith("legacy:", StringComparison.Ordinal) && ShipHash(memberId[7..]))) throw Invalid();
                var memberRef = MemberReferenceFor(memberId, target.Code, scope)!;
                members[memberRef] = new(memberId, target.Code, scope, now.AddMinutes(5));
                var shipRef = _shipTargets.FirstOrDefault(p => p.Value.Id == id && p.Value.Code == target.Code
                    && p.Value.Scope == scope && p.Value.Expires > now).Key ?? Guid.NewGuid().ToString("N");
                ships[shipRef] = new(id, target.Code, scope, now.AddMinutes(5));
                return ProjectShipView(row, shipRef, memberRef, query);
            }).ToArray();
            foreach (var old in _shipTargets.Where(p => p.Value.Expires <= now).ToArray()) _shipTargets.TryRemove(old.Key, out _);
            if (_shipTargets.Count + ships.Count(p => !_shipTargets.ContainsKey(p.Key)) > 10000)
                throw new AccountBridgeHostException("communities.refreshRequired");
            current(); token.ThrowIfCancellationRequested();
            PublishMemberTargets(members);
            foreach (var pair in ships) _shipTargets[pair.Key] = pair.Value;
            RenewTarget(reference, target, token);
            return new { schemaVersion = 1, targetRef = reference, revision, offset, next, totalCount = total, ships = views,
                queryVersion = query is null ? 0 : 2, query = query?.View, matchedCount = query is null ? (int?)null : matched };
        });

    // Catalog and public row fields have one projection for both real organization adapters.
    private object ProjectShipView(JsonElement row, string shipRef, string memberRef, ShipQuery? query)
    {
        var code = Text(row, "code", 256);
        if (code.Length == 0) throw Invalid();
        var displayName = Text(row, "displayName", 512);
        var catalog = _shipCatalog(code, displayName);
        var metadata = ShipMetadata(row, catalog);
        var ownerAvatarVersion = Optional(row, "ownerAvatarVersion", 64);
        if (ownerAvatarVersion is not null && !LowerHex(ownerAvatarVersion, 64)) throw Invalid();
        return new
        {
            shipRef, code,
            displayName = CommunityShipCatalog.DisplayName(catalog, displayName, query?.Culture ?? "zh-CN"),
            englishName = catalog.EnglishName, manufacturer = catalog.Manufacturer,
            ownerMemberRef = memberRef,
            ownerGameName = Text(row, "ownerGameName", 256), ownerCallsign = Text(row, "ownerCallsign", 256),
            ownerOnline = row.GetProperty("ownerOnline").GetBoolean(), ownerLiveStatus = Text(row, "ownerLiveStatus", 64),
            ownerIsSelf = row.GetProperty("ownerIsSelf").GetBoolean(), ownerHasAvatar = row.GetProperty("ownerHasAvatar").GetBoolean(),
            ownerAvatarVersion,
            sharedAt = Timestamp(row, "sharedAt"), hangarImportedAt = Timestamp(row, "hangarImportedAt"),
            roleCategory = metadata.RoleCategory, catalogSpec = metadata.Spec,
            catalogRole = metadata.Role, catalogStatus = metadata.Status,
            catalogPriceUsd = metadata.PriceUsd,
            catalogImageAsset = Hangar.HangarShipNames.Image(catalog.ImageKey),
            catalogThumbnailAsset = Hangar.HangarShipNames.Thumbnail(catalog.ImageKey),
            catalogIconKey = catalog.Display is { } display ? display.IconKey : catalog.IconKey,
            display = catalog.Display,
            loaners = _shipLoaners(code, metadata.Status, query?.Culture ?? "zh-CN"),
            hasCustomImage = !string.IsNullOrEmpty(Optional(row, "customImageMediaId", 256)),
            customImageCropFocusX = ShipCrop(row, "customImageCropFocusX", 0, 1),
            customImageCropFocusY = ShipCrop(row, "customImageCropFocusY", 0, 1),
            customImageCropZoom = ShipCrop(row, "customImageCropZoom", .1, 20)
        };
    }

    private static StarBridge.Core.Ships.ShipCatalogMetadata ShipMetadata(JsonElement row, StarBridge.Core.Ships.ShipPresentation catalog) =>
        new StarBridge.Core.Ships.ShipCatalogMetadata(Optional(row, "catalogSpec", 256), Optional(row, "catalogRole", 512),
            Optional(row, "catalogStatus", 256), Optional(row, "catalogPriceUsd", 128), Optional(row, "roleCategory", 64)).FillMissing(catalog);

    private JsonElement FillShipMetadata(JsonElement row)
    {
        var metadata = ShipMetadata(row, _shipCatalog(Text(row, "code", 256), Text(row, "displayName", 512)));
        var fields = row.EnumerateObject().ToDictionary(p => p.Name, p => p.Value);
        fields["catalogSpec"] = JsonSerializer.SerializeToElement(metadata.Spec);
        fields["catalogRole"] = JsonSerializer.SerializeToElement(metadata.Role);
        fields["catalogStatus"] = JsonSerializer.SerializeToElement(metadata.Status);
        fields["catalogPriceUsd"] = JsonSerializer.SerializeToElement(metadata.PriceUsd);
        fields["roleCategory"] = JsonSerializer.SerializeToElement(metadata.RoleCategory);
        return JsonSerializer.SerializeToElement(fields);
    }

    private static bool ShipHash(string value) => value.Length == 64 && value.All(c => char.IsAsciiHexDigit(c) && !char.IsUpper(c));
    private static void ShipObject(JsonElement value)
    {
        if (value.ValueKind != JsonValueKind.Object || value.EnumerateObject().Select(p => p.Name).Distinct().Count()
            != value.EnumerateObject().Count()) throw Invalid();
    }
    private static double ShipCrop(JsonElement row, string key, double min, double max)
    {
        var value = row.GetProperty(key).GetDouble();
        return double.IsFinite(value) && value >= min && value <= max ? value : throw Invalid();
    }
}
