using System.Globalization;
using System.Text.Json;

namespace StarBridge.HostRuntime.OfficialFleet;

// Only public organization DTO IDs use SCM's number-or-string Long serializer.
// G1, bootstrap and Relay protocols retain their independently owned shapes.
internal static class OfficialFleetPublicId
{
    internal static long Read(JsonElement value)
    {
        var text = value.ValueKind switch {
            JsonValueKind.Number => value.GetRawText(),
            JsonValueKind.String => value.GetString(),
            _ => null
        };
        if (text is not { Length: >= 1 and <= 19 } || text[0] is < '1' or > '9')
            throw OfficialFleetReadModel.Invalid();
        foreach (var digit in text)
            if (digit is < '0' or > '9') throw OfficialFleetReadModel.Invalid();
        if (!long.TryParse(text, NumberStyles.None, CultureInfo.InvariantCulture, out var id))
            throw OfficialFleetReadModel.Invalid();
        return id;
    }
}
