using System.IO;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using StarBridge.Core.ShipMedia;

namespace StarBridge.Desktop;

internal sealed record HangarShipImageImportSummary(
    int CandidateCount,
    int AvailableCount,
    int DownloadedCount);

internal static class HangarImportedShipImageCache
{
    private const int MaximumDownloadBytes = 8 * 1024 * 1024;
    private const int MaximumDistinctImagesPerScan = 128;
    private const int PreferredMinimumLongEdge = 900;

    private static readonly HttpClient HttpClient = CreateHttpClient();

    internal static string? Resolve(string? shipCode)
    {
        var path = GetImagePath(shipCode);
        try
        {
            return path.Length > 0 &&
                   File.Exists(path) &&
                   new FileInfo(path).Length is > 0 and <= ShipMediaPolicy.MaximumImageBytes
                ? path
                : null;
        }
        catch (Exception exception) when (
            exception is IOException or
            UnauthorizedAccessException or
            ArgumentException or
            NotSupportedException)
        {
            return null;
        }
    }

    internal static async Task<HangarShipImageImportSummary> ImportAsync(
        IEnumerable<HangarShipImageCandidate> candidates,
        CancellationToken cancellationToken = default)
    {
        var selected = candidates
            .Where(candidate => IsAllowedSource(candidate.ImageUrl))
            .GroupBy(
                candidate => ShipNameLocalizer.NormalizeCode(candidate.Code),
                StringComparer.OrdinalIgnoreCase)
            .Select(group => group.First())
            .Take(MaximumDistinctImagesPerScan)
            .ToArray();
        if (selected.Length == 0)
        {
            return new HangarShipImageImportSummary(0, 0, 0);
        }

        using var gate = new SemaphoreSlim(3, 3);
        var available = 0;
        var downloaded = 0;
        await Task.WhenAll(selected.Select(async candidate =>
        {
            await gate.WaitAsync(cancellationToken);
            try
            {
                var result = await ImportOneAsync(candidate, cancellationToken);
                if (result.Available)
                {
                    Interlocked.Increment(ref available);
                }

                if (result.Downloaded)
                {
                    Interlocked.Increment(ref downloaded);
                }
            }
            finally
            {
                gate.Release();
            }
        }));

        return new HangarShipImageImportSummary(selected.Length, available, downloaded);
    }

    internal static async Task<HangarShipImageImportSummary> UpgradeExistingAsync(
        IEnumerable<string> shipCodes,
        CancellationToken cancellationToken = default)
    {
        var candidates = new List<HangarShipImageCandidate>();
        foreach (var code in shipCodes
                     .Select(ShipNameLocalizer.NormalizeCode)
                     .Where(code => !string.IsNullOrWhiteSpace(code))
                     .Distinct(StringComparer.OrdinalIgnoreCase))
        {
            try
            {
                var imagePath = GetImagePath(code);
                var sourcePath = GetSourcePath(code);
                if (imagePath.Length == 0 ||
                    sourcePath.Length == 0 ||
                    !File.Exists(imagePath) ||
                    !File.Exists(sourcePath) ||
                    HasPreferredQuality(imagePath))
                {
                    continue;
                }

                var sourceUrl = (await File.ReadAllTextAsync(sourcePath, cancellationToken)).Trim();
                if (IsAllowedSource(sourceUrl))
                {
                    candidates.Add(new HangarShipImageCandidate(code, sourceUrl));
                }
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                throw;
            }
            catch (Exception exception) when (
                exception is IOException or
                UnauthorizedAccessException or
                ArgumentException or
                NotSupportedException)
            {
                // Ignore one damaged cache entry and continue upgrading the remaining ships.
            }
        }

        return await ImportAsync(candidates, cancellationToken);
    }

    internal static bool IsAllowedSource(string? value)
    {
        if (!Uri.TryCreate(value?.Trim(), UriKind.Absolute, out var uri) ||
            !uri.Scheme.Equals(Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        return uri.Host.Equals("robertsspaceindustries.com", StringComparison.OrdinalIgnoreCase) ||
               uri.Host.EndsWith(".robertsspaceindustries.com", StringComparison.OrdinalIgnoreCase);
    }

    internal static IReadOnlyList<string> BuildDownloadCandidates(string sourceUrl)
    {
        if (!Uri.TryCreate(sourceUrl?.Trim(), UriKind.Absolute, out var sourceUri) ||
            !IsAllowedSource(sourceUri.AbsoluteUri))
        {
            return [];
        }

        var candidates = new List<string>();
        var path = sourceUri.AbsolutePath;
        if (sourceUri.Host.Equals("media.robertsspaceindustries.com", StringComparison.OrdinalIgnoreCase) &&
            path.EndsWith("/subscribers_vault_thumbnail.jpg", StringComparison.OrdinalIgnoreCase))
        {
            var builder = new UriBuilder(sourceUri)
            {
                Path = path[..(path.LastIndexOf('/') + 1)] + "source.jpg",
                Query = ""
            };
            candidates.Add(builder.Uri.AbsoluteUri);
        }

        const string legacyThumbnailSegment = "/subscribers_vault_thumbnail/";
        var legacyThumbnailIndex = path.IndexOf(legacyThumbnailSegment, StringComparison.OrdinalIgnoreCase);
        if (legacyThumbnailIndex >= 0)
        {
            var builder = new UriBuilder(sourceUri)
            {
                Path = path[..legacyThumbnailIndex] + "/source/" +
                       path[(legacyThumbnailIndex + legacyThumbnailSegment.Length)..],
                Query = ""
            };
            candidates.Add(builder.Uri.AbsoluteUri);
        }

        candidates.Add(sourceUri.AbsoluteUri);
        return candidates
            .Where(IsAllowedSource)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();
    }

    internal static bool MeetsPreferredQuality(int pixelWidth, int pixelHeight)
    {
        return pixelWidth > 0 &&
               pixelHeight > 0 &&
               Math.Max(pixelWidth, pixelHeight) >= PreferredMinimumLongEdge;
    }

    private static async Task<(bool Available, bool Downloaded)> ImportOneAsync(
        HangarShipImageCandidate candidate,
        CancellationToken cancellationToken)
    {
        var imagePath = GetImagePath(candidate.Code);
        var sourcePath = GetSourcePath(candidate.Code);
        if (imagePath.Length == 0 || sourcePath.Length == 0)
        {
            return (false, false);
        }

        try
        {
            if (File.Exists(imagePath) &&
                File.Exists(sourcePath) &&
                string.Equals(
                    (await File.ReadAllTextAsync(sourcePath, cancellationToken)).Trim(),
                    candidate.ImageUrl,
                    StringComparison.OrdinalIgnoreCase) &&
                Resolve(candidate.Code) is not null &&
                HasPreferredQuality(imagePath))
            {
                return (true, false);
            }

            foreach (var downloadUrl in BuildDownloadCandidates(candidate.ImageUrl))
            {
                var normalizedBytes = await TryDownloadNormalizedAsync(downloadUrl, cancellationToken);
                if (normalizedBytes is null)
                {
                    continue;
                }

                Directory.CreateDirectory(Path.GetDirectoryName(imagePath)!);
                var temporaryImagePath = imagePath + ".tmp";
                var temporarySourcePath = sourcePath + ".tmp";
                await File.WriteAllBytesAsync(temporaryImagePath, normalizedBytes, cancellationToken);
                await File.WriteAllTextAsync(temporarySourcePath, candidate.ImageUrl, Encoding.UTF8, cancellationToken);
                File.Move(temporaryImagePath, imagePath, overwrite: true);
                File.Move(temporarySourcePath, sourcePath, overwrite: true);
                return (true, true);
            }

            return (Resolve(candidate.Code) is not null, false);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception exception) when (
            exception is HttpRequestException or
            TaskCanceledException or
            IOException or
            InvalidDataException or
            FormatException or
            UnauthorizedAccessException or
            NotSupportedException or
            ArgumentException)
        {
            return (Resolve(candidate.Code) is not null, false);
        }
    }

    private static async Task<byte[]?> TryDownloadNormalizedAsync(
        string downloadUrl,
        CancellationToken cancellationToken)
    {
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, downloadUrl);
            request.Headers.Referrer = new Uri("https://robertsspaceindustries.com/account/pledges");
            using var response = await HttpClient.SendAsync(
                request,
                HttpCompletionOption.ResponseHeadersRead,
                cancellationToken);
            if (!response.IsSuccessStatusCode ||
                !IsAllowedSource(response.RequestMessage?.RequestUri?.AbsoluteUri) ||
                response.Content.Headers.ContentLength is > MaximumDownloadBytes)
            {
                return null;
            }

            var contentType = response.Content.Headers.ContentType?.MediaType ?? "";
            if (!contentType.StartsWith("image/", StringComparison.OrdinalIgnoreCase))
            {
                return null;
            }

            var sourceBytes = await ReadBoundedAsync(
                await response.Content.ReadAsStreamAsync(cancellationToken),
                cancellationToken);
            return NormalizeImage(sourceBytes);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception exception) when (
            exception is HttpRequestException or
            TaskCanceledException or
            IOException or
            InvalidDataException or
            FormatException or
            UnauthorizedAccessException or
            NotSupportedException or
            ArgumentException)
        {
            return null;
        }
    }

    private static bool HasPreferredQuality(string imagePath)
    {
        try
        {
            using var input = File.Open(imagePath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            var decoder = BitmapDecoder.Create(
                input,
                BitmapCreateOptions.PreservePixelFormat,
                BitmapCacheOption.OnLoad);
            var frame = decoder.Frames.FirstOrDefault();
            return frame is not null && MeetsPreferredQuality(frame.PixelWidth, frame.PixelHeight);
        }
        catch (Exception exception) when (
            exception is IOException or
            InvalidDataException or
            FormatException or
            UnauthorizedAccessException or
            NotSupportedException or
            ArgumentException)
        {
            return false;
        }
    }

    private static async Task<byte[]> ReadBoundedAsync(Stream source, CancellationToken cancellationToken)
    {
        using var target = new MemoryStream();
        var buffer = new byte[81920];
        while (true)
        {
            var read = await source.ReadAsync(buffer, cancellationToken);
            if (read == 0)
            {
                break;
            }

            if (target.Length + read > MaximumDownloadBytes)
            {
                throw new InvalidDataException("舰船图片超过本地读取上限。");
            }

            await target.WriteAsync(buffer.AsMemory(0, read), cancellationToken);
        }

        return target.ToArray();
    }

    private static byte[] NormalizeImage(byte[] bytes)
    {
        if (bytes.Length == 0)
        {
            throw new InvalidDataException("舰船图片没有可用内容。");
        }

        using var input = new MemoryStream(bytes, writable: false);
        var decoder = BitmapDecoder.Create(
            input,
            BitmapCreateOptions.PreservePixelFormat,
            BitmapCacheOption.OnLoad);
        var source = decoder.Frames.FirstOrDefault() ??
                     throw new InvalidDataException("舰船图片没有可用画面。");
        if ((long)source.PixelWidth * source.PixelHeight > 80_000_000)
        {
            throw new InvalidDataException("舰船图片尺寸过大。");
        }

        var scale = Math.Min(1d, Math.Min(1600d / source.PixelWidth, 900d / source.PixelHeight));
        BitmapSource output = source;
        if (scale < 1d)
        {
            output = new TransformedBitmap(source, new ScaleTransform(scale, scale));
            output.Freeze();
        }

        using var encoded = new MemoryStream();
        var png = new PngBitmapEncoder();
        png.Frames.Add(BitmapFrame.Create(output));
        png.Save(encoded);
        if (encoded.Length <= ShipMediaPolicy.MaximumImageBytes)
        {
            return encoded.ToArray();
        }

        encoded.SetLength(0);
        var jpeg = new JpegBitmapEncoder { QualityLevel = 86 };
        jpeg.Frames.Add(BitmapFrame.Create(output));
        jpeg.Save(encoded);
        if (encoded.Length > ShipMediaPolicy.MaximumImageBytes)
        {
            throw new InvalidDataException("舰船图片压缩后仍然过大。");
        }

        return encoded.ToArray();
    }

    private static string GetImagePath(string? shipCode)
    {
        var key = BuildStorageKey(shipCode);
        return key.Length == 0
            ? ""
            : Path.Combine(GetCacheDirectory(), $"{key}.image");
    }

    private static string GetSourcePath(string? shipCode)
    {
        var key = BuildStorageKey(shipCode);
        return key.Length == 0
            ? ""
            : Path.Combine(GetCacheDirectory(), $"{key}.source");
    }

    private static string GetCacheDirectory()
    {
        return Path.Combine(DesktopAppConfig.ConfigDirectory, "Images", "HangarImports");
    }

    private static string BuildStorageKey(string? shipCode)
    {
        var normalized = ShipNameLocalizer.NormalizeCode(shipCode);
        if (string.IsNullOrWhiteSpace(normalized) ||
            normalized.Equals("Unknown", StringComparison.OrdinalIgnoreCase))
        {
            return "";
        }

        var bytes = SHA256.HashData(Encoding.UTF8.GetBytes(normalized.ToLowerInvariant()));
        return Convert.ToHexString(bytes.AsSpan(0, 16)).ToLowerInvariant();
    }

    private static HttpClient CreateHttpClient()
    {
        var client = new HttpClient
        {
            Timeout = TimeSpan.FromSeconds(12)
        };
        client.DefaultRequestHeaders.UserAgent.ParseAdd("StarBridge/0.5 HangarImageReader");
        return client;
    }
}
