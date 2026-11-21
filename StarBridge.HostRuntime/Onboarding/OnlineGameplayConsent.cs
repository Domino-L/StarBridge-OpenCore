using StarBridge.HostRuntime.Presence;

namespace StarBridge.HostRuntime.Onboarding;

// Only an Unknown online record consults the existing setup choice. No local
// profile data is migrated, and a saved online decision always takes precedence.
internal static class OnlineGameplayConsent
{
    // Preserve the legacy default for online records with no applicable choice.
    private const GameplayRecordingConsent UnchosenLegacyDefault = GameplayRecordingConsent.Allowed;

    internal static GameplayRecordingConsent Read(string root, string? verifiedHandle, out bool identityPending)
    {
        identityPending = false;
        var local = new LocalFirstUseStore(root).Read();
        var source = local.Sources.SingleOrDefault(s => s.SourceKey == local.SelectedSourceKey);
        if (source is { ConfirmedProfileId: not null, NeedsFreshGameEvidence: false } &&
            local.ActiveProfileId == source.ConfirmedProfileId &&
            local.Profiles.SingleOrDefault(p => p.Id == source.ConfirmedProfileId) is { } profile)
        {
            // Identity metadata may arrive after login without changing the
            // account generation. Keep Unknown until its ownership can be checked.
            if (string.IsNullOrWhiteSpace(verifiedHandle))
            {
                try
                {
                    identityPending = new LocalGameplayTimeStore(root).Read(source.ConfirmedProfileId).Consent is
                        GameplayRecordingConsent.Allowed or GameplayRecordingConsent.Declined;
                }
                catch (LocalFirstUseException)
                {
                    // This optional hint cannot change the existing Unknown
                    // state when the saved choice cannot be checked yet.
                }
                return GameplayRecordingConsent.Unknown;
            }
            if (!string.Equals(profile.Handle, verifiedHandle.Trim(), StringComparison.OrdinalIgnoreCase))
                return UnchosenLegacyDefault;
            var choice = new LocalGameplayTimeStore(root).Read(source.ConfirmedProfileId).Consent;
            // A confirmed setup profile with no decision is still on the
            // existing statistics step. Do not materialize the legacy default
            // before that step has had a chance to save Declined.
            return choice;
        }
        return UnchosenLegacyDefault;
    }
}
