namespace StarBridge.HostRuntime.Presence;

public sealed partial class GameplayTimeRuntime
{
    // Reuse the account's existing consent owner; no remote eligibility or once-only marker.
    internal bool MissionImportConsentAllowed
    {
        get
        {
            lock (_sync)
            {
                var entry = Resolve();
                return entry?.Saved is not null && entry.Error is null && entry.Desired == GameplayRecordingConsent.Allowed;
            }
        }
    }
}
