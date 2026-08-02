using System.Drawing.Imaging;
using System.IO;
using System.Windows.Forms;

namespace StarBridge.Desktop;

internal static class InGameBrowserAddressPolicy
{
    private static readonly Uri SearchHome = new("https://cn.bing.com/");

    internal static bool TryNormalize(string? input, out Uri uri)
    {
        uri = null!;
        var candidate = input?.Trim();
        if (string.IsNullOrWhiteSpace(candidate))
        {
            return false;
        }

        if (!candidate.Contains("://", StringComparison.Ordinal))
        {
            candidate = $"https://{candidate}";
        }

        if (!Uri.TryCreate(candidate, UriKind.Absolute, out var parsed) ||
            parsed.Scheme is not ("http" or "https") ||
            string.IsNullOrWhiteSpace(parsed.Host) ||
            !string.IsNullOrEmpty(parsed.UserInfo))
        {
            return false;
        }

        uri = parsed;
        return true;
    }

    internal static bool TryResolveNavigation(string? input, out Uri uri)
    {
        return TryResolveNavigation(input, SearchHome, out uri);
    }

    internal static bool TryResolveNavigation(
        string? input,
        Uri searchHome,
        out Uri uri)
    {
        ArgumentNullException.ThrowIfNull(searchHome);
        uri = null!;
        var candidate = input?.Trim();
        if (string.IsNullOrWhiteSpace(candidate) ||
            candidate.Any(char.IsControl))
        {
            return false;
        }

        var looksLikeAddress =
            candidate.Contains("://", StringComparison.Ordinal) ||
            !candidate.Any(char.IsWhiteSpace) &&
            (candidate.Contains('.') ||
             candidate.StartsWith("localhost", StringComparison.OrdinalIgnoreCase));
        if (looksLikeAddress)
        {
            return TryNormalize(candidate, out uri);
        }

        if (HasExplicitScheme(candidate))
        {
            return false;
        }

        var escapedQuery = Uri.EscapeDataString(candidate);
        uri = searchHome.Host.ToLowerInvariant() switch
        {
            "www.baidu.com" => new Uri(searchHome, $"s?wd={escapedQuery}"),
            "duckduckgo.com" => new Uri(searchHome, $"?q={escapedQuery}"),
            _ => new Uri(searchHome, $"search?q={escapedQuery}")
        };
        return true;
    }

    private static bool HasExplicitScheme(string candidate)
    {
        var separator = candidate.IndexOf(':');
        if (separator <= 0)
        {
            return false;
        }

        return candidate[..separator].All(character =>
            char.IsAsciiLetterOrDigit(character) ||
            character is '+' or '-' or '.');
    }
}

internal static class InGameImageFilePolicy
{
    private static readonly HashSet<string> SupportedExtensions =
        new(StringComparer.OrdinalIgnoreCase)
        {
            ".png",
            ".jpg",
            ".jpeg",
            ".bmp",
            ".gif",
            ".tif",
            ".tiff"
        };

    internal static bool IsSupported(string? path) =>
        !string.IsNullOrWhiteSpace(path) &&
        SupportedExtensions.Contains(Path.GetExtension(path));
}

internal static class InGameGuideImageVisibilityPolicy
{
    internal static bool ShouldShow(
        bool menuSessionActive,
        bool pinnedToOverlay,
        bool gameForeground) =>
        menuSessionActive || pinnedToOverlay && gameForeground;
}

internal static class InGameScreenshotPathPolicy
{
    internal static string ResolveDirectory()
        => ResolveDirectory(null);

    internal static string ResolveDirectory(string? preferredDirectory)
    {
        var preferred = preferredDirectory?.Trim();
        if (!string.IsNullOrWhiteSpace(preferred))
        {
            return Path.GetFullPath(
                Environment.ExpandEnvironmentVariables(preferred));
        }

        var pictures = Environment.GetFolderPath(Environment.SpecialFolder.MyPictures);
        return string.IsNullOrWhiteSpace(pictures)
            ? Path.Combine(DesktopAppConfig.ConfigDirectory, "Screenshots")
            : Path.Combine(pictures, "StarBridge", "Screenshots");
    }

    internal static string CreatePath(
        string directory,
        DateTimeOffset capturedAt,
        Func<string, bool>? fileExists = null)
        => CreatePath(
            directory,
            capturedAt,
            InGameMenuScreenshotFormat.Png,
            fileExists);

    internal static string CreatePath(
        string directory,
        DateTimeOffset capturedAt,
        InGameMenuScreenshotFormat format,
        Func<string, bool>? fileExists = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(directory);
        fileExists ??= File.Exists;

        var stem = $"StarBridge_{capturedAt:yyyyMMdd_HHmmss_fff}";
        var extension = format == InGameMenuScreenshotFormat.Jpeg
            ? ".jpg"
            : ".png";
        var candidate = Path.Combine(directory, $"{stem}{extension}");
        for (var suffix = 2; fileExists(candidate); suffix++)
        {
            candidate = Path.Combine(
                directory,
                $"{stem}_{suffix:00}{extension}");
        }

        return candidate;
    }
}

internal static class InGameScreenCapture
{
    internal static Task<string> CaptureAsync(
        IntPtr preferredWindowHandle,
        CancellationToken cancellationToken = default)
        => CaptureAsync(
            preferredWindowHandle,
            InGameMenuSettings.Default,
            cancellationToken);

    internal static Task<string> CaptureAsync(
        IntPtr preferredWindowHandle,
        InGameMenuSettings settings,
        CancellationToken cancellationToken = default)
    {
        var normalized = settings.Normalize();
        var screen = preferredWindowHandle != IntPtr.Zero
            ? Screen.FromHandle(preferredWindowHandle)
            : Screen.PrimaryScreen ?? Screen.AllScreens.First();
        var bounds = screen.Bounds;
        var directory = InGameScreenshotPathPolicy.ResolveDirectory(
            normalized.ScreenshotDirectory);
        var path = InGameScreenshotPathPolicy.CreatePath(
            directory,
            DateTimeOffset.Now,
            normalized.ScreenshotFormat);

        return Task.Run(() =>
        {
            cancellationToken.ThrowIfCancellationRequested();
            Directory.CreateDirectory(directory);
            using var bitmap = new System.Drawing.Bitmap(
                bounds.Width,
                bounds.Height,
                System.Drawing.Imaging.PixelFormat.Format32bppArgb);
            using var graphics = System.Drawing.Graphics.FromImage(bitmap);
            graphics.CopyFromScreen(
                bounds.Left,
                bounds.Top,
                0,
                0,
                bounds.Size,
                CopyPixelOperation.SourceCopy);
            cancellationToken.ThrowIfCancellationRequested();
            if (normalized.ScreenshotFormat ==
                InGameMenuScreenshotFormat.Jpeg)
            {
                SaveJpeg(
                    bitmap,
                    path,
                    normalized.ScreenshotJpegQuality);
            }
            else
            {
                bitmap.Save(path, ImageFormat.Png);
            }

            return path;
        }, cancellationToken);
    }

    private static void SaveJpeg(
        System.Drawing.Bitmap bitmap,
        string path,
        int quality)
    {
        var encoder = ImageCodecInfo.GetImageEncoders()
            .First(codec => codec.FormatID == ImageFormat.Jpeg.Guid);
        using var parameters = new EncoderParameters(1);
        parameters.Param[0] = new EncoderParameter(
            System.Drawing.Imaging.Encoder.Quality,
            Math.Clamp(quality, 50, 100));
        bitmap.Save(path, encoder, parameters);
    }
}
