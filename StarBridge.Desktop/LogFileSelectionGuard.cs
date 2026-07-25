using System.IO;

namespace StarBridge.Desktop;

public sealed record GameLogSelectionValidation(
    bool IsValid,
    string Status,
    string Title,
    string Detail)
{
    public static GameLogSelectionValidation Valid { get; } = new(
        true,
        "Game.log 可用",
        "",
        "");
}

public static class LogFileSelectionGuard
{
    public const string RequiredFileName = "Game.log";

    public static GameLogSelectionValidation ValidateGameLogPath(string? path)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            return Invalid(
                "未选择游戏日志",
                "未选择 Game.log",
                "请选择 StarCitizen\\LIVE\\Game.log。");
        }

        string fullPath;
        try
        {
            fullPath = Path.GetFullPath(path);
        }
        catch (Exception ex) when (ex is ArgumentException or NotSupportedException or PathTooLongException)
        {
            return Invalid(
                "日志路径无效",
                "无法读取日志路径",
                "请选择有效的 StarCitizen\\LIVE\\Game.log。");
        }

        if (!string.Equals(Path.GetFileName(fullPath), RequiredFileName, StringComparison.OrdinalIgnoreCase))
        {
            return Invalid(
                "已拒绝非 Game.log 文件",
                "只能选择 Game.log",
                "为避免误选大文件导致应用卡死，星海舰桥只接受文件名为 Game.log 的游戏日志。");
        }

        if (!File.Exists(fullPath))
        {
            return Invalid(
                "Game.log 不存在",
                "未找到 Game.log",
                "请确认路径指向 StarCitizen\\LIVE\\Game.log。");
        }

        try
        {
            using var stream = new FileStream(
                fullPath,
                FileMode.Open,
                FileAccess.Read,
                FileShare.ReadWrite | FileShare.Delete);
        }
        catch (UnauthorizedAccessException)
        {
            return Invalid(
                "Game.log 无法读取",
                "没有读取权限",
                "当前账号没有权限读取这个 Game.log，请检查文件权限或重新选择日志。");
        }
        catch (IOException ex)
        {
            return Invalid(
                "Game.log 暂不可读",
                "无法读取 Game.log",
                UserFacingError.Describe(ex, "文件暂时无法读取，请确认文件未被其他程序占用。"));
        }

        return GameLogSelectionValidation.Valid;
    }

    private static GameLogSelectionValidation Invalid(string status, string title, string detail)
    {
        return new GameLogSelectionValidation(false, status, title, detail);
    }
}
