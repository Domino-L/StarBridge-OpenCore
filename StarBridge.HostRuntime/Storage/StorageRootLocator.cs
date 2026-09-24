using System.Text;

namespace StarBridge.HostRuntime.Storage;

/// <summary>Shared S2 locator encoding and absolute-path contract, without cached roots.</summary>
public static class StorageRootLocator
{
    public const string FileName = "data-root.path";
    private static readonly UTF8Encoding Utf8 = new(false, true);

    public static string Read(string bootstrap)
    {
        var root = Normalize(bootstrap);
        var path = Path.Combine(root, FileName);
        if (!File.Exists(path)) return root;
        if (new FileInfo(path).Length > 131072 || (File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0)
            throw new InvalidDataException("Invalid data-root locator.");
        var bytes = File.ReadAllBytes(path);
        string value;
        try { value = Utf8.GetString(bytes); }
        catch (DecoderFallbackException)
        {
            Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);
            value = Encoding.GetEncoding(System.Globalization.CultureInfo.CurrentCulture.TextInfo.ANSICodePage,
                EncoderFallback.ExceptionFallback, DecoderFallback.ExceptionFallback).GetString(bytes);
        }
        return Normalize(value.Trim().TrimStart('\uFEFF'));
    }

    internal static void Write(string bootstrap, string destination)
    {
        var path = Path.Combine(Normalize(bootstrap), FileName);
        var temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None))
        {
            stream.Write(Utf8.GetBytes(Normalize(destination) + Environment.NewLine));
            stream.Flush(flushToDisk: true);
        }
        File.Move(temporary, path, overwrite: true);
    }

    internal static string Normalize(string path)
    {
        var expanded = Environment.ExpandEnvironmentVariables(path.Trim());
        if (string.IsNullOrWhiteSpace(expanded) || !Path.IsPathFullyQualified(expanded) || expanded.Contains('\uFFFD'))
            throw new InvalidDataException("Data root must be a valid absolute path.");
        return Path.TrimEndingDirectorySeparator(Path.GetFullPath(expanded));
    }
}
