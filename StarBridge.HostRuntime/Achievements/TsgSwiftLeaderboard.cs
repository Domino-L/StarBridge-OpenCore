using System.Text.Json.Serialization;

namespace StarBridge.HostRuntime.Achievements;

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record LeaderboardEntry([property: JsonRequired] int Rank, [property: JsonRequired] string Handle, [property: JsonRequired] long BestMs, [property: JsonRequired] DateOnly AchievedOn);
public sealed record LeaderboardMe([property: JsonRequired] int? Rank, [property: JsonRequired] long? BestMs, [property: JsonRequired] bool OptedIn);
public sealed record TsgSwiftLeaderboard([property: JsonRequired] int SchemaVersion, [property: JsonRequired] DateTimeOffset ComputedAt,
    [property: JsonRequired] LeaderboardEntry[] Entries, [property: JsonRequired] LeaderboardMe Me)
{
    internal static bool ValidTime(DateTimeOffset at) => at > DateTimeOffset.UnixEpoch &&
        at.Offset == TimeSpan.Zero && at <= DateTimeOffset.UtcNow.AddMinutes(5);
    internal static bool ValidMs(long? ms) => ms is >= 300000 and <= 5400000;
    public void Validate()
    {
        if (SchemaVersion != 1 || !ValidTime(ComputedAt) || Entries is null || Entries.Length > 100 || Me is null ||
            Me.Rank is <= 0 || Me.BestMs is not null && !ValidMs(Me.BestMs) ||
            Me.Rank is not null && (!Me.OptedIn || Me.BestMs is null)) throw new InvalidDataException("Invalid leaderboard.");

        for (var i = 0; i < Entries.Length; i++)
        {
            var e = Entries[i];
            if (e is null || e.Rank != i + 1 || !ValidMs(e.BestMs) || (e.AchievedOn <= DateOnly.FromDateTime(DateTime.UnixEpoch) || e.AchievedOn > DateOnly.FromDateTime(DateTime.UtcNow)) ||
                e.Handle is not { Length: >= 1 and <= 60 } || e.Handle.Any(c => !(char.IsAsciiLetterOrDigit(c) || c is '_' or '-')) ||
                i > 0 && (Entries[i-1].BestMs > e.BestMs ||
                    Entries[i-1].BestMs == e.BestMs && Entries[i-1].AchievedOn > e.AchievedOn))
                throw new InvalidDataException("Invalid leaderboard entry.");
        }
    }
}

public sealed record LeaderboardConsent([property: JsonRequired] int SchemaVersion, [property: JsonRequired] string State, [property: JsonRequired] bool OptedIn, [property: JsonRequired] DateTimeOffset? DecidedAt)
{
    public void Validate()
    {
        if (SchemaVersion != 1 || State is not ("undecided" or "opted-in" or "withdrawn") ||
            OptedIn != (State == "opted-in") || (State == "undecided") != (DecidedAt is null) ||
            DecidedAt is { } at && !TsgSwiftLeaderboard.ValidTime(at)) throw new InvalidDataException("Invalid leaderboard consent.");
    }
}
