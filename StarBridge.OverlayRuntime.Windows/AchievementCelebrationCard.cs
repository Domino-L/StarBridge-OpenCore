namespace StarBridge.OverlayRuntime.Windows;

using System.Globalization;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;

internal sealed partial class AchievementCelebrationCard : FrameworkElement
{
    internal const double CardWidth = 364, CardHeight = 108, Bleed = 24;
    internal const double HoldMilliseconds = 4500, ExitMilliseconds = 300;
    private readonly bool _light, _reduced;
    private readonly string _locale, _name, _memory;
    private readonly int _summaryCount;
    private readonly ImageSource? _earned, _locked;
    private readonly Palette _palette;
    internal AchievementCelebrationCard(string? locale, bool light, bool reduced, string id = "first-entry", int rank = 0,
        string? displayName = null, string? localImagePath = null, StarBridge.HostRuntime.Achievements.ContractRecordLines? record = null,
        int summaryCount = 0, string? rarityTier = null, int? rarityBasisPoints = null)
    {
        _locale = locale ?? CultureInfo.CurrentUICulture.Name;
        _light = light;
        _reduced = reduced;
        _summaryCount = id == "scm-summary" ? Math.Clamp(summaryCount, 0, 4096) : 0;
        Width = CardWidth + Bleed;
        Height = CardHeight + Bleed;
        ClipToBounds = true;
        RenderOptions.SetBitmapScalingMode(this, BitmapScalingMode.HighQuality);
        var english = English;
        var traditional = Traditional;
        (RarityLevel, RarityLine) = _summaryCount > 0 ? (0, "") : DescribeRarity(
            id.StartsWith("scm-", StringComparison.Ordinal), rarityTier, rarityBasisPoints);
        _palette = Palette.Create(light, RarityLevel);
        var (prefix, name, memory) = id switch {
            "contract-first" => (id,english ? "Open for Business" : traditional ? "開張大吉" : "开张大吉", ""),
            "contract-tsg-lead" => (id, english ? "TSG · Leader" : traditional ? "打擊群·領隊" : "打击群·领队", ""),
            "contract-tsg-complete" => (id, english ? "TSG · Triumph" : traditional ? "打擊群·凱旋" : "打击群·凯旋", ""),
            "contract-tsg-swift" => (id, english ? "TSG · Blitz" : traditional ? "打擊群·閃擊" : "打击群·闪击", ""),
            "contract-tsg-deathless" => (id, english ? "TSG · Undying" : traditional ? "打擊群·不滅" : "打击群·不灭", ""),
            "journey-lorville" => (id, english ? "Lorville Dusk" : traditional ? "羅威爾黃昏" : "罗威尔黄昏", english ? "Dusk lingers; the towers stand like mountains" : traditional ? "夕照未盡，塔影如山" : "夕照未尽，塔影如山"),
            "journey-area18" => (id, english ? "Neon Area18" : traditional ? "霓虹十八區" : "霓虹十八区", english ? "The city that never dims" : traditional ? "燈火通明，不眠不休" : "灯火通明，不眠不休"),
            "journey-orison" => (id, english ? "Orison Above the Clouds" : traditional ? "雲上奧里森" : "云上奥里森", english ? "A city afloat on a sea of cloud" : traditional ? "雲海之上，自有人間" : "云海之上，自有人间"),
            "journey-new-babbage" => (id, english ? "Snowfall over New Babbage" : traditional ? "雪落新巴貝奇" : "雪落新巴贝奇", english ? "Snow falls quietly; the lights come on to meet you" : traditional ? "雪落無聲，燈火相迎" : "雪落无声，灯火相迎"),
            "journey-stanton" => (id, english ? "Stanton Pilgrimage" : traditional ? "巡禮斯坦頓" : "巡礼斯坦顿", english ? "Four cities reached; the stars are home" : traditional ? "四城皆至，星海為家" : "四城皆至，星海为家"),
            "journey-levski" => (id, english ? "Levski in the Rock" : traditional ? "岩中列夫斯基" : "岩中列夫斯基", english ? "Deep in the rock, the lights still burn" : traditional ? "岩壁深處，自有燈火" : "岩壁深处，自有灯火"),
            "journey-pyro-majors" => (id, english ? "First Steps in Pyro" : traditional ? "初探派羅" : "初探派罗", english ? "A lawless star, first seen up close" : traditional ? "無主之地，初見火光" : "无主之地，初见火光"),
            "journey-pyro-all" => (id, english ? "Walker of the Fire Sea" : traditional ? "火海行者" : "火海行者", english ? "Across the sea of fire, every harbour known" : traditional ? "火海茫茫，處處留航" : "火海茫茫，处处留航"),
            "journey-grimhex" => (id, english ? "Lawless Grim HEX" : traditional ? "法外六角灣" : "法外六角湾", english ? "A hidden reef in the ring, a harbour of its own" : traditional ? "環中暗礁，自成一港" : "环中暗礁，自成一港"),
            "hangar-home" => ("home", english ? "Fleet Builder" : traditional ? "艦隊成軍" : "舰队成军", english ? "And all I ask is a tall ship\nand a star to steer her by;" : traditional ? "滿船清夢壓星河" : "满船清梦压星河"),
            "hangar-collection" => ("collection", english ? "Model Collector" : traditional ? "型號收藏家" : "型号收藏家", english ? "I am a part of all\nthat I have met;" : traditional ? "星河欲轉千帆舞" : "星河欲转千帆舞"),
            "hangar-paths" => ("paths", english ? "Every Role Covered" : traditional ? "全能機庫" : "全能机库", english ? "I dwell in Possibility -" : traditional ? "大海從魚躍，長空任鳥飛" : "大海从鱼跃，长空任鸟飞"),
            _ => ("first-entry", english ? "First Light" : "初入星海", english ? "Look’d up in perfect silence\nat the stars" : traditional ? "星漢燦爛，若出其裏" : "星汉灿烂，若出其里")
        };
        _name = name + (rank > 0 ? " · " + StarBridge.Core.Achievements.HangarAchievementPolicy.Roman(rank) : ""); _memory = memory;
        if (StarBridge.Core.Achievements.ContractAchievementPolicy.IsAward(id)) _memory = record?.For(_locale) ?? "";
        // Every bundled artwork ships an earned/locked pair; a missing locked
        // image falls back to the shared first-entry locked art.
        var rankedArt = id is "hangar-home" or "hangar-collection" or "hangar-paths";
        var artRank = rank is >= 1 and <= 5 ? rank : 1;
        _earned = Load(rankedArt ? $"{prefix}-{artRank}.png" : prefix + "-earned.png");
        _locked = Load(prefix + "-locked.png") ?? Load("first-entry-locked.png");
        if (id.StartsWith("scm-", StringComparison.Ordinal) && displayName is not null)
        {
            _name = displayName; _memory = "";
            _earned = LoadLocal(localImagePath);
            _locked = LoadLocal(localImagePath?.Replace("-512.webp", "-locked-512.webp", StringComparison.Ordinal));
        }
        if (_summaryCount > 0)
        {
            _name = SummaryName(_summaryCount);
            _memory = english ? "See them in the achievement centre" : "到成就中心查看";
            _earned = null; _locked = null;
        }
        System.Windows.Automation.AutomationProperties.SetName(this,
            (english ? "Achievement unlocked: " : "成就已解锁：") + _name);
    }
    private bool English => _locale.StartsWith("en", StringComparison.OrdinalIgnoreCase);
    private bool Traditional => _locale.StartsWith("zh-TW", StringComparison.OrdinalIgnoreCase);
    internal double EntryMilliseconds => _reduced ? 0 : RarityLevel switch { 2 => 1100, 1 => 820, _ => 760 };
    internal double LifetimeMilliseconds => EntryMilliseconds + HoldMilliseconds + (_reduced ? 0 : ExitMilliseconds);
    internal bool HasArtwork => _earned is not null && _locked is not null;
    internal string Memory => _memory;
    internal int RarityLevel { get; }
    internal string RarityLine { get; }
    private string SummaryName(int count) => English ? $"{count} more SCM achievement{(count == 1 ? "" : "s")} unlocked" :
        Traditional ? $"另有 {count} 個 SCM 成就已解鎖" : $"另有 {count} 个 SCM 成就已解锁";

    internal int SummaryCountAt(double elapsed)
    {
        if (_summaryCount == 0 || _reduced || elapsed >= 760) return _summaryCount;
        // At most 21 distinct numbers need text drawings, even for a large backlog.
        var step = Math.Clamp(Math.Floor((elapsed - 420) / 17), 0, 20) / 20;
        return 1 + (int)Math.Floor((_summaryCount - 1) * step);
    }

    private (int Level, string Line) DescribeRarity(bool scm, string? tier, int? basisPoints)
    {
        if (scm) return tier switch
        {
            "RARE" => (1, English ? "Rare" : "稀有"),
            "EPIC" => (2, English ? "Epic" : Traditional ? "史詩" : "史诗"),
            "LEGENDARY" => (2, English ? "Legendary" : Traditional ? "傳說" : "传说"),
            _ => (0, "")
        };

        var (level, label) = tier switch
        {
            "rare" => (1, English ? "Rare" : "稀有"),
            "veryRare" => (2, English ? "Ultra rare" : Traditional ? "極稀有" : "极稀有"),
            _ => (0, "")
        };
        if (basisPoints is not (>= 0 and <= 10000)) return (level, label);
        var percent = (basisPoints.Value / 100d).ToString("0.0", CultureInfo.InvariantCulture);
        var ratio = English
            ? basisPoints < 10 ? "Earned by fewer than 0.1% of players" : $"Earned by {percent}% of players"
            : (basisPoints < 10 ? (Traditional ? "少於 0.1%" : "少于 0.1%") : $"{percent}%") +
                (Traditional ? " 的玩家獲得" : " 的玩家获得");
        return (level, label.Length == 0 ? ratio : label + " · " + ratio);
    }
    private static ImageSource? Load(string file, string folder = "Achievements")
    {
        try
        {
            var image = new BitmapImage(new Uri($"pack://application:,,,/StarBridge.OverlayRuntime.Windows;component/Assets/{folder}/{file}"));
            image.Freeze(); return image;
        }
        catch { return null; } // An optional image never suppresses the achievement text.
    }
    private static ImageSource? LoadLocal(string? relative)
    {
        // Only bundled artwork, never ImageUrl, a URI, an arbitrary file or a WIC network codec.
        // SCM holiday, daily and limited-event art (daily/event added for 0.7.3 build 105).
        if (relative is null || !(relative.StartsWith("Assets/Achievements/scm-holiday-", StringComparison.Ordinal) ||
            relative.StartsWith("Assets/Achievements/scm-daily-", StringComparison.Ordinal) ||
            relative.StartsWith("Assets/Achievements/scm-event-", StringComparison.Ordinal)) ||
            !relative.EndsWith("-512.webp", StringComparison.Ordinal) || relative.Contains("..") || relative.Contains('\\') ||
            relative["Assets/Achievements/".Length..].Contains('/')) return null;
        try
        {
            using var bitmap = SkiaSharp.SKBitmap.Decode(System.IO.Path.Combine(AppContext.BaseDirectory, relative));
            if (bitmap is null) return null;
            using var converted = bitmap.Copy(SkiaSharp.SKColorType.Bgra8888);
            var image = BitmapSource.Create(converted.Width, converted.Height, 96, 96, PixelFormats.Pbgra32, null,
                converted.GetPixels(), converted.ByteCount, converted.RowBytes);
            image.Freeze(); return image;
        }
        catch { return null; }
    }
}
