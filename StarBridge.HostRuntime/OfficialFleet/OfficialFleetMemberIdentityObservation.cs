using System.Collections.ObjectModel;
using System.Globalization;
using System.Text.Json;
using System.Text.RegularExpressions;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.OfficialFleet;

// A bounded per-row last observation, never a distributed permission lease.
internal sealed record OfficialFleetMemberIdentityObservation(OfficialFleetMemberIdentity Identity,
    DateTimeOffset IdentityObservedAtUtc, DateTimeOffset IdentityValidUntilUtc)
{
    internal static IReadOnlyDictionary<long, OfficialFleetMemberIdentityObservation> Parse(
        JsonElement root, string sourceRef, IReadOnlyCollection<long> requested, DateTimeOffset now)
    {
        try
        {
            RequireProperties(root, ["schemaVersion", "sourceRef", "members"]);
            if (root.GetProperty("schemaVersion").GetInt32() != 2 ||
                root.GetProperty("sourceRef").GetString() != sourceRef ||
                requested.Count is < 1 or > 100 || requested.Any(id => id <= 0) || requested.Distinct().Count() != requested.Count ||
                root.GetProperty("members") is not { ValueKind: JsonValueKind.Array } rows || rows.GetArrayLength() != requested.Count)
                throw OfficialFleetMemberIdentity.Invalid();
            var stamps = new Dictionary<long, (DateTimeOffset Observed, DateTimeOffset Until)>();
            using var bytes = new MemoryStream();
            using (var writer = new Utf8JsonWriter(bytes))
            {
                // Reuse V1's complete state, identity, duplicate and media validator.
                writer.WriteStartObject(); writer.WriteNumber("schemaVersion", 1); writer.WriteString("sourceRef", sourceRef);
                writer.WritePropertyName("members"); writer.WriteStartArray();
                foreach (var row in rows.EnumerateArray())
                {
                    RequireProperties(row, ["memberId", "state", "identityObservedAtUtc", "identityValidUntilUtc"],
                        ["businessSubjectId", "callsign", "avatarImageData"]);
                    var id = row.GetProperty("memberId").GetInt64();
                    if (!stamps.TryAdd(id, (Utc(row.GetProperty("identityObservedAtUtc")), Utc(row.GetProperty("identityValidUntilUtc")))))
                        throw OfficialFleetMemberIdentity.Invalid();
                    writer.WriteStartObject();
                    foreach (var property in row.EnumerateObject())
                        if (property.Name is not ("identityObservedAtUtc" or "identityValidUntilUtc")) property.WriteTo(writer);
                    writer.WriteEndObject();
                }
                writer.WriteEndArray(); writer.WriteEndObject();
            }
            using var identityDocument = JsonDocument.Parse(bytes.ToArray());
            var identities = OfficialFleetMemberIdentity.Parse(identityDocument.RootElement, sourceRef, requested);
            var result = identities.ToDictionary(p => p.Key, p => new OfficialFleetMemberIdentityObservation(
                p.Value, stamps[p.Key].Observed, stamps[p.Key].Until));
            EnsureCurrent(result.Values, now);
            return new ReadOnlyDictionary<long, OfficialFleetMemberIdentityObservation>(result);
        }
        catch (AccountBridgeHostException) { throw; }
        catch (Exception error) when (error is JsonException or InvalidOperationException or KeyNotFoundException or
            FormatException or OverflowException or ArgumentException)
        { throw OfficialFleetMemberIdentity.Invalid(); }
    }

    internal static void EnsureCurrent(IEnumerable<OfficialFleetMemberIdentityObservation> rows, DateTimeOffset now)
    {
        AccountReadTiming.Checkpoint(MemberReadCheckpoint.G1Deadline);
        foreach (var row in rows)
        {
            if (row.IdentityObservedAtUtc.Offset != TimeSpan.Zero || row.IdentityValidUntilUtc.Offset != TimeSpan.Zero ||
                row.IdentityObservedAtUtc - now > TimeSpan.FromSeconds(1) ||
                row.IdentityValidUntilUtc <= row.IdentityObservedAtUtc ||
                row.IdentityValidUntilUtc - row.IdentityObservedAtUtc > TimeSpan.FromSeconds(5) ||
                now >= row.IdentityValidUntilUtc) throw OfficialFleetMemberIdentity.Invalid();
        }
    }

    internal static DateTimeOffset Utc(JsonElement value)
    {
        var text = value.GetString();
        if (text is null || text.Length > 40 ||
            !Regex.IsMatch(text, @"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(?:\.[0-9]{1,7})?(?:Z|\+00:00)\z", RegexOptions.CultureInvariant) ||
            !DateTimeOffset.TryParse(text, CultureInfo.InvariantCulture, DateTimeStyles.None, out var parsed) || parsed.Offset != TimeSpan.Zero)
            throw OfficialFleetMemberIdentity.Invalid();
        return parsed;
    }

    private static void RequireProperties(JsonElement value, string[] required, string[]? optional = null)
    {
        if (value.ValueKind != JsonValueKind.Object) throw OfficialFleetMemberIdentity.Invalid();
        var names = value.EnumerateObject().Select(p => p.Name).ToArray();
        if (names.Distinct(StringComparer.Ordinal).Count() != names.Length || required.Any(n => !names.Contains(n)) ||
            names.Any(n => !required.Contains(n) && optional?.Contains(n) != true)) throw OfficialFleetMemberIdentity.Invalid();
    }
}
