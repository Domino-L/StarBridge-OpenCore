using System.Text.Json;

namespace StarBridge.HostRuntime.Account;

/// <summary>The optional account-facts v1 response. Public headers keep their original whitelist.</summary>
internal static class PersonalProfileAccountFacts
{
    internal static PersonalProfilePublicFacts? Parse(JsonElement root)
    {
        if (root.ValueKind != JsonValueKind.Object ||
            !root.EnumerateObject().Select(p => p.Name).Order(StringComparer.Ordinal)
                .SequenceEqual(["facts", "schemaVersion"], StringComparer.Ordinal) ||
            root.GetProperty("schemaVersion").ValueKind != JsonValueKind.Number ||
            !root.GetProperty("schemaVersion").TryGetInt32(out var version) || version != 1)
            throw new JsonException("Invalid account facts response.");
        var facts = root.GetProperty("facts");
        if (facts.ValueKind == JsonValueKind.Null) return null;
        if (facts.ValueKind != JsonValueKind.Object ||
            facts.EnumerateObject().Select(p => p.Name).Distinct(StringComparer.Ordinal).Count() != facts.EnumerateObject().Count())
            throw new JsonException("Invalid account facts.");
        // User 2026-11-05: last online follows the online-status privacy. Only the
        // server's explicit yes shows it; a missing flag (an older server) hides it.
        var visible = false;
        if (facts.TryGetProperty("lastOnlineVisible", out var flag))
        {
            if (flag.ValueKind is not (JsonValueKind.True or JsonValueKind.False))
                throw new JsonException("Invalid last online visibility.");
            visible = flag.GetBoolean();
        }
        // Strip only this route's extra flag. Every other key and value still passes
        // through the existing parser, including a hidden last-online day's format.
        var fields = facts.EnumerateObject().Where(p => p.Name != "lastOnlineVisible")
            .ToDictionary(p => p.Name, p => p.Value);
        var parsed = PersonalProfilePublicFacts.Parse(JsonSerializer.SerializeToElement(fields));
        return !visible && parsed is not null ? parsed with { LastOnlineDay = null } : parsed;
    }
}
