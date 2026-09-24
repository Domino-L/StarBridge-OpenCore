using StarBridge.Core.Fleets;

namespace StarBridge.Core.Tests;

internal static class CommunityProfileEditingRulesTests
{
    internal static void RunAll()
    {
        Check(CommunityProfileEditingRules.TextFits("name", "星海 Équipe 探索"), "Unicode organization names allowed");
        Check(!CommunityProfileEditingRules.TextFits("name", " ") && !CommunityProfileEditingRules.TextFits("name", new string('船', 33)) && !CommunityProfileEditingRules.TextFits("name", "A\nB"), "invalid organization names rejected");
        Check(CommunityProfileEditingRules.TextFits("logoText", new string('中', 8)), "8 CJK logo");
        Check(!CommunityProfileEditingRules.TextFits("logoText", new string('中', 8) + "a"), "mixed logo overflow");
        Check(CommunityProfileEditingRules.TextFits("description", new string('a', 400)), "400 ASCII description");
        Check(!CommunityProfileEditingRules.TextFits("description", new string('中', 201)), "201 CJK description");
        Check(!CommunityProfileEditingRules.TextFits("websiteUrl", new string('a', 257)), "website limit");
        Check(CommunityProfileEditingRules.TagsFit("战斗 / 工业 / 探索 / PVE / PVP / FPS / 狗斗 / 空战 / 休闲 / 教学"), "all ten valid slots");
        Check(!CommunityProfileEditingRules.TagsFit("战斗 / 工业 / 探索 / 商业"), "core max 3");
        Check(!CommunityProfileEditingRules.TagsFit("PVE / 休闲"), "core required");
        Check(CommunityProfileEditingRules.TagsFit("战斗 / PVE / PVP / FPS / 狗斗 / 空战 / 小队行动 / 周末活动"), "scale can use reserved style slots");
        Check(!CommunityProfileEditingRules.TagsFit("战斗 / PVE / PVP / FPS / 狗斗 / 空战 / 休闲 / 小队行动 / 周末活动"), "third mixed style scale consumes shared slot");
        Check(!CommunityProfileEditingRules.TagsFit("战斗 / PVE / PVP / FPS / 狗斗 / 空战 / 护航"), "shared cannot borrow reserved style");
        Check(CommunityProfileEditingRules.TagsFit("战斗 / PVE / 休闲 / 教学 / 新手友好"), "extra style shares pool");
        Check(!CommunityProfileEditingRules.RecruitmentFits(true, false, "Open"), "recruitment must list");
        Check(CommunityProfileEditingRules.ActivityWindowFits("19:00", "02:00", true), "overnight window");
        Check(CommunityProfileEditingRules.ActivityWindowFits("19:00", "19:00", true), "24 hour window");
        Check(!CommunityProfileEditingRules.ActivityWindowFits("19:00", "22:00", true), "over 24 hours rejected");
        Check(!CommunityProfileEditingRules.ActivityWindowFits("19:00", "02:00", false), "earlier end must cross midnight");
        Check(!CommunityProfileEditingRules.RecruitmentFits(true, true, "Invite"), "recruitment excludes invite only");
    }
    private static void Check(bool ok, string message) { if (!ok) throw new InvalidOperationException(message); }
}
