namespace StarBridge.Desktop;

public readonly record struct FleetImageSyncPayloadCheck(bool CanSync, string? Message);

public static class FleetImageSyncGuard
{
    public static FleetImageSyncPayloadCheck CheckRequiredImage(
        bool required,
        string imageLabel,
        string? imagePath,
        string? imageData)
    {
        if (!required)
        {
            return new FleetImageSyncPayloadCheck(true, null);
        }

        if (string.IsNullOrWhiteSpace(imagePath))
        {
            return new FleetImageSyncPayloadCheck(false, $"{imageLabel}同步失败：没有可用的图片文件，请重新选择图片。");
        }

        if (string.IsNullOrWhiteSpace(imageData))
        {
            return new FleetImageSyncPayloadCheck(false, $"{imageLabel}同步失败：图片文件过大或无法读取，请重新选择较小的 JPG / PNG 图片。");
        }

        return new FleetImageSyncPayloadCheck(true, null);
    }
}
