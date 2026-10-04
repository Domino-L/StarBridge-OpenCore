namespace StarBridge.Core.Friends;

public sealed record RealtimeActivityContract(
    string InstanceId,
    long Version,
    DateTimeOffset ServerTime)
{
    // Older servers emit no promise of presence invalidations. Readers must
    // retain reconciliation until this capability is explicitly confirmed.
    [System.Text.Json.Serialization.JsonIgnore(Condition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingDefault)]
    public bool PresenceEvents { get; init; }
}
