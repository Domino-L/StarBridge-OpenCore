using StarBridge.Core.Parsing;

namespace StarBridge.Core.Tests;

internal static class LocalGameIdentityLineTests
{
    private static readonly DateTimeOffset Now = new(2026, 1, 1, 12, 0, 0, TimeSpan.Zero);
    internal static void RunAll()
    {
        foreach (var value in new[] { " 100", "=100", "=\"100\"", " \"100\"", "=000100" })
        {
            var line = $"<2026-01-01T11:59:00.000Z> [Client] nickname=\"Pilot-Example\" playerGEID{value}, [Tag]";
            Require(LocalGameIdentityLine.Parse(line, Now, out var record) == LocalGameIdentityLineState.Valid &&
                record is { Handle: "Pilot-Example", PlayerId: "100" } && record.ObservedAt == Now.AddMinutes(-1),
                "Canonical identity, timestamp and numeric ID must be retained.");
        }
        foreach (var body in new[] { "nickname=\"Pilot-Example\"", "Player[Pilot-Example] joined channel ship",
            "PLAYER_ONLINE player=Pilot-Example", "othernickname=\"Pilot-Example\" playerGEID=100",
            "nickname=\"Pilot-Example\" playerGEIDOther=100", "party nickname=\"Pilot-Example\"" })
            Require(State("<2026-01-01T11:59:00Z> " + body) == LocalGameIdentityLineState.Unrelated,
                "Other-player mentions are not local identity evidence.");
        foreach (var body in new[] { "nickname=\"Pilot-Example\" playerGEID=0",
            "nickname=\"Pilot-Example\" playerGEID=000", "nickname=\"Pilot-Example\" playerGEID=100suffix",
            "nickname=\"Pilot-Example\" playerGEID=\"100", "nickname=\"Pilot-Example\" playerGEID=100\"",
            "nickname=\"Pilot-Example\" playerGEID=１００", "nickname=\" Pilot-Example\" playerGEID=100",
            "nickname=\"Pilot Example\" playerGEID=100", "nickname=\"Pilot-Example\" other=true playerGEID=100",
            "nickname=\"Pilot-Example\" playerGEID=100 nickname=\"Other-Pilot\" playerGEID=200",
            "nickname=\"Pilot-Example\" playerGEID=100 nickname=\"Other-Pilot\" playerGEID=broken",
            "nickname=\"Pilot-Example\" playerGEID=100 playerGEID=200" })
            Require(State("<2026-01-01T11:59:00Z> " + body) == LocalGameIdentityLineState.Invalid,
                "Damaged or multiple identity records must not supply a candidate.");
        foreach (var stamp in new[] { "2026-02-30T11:59:00Z", "2026-01-01T12:00:01Z",
            "1969-12-31T11:59:00Z", "2026/01/01 11:59:00", "broken" })
            Require(State($"<{stamp}> nickname=\"Pilot-Example\" playerGEID=100") == LocalGameIdentityLineState.Invalid,
                "Only valid nonfuture canonical timestamp evidence is accepted.");
        Require(State("nickname=\"Pilot-Example\" playerGEID=100") == LocalGameIdentityLineState.Invalid,
            "An identity without its record time is uncertain.");
        Require(State("<2026-01-01T11:59:00Z> nickname=\"Pilot-Example\" playerGEID=100\0") == LocalGameIdentityLineState.Invalid,
            "Control bytes do not authorize identity.");
        SessionTime();
    }
    private static void SessionTime()
    {
        for (var digits = 0; digits <= 7; digits++)
        {
            var fraction = digits == 0 ? "" : "." + new string('0', digits);
            var line = $"<2026-01-01T11:59:00{fraction}Z> nickname=\"Pilot-Example\" playerGEID=100";
            Require(LocalGameIdentityLine.Parse(line, Now, out var record) == LocalGameIdentityLineState.Valid,
                "All supported timestamp precisions parse.");
            var resolution = (long)Math.Pow(10, 7 - digits);
            Require(record!.ResolutionTicks == resolution, "Keep the actual log timestamp precision.");
            var inside = record.ObservedAt.AddTicks(resolution - 1);
            Require(LocalGameIdentityLine.MeetsSessionTime(record, inside, inside, Now),
                "A byte-verified record may overlap a subsecond process/baseline boundary.");
            Require(!LocalGameIdentityLine.MeetsSessionTime(record, inside.AddTicks(1), inside, Now),
                "The quantized interval is half-open, not a whole extra second.");
            Require(!LocalGameIdentityLine.MeetsSessionTime(record, inside, inside.AddTicks(1), Now),
                "Both process and capture boundaries must match.");
        }
        var example = new LocalGameIdentityRecord("Pilot-Example", "100", Now);
        Require(!LocalGameIdentityLine.MeetsSessionTime(example, Now.AddTicks(1), Now, Now), "Clock rollback revokes evidence.");
        Require(!LocalGameIdentityLine.MeetsSessionTime(example, Now, Now.AddTicks(1), Now), "Future process start is not evidence.");
        Require(!LocalGameIdentityLine.MeetsSessionTime(example with { ResolutionTicks = 2 }, Now, Now, Now),
            "Unknown timestamp precision is not accepted.");
        Require(!LocalGameIdentityLine.MeetsSessionTime(example with { ObservedAt = Now.ToOffset(TimeSpan.FromHours(1)) },
            Now, Now, Now), "Records supplied outside the parser must still use UTC.");
        var maximum = example with { ObservedAt = DateTimeOffset.MaxValue };
        Require(LocalGameIdentityLine.MeetsSessionTime(maximum, DateTimeOffset.MaxValue, DateTimeOffset.MaxValue,
            DateTimeOffset.MaxValue), "Boundary comparison never overflows the maximum date.");
    }
    private static LocalGameIdentityLineState State(string line) => LocalGameIdentityLine.Parse(line, Now, out _);
    private static void Require(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }
}
