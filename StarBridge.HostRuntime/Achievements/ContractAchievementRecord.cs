using System.Globalization;
using StarBridge.Core.Achievements;

namespace StarBridge.HostRuntime.Achievements;

public sealed record ContractRecordLines(string ZhCN, string ZhTW, string En)
{
    public string For(string locale) => locale.StartsWith("en", StringComparison.OrdinalIgnoreCase) ? En :
        locale.StartsWith("zh-TW", StringComparison.OrdinalIgnoreCase) ? ZhTW : ZhCN;
}

// Local presentation facts only; never serialized into a remote observation.
public sealed record ContractAchievementRecord(string? DisplayName, DateTimeOffset AcceptedAt,
    DateTimeOffset? ArrivedAt, DateTimeOffset CompletedAt, int StageObjectives, bool Owner, int Deaths)
{
    internal static string? CleanName(string? name) => name is { Length: > 0 and <= 160 } &&
        !string.IsNullOrWhiteSpace(name) && !name.Any(char.IsControl) ? name.Trim() : null;

    internal void Validate()
    {
        if (DisplayName is not null && CleanName(DisplayName) != DisplayName ||
            AcceptedAt <= DateTimeOffset.UnixEpoch || AcceptedAt.Offset != TimeSpan.Zero ||
            CompletedAt.Offset != TimeSpan.Zero || CompletedAt < AcceptedAt ||
            ArrivedAt is { } at && (at.Offset != TimeSpan.Zero || at < AcceptedAt || at > CompletedAt) ||
            StageObjectives is < 0 or > 256 || Deaths is < 0 or > 10000)
            throw new InvalidDataException("Invalid local contract record.");
    }

    public ContractRecordLines? Lines(string id)
    {
        Validate();
        if (!ContractAchievementPolicy.IsAward(id)) return null;
        string Duration(TimeSpan duration, string locale)
        {
            var total = (long)duration.TotalMinutes;
            var hours = total / 60; var minutes = total % 60;
            return locale == "en" ? hours > 0 ? $"{hours} h {minutes} min" : $"{minutes} min" :
                hours > 0 ? $"{hours} 小{(locale == "tw" ? "時" : "时")} {minutes} 分" : $"{minutes} 分";
        }
        string Line(string locale)
        {
            var en = locale == "en"; var tw = locale == "tw";
            var full = Duration(CompletedAt - AcceptedAt, locale);
            var date = CompletedAt.ToLocalTime();
            var day = en ? date.ToString("MMM d", CultureInfo.GetCultureInfo("en-US")) : $"{date.Month}月{date.Day}日";
            var first = DisplayName is null ? day : DisplayName + " · " + day;
            return id switch {
                "contract-first" => DisplayName is null ? day : (en ? "First contract: " : tw ? "第一單：" : "第一单：") + first,
                "contract-tsg-lead" => en ? $"Completed Tactical Strike Group as mission owner: {full}" : tw ? $"作為任務主完成戰術打擊群：{full}" : $"作为任务主完成战术打击群：{full}",
                "contract-tsg-complete" => en ? $"Completed a full Tactical Strike Group contract: {full}" : tw ? $"完整完成一次戰術打擊群：{full}" : $"完整完成一次战术打击群：{full}",
                "contract-tsg-swift" when ArrivedAt is { } arrived => en ? $"Best: completed Tactical Strike Group within {Duration(CompletedAt - arrived, locale)} of arrival" : tw ? $"最佳：在抵達後 {Duration(CompletedAt - arrived, locale)} 內完成戰術打擊群" : $"最佳：在到达后 {Duration(CompletedAt - arrived, locale)} 内完成战术打击群",
                "contract-tsg-deathless" => en ? $"Completed Tactical Strike Group without dying: {full}" : tw ? $"無死亡完成戰術打擊群：{full}" : $"无死亡完成战术打击群：{full}",
                _ => "" };
        }
        if (id == "contract-tsg-swift" && ArrivedAt is null || id == "contract-tsg-lead" && !Owner ||
            id == "contract-tsg-deathless" && Deaths != 0) return null;
        return new(Line("cn"), Line("tw"), Line("en"));
    }
}
