namespace StarBridge.NativeBridge;

using System.Text.Json;
using System.Text.Json.Serialization;

public static class BridgeProtocol
{
    public const int CurrentVersion = 1;
    public const int DefaultQueueCapacity = 128;
    public const int MaximumFrameBytes = 1024 * 1024;
    // Two 2 MiB images plus base64/JSON overhead for profile-save requests.
    public const int MaximumCommunityProfileFrameBytes = 8 * 1024 * 1024;
    public const int MaximumCommunityWideImageFrameBytes = 4 * 1024 * 1024;

    internal static int FrameLimit(BridgeEnvelope envelope) =>
        envelope.MessageType == BridgeMessageTypes.Request && envelope.Name == "communities.saveProfile"
            ? MaximumCommunityProfileFrameBytes :
        envelope.MessageType == BridgeMessageTypes.Response && envelope.Name == "communities.cropWideImage"
            ? MaximumCommunityWideImageFrameBytes : MaximumFrameBytes;

    public static readonly TimeSpan DefaultRequestTimeout = TimeSpan.FromSeconds(15);

    public static JsonSerializerOptions JsonOptions { get; } = CreateJsonOptions();

    private static JsonSerializerOptions CreateJsonOptions()
    {
        return new JsonSerializerOptions
        {
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
            PropertyNameCaseInsensitive = false,
            DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
            WriteIndented = false
        };
    }
}

public static class BridgeMessageTypes
{
    public const string Request = "request";
    public const string Response = "response";
    public const string Event = "event";
}

public static class BridgeResponseStatuses
{
    public const string Ok = "ok";
    public const string Error = "error";
    public const string Cancelled = "cancelled";
}

public static class BridgeErrorCodes
{
    public const string ProtocolIncompatible = "bridge.protocol_incompatible";
    public const string InvalidEnvelope = "bridge.invalid_envelope";
    public const string AccountContextRequired = "bridge.account_context_required";
    public const string StaleGeneration = "bridge.stale_generation";
    public const string Cancelled = "bridge.cancelled";
    public const string Timeout = "bridge.timeout";
    public const string Disconnected = "bridge.disconnected";
    public const string HostError = "bridge.host_error";
    public const string Backpressure = "bridge.backpressure";
    public const string CapabilityUnavailable = "bridge.capability_unavailable";
}
