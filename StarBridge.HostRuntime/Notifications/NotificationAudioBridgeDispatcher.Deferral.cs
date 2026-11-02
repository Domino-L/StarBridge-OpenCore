namespace StarBridge.HostRuntime.Notifications;

public sealed partial class NotificationAudioBridgeDispatcher
{
    private readonly Achievements.AchievementCelebrationActivity _celebration;
    private sealed record DeferredAudio(long Generation, int AudioRevision, StarBridge.NativeBridge.BridgeAccountContext? Owner,
        string? Source, long SourceRevision, Func<bool> Play);
    private readonly Queue<DeferredAudio> _deferredAudio = new();
    private readonly ITimer _audioDrain;
    private bool _drainingAudio;
    private long? _audioAcceptedAt;
    private TimeSpan _audioDuration;
    private bool _deferredPlayback;
    private bool AutomaticThrottled(int seconds) => !_drainingAudio && _lastPlayback is { } last &&
        _time.GetElapsedTime(last) < TimeSpan.FromSeconds(seconds);
    // Caller owns _gate. Return false to existing callers because queued is not yet played.
    private bool Defer(Func<bool> play, StarBridge.NativeBridge.BridgeAccountContext? owner = null, string? source = null)
    {
        var tailPlaying = _deferredPlayback && _audioAcceptedAt is { } at && _time.GetElapsedTime(at) < _audioDuration;
        if (_drainingAudio || !AchievementPlaying && _deferredAudio.Count == 0 && !tailPlaying) return false;
        _deferredAudio.Enqueue(new(_generation(), _store.Read().SuppressionRevision, owner, source,
            owner is not null && source is not null ? _policies.Read(owner).SuppressionRevision(source) : 0, play));
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
            if (_disposed || AchievementPlaying) return;
            if (_audioAcceptedAt is { } at && _time.GetElapsedTime(at) < _audioDuration) { ScheduleDrain(); return; }
            while (_deferredAudio.TryDequeue(out var pending))
            {
                if (pending.Generation != _generation()) continue;
                try {
                    if (pending.AudioRevision != _store.Read().SuppressionRevision ||
                        pending.Owner is { } owner && pending.Source is { } source &&
                        pending.SourceRevision != _policies.Read(owner).SuppressionRevision(source)) continue;
                } catch (Exception error) when (error is System.IO.IOException or UnauthorizedAccessException or System.Text.Json.JsonException) { continue; }
                _drainingAudio = true;
                var before = _audioAcceptedAt;
                try { pending.Play(); } finally { _drainingAudio = false; }
                if (_audioAcceptedAt != before) break;
            }
            if (_deferredAudio.Count > 0) ScheduleDrain();
        }
    }
}
