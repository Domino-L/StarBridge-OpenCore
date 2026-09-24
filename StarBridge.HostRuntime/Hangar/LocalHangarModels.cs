using System.Text.Json.Serialization;

namespace StarBridge.HostRuntime.Hangar;

public sealed record LocalHangarShip(
    [property: JsonRequired] string Id, [property: JsonRequired] string PledgeKey,
    [property: JsonRequired] string Title, [property: JsonRequired] string? Liner,
    [property: JsonRequired] string? AcquiredText, [property: JsonRequired] DateTimeOffset AddedAt,
    string? CustomImagePath = null, LocalHangarImageCrop? CustomImageCrop = null,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] DateTimeOffset? RemovedAt = null);

/// <summary>Normalized image rectangle; preserved metadata only, never loaded by this store.</summary>
public sealed record LocalHangarImageCrop(
    [property: JsonRequired] double X, [property: JsonRequired] double Y,
    [property: JsonRequired] double Width, [property: JsonRequired] double Height);

public sealed record LocalHangarSnapshot(
    [property: JsonRequired] long Revision, [property: JsonRequired] DateTimeOffset? SavedAt,
    [property: JsonRequired] string? OperationId, [property: JsonRequired] IReadOnlyList<LocalHangarShip> Ships,
    [property: JsonRequired] bool Partial = false,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] IReadOnlyList<LocalHangarShip>? FormerShips = null);

public sealed class LocalHangarStoreException : Exception
{
    public string Code { get; }
    public LocalHangarStoreException(string code, string message, Exception? innerException = null)
        : base(message, innerException) => Code = code;
}
