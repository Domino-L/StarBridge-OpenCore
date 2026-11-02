using StarBridge.HostRuntime.Images;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime;

public sealed partial class AccountBridgeRuntime
{
    private readonly object _imageCacheGate = new();
    private RemoteImageCacheBridge? _imageCache;

    private ValueTask<BridgeDispatchBatch> DispatchImageCacheAsync(BridgeEnvelope request, CancellationToken token)
    {
        RemoteImageCacheBridge bridge;
        lock (_imageCacheGate)
        {
            if (_disposed || _offlineAccount is null)
                return ValueTask.FromResult(new BridgeDispatchBatch(BridgeEnvelope.ErrorResponse(request with { AccountContext = null },
                    new("imageCache.unavailable", "Image cache is unavailable.", true)), []));
            bridge = _imageCache ??= new(_offlineAccount, CaptureImageCacheOwner);
        }
        // NativeAccountRuntimeBinding's original slot owns this physical call.
        // Completed offline restores a new local slot without reopening the
        // original account network lane. Installed candidates retain their own
        // typed installation request lease through DispatchCoreAsync.
        return bridge.DispatchAsync(request, token);
    }

    private RemoteImageCacheOwner? CaptureImageCacheOwner()
    {
        if (_disposed || _offlineAccount is null) return null;
        try
        {
            var mode = FirstUseMode;
            var observed = mode?.Current;
            var generation = mode?.ControlGeneration ?? Generation;
            if (mode is not null && observed is { State: "offline" })
            {
                var fence = mode.CaptureOfflineReadFence(observed.Revision);
                bool Current() => !_disposed && ReferenceEquals(FirstUseMode, mode) &&
                    mode.ControlGeneration == generation && fence();
                var retained = _offlineAccount.ReadRetainedOwner(observed.Revision, Current);
                if (retained is null) return null;
                bool Verify() => Current() && mode.Current == observed &&
                    _offlineAccount.ReadRetainedOwner(observed.Revision, Current) == retained && Current();
                return Verify() ? new(null, observed.Revision, generation, Current, Verify) : null;
            }
            if (observed is not null && observed is not { State: "online", ActiveMode: "online", PublicationSuspended: false }) return null;
            bool Admission() => !_disposed && !FirstUseBusinessUnavailable && (_firstUseCandidate
                ? _firstUseInstallation is { IsActive: true }
                : !_requestRetirement.IsClosed && !_localBusinessRetired);
            var selected = _host.CurrentContext;
            if (selected is null || !Admission()) return null;
            var onlineFence = mode is null ? null : mode.CaptureOnlineReadFence(observed!.Revision);
            bool Online() => Admission() && _host.CurrentContext == selected &&
                (mode is null ? FirstUseMode is null && Generation == generation :
                    ReferenceEquals(FirstUseMode, mode) && mode.ControlGeneration == generation && onlineFence!());
            bool Confirm() => Online() && (mode is null || mode.Current == observed) && Online();
            return Confirm() ? new(selected, null, generation, Online, Confirm) : null;
        }
        catch (Exception error) when (CacheFailure(error)) { return null; }
    }

    private void DisposeImageCache()
    {
        RemoteImageCacheBridge? bridge;
        lock (_imageCacheGate) { bridge = _imageCache; _imageCache = null; }
        bridge?.Dispose();
    }
}
