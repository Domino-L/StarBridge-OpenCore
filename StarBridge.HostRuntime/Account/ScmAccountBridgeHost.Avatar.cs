using System.Text.Json;
using StarBridge.NativeBridge;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.PartyRooms;
using System.Net;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    private string? _scmAvatarImageData;
    private readonly Func<Uri, CancellationToken, Task<byte[]?>> _rsiAvatarDownload;
    internal event Action<BridgeAccountContext, long, StarBridge.Core.Profiles.PersonalProfileDocumentContract, CancellationToken>? AvatarProfileObserved;
    public async Task<object> ReadAvatarAsync(BridgeAccountContext context, CancellationToken token)
    {
        var generation = Generation;
        StarBridge.Core.Profiles.PersonalProfileDocumentContract profile;
        try { profile = await GetPersonalProfileAsync(context, token); }
        catch (AccountBridgeHostException error) when (error.Code is
            AccountBridgeStableErrors.PersonalProfileReadForbidden or AccountBridgeStableErrors.PersonalProfileDataInvalid)
        {
            if (!_disposed && generation == Generation && CurrentContext == context) ForgetAvatarImage(context);
            throw;
        }
        if (_disposed || generation != Generation || CurrentContext != context)
            throw new AccountBridgeHostException("account.reauthorization_required");
        token.ThrowIfCancellationRequested();
        // SCM: GetPersonalProfileAsync already replaced the stored upload with the RSI image.
        var image = _session is not null
            ? profile.Identity.AvatarAssetId
            : RoomAvatarProjection.Normalize(profile.Identity.AvatarAssetId, 512 * 1024);
        var callSign = ValidDisplayCallSign(profile.Identity.Callsign);
        if (_session is not null) { _scmAvatarImageData = image; _scmDisplayCallSign = callSign; }
        AvatarProfileObserved?.Invoke(context, generation, profile, token);
        return new { schemaVersion = 1, imageData = image, callSign, revision = profile.Revision };
    }

    public async Task<object> UpdateAvatarAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token)
    {
        if (payload.ValueKind != JsonValueKind.Object || payload.EnumerateObject().Count() != 2 ||
            !payload.TryGetProperty("schemaVersion", out var schema) || !schema.TryGetInt32(out var version) || version != 1 ||
            !payload.TryGetProperty("imageData", out var image) || image.ValueKind != JsonValueKind.String)
            throw new AccountBridgeHostException("account.avatar_invalid");
        if (RoomAvatarProjection.Normalize(image.GetString(), 512 * 1024) is null)
            throw new AccountBridgeHostException("account.avatar_invalid");
        // SCM-signed-in users use their RSI avatar; StarBridge no longer stores a custom one for them.
        // Legacy accounts keep their own avatar below.
        if (_session is not null) throw new AccountBridgeHostException("account.avatar_managed_by_scm");
        if (_legacySession is not { } legacy || _legacyPasswordLogin is null)
            throw new AccountBridgeHostException("account.avatar_managed_by_scm");
        var generation = Generation;
        void Current()
        {
            token.ThrowIfCancellationRequested();
            if (_disposed || generation != Generation || context != CurrentContext ||
                _legacySession != legacy || _reauthorizationRequired || _credentialTemporarilyUnavailable || _legacyRestoreUnavailable)
                throw new AccountBridgeHostException("account.reauthorization_required");
        }
        Current();
        var confirmed = await _legacyPasswordLogin.UpdateAvatarAsync(legacy, image.GetString()!, Current, token);
        Current();
        _legacyAvatarImageData = confirmed;
        return new { schemaVersion = 1, imageData = confirmed };
    }

    // Every self-profile document handed out for an SCM session (profile page,
    // editor, offline snapshot) carries the RSI avatar, never the old upload the
    // profile service still stores. No avatar URL = no avatar; a failed download
    // keeps the last image.
    private async Task<StarBridge.Core.Profiles.PersonalProfileDocumentContract> WithRsiAvatarAsync(
        StarBridge.Core.Profiles.PersonalProfileDocumentContract profile, BridgeAccountContext context,
        long generation, CancellationToken token) =>
        profile with { Identity = profile.Identity with { AvatarAssetId = await ReadRsiAvatarAsync(context, generation, token) } };

    // SCM avatars come from RSI (SCM /me avatarUrl). Failed downloads are not
    // cached, so a later read retries; the old StarBridge upload is never used.
    private (BridgeAccountContext Owner, string Url, string Image)? _rsiAvatarCache;
    // The avatar the offline store last kept for this owner; set by the runtime.
    internal Func<BridgeAccountContext, long, string?>? StoredAvatarImage { get; set; }
    // A kept image must not be saved again: not to refresh its time, and not over a
    // newer image. Compared by value and only released when that same image is
    // confirmed, so a concurrent read cannot answer for this profile.
    private string? _keptAvatarImage;
    internal bool IsKeptAvatarImage(string? image) => image is not null && image == Volatile.Read(ref _keptAvatarImage);
    private void ConfirmAvatarImage(string image)
    {
        if (IsKeptAvatarImage(image)) Volatile.Write(ref _keptAvatarImage, null);
    }
    // A hard read failure on any path, including internal reads; the runtime drops the stored profile.
    internal event Action<BridgeAccountContext, long>? AvatarDenied;
    // A confirmed profile has no usable URL; the runtime drops only the stored image.
    internal event Action<BridgeAccountContext, long>? AvatarConfirmedAbsent;
    private BridgeAccountContext? _avatarClearedOwner;
    private void ForgetAvatarImage(BridgeAccountContext context)
    {
        _scmAvatarImageData = null;
        _rsiAvatarCache = null;
        _avatarClearedOwner = context;
        Volatile.Write(ref _keptAvatarImage, null);
    }

    private async Task<string?> ReadRsiAvatarAsync(BridgeAccountContext context, long generation, CancellationToken token)
    {
        string? url;
        bool known, suppressed;
        lock (_realtimeGate)
        {
            var memory = _profileReadSnapshot;
            suppressed = _profileReadCacheSuppressed;
            var cached = memory?.Owner == context && memory.Generation == generation
                ? memory.Profile : suppressed ? null : _profileCache.Load(CurrentRoute());
            known = cached is not null;
            url = cached?.AvatarUrl;
        }
        var uri = RsiAvatarImage.Validate(url);
        // Only a confirmed profile without a usable URL, or a hard read failure, clears the avatar.
        if (uri is null && (known || suppressed))
        {
            ForgetAvatarImage(context);
            AvatarConfirmedAbsent?.Invoke(context, generation);
            return null;
        }
        string? image = null;
        if (uri is not null)
        {
            if (_rsiAvatarCache is { } hit && hit.Owner == context && hit.Url == uri.AbsoluteUri)
            {
                ConfirmAvatarImage(hit.Image);
                return hit.Image;
            }
            try { image = RsiAvatarImage.ToImageData(await _rsiAvatarDownload(uri, token)); }
            catch (Exception error) when ((error is HttpRequestException or IOException or TaskCanceledException) &&
                !token.IsCancellationRequested) { image = null; }
        }
        token.ThrowIfCancellationRequested();
        if (_disposed || generation != Generation || CurrentContext != context)
            throw new AccountBridgeHostException("account.reauthorization_required");
        if (image is not null)
        {
            _rsiAvatarCache = (context, uri!.AbsoluteUri, image);
            _avatarClearedOwner = null;
            ConfirmAvatarImage(image);
            return image;
        }
        if (suppressed) return null;
        var kept = _rsiAvatarCache is { } last && last.Owner == context ? last.Image :
            _avatarClearedOwner == context ? null : StoredAvatarImage?.Invoke(context, generation);
        Volatile.Write(ref _keptAvatarImage, kept);
        return kept;
    }
}
