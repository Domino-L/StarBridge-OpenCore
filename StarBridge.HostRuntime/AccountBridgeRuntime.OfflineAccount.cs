using StarBridge.HostRuntime.Account;
using StarBridge.NativeBridge;
using System.Text.Json;

namespace StarBridge.HostRuntime;

public sealed partial class AccountBridgeRuntime
{
    private OfflineAccountStore? _offlineAccount;
    private sealed record RetainedDataSelection(string ReadId, long Generation, BridgeAccountContext Owner,
        Auth.ScmOfflineDisplayOwner Credential);
    private RetainedDataSelection? _retainedDataSelection;
    internal void InitializeOfflineAccount(string root)
    {
        InitializeAccountDisplayCache(root);
        InitializeOfflineAppearancesCore(root);
    }

    // Ordinary startup needs presentation caching too. This does not construct
    // a first-use mode, offline entitlement verifier, credential or new timer.
    private void InitializeAccountDisplayCache(string root)
    {
        if (_offlineAccount is null && _host is ScmAccountBridgeHost scm)
        {
            scm.AuthenticatedSessionRetired += RetireOfflineAppearanceProof;
            scm.AccountDisplayObserved += ObserveAccountDisplay;
            scm.AvatarProfileObserved += ObserveAvatarProfile;
            scm.StoredAvatarImage = ReadStoredAvatar;
            scm.AvatarDenied += (owner, generation) =>
                ChangeStoredAvatar(owner, generation, (store, current) => store.ClearRemoteProfile(owner, current));
            scm.AvatarConfirmedAbsent += (owner, generation) =>
                ChangeStoredAvatar(owner, generation, (store, current) => store.ClearStoredAvatar(owner, current));
            scm.OrganizationDisplayObserved += ObserveOrganizationDisplay;
            scm.OrganizationReadStarting += BeginOrganizationDisplayRead;
            scm.OrganizationReadFinished += CompleteOrganizationDisplayRead;
            scm.OrganizationLogoObserved += ObserveOrganizationLogo;
            scm.OrganizationImageReadStarting += CaptureOrganizationImageRead;
            scm.FriendsReadStarting += BeginFriendsDisplayRead;
            scm.FriendsReadFinished += CompleteFriendsDisplayRead;
        }
        _offlineAccount ??= new(root);
        _offlineAccount.ScmAchievementsRead = ConfirmOfflineScmAchievements;
    }

    private void ObserveAccountDisplay(AccountBridgeSessionProjection projection, CancellationToken token)
    {
        if (projection.State is not ("signedIn" or "legacySignedIn") ||
            projection.Context is not { } context || projection.DisplayName is not { } name) return;
        // The restored root legitimately changes generation. Observe the actual
        // Native projection before its wire response keeps the request generation.
        // This receipt is display-only and never establishes account authority.
        bool Current() => !token.IsCancellationRequested && !_disposed && !_firstUseCandidate &&
            !_requestRetirement.IsClosed && projection.Generation == Generation && context == _host.CurrentContext;
        try { if (Current()) PersistAccountDisplay(context, name, Current); }
        catch (Exception error) when (CacheFailure(error)) { }
    }

    private void PersistAccountDisplay(BridgeAccountContext context, string name, Func<bool> current)
    {
        BridgeAccountContext? storage = null;
        try { storage = _host.ResolveLocalDataOwner(context); }
        catch (Privacy.LocalPrivacyException) { }
        _offlineAccount?.Observe(context, name, current, storage);
        if (_host is ScmAccountBridgeHost scm && scm.ReadCurrentOfflineAppearanceSnapshot() is { } snapshot)
            ObserveOfflineAppearanceProofCore(context, snapshot.OfflineReceipt, current);
    }
    private void ObserveAvatarProfile(BridgeAccountContext owner, long generation,
        StarBridge.Core.Profiles.PersonalProfileDocumentContract profile, CancellationToken token)
    {
        bool Current() => !token.IsCancellationRequested && !_disposed && !_firstUseCandidate &&
            !_requestRetirement.IsClosed && generation == Generation && owner == _host.CurrentContext;
        try
        {
            if (Current() && !(_host is ScmAccountBridgeHost scm && scm.IsKeptAvatarImage(profile.Identity.AvatarAssetId)))
                _offlineAccount?.ObserveAvatarProfile(owner, profile, Current);
        }
        catch (Exception error) when (CacheFailure(error)) { }
    }
    // A live first-use installation serves online business with the original retirement closed.
    internal bool AvatarStoreOpen => !_disposed &&
        (_firstUseCandidate ? Volatile.Read(ref _firstUseInstallation)?.IsActive == true : !_requestRetirement.IsClosed);
    private void ChangeStoredAvatar(BridgeAccountContext owner, long generation, Action<OfflineAccountStore, Func<bool>> change)
    {
        bool Current() => AvatarStoreOpen && generation == Generation && owner == _host.CurrentContext;
        try { if (_offlineAccount is { } store) change(store, Current); }
        catch (Exception error) when (CacheFailure(error)) { }
    }
    private bool CarriesKeptAvatar(JsonElement payload) =>
        _host is ScmAccountBridgeHost scm && payload.ValueKind == JsonValueKind.Object &&
        payload.TryGetProperty("profile", out var profile) && profile.ValueKind == JsonValueKind.Object &&
        profile.TryGetProperty("identity", out var identity) && identity.ValueKind == JsonValueKind.Object &&
        identity.TryGetProperty("avatarAssetId", out var image) && image.ValueKind == JsonValueKind.String &&
        scm.IsKeptAvatarImage(image.GetString());
    private string? ReadStoredAvatar(BridgeAccountContext owner, long generation)
    {
        bool Current() => AvatarStoreOpen && generation == Generation && owner == _host.CurrentContext;
        try { return _offlineAccount?.ReadSelectedDisplay(owner, Current)?.AvatarImageData; }
        catch (Exception error) when (CacheFailure(error)) { return null; }
    }
    partial void InitializeOfflineAppearancesCore(string root);
    partial void RetireOfflineAppearanceProofCore(BridgeAccountContext owner);
    private void RetireOfflineAppearanceProof(BridgeAccountContext owner)
    {
        // An actual retired session or confirmed rejection of the original
        // stored credential, never a transport outage or manual-offline stop.
        // Retiring authorization must not delete account display data.
        try { RetireOfflineAppearanceProofCore(owner); }
        catch (Exception error) when (CacheFailure(error)) { }
    }
    partial void ObserveOfflineAppearanceProofCore(BridgeAccountContext owner, JsonElement? proof, Func<bool> current);
    partial void ReadOfflineAppearanceProofCore(BridgeAccountContext owner, Func<bool> current,
        ref IReadOnlyList<string>? result);

    private IReadOnlyList<string> ReadCurrentOverlayEntitlements()
    {
        if (_disposed) return [];
        if (FirstUseMode is { } mode && mode.Current is { State: not "online" } observed)
        {
            if (observed.State != "offline" || _offlineAccount is null) return [];
            var fence = mode.CaptureOfflineReadFence(observed.Revision);
            bool Current() => !_disposed && fence();
            try
            {
                if (_offlineAccount.ReadRetainedOwner(observed.Revision, Current) is not { } owner) return [];
                IReadOnlyList<string>? verified = null;
                // Full disk/credential validation brackets the proof read;
                // nested storage guards only need the original runtime fence.
                // No result escapes until external mode/credential writes are
                // checked again, avoiding repeated DPAPI calls per guard.
                ReadOfflineAppearanceProofCore(owner, Current, ref verified);
                return Current() && _offlineAccount.ReadRetainedOwner(observed.Revision, Current) == owner &&
                    mode.Current == observed && Current() ? verified ?? [] : [];
            }
            catch (Exception error) when (CacheFailure(error)) { return []; }
        }
        if (_host is ScmAccountBridgeHost scm && scm.ReadOfflineDisplaySelection() is { } selected)
        {
            var generation = Generation;
            bool Current() => !_disposed && Generation == generation &&
                scm.ReadOfflineDisplaySelection() == selected;
            IReadOnlyList<string>? verified = null;
            try { ReadOfflineAppearanceProofCore(selected.Owner, Current, ref verified); }
            catch (Exception error) when (CacheFailure(error)) { return []; }
            return Current() ? verified ?? [] : [];
        }
        return _host.CurrentOverlayEntitlements;
    }

    private BridgeEnvelope AddRetainedAccountDisplay(BridgeEnvelope request, BridgeEnvelope response, Func<bool> current)
    {
        var previous = request.Name == AccountBridgeRequestNames.GetCurrent
            ? Interlocked.Exchange(ref _retainedDataSelection, null) : null;
        if (_offlineAccount is null || _host is not ScmAccountBridgeHost scm ||
            request.Name != AccountBridgeRequestNames.GetCurrent || response.Status != "ok" ||
            response.AccountContext is not null || !response.Payload.TryGetProperty("state", out var state) ||
            state.GetString() != "credentialTemporarilyUnavailable") return response;
        try
        {
            var selection = scm.ReadOfflineDisplaySelection();
            if (selection is not { } selected) return response;
            bool Selected() => current() && scm.ReadOfflineDisplaySelection() == selection;
            var display = _offlineAccount.ReadSelectedDisplay(selected.Owner, Selected);
            if (display is null || !Selected()) return response;
            var access = new RetainedDataSelection(Guid.NewGuid().ToString("N"), Generation, selected.Owner, selected.Credential);
            Volatile.Write(ref _retainedDataSelection, access);
            var payload = System.Text.Json.Nodes.JsonNode.Parse(response.Payload.GetRawText())!.AsObject();
            payload["retainedDisplay"] = JsonSerializer.SerializeToNode(new {
                displayName = display.DisplayName, cachedAtUtc = display.CachedAtUtc, readId = access.ReadId,
                previousReadId = previous is not null && previous.Generation == access.Generation &&
                    previous.Owner == access.Owner && previous.Credential == access.Credential ? previous.ReadId : null,
                avatarImageData = display.AvatarImageData, avatarCachedAtUtc = display.AvatarCachedAtUtc }, BridgeProtocol.JsonOptions);
            return response with { Payload = JsonSerializer.SerializeToElement(payload) };
        }
        catch (Exception error) when (CacheFailure(error)) { return response; }
    }

    private BridgeEnvelope AddSignedInCachedAvatar(BridgeEnvelope request, BridgeEnvelope response, Func<bool> current)
    {
        if (_offlineAccount is null || request.Name != AccountBridgeRequestNames.GetCurrent ||
            response.Status != "ok" || response.AccountContext is not { } owner ||
            !response.Payload.TryGetProperty("state", out var state) || state.GetString() is not ("signedIn" or "legacySignedIn") ||
            response.Payload.TryGetProperty("avatarImageData", out var image) && image.ValueKind != JsonValueKind.Null)
            return response;
        // The first restored root keeps the original wire generation (often 0)
        // while Native has already authenticated generation 1. Cache is allowed
        // only AFTER that authentication, for its exact current owner, and is
        // display-only. It never establishes a session or any permission.
        var generation = Generation;
        bool Current() => current() && !_requestRetirement.IsClosed &&
            Generation == generation && _host.CurrentContext == owner;
        try
        {
            var display = _offlineAccount.ReadSelectedDisplay(owner, Current);
            if (display?.AvatarImageData is null || !Current()) return response;
            var payload = System.Text.Json.Nodes.JsonNode.Parse(response.Payload.GetRawText())!.AsObject();
            payload["avatarImageData"] = display.AvatarImageData;
            return Current() ? response with { Payload = JsonSerializer.SerializeToElement(payload) } : response;
        }
        catch (Exception error) when (CacheFailure(error)) { return response; }
    }

    private void ObserveOfflineAccount(BridgeEnvelope request, BridgeEnvelope response, Func<bool> current)
    {
        if (_offlineAccount is null || !current() ||
            response.AccountContext is not { } context || context != _host.CurrentContext) return;
        try
        {
            if (response.Status != "ok")
            {
                if (request.Name is AccountBridgeRequestNames.GetPersonalProfile or "account.readAvatar" &&
                    request.AccountContext == context && response.Error?.Code is
                        AccountBridgeStableErrors.PersonalProfileReadForbidden or AccountBridgeStableErrors.PersonalProfileDataInvalid)
                    _offlineAccount.ClearRemoteProfile(context, current);
                return;
            }
            if (request.Name == AccountBridgeRequestNames.GetCurrent &&
                response.Payload.TryGetProperty("state", out var state) &&
                state.GetString() is "signedIn" or "legacySignedIn" &&
                response.Payload.TryGetProperty("displayName", out var name) && name.ValueKind == JsonValueKind.String)
            {
                // SCM/selected Relay roots are already observed at their exact
                // Native generation, including the initial restore transition.
                if (_host is not ScmAccountBridgeHost) PersistAccountDisplay(context, name.GetString()!, current);
            }
            else if (request.Name == AccountBridgeRequestNames.GetPersonalProfile && request.AccountContext == context &&
                !CarriesKeptAvatar(response.Payload))
                _offlineAccount.ObserveProfile(context, response.Payload, current);
        }
        // Optional display persistence never changes the original business result.
        catch (Exception error) when (CacheFailure(error)) { }
    }

    internal Auth.ScmCredentialRetirementStamp? ReadRetainedCredentialVersion(BridgeAccountContext owner, long generation) =>
        !_disposed && _host is ScmAccountBridgeHost scm ? scm.ReadRetainedCredentialVersion(owner, generation) : null;

    internal void PinOfflineAccount(BridgeAccountContext context, long revision, Func<bool> current,
        Auth.ScmCredentialRetirementStamp? credential = null)
    {
        try { _offlineAccount?.Pin(context, revision, current, credential); }
        catch (Exception error) when (CacheFailure(error)) { }
    }

    internal OfflineAccountDisplay? ReadOfflineAccount(long revision)
    {
        try { return _offlineAccount?.ReadDisplay(revision); }
        catch (Exception error) when (CacheFailure(error)) { return null; }
    }
    internal Hangar.LocalHangarSnapshot? ReadOfflineHangar(long revision) => _offlineAccount?.ReadHangar(revision);
    internal Profiles.LocalProfileSnapshot? ReadOfflineProfile(long revision) => _offlineAccount?.ReadProfile(revision);
    internal OfflinePersonalProfileDisplay? ReadOfflineRemoteProfile(long revision) => _offlineAccount?.ReadRemoteProfile(revision);
    internal OfflineAchievementDisplay? ReadOfflineAchievements(long revision) => _offlineAccount?.ReadAchievements(revision);
    internal Achievements.ScmAchievementCatalog? ReadOfflineScmAchievements(long revision) => _offlineAccount?.ReadScmAchievements(revision);
    private OfflineAchievementDisplay? ReadCachedAchievements(BridgeAccountContext owner, Func<bool> current)
    {
        try { return _offlineAccount?.ReadSelectedAchievements(owner, current); }
        catch (Exception error) when (CacheFailure(error)) { return null; }
    }
    private void ObserveOfflineAchievements(BridgeAccountContext owner, Achievements.AchievementSnapshot snapshot, Func<bool> current)
    {
        try { _offlineAccount?.ObserveAchievements(owner, snapshot, current); }
        catch (Exception error) when (CacheFailure(error)) { }
    }
    internal void ReturnOfflineAccount(long previousRevision, long revision, Func<bool> current)
    {
        try { _offlineAccount?.ReturnToOffline(previousRevision, revision, current); }
        catch (Exception error) when (CacheFailure(error)) { }
    }
    private static bool CacheFailure(Exception error) => error is IOException or UnauthorizedAccessException or
        JsonException or System.Security.Cryptography.CryptographicException or InvalidOperationException or ArgumentException;
}
