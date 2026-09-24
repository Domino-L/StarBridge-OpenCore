namespace StarBridge.NativeBridge;

public sealed record BridgeProtocolRange(int Minimum, int Maximum);

public sealed record BridgeHelloRequest(
    BridgeProtocolRange Protocols,
    IReadOnlyList<string> Capabilities);

public sealed record BridgeHelloResponse(
    int SelectedProtocol,
    IReadOnlyList<string> HostCapabilities,
    string HostInstanceId,
    long SessionGeneration,
    int MaximumFrameBytes);

public static class BridgeHandshake
{
    public static BridgeHelloResponse Negotiate(
        BridgeHelloRequest request,
        IEnumerable<string> hostCapabilities,
        string hostInstanceId,
        long sessionGeneration)
    {
        ArgumentNullException.ThrowIfNull(request);
        ArgumentNullException.ThrowIfNull(hostCapabilities);

        if (request.Protocols.Minimum > BridgeProtocol.CurrentVersion ||
            request.Protocols.Maximum < BridgeProtocol.CurrentVersion)
        {
            throw new BridgeProtocolVersionException(
                $"Client supports {request.Protocols.Minimum}-{request.Protocols.Maximum}; " +
                $"host supports {BridgeProtocol.CurrentVersion}.");
        }

        if (string.IsNullOrWhiteSpace(hostInstanceId))
        {
            throw new ArgumentException("Host instance ID is required.", nameof(hostInstanceId));
        }

        return new BridgeHelloResponse(
            BridgeProtocol.CurrentVersion,
            hostCapabilities.Distinct(StringComparer.Ordinal).Order(StringComparer.Ordinal).ToArray(),
            hostInstanceId,
            sessionGeneration,
            BridgeProtocol.MaximumFrameBytes);
    }
}

public static class BridgeEnvelopeValidator
{
    public static void ValidateWireShape(BridgeEnvelope envelope)
    {
        ArgumentNullException.ThrowIfNull(envelope);

        if (envelope.ProtocolVersion <= 0)
        {
            throw new BridgeProtocolException(BridgeErrorCodes.InvalidEnvelope, "Protocol version must be positive.");
        }

        if (string.IsNullOrWhiteSpace(envelope.Name))
        {
            throw new BridgeProtocolException(BridgeErrorCodes.InvalidEnvelope, "Message name is required.");
        }

        if (envelope.SessionGeneration < 0)
        {
            throw new BridgeProtocolException(BridgeErrorCodes.InvalidEnvelope, "Session generation cannot be negative.");
        }

        if (envelope.AccountContext is { IsComplete: false })
        {
            throw new BridgeProtocolException(
                BridgeErrorCodes.AccountContextRequired,
                "Account context must include environment, authority, and subject.");
        }

        switch (envelope.MessageType)
        {
            case BridgeMessageTypes.Request:
                RequireCorrelation(envelope);
                break;
            case BridgeMessageTypes.Response:
                RequireCorrelation(envelope);
                ValidateResponse(envelope);
                break;
            case BridgeMessageTypes.Event:
                if (envelope.Sequence is null or < 0)
                {
                    throw new BridgeProtocolException(
                        BridgeErrorCodes.InvalidEnvelope,
                        "Events require a non-negative sequence.");
                }
                break;
            default:
                throw new BridgeProtocolException(
                    BridgeErrorCodes.InvalidEnvelope,
                    $"Unsupported message type '{envelope.MessageType}'.");
        }
    }

    public static void RequireCurrentVersion(BridgeEnvelope envelope)
    {
        if (envelope.ProtocolVersion != BridgeProtocol.CurrentVersion)
        {
            throw new BridgeProtocolVersionException(
                $"Received protocol {envelope.ProtocolVersion}; expected {BridgeProtocol.CurrentVersion}.");
        }
    }

    public static void RequireAccountContext(string requestName, BridgeAccountContext? context)
    {
        if (BridgeRequestPolicy.RequiresAccountContext(requestName) && context is not { IsComplete: true })
        {
            throw new BridgeProtocolException(
                BridgeErrorCodes.AccountContextRequired,
                $"Request '{requestName}' requires a complete account context.");
        }
    }

    private static void RequireCorrelation(BridgeEnvelope envelope)
    {
        if (string.IsNullOrWhiteSpace(envelope.CorrelationId))
        {
            throw new BridgeProtocolException(
                BridgeErrorCodes.InvalidEnvelope,
                $"{envelope.MessageType} messages require a correlation ID.");
        }
    }

    private static void ValidateResponse(BridgeEnvelope envelope)
    {
        if (envelope.Status is not (
            BridgeResponseStatuses.Ok or
            BridgeResponseStatuses.Error or
            BridgeResponseStatuses.Cancelled))
        {
            throw new BridgeProtocolException(BridgeErrorCodes.InvalidEnvelope, "Response status is invalid.");
        }

        if (envelope.Status == BridgeResponseStatuses.Error && envelope.Error is null)
        {
            throw new BridgeProtocolException(BridgeErrorCodes.InvalidEnvelope, "Error responses require an error body.");
        }
    }
}

public static class BridgeRequestPolicy
{
    private static readonly HashSet<string> OutOfBandControlRequests = new(StringComparer.Ordinal)
    {
        "account.cancelLogin",
        "bridge.cancel",
        "host.shutdown"
    };

    private static readonly HashSet<string> AccountAgnosticRequests = new(StringComparer.Ordinal)
    {
        "host.hello",
        "host.ready",
        "host.getGamePresence",
        "host.shutdown",
        "account.getCurrent",
        "account.sendPasswordResetCode",
        "account.confirmPasswordReset",
        "account.loginLegacy",
        "account.login",
        "account.cancelLogin",
        "applicationPreferences.get",
        "applicationPreferences.update",
        "notificationAudio.read",
        "playReminder.read",
        "playReminder.save",
        "notificationSettings.read",
        "notificationSettings.save",
        "notificationSettings.presentDesktop",
        "notificationSettings.testDesktop",
        "notificationSettings.clearDesktop",
        "notificationSettings.consumeActivation",
        "notificationAudio.save",
        "notificationAudio.preview",
        "notificationAudio.stop",
        "runtime.getSnapshot",
        "overlay.getState",
        "overlay.getWorkspace",
        "overlay.updateWorkspace",
        "overlay.runtime.getState",
        "overlay.runtime.open",
        "overlay.runtime.close",
        "overlay.runtime.retry",
        "overlay.preview",
        "overlay.update",
        "diagnostics.getSafeSummary",
        "diagnostics.openDataDirectory",
        "diagnostics.getDataLocation",
        "diagnostics.clearImageCache",
        "diagnostics.openInstalledApps",
        "diagnostics.flutterInstallation",
        "diagnostics.flutterInstallationExecute",
        "legal.getClientLicense",
        "legal.readTestBuildNotice",
        "legal.acceptTestBuildNotice",
        "diagnostics.getRuntimeFacts",
        "diagnostics.getOverlayRuntimeStatus",
        "diagnostics.getLocalEvents",
        "diagnostics.exportLocalEvents",
        "diagnostics.clearLocalEvents",
        "bridge.cancel"
    };

    public static bool RequiresAccountContext(string requestName) =>
        !AccountAgnosticRequests.Contains(requestName);

    public static bool IsOutOfBandControl(string requestName) =>
        OutOfBandControlRequests.Contains(requestName);
}

public class BridgeProtocolException : Exception
{
    public BridgeProtocolException(string code, string message)
        : base(message)
    {
        Code = code;
    }

    public string Code { get; }
}

public sealed class BridgeProtocolVersionException : BridgeProtocolException
{
    public BridgeProtocolVersionException(string message)
        : base(BridgeErrorCodes.ProtocolIncompatible, message)
    {
    }
}

public sealed class BridgeStaleGenerationException : BridgeProtocolException
{
    public BridgeStaleGenerationException(long requestGeneration, long activeGeneration)
        : base(
            BridgeErrorCodes.StaleGeneration,
            $"Request generation {requestGeneration} is stale; active generation is {activeGeneration}.")
    {
    }
}

public sealed class BridgeDisconnectedException : BridgeProtocolException
{
    public BridgeDisconnectedException(string message, Exception? innerException = null)
        : base(BridgeErrorCodes.Disconnected, message)
    {
        if (innerException is not null)
        {
            Data[nameof(InnerException)] = innerException.GetType().Name;
        }
    }
}

public sealed class BridgeRemoteException : BridgeProtocolException
{
    public BridgeRemoteException(BridgeError error)
        : base(error.Code, error.Message)
    {
        Retryable = error.Retryable;
    }

    public bool Retryable { get; }
}
