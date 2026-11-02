using System.Text.Json;
using System.Text.RegularExpressions;
using StarBridge.HostRuntime.Marketplace;

namespace StarBridge.HostRuntime.Account;

/// <summary>The always-public trade window (user rule 2026-10-20): seven Monday-first day flags,
/// an HH:mm window and the SCM time zone id. Never carries the SCM member id or contact.</summary>
internal sealed record PersonalProfileTradeWindow(int[] Days, string Start, string End, long TimezoneId)
{
    /// <summary>The owner's UTC offset now (DST applied), resolved by the Host from SCM's
    /// time-zone directory so the client can show the window in local time; null if unknown.</summary>
    internal int? OwnerOffsetMinutes { get; init; }

    private static readonly Regex Time = new("^(?:[01][0-9]|2[0-3]):[0-5][0-9]$", RegexOptions.CultureInvariant);

    /// <summary>The owner's SCM trade profile as the window to publish; null when it is not set.</summary>
    internal static PersonalProfileTradeWindow? FromScm(JsonElement raw)
    {
        if (raw.ValueKind != JsonValueKind.Object) return null;
        var days = TradeProfileContract.StoredDays(raw);
        static string? HourMinute(JsonElement source, string key) =>
            source.TryGetProperty(key, out var v) && v.ValueKind == JsonValueKind.String && v.GetString() is { Length: >= 5 } text
                && Time.IsMatch(text[..5]) ? text[..5] : null;
        var start = HourMinute(raw, "tradeStartTime");
        var end = HourMinute(raw, "tradeEndTime");
        long zone = 0;
        var hasZone = raw.TryGetProperty("timezoneId", out var z) &&
            (z.ValueKind == JsonValueKind.Number && z.TryGetInt64(out zone) ||
             z.ValueKind == JsonValueKind.String && long.TryParse(z.GetString(), out zone));
        return Valid(days, start, end, hasZone ? zone : 0) ? new(days, start!, end!, zone) : null;
    }

    internal static bool Valid(int[]? days, string? start, string? end, long zone) =>
        days is { Length: 7 } && days.All(d => d is 0 or 1) && days.Contains(1) &&
        start is not null && end is not null && Time.IsMatch(start) && Time.IsMatch(end) && start != end &&
        zone is >= 1 and <= 100000;

    internal static PersonalProfileTradeWindow? Parse(JsonElement value)
    {
        if (value.ValueKind == JsonValueKind.Null) return null;
        if (value.ValueKind != JsonValueKind.Object ||
            !value.EnumerateObject().Select(p => p.Name).Order(StringComparer.Ordinal)
                .SequenceEqual(["days", "end", "start", "timezoneId"], StringComparer.Ordinal))
            throw new JsonException("Invalid trade window.");
        var days = value.GetProperty("days").EnumerateArray().Select(d => d.GetInt32()).ToArray();
        var start = value.GetProperty("start").GetString();
        var end = value.GetProperty("end").GetString();
        var zone = value.GetProperty("timezoneId").GetInt64();
        if (!Valid(days, start, end, zone)) throw new JsonException("Invalid trade window.");
        return new(days, start!, end!, zone);
    }

    // The SCM zone id stays here, like the one in the facts: the client only needs the resolved offset.
    internal object ToPayload() => new { days = Days, start = Start, end = End, ownerOffsetMinutes = OwnerOffsetMinutes };

    internal string Fingerprint => string.Join(',', Days) + '|' + Start + '|' + End + '|' + TimezoneId;
}

/// <summary>SCM's public trade facts about someone who never chose a page visibility (user rules 2026-10-30).
/// Every value may be null: unknown. Parsed by whitelist like the header, and the time zone id stops here:
/// the client only ever receives the resolved offset.</summary>
internal sealed record PersonalProfilePublicFacts(
    long? Reputation, long? CompletedTrades, long? SellOrders, long? BuyOrders,
    string? LastOnlineDay, string? SiteRegisteredDay, string? GameRegisteredDay,
    string? Language, long? TimezoneId, bool? Banned, int? BanCount)
{
    /// <summary>Resolved by the Host from SCM's time-zone directory; null if unknown.</summary>
    internal int? UtcOffsetMinutes { get; init; }

    internal static PersonalProfilePublicFacts? Parse(JsonElement value)
    {
        if (value.ValueKind == JsonValueKind.Null) return null;
        // Unknown keys are a protocol error. A missing key is unknown like a null: a server may omit nulls.
        string[] allowed = ["banCount", "banned", "buyOrders", "completedTrades", "gameRegisteredDay", "language",
            "lastOnlineDay", "reputation", "sellOrders", "siteRegisteredDay", "timezoneId"];
        if (value.ValueKind != JsonValueKind.Object || value.EnumerateObject().Any(p => !allowed.Contains(p.Name, StringComparer.Ordinal)) ||
            value.EnumerateObject().Select(p => p.Name).Distinct(StringComparer.Ordinal).Count() != value.EnumerateObject().Count())
            throw new JsonException("Invalid public facts.");
        var language = Field(value, "language");
        if (language.ValueKind != JsonValueKind.Null && language.GetString() is not ("zh" or "en"))
            throw new JsonException("Invalid public language.");
        var banned = Field(value, "banned");
        if (banned.ValueKind is not (JsonValueKind.Null or JsonValueKind.True or JsonValueKind.False))
            throw new JsonException("Invalid public ban state.");
        return new(
            Whole(value, "reputation", -1_000_000_000, 1_000_000_000),
            Whole(value, "completedTrades", 0, 1_000_000_000), Whole(value, "sellOrders", 0, 1_000_000_000), Whole(value, "buyOrders", 0, 1_000_000_000),
            Day(value, "lastOnlineDay"), Day(value, "siteRegisteredDay"), Day(value, "gameRegisteredDay"),
            language.ValueKind == JsonValueKind.Null ? null : language.GetString(),
            Whole(value, "timezoneId", 1, 100_000),
            banned.ValueKind == JsonValueKind.Null ? null : banned.GetBoolean(),
            (int?)Whole(value, "banCount", 0, 1_000_000));
    }

    private static readonly JsonElement NullValue = JsonDocument.Parse("null").RootElement.Clone();

    private static JsonElement Field(JsonElement source, string key) =>
        source.TryGetProperty(key, out var value) ? value : NullValue;

    private static long? Whole(JsonElement source, string key, long min, long max)
    {
        var value = Field(source, key);
        if (value.ValueKind == JsonValueKind.Null) return null;
        var number = value.GetInt64();
        return number >= min && number <= max ? number : throw new JsonException("Invalid public fact.");
    }

    private static string? Day(JsonElement source, string key)
    {
        var value = Field(source, key);
        if (value.ValueKind == JsonValueKind.Null) return null;
        var day = value.GetString();
        return DateOnly.TryParseExact(day, "yyyy-MM-dd", System.Globalization.CultureInfo.InvariantCulture,
            System.Globalization.DateTimeStyles.None, out _) ? day : throw new JsonException("Invalid public day.");
    }

    internal object ToPayload() => new
    {
        reputation = Reputation, completedTrades = CompletedTrades, sellOrders = SellOrders, buyOrders = BuyOrders,
        lastOnlineDay = LastOnlineDay, siteRegisteredDay = SiteRegisteredDay, gameRegisteredDay = GameRegisteredDay,
        language = Language, utcOffsetMinutes = UtcOffsetMinutes, banned = Banned, banCount = BanCount
    };
}

/// <summary>DEPLOY-QUEUE §4: what a visitor outside a profile's visibility may still see — callsign,
/// avatar and the trade window. Parsed by whitelist; any other field is a protocol error, so a server
/// change can never leak more than this through the Host.</summary>
internal sealed record PersonalProfilePublicHeader(
    string Visibility, string Callsign, string? AvatarAssetId, PersonalProfileTradeWindow? TradeWindow,
    string FleetAffiliationStatus = "unavailable", bool Defaulted = false, bool NameMasked = false,
    PersonalProfilePublicFacts? Facts = null)
{
    internal const string AcceptHeader = "X-StarBridge-Profile-Accept";
    internal const string AcceptValue = "public-header-v1";
    /// <summary>The visitor routes understand both answers, so a server not yet swapped keeps working.
    /// The historical-member route stays on v1.</summary>
    internal const string AcceptValues = "public-header-v1, public-header-v2";
    private const int MaxAvatarLength = 4 * 1024 * 1024;

    internal static bool IsRestricted(JsonElement root) =>
        root.ValueKind == JsonValueKind.Object && root.TryGetProperty("restricted", out _);

    /// <param name="legacyAccountId">The visitor-legacy route echoes the requested id; null for visitor/{id}.</param>
    internal static PersonalProfilePublicHeader Parse(JsonElement root, string? legacyAccountId)
    {
        // Wrong JSON kinds throw InvalidOperationException; report every malformed shape the same way.
        try { return ParseCore(root, legacyAccountId); }
        catch (Exception e) when (e is InvalidOperationException or FormatException or KeyNotFoundException)
        { throw new JsonException("Invalid restricted profile.", e); }
    }

    private static PersonalProfilePublicHeader ParseCore(JsonElement root, string? legacyAccountId)
    {
        string[] expected = legacyAccountId is null
            ? ["publicHeader", "restricted", "schemaVersion", "visibility"]
            : ["legacyAccountId", "publicHeader", "restricted", "schemaVersion", "visibility"];
        // A restricted answer never carries the organization, so it is hidden from this viewer.
        // Servers omit the status here because shipped Hosts reject unknown top-level keys.
        var affiliationStatus = "hidden";
        if (root.ValueKind == JsonValueKind.Object && root.TryGetProperty("fleetAffiliationStatus", out var status))
        {
            if (status.ValueKind != JsonValueKind.String || status.GetString() != "hidden")
                throw new JsonException("Invalid restricted affiliation status.");
            affiliationStatus = "hidden";
            expected = expected.Append("fleetAffiliationStatus").Order(StringComparer.Ordinal).ToArray();
        }
        if (root.ValueKind != JsonValueKind.Object ||
            !root.EnumerateObject().Select(p => p.Name).Order(StringComparer.Ordinal).SequenceEqual(expected, StringComparer.Ordinal) ||
            root.GetProperty("schemaVersion").GetInt32() is not (1 or 2) ||
            legacyAccountId is not null && root.GetProperty("schemaVersion").GetInt32() != 1 ||
            root.GetProperty("restricted").ValueKind != JsonValueKind.True ||
            legacyAccountId is not null && root.GetProperty("legacyAccountId").GetString() != legacyAccountId)
            throw new JsonException("Invalid restricted profile.");
        var visibility = root.GetProperty("visibility").GetString();
        // A public profile is never restricted by visibility.
        if (visibility is not ("friendsAndMainFleet" or "friendsOnly" or "private"))
            throw new JsonException("Invalid restricted visibility.");
        var header = root.GetProperty("publicHeader");
        var v2 = root.GetProperty("schemaVersion").GetInt32() == 2;
        string[] allowed = v2
            ? ["avatarAssetId", "avatarOrigin", "callSignOrigin", "callsign", "defaulted", "facts", "nameMasked", "tradeWindow"]
            : ["avatarAssetId", "avatarOrigin", "callSignOrigin", "callsign", "tradeWindow"];
        if (header.ValueKind != JsonValueKind.Object || header.EnumerateObject().Any(p => !allowed.Contains(p.Name, StringComparer.Ordinal)) ||
            header.EnumerateObject().Select(p => p.Name).Distinct(StringComparer.Ordinal).Count() != header.EnumerateObject().Count())
            throw new JsonException("Invalid public header.");
        var callsign = header.TryGetProperty("callsign", out var c) && c.ValueKind == JsonValueKind.String ? c.GetString()! : null;
        if (callsign is null || callsign.Length > 128 || callsign.Any(char.IsControl))
            throw new JsonException("Invalid public callsign.");
        string? avatar = null;
        if (header.TryGetProperty("avatarAssetId", out var a) && a.ValueKind != JsonValueKind.Null)
        {
            avatar = a.ValueKind == JsonValueKind.String ? a.GetString() : null;
            if (avatar is null || avatar.Length > MaxAvatarLength ||
                !(avatar.StartsWith("data:image/png;base64,", StringComparison.Ordinal) ||
                  avatar.StartsWith("data:image/jpeg;base64,", StringComparison.Ordinal)))
                throw new JsonException("Invalid public avatar.");
        }
        foreach (var origin in new[] { "callSignOrigin", "avatarOrigin" })
            if (header.TryGetProperty(origin, out var o) && o.ValueKind is not (JsonValueKind.Null or JsonValueKind.String))
                throw new JsonException("Invalid public header origin.");
        var window = header.TryGetProperty("tradeWindow", out var w) ? PersonalProfileTradeWindow.Parse(w) : null;
        if (!v2) return new(visibility, callsign, avatar, window, affiliationStatus);
        var defaulted = header.GetProperty("defaulted");
        var masked = header.GetProperty("nameMasked");
        if (defaulted.ValueKind is not (JsonValueKind.True or JsonValueKind.False) ||
            masked.ValueKind is not (JsonValueKind.True or JsonValueKind.False))
            throw new JsonException("Invalid public header flags.");
        var facts = header.TryGetProperty("facts", out var f) ? PersonalProfilePublicFacts.Parse(f) : null;
        // An explicit visibility choice never carries the extra facts; a never-saved page is private by default.
        if (facts is not null && !defaulted.GetBoolean() || defaulted.GetBoolean() && visibility != "private")
            throw new JsonException("Invalid public header flags.");
        return new(visibility, callsign, avatar, window, affiliationStatus, defaulted.GetBoolean(), masked.GetBoolean(), facts);
    }

    internal object ToBridge() => new
    {
        schemaVersion = AccountBridgeSchema.Version,
        editable = false,
        restricted = true,
        visibility = Visibility,
        fleetAffiliationStatus = FleetAffiliationStatus,
        publicHeader = new
        {
            callSign = Callsign, avatarAssetId = AvatarAssetId, tradeWindow = TradeWindow?.ToPayload(),
            // Null values are not written: an answer without these facts keeps exactly the original keys.
            defaulted = Defaulted ? true : (bool?)null, nameMasked = NameMasked ? true : (bool?)null, facts = Facts?.ToPayload()
        }
    };
}

/// <summary>Carries a restricted visitor read through the shared profile reader to the bridge response.</summary>
internal sealed class PersonalProfileRestrictedException(PersonalProfilePublicHeader header) : Exception("profile.visitor_restricted")
{
    internal PersonalProfilePublicHeader Header { get; } = header;
}
