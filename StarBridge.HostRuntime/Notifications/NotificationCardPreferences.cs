namespace StarBridge.HostRuntime.Notifications;

using System.Text.Json;
using System.Text.Json.Serialization;

/// <summary>
/// Card preferences added in 0.7.3, kept in their own file: notification-settings.v1.json is read
/// with an exact field list, so a field added there would make an older (rolled-back) version fail
/// to read it. Unknown fields here are ignored, so later versions may add more.
/// </summary>
internal sealed record NotificationCardPreferences(
    int SchemaVersion = 1,
    // Show social cards while Windows is in do-not-disturb or quiet time (user decision: default on).
    bool ShowDuringQuiet = true,
    // When ShowDuringQuiet is off: one summary card after the quiet period ends.
    bool QuietSummary = true,
    // The one-time 0.7.3 switch-on of the Windows card master switch has been applied.
    [property: JsonPropertyName("windowsMigrated073")] bool WindowsMigrated073 = false);

internal sealed class NotificationCardPreferencesStore(string dataRoot)
{
    private const int MaximumBytes = 4096;
    private readonly string _path = Path.Combine(Path.GetFullPath(dataRoot), "notification-cards.v1.json");

    internal string FilePath => _path;

    /// <summary>Missing, oversized, linked or unreadable files read as the defaults; the file is not rewritten here.</summary>
    internal NotificationCardPreferences Load()
    {
        try
        {
            if (!File.Exists(_path)) return new();
            var info = new FileInfo(_path);
            if (info.Length > MaximumBytes || info.Attributes.HasFlag(FileAttributes.ReparsePoint)) return new();
            var value = JsonSerializer.Deserialize<NotificationCardPreferences>(File.ReadAllBytes(_path), Options);
            return value is { SchemaVersion: 1 } ? value : new();
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or JsonException)
        {
            return new();
        }
    }

    internal void Save(NotificationCardPreferences value)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
        var temp = _path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            using (var file = new FileStream(temp, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough))
            {
                JsonSerializer.Serialize(file, value, Options);
                file.Flush(true);
            }
            File.Move(temp, _path, true);
        }
        finally
        {
            if (File.Exists(temp)) File.Delete(temp);
        }
    }

    private static readonly JsonSerializerOptions Options = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = false,
    };
}

/// <summary>
/// Which environment rule a social card follows. With "show during quiet" on, the trade-card rule
/// applies (Windows do-not-disturb and quiet time do not block; a locked, presentation, inactive or
/// unknown desktop still does). Off keeps the existing rule.
/// </summary>
internal static class SocialCardEnvironment
{
    internal static string SuppressionReason(bool showDuringQuiet, Func<string> existingRule, Func<string> quietIgnoringRule)
    {
        try { return showDuringQuiet ? quietIgnoringRule() : existingRule(); }
        catch { return "unavailable"; }
    }

    /// <summary>Reasons that mean "Windows asked for quiet", which the summary counts and later reports.</summary>
    internal static bool IsQuietReason(string reason) =>
        reason is "do-not-disturb" or "shell-suppressed-6"; // Focus assist / do-not-disturb, Windows quiet time
}

/// <summary>Counts cards held back by quiet time and produces one summary card when it ends.</summary>
internal sealed class QuietCardSummary
{
    private readonly Dictionary<string, int> _counts = new(StringComparer.Ordinal);

    internal void Held(string kind) => _counts[kind] = _counts.GetValueOrDefault(kind) + 1;

    internal int Total => _counts.Values.Sum();

    /// <summary>The summary text once quiet time is over, then empty; null when nothing was held.</summary>
    internal string? Take(bool zh)
    {
        if (_counts.Count == 0) return null;
        string Label(string kind) => kind switch
        {
            "directMessage" => zh ? "私信" : "direct messages",
            "online" => zh ? "上线" : "came online",
            "offline" => zh ? "下线" : "went offline",
            "friendRequest" => zh ? "好友申请" : "friend requests",
            "announcement" => zh ? "公告" : "announcements",
            "roomInvite" => zh ? "房间邀请" : "room invites",
            "chat" => zh ? "组织聊天" : "organization chat",
            "management" => zh ? "管理待办" : "management tasks",
            _ => zh ? "提醒" : "reminders",
        };
        var parts = _counts.OrderByDescending(pair => pair.Value).ThenBy(pair => pair.Key, StringComparer.Ordinal)
            .Select(pair => zh ? $"{pair.Value} 条{Label(pair.Key)}" : $"{pair.Value} {Label(pair.Key)}").ToArray();
        _counts.Clear();
        return (zh ? "刚才有 " : "While quiet: ") + string.Join(zh ? "、" : ", ", parts);
    }

    internal void Reset() => _counts.Clear();
}
