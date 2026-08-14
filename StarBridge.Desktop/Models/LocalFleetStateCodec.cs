using System.Text.Json;
using System.Text.Json.Serialization;

namespace StarBridge.Desktop;

internal static class LocalFleetStateCodec
{
    private static readonly JsonSerializerOptions CompatibilityOptions = new()
    {
        PropertyNameCaseInsensitive = true,
        UnmappedMemberHandling = JsonUnmappedMemberHandling.Skip
    };

    internal static string Serialize(LocalFleetState state) =>
        JsonSerializer.Serialize(state, CompatibilityOptions);

    internal static LocalFleetState? Deserialize(string json) =>
        JsonSerializer.Deserialize<LocalFleetState>(json, CompatibilityOptions);
}
