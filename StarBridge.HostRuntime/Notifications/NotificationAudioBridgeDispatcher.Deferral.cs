namespace StarBridge.HostRuntime.Notifications;

public sealed partial class NotificationAudioBridgeDispatcher
{
    private readonly Achievements.AchievementCelebrationActivity _celebration;
    private sealed record DeferredAudio(long Generation, int AudioRevision, StarBridge.NativeBridge.BridgeAccountContext? Owner,
        string? Source, long SourceRevision, Func<bool> Play, DateTimeOffset AdmittedAt, TimeZoneInfo Zone, NotificationEventKind? Kind,
        Func<CancellationToken, Task<bool>>? Revalidate);
    private readonly Queue<DeferredAudio> _deferredAudio = new();
    private readonly ITimer _audioDrain;
    private bool _drainingAudio;
    private long? _audioAcceptedAt;
    private TimeSpan _audioDuration;
    private bool _deferredPlayback;
    private bool _audioAuthorizationPending;
    private bool AutomaticThrottled(int seconds) => !_drainingAudio && _lastPlayback is { } last &&
        _time.GetElapsedTime(last) < TimeSpan.FromSeconds(seconds);
    // Caller owns _gate. Return false to existing callers because queued is not yet played.
    private bool Defer(Func<bool> play, StarBridge.NativeBridge.BridgeAccountContext? owner = null, string? source = null,
        NotificationEventKind? kind = null, Func<CancellationToken, Task<bool>>? revalidate = null)
    {
        var tailPlaying = _deferredPlayback && _audioAcceptedAt is { } at && _time.GetElapsedTime(at) < _audioDuration;
        if (_drainingAudio || !AchievementPlaying && _deferredAudio.Count == 0 && !tailPlaying && !_audioAuthorizationPending) return false;
        _deferredAudio.Enqueue(new(_generation(), _store.Read().SuppressionRevision, owner, source,
            owner is not null && source is not null ? _policies.Read(owner).SuppressionRevision(source) : 0, play,
            _time.GetUtcNow(), NotificationOrganizationPolicy.LocalZone(_time), kind, revalidate));
        if (!AchievementPlaying) ScheduleDrain();
        return true;
    }
    private void CelebrationChanged(bool active)
    {
        lock (_gate)
        {
            if (_disposed) return;
            if (active) _audioDrain.Change(Timeout.InfiniteTimeSpan, Timeout.InfiniteTimeSpan);
            else { _audioAcceptedAt = null; _deferredPlayback = false; ScheduleDrain(); }
        }
    }
    private void ScheduleDrain() => _audioDrain.Change(TimeSpan.FromMilliseconds(25), Timeout.InfiniteTimeSpan);
    private void AudioAccepted(byte[] wave)
    {
        _audioAcceptedAt = _time.GetTimestamp();
        _deferredPlayback = _drainingAudio;
        // Verified PCM WAV: skip optional chunks and use the data duration, not a guessed cue lifetime.
        var bytesPerSecond = BitConverter.ToUInt32(wave, 28);
        _audioDuration = TimeSpan.FromSeconds(1);
        for (var offset = 12; offset + 8 <= wave.Length;)
        {
            var length = BitConverter.ToUInt32(wave, offset + 4);
            if (wave.AsSpan(offset, 4).SequenceEqual("data"u8) && bytesPerSecond > 0)
            { _audioDuration = TimeSpan.FromSeconds(Math.Max(1, (double)length / bytesPerSecond)); break; }
            if (length > int.MaxValue - offset - 9) break;
            offset += 8 + (int)length + (int)(length % 2);
        }
    }
    internal void DrainDeferred()
    {
        lock (_gate)
        {
            if (_disposed || AchievementPlaying || _audioAuthorizationPending) return;
            if (_audioAcceptedAt is { } at && _time.GetElapsedTime(at) < _audioDuration) { ScheduleDrain(); return; }
            while (_deferredAudio.TryDequeue(out var pending))
            {
                if (pending.Generation != _generation()) continue;
                try {
                    if (pending.AudioRevision != _store.Read().SuppressionRevision ||
                        pending.Owner is { } owner && pending.Source is { } source &&
                        (pending.SourceRevision != _policies.Read(owner).SuppressionRevision(source) || pending.Kind is { } kind &&
                            !NotificationOrganizationPolicy.Current(_policies, owner, source, kind, pending.SourceRevision,
                                pending.AdmittedAt, pending.Zone, _time))) continue;
                } catch (Exception error) when (error is System.IO.IOException or InvalidDataException or UnauthorizedAccessException or System.Text.Json.JsonException) { continue; }
                if (pending.Revalidate != null) {
                    _audioAuthorizationPending = true;
                    _ = ReauthorizeDeferredAsync(pending);
                    return;
                }
                _drainingAudio = true;
                var before = _audioAcceptedAt;
                try { pending.Play(); } finally { _drainingAudio = false; }
                if (_audioAcceptedAt != before) break;
            }
            if (_deferredAudio.Count > 0) ScheduleDrain();
        }
    }
    private async Task ReauthorizeDeferredAsync(DeferredAudio pending)
    {
        await Task.Yield(); // No network read or continuation under _gate.
        var allowed = false;
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(3));
        try { allowed = await pending.Revalidate!(timeout.Token).WaitAsync(timeout.Token); } catch { }
        lock (_gate) {
            _audioAuthorizationPending = false;
            try {
                if (allowed && !_disposed && !AchievementPlaying && pending.Generation == _generation() &&
                    pending.AudioRevision == _store.Read().SuppressionRevision &&
                    (pending.Owner is not { } owner || pending.Source is not { } source || pending.Kind is not { } kind ||
                        NotificationOrganizationPolicy.Current(_policies, owner, source, kind, pending.SourceRevision,
                            pending.AdmittedAt, pending.Zone, _time))) {
                    _drainingAudio = true;
                    try { pending.Play(); } finally { _drainingAudio = false; }
                }
            } catch (Exception error) when (error is IOException or InvalidDataException or UnauthorizedAccessException or System.Text.Json.JsonException) { }
            if (!_disposed && _deferredAudio.Count > 0 && !AchievementPlaying) ScheduleDrain();
        }
    }
}
