namespace StarBridge.Core.Tools;

/// <summary>Device-local ownership for one observed game process. A manual pause
/// survives client restarts but never applies to a different game process.</summary>
public sealed record ExecHangarGameMonitoring(Guid Id, string SessionId, DateTimeOffset StartedAt,
    bool Paused = false, DateTimeOffset? MissingSince = null, DateTimeOffset? MutedBoundary = null)
{
    public void Validate()
    {
        if (Id == Guid.Empty || string.IsNullOrWhiteSpace(SessionId) || SessionId.Length > 100 ||
            SessionId.Any(char.IsControl)) throw new ArgumentException("Invalid game monitoring session.");
    }

    public static ExecHangarGameMonitoring? Observe(ExecHangarGameMonitoring? current,
        string state, string? sessionId, DateTimeOffset now)
    {
        if (state == "running" && !string.IsNullOrWhiteSpace(sessionId) && sessionId.Length <= 100 && !sessionId.Any(char.IsControl))
            return current?.SessionId == sessionId ? current with { MissingSince = null } : new(Guid.NewGuid(), sessionId, now);
        if (current is null) return null;
        if (state != "notRunning") return current with { MissingSince = null };
        var missing = current.MissingSince is {} prior && prior <= now ? prior : now;
        return now - missing >= TimeSpan.FromSeconds(10) ? null : current with { MissingSince = missing };
    }
}
