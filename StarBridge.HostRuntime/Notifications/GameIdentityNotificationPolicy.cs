namespace StarBridge.HostRuntime.Notifications;

/// <summary>Host-owned identity assessment. Never accepted from a bridge payload or rendered externally.</summary>
public sealed record GameIdentityNotificationPolicy(
    string State, string? AuthoritativeHandle, string? DetectedHandle);
