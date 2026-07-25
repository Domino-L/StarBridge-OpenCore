namespace StarBridge.Desktop;

using System.IO;

internal sealed record IdentityInitializationStatus(
    bool HasLog,
    bool HasPlayerName,
    bool HasPlayerId,
    bool IsComplete,
    string StatusText,
    string DetailText);

internal static class IdentityInitialization
{
    public static IdentityInitializationStatus GetStatus(string? logPath, string? playerName, string? playerId)
    {
        var hasLog = !string.IsNullOrWhiteSpace(logPath) && File.Exists(logPath);
        var hasPlayerName = !string.IsNullOrWhiteSpace(playerName);
        var hasPlayerId = !string.IsNullOrWhiteSpace(playerId);
        var isComplete = hasLog && hasPlayerName && hasPlayerId;

        if (isComplete)
        {
            return new IdentityInitializationStatus(
                true,
                true,
                true,
                true,
                $"已完成：{playerName} / {playerId}",
                "已选择 Game.log，并已读取游戏名与玩家 ID。");
        }

        if (!hasLog)
        {
            return new IdentityInitializationStatus(
                false,
                hasPlayerName,
                hasPlayerId,
                false,
                "未选择 Game.log",
                "请使用快速扫描，或手动选择 StarCitizen\\LIVE\\Game.log。");
        }

        if (!hasPlayerName)
        {
            return new IdentityInitializationStatus(
                true,
                false,
                hasPlayerId,
                false,
                $"已选择：{Path.GetFileName(logPath)}，等待读取游戏名",
                "请进入星际公民，应用会从 Game.log 中读取你的游戏身份。");
        }

        return new IdentityInitializationStatus(
            true,
            true,
            false,
            false,
            $"已读取游戏名：{playerName}，等待玩家 ID",
            "请进入 PU，直到 Game.log 出现玩家 ID 信息。完成后才可加入或创建舰队。");
    }

    public static string? FindDefaultGameLog()
    {
        var candidates = new List<string>();
        AddCandidate(candidates, Path.Combine(GetSystemDriveRoot(), "StarCitizen", "LIVE", "Game.log"));

        foreach (var drive in DriveInfo.GetDrives())
        {
            try
            {
                if (drive.DriveType != DriveType.Fixed || !drive.IsReady)
                {
                    continue;
                }

                AddCandidate(candidates, Path.Combine(drive.RootDirectory.FullName, "StarCitizen", "LIVE", "Game.log"));
            }
            catch
            {
                // Some drives can disappear or deny metadata access while scanning.
            }
        }

        return candidates
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .Where(File.Exists)
            .Select(path => new { Path = path, LastWrite = SafeGetLastWriteTimeUtc(path) })
            .OrderByDescending(item => item.LastWrite)
            .FirstOrDefault()
            ?.Path;
    }

    private static void AddCandidate(List<string> candidates, string path)
    {
        if (candidates.Any(existing => string.Equals(existing, path, StringComparison.OrdinalIgnoreCase)))
        {
            return;
        }

        candidates.Add(path);
    }

    private static string GetSystemDriveRoot()
    {
        var systemPath = Environment.GetFolderPath(Environment.SpecialFolder.System);
        return Path.GetPathRoot(systemPath) ?? @"C:\";
    }

    private static DateTime SafeGetLastWriteTimeUtc(string path)
    {
        try
        {
            return File.GetLastWriteTimeUtc(path);
        }
        catch
        {
            return DateTime.MinValue;
        }
    }
}
