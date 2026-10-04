using System.Text.Json;
using StarBridge.Core.Friends;

namespace StarBridge.Core.Tests;

internal static class RealtimeActivityContractTests
{
    internal static void RunAll()
    {
        var options = new JsonSerializerOptions(JsonSerializerDefaults.Web);
        var original = new RealtimeActivityContract(new string('a', 32), 1, DateTimeOffset.UnixEpoch);
        var oldJson = JsonSerializer.Serialize(original, options);
        if (oldJson.Contains("presenceEvents", StringComparison.Ordinal) ||
            JsonSerializer.Deserialize<RealtimeActivityContract>(oldJson, options)!.PresenceEvents)
            throw new InvalidOperationException("Legacy activity must not promise presence delivery.");
        var upgraded = JsonSerializer.Deserialize<RealtimeActivityContract>(
            JsonSerializer.Serialize(original with { PresenceEvents = true }, options), options)!;
        if (!upgraded.PresenceEvents || upgraded.Version != 1 || upgraded.InstanceId != original.InstanceId)
            throw new InvalidOperationException("Presence capability must round-trip without changing the cursor.");
    }
}
