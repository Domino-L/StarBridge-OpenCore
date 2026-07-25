namespace StarBridge.Core.Friends;

public sealed record RealtimeActivityContract(
    string InstanceId,
    long Version,
    DateTimeOffset ServerTime);
