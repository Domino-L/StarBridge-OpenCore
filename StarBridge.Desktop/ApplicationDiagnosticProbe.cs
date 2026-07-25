using System.IO;

namespace StarBridge.Desktop;

internal sealed record ApplicationDiagnosticResult(string Name, bool Passed, string Detail);

internal static class ApplicationDiagnosticProbe
{
    public static ApplicationDiagnosticResult CheckWritableDirectory(string? directory)
    {
        if (string.IsNullOrWhiteSpace(directory))
        {
            return new ApplicationDiagnosticResult("配置目录", false, "路径未配置");
        }

        var probePath = Path.Combine(directory, $".write-check-{Guid.NewGuid():N}.tmp");
        try
        {
            Directory.CreateDirectory(directory);
            File.WriteAllText(probePath, "StarBridge diagnostic probe");
            File.Delete(probePath);
            return new ApplicationDiagnosticResult("配置目录", true, "可正常写入");
        }
        catch (Exception ex)
        {
            TryDelete(probePath);
            return new ApplicationDiagnosticResult("配置目录", false, UserFacingError.Describe(ex, "无法写入配置目录，请检查文件夹权限后重试。"));
        }
    }

    public static ApplicationDiagnosticResult CheckGameLog(string? path)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            return new ApplicationDiagnosticResult("游戏日志", false, "尚未选择 Game.log");
        }

        try
        {
            if (!File.Exists(path))
            {
                return new ApplicationDiagnosticResult("游戏日志", false, "文件不存在");
            }

            using var stream = new FileStream(
                path,
                FileMode.Open,
                FileAccess.Read,
                FileShare.ReadWrite | FileShare.Delete);
            _ = stream.Length;
            return new ApplicationDiagnosticResult("游戏日志", true, "文件存在且可读取");
        }
        catch (Exception ex)
        {
            return new ApplicationDiagnosticResult("游戏日志", false, UserFacingError.Describe(ex, "无法读取游戏日志，请重新选择 Game.log。"));
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
            // Diagnostic cleanup is best effort.
        }
    }
}
