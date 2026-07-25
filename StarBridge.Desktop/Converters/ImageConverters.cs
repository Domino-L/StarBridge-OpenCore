using System.Globalization;
using System.IO;
using System.Runtime.CompilerServices;
using System.Windows.Data;
using System.Windows.Media.Imaging;

namespace StarBridge.Desktop;

public sealed class ImagePathConverter : IValueConverter
{
    public object? Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        if (value is not string path || string.IsNullOrWhiteSpace(path))
        {
            return null;
        }

        return ImageDecodeCache.Load(path, ParseDecodeWidth(parameter));
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
    {
        return System.Windows.Data.Binding.DoNothing;
    }

    internal static int ParseDecodeWidth(object? parameter)
    {
        return int.TryParse(
                   System.Convert.ToString(parameter, CultureInfo.InvariantCulture),
                   NumberStyles.Integer,
                   CultureInfo.InvariantCulture,
                   out var width)
               && width > 0
            ? Math.Clamp(width, 16, 2048)
            : 0;
    }
}

public sealed class ImageDataConverter : IValueConverter
{
    public object? Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        if (value is not string data || string.IsNullOrWhiteSpace(data))
        {
            return null;
        }

        return ImageDecodeCache.Load(data, ImagePathConverter.ParseDecodeWidth(parameter));
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
    {
        return System.Windows.Data.Binding.DoNothing;
    }
}

internal static class ImageDecodeCache
{
    private const int MaxFileEntries = 192;
    private static readonly object FileCacheGate = new();
    private static readonly Dictionary<string, LinkedListNode<FileCacheEntry>> FileCache = new(StringComparer.OrdinalIgnoreCase);
    private static readonly LinkedList<FileCacheEntry> FileLru = new();
    private static readonly ConditionalWeakTable<string, DataImageCache> DataCache = new();

    public static BitmapImage? Load(string source, int decodePixelWidth)
    {
        try
        {
            var filePath = ResolveImagePath(source);
            return filePath is not null
                ? LoadFile(filePath, decodePixelWidth)
                : DataCache.GetValue(source, static _ => new DataImageCache()).GetOrCreate(source, decodePixelWidth);
        }
        catch
        {
            return null;
        }
    }

    private static BitmapImage? LoadFile(string filePath, int decodePixelWidth)
    {
        var file = new FileInfo(filePath);
        var cacheKey = $"{file.FullName}|{file.LastWriteTimeUtc.Ticks}|{file.Length}|{decodePixelWidth}";
        lock (FileCacheGate)
        {
            if (FileCache.TryGetValue(cacheKey, out var cachedNode))
            {
                FileLru.Remove(cachedNode);
                FileLru.AddFirst(cachedNode);
                return cachedNode.Value.Image;
            }
        }

        using var stream = File.Open(file.FullName, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
        var image = Decode(stream, decodePixelWidth);
        lock (FileCacheGate)
        {
            if (FileCache.TryGetValue(cacheKey, out var existingNode))
            {
                return existingNode.Value.Image;
            }

            var node = FileLru.AddFirst(new FileCacheEntry(cacheKey, image));
            FileCache[cacheKey] = node;
            while (FileCache.Count > MaxFileEntries && FileLru.Last is { } expiredNode)
            {
                FileLru.RemoveLast();
                FileCache.Remove(expiredNode.Value.Key);
            }
        }

        return image;
    }

    private static BitmapImage Decode(Stream stream, int decodePixelWidth)
    {
        var image = new BitmapImage();
        image.BeginInit();
        image.CacheOption = BitmapCacheOption.OnLoad;
        if (decodePixelWidth > 0)
        {
            image.DecodePixelWidth = decodePixelWidth;
        }

        image.StreamSource = stream;
        image.EndInit();
        image.Freeze();
        return image;
    }

    private static string? ResolveImagePath(string value)
    {
        var path = value.Trim();
        if (File.Exists(path))
        {
            return Path.GetFullPath(path);
        }

        if (Path.IsPathRooted(path))
        {
            return null;
        }

        var appRelativePath = Path.Combine(AppContext.BaseDirectory, path);
        return File.Exists(appRelativePath) ? Path.GetFullPath(appRelativePath) : null;
    }

    private static byte[]? ReadDataBytes(string value)
    {
        var payload = value.Trim();
        var commaIndex = payload.IndexOf(',');
        if (payload.StartsWith("data:image/", StringComparison.OrdinalIgnoreCase) && commaIndex >= 0)
        {
            payload = payload[(commaIndex + 1)..];
        }

        return payload.Length < 64 ? null : System.Convert.FromBase64String(payload);
    }

    private sealed record FileCacheEntry(string Key, BitmapImage Image);

    private sealed class DataImageCache
    {
        private readonly object _gate = new();
        private readonly Dictionary<int, BitmapImage?> _images = [];

        public BitmapImage? GetOrCreate(string source, int decodePixelWidth)
        {
            lock (_gate)
            {
                if (_images.TryGetValue(decodePixelWidth, out var cached))
                {
                    return cached;
                }

                var bytes = ReadDataBytes(source);
                if (bytes is null || bytes.Length == 0)
                {
                    return null;
                }

                using var stream = new MemoryStream(bytes, writable: false);
                var image = Decode(stream, decodePixelWidth);
                _images[decodePixelWidth] = image;
                return image;
            }
        }
    }
}
