namespace StarBridge.Desktop;

internal sealed record LocalPlayReminderCopy(int Index, string Title, string Detail);

internal static class LocalPlayReminderCopyCatalog
{
    private sealed record CopyTemplate(
        int Index,
        string ChineseTitle,
        string ChineseDetail,
        string EnglishTitle,
        string EnglishDetail);

    private static readonly CopyTemplate[] DefaultCopies =
    [
        new(0, "喝口水吧", "渴死了可没复活床。", "Have some water", "There is no respawn bed for dehydration."),
        new(1, "稍微歇一下", "坐了这么久，起来走两步、伸个懒腰再回来吧。", "Take a short break", "Stand up, stretch, and come back when you are ready."),
        new(2, "眼睛也该休息了", "看一会儿远处，让眼睛缓一缓。", "Give your eyes a rest", "Look into the distance and let your eyes relax for a moment."),
        new(3, "动一动吧", "肩膀是不是有点紧了？放松一下肩颈和手腕吧。", "Time to move", "Are your shoulders feeling tight? Relax your neck, shoulders, and wrists."),
        new(4, "这一小时辛苦了", "先喝口水，换个舒服点的姿势，再继续也不迟。", "You have earned a pause", "Have some water and find a more comfortable position before continuing."),
        new(5, "休息不会掉队", "离开座位几分钟没关系，照顾好自己更重要。", "You will not fall behind", "A few minutes away is fine. Taking care of yourself matters more."),
        new(6, "别忘了自己", "手腕和肩颈也陪你忙了很久，给它们一点休息时间吧。", "Do not forget yourself", "Your wrists and shoulders have been working too. Give them a little rest."),
        new(7, "下一段航程之前", "先补充一点水分，慢慢来，我们不赶这一分钟。", "Before the next leg", "Drink some water first. Take your time; this minute can wait."),
        new(8, "上个厕所", "队友和任务可以等，厕所不能。", "Bathroom break", "Your teammates and missions can wait. Your bladder cannot."),
        new(9, "肩膀放下来", "对，就是刚才不知不觉抬起来的那两个。", "Drop your shoulders", "Yes, the two you raised without noticing.")
    ];

    public static int Count => DefaultCopies.Length;

    public static string FormatDisplayTitle(string? copyTitle, TimeSpan continuousPlayTime, bool useChinese)
    {
        var hours = Math.Max(0, (int)Math.Floor(continuousPlayTime.TotalHours));
        var prefix = useChinese
            ? $"你已连续游玩 {hours} 小时"
            : $"You have been playing for {hours} hours";
        return string.IsNullOrWhiteSpace(copyTitle)
            ? prefix
            : useChinese
                ? $"{prefix}，{copyTitle.Trim()}"
                : $"{prefix} — {copyTitle.Trim()}";
    }

    public static LocalPlayReminderCopy Pick(bool useChinese, int previousIndex = -1, Random? random = null)
    {
        return Pick(useChinese, DateTimeOffset.Now, TimeSpan.Zero, previousIndex, random);
    }

    public static LocalPlayReminderCopy Pick(
        bool useChinese,
        DateTimeOffset localNow,
        TimeSpan continuousPlayTime,
        int previousIndex = -1,
        Random? random = null)
    {
        random ??= Random.Shared;
        var sessionCopies = BuildSessionCopies(continuousPlayTime);
        var timeCopies = BuildTimeCopies(localNow);
        IReadOnlyList<CopyTemplate> pool;
        if (sessionCopies.Count > 0 && sessionCopies.Any(copy => copy.Index != previousIndex))
        {
            pool = sessionCopies;
        }
        else if (timeCopies.Count > 0 && random.NextDouble() < 0.5)
        {
            pool = timeCopies;
        }
        else
        {
            pool = DefaultCopies;
        }

        var candidates = pool.Where(copy => copy.Index != previousIndex).ToArray();
        if (candidates.Length == 0)
        {
            candidates = DefaultCopies.Where(copy => copy.Index != previousIndex).ToArray();
        }

        var selected = candidates[random.Next(candidates.Length)];
        return useChinese
            ? new LocalPlayReminderCopy(selected.Index, selected.ChineseTitle, selected.ChineseDetail)
            : new LocalPlayReminderCopy(selected.Index, selected.EnglishTitle, selected.EnglishDetail);
    }

    private static IReadOnlyList<CopyTemplate> BuildTimeCopies(DateTimeOffset localNow)
    {
        var copies = new List<CopyTemplate>();
        var time = localNow.TimeOfDay;
        if (time >= TimeSpan.Zero && time < TimeSpan.FromHours(5))
        {
            copies.Add(new CopyTemplate(
                100,
                "凌晨电台",
                "张雪峰老师~ 我还记得你~",
                "Late-night radio",
                "Teacher Zhang Xuefeng, I still remember you~"));
            copies.Add(new CopyTemplate(
                101,
                "凌晨航行",
                $"你见过凌晨 {localNow.Hour} 点的斯坦顿吗？",
                "Flying after midnight",
                $"Have you ever seen Stanton at {localNow.Hour}:00?"));
        }

        if (time >= new TimeSpan(6, 30, 0) && time <= new TimeSpan(9, 0, 0))
        {
            copies.Add(new CopyTemplate(
                102,
                "早啊，老斯坦顿人",
                "嘿，咱这老斯坦顿人早上起来就得玩星际公民，那叫一个地道。",
                "Morning, Stanton regular",
                "Nothing says morning in Stanton like starting up Star Citizen."));
        }

        if (time >= new TimeSpan(11, 30, 0) && time <= new TimeSpan(12, 30, 0))
        {
            copies.Add(new CopyTemplate(
                103,
                "到饭点了",
                "点个外卖吃吃？",
                "Lunch time",
                "How about ordering something to eat?"));
        }

        return copies;
    }

    private static IReadOnlyList<CopyTemplate> BuildSessionCopies(TimeSpan continuousPlayTime)
    {
        return continuousPlayTime >= TimeSpan.FromHours(10)
            ?
            [
                new CopyTemplate(
                    104,
                    "你简直是超人",
                    "已经连续玩了 10 个小时以上，真该休息一下了。",
                    "You are practically superhuman",
                    "You have been playing for over 10 hours. It really is time for a break.")
            ]
            : [];
    }
}
