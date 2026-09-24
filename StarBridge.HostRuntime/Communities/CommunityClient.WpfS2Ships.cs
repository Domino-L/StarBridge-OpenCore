using System.Globalization;
using System.Security.Cryptography;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Hangar;

namespace StarBridge.HostRuntime.Communities;

// Only fields already visible in the authenticated WPF organization snapshot.
internal sealed record WpfS2SharedShip(string Id, string Code, string DisplayName,
    string OwnerMemberId, string OwnerGameName, string OwnerCallsign, bool OwnerOnline,
    string OwnerLiveStatus, bool OwnerIsSelf, bool OwnerHasAvatar, string? OwnerAvatarVersion, string? HangarImportedAt,
    string? RoleCategory, string? CatalogSpec, string? CatalogRole, string? CatalogStatus, string? CatalogPriceUsd)
{
    // S2 may synthesize ImportedAt at read time. Do not present it as recorded sharing history.
    public string? SharedAt => null;
    public string? CustomImageMediaId => null;
    public double CustomImageCropFocusX => .5;
    public double CustomImageCropFocusY => .5;
    public double CustomImageCropZoom => 1;
}

internal sealed partial class CommunityClient
{
    private async Task<JsonElement> WpfS2Ships(string bearer, Target target, ShipQuery? query,
        int offset, string? expected, Action current, CancellationToken token)
    {
        var fleet = (await WpfS2Membership(bearer, token)).SingleOrDefault(row =>
            Text(row, "code", 256).Equals(target.Code, StringComparison.OrdinalIgnoreCase));
        current(); token.ThrowIfCancellationRequested();
        if (fleet.ValueKind == JsonValueKind.Undefined) throw new AccountBridgeHostException("communities.notAllowed");
        var members = Rows(fleet, "members", 10000);
        var rows = new List<WpfS2SharedShip>();
        var seen = new HashSet<string>(StringComparer.Ordinal);
        foreach (var ship in Rows(fleet, "ships", 10000))
        {
            ShipObject(ship);
            var ownerId = Optional(ship, "ownerAccountId", 512);
            var ownerName = WpfText(ship, "ownerGameName", 256);
            // Never guess ownership from callsign or claim a hidden account by name.
            var owners = members.Where(m => !string.IsNullOrWhiteSpace(ownerId)
                ? string.Equals(Optional(m, "accountId", 512), ownerId, StringComparison.OrdinalIgnoreCase)
                : ownerName.Length > 0 && string.IsNullOrEmpty(Optional(m, "accountId", 512)) &&
                    WpfText(m, "gameName", 512).Equals(ownerName, StringComparison.OrdinalIgnoreCase)).ToArray();
            if (owners.Length == 0) continue; // Stale contribution from a departed member.
            if (owners.Length != 1) throw Invalid();
            var owner = owners[0];
            var memberId = WpfS2MemberId(owner) ?? throw Invalid();
            var code = Text(ship, "code", 256);
            if (string.IsNullOrWhiteSpace(code)) throw Invalid();
            var instance = Optional(ship, "instanceId", 512);
            var id = Convert.ToHexString(SHA256.HashData(JsonSerializer.SerializeToUtf8Bytes(new[] {
                target.Code.ToUpperInvariant(), memberId.ToUpperInvariant(),
                string.IsNullOrWhiteSpace(instance) ? "code:" + code.ToUpperInvariant() : "instance:" + instance.ToUpperInvariant()
            }))).ToLowerInvariant();
            if (!seen.Add(id)) throw Invalid(); // Never silently collapse multiple instances.
            var name = WpfText(ship, "displayName", 512, fallback: code);
            var catalog = HangarShipNames.Lookup(code);
            if (catalog.CatalogId is null) catalog = HangarShipNames.Lookup(name);
            name = CommunityShipCatalog.DisplayName(catalog, name, query?.Culture ?? "zh-CN");
            var status = Optional(ship, "catalogStatus", 256);
            // Same WPF boundary: an authoritative status means its related metadata wins.
            string? spec = status is not null ? Optional(ship, "catalogSpec", 256) : catalog.SizeClass switch {
                "capital" => "旗舰级", "large" => "大型", "medium" => "中型", "small" => "小型", _ => catalog.SizeClass };
            var role = status is not null ? Optional(ship, "catalogRole", 512) : catalog.Category;
            var price = status is not null ? Optional(ship, "catalogPriceUsd", 128) : catalog.PriceUsd?.ToString(CultureInfo.InvariantCulture);
            status ??= catalog.DeliveryStatus switch { "flyable" => "可飞", "concept" => "概念", _ => catalog.DeliveryStatus };
            var imported = Timestamp(ship, "hangarImportedAt");
            if (imported is not null && DateTimeOffset.Parse(imported).Year == 1) imported = null;
            rows.Add(new(id, code, name, memberId, WpfText(owner, "gameName", 256), WpfText(owner, "callsign", 256),
                owner.GetProperty("online").GetBoolean(), WpfText(owner, "liveStatus", 64, fallback: "Offline"),
                string.Equals(Optional(owner, "accountId", 512), target.WpfS2ViewerId, StringComparison.Ordinal),
                !string.IsNullOrEmpty(Optional(owner, "avatarImageData", 1024 * 1024)),
                AvatarContentVersion(Optional(owner, "avatarImageData", 1024 * 1024)), imported,
                Optional(ship, "roleCategory", 64) ?? catalog.Category, spec, role, status, price));
        }
        var ordered = rows.OrderBy(row => row.Id, StringComparer.Ordinal).ToArray();
        var selected = query is null ? ordered : new CommunityShipQuery("", query.Filter, query.Sort, query.Descending, query.Culture).Apply(ordered);
        if (query is { Text.Length: > 0 }) selected = selected.Where(row => MatchesShipSearch(
            JsonSerializer.SerializeToElement(row, ChatJson), JsonSerializer.SerializeToElement(
                _shipLoaners(row.Code, row.CatalogStatus, query.Culture), ChatJson), query.Text)).ToArray();
        // Hash the bounded authorized projection, excluding original images, private extras and read-time timestamps.
        var revision = Convert.ToHexString(SHA256.HashData(JsonSerializer.SerializeToUtf8Bytes(
            new { target.Code, query = query?.View, ships = ordered }, ChatJson))).ToLowerInvariant();
        if (expected is not null && revision != expected || offset > selected.Length)
            throw new AccountBridgeHostException("communities.shipsChanged");
        current(); token.ThrowIfCancellationRequested();
        return JsonSerializer.SerializeToElement(new { schemaVersion = 1, code = target.Code, revision, offset,
            next = offset + 20 < selected.Length ? (int?)(offset + 20) : null, totalCount = rows.Count,
            queryVersion = query is null ? 0 : 2, query = query?.View, matchedCount = query is null ? (int?)null : selected.Length,
            ships = selected.Skip(offset).Take(20).ToArray() }, ChatJson);
    }
}
