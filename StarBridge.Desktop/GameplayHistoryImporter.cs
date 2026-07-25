using System.Globalization;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;

namespace StarBridge.Desktop;

internal sealed record GameplayHistoryImportResult(
    long PlayTimeSeconds,
    int SessionCount,
    int IncompleteSessionCount,
    int SkippedFileCount,
    DateTimeOffset? FirstSessionAt,
    DateTimeOffset? LastSessionAt,
    string? Error = null)
{
    public bool HasData => PlayTimeSeconds > 0 && SessionCount > 0 && Error is null;

    public static GameplayHistoryImportResult Empty(string error, int skippedFileCount = 0) =>
        new(0, 0, 0, skippedFileCount, null, null, error);
}

internal static partial class GameplayHistoryImporter
{
    private static readonly TimeSpan MaximumSessionLength = TimeSpan.FromHours(24);

    [GeneratedRegex(@"^<(?<timestamp>[^>]+)>", RegexOptions.CultureInvariant)]
    private static partial Regex TimestampPattern();

    [GeneratedRegex("nickname=\"(?<player>[^\"]+)\"", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex NicknamePattern();

    public static GameplayHistoryImportResult Scan(
        string? gameLogPath,
        string? expectedGameName,
        DateTimeOffset? recordedBefore)
    {
        if (string.IsNullOrWhiteSpace(gameLogPath))
        {
            return GameplayHistoryImportResult.Empty("尚未选择 Game.log。");
        }

        if (string.IsNullOrWhiteSpace(expectedGameName))
        {
            return GameplayHistoryImportResult.Empty("尚未识别当前游戏 ID，无法验证历史日志归属。");
        }

        var liveDirectory = Path.GetDirectoryName(gameLogPath);
        if (string.IsNullOrWhiteSpace(liveDirectory))
        {
            return GameplayHistoryImportResult.Empty("无法确定 Star Citizen LIVE 目录。");
        }

        var backupDirectory = Path.Combine(liveDirectory, "logbackups");
        if (!Directory.Exists(backupDirectory))
        {
            return GameplayHistoryImportResult.Empty("未找到 logbackups 历史日志目录。");
        }

        var intervals = new List<HistoricalInterval>();
        var skippedFileCount = 0;
        string[] files;
        try
        {
            files = Directory.GetFiles(backupDirectory, "*.log", SearchOption.TopDirectoryOnly);
        }
        catch (Exception ex)
        {
            return GameplayHistoryImportResult.Empty(UserFacingError.Describe(ex, "无法读取历史日志目录，请检查文件夹权限后重试。"));
        }

        foreach (var file in files)
        {
            var interval = ReadInterval(file, expectedGameName.Trim(), recordedBefore);
            if (interval is null)
            {
                skippedFileCount++;
                continue;
            }

            intervals.Add(interval);
        }

        var uniqueIntervals = intervals
            .DistinctBy(interval => (interval.Start, interval.End))
            .OrderBy(interval => interval.Start)
            .ToArray();
        if (uniqueIntervals.Length == 0)
        {
            return GameplayHistoryImportResult.Empty(
                files.Length == 0
                    ? "logbackups 中暂时没有可导入的日志。"
                    : "没有找到属于当前游戏 ID 的有效历史时长。",
                skippedFileCount);
        }

        var merged = MergeIntervals(uniqueIntervals);
        var seconds = merged.Sum(interval =>
            Math.Max(0, (long)Math.Round(
                (interval.End - interval.Start).TotalSeconds,
                MidpointRounding.AwayFromZero)));
        if (seconds <= 0)
        {
            return GameplayHistoryImportResult.Empty("历史日志中没有可验证的有效时长。", skippedFileCount);
        }

        return new GameplayHistoryImportResult(
            seconds,
            uniqueIntervals.Length,
            uniqueIntervals.Count(interval => !interval.CleanExit),
            skippedFileCount,
            merged[0].Start,
            merged[^1].End);
    }

    private static HistoricalInterval? ReadInterval(
        string path,
        string expectedGameName,
        DateTimeOffset? recordedBefore)
    {
        DateTimeOffset? first = null;
        DateTimeOffset? last = null;
        var identityMatched = false;
        var cleanExit = false;

        try
        {
            using var stream = new FileStream(
                path,
                FileMode.Open,
                FileAccess.Read,
                FileShare.ReadWrite | FileShare.Delete);
            using var reader = new StreamReader(
                stream,
                Encoding.UTF8,
                detectEncodingFromByteOrderMarks: true);
            while (reader.ReadLine() is { } line)
            {
                var timestamp = ParseTimestamp(line);
                if (timestamp.HasValue)
                {
                    first ??= timestamp;
                    last = timestamp;
                }

                if (!identityMatched)
                {
                    var identity = NicknamePattern().Match(line);
                    identityMatched = identity.Success &&
                                      identity.Groups["player"].Value.Equals(
                                          expectedGameName,
                                          StringComparison.OrdinalIgnoreCase);
                }

                if (line.Contains("<SystemQuit>", StringComparison.OrdinalIgnoreCase) &&
                    line.Contains("CSystem::Quit", StringComparison.OrdinalIgnoreCase))
                {
                    cleanExit = true;
                }
            }
        }
        catch
        {
            return null;
        }

        if (!identityMatched || !first.HasValue || !last.HasValue)
        {
            return null;
        }

        var start = first.Value;
        var end = recordedBefore.HasValue && last.Value > recordedBefore.Value
            ? recordedBefore.Value
            : last.Value;
        var duration = end - start;
        if (duration <= TimeSpan.Zero || duration > MaximumSessionLength)
        {
            return null;
        }

        return new HistoricalInterval(start, end, cleanExit);
    }

    private static DateTimeOffset? ParseTimestamp(string line)
    {
        var match = TimestampPattern().Match(line);
        return match.Success && DateTimeOffset.TryParse(
            match.Groups["timestamp"].Value,
            CultureInfo.InvariantCulture,
            DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal,
            out var timestamp)
            ? timestamp
            : null;
    }

    private static HistoricalInterval[] MergeIntervals(HistoricalInterval[] intervals)
    {
        var merged = new List<HistoricalInterval>();
        foreach (var interval in intervals)
        {
            if (merged.Count == 0 || interval.Start > merged[^1].End)
            {
                merged.Add(interval);
                continue;
            }

            var previous = merged[^1];
            merged[^1] = previous with
            {
                End = interval.End > previous.End ? interval.End : previous.End,
                CleanExit = previous.CleanExit && interval.CleanExit
            };
        }

        return [.. merged];
    }

    private sealed record HistoricalInterval(
        DateTimeOffset Start,
        DateTimeOffset End,
        bool CleanExit);
}
