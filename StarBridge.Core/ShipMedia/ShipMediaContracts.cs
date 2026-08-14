namespace StarBridge.Core.ShipMedia;

public sealed record ShipMediaSummaryContract(
    string MediaId,
    string ShipInstanceId,
    string ShipCode,
    string ShipDisplayName,
    string OwnerAccountId,
    string OwnerDisplayName,
    string ContentType,
    int Width,
    int Height,
    long SizeBytes,
    DateTimeOffset UpdatedAt,
    double CropFocusX = 0.5,
    double CropFocusY = 0.5,
    double CropZoom = 1.0)
{
    public ShipImageCropFrame CropFrame => ShipImageCropFrame.Normalize(
        CropFocusX,
        CropFocusY,
        CropZoom);
}

public sealed record ShipMediaCatalogContract(
    ShipMediaSummaryContract[] Items,
    DateTimeOffset UpdatedAt);

public sealed record ShipMediaUploadRequestContract(
    string ShipInstanceId,
    string ShipCode,
    string ShipDisplayName,
    string ImageBase64,
    string ClientRequestId,
    double CropFocusX = 0.5,
    double CropFocusY = 0.5,
    double CropZoom = 1.0);

public sealed record ShipMediaUploadResponseContract(
    ShipMediaSummaryContract Media,
    string Status);

public static class ShipMediaPolicy
{
    public const int MaximumImageBytes = 2 * 1024 * 1024;
    public const int MaximumDimension = 4096;
    public const long MaximumPixels = 16_000_000;
    public const int MaximumUploadsPerHour = 20;
}

public static class ShipMediaModerationStatuses
{
    public const string Available = "available";
    public const string Quarantined = "quarantined";

    public static string Normalize(string? value) => value?.Trim().ToLowerInvariant() switch
    {
        Quarantined => Quarantined,
        _ => Available
    };
}

public readonly record struct ShipImageCropFrame(
    double FocusX,
    double FocusY,
    double Zoom)
{
    public const double MinimumZoom = 1.0;
    public const double MaximumZoom = 3.0;

    public static ShipImageCropFrame Default => new(0.5, 0.5, MinimumZoom);

    public static ShipImageCropFrame Normalize(double focusX, double focusY, double zoom)
    {
        // Older records do not contain crop metadata and deserialize all three
        // values as zero. Treat that shape as the centered legacy default rather
        // than silently pinning the square preview to the upper-left corner.
        if (!double.IsFinite(zoom) || zoom < MinimumZoom)
        {
            return Default;
        }

        return new(
            NormalizeFocus(focusX),
            NormalizeFocus(focusY),
            NormalizeZoom(zoom));
    }

    private static double NormalizeFocus(double value) =>
        double.IsFinite(value) ? Math.Clamp(value, 0.0, 1.0) : 0.5;

    private static double NormalizeZoom(double value) =>
        double.IsFinite(value) && value >= MinimumZoom
            ? Math.Clamp(value, MinimumZoom, MaximumZoom)
            : MinimumZoom;
}
