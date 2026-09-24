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
                var memberRef = members.FirstOrDefault(p => p.Value.MemberId == memberId).Key
                    ?? _memberTargets.FirstOrDefault(p => p.Value.MemberId == memberId && p.Value.Code == target.Code
                        && p.Value.Scope == scope && p.Value.Expires > now).Key ?? Guid.NewGuid().ToString("N");
                members[memberRef] = new(memberId, target.Code, scope, now.AddMinutes(5));
                var shipRef = _shipTargets.FirstOrDefault(p => p.Value.Id == id && p.Value.Code == target.Code
                    && p.Value.Scope == scope && p.Value.Expires > now).Key ?? Guid.NewGuid().ToString("N");
                ships[shipRef] = new(id, target.Code, scope, now.AddMinutes(5));
                var code = Text(row, "code", 256);
                if (code.Length == 0) throw Invalid();
                var displayName = Text(row, "displayName", 512);
                var catalog = Hangar.HangarShipNames.Lookup(code, displayName);
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
                    roleCategory = Optional(row, "roleCategory", 64), catalogSpec = Optional(row, "catalogSpec", 256),
                    catalogRole = Optional(row, "catalogRole", 512), catalogStatus = Optional(row, "catalogStatus", 256),
                    catalogPriceUsd = Optional(row, "catalogPriceUsd", 128),
                    catalogImageAsset = Hangar.HangarShipNames.Image(catalog.ImageKey),
                    catalogThumbnailAsset = Hangar.HangarShipNames.Thumbnail(catalog.ImageKey),
                    catalogIconKey = catalog.Display is { } display ? display.IconKey : catalog.IconKey,
                    display = catalog.Display,
                    loaners = _shipLoaners(code, Optional(row, "catalogStatus", 256), query?.Culture ?? "zh-CN"),
                    hasCustomImage = !string.IsNullOrEmpty(Optional(row, "customImageMediaId", 256)),
                    customImageCropFocusX = ShipCrop(row, "customImageCropFocusX", 0, 1),
                    customImageCropFocusY = ShipCrop(row, "customImageCropFocusY", 0, 1),
                    customImageCropZoom = ShipCrop(row, "customImageCropZoom", .1, 20)
                };
            }).ToArray();
            foreach (var old in _shipTargets.Where(p => p.Value.Expires <= now).ToArray()) _shipTargets.TryRemove(old.Key, out _);
            foreach (var old in _memberTargets.Where(p => p.Value.Expires <= now).ToArray()) _memberTargets.TryRemove(old.Key, out _);
            if (_shipTargets.Count + ships.Count(p => !_shipTargets.ContainsKey(p.Key)) > 10000 ||
                _memberTargets.Count + members.Count(p => !_memberTargets.ContainsKey(p.Key)) > 10000)
                throw new AccountBridgeHostException("communities.refreshRequired");
            current(); token.ThrowIfCancellationRequested();
            foreach (var pair in ships) _shipTargets[pair.Key] = pair.Value;
            foreach (var pair in members) _memberTargets[pair.Key] = pair.Value;
            RenewTarget(reference, target, token);
            return new { schemaVersion = 1, targetRef = reference, revision, offset, next, totalCount = total, ships = views,
                queryVersion = query is null ? 0 : 2, query = query?.View, matchedCount = query is null ? (int?)null : matched };
        });

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
