using System;
using System.IO;

namespace StarBridge.Desktop;

internal sealed class TestBuildNoticeStore
{
    private const string AcknowledgementMarker = "starbridge-test-build-notice-v1";
    private readonly string _acknowledgementPath;

    public TestBuildNoticeStore(string? baseDirectory = null)
    {
        var root = string.IsNullOrWhiteSpace(baseDirectory)
            ? DesktopAppConfig.ConfigDirectory
            : baseDirectory;
        _acknowledgementPath = Path.Combine(root, "test-build-notice.acknowledged");
    }

    public bool IsAcknowledged()
    {
        try
        {
            return File.Exists(_acknowledgementPath) &&
                   string.Equals(
                       File.ReadAllText(_acknowledgementPath).Trim(),
                       AcknowledgementMarker,
                       StringComparison.Ordinal);
        }
        catch
        {
            return false;
        }
    }

    public bool TryAcknowledge(out string? error)
    {
        var temporaryPath = _acknowledgementPath + ".tmp";
        try
        {
            var directory = Path.GetDirectoryName(_acknowledgementPath);
            if (!string.IsNullOrWhiteSpace(directory))
            {
                Directory.CreateDirectory(directory);
            }

            File.WriteAllText(temporaryPath, AcknowledgementMarker);
            File.Move(temporaryPath, _acknowledgementPath, overwrite: true);
            error = null;
            return true;
        }
        catch (Exception ex)
        {
            TryDelete(temporaryPath);
            error = ex.Message;
            return false;
        }
    }

    private static void TryDelete(string path)
    {
        try
        {
            if (File.Exists(path))
            {
                File.Delete(path);
            }
        }
        catch
        {
            // A stale temporary marker is harmless and can be replaced later.
        }
    }
}
