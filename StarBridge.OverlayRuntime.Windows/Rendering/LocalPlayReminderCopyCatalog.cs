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

    internal static LocalPlayReminderCopy ToTraditional(LocalPlayReminderCopy copy, DateTimeOffset localNow) => copy.Index switch
    {
        0 => new(0, "喝口水吧", "渴死了可沒復活床。"),
        1 => new(1, "稍微歇一下", "坐了這麼久，起來走兩步、伸個懶腰再回來吧。"),
        2 => new(2, "眼睛也該休息了", "看一會兒遠處，讓眼睛緩一緩。"),
        3 => new(3, "動一動吧", "肩膀是不是有點緊了？放鬆一下肩頸和手腕吧。"),
        4 => new(4, "這一小時辛苦了", "先喝口水，換個舒服點的姿勢，再繼續也不遲。"),
        5 => new(5, "休息不會掉隊", "離開座位幾分鐘沒關係，照顧好自己更重要。"),
        6 => new(6, "別忘了自己", "手腕和肩頸也陪你忙了很久，給它們一點休息時間吧。"),
        7 => new(7, "下一段航程之前", "先補充一點水分，慢慢來，我們不趕這一分鐘。"),
        8 => new(8, "上個廁所", "隊友和任務可以等，廁所不能。"),
        9 => new(9, "肩膀放下來", "對，就是剛才不知不覺抬起來的那兩個。"),
        100 => new(100, "凌晨電台", "張雪峰老師~ 我還記得你~"),
        101 => new(101, "凌晨航行", $"你見過凌晨 {localNow.Hour} 點的斯坦頓嗎？"),
        102 => new(102, "早啊，老斯坦頓人", "嘿，咱這老斯坦頓人早上起來就得玩星際公民，那叫一個地道。"),
        103 => new(103, "到飯點了", "點個外賣吃吃？"),
        104 => new(104, "你簡直是超人", "已經連續玩了 10 個小時以上，真該休息一下了。"),
        _ => copy
    };

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
