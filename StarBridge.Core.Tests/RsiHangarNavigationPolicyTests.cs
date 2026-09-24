using StarBridge.Core.Hangar;

namespace StarBridge.Core.Tests;

internal static class RsiHangarNavigationPolicyTests
{
    public static void RunAll()
    {
        var first = new Uri("https://robertsspaceindustries.com/en/account/pledges");
        var second = new Uri("https://robertsspaceindustries.com/account/pledges?page=2&product-type=");
        Require(RsiHangarNavigationPolicy.Allows(HangarNavigationAction.Start, null, first), "Explicit start to first page");
        Require(RsiHangarNavigationPolicy.Allows(HangarNavigationAction.NextPage, first, second), "Allow next unfiltered page");
        Require(RsiHangarNavigationPolicy.Allows(HangarNavigationAction.RecheckFirstPage, second, first), "Allow bookend recheck");
        Require(!RsiHangarNavigationPolicy.Allows(HangarNavigationAction.Start, first, first), "Start is not arbitrary navigation");
        Require(!RsiHangarNavigationPolicy.Allows(HangarNavigationAction.NextPage, second, first), "No unexpected reverse navigation");
        Require(!RsiHangarNavigationPolicy.Allows((HangarNavigationAction)99, first, second), "Unknown action rejected");
        foreach (var value in new[] {
            "http://robertsspaceindustries.com/account/pledges?page=2",
            "https://robertsspaceindustries.com.example.invalid/account/pledges?page=2",
            "https://user" + "@robertsspaceindustries.com/account/pledges?page=2",
            "https://robertsspaceindustries.com:444/account/pledges?page=2",
            "https://robertsspaceindustries.com/account/buy-back-pledges",
            "https://robertsspaceindustries.com/account/pledges/gift",
            "https://robertsspaceindustries.com/account/pledges?page=2&action=reclaim",
            "https://robertsspaceindustries.com/account/pledges?page=2&upgrade=1",
            "https://robertsspaceindustries.com/account/pledges?page=2&product-type=ship",
            "https://robertsspaceindustries.com/account/pledges?page=2&page=2",
            "https://robertsspaceindustries.com/account/pledges?page=3",
            "https://robertsspaceindustries.com/account/pledges?page=02",
            "https://robertsspaceindustries.com/account/pledges?page=2#gift",
            "https://robertsspaceindustries.com/account/pledges?page=%32",
            "https://robertsspaceindustries.com/account/pledges?page=101",
            "https://robertsspaceindustries.com/account/pledges?search=ship&page=2",
            "javascript:alert(1)", "file:///C:/fixture.html"
        }) Require(!RsiHangarNavigationPolicy.Allows(HangarNavigationAction.NextPage, first, new Uri(value)), "Unexpected automatic action accepted: " + value);
    }

    private static void Require(bool condition, string message)
    { if (!condition) throw new InvalidOperationException(message); }
}
