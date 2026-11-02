namespace StarBridge.HostRuntime.Overlay;

public sealed record RallyBannerNotice(Guid Id, string Text, DateTimeOffset ExpiresAt,
    string Preview, Func<bool> IsCurrent)
{
    public bool Sample { get; init; }
}

public interface IRallyBannerSink
{
    // True means submitted to a banner surface that shows with or without the overlay.
    ValueTask<bool> TryPresentAsync(RallyBannerNotice notice, CancellationToken cancellationToken);
    void Clear(Guid id);
}
