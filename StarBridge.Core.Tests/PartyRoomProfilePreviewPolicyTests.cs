using StarBridge.Core.PartyRooms;

namespace StarBridge.Core.Tests;

internal static class PartyRoomProfilePreviewPolicyTests
{
    internal static void RunAll()
    {
        foreach (var password in new[] { false, true })
        foreach (var admission in new string?[] { "direct", "approval", "future", null })
        foreach (var eligibility in new string?[] { "everyone", "friends", "fleet", "invite", "future", null })
        {
            var expected = !password && admission is "direct" or "approval" && eligibility is "everyone" or "friends" or "fleet";
            if (PartyRoomProfilePreviewPolicy.Allows(password, admission, eligibility) != expected)
                throw new InvalidOperationException("Room profile preview must fail closed for locked and unsupported admission.");
        }
    }
}
