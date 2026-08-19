namespace StarBridge.Desktop;

internal sealed record GameProcessSessionObservation(
    bool IsRunning,
    DateTimeOffset? MissingSinceUtc,
    bool SessionEnded);

internal static class GameProcessSessionBoundaryPolicy
{
    internal static readonly TimeSpan MissingProcessConfirmationWindow = TimeSpan.FromSeconds(10);

    internal static GameProcessSessionObservation Observe(
        bool sessionWasRunning,
        bool processObserved,
        DateTimeOffset now,
        DateTimeOffset? missingSinceUtc)
    {
        if (processObserved)
        {
            return new GameProcessSessionObservation(
                IsRunning: true,
                MissingSinceUtc: null,
                SessionEnded: false);
        }

        if (!sessionWasRunning)
        {
            return new GameProcessSessionObservation(
                IsRunning: false,
                MissingSinceUtc: null,
                SessionEnded: false);
        }

        var missingSince = missingSinceUtc is null || missingSinceUtc > now
            ? now
            : missingSinceUtc.Value;
        if (now - missingSince < MissingProcessConfirmationWindow)
        {
            // Process enumeration can briefly miss Star Citizen while Windows is
            // under load. Keep the current game session authoritative until the
            // absence has remained stable long enough to confirm a real exit.
            return new GameProcessSessionObservation(
                IsRunning: true,
                MissingSinceUtc: missingSince,
                SessionEnded: false);
        }

        return new GameProcessSessionObservation(
            IsRunning: false,
            MissingSinceUtc: null,
            SessionEnded: true);
    }
}
