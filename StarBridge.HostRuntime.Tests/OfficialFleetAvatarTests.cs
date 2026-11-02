using System.Text.Json;
using StarBridge.HostRuntime.OfficialFleet;

internal static class OfficialFleetAvatarTests
{
    internal static void Run()
    {
        const string root = "https://robertsspaceindustries.com/avatar.png";
        string?[] accepted = [root, "https://cdn.robertsspaceindustries.com/avatar.png",
            "https://robertsspaceindustries.com:443/avatar.png",
            "https://cdn.robertsspaceindustries.com:443/avatar.png"];
        string?[] rejected = [null, "", " ", "http://robertsspaceindustries.com/avatar.png",
            "https://evil.test/avatar.png", "https://robertsspaceindustries.com.evil.test/avatar.png",
            "https://evil.test/robertsspaceindustries.com", "https://robertsspaceindustries.com" + "@evil.test/avatar.png",
            "https://evil.test" + "@robertsspaceindustries.com/avatar.png", "https://robertsspaceindustries.com:444/avatar.png",
            "https://127.0.0.1/avatar.png", "https://[::1]/avatar.png", root + new string('a', 2048)];
        var count = 0;
        foreach (var input in accepted.Concat(rejected))
        {
            foreach (var state in new string?[] { null, "unlinked", "visible", "restricted" })
            {
                var data = JsonSerializer.SerializeToElement(new { total = 1, list = new[] {
                    new { userId = 1, nickname = "SCM Pilot", avatar = input } } });
                var identities = state is null ? null : new Dictionary<long, OfficialFleetMemberIdentity> {
                    [1] = new(1, state, Callsign: "Bridge Pilot") };
                var page = JsonSerializer.SerializeToElement(OfficialFleetReadModel.Members(
                    data, "officialFleet:7", 1, 25, "", _ => "member-ref", identities));
                var row = page.GetProperty("members")[0];
                var expected = state is "visible" or "restricted" || !accepted.Contains(input)
                    ? null : new Uri(input!).AbsoluteUri;
                Check(row.GetProperty("avatarUrl").GetString() == expected, "avatar projection");
                Check(row.GetProperty("identityState").GetString() ==
                    (state == "visible" ? "starBridge" : state == "restricted" ? "restricted" : "scm"), "identity state");
                Check(row.GetProperty("callsign").GetString() ==
                    (state == "visible" ? "Bridge Pilot" : state == "restricted" ? "—" : "SCM Pilot"), "identity name");
                Check(row.GetProperty("profileTargetRef").GetString() ==
                    (state == "visible" ? "member-ref" : null), "profile authority");
                count++;
            }
        }
        Console.WriteLine($"PASS official fleet RSI avatar allowlist and identity rules ({count} cases)");
    }

    private static void Check(bool value, string label)
    {
        if (!value) throw new InvalidOperationException("Official fleet avatar regression: " + label);
    }
}
