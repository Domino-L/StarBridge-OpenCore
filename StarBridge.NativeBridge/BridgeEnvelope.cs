namespace StarBridge.NativeBridge;

using System.Text.Json;

public sealed record BridgeAccountContext(
    string Environment,
    string Authority,
    string Subject)
{
    public bool IsComplete =>
        !string.IsNullOrWhiteSpace(Environment) &&
        !string.IsNullOrWhiteSpace(Authority) &&
        !string.IsNullOrWhiteSpace(Subject);
}

public sealed record BridgeError(
    string Code,
    string Message,
    bool Retryable = false);

public sealed record BridgeEnvelope
{
    public int ProtocolVersion { get; init; } = BridgeProtocol.CurrentVersion;

    public required string MessageType { get; init; }

    public required string Name { get; init; }

    public string? CorrelationId { get; init; }

    public long SessionGeneration { get; init; }

    public BridgeAccountContext? AccountContext { get; init; }

    public long? Sequence { get; init; }

    public JsonElement Payload { get; init; } = BridgePayload.Empty;

    public string? Status { get; init; }

    public BridgeError? Error { get; init; }

    public static BridgeEnvelope Request(
        string name,
        string correlationId,
        long sessionGeneration,
        object? payload = null,
        BridgeAccountContext? accountContext = null)
    {
        return new BridgeEnvelope
        {
            MessageType = BridgeMessageTypes.Request,
            Name = name,
            CorrelationId = correlationId,
            SessionGeneration = sessionGeneration,
            AccountContext = accountContext,
            Payload = BridgePayload.From(payload)
        };
    }

    public static BridgeEnvelope Response(
        BridgeEnvelope request,
        object? payload = null,
        BridgeAccountContext? accountContext = null,
        bool preserveRequestAccountContext = true)
    {
        return new BridgeEnvelope
        {
            MessageType = BridgeMessageTypes.Response,
            Name = request.Name,
            CorrelationId = request.CorrelationId,
            SessionGeneration = request.SessionGeneration,
            AccountContext = accountContext ??
                (preserveRequestAccountContext ? request.AccountContext : null),
            Payload = BridgePayload.From(payload),
            Status = BridgeResponseStatuses.Ok
        };
    }

    public static BridgeEnvelope ErrorResponse(
        BridgeEnvelope request,
        BridgeError error)
    {
        return new BridgeEnvelope
        {
            MessageType = BridgeMessageTypes.Response,
            Name = request.Name,
            CorrelationId = request.CorrelationId,
            SessionGeneration = request.SessionGeneration,
            AccountContext = request.AccountContext,
            Payload = BridgePayload.Empty,
            Status = BridgeResponseStatuses.Error,
            Error = error
        };
    }

    public static BridgeEnvelope CancelledResponse(BridgeEnvelope request)
    {
        return new BridgeEnvelope
        {
            MessageType = BridgeMessageTypes.Response,
            Name = request.Name,
            CorrelationId = request.CorrelationId,
            SessionGeneration = request.SessionGeneration,
            AccountContext = request.AccountContext,
            Payload = BridgePayload.Empty,
            Status = BridgeResponseStatuses.Cancelled,
            Error = new BridgeError(BridgeErrorCodes.Cancelled, "The request was cancelled.")
        };
    }

    public static BridgeEnvelope Event(
        string name,
        long sessionGeneration,
        long sequence,
        object? payload = null)
    {
        return new BridgeEnvelope
        {
            MessageType = BridgeMessageTypes.Event,
            Name = name,
            SessionGeneration = sessionGeneration,
            Sequence = sequence,
            Payload = BridgePayload.From(payload)
        };
    }
}

public static class BridgePayload
{
    public static JsonElement Empty => JsonSerializer.SerializeToElement(
        new Dictionary<string, object?>(),
        BridgeProtocol.JsonOptions);

    public static JsonElement From(object? value)
    {
        return value is JsonElement element
            ? element.Clone()
            : JsonSerializer.SerializeToElement(value ?? new Dictionary<string, object?>(), BridgeProtocol.JsonOptions);
    }
}
